import AppKit

/// Draw the symbol inside the same rectangle AppKit uses for mouse tracking.
@MainActor final class TrayMenuButton: NSButton, NSMenuDelegate {
    private var hoverArea: NSTrackingArea?
    private var hovered = false { didSet { needsDisplay = true } }
    private let model: TrayModel
    private let pin: NSMenuItem
    private let clear: NSMenuItem
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init?(coder: NSCoder) { nil }

    init(model: TrayModel) {
        self.model = model
        pin = NSMenuItem(title: "固定 Tray", action: #selector(togglePin), keyEquivalent: "")
        clear = NSMenuItem(title: "清空 Tray…", action: #selector(clearTray), keyEquivalent: "")
        super.init(frame: .zero)
        title = ""
        setButtonType(.momentaryChange)
        target = self
        action = #selector(openMenu)
        image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        isBordered = false
        imagePosition = .imageOnly
        toolTip = "添加文件、固定与清空"
        setAccessibilityLabel("更多操作")
        let menu = NSMenu()
        menu.autoenablesItems = false
        func command(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            return item
        }
        _ = command("添加文件…", #selector(addFiles), "o")
        pin.target = self
        menu.addItem(pin)
        menu.addItem(.separator())
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())
        let version = menu.addItem(withTitle: "Tray", action: nil, keyEquivalent: "")
        version.isEnabled = false
        _ = command("退出 Tray", #selector(quit), "q")
        menu.delegate = self
        self.menu = menu
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        if let window { hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovered || isHighlighted || model.trackingTrayMenu {
            NSColor.labelColor.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10).fill()
        }
        NSColor.secondaryLabelColor.setFill()
        for dx: CGFloat in [-5, 0, 5] {
            let dot = NSRect(x: bounds.midX + dx - 1.25, y: bounds.midY - 1.25, width: 2.5, height: 2.5)
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    @objc private func openMenu() {
        let edge = isFlipped ? bounds.maxY + 2 : bounds.minY - 2
        menu?.popUp(positioning: nil, at: NSPoint(x: bounds.minX + 3, y: edge), in: self)
        needsDisplay = true
    }
    func menuWillOpen(_ menu: NSMenu) {
        model.trackingTrayMenu = true
        pin.image = NSImage(systemSymbolName: model.pinned ? "pin.slash" : "pin", accessibilityDescription: nil)
        pin.title = model.pinned ? "取消固定" : "固定 Tray"
        clear.isEnabled = !model.items.isEmpty && !model.importing
    }
    func menuDidClose(_ menu: NSMenu) { model.trackingTrayMenu = false }
    @objc func addFiles() { model.chooseFiles() }
    @objc func togglePin() { model.pinned.toggle() }
    @objc func clearTray() { model.confirmClear = true }
    @objc func quit() { NSApp.terminate(nil) }
}
