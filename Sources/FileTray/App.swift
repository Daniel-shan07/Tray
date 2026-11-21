import AppKit
import SwiftUI
import Combine
import Quartz
import TrayCore

@main struct FileTrayApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class TrayPanel: NSPanel, NSDraggingDestination {
    weak var dropModel: TrayModel?
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        let point = sender.draggingLocation
        return !(sender.draggingSource is FileDragView) && sender.draggingSourceOperationMask.contains(.copy)
            && NSBezierPath(roundedRect: NSRect(origin: .zero, size: frame.size), xRadius: 32, yRadius: 32).contains(point)
            && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true])
    }
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        let point = sender.draggingLocation
        dropModel?.dragging = true
        dropModel?.pointer = CGPoint(x: point.x, y: frame.height - point.y)
        return .copy
    }
    func draggingExited(_ sender: NSDraggingInfo?) {
        dropModel?.pointer = nil
    }
    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepts(sender) else { return false }
        let urls = fileURLs(from: sender.draggingPasteboard)
        dropModel?.dragging = false
        dropModel?.pointer = nil
        dropModel?.add(urls)
        return !urls.isEmpty
    }

    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        (contentViewController as? PreviewController)?.urls.isEmpty == false
    }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let controller = contentViewController as? PreviewController else { return }
        panel.dataSource = controller
        panel.delegate = controller
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor final class PreviewController: NSViewController, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var urls: [URL] = []
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] as NSURL }
    func show(_ urls: [URL], index: Int) {
        guard urls.indices.contains(index), let owner = view.window else { return }
        self.urls = urls
        NSApp.activate(ignoringOtherApps: true)
        owner.makeKeyAndOrderFront(nil)
        owner.makeMain()
        owner.makeFirstResponder(owner)
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.level = .popUpMenu
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        panel.currentPreviewItemIndex = index
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { panel.draggingEntered(sender) }
    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { panel.draggingUpdated(sender) }
    func draggingExited(_ sender: NSDraggingInfo?) { panel.draggingExited(sender) }
    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { panel.prepareForDragOperation(sender) }
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool { panel.performDragOperation(sender) }

    private var dragHighlight: AnyCancellable?
    private var menuVisibility: AnyCancellable?
    private var status: NSStatusItem!
    private var panel: TrayPanel!
    private var model: TrayModel!
    private let previewController = PreviewController()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var proximityTimer: Timer?
    private var autoOpened = false
    private var reveal = TrayRevealMotion()
    private var revealTimer: Timer?
    private var lastRevealTick = ProcessInfo.processInfo.systemUptime
    private var restingFrame = NSRect.zero
    private var displayedHeight = TrayListLayout.compactHeight
    private var initialHeight = TrayListLayout.compactHeight
    private var resizeStarted = 0.0
    private var dragWasActive = false
    private var lastNearTime = Date.distantPast
    private var dragScreen: NSScreen?
    private var dragSession = FileDragSession(initialChangeCount: NSPasteboard(name: .drag).changeCount)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { model = try TrayModel() }
        catch {
            let alert = NSAlert()
            alert.messageText = "无法读取 Tray 文件"
            alert.informativeText = "为保护已有文件，Tray 已保留原有数据。请检查 ~/Library/Application Support/FileTray/items.json。\n" + error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = status.button {
            button.image = TrayStatusIcon.make()
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            button.toolTip = "Tray · 拖入文件，随时取用"
            let drop = StatusDropView(frame: button.bounds)
            drop.autoresizingMask = [.width, .height]
            drop.clicked = { [weak self] in self?.autoOpened = false; self?.toggle() }
            drop.contextClicked = { [weak self, weak drop] event in
                guard let self, let drop else { return }
                self.showStatusMenu(event, in: drop)
            }
            drop.received = { [weak self] urls in self?.autoOpened = false; self?.model.dragging = false; self?.model.add(urls); self?.show() }
            drop.hover = { [weak self] active in
                self?.model.dragging = active
                self?.model.pointer = nil
                if active { self?.show(activate: false) }
            }
            button.addSubview(drop)
        }
        dragHighlight = model.$dragging.removeDuplicates().sink { [weak self] active in
            self?.status.button?.isHighlighted = active
            self?.status.button?.image = TrayStatusIcon.make(active: active)
        }
        let host = NSHostingController(rootView: TrayView(model: model))
        host.sizingOptions = []
        previewController.addChild(host)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: TrayListLayout.width, height: TrayListLayout.compactHeight))
        previewController.view = content
        host.view.frame = content.bounds
        host.view.autoresizingMask = [.width, .height]
        content.addSubview(host.view)

        let more = TrayMenuButton(model: model)
        more.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(more, positioned: .above, relativeTo: host.view)
        NSLayoutConstraint.activate([
            more.topAnchor.constraint(equalTo: content.topAnchor),
            more.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            more.widthAnchor.constraint(equalToConstant: 52),
            more.heightAnchor.constraint(equalToConstant: TrayListLayout.topInset)
        ])
        let target = TrayFileTarget(frame: content.bounds)
        target.autoresizingMask = [.width, .height]
        target.isHidden = true
        content.addSubview(target, positioned: .above, relativeTo: more)
        menuVisibility = model.$dragging.combineLatest(model.$revealProgress, model.$confirmClear).sink { dragging, progress, confirming in
            target.updateVisibility(dragging && !confirming)
            more.isHidden = confirming || dragging || progress < 0.72
            more.alphaValue = min(1, max(0, (progress - 0.72) / 0.28))
        }
        panel = TrayPanel(contentRect: NSRect(x: 0, y: 0, width: TrayListLayout.width, height: TrayListLayout.compactHeight), styleMask: [.borderless], backing: .buffered, defer: false)
        target.tray = panel
        panel.dropModel = model
        panel.registerForDraggedTypes([.fileURL])
        panel.isReleasedWhenClosed = false
        panel.title = "Tray"
        panel.contentViewController = previewController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 32
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        model.didChange = { [weak self] in self?.updateCount() }
        model.preview = { [weak self] urls, index in self?.previewController.show(urls, index: index) }
        updateCount()
        // The drag pasteboard and mouse-button state let us sense real file drags
        // before the pointer touches our status item, without Accessibility access.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDragProximity() }
        }
        RunLoop.main.add(timer, forMode: .common)
        proximityTimer = timer
        if let flag = CommandLine.arguments.firstIndex(of: "--export-preview"), CommandLine.arguments.count > flag + 1 {
            let path = CommandLine.arguments[flag + 1]
            if CommandLine.arguments.contains("--drag-preview") {
                model.dragging = true
                model.pointer = CGPoint(x: 92.5, y: 109)
            }
            show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                guard let view = self?.panel.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                print("Reveal snapshot: \(self?.reveal.value ?? -1), timer: \(self?.revealTimer?.isValid ?? false)")
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
            return
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.panel.isVisible, !self.model.pinned, event.window !== self.panel,
               event.window?.sheetParent !== self.panel, !(event.window is NSOpenPanel),
               event.window !== self.status.button?.window, !(QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible) {
                self.hideGracefully()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible, !self.model.trackingTrayMenu else { return }
            if !self.model.pinned {
                self.hideGracefully()
            } else if event.type == .leftMouseDown, self.isDesktopClick(event) {
                self.hideGracefully(ignorePin: true)
            }
        }
        // First launch opens an empty, working tray; subsequent launches stay in the menu bar.
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            show()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.importing == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "文件仍在加入 Tray"
        alert.informativeText = "请等复制完成后再退出。"
        alert.addButton(withTitle: "继续等待")
        alert.runModal()
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        proximityTimer?.invalidate()
        revealTimer?.invalidate()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
    private func updateCount() {
        status.button?.title = model.items.isEmpty ? "" : " \(model.items.count)"
        status.button?.toolTip = "Tray · \(model.items.count) 个文件"
        // Keep the panel attached to its menu-bar item as rows are added or removed.
        if panel != nil { resizeAndPosition() }
    }
    private func showStatusMenu(_ event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .accessibilityHighContrastAqua : .aqua)
        menu.autoenablesItems = false
        func add(_ title: String, _ symbol: String, _ action: Selector) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return item
        }
        let open = reveal.target == 1
        _ = add(open ? "收起 Tray" : "打开 Tray", "tray", #selector(toggleFromMenu))
        _ = add("添加文件…", "plus", #selector(addFromMenu))
        _ = add(model.pinned ? "取消固定" : "固定 Tray", model.pinned ? "pin.slash" : "pin", #selector(pinFromMenu))
        menu.addItem(.separator())
        add("清空 Tray…", "trash", #selector(clearFromMenu)).isEnabled = !model.items.isEmpty && !model.importing
        menu.addItem(.separator())
        _ = add("退出 Tray", "power", #selector(quitFromMenu))
        model.trackingTrayMenu = true
        defer { model.trackingTrayMenu = false }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
    @objc private func toggleFromMenu() {
        model.trackingTrayMenu = false
        autoOpened = false
        toggle()
    }
    @objc private func addFromMenu() { show(); model.chooseFiles() }
    @objc private func pinFromMenu() {
        model.pinned.toggle()
        if model.pinned { show() }
    }
    @objc private func clearFromMenu() { show(); model.confirmClear = true }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    private func toggle() {
        if reveal.target == 1 { hideGracefully(ignorePin: true) } else { dragScreen = nil; show() }
    }
    private func checkDragProximity() {
        // Suppress desktop sensing in deterministic view exports.
        guard !CommandLine.arguments.contains("--export-preview") else { return }
        let point = NSEvent.mouseLocation
        let held = NSEvent.pressedMouseButtons & 1 != 0
        let dragBoard = NSPasteboard(name: .drag)
        let hasFileType = dragBoard.types?.contains(.fileURL) == true
        let active = dragSession.update(buttonHeld: held, changeCount: dragBoard.changeCount, hasFiles: hasFileType)
        if active, let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            let nearMenu = screen.frame.maxY - point.y < 84
            let insideTray = panel.isVisible && panel.frame.insetBy(dx: -24, dy: -24).contains(point)
            if nearMenu || (autoOpened && insideTray) {
                lastNearTime = Date()
                if reveal.target == 0 {
                    dragScreen = screen
                    autoOpened = true
                    model.dragging = true
                    show(activate: false)
                }
            }
            if autoOpened || insideTray {
                model.dragging = true
                model.pointer = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
                // Hysteresis prevents flicker while crossing the menu/card gap.
                if !nearMenu && !insideTray && Date().timeIntervalSince(lastNearTime) > 0.32 {
                    hideGracefully()
                }
            }
        } else if dragWasActive {
            let droppedInside = panel.isVisible && panel.frame.contains(point)
            model.dragging = false
            model.pointer = nil
            if autoOpened && !droppedInside && !model.importing { hideGracefully() }
            autoOpened = false
        }
        dragWasActive = active
    }
    private func isDesktopClick(_ event: NSEvent) -> Bool {
        let id = event.windowNumber > 0 ? event.windowNumber :
            NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        guard id > 0, let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(id)) as? [[String: Any]],
              let level = info.first?[kCGWindowLayer as String] as? Int else { return false }
        return level <= Int(CGWindowLevelForKey(.desktopIconWindow))
    }

    private func hideGracefully(ignorePin: Bool = false) {
        guard !model.trackingTrayMenu, !model.pinned || ignorePin else { return }
        if ignorePin { autoOpened = false }
        model.dragging = false
        model.pointer = nil
        guard panel.isVisible else { return }
        model.confirmClear = false
        setRevealVisible(false)
    }
    private func show(activate: Bool = true) {
        resizeAndPosition()
        setRevealVisible(true)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel)
        } else { panel.orderFrontRegardless() }
    }
    private func setRevealVisible(_ visible: Bool) {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        reveal.setVisible(visible, reduceMotion: reduced)
        applyReveal()
        if reveal.settled && displayedHeight == restingFrame.height {
            revealTimer?.invalidate(); revealTimer = nil
            if !visible { panel.orderOut(nil) }
            return
        }
        startFrameTimer()
    }
    private func startFrameTimer() {
        guard revealTimer == nil else { return }
        lastRevealTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceReveal() }
        }
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
    }
    private func advanceReveal() {
        let now = ProcessInfo.processInfo.systemUptime
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            reveal.setVisible(reveal.target == 1, reduceMotion: true)
        } else {
            reveal.advance(by: min(now - lastRevealTick, 0.064))
        }
        lastRevealTick = now
        if displayedHeight != restingFrame.height {
            let t = min(1, (now - resizeStarted) / 0.20)
            let smooth = t * t * (3 - 2 * t)
            displayedHeight = t == 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? restingFrame.height : initialHeight + (restingFrame.height - initialHeight) * smooth
        }
        applyReveal()
        if reveal.settled && displayedHeight == restingFrame.height {
            revealTimer?.invalidate(); revealTimer = nil
            if reveal.target == 0 { autoOpened = false; panel.orderOut(nil) }
        }
    }
    private func applyReveal() {
        let progress = reveal.value
        model.revealProgress = progress
        // The top edge remains linked to the menu bar; displacement is only 3pt.
        let displacement = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 3 * (1 - progress)
        if restingFrame != .zero {
            let frame = NSRect(x: restingFrame.minX, y: restingFrame.maxY - displayedHeight + displacement,
                               width: restingFrame.width, height: displayedHeight)
            if panel.frame != frame {
                let resized = panel.frame.size != frame.size
                panel.setFrame(frame, display: true)
                if resized { panel.invalidateShadow() }
            }
        }
        panel.alphaValue = progress
    }
    private func resizeAndPosition() {
        guard let button = status.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = dragScreen ?? window.screen ?? NSScreen.main!
        let width = TrayListLayout.width
        let height = min(screen.visibleFrame.height - 16, model.items.isEmpty ? TrayListLayout.compactHeight : 222)
        if height != restingFrame.height {
            if panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                initialHeight = displayedHeight
                resizeStarted = ProcessInfo.processInfo.systemUptime
                startFrameTimer()
            } else { displayedHeight = height }
        }
        let anchorX = screen.frame.contains(anchor.origin) ? anchor.midX : NSEvent.mouseLocation.x
        let x = min(max(anchorX - width / 2, screen.visibleFrame.minX + 10), screen.visibleFrame.maxX - width - 10)
        model.revealAnchorX = min(width, max(0, anchorX - x))
        restingFrame = NSRect(x: x, y: screen.visibleFrame.maxY - height - 8, width: width, height: height)
        applyReveal()
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        if model.confirmClear {
            if event.keyCode == 53 { model.confirmClear = false; return true }
            return false
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "o" { model.chooseFiles(); return true }
        if event.keyCode == 53, model.selected != nil { model.selected = nil; return true }
        if event.keyCode == 53 { model.pinned = false; hideGracefully(); return true }
        if panel.firstResponder is NSTextView { return false }
        let visible = model.visibleItems
        guard !visible.isEmpty else { return false }
        let index = visible.firstIndex { $0.id == model.selected } ?? -1
        switch event.keyCode {
        case 49:
            model.quickLook(visible[max(index, 0)]); return true
        case 125, 126, 123, 124:
            let delta = (event.keyCode == 125 || event.keyCode == 124) ? 1 : -1
            model.selected = visible[min(max(index + delta, 0), visible.count - 1)].id; return true
        case 51, 117:
            if let selected = model.selected { model.remove([selected]) }; return true
        default: return false
        }
    }
}
