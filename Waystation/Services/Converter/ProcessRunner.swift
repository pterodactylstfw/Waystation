import Foundation

/// Represents the output and termination status of a completed process.
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public var isSuccess: Bool {
        exitCode == 0
    }

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Thread-safe actor coordinating subprocess execution conforming to AD-2.
/// Eliminates deadlocks by draining pipe buffers asynchronously before awaiting termination.
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

        // Continuous streaming via readabilityHandler to prevent any pipe buffer overflow (64KB deadlock)
        let stdoutCollector = SafeDataCollector()
        let stderrCollector = SafeDataCollector()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stdoutCollector.append(chunk)

            if let onOutputLine = onOutputLine, let str = String(data: chunk, encoding: .utf8) {
                let lines = str.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    onOutputLine(line)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrCollector.append(chunk)

            if let onOutputLine = onOutputLine, let str = String(data: chunk, encoding: .utf8) {
                let lines = str.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    onOutputLine(line)
                }
            }
        }

        // Cooperative asynchronous wait on process termination
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        // Clean up readability handlers
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        // Drain any remaining bytes
        let remainingOut = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingOut.isEmpty {
            stdoutCollector.append(remainingOut)
        }

        let remainingErr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingErr.isEmpty {
            stderrCollector.append(remainingErr)
        }

        let standardOutput = String(data: stdoutCollector.data, encoding: .utf8) ?? ""
        let standardError = String(data: stderrCollector.data, encoding: .utf8) ?? ""

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: standardOutput.trimmingCharacters(in: .newlines),
            standardError: standardError.trimmingCharacters(in: .newlines)
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

/// Thread-safe helper to collect data from readability handler blocks.
private final class SafeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var internalData = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return internalData
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        internalData.append(chunk)
    }
}
