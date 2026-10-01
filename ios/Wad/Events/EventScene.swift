import SwiftUI

/// The picture of one show, drawn in code into a Canvas as a function of
/// how far along it is (0 at the start, 1 at the end). Scenes are pure values:
/// nothing is allocated per frame beyond the paths drawn.
protocol EventScene {
    /// The moment to show as a still under Reduce Motion.
    var stillProgress: Double { get }
    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double)
}

enum EventScenes {
    static func scene(for kind: GameEventKind) -> any EventScene {
        switch kind {
        case .holeInOne: HoleInOneScene()
        case .albatross: AlbatrossScene()
        case .eagle: EagleScene()
        case .greenie: GreenieScene()
        case .wadTaken: WadScene()
        case .skinWon: SkinScene()
        case .wolfHoleWon: WolfScene()
        case .snowman: SnowmanScene()
        case .birdie: BirdieScene()
        }
    }
}

// MARK: - Timing

/// Easing and deterministic randomness, so that a frame depends on the
/// progress alone and nothing is kept between frames.
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

    /// 0..<1, the same for the same index and salt every frame.
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

// MARK: - Drawing

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }

    /// `distance` away at `angle` (radians, clockwise on screen).
    func moved(_ distance: CGFloat, at angle: CGFloat) -> CGPoint {
        CGPoint(x: x + distance * cos(angle), y: y + distance * sin(angle))
    }
}

extension GraphicsContext {
    func fill(circleAt center: CGPoint, radius: CGFloat, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
    }

    func fill(ellipseAt center: CGPoint, rx: CGFloat, ry: CGFloat, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)), with: .color(color))
    }

    func fill(polygon points: [CGPoint], _ color: Color) {
        guard points.count > 2 else { return }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        fill(path, with: .color(color))
    }

    func fill(rect: CGRect, radius: CGFloat = 0, _ color: Color) {
        fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
    }

    func stroke(line points: [CGPoint], _ color: Color, width: CGFloat, closed: Bool = false, round: Bool = true) {
        guard points.count > 1 else { return }
        var path = Path()
        path.addLines(points)
        if closed { path.closeSubpath() }
        stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt, lineJoin: .round))
    }

    /// A thick line with round ends.
    func capsule(from a: CGPoint, to b: CGPoint, radius: CGFloat, _ color: Color) {
        stroke(line: [a, b], color, width: radius * 2)
    }

    /// Draws `body` moved, turned and scaled; `rotation` in radians.
    func placed(at origin: CGPoint, rotation: CGFloat = 0, scale: CGFloat = 1, _ body: (inout GraphicsContext) -> Void) {
        drawLayer { layer in
            layer.translateBy(x: origin.x, y: origin.y)
            layer.rotate(by: .radians(rotation))
            layer.scaleBy(x: scale, y: scale)
            body(&layer)
        }
    }

    func fillBackground(_ size: CGSize, top: Color, bottom: Color) {
        fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )
    }

    /// A white flash over everything, `strength` 0...1.
    func flash(_ size: CGSize, _ strength: Double) {
        guard strength > 0 else { return }
        fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(strength)))
    }
}

// MARK: - Hands

/// One hand, palm to the viewer, drawn as bones or as flesh from the same
/// joints. The origin is the middle of the palm; `u` is the palm's width.
/// Fingers are 0 (index) to 3 (little), the thumb is 4.
struct HandModel {
    struct Bone {
        var from: CGPoint
        var to: CGPoint
        var radius: CGFloat
    }

    var u: CGFloat
    /// Per finger, radians: 0 straight, positive curls toward the palm.
    var curl: (Int) -> Double = { _ in 0 }

    var palm: CGRect { CGRect(x: -u / 2, y: -u * 0.55, width: u, height: u * 1.15) }

    var bones: [Bone] {
        var bones: [Bone] = []
        let bases: [CGFloat] = [-0.34, -0.11, 0.12, 0.35]
        let lengths: [CGFloat] = [0.95, 1.05, 0.95, 0.72]
        let spreads: [Double] = [-0.14, -0.04, 0.05, 0.17]
        for finger in 0..<4 {
            var point = CGPoint(x: bases[finger] * u, y: palm.minY)
            var angle = -.pi / 2 + spreads[finger]
            let c = curl(finger)
            for (joint, share) in [0.42, 0.32, 0.26].enumerated() {
                angle += c * (joint == 0 ? 0.6 : 1)
                let next = point.moved(lengths[finger] * share * u, at: angle)
                bones.append(Bone(from: point, to: next, radius: u * (0.085 - CGFloat(joint) * 0.012)))
                point = next
            }
        }
        var point = CGPoint(x: palm.minX + u * 0.05, y: u * 0.1)
        var angle = -2.45 + curl(4)
        for (joint, length) in [0.5, 0.4].enumerated() {
            angle += curl(4) * Double(joint)
            let next = point.moved(length * u, at: angle)
            bones.append(Bone(from: point, to: next, radius: u * (0.1 - CGFloat(joint) * 0.015)))
            point = next
        }
        return bones
    }

    static let bone = Color(red: 0.93, green: 0.9, blue: 0.82)
    static let boneShade = Color(red: 0.62, green: 0.58, blue: 0.5)
    static let skin = Color(red: 0.91, green: 0.72, blue: 0.58)
    static let skinShade = Color(red: 0.72, green: 0.5, blue: 0.38)

    /// The skeleton: carpals, metacarpals, phalanges and the two forearm bones.
    func drawBones(_ c: inout GraphicsContext) {
        let wrist = CGPoint(x: 0, y: palm.maxY)
        c.capsule(from: CGPoint(x: -u * 0.18, y: palm.maxY - u * 0.05), to: CGPoint(x: -u * 0.22, y: palm.maxY + u * 0.9), radius: u * 0.08, Self.bone)
        c.capsule(from: CGPoint(x: u * 0.16, y: palm.maxY - u * 0.05), to: CGPoint(x: u * 0.2, y: palm.maxY + u * 0.9), radius: u * 0.065, Self.bone)
        for base in [-0.34, -0.11, 0.12, 0.35] as [CGFloat] {
            c.capsule(from: wrist, to: CGPoint(x: base * u, y: palm.minY), radius: u * 0.06, Self.bone)
            c.fill(circleAt: CGPoint(x: base * u, y: palm.minY), radius: u * 0.085, Self.boneShade)
        }
        for i in 0..<5 {
            c.fill(circleAt: CGPoint(x: CGFloat(i - 2) * u * 0.17, y: palm.maxY - u * 0.12 - CGFloat(i % 2) * u * 0.12), radius: u * 0.085, Self.bone)
        }
        for bone in bones {
            c.capsule(from: bone.from, to: bone.to, radius: bone.radius, Self.bone)
            c.fill(circleAt: bone.from, radius: bone.radius * 1.1, Self.boneShade)
            c.fill(circleAt: bone.from, radius: bone.radius * 0.8, Self.bone)
        }
    }

    /// The hand with its skin on, as one silhouette.
    func fleshPath() -> Path {
        var path = Path()
        path.addRoundedRect(in: palm.insetBy(dx: -u * 0.06, dy: -u * 0.04), cornerSize: CGSize(width: u * 0.22, height: u * 0.22))
        for bone in bones {
            let r = bone.radius * 1.55
            path.addPath(Path(ellipseIn: CGRect(x: bone.from.x - r, y: bone.from.y - r, width: r * 2, height: r * 2)))
            path.addPath(Path(ellipseIn: CGRect(x: bone.to.x - r, y: bone.to.y - r, width: r * 2, height: r * 2)))
            path.addPath(Path(roundedRect: CGRect(x: -r, y: 0, width: r * 2, height: hypot(bone.to.x - bone.from.x, bone.to.y - bone.from.y)), cornerRadius: r)
                .applying(CGAffineTransform(translationX: bone.from.x, y: bone.from.y)
                    .rotated(by: atan2(bone.to.y - bone.from.y, bone.to.x - bone.from.x) - .pi / 2)))
        }
        path.addRoundedRect(in: CGRect(x: -u * 0.3, y: palm.maxY - u * 0.1, width: u * 0.6, height: u), cornerSize: CGSize(width: u * 0.15, height: u * 0.15))
        return path
    }
}
