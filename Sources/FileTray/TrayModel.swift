import AppKit
import SwiftUI
import TrayCore

@MainActor final class TrayModel: ObservableObject {
    @Published var items: [TrayItem] = []
    @Published var importing = false
    @Published var revealProgress: Double = 0
    @Published var revealAnchorX: CGFloat = TrayListLayout.width / 2
    @Published var dragging = false
    @Published var pointer: CGPoint?
    @Published var message: String?
    @Published var search = ""
    @Published var pinned = false
    @Published var selected: UUID?
    private let storage: TrayStorage
    private let queue = DispatchQueue(label: "local.filetray.storage", qos: .userInitiated)
    private var pendingURLs: [URL] = []
    @Published var confirmClear = false
    var trackingTrayMenu = false
    var didChange: (() -> Void)?
    var preview: (([URL], Int) -> Void)?
    var visibleItems: [TrayItem] {
        items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    init() throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FileTray", isDirectory: true)
        storage = try TrayStorage(root: root)
        items = try storage.load()
    }
    func url(_ item: TrayItem) -> URL { storage.url(for: item) }
    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if importing { pendingURLs.append(contentsOf: urls); return }
        importing = true
        message = nil
        let original = items
        let storage = storage
        queue.async {
            var updated = original
            var failures: [String] = []
            var duplicates = 0
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    if let item = try storage.importFile(url, existing: updated) {
                        // Commit each imported copy so a later error cannot lose successful entries.
                        do { try storage.save([item] + updated); updated.insert(item, at: 0) }
                        catch {
                            try? FileManager.default.removeItem(at: storage.url(for: item).deletingLastPathComponent())
                            throw error
                        }
                    } else { duplicates += 1 }
                } catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
            let result = updated
            let notice = !failures.isEmpty ? failures.joined(separator: "\n") :
                (duplicates > 0 ? "已跳过 \(duplicates) 个重复文件" : nil)
            DispatchQueue.main.async {
                self.items = result
                self.importing = false
                self.message = notice
                self.didChange?()
                if !self.pendingURLs.isEmpty {
                    let pending = self.pendingURLs
                    self.pendingURLs = []
                    self.add(pending)
                }
            }
        }
    }
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "加入 Tray"
        panel.begin { [weak self] response in
            if response == .OK { self?.add(panel.urls) }
        }
    }
    func remove(_ ids: Set<UUID>) {
        guard !importing else { return }
        do {
            items = try storage.remove(ids, from: items)
            if let selected, ids.contains(selected) { self.selected = nil }
            didChange?()
        } catch { message = error.localizedDescription }
    }
    func quickLook(_ item: TrayItem) {
        selected = item.id
        let visible = visibleItems
        preview?(visible.map { url($0) }, visible.firstIndex(of: item) ?? 0)
    }
    func reveal(_ item: TrayItem) { NSWorkspace.shared.activateFileViewerSelecting([url(item)]) }
    func open(_ item: TrayItem) { NSWorkspace.shared.open(url(item)) }
    func copy(_ item: TrayItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url(item) as NSURL])
    }
}
