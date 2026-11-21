import AppKit
import SwiftUI
import TrayCore

/// The tray itself is the interface: one wide glass surface, no chrome or nested card.
struct TrayView: View {
    @ObservedObject var model: TrayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
    private var dropping: Bool { model.dragging || model.items.isEmpty }

    var body: some View {
        GeometryReader { viewport in
            let morph = TrayMorphGeometry(progress: reduceMotion ? 1 : model.revealProgress,
                                          anchorX: model.revealAnchorX, expandedHeight: viewport.size.height)
            tray(morph)
        }
        .frame(width: TrayListLayout.width)
    }

    private func tray(_ morph: TrayMorphGeometry) -> some View {
        return ZStack {
            TrayGlass(radius: morph.cornerRadius, reveal: model.revealProgress)
                .frame(width: morph.bounds.width, height: morph.bounds.height)
                .position(x: morph.bounds.midX, y: morph.bounds.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            DotField(point: model.pointer, clearCenter: dropping, dragging: model.dragging)
                .padding(5).clipShape(shape).allowsHitTesting(false)
                .opacity(min(1, model.revealProgress * 1.6))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.085), value: model.pointer)
            if dropping {
                Text(model.importing ? "正在添加文件…" : "Tray")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.88))
                    .allowsHitTesting(false)
                    .opacity(morph.contentOpacity)
            } else { files.opacity(morph.contentOpacity) }
            if !model.dragging {
                VStack {
                    HStack {
                        if !model.items.isEmpty {
                            Text("\(model.items.count) 个文件")
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.pinned {
                            Image(systemName: "pin")
                                .font(.system(size: 11, weight: .regular))
                                .rotationEffect(.degrees(18))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 22)
                                .offset(y: -6)
                                .accessibilityLabel("Tray 已固定")
                                .help("Tray 已固定")
                        }
                        Color.clear.frame(width: 40, height: 24).allowsHitTesting(false)
                    }
                    Spacer()
                    if model.importing && !model.items.isEmpty {
                        ProgressView().controlSize(.small)
                    }
                    if let message = model.message {
                        HStack(spacing: 6) {
                            Text(message).lineLimit(2)
                            Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                }.padding(.horizontal, 19).padding(.vertical, 10).opacity(morph.contentOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(shape)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): if !model.dragging { model.pointer = point }
            case .ended: if !model.dragging { model.pointer = nil }
            }
        }
        .contextMenu {
            Button("添加文件…") { model.chooseFiles() }
            Button(model.pinned ? "取消固定" : "固定 Tray") { model.pinned.toggle() }
            Button("清空 Tray…", role: .destructive) { model.confirmClear = true }.disabled(model.items.isEmpty || model.importing)
        }
        .allowsHitTesting(!model.confirmClear)
        .accessibilityHidden(model.confirmClear)
        .overlay {
            if model.confirmClear {
                ZStack {
                    shape.fill(.black.opacity(0.12)).onTapGesture { model.confirmClear = false }
                    VStack(spacing: 12) {
                        Text("清空 Tray？").font(.headline)
                        Text("仅移除Tray 中的副本，原文件不受影响。").font(.callout)
                        HStack(spacing: 10) {
                            Button("取消") { model.confirmClear = false }.keyboardShortcut(.cancelAction)
                            Button("清空 Tray", role: .destructive) {
                                model.confirmClear = false
                                model.remove(Set(model.items.map(\.id)))
                            }.disabled(model.importing || model.items.isEmpty)
                        }.controlSize(.large)
                    }
                    .padding(18)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .mask {
            Path(roundedRect: morph.bounds, cornerRadius: morph.cornerRadius, style: .continuous)
                .fill(.white)
        }
    }
    private var files: some View { FileDeck(model: model) }
}

private struct TrayGlass: View {
    let radius: CGFloat
    let reveal: Double
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shell = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        let finish = min(1, max(0, (reveal - 0.12) / 0.75))
        ZStack {
            if reduceTransparency {
                shell.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                TrayFrostedBackdrop(radius: radius)
                shell.fill(LinearGradient(colors: [
                    .white.opacity((dark ? 0.07 : 0.14) * finish),
                    .white.opacity(0.025 * finish),
                    .black.opacity((dark ? 0.06 : 0.025) * finish)
                ], startPoint: .top, endPoint: .bottom))
                shell.fill(RadialGradient(colors: [.white.opacity(0.10 * finish), .clear],
                                          center: .topLeading, startRadius: 0, endRadius: 230))
            }
            // A soft inner contact edge sits inside the window's ambient shadow.
            shell.strokeBorder(.black.opacity((dark ? 0.18 : 0.08) * finish), lineWidth: 1.2)
                .blur(radius: 1.2).offset(y: 0.8).clipShape(shell)
            shell.strokeBorder(LinearGradient(stops: [
                .init(color: .white.opacity(dark ? 0.42 : 0.54), location: 0),
                .init(color: .white.opacity(0.16), location: 0.30),
                .init(color: .white.opacity(0.045), location: 0.65),
                .init(color: .black.opacity(dark ? 0.22 : 0.13), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65)
                .opacity(finish)
            shell.inset(by: 1).strokeBorder(LinearGradient(colors: [
                .white.opacity(0.16 * finish), .clear, .white.opacity(0.07 * finish)
            ], startPoint: .top, endPoint: .bottom), lineWidth: 0.45)
        }
    }
}

private struct TrayFrostedBackdrop: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = TrayBackdropView()
        view.blendingMode = .behindWindow
        view.material = .popover
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = radius
    }
}

private final class TrayBackdropView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct FileRow: View {
    let item: TrayItem
    @ObservedObject var model: TrayModel
    let featured: Bool
    @State private var hovered = false
    private var fileURL: URL { model.url(item) }
    private var title: String {
        item.isDirectory ? item.name : (item.name as NSString).deletingPathExtension
    }
    private var details: String {
        if item.isDirectory { return "文件夹" }
        let ext = fileURL.pathExtension
        let size = item.byteCount < 1000 ? "\(item.byteCount) B" : ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
        return "\(ext.isEmpty ? "文件" : ext.uppercased())  ·  \(size)"
    }

    var body: some View {
        HStack(spacing: featured ? 12 : 8) {
            FileThumbnail(url: fileURL, isDirectory: item.isDirectory)
                .frame(width: featured ? 46 : 27, height: featured ? 56 : 31)
            VStack(alignment: .leading, spacing: featured ? 4 : 2) {
                Text(title).font(.system(size: featured ? 13 : 11.5, weight: .medium))
                    .lineLimit(featured ? 2 : 1).truncationMode(.tail)
                Text(details).font(.system(size: featured ? 10 : 9)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8).padding(.trailing, 21)
        .frame(height: featured ? 72 : TrayListLayout.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(model.selected == item.id ? 0.10 : (hovered ? 0.045 : 0)))
        }
        .overlay {
            FileDragSurface(url: fileURL, selected: { model.selected = item.id }, preview: { model.quickLook(item) })
                .accessibilityLabel(item.name)
        }
        .overlay(alignment: .trailing) {
            if hovered || model.selected == item.id {
                Button { model.quickLook(item) } label: {
                    Image(systemName: "eye").font(.system(size: 11))
                        .frame(width: 22, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("快速预览").help("快速预览")
            }
        }
        .help(item.name)
        .onHover { hovered = $0 }
        .accessibilityAction(named: "快速预览") { model.quickLook(item) }
        .contextMenu {
            Button("快速预览") { model.quickLook(item) }
            Button("打开") { model.open(item) }
            Button("在 Finder 中显示副本") { model.reveal(item) }
            Button("复制文件") { model.copy(item) }
            Divider()
            Button("从 Tray 移除", role: .destructive) { model.remove([item.id]) }.disabled(model.importing)
        }
    }
}

struct DotField: View, Animatable {
    var location: CGPoint
    var strength: CGFloat
    let clearCenter: Bool
    let dragging: Bool
    init(point: CGPoint?, clearCenter: Bool, dragging: Bool) {
        self.dragging = dragging
        location = point ?? CGPoint(x: 130, y: 64)
        strength = point == nil ? 0 : 1
        self.clearCenter = clearCenter
    }
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { .init(.init(location.x, location.y), strength) }
        set { location = CGPoint(x: newValue.first.first, y: newValue.first.second); strength = newValue.second }
    }
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let spread: CGFloat = dragging ? 46 : 35
            let growth: CGFloat = dragging ? 1.65 : 0.76
            let contrast: CGFloat = dragging ? 0.49 : 0.29
            let pitch: CGFloat = 8.5
            let columns = Int(size.width / pitch)
            let rows = Int(size.height / pitch)
            let startX = (size.width - CGFloat(columns) * pitch) / 2
            let startY = (size.height - CGFloat(rows) * pitch) / 2
            for row in 0...rows {
                for col in 0...columns {
                    let x = startX + CGFloat(col) * pitch
                    let y = startY + CGFloat(row) * pitch
                    let distance = hypot(x + 5 - location.x, y + 5 - location.y)
                    let influence = exp(-pow(distance / spread, 2)) * strength
                    let radius: CGFloat = 0.55 + influence * growth
                    let edge = min(x, size.width - x, y, size.height - y)
                    let edgeFade = min(1, max(0, edge / 12))
                    let labelDistance = max(abs(x - size.width / 2) - 26, abs(y - size.height / 2) * 1.8 - 12)
                    let labelFade: CGFloat = clearCenter ? min(1, max(0, labelDistance / 21)) : 0.55
                    let opacity = (0.13 * labelFade * (clearCenter ? 1 : 0.24) + influence * contrast * (clearCenter ? max(labelFade, 0.35) : 1)) * edgeFade
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color((scheme == .dark ? Color.white : Color.black).opacity(opacity)))
                }
            }
        }.accessibilityHidden(true)
    }
}

