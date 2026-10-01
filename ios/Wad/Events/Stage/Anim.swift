import CoreGraphics
import Foundation

/// Easing and deterministic randomness for the drawings and the shows: the
/// same index and salt always give the same number, so art is reproducible.
enum Anim {
    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// 0...1 as `t` goes from `from` to `to`, clamped outside.
    static func seg(_ t: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return t >= to ? 1 : 0 }
        return clamp((t - from) / (to - from))
    }

    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    static func easeIn(_ x: Double) -> Double { pow(clamp(x), 3) }
    static func easeInOut(_ x: Double) -> Double {
        let c = clamp(x)
        return c * c * (3 - 2 * c)
    }

    /// Overshoots the end and settles back.
    static func back(_ x: Double) -> Double {
        let c = clamp(x) - 1
        return 1 + 2.70158 * c * c * c + 1.70158 * c * c
    }

    static func lerp(_ a: Double, _ b: Double, _ x: Double) -> Double { a + (b - a) * x }

    /// 0..<1, the same for the same index and salt every time.
    static func hash(_ i: Int, _ salt: Int = 0) -> Double {
        var x = UInt64(truncatingIfNeeded: i) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(truncatingIfNeeded: salt) &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 31
        x &*= 0x94D0_49BB_1331_11EB
        x ^= x >> 29
        return Double(x >> 11) / Double(1 << 53)
    }

    /// -1...1, the same for the same index and salt.
    static func signed(_ i: Int, _ salt: Int = 0) -> Double { hash(i, salt) * 2 - 1 }
}

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }
}
