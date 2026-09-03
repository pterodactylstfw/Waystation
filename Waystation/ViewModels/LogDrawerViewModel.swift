import SwiftUI

/// ViewModel driving the live terminal output log drawer.
/// Conforms to AD-1, AD-2 and Story 1.4 acceptance criteria.
@Observable
@MainActor
public final class LogDrawerViewModel {
    public static let shared = LogDrawerViewModel()

    public var isExpanded: Bool = false
    public var isStreaming: Bool = false
    public var copiedToast: Bool = false
    public var entries: [LogEntry] = []
    public var autoScroll: Bool = true

    private let logBuffer: LogBuffer

    public init(logBuffer: LogBuffer = .shared) {
        self.logBuffer = logBuffer
    }

    /// Appends a raw log line, parsing stderr prefixes and keeping the UI reactive.
    public func append(line: String) {
        let isError = line.hasPrefix("[stderr]")
        let cleanText = isError ? String(line.dropFirst("[stderr] ".count)) : line

        Task {
            let entry = await logBuffer.append(text: cleanText, isError: isError)
            self.entries.append(entry)
            if self.entries.count > 1000 {
                self.entries.removeFirst(self.entries.count - 1000)
            }
        }
    }

    /// Copies all buffered log entries to the macOS pasteboard.
    public func copyLogs() {
        Task {
            let text = await logBuffer.plainText()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

            withAnimation {
                self.copiedToast = true
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                self.copiedToast = false
            }
        }
    }

    /// Clears both the in-memory ring buffer and the UI view lines.
    public func clear() {
        entries.removeAll()
        Task {
            await logBuffer.clear()
        }
    }

    public func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}
