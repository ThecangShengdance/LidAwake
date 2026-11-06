import AppKit
import SwiftUI

/// 命令行辅助入口：`--probe` 输出状态，`--snapshot` 渲染面板截图。
/// 供自动化验证使用，正常双击启动不会触发。
enum CommandLineSupport {
    @MainActor
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--probe") {
            printProbe()
            return true
        }
        if args.contains("--print-script") {
            print("-- sudoers 规则 --")
            print(Privileged.sudoersRule)
            print("-- 安装脚本 --")
            print(Privileged.installScript)
            print("-- AppleScript 源码 --")
            print("do shell script \(AppleScript.literal(Privileged.installScript)) with administrator privileges")
            return true
        }
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            runSnapshot(path: args[index + 1], args: args)
            return true
        }
        return false
    }

    // MARK: - probe

    @MainActor
    private static func printProbe() {
        let model = AppModel.shared
        model.refresh()
        let sleepDisabled = PowerSettings.isSleepDisabled().map(String.init) ?? "unknown"
        let lid = SystemStatus.isLidClosed().map { $0 ? "closed" : "open" } ?? "unknown"
        let power = SystemStatus.power()

        print("sleepDisabled=\(sleepDisabled)")
        print("lid=\(lid)")
        print("onAC=\(power.onAC)")
        print("battery=\(power.percent.map(String.init) ?? "none")")
        print("charging=\(power.charging)")
        print("passwordless=\(model.passwordless ? 1 : 0)")
        print("restoreOnQuit=\(model.restoreOnQuit ? 1 : 0)")
        print("loginItem=\(model.launchAtLogin ? 1 : 0)")
        print("bundlePath=\(Bundle.main.bundlePath)")
        print("-- pmset -g --")
        print(PowerSettings.rawSummary())
    }

    // MARK: - snapshot

    @MainActor
    private static func runSnapshot(path: String, args: [String]) {
        let model = AppModel.shared
        let state = value(after: "--state", in: args) ?? "on"
        let onBattery = args.contains("--battery")
        let withError = args.contains("--error")

        model.loadPreviewState(
            enabled: state != "off",
            lidClosed: state != "off",
            power: onBattery
                ? PowerSnapshot(onAC: false, hasBattery: true, percent: 64, charging: false)
                : PowerSnapshot(onAC: true, hasBattery: true, percent: 92, charging: false),
            passwordless: !args.contains("--prompt"),
            errorText: withError ? "已取消管理员授权" : nil
        )

        let content = PanelView(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        let renderer = ImageRenderer(content: content.padding(20).background(Color.clear))
        renderer.scale = 2
        guard
            let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("snapshot: 渲染失败\n".utf8))
            return
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("snapshot written: \(path)")
        } catch {
            FileHandle.standardError.write(Data("snapshot: 写入失败 \(error.localizedDescription)\n".utf8))
        }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
