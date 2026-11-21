import Foundation

public struct TrayItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let addedAt: Date
    public let isDirectory: Bool
    public let byteCount: Int64
    public let sourcePath: String
    public var relativePath: String { "Files/\(id.uuidString)/\(name)" }
}

/// Every entry owns a copy. The original URL is never a deletion target.
public final class TrayStorage: @unchecked Sendable {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) throws {
        self.root = root.standardizedFileURL
        try fm.createDirectory(at: root.appendingPathComponent("Files"), withIntermediateDirectories: true)
    }
    public func url(for item: TrayItem) -> URL { root.appendingPathComponent(item.relativePath) }
    public func load() throws -> [TrayItem] {
        let manifest = root.appendingPathComponent("items.json")
        guard fm.fileExists(atPath: manifest.path) else { return [] }
        let items = try JSONDecoder().decode([TrayItem].self, from: Data(contentsOf: manifest))
        // A damaged manifest cannot redirect deletion or exports outside our storage.
        guard items.allSatisfy({ !$0.name.isEmpty && $0.name != "." && $0.name != ".." && !$0.name.contains("/") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return items
    }
    public func save(_ items: [TrayItem]) throws {
        try JSONEncoder().encode(items).write(to: root.appendingPathComponent("items.json"), options: .atomic)
    }
    public func importFile(_ source: URL, existing: [TrayItem]) throws -> TrayItem? {
        let source = source.standardizedFileURL
        guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        // Do not copy the tray into itself or recursively import a parent of it.
        let rootPath = root.resolvingSymlinksInPath().path + "/"
        let sourcePath = source.resolvingSymlinksInPath().path + "/"
        guard !sourcePath.hasPrefix(rootPath), !rootPath.hasPrefix(sourcePath) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        if existing.contains(where: { $0.sourcePath == source.path && fm.fileExists(atPath: url(for: $0).path) }) { return nil }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let item = TrayItem(id: UUID(), name: source.lastPathComponent, addedAt: Date(),
                            isDirectory: values.isDirectory ?? false,
                            byteCount: Int64(values.fileSize ?? 0), sourcePath: source.path)
        let directory = url(for: item).deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        do { try fm.copyItem(at: source, to: url(for: item)) }
        catch { try? fm.removeItem(at: directory); throw error }
        return item
    }
    /// Persist removal first; if cleanup fails, the detached copy remains recoverable in Files.
    public func remove(_ ids: Set<UUID>, from items: [TrayItem]) throws -> [TrayItem] {
        let remaining = items.filter { !ids.contains($0.id) }
        try save(remaining)
        for item in items where ids.contains(item.id) {
            try? fm.removeItem(at: url(for: item).deletingLastPathComponent())
        }
        return remaining
    }
}
