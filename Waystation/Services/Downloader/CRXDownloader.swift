import Foundation

/// Service responsible for downloading .crx extension binaries directly from Google's update API.
/// Conforms to Story 2.3 acceptance criteria and AD-1/AD-8 architectural invariants.
public actor CRXDownloader {
    public static let shared = CRXDownloader()

    private let fileManager = FileManager.default
    private let urlSession: URLSession

    public init(session: URLSession = .shared) {
        self.urlSession = session
    }

    /// Computes the cache destination directory for CRX downloads:
    /// `~/Library/Caches/org.waystation.app/downloads/`
    public var downloadsDirectory: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches
            .appendingPathComponent("org.waystation.app")
            .appendingPathComponent("downloads")
    }

    /// Downloads a CRX binary for the specified 32-character Chrome extension ID.
    /// Uses streaming disk download (URLSession.download) to eliminate memory spikes on large extensions.
    ///
    /// - Parameters:
    ///   - extensionId: The 32-character lowercase extension identifier.
    ///   - onProgress: Optional callback reporting download progress from 0.0 to 1.0.
    /// - Returns: File URL to the downloaded `.crx` file.
    public func downloadCRX(
        extensionId: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        // Validate 32-character extension ID format
        let idRegex = try NSRegularExpression(pattern: "^[a-z]{32}$")
        let range = NSRange(location: 0, length: extensionId.utf16.count)
        guard idRegex.firstMatch(in: extensionId, options: [], range: range) != nil else {
            throw WaystationError.downloadFailed(reason: "ID extensie invalid: \(extensionId)")
        }

        // Google Update API CRX endpoint URL
        let urlString = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=130.0.0.0&acceptformat=crx2,crx3&x=id%3D\(extensionId)%26uc"
        guard let endpointURL = URL(string: urlString) else {
            throw WaystationError.downloadFailed(reason: "URL invalid pentru endpoint-ul de descărcare.")
        }

        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        let destinationURL = downloadsDirectory.appendingPathComponent("\(extensionId).crx")

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        // Download directly to disk via URLSession.download to avoid memory spikes
        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let (tempDownloadedURL, response) = try await urlSession.download(for: request, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse else {
            try? fileManager.removeItem(at: tempDownloadedURL)
            throw WaystationError.downloadFailed(reason: "Răspuns server invalid.")
        }

        guard httpResponse.statusCode == 200 else {
            try? fileManager.removeItem(at: tempDownloadedURL)
            throw WaystationError.downloadFailed(reason: "Serverul a returnat codul HTTP \(httpResponse.statusCode).")
        }

        // Validate header signature and move item off the cooperative thread pool
        try await Task.detached {
            let handle = try FileHandle(forReadingFrom: tempDownloadedURL)
            let headerData = try handle.read(upToCount: 4) ?? Data()
            try handle.close()

            guard headerData.count >= 4 else {
                try? FileManager.default.removeItem(at: tempDownloadedURL)
                throw WaystationError.downloadFailed(reason: "Pachetul descărcat este gol sau corupt.")
            }

            // Validate that received payload has CRX magic "Cr24" or standard ZIP "PK\x03\x04"
            let isCRX = headerData.prefix(4) == Data([0x43, 0x72, 0x32, 0x34])
            let isZIP = headerData.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])

            guard isCRX || isZIP else {
                try? FileManager.default.removeItem(at: tempDownloadedURL)
                throw WaystationError.downloadFailed(reason: "Datele primite nu sunt un pachet de extensie valid (CRX/ZIP).")
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempDownloadedURL, to: destinationURL)
        }.value

        onProgress?(1.0)
        return destinationURL
    }
}

/// Helper delegate to report granular progress during URLSession.download.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (@Sendable (Double) -> Void)?

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            onProgress?(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onProgress?(1.0)
    }
}
