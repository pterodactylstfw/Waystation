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

    /// Loads all installed extensions from `registry.json`.
    public func loadAll() throws -> [InstalledExtension] {
        guard fileManager.fileExists(atPath: registryFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: registryFileURL)
        guard !data.isEmpty else {
            return []
        }

        return try decoder.decode([InstalledExtension].self, from: data)
    }

    /// Registers a new extension or updates an existing one, saving atomically.
    public func register(_ ext: InstalledExtension) throws {
        var all = try loadAll()
        if let idx = all.firstIndex(where: { $0.id == ext.id }) {
            all[idx] = ext
        } else {
            all.append(ext)
        }
        try saveAll(all)
    }

    /// Updates an existing extension entry.
    public func update(_ ext: InstalledExtension) throws {
        var all = try loadAll()
        guard let idx = all.firstIndex(where: { $0.id == ext.id }) else {
            throw WaystationError.registryError(reason: "Extensia cu ID-ul '\(ext.id)' nu există în registru.")
        }
        all[idx] = ext
        try saveAll(all)
    }

    /// Removes an extension entry by its ID.
    public func remove(id: String) throws {
        var all = try loadAll()
        all.removeAll { $0.id == id }
        try saveAll(all)
    }

    /// Finds a registered extension by ID.
    public func find(id: String) throws -> InstalledExtension? {
        let all = try loadAll()
        return all.first { $0.id == id }
    }

    /// Atomic persistence conforming strictly to AD-5.
    /// Writes to a temporary file, flushes to disk, and replaces destination atomically.
    private func saveAll(_ extensions: [InstalledExtension]) throws {
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)

        let data = try encoder.encode(extensions)

        let tempFile = appSupportDirectory.appendingPathComponent("registry.\(UUID().uuidString).tmp")
        try data.write(to: tempFile, options: .atomic)

        if fileManager.fileExists(atPath: registryFileURL.path) {
            _ = try fileManager.replaceItemAt(registryFileURL, withItemAt: tempFile)
        } else {
            try fileManager.moveItem(at: tempFile, to: registryFileURL)
        }
    }
}
