import CoreGraphics

public enum TrayListLayout {
    public static let width: CGFloat = 344
    public static let compactHeight: CGFloat = 170
    public static let rowHeight: CGFloat = 42
    public static let topInset: CGFloat = 32
    public static let bottomInset: CGFloat = 12
    public static let maxRows = 6

    public static func height(for count: Int, availableHeight: CGFloat) -> CGFloat {
        let insets = topInset + bottomInset
        let room = max(0, min(CGFloat(maxRows), floor((availableHeight - insets) / rowHeight)))
        let rows = min(CGFloat(max(0, count)), room)
        return min(max(0, availableHeight), max(compactHeight, insets + rows * rowHeight))
    }
}
