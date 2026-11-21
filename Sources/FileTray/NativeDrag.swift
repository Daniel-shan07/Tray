import AppKit
import SwiftUI

func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
}

final class StatusDropView: NSView {
    var contextClicked: ((NSEvent) -> Void)?
    var clicked: (() -> Void)?
    var received: (([URL]) -> Void)?
    var hover: ((Bool) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Tray 文件托盘")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func accessibilityPerformPress() -> Bool { clicked?(); return true }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let contextClicked { contextClicked(event) }
        else { clicked?() }
    }
    override func rightMouseDown(with event: NSEvent) { contextClicked?(event) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender.draggingPasteboard).isEmpty else { return [] }
        hover?(true)
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hover?(false) }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { hover?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hover?(false)
        let urls = fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        received?(urls)
        return true
    }
}

/// A native file-URL drag exports the actual cached file, including folders.
struct FileDragSurface: NSViewRepresentable {
    let url: URL
    let selected: () -> Void
    let preview: () -> Void
    var showsDeleteButton = false
    func makeNSView(context: Context) -> FileDragView { FileDragView() }
    func updateNSView(_ view: FileDragView, context: Context) {
        view.url = url; view.select = selected; view.preview = preview
        view.showsDeleteButton = showsDeleteButton
    }
}
final class FileDragView: NSView, NSDraggingSource {
    var url: URL?
    var select: (() -> Void)?
    var preview: (() -> Void)?
    var showsDeleteButton = false
    private var down: NSPoint?
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let topDistance = isFlipped ? local.y - bounds.minY : bounds.maxY - local.y
        // SwiftUI owns the visible delete control above this native drag surface.
        if showsDeleteButton, bounds.contains(local), hypot(bounds.maxX - local.x, topDistance) <= 13 {
            return nil
        }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
        down = convert(event.locationInWindow, from: nil)
        select?()
        if event.clickCount == 2 { preview?() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let url, let down else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - down.x, point.y - down.y) > 4 else { return }
        self.down = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(NSRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}

struct TrayDropSurface: NSViewRepresentable {
    let received: ([URL]) -> Void
    let hover: (Bool) -> Void
    func makeNSView(context: Context) -> StatusDropView { StatusDropView(frame: .zero) }
    func updateNSView(_ view: StatusDropView, context: Context) { view.received = received; view.hover = hover }
}

/// The foreground destination stays in the view hierarchy until Finder finishes the drop.
final class TrayFileTarget: NSView {
    weak var tray: TrayPanel?
    private var tracking = false
    private var showingFeedback = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.012).cgColor
        layer?.cornerRadius = 32
    }
    required init?(coder: NSCoder) { nil }
    func updateVisibility(_ dragging: Bool) {
        showingFeedback = dragging
        isHidden = !tracking && !dragging
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        tracking = true
        return tray?.draggingEntered(sender) ?? []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        tray?.draggingUpdated(sender) ?? []
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        tray?.prepareForDragOperation(sender) ?? false
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { finish() }
        return tray?.performDragOperation(sender) ?? false
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        tray?.draggingExited(sender)
        finish()
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { finish() }
    private func finish() { tracking = false; isHidden = !showingFeedback }
}
