import Foundation

/// Represents the output and termination status of a completed process.
public struct ProcessResult: Sendable {
    public nonisolated let exitCode: Int32
    public nonisolated let standardOutput: String
    public nonisolated let standardError: String

    public nonisolated var isSuccess: Bool {
        exitCode == 0
    }

    public nonisolated init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Thread-safe actor coordinating subprocess execution conforming to AD-2.
/// Streams process stdout and stderr using AsyncSequence (bytes.lines) to eliminate buffer boundary UTF-8 decoding loss.
public actor ProcessRunner {
    public static let shared = ProcessRunner()

    public init() {}

    /// Executes a process and awaits its completion, streaming stdout and stderr line-by-line in real time.
    @discardableResult
    public func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        if let environment = environment {
            var currentEnv = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                currentEnv[key] = value
            }
            process.environment = currentEnv
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let outHandle = outputPipe.fileHandleForReading
        let errHandle = errorPipe.fileHandleForReading

        // Consume both stdout and stderr concurrently via AsyncSequence bytes.lines
        // This guarantees complete lines and prevents UTF-8 multi-byte chunk truncation
        let (stdout, stderr) = await withTaskGroup(of: (isError: Bool, text: String).self) { group in
            group.addTask {
                var collected: [String] = []
                do {
                    for try await line in outHandle.bytes.lines {
                        collected.append(line)
                        onOutputLine?(line)
                    }
                } catch {}
                return (false, collected.joined(separator: "\n"))
            }

            group.addTask {
                var collected: [String] = []
                do {
                    for try await line in errHandle.bytes.lines {
                        collected.append(line)
                        onOutputLine?(line)
                    }
                } catch {}
                return (true, collected.joined(separator: "\n"))
            }

            var outStr = ""
            var errStr = ""
            for await result in group {
                if result.isError {
                    errStr = result.text
                } else {
                    outStr = result.text
                }
            }
            return (outStr, errStr)
        }

        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: stdout.trimmingCharacters(in: .newlines),
            standardError: stderr.trimmingCharacters(in: .newlines)
        )
    }

    /// Convenience overload using command path string.
    @discardableResult
    public func run(
        command: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let executableURL = URL(fileURLWithPath: command)
        return try await run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            onOutputLine: onOutputLine
        )
    }
}
