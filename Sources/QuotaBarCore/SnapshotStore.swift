import Foundation

public actor SnapshotStore {
    private let fileManager: FileManager
    private let url: URL

    public init(
        fileManager: FileManager = .default,
        appSupportRoot: URL? = nil
    ) {
        self.fileManager = fileManager
        let root = appSupportRoot
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.url = root
            .appendingPathComponent("QuotaBar", isDirectory: true)
            .appendingPathComponent("snapshots.json")
    }

    public func load() throws -> [ProviderSnapshot] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder.iso8601.decode(SnapshotEnvelope.self, from: data)
        return envelope.snapshots
    }

    public func save(_ snapshots: [ProviderSnapshot]) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(SnapshotEnvelope(snapshots: snapshots))
        try data.write(to: url, options: .atomic)
    }

    public func storageURL() -> URL {
        url
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
