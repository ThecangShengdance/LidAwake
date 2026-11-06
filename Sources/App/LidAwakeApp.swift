import AppKit
import SwiftUI

@main
struct LidAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarIcon(isEnabled: model.isEnabled)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏图标：开启时为笔记本，关闭时为「禁止合盖」样式。
struct MenuBarIcon: View {
    let isEnabled: Bool

    var body: some View {
        Image(systemName: isEnabled ? "laptopcomputer" : "laptopcomputer.slash")
            .accessibilityLabel(isEnabled ? "合盖不休眠：已开启" : "合盖不休眠：已关闭")
            .help(isEnabled ? "合盖不休眠已开启" : "合盖不休眠已关闭")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLineSupport.runIfRequested() {
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)

        // 自检：确认 MenuBarExtra 真的创建了状态栏 item。
        if CommandLine.arguments.contains("--status") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let windows = NSApp.windows
                for window in windows {
                    print("window: \(type(of: window)) level=\(window.level.rawValue) frame=\(window.frame) visible=\(window.isVisible)")
                }
                let hasStatusItem = windows.contains { $0.level.rawValue == Int(CGWindowLevelForKey(.statusWindow)) }
                print("statusItemWindow=\(hasStatusItem) windowCount=\(windows.count)")
                exit(0)
            }
        }
    }

    /// 退出前处理「恢复默认休眠」，避免 disablesleep=1 被留在系统里。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.restoreOnQuit, model.isEnabled else { return .terminateNow }

        if model.disableSilently() { return .terminateNow }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "退出前恢复系统默认休眠？"
        alert.informativeText = "「合盖不休眠」仍处于开启状态。它会一直生效到下次手动关闭，可能导致机身发热、电池耗尽。"
        alert.addButton(withTitle: "恢复并退出")
        alert.addButton(withTitle: "保持开启退出")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return model.disableWithPrompt() ? .terminateNow : .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
