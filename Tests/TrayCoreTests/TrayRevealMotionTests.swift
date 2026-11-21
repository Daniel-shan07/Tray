import XCTest
@testable import TrayCore
final class TrayRevealMotionTests: XCTestCase {
    func testOpenAndCloseSettleWithoutOvershoot() {
        var motion = TrayRevealMotion()
        for visible in [true, false] {
            motion.setVisible(visible)
            for _ in 0..<90 {
                let previous = motion.value
                motion.advance(by: 1.0 / 60)
                XCTAssertTrue((0...1).contains(motion.value))
                if visible { XCTAssertGreaterThanOrEqual(motion.value, previous) }
                else { XCTAssertLessThanOrEqual(motion.value, previous) }
            }
            XCTAssertEqual(motion.value, visible ? 1 : 0)
            XCTAssertTrue(motion.settled)
        }
    }
    func testFastReversalPreservesPositionAndVelocity() {
        var motion = TrayRevealMotion()
        motion.setVisible(true)
        motion.advance(by: 0.07)
        for visible in [false, true, false, true] {
            let value = motion.value, velocity = motion.velocity
            motion.setVisible(visible)
            XCTAssertEqual(motion.value, value)
            XCTAssertEqual(motion.velocity, velocity)
            motion.advance(by: 1.0 / 60)
        }
        for _ in 0..<90 { motion.advance(by: 1.0 / 60) }
        XCTAssertEqual(motion.value, 1)
    }
    func testOpeningHasPacedMiddleAndRepeatedRequestsDoNotRestart() {
        var motion = TrayRevealMotion()
        motion.setVisible(true)
        motion.advance(by: 0.38 / 3)
        XCTAssertGreaterThan(motion.value, 0.25)
        XCTAssertLessThan(motion.value, 0.35)
        let initial = motion.value
        motion.setVisible(true)
        motion.advance(by: 0.38 / 3)
        let middle = motion.value
        XCTAssertGreaterThan(middle, 0.65)
        XCTAssertLessThan(middle, 0.75)
        XCTAssertGreaterThan(middle - initial, 0.35)
        motion.advance(by: 0.38 / 3)
        XCTAssertEqual(motion.value, 1)
        XCTAssertTrue(motion.settled)
    }
    func testReducedMotionChangesStateImmediately() {
        var motion = TrayRevealMotion()
        motion.setVisible(true, reduceMotion: true)
        XCTAssertEqual(motion.value, 1)
        XCTAssertEqual(motion.velocity, 0)
        motion.setVisible(false, reduceMotion: true)
        XCTAssertEqual(motion.value, 0)
        XCTAssertTrue(motion.settled)
    }
    func testMorphStaysInsideSmallWindowAndExpandsContinuously() {
        for anchor in [CGFloat(0), 172, 344] {
            var previous = TrayMorphGeometry(progress: 0, anchorX: anchor)
            XCTAssertLessThan(previous.bounds.height, 5)
            for step in 1...100 {
                let shape = TrayMorphGeometry(progress: Double(step) / 100, anchorX: anchor)
                XCTAssertGreaterThanOrEqual(shape.bounds.width, previous.bounds.width)
                XCTAssertGreaterThanOrEqual(shape.bounds.height, previous.bounds.height)
                XCTAssertGreaterThanOrEqual(shape.bounds.minX, -0.001)
                XCTAssertLessThanOrEqual(shape.bounds.maxX, 344.001)
                previous = shape
            }
            XCTAssertEqual(previous.bounds.width, 344)
            XCTAssertEqual(previous.bounds.height, 170)
            XCTAssertEqual(previous.contentOpacity, 1)
        }
    }
}
