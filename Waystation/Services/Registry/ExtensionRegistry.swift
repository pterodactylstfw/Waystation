import Foundation

/// Thread-safe registry for persisting and querying installed extensions.
/// Conforms strictly to AD-5: atomic JSON registry at `~/Library/Application Support/Waystation/registry.json`.
public actor ExtensionRegistry {
    public static let shared = ExtensionRegistry()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// `~/Library/Application Support/Waystation/`
    public var appSupportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Waystation", isDirectory: true)
    }

    /// `~/Library/Application Support/Waystation/registry.json`
    public var registryFileURL: URL {
        appSupportDirectory.appendingPathComponent("registry.json")
    }

    /// `~/Library/Application Support/Waystation/Extensions/`
    public var extensionsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Extensions", isDirectory: true)
    }

    /// Loads all installed extensions from `registry.json` via detached task to prevent actor starvation.
    public func loadAll() async throws -> [InstalledExtension] {
        let fileURL = registryFileURL
        let decoder = self.decoder
        return try await Task.detached {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return []
            }

            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                return []
            }

            return try decoder.decode([InstalledExtension].self, from: data)
        }.value
    }

    /// Registers a new extension or updates an existing one, saving atomically.
    public func register(_ ext: InstalledExtension) async throws {
        var all = try await loadAll()
        if let idx = all.firstIndex(where: { $0.id == ext.id }) {
            all[idx] = ext
        } else {
            all.append(ext)
        }
        try await saveAll(all)
    }

    /// Updates an existing extension entry.
    public func update(_ ext: InstalledExtension) async throws {
        var all = try await loadAll()
        guard let idx = all.firstIndex(where: { $0.id == ext.id }) else {
            throw WaystationError.registryError(reason: "Extensia cu ID-ul '\(ext.id)' nu există în registru.")
        }
        all[idx] = ext
        try await saveAll(all)
    }

    /// Removes an extension entry by its ID.
    public func remove(id: String) async throws {
        var all = try await loadAll()
        all.removeAll { $0.id == id }
        try await saveAll(all)
    }

    /// Finds a registered extension by ID.
    public func find(id: String) async throws -> InstalledExtension? {
        let all = try await loadAll()
        return all.first { $0.id == id }
    }

    /// Atomic persistence conforming strictly to AD-5.
    /// Writes to a temporary file, flushes to disk, and replaces destination atomically in detached task.
    private func saveAll(_ extensions: [InstalledExtension]) async throws {
        let appDir = appSupportDirectory
        let extDir = extensionsDirectory
        let regURL = registryFileURL
        let encoder = self.encoder

        try await Task.detached {
            let fm = FileManager.default
            try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: extDir, withIntermediateDirectories: true)

            let data = try encoder.encode(extensions)

            let tempFile = appDir.appendingPathComponent("registry.\(UUID().uuidString).tmp")
            try data.write(to: tempFile, options: .atomic)

            if fm.fileExists(atPath: regURL.path) {
                _ = try fm.replaceItemAt(regURL, withItemAt: tempFile)
            } else {
                try fm.moveItem(at: tempFile, to: regURL)
            }
        }.value
    }
}
