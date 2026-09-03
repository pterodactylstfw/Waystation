import Foundation

/// Result of an executed command-line process.
public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public nonisolated var isSuccess: Bool {
        exitCode == 0
    }

    public nonisolated var combinedOutput: String {
        if standardOutput.isEmpty { return standardError }
        if standardError.isEmpty { return standardOutput }
        return standardOutput + "\n" + standardError
    }

    public nonisolated init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Isolated asynchronous process execution actor conforming to AD-2.
/// Wraps Foundation `Process` and streams stdout/stderr lines continuously.
public actor ProcessRunner {
    public static let shared = ProcessRunner()

    public init() {}

    /// Executes a process and awaits its completion, optionally streaming stdout and stderr line-by-line.
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

        var outputData = Data()
        var errorData = Data()

        let (stream, continuation) = AsyncStream<String>.makeStream()

        // Background collector for stdout
        let outTask = Task.detached { () -> Data in
            var collected = Data()
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                continuation.yield(line)
                if let lineData = (line + "\n").data(using: .utf8) {
                    collected.append(lineData)
                }
            }
            return collected
        }

        // Background collector for stderr
        let errTask = Task.detached { () -> Data in
            var collected = Data()
            for try await line in errorPipe.fileHandleForReading.bytes.lines {
                continuation.yield("[stderr] " + line)
                if let lineData = (line + "\n").data(using: .utf8) {
                    collected.append(lineData)
                }
            }
            return collected
        }

        // Forward stream lines to onOutputLine if provided
        let consumerTask = Task {
            for await line in stream {
                onOutputLine?(line)
            }
        }

        do {
            try process.run()
        } catch {
            continuation.finish()
            throw error
        }

        process.waitUntilExit()

        outputData = (try? await outTask.value) ?? Data()
        errorData = (try? await errTask.value) ?? Data()
        continuation.finish()
        _ = await consumerTask.value

        let standardOutput = String(data: outputData, encoding: .utf8) ?? ""
        let standardError = String(data: errorData, encoding: .utf8) ?? ""

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: standardOutput.trimmingCharacters(in: .newlines),
            standardError: standardError.trimmingCharacters(in: .newlines)
        )
    }

    /// Convenience runner for launching common system binaries (e.g. /usr/bin/xcrun, /usr/bin/xcode-select).
    @discardableResult
    public func run(
        command: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let executableURL: URL
        if command.hasPrefix("/") {
            executableURL = URL(fileURLWithPath: command)
        } else {
            // Check common paths
            let candidatePaths = [
                "/usr/bin/" + command,
                "/usr/local/bin/" + command,
                "/opt/homebrew/bin/" + command
            ]
            if let found = candidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                executableURL = URL(fileURLWithPath: found)
            } else {
                executableURL = URL(fileURLWithPath: "/usr/bin/" + command)
            }
        }

        return try await run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            onOutputLine: onOutputLine
        )
    }
}
