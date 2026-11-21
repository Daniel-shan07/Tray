import XCTest
@testable import TrayCore

final class TrayListLayoutTests: XCTestCase {
    func testListGrowsByWholeRowsAndShrinksBackToCompactHeight() {
        for (count, height) in [(0, 170), (1, 170), (2, 170), (3, 170), (6, 296), (7, 296), (3, 170), (1, 170)] {
            XCTAssertEqual(TrayListLayout.height(for: count, availableHeight: 800), CGFloat(height))
        }
    }

    func testShortDisplayFitsWholeRowsAndStaysOnScreen() {
        XCTAssertEqual(TrayListLayout.height(for: 15, availableHeight: 220), 212)
        XCTAssertEqual(TrayListLayout.height(for: 15, availableHeight: 100), 100)
    }

    func testExpandedMaskMatchesPanelAndKeepsThinStartingShape() {
        for height: CGFloat in [170, 170, 296] {
            XCTAssertEqual(TrayMorphGeometry(progress: 0, expandedHeight: height).bounds.height, 4.48)
            XCTAssertEqual(TrayMorphGeometry(progress: 1, expandedHeight: height).bounds.height, height)
        }
    }
}
