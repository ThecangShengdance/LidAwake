import Foundation

/// pmset 相关：读取与写入系统休眠开关（写入需要 root）。
enum PowerSettings {
    static let pmset = "/usr/bin/pmset"

    /// 读取 `pmset -g` 中的 SleepDisabled（即 `pmset -a disablesleep` 的当前值）。
    /// - Returns: 读不到时返回 nil。
    static func isSleepDisabled() -> Bool? {
        let result = Shell.run(pmset, ["-g"], timeout: 6)
        guard result.ok else { return nil }
        for line in result.stdout.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, fields[0] == "SleepDisabled" else { continue }
            return fields[1].trimmingCharacters(in: .whitespaces) == "1"
        }
        // 系统未展示该键时，按关闭处理。
        return false
    }

    /// 一次性读取全部原始状态，便于调试面板展示。
    static func rawSummary() -> String {
        let result = Shell.run(pmset, ["-g"], timeout: 6)
        return result.ok ? result.stdout : "pmset -g 执行失败：\(result.message)"
    }
}

enum PrivilegedError: LocalizedError {
    case cancelled
    case notPermitted
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "已取消管理员授权"
        case .notPermitted: return "没有权限修改系统休眠设置"
        case .failed(let detail): return detail.isEmpty ? "系统拒绝了该设置" : detail
        }
    }
}

/// 需要 root 的操作统一走这里。
///
/// 两条通道：
/// 1. 免密通道：`sudo -n`，仅在用户安装过受限 sudoers 规则（仅允许 `pmset -a disablesleep 0|1`）时可用；
/// 2. 授权通道：`osascript ... with administrator privileges`，每次弹系统管理员密码框（支持触控 ID）。
enum Privileged {
    static let sudo = "/usr/bin/sudo"
    static let osascript = "/usr/bin/osascript"
    static let sudoersPath = "/etc/sudoers.d/lidawake"

    /// 只放行两条确定的命令，不给整机 root 权限。
    static var sudoersRule: String {
        let user = NSUserName()
        return "\(user) ALL=(root) NOPASSWD: \(PowerSettings.pmset) -a disablesleep 0, \(PowerSettings.pmset) -a disablesleep 1"
    }

    // MARK: - 读取免密状态

    /// 免密规则是否可用：用当前值做一次“原地写入”，成功即代表授权已生效。
    static func passwordlessAvailable(currentlyDisabled: Bool) -> Bool {
        silentArgs(disabled: currentlyDisabled).map { $0.ok } ?? false
    }

    private static func silentArgs(disabled: Bool) -> CommandResult? {
        Shell.run(sudo, ["-n", PowerSettings.pmset, "-a", "disablesleep", disabled ? "1" : "0"], timeout: 10)
    }

    // MARK: - 设置休眠开关

    static func setSleepDisabled(_ disabled: Bool) throws {
        let args = ["-a", "disablesleep", disabled ? "1" : "0"]

        if Shell.run(sudo, ["-n", PowerSettings.pmset] + args, timeout: 10).ok { return }

        let command = ([PowerSettings.pmset] + args).joined(separator: " ")
        let source = "do shell script \(AppleScript.literal(command)) with administrator privileges"
        let result = Shell.run(osascript, ["-e", source], timeout: 180)

        if result.ok { return }
        if result.message.lowercased().contains("user canceled") || result.message.contains("-128") {
            throw PrivilegedError.cancelled
        }
        if result.message.contains("not allowed to") || result.message.contains("权限") {
            throw PrivilegedError.notPermitted
        }
        throw PrivilegedError.failed(friendlyMessage(result, fallback: "写入 pmset 设置失败"))
    }

    // MARK: - 安装 / 移除免密规则

    /// 安装脚本：先写临时文件 -> 校验 -> 原子替换，避免写坏 sudoers 导致 sudo 整体失效。
    static var installScript: String {
        """
        set -e
        umask 022
        tmp=/etc/sudoers.d/.lidawake.tmp.$$
        trap 'rm -f "$tmp"' EXIT
        cat > "$tmp" <<'LIDawakeRule'
        \(sudoersRule)
        LIDawakeRule
        chown root:wheel "$tmp"
        chmod 0440 "$tmp"
        /usr/sbin/visudo -cf "$tmp" >/dev/null
        mv -f "$tmp" /etc/sudoers.d/lidawake
        """
    }

    static func installPasswordlessRule() throws {
        try runAdmin(installScript, fallback: "安装免密规则失败")
    }

    static func removePasswordlessRule() throws {
        let script = """
        set -e
        rm -f /etc/sudoers.d/lidawake
        """
        try runAdmin(script, fallback: "移除免密规则失败")
    }

    private static func runAdmin(_ script: String, fallback: String) throws {
        let source = "do shell script \(AppleScript.literal(script)) with administrator privileges"
        let result = Shell.run(osascript, ["-e", source], timeout: 180)
        if result.ok { return }
        if result.message.lowercased().contains("user canceled") || result.message.contains("-128") {
            throw PrivilegedError.cancelled
        }
        throw PrivilegedError.failed(friendlyMessage(result, fallback: fallback))
    }

    // MARK: - 错误文案

    private static func friendlyMessage(_ result: CommandResult, fallback: String) -> String {
        if result.timedOut { return "等待管理员授权超时" }
        let raw = result.message
        if let range = raw.range(of: "execution error:") {
            let detail = raw[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? fallback : detail
        }
        return raw.isEmpty ? fallback : raw
    }
}

/// AppleScript 字符串字面量转义（`do shell script` 需要两层转义）。
enum AppleScript {
    static func literal(_ string: String) -> String {
        var escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // AppleScript 源码里字面换行合法，但用 \n 会原样传给 shell，故保留真实换行。
        escaped = escaped.replacingOccurrences(of: "\r\n", with: "\n")
        return "\"\(escaped)\""
    }
}
