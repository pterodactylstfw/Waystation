import Foundation

/// A single timestamped log entry emitted during CLI processes.
public struct LogEntry: Identifiable, Sendable, Equatable {
    public nonisolated let id: UUID
    public let timestamp: Date
    public let text: String
    public let isError: Bool

    public nonisolated var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    public nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        isError: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.isError = isError
    }
}

/// Thread-safe ring buffer storing up to `capacity` lines (max 1,000 as defined in AD-1 / ARCHITECTURE-SPINE.md).
/// Prevents unbounded memory growth during long-running builds.
public actor LogBuffer {
    public static let shared = LogBuffer()

    private let capacity: Int
    private var entries: [LogEntry] = []

    public init(capacity: Int = 1000) {
        self.capacity = capacity
    }

    /// Appends a new log line, evicting the oldest line if capacity is exceeded.
    public func append(text: String, isError: Bool = false) -> LogEntry {
        let entry = LogEntry(text: text, isError: isError)
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        return entry
    }

    /// Returns a copy of all current entries in chronological order.
    public func allEntries() -> [LogEntry] {
        entries
    }

    /// Returns all log entries formatted as plain text for clipboard export.
    public func plainText() -> String {
        entries.map { "[\($0.formattedTime)] \($0.text)" }.joined(separator: "\n")
    }

    /// Clears the log buffer.
    public func clear() {
        entries.removeAll()
    }
}
