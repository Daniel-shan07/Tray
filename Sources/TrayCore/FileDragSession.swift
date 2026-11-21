/// The drag pasteboard retains old URLs after a drop. A held mouse button alone
/// must never treat that old content as a new file drag.
public struct FileDragSession {
    private var idleChangeCount: Int
    public init(initialChangeCount: Int) { idleChangeCount = initialChangeCount }
    public mutating func update(buttonHeld: Bool, changeCount: Int, hasFiles: Bool) -> Bool {
        if !buttonHeld { idleChangeCount = changeCount; return false }
        return changeCount != idleChangeCount && hasFiles
    }
}
