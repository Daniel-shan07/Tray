import Foundation

public struct PendingFileDrop {
    public private(set) var generation: Int?
    private var urls: [URL] = []
    public init() {}
    public mutating func stage(changeCount: Int, files: () -> [URL]) {
        guard generation != changeCount || urls.isEmpty else { return }
        generation = changeCount
        urls = files()
    }
    public mutating func release(inside: Bool) -> [URL] {
        defer { cancel() }
        return inside ? urls : []
    }
    public mutating func cancel() { generation = nil; urls = [] }
}
