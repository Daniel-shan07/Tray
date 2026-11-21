import AppKit
import Combine
import SwiftUI
import TrayCore

/// Keep native wheel and keyboard behavior. The narrow thumb also accepts a direct drag.
struct FileList: View {
    @ObservedObject var model: TrayModel
    @State private var offset: CGFloat = 0
    @State private var hovering = false
    @State private var scrolling = false
    @State private var dragOrigin: CGFloat?
    @State private var scrollLink = ScrollLink()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { viewport in
            let height = viewport.size.height
            let contentHeight = CGFloat(model.items.count) * TrayListLayout.rowHeight
            let travel = max(0, contentHeight - height)
            let thumbHeight = min(height, max(18, height * height / max(contentHeight, 1)))
            let track = height - thumbHeight
            NativeFileList(model: model, items: model.items, selection: model.selected, link: scrollLink)
                .onReceive(scrollLink.positions) { newOffset in
                    let next = min(travel, max(0, newOffset))
                    if abs(offset - next) > 0.1 {
                        offset = next
                        scrolling = true
                    }
                }
                .task(id: offset) {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    if !Task.isCancelled { scrolling = false }
                }
                .overlay(alignment: .topTrailing) {
                    if travel > 0.5, track > 0 {
                        Capsule()
                            .fill(.primary.opacity(0.34))
                            .frame(width: 2, height: thumbHeight)
                            .frame(width: 12)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { drag in
                                    if dragOrigin == nil { dragOrigin = offset }
                                    let y = (dragOrigin ?? offset) + drag.translation.height * travel / track
                                    scrollLink.scroll(to: min(travel, max(0, y)))
                                }
                                .onEnded { _ in dragOrigin = nil })
                            .offset(x: 7, y: track * min(1, offset / travel))
                            .opacity(hovering || scrolling || dragOrigin != nil ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering || scrolling || dragOrigin != nil)
                            .accessibilityHidden(true)
                    }
                }
                .onHover { hovering = $0 }
        }
    }
}

private final class ScrollLink {
    let positions = PassthroughSubject<CGFloat, Never>()
    weak var scrollView: NSScrollView?
    func scroll(to y: CGFloat) {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }
}

/// Own the clip view so a system preference change cannot add a second indicator.
private struct NativeFileList: NSViewRepresentable {
    let model: TrayModel
    let items: [TrayItem]
    let selection: UUID?
    let link: ScrollLink

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        let table = NSTableView()
        table.style = .plain
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.rowHeight = TrayListLayout.rowHeight
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = [.width]
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("files"))
        column.minWidth = 0
        table.addTableColumn(column)
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        scroll.documentView = table
        link.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observe(scroll.contentView, link: link)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        if coordinator.items != items {
            coordinator.items = items
            table.reloadData()
        }
        if coordinator.selection != selection {
            coordinator.selection = selection
            if let selection, let index = items.firstIndex(where: { $0.id == selection }) {
                table.scrollRowToVisible(index)
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let model: TrayModel
        var items: [TrayItem] = []
        var selection: UUID?
        private var observation: AnyCancellable?
        init(model: TrayModel) { self.model = model }

        func observe(_ clip: NSClipView, link: ScrollLink) {
            observation = NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: clip)
                .map { _ in clip.documentVisibleRect.minY }
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { link.positions.send($0) }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { items.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let item = items[row]
            let content = FileRow(item: item, model: model, featured: false).id(item.id)
            let identifier = NSUserInterfaceItemIdentifier("fileRow")
            if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSHostingView<AnyView> {
                cell.rootView = AnyView(content)
                return cell
            }
            let cell = NSHostingView(rootView: AnyView(content))
            cell.identifier = identifier
            cell.sizingOptions = []
            return cell
        }
    }
}
