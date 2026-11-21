import AppKit
import ImageIO
import PDFKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

private enum Thumbnails {
    static let cache: NSCache<NSURL, CGImage> = {
        let result = NSCache<NSURL, CGImage>()
        result.countLimit = 128
        return result
    }()

    static func load(_ url: URL) -> CGImage? {
        if let existing = cache.object(forKey: url as NSURL) { return existing }
        let type = UTType(filenameExtension: url.pathExtension)
        let result: CGImage?
        if type?.conforms(to: .pdf) == true {
            guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
            result = withExtendedLifetime(document) {
                page.thumbnail(of: NSSize(width: 144, height: 144), for: .cropBox)
                    .cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
        } else if type?.conforms(to: .image) == true,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 144
                  ] as CFDictionary) {
            result = image
        } else {
            return nil
        }
        if let result { cache.setObject(result, forKey: url as NSURL) }
        return result
    }
}

struct FileThumbnail: View {
    let url: URL
    let isDirectory: Bool
    @State private var thumbnail: NSImage?

    private var spreadsheet: Bool {
        !isDirectory && ["xlsx", "xls", "xlsm", "numbers", "csv", "ods"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable().interpolation(.high).scaledToFit()
                    .shadow(color: .black.opacity(0.14), radius: 1, y: 0.8)
            } else if spreadsheet {
                Canvas { context, size in
                    let green = Color(red: 0.23, green: 0.48, blue: 0.37)
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(green.opacity(0.10)))
                    context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 9)), with: .color(green.opacity(0.82)))
                    var lines = Path()
                    for i in 1..<5 {
                        let x = size.width * CGFloat(i) / 5
                        lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: CGFloat(9), to: size.height, by: 8) {
                        lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(green.opacity(0.30)), lineWidth: 0.6)
                }.clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: isDirectory ? "folder" : "doc")
                    .font(.title2).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            if spreadsheet {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 150, height: 110), scale: 2, representationTypes: .thumbnail)
                request.iconMode = false
                let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                if !Task.isCancelled, let result, result.type == .thumbnail { thumbnail = result.nsImage }
                return
            }
            let image = isDirectory ? nil : await Task.detached(priority: .utility) { [url] in
                Thumbnails.load(url)
            }.value
            guard !Task.isCancelled else { return }
            if let image {
                thumbnail = NSImage(cgImage: image, size: .zero)
            } else {
                thumbnail = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
    }
}
