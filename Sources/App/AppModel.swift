import Foundation
import Combine
import ServiceManagement

/// 应用状态与系统操作的门面。
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: - 展示状态

    @Published private(set) var isEnabled = false
    private(set) var lidClosed: Bool?
    @Published private(set) var power = PowerSnapshot()
    @Published private(set) var passwordless = false
    @Published private(set) var busy = false
    private(set) var errorText: String?
    private(set) var enabledAt: Date?
    @Published private(set) var lastUpdated = Date()
    @Published private(set) var launchAtLogin = false
    private(set) var refreshError: String?

    /// 退出应用时是否自动恢复系统默认休眠（默认开启，避免忘关后整夜耗电）。
    @Published var restoreOnQuit: Bool {
        didSet { defaults.set(restoreOnQuit, forKey: Keys.restoreOnQuit) }
    }

    // MARK: - 内部

    private enum Keys {
        static let restoreOnQuit = "restoreOnQuit"
        static let enabledAt = "enabledAt"
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var actionInFlight = false
    private var lastPasswordlessCheck = Date.distantPast
    private var lastLoginItemSync = Date.distantPast
    private var isPreviewMode = false

    private init() {
        restoreOnQuit = defaults.object(forKey: Keys.restoreOnQuit) as? Bool ?? true
        if let stored = defaults.object(forKey: Keys.enabledAt) as? Date {
            enabledAt = stored
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
        refresh()
        startTimer()
    }

    // MARK: - 定时刷新

    private func startTimer() {
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !actionInFlight, !isPreviewMode else { return }
        lastUpdated = Date()

        if let value = PowerSettings.isSleepDisabled() {
            refreshError = nil
            apply(isEnabled: value)
        } else {
            refreshError = "无法读取系统休眠设置"
        }

        lidClosed = SystemStatus.isLidClosed()
        power = SystemStatus.power()

        if Date().timeIntervalSince(lastPasswordlessCheck) > 30 {
            lastPasswordlessCheck = Date()
            passwordless = Privileged.passwordlessAvailable(currentlyDisabled: isEnabled)
        }

        if Date().timeIntervalSince(lastLoginItemSync) > 30 {
            lastLoginItemSync = Date()
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func apply(isEnabled value: Bool) {
        guard value != isEnabled else { return }
        isEnabled = value
        if value {
            if enabledAt == nil {
                enabledAt = defaults.object(forKey: Keys.enabledAt) as? Date ?? Date()
            }
        } else {
            enabledAt = nil
            defaults.removeObject(forKey: Keys.enabledAt)
        }
    }

    // MARK: - 主开关

    func setEnabled(_ newValue: Bool) {
        guard !actionInFlight else { return }
        errorText = nil
        actionInFlight = true
        busy = true

        Task { @MainActor in
            defer {
                self.actionInFlight = false
                self.busy = false
                self.lastPasswordlessCheck = .distantPast
                self.refresh()
            }
            do {
                try await Self.performOffMain { try Privileged.setSleepDisabled(newValue) }
                try? await Task.sleep(for: .milliseconds(350))

                guard let actual = PowerSettings.isSleepDisabled() else {
                    throw PrivilegedError.failed("写入后无法读取系统状态，请手动执行 pmset -g 确认")
                }
                apply(isEnabled: actual)
                if actual != newValue {
                    throw PrivilegedError.failed(newValue ? "系统没有接受「合盖不休眠」，请重试" : "系统没有恢复默认休眠，请重试")
                }
                if newValue, enabledAt == nil {
                    enabledAt = Date()
                    defaults.set(enabledAt, forKey: Keys.enabledAt)
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - 免密授权

    func installPasswordless() {
        guard !actionInFlight else { return }
        errorText = nil
        actionInFlight = true
        busy = true

        Task { @MainActor in
            defer {
                self.actionInFlight = false
                self.busy = false
                self.lastPasswordlessCheck = .distantPast
                self.refresh()
            }
            do {
                try await Self.performOffMain { try Privileged.installPasswordlessRule() }
                try? await Task.sleep(for: .milliseconds(200))
                passwordless = Privileged.passwordlessAvailable(currentlyDisabled: isEnabled)
                if !passwordless { throw PrivilegedError.failed("免密规则已写入但未生效，请检查 /etc/sudoers.d/lidawake") }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    func removePasswordless() {
        guard !actionInFlight else { return }
        errorText = nil
        actionInFlight = true
        busy = true

        Task { @MainActor in
            defer {
                self.actionInFlight = false
                self.busy = false
                self.lastPasswordlessCheck = .distantPast
                self.refresh()
            }
            do {
                try await Self.performOffMain { try Privileged.removePasswordlessRule() }
                try? await Task.sleep(for: .milliseconds(200))
                passwordless = Privileged.passwordlessAvailable(currentlyDisabled: isEnabled)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - 登录启动

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            if launchAtLogin != enabled {
                errorText = "登录项未生效：请把 App 放到「应用程序」文件夹后再试"
            }
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            errorText = "登录项设置失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 退出

    /// 退出前静默恢复（仅在免密规则生效时成功）。
    func disableSilently() -> Bool {
        Shell.run(Privileged.sudo, ["-n", PowerSettings.pmset, "-a", "disablesleep", "0"], timeout: 10).ok
    }

    func disableWithPrompt() -> Bool {
        do {
            try Privileged.setSleepDisabled(false)
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func clearError() {
        errorText = nil
    }

    /// 仅供 `--snapshot` 使用：写入一份展示状态并暫停自动刷新。
    func loadPreviewState(enabled: Bool, lidClosed: Bool?, power: PowerSnapshot, passwordless: Bool, errorText: String?) {
        isPreviewMode = true
        self.isEnabled = enabled
        self.lidClosed = lidClosed
        self.power = power
        self.passwordless = passwordless
        self.errorText = errorText
        self.enabledAt = enabled ? Date().addingTimeInterval(-3725) : nil
        self.lastUpdated = Date()
    }

    // MARK: - 展示辅助

    /// 已持续运行的时长文案。
    var durationText: String {
        guard isEnabled, let enabledAt else { return "—" }
        let seconds = max(0, Int(lastUpdated.timeIntervalSince(enabledAt)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }

    var lidText: String {
        switch lidClosed {
        case true?: return "已合上"
        case false?: return "打开"
        case nil: return "未知"
        }
    }

    var statusTitle: String {
        isEnabled ? "合盖后保持运行" : "合盖即进入睡眠"
    }

    var statusDetail: String {
        isEnabled ? "已禁用系统合盖休眠" : "系统默认 · 合盖即睡眠"
    }

    // MARK: - 工具

    private static func performOffMain(_ work: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
