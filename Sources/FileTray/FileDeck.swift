import SwiftUI
import TrayCore

struct FileDeck: View {
    @ObservedObject var model: TrayModel
    @State private var hovered: UUID?
    @State private var deleteReady: UUID?
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var lastPage: Int { max(0, (model.items.count - 1) / 4) }
    private var current: Int { min(page, lastPage) }
    private func turn(_ step: Int) {
        page = min(lastPage, max(0, current + step))
        model.selected = nil
    }

    var body: some View {
        let cards = Array(model.items.dropFirst(current * 4).prefix(4))
        let chosen = cards.firstIndex { $0.id == model.selected }
        VStack(spacing: 0) {
            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, item in
                    let distance = CGFloat(index) - CGFloat(cards.count - 1) / 2
                    let selected = chosen == index
                    let raised = hovered == item.id
                    let showsDelete = raised && deleteReady == item.id
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.isDirectory ? "文件夹" : (model.url(item).pathExtension.uppercased().isEmpty ? "文件" : model.url(item).pathExtension.uppercased()))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                        FileThumbnail(url: model.url(item), isDirectory: item.isDirectory)
                            .frame(maxWidth: .infinity).frame(height: 51)
                        Text(item.isDirectory ? item.name : (item.name as NSString).deletingPathExtension).font(.system(size: 10, weight: .medium)).lineLimit(2).frame(height: 24, alignment: .topLeading)
                    }
                    .padding(8).frame(width: 94, height: 116)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.12), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.08), radius: 0.8, y: 0.7)
                    .shadow(color: .black.opacity(selected ? 0.17 : (raised ? 0.13 : 0.09)),
                            radius: selected ? 7 : (raised ? 5 : 3), y: selected ? 5 : (raised ? 3 : 2))
                    .overlay {
                        FileDragSurface(url: model.url(item), selected: { model.selected = selected ? nil : item.id }, preview: { model.quickLook(item) }, showsDeleteButton: showsDelete)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            hovered = nil
                            deleteReady = nil
                            model.remove([item.id])
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color(white: 0.46))
                                .frame(width: 18, height: 18)
                                .background(.white, in: Circle())
                                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.6))
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                .frame(width: 26, height: 26)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 13, y: -13)
                        .disabled(model.importing)
                        .accessibilityLabel("从 Tray 移除 \(item.name)")
                        .help("从 Tray 移除")
                        .opacity(showsDelete ? 1 : 0)
                        .allowsHitTesting(showsDelete)
                        .accessibilityHidden(!showsDelete)
                        .animation(reduceMotion ? nil : .easeInOut(duration: showsDelete ? 0.48 : 0.16), value: showsDelete)
                    }
                    .contextMenu {
                        Button("快速预览") { model.quickLook(item) }
                        Button("打开") { model.open(item) }
                        Button("在 Finder 中显示副本") { model.reveal(item) }
                        Button("复制文件") { model.copy(item) }
                        Button("从 Tray 移除", role: .destructive) { model.remove([item.id]) }.disabled(model.importing)
                    }
                    .help(item.name)
                    .contentShape(FileCardHoverShape(includesDeleteButton: showsDelete))
                    .onHover { inside in
                        if inside {
                            if hovered != item.id { deleteReady = nil; hovered = item.id }
                        } else if hovered == item.id {
                            deleteReady = nil
                            hovered = nil
                        }
                    }
                    .rotationEffect(.degrees(selected ? 0 : Double(distance) * (raised ? 2 : 7)), anchor: .bottom)
                    .offset(x: distance * 49 + CGFloat(chosen.map { index == $0 ? 0 : (index < $0 ? -7 : 7) } ?? 0),
                            y: selected ? -16 : (raised ? -5 : abs(distance) * 4 + 7))
                    .zIndex(raised ? 11 : (selected ? 10 : Double(index)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovered)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.72, 0.18, 1, duration: 0.36), value: model.selected)
            HStack {
                if lastPage > 0 { Button { turn(-1) } label: { Image(systemName: "chevron.left") }.disabled(current == 0).accessibilityLabel("上一叠") }
                Group {
                    if let chosen {
                        let item = cards[chosen]
                        Text(item.name + (item.isDirectory ? "" : " · " + ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)))
                    } else if lastPage > 0 { Text("\(current + 1) / \(lastPage + 1)") }
                }.lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity)
                if lastPage > 0 { Button { turn(1) } label: { Image(systemName: "chevron.right") }.disabled(current == lastPage).accessibilityLabel("下一叠") }
            }.buttonStyle(.plain).font(.system(size: 11)).frame(height: 22)
        }
        .padding(.top, 31).padding(.bottom, 6).padding(.horizontal, 15)
        .task(id: hovered) {
            guard let id = hovered else { return }
            do { try await Task.sleep(nanoseconds: 100_000_000) }
            catch { return }
            guard !Task.isCancelled, hovered == id else { return }
            deleteReady = id
        }
        .onChange(of: current) { _ in
            hovered = nil
            deleteReady = nil
        }
        .onChange(of: model.selected) { id in
            if let i = model.items.firstIndex(where: { $0.id == id }) { page = i / 4 }
        }
        .onChange(of: lastPage) { page = min(page, $0) }
    }
}

private struct FileCardHoverShape: Shape {
    let includesDeleteButton: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if includesDeleteButton {
            // Keep hovering active while crossing from the card onto its corner button.
            path.addEllipse(in: CGRect(x: rect.maxX - 13, y: rect.minY - 13, width: 26, height: 26))
        }
        return path
    }
}
