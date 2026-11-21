import Foundation

/// A paced, nearly linear middle with gentle cosine ramps at both ends.
/// Retargeting retains current position and velocity instead of restarting a clip.
public struct TrayRevealMotion {
    public private(set) var value: Double = 0
    public private(set) var velocity: Double = 0
    public private(set) var target: Double = 0
    private var start: Double = 0
    private var initialVelocity: Double = 0
    private var elapsed: Double = 0
    private var duration: Double = 0.38
    public var settled: Bool { abs(value - target) < 0.0008 && abs(velocity) < 0.012 }
    public init() {}
    public mutating func setVisible(_ visible: Bool, reduceMotion: Bool = false) {
        let destination: Double = visible ? 1 : 0
        if reduceMotion {
            target = destination; value = target; velocity = 0
            start = target; initialVelocity = 0; elapsed = duration
            return
        }
        guard destination != target else { return }
        target = destination
        start = value
        initialVelocity = velocity
        elapsed = 0
        duration = max(0.16, (visible ? 0.38 : 0.26) * sqrt(abs(target - start)))
    }
    public mutating func advance(by seconds: Double) {
        guard seconds > 0, !settled else { return }
        elapsed = min(duration, elapsed + seconds)
        let t = elapsed / duration
        let ramp = 0.18
        let rate = 1 / (1 - ramp)
        let progress: Double
        let slope: Double
        if t < ramp {
            progress = rate * (t / 2 - ramp / (2 * .pi) * sin(.pi * t / ramp))
            slope = rate / 2 * (1 - cos(.pi * t / ramp))
        } else if t > 1 - ramp {
            let remaining = 1 - t
            progress = 1 - rate * (remaining / 2 - ramp / (2 * .pi) * sin(.pi * remaining / ramp))
            slope = rate / 2 * (1 - cos(.pi * remaining / ramp))
        } else {
            progress = rate * (t - ramp / 2)
            slope = rate
        }
        // Carry the interrupted velocity smoothly; the correction vanishes at completion.
        let carry = t - 6 * pow(t, 3) + 8 * pow(t, 4) - 3 * pow(t, 5)
        let carrySlope = 1 - 18 * t * t + 32 * pow(t, 3) - 15 * pow(t, 4)
        value = start + (target - start) * progress + initialVelocity * duration * carry
        velocity = (target - start) * slope / duration + initialVelocity * carrySlope
        if value < 0 { value = 0; velocity = 0 }
        if value > 1 { value = 1; velocity = 0 }
        if elapsed == duration || settled { value = target; velocity = 0 }
    }
}
