import XCTest
@testable import TrayCore
final class FileDragSessionTests: XCTestCase {
    func testStaleFilePasteboardDoesNotOpenOnOrdinaryClicks() {
        var session = FileDragSession(initialChangeCount: 10)
        XCTAssertFalse(session.update(buttonHeld: true, changeCount: 10, hasFiles: true))
        XCTAssertFalse(session.update(buttonHeld: false, changeCount: 10, hasFiles: true))
        XCTAssertFalse(session.update(buttonHeld: true, changeCount: 10, hasFiles: true))
    }
    func testOnlyNewFileDragStaysActiveUntilRelease() {
        var session = FileDragSession(initialChangeCount: 10)
        XCTAssertFalse(session.update(buttonHeld: true, changeCount: 11, hasFiles: false))
        XCTAssertTrue(session.update(buttonHeld: true, changeCount: 12, hasFiles: true))
        XCTAssertTrue(session.update(buttonHeld: true, changeCount: 12, hasFiles: true))
        XCTAssertFalse(session.update(buttonHeld: false, changeCount: 12, hasFiles: true))
        XCTAssertFalse(session.update(buttonHeld: true, changeCount: 12, hasFiles: true))
        XCTAssertTrue(session.update(buttonHeld: true, changeCount: 13, hasFiles: true))
    }
    func testReleaseUsesStagedURLsExactlyOnce() {
        let files = [URL(fileURLWithPath: "/tmp/示例.txt")]
        var pending = PendingFileDrop()
        pending.stage(changeCount: 1) { files }
        pending.stage(changeCount: 1) { [] }
        XCTAssertEqual(pending.release(inside: true), files)
        XCTAssertEqual(pending.release(inside: true), [])
        pending.stage(changeCount: 2) { files }
        XCTAssertEqual(pending.release(inside: false), [])
        pending.stage(changeCount: 3) { files }
        pending.cancel()
        XCTAssertEqual(pending.release(inside: true), [])
    }
}
