import AppKit

/// Original menu-bar mark: the same rounded dot surface as the open tray.
/// Template rendering lets macOS choose contrast for light/dark menu bars.
enum TrayStatusIcon {
    static func make(active: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let outline = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 16, height: 11), xRadius: 3.6, yRadius: 3.6)
            outline.lineWidth = 1.2
            outline.stroke()
            for x: CGFloat in [6, 9.5, 13] {
                for y: CGFloat in [7.3, 10.7] {
                    let diameter: CGFloat = active ? 1.8 : 1.35
                    NSBezierPath(ovalIn: NSRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tray"
        return image
    }
}
