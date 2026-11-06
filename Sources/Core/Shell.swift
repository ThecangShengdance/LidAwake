import Foundation

/// 一次子进程调用的结果。
struct CommandResult {
    var status: Int32
    var stdout: String
    var stderr: String
    var timedOut = false
    var launchError: String?

    var ok: Bool { launchError == nil && !timedOut && status == 0 }

    /// 合并后的输出，便于匹配错误文案。
    var message: String {
        [launchError, stderr, stdout]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// 极简的子进程执行器（带超时、不阻塞主线程以外的地方）。
enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 20) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: "", launchError: error.localizedDescription)
        }

        // 关键：父进程关掉写端，子进程退出后 read 才能读到 EOF。
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
        }

        var outData = Data()
        var errData = Data()
        outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            timedOut: timedOut
        )
    }
}
