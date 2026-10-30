import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct CommandResult {
    let status: Int32
    let output: Data
    let error: Data

    var errorText: String {
        String(decoding: error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

protocol CommandRunning {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) throws -> CommandResult
}

enum BackendError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

struct ProcessRunner: CommandRunning {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
        } catch {
            throw BackendError.message("Could not launch \(executable.lastPathComponent): \(error.localizedDescription)")
        }

        // Drain both pipes while the process runs; a full stderr pipe must not
        // deadlock a large paginated GraphQL response on stdout.
        let output = CapturedData()
        let error = CapturedData()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            output.store(stdout.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            error.store(stderr.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        var cancelled = false
        var timedOut = false
        while terminated.wait(timeout: .now() + 0.1) == .timedOut {
            cancelled = Task<Never, Never>.isCancelled
            timedOut = Date() >= deadline
            if cancelled || timedOut {
                if process.isRunning { process.terminate() }
                if terminated.wait(timeout: .now() + 1) == .timedOut {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    terminated.wait()
                }
                break
            }
        }
        readers.wait()
        if cancelled { throw CancellationError() }
        if timedOut {
            throw BackendError.message("\(executable.lastPathComponent) timed out after \(Int(timeout)) seconds. Check your network connection and try again.")
        }
        return CommandResult(status: process.terminationStatus, output: output.value, error: error.value)
    }

    private final class CapturedData: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ data: Data) {
            lock.lock()
            self.data = data
            lock.unlock()
        }

        var value: Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }
}
