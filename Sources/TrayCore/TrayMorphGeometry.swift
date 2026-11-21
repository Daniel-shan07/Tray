import Foundation
import CoreGraphics

/// A narrow capsule broadens first, then gains depth. Content keeps its own size.
public struct TrayMorphGeometry {
    public let bounds: CGRect
    public let cornerRadius: CGFloat
    public let contentOpacity: Double
    public init(progress: Double, anchorX: CGFloat = TrayListLayout.width / 2, expandedHeight: CGFloat = TrayListLayout.compactHeight) {
        let p = min(1, max(0, progress))
        func smooth(_ value: Double) -> Double {
            let t = min(1, max(0, value))
            return t * t * (3 - 2 * t)
        }
        let growth = 1 - pow(1 - p, 2)
        let width: CGFloat = 73 + (TrayListLayout.width - 73) * growth
        let height: CGFloat = 4.48 + (expandedHeight - 4.48) * growth
        bounds = CGRect(x: min(max(0, anchorX - width / 2), TrayListLayout.width - width), y: 0, width: width, height: height)
        cornerRadius = min(32, height / 2)
        contentOpacity = smooth((p - 0.1) / 0.52)
    }
}
