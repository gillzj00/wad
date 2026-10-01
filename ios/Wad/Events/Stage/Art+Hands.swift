import SpriteKit
import UIKit

/// A right hand seen from the back, fingers up, from the same joints whether
/// bone or flesh. The origin is the middle of the palm; `u` is the palm's
/// width. Fingers are 0 (index, on the left) to 3 (little), the thumb is 4.
///
/// Curling folds a finger away from the viewer, as a real fist does: each
/// phalanx pitches out of the picture plane, so it foreshortens, and once it
/// is past vertical it hangs behind the palm.
struct HandGeometry {
    struct Segment {
        var from: CGPoint
        var to: CGPoint
        var radius: CGFloat
        var finger: Int
        var joint: Int
        /// How far out of the plane the segment points: 0 flat, pi/2 straight
        /// away from the viewer, more than that folded back behind the palm.
        var pitch: CGFloat
        var behind: Bool { pitch > .pi / 2 + 0.12 }
        var direction: CGPoint {
            let len = max(hypot(to.x - from.x, to.y - from.y), 0.001)
            return CGPoint(x: (to.x - from.x) / len, y: (to.y - from.y) / len)
        }
    }

    var u: CGFloat
    var origin: CGPoint
    /// Per finger: 0 straight, 1 folded into a fist.
    var curl: (Int) -> CGFloat

    var palm: CGRect { CGRect(x: origin.x - u / 2, y: origin.y - u * 0.6, width: u, height: u * 1.15) }
    var wrist: CGPoint { CGPoint(x: origin.x, y: palm.minY) }
    var knuckleY: CGFloat { palm.maxY }

    static let bases: [CGFloat] = [-0.34, -0.11, 0.12, 0.35]
    static let lengths: [CGFloat] = [0.95, 1.05, 0.95, 0.72]
    static let spreads: [CGFloat] = [0.14, 0.04, -0.05, -0.17]
    static let shares: [CGFloat] = [0.42, 0.32, 0.26]
    /// How much each joint bends, in radians, at a full curl.
    static let bends: [CGFloat] = [1.6, 1.4, 0.85]

    func knuckle(_ finger: Int) -> CGPoint { CGPoint(x: origin.x + Self.bases[finger] * u, y: knuckleY) }
    var thumbBase: CGPoint { CGPoint(x: palm.minX + u * 0.02, y: origin.y - u * 0.12) }

    var segments: [Segment] {
        var out: [Segment] = []
        for finger in 0..<4 {
            let c = curl(finger)
            var point = knuckle(finger)
            let angle = CGFloat.pi / 2 + Self.spreads[finger] * (1 - 0.6 * c)
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            var pitch: CGFloat = 0
            for joint in 0..<3 {
                pitch += Self.bends[joint] * c
                let radius = u * (0.085 - CGFloat(joint) * 0.011) * (1 - 0.1 * abs(sin(min(pitch, .pi))))
                let full = Self.lengths[finger] * Self.shares[joint] * u
                var length = full * cos(pitch)
                // Nearly end on: the knuckle still shows as a short knob.
                if abs(length) < radius * 1.3 { length = length < 0 ? -radius * 1.3 : radius * 1.3 }
                let next = CGPoint(x: point.x + dir.x * length, y: point.y + dir.y * length)
                out.append(Segment(from: point, to: next, radius: radius, finger: finger, joint: joint, pitch: pitch))
                point = next
            }
        }
        // The thumb folds across the palm in the plane.
        let t = curl(4)
        var point = thumbBase
        var angle = CGFloat(2.6) - t * 4.8
        for (joint, length) in [CGFloat(0.42), 0.34].enumerated() {
            angle -= t * 1.2 * CGFloat(joint)
            let next = CGPoint(x: point.x + cos(angle) * length * u, y: point.y + sin(angle) * length * u)
            out.append(Segment(from: point, to: next, radius: u * (0.1 - CGFloat(joint) * 0.015), finger: 4, joint: joint, pitch: 0))
            point = next
        }
        return out
    }

    func segments(of finger: Int) -> [Segment] { segments.filter { $0.finger == finger } }

    /// The skin over the back of the hand, without the fingers: wide at the
    /// knuckles, narrower at the wrist, with the web of the thumb.
    var palmPath: CGPath {
        let p = palm
        return Draw.smooth([
            CGPoint(x: p.minX + u * 0.1, y: p.minY - u * 0.05),
            CGPoint(x: p.maxX - u * 0.08, y: p.minY - u * 0.05),
            CGPoint(x: p.maxX + u * 0.06, y: p.midY - u * 0.1),
            CGPoint(x: p.maxX + u * 0.02, y: p.maxY - u * 0.02),
            CGPoint(x: p.midX, y: p.maxY + u * 0.04),
            CGPoint(x: p.minX - u * 0.02, y: p.maxY - u * 0.05),
            CGPoint(x: p.minX - u * 0.06, y: p.midY + u * 0.05),
            CGPoint(x: p.minX - u * 0.02, y: p.minY + u * 0.2),
        ], tension: 0.5)
    }

    /// The forearm, narrowest at the wrist, widening down out of the picture.
    var forearmPath: CGPath {
        let w = wrist
        return Draw.smooth([
            CGPoint(x: w.x - u * 0.3, y: w.y + u * 0.12), CGPoint(x: w.x + u * 0.3, y: w.y + u * 0.12),
            CGPoint(x: w.x + u * 0.33, y: w.y - u * 0.3), CGPoint(x: w.x + u * 0.4, y: w.y - u * 1.1), CGPoint(x: w.x + u * 0.42, y: w.y - u * 1.6),
            CGPoint(x: w.x - u * 0.42, y: w.y - u * 1.6), CGPoint(x: w.x - u * 0.4, y: w.y - u * 1.1), CGPoint(x: w.x - u * 0.33, y: w.y - u * 0.3),
        ], tension: 0.4)
    }
}

extension Art {
    static let handSize = CGSize(width: 520, height: 780)
    /// Where the wrist is in a hand texture, as the sprite's anchor.
    static let handAnchor = CGPoint(x: 0.5, y: 0.1)

    private static func geometry(curl: @escaping (Int) -> CGFloat) -> HandGeometry {
        HandGeometry(u: 170, origin: CGPoint(x: 260, y: 280), curl: curl)
    }

    // MARK: Bone

    /// A skeleton hand: `curl` 0 is open, 1 is a fist; `middle` overrides the
    /// middle finger. Flicking fingers cycle a few of these.
    static func skeletonHand(curl: CGFloat, middle: CGFloat? = nil, thumb: CGFloat = 0.1, key: String) -> SKTexture {
        Textures.make("skeleton-\(key)", size: handSize) { c, _ in
            let hand = geometry { finger in
                if finger == 4 { return thumb }
                if finger == 1, let middle { return middle }
                return curl
            }
            drawBones(c, hand)
        }
    }

    /// A long bone: an hourglass shaft with flared ends, two condyles at each
    /// end (a tuft at `to` for a fingertip). The extremities are at the points.
    static func bone(from a: CGPoint, to b: CGPoint, r: CGFloat, headA: CGFloat = 1.3, headB: CGFloat = 1.25, tuft: Bool = false) -> CGPath {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let ha = r * headA, hb = r * headB
        if length < r * 2.2 {
            // Seen nearly end on: just the head, a rounded knob with a dip between its condyles.
            let knob = Draw.smooth([
                CGPoint(x: 0, y: hb * 0.6), CGPoint(x: length * 0.5, y: hb * 0.95), CGPoint(x: length, y: hb * 0.55), CGPoint(x: length * 0.92, y: 0),
                CGPoint(x: length, y: -hb * 0.55), CGPoint(x: length * 0.5, y: -hb * 0.95), CGPoint(x: 0, y: -hb * 0.6), CGPoint(x: -ha * 0.1, y: 0),
            ], tension: 0.55)
            var transform = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: atan2(dy, dx))
            return knob.copy(using: &transform) ?? knob
        }
        let inner = max(length - ha * 0.55 - hb * 0.6, r * 0.4)
        let waist = r * 0.74
        var points: [CGPoint] = []
        func add(_ x: CGFloat, _ y: CGFloat) { points.append(CGPoint(x: x, y: y)) }
        let x0 = ha * 0.55, x1 = x0 + inner
        add(x0 - ha * 0.1, ha * 0.95)
        add(x0 + inner * 0.25, waist)
        add(x0 + inner * 0.5, waist * 0.96)
        add(x0 + inner * 0.75, waist)
        add(x1 + hb * 0.1, hb * 0.95)
        if tuft {
            add(x1 + hb * 0.5, hb * 0.6)
            add(x1 + hb * 0.62, 0)
            add(x1 + hb * 0.5, -hb * 0.6)
        } else {
            add(x1 + hb * 0.52, hb * 0.5)
            add(x1 + hb * 0.4, 0)
            add(x1 + hb * 0.52, -hb * 0.5)
        }
        add(x1 + hb * 0.1, -hb * 0.95)
        add(x0 + inner * 0.75, -waist)
        add(x0 + inner * 0.5, -waist * 0.96)
        add(x0 + inner * 0.25, -waist)
        add(x0 - ha * 0.1, -ha * 0.95)
        add(x0 - ha * 0.5, -ha * 0.5)
        add(x0 - ha * 0.4, 0)
        add(x0 - ha * 0.5, ha * 0.5)
        var transform = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: atan2(dy, dx)).scaledBy(x: length / (x1 + hb * 0.62), y: 1)
        let path = Draw.smooth(points, tension: 0.45)
        return path.copy(using: &transform) ?? path
    }

    /// A small irregular carpal bone.
    static func carpal(at center: CGPoint, r: CGFloat, seed: Int) -> CGPath {
        Draw.smooth((0..<6).map { k in
            let a = CGFloat(k) / 6 * .pi * 2 + CGFloat(Anim.signed(k + seed * 7, 300)) * 0.2
            let rr = r * (0.85 + CGFloat(Anim.hash(k + seed * 7, 301)) * 0.3)
            return CGPoint(x: center.x + cos(a) * rr, y: center.y + sin(a) * rr * 0.9)
        }, tension: 0.6)
    }

    static func drawBones(_ c: CGContext, _ hand: HandGeometry) {
        let u = hand.u, o = hand.origin, wrist = hand.wrist
        let ink = Metal.ink
        func bone(_ path: CGPath, r: CGFloat, dim: Bool = false) {
            Draw.cel(c, path, base: dim ? Metal.boneShade : Metal.bone, shadow: dim ? Metal.boneDark : Metal.boneShade, core: dim ? nil : Metal.boneDark.withAlphaComponent(0.55), rim: dim ? nil : Metal.boneLight, ink: ink, width: 3, depth: r * 0.8)
        }
        let segments = hand.segments
        // Forearm: radius (thumb side) and ulna, with their knobs at the wrist.
        bone(Self.bone(from: CGPoint(x: o.x - u * 0.26, y: wrist.y - u * 1.25), to: CGPoint(x: o.x - u * 0.2, y: wrist.y + u * 0.02), r: u * 0.085, headA: 1.1, headB: 1.6), r: u * 0.085)
        bone(Self.bone(from: CGPoint(x: o.x + u * 0.24, y: wrist.y - u * 1.25), to: CGPoint(x: o.x + u * 0.19, y: wrist.y), r: u * 0.07, headA: 1.1, headB: 1.5), r: u * 0.07)
        // Fingers folded back behind the palm, dimmer, tucked under the knuckle in front.
        for s in segments where s.behind {
            let d = s.direction
            let from = CGPoint(x: s.from.x + d.x * s.radius * 1.2, y: s.from.y + d.y * s.radius * 1.2)
            bone(Self.bone(from: from, to: s.to, r: s.radius * 0.9, tuft: s.joint == 2), r: s.radius, dim: true)
        }
        // Carpals: eight small bones packed in two staggered rows at the wrist.
        let carpals: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.27, 0.12, 0.1), (-0.08, 0.09, 0.095), (0.1, 0.1, 0.085), (0.26, 0.15, 0.08),
            (-0.3, 0.32, 0.085), (-0.13, 0.3, 0.085), (0.06, 0.32, 0.11), (0.26, 0.34, 0.095),
        ]
        for (i, (x, y, r)) in carpals.enumerated() {
            bone(carpal(at: CGPoint(x: o.x + x * u, y: wrist.y + y * u), r: r * u, seed: i), r: r * u)
        }
        // Metacarpals fanning out of the carpals to the knuckles; the thumb's leads to the thumb's base.
        bone(Self.bone(from: CGPoint(x: o.x - u * 0.34, y: wrist.y + u * 0.42), to: hand.thumbBase, r: u * 0.075, headA: 1.1, headB: 1.4), r: u * 0.075)
        for finger in 0..<4 {
            let base = HandGeometry.bases[finger]
            bone(Self.bone(from: CGPoint(x: o.x + base * u * 0.45, y: wrist.y + u * 0.46), to: hand.knuckle(finger), r: u * 0.072, headA: 1.15, headB: 1.5), r: u * 0.072)
        }
        // Phalanges, little finger first so the index lies on top, the thumb last.
        for finger in [3, 2, 0, 1, 4] {
            for s in segments where s.finger == finger && !s.behind {
                bone(Self.bone(from: s.from, to: s.to, r: s.radius, headA: s.joint == 0 ? 1.25 : 1.2, headB: 1.2, tuft: s.joint == (finger == 4 ? 1 : 2)), r: s.radius)
            }
        }
        Draw.cracks(c, around: CGPoint(x: o.x - u * 0.2, y: wrist.y - u * 0.6), count: 2, length: u * 0.3, color: Metal.boneDark.withAlphaComponent(0.7), seed: 71)
    }

    // MARK: Flesh

    /// A hand with its skin on. `middle` overrides the middle finger.
    static func fleshHand(curl: CGFloat, middle: CGFloat? = nil, thumb: CGFloat = 0.1, key: String) -> SKTexture {
        Textures.make("flesh-\(key)", size: handSize) { c, _ in
            let hand = geometry { finger in
                if finger == 4 { return thumb }
                if finger == 1, let middle { return middle }
                return curl
            }
            drawFlesh(c, hand)
        }
    }

    static func drawFlesh(_ c: CGContext, _ hand: HandGeometry) {
        let u = hand.u
        let segments = hand.segments
        func skin(_ path: CGPath, depth: CGFloat) {
            Draw.cel(c, path, base: Metal.flesh, shadow: Metal.fleshShade, core: Metal.fleshDark.withAlphaComponent(0.5), rim: Metal.fleshLight, ink: Metal.ink, width: 3, depth: depth)
        }
        // A finger's skin: its visible segments as one shape.
        func fingerPath(_ finger: Int) -> CGPath {
            let path = CGMutablePath()
            for s in segments where s.finger == finger && !s.behind {
                path.addPath(Draw.capsule(from: s.from, to: s.to, radius: s.radius * 1.5))
                if s.joint == 0 && s.pitch > 0.6 {
                    // A knuckle at the fold.
                    path.addPath(Draw.circle(at: s.to, r: s.radius * 1.7))
                }
            }
            return path.normalized(using: .winding)
        }
        skin(hand.forearmPath, depth: u * 0.14)
        skin(hand.palmPath, depth: u * 0.16)
        // Tendons on the back of the hand.
        for finger in 0..<4 {
            let k = hand.knuckle(finger)
            let tendon = CGMutablePath()
            tendon.move(to: CGPoint(x: hand.origin.x + HandGeometry.bases[finger] * u * 0.5, y: hand.wrist.y + u * 0.45))
            tendon.addQuadCurve(to: CGPoint(x: k.x, y: k.y - u * 0.12), control: CGPoint(x: k.x - HandGeometry.bases[finger] * u * 0.1, y: hand.origin.y))
            Draw.stroke(c, tendon, Metal.fleshShade.withAlphaComponent(0.35), width: 3)
        }
        for finger in [3, 2, 0, 1, 4] {
            let path = fingerPath(finger)
            skin(path, depth: u * 0.1)
            c.saveGState()
            c.addPath(path)
            c.clip()
            for s in segments where s.finger == finger && !s.behind {
                let d = s.direction
                let n = CGPoint(x: -d.y, y: d.x)
                let r = s.radius * 1.5
                if s.joint > 0 {
                    // The crease at the joint: a short arc across the finger.
                    let crease = CGMutablePath()
                    crease.move(to: CGPoint(x: s.from.x + n.x * r * 0.75, y: s.from.y + n.y * r * 0.75))
                    crease.addQuadCurve(to: CGPoint(x: s.from.x - n.x * r * 0.75, y: s.from.y - n.y * r * 0.75), control: CGPoint(x: s.from.x + d.x * r * 0.45, y: s.from.y + d.y * r * 0.45))
                    Draw.stroke(c, crease, Metal.fleshDark.withAlphaComponent(0.6), width: 2.5)
                }
                if s.joint == 0 && s.pitch > 0.6 {
                    // Folded: the knuckle bump with its shadow under it and a highlight on top.
                    let under = CGMutablePath()
                    under.addArc(center: s.to, radius: s.radius * 1.5, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
                    Draw.stroke(c, under, Metal.fleshDark.withAlphaComponent(0.55), width: 3)
                    Draw.fill(c, Draw.ellipse(at: CGPoint(x: s.to.x - s.radius * 0.3, y: s.to.y + s.radius * 0.5), rx: s.radius * 0.6, ry: s.radius * 0.35), Metal.fleshLight.withAlphaComponent(0.7))
                }
                let last = s.joint == (finger == 4 ? 1 : 2)
                if last && s.pitch < 1.2 {
                    // The nail, on the back of the fingertip.
                    c.saveGState()
                    c.translateBy(x: s.to.x - d.x * s.radius * 0.95, y: s.to.y - d.y * s.radius * 0.95)
                    c.rotate(by: atan2(d.y, d.x))
                    let nail = Draw.smooth([CGPoint(x: -s.radius * 0.7, y: s.radius * 0.72), CGPoint(x: s.radius * 0.55, y: s.radius * 0.62), CGPoint(x: s.radius * 0.8, y: 0), CGPoint(x: s.radius * 0.55, y: -s.radius * 0.62), CGPoint(x: -s.radius * 0.7, y: -s.radius * 0.72)], tension: 0.5)
                    Draw.cel(c, nail, base: UIColor(red: 0.98, green: 0.86, blue: 0.82, alpha: 1), shadow: UIColor(red: 0.85, green: 0.62, blue: 0.6, alpha: 1), rim: nil, ink: Metal.ink.withAlphaComponent(0.8), width: 2, depth: s.radius * 0.4, light: CGVector(dx: -0.8, dy: 0.5))
                    Draw.fill(c, Draw.ellipse(at: CGPoint(x: -s.radius * 0.25, y: s.radius * 0.3), rx: s.radius * 0.22, ry: s.radius * 0.14), UIColor.white.withAlphaComponent(0.6))
                    c.restoreGState()
                }
            }
            c.restoreGState()
        }
        // Knuckle creases on the back of the hand where straight fingers start.
        for finger in 0..<4 where hand.curl(finger) < 0.6 {
            let k = hand.knuckle(finger)
            let crease = CGMutablePath()
            crease.move(to: CGPoint(x: k.x - u * 0.06, y: k.y - u * 0.02))
            crease.addQuadCurve(to: CGPoint(x: k.x + u * 0.06, y: k.y - u * 0.02), control: CGPoint(x: k.x, y: k.y - u * 0.07))
            Draw.stroke(c, crease, Metal.fleshDark.withAlphaComponent(0.5), width: 2.5)
        }
    }

    /// A studded leather band round the wrist, for the fist.
    static let wristbandSize = CGSize(width: 260, height: 110)

    static var wristband: SKTexture { Textures.make("wristband", size: wristbandSize) { c, size in
        let band = CGPath(roundedRect: CGRect(x: 20, y: 20, width: size.width - 40, height: 70), cornerWidth: 14, cornerHeight: 14, transform: nil)
        Draw.cel(c, band, base: UIColor(white: 0.2, alpha: 1), shadow: UIColor(white: 0.08, alpha: 1), rim: UIColor(white: 0.4, alpha: 1), width: 3, depth: 16)
        for i in 0..<5 {
            let cx = 45 + CGFloat(i) * 42.5
            let stud = Draw.polygon([CGPoint(x: cx - 15, y: 38), CGPoint(x: cx + 15, y: 38), CGPoint(x: cx + 9, y: 72), CGPoint(x: cx - 9, y: 72)])
            Draw.cel(c, stud, base: Metal.bone, shadow: Metal.boneShade, rim: .white, width: 2.5, depth: 9)
            Draw.fill(c, Draw.ellipse(at: CGPoint(x: cx - 4, y: 60), rx: 4, ry: 2.5), UIColor.white.withAlphaComponent(0.9))
        }
    } }

    // MARK: Skinning

    /// The skin peeled off: flesh outside, raw inside, hanging from its top edge.
    static let skinFlapSize = CGSize(width: 300, height: 440)

    static var skinFlap: SKTexture { Textures.make("skin-flap", size: skinFlapSize) { c, size in
        let top = size.height - 10
        let flap = Draw.smooth([CGPoint(x: 20, y: top), CGPoint(x: 280, y: top), CGPoint(x: 265, y: top - 180), CGPoint(x: 200, y: 40), CGPoint(x: 120, y: 20), CGPoint(x: 60, y: 120), CGPoint(x: 30, y: top - 160)], tension: 0.5)
        Draw.cel(c, flap, base: Metal.blood, shadow: Metal.bloodDark, rim: Metal.bloodBright, width: 3, depth: 30)
        c.saveGState()
        c.addPath(flap)
        c.clip()
        for i in 0..<12 {
            let vein = CGMutablePath()
            let x = 40 + CGFloat(Anim.hash(i, 80)) * 220
            vein.move(to: CGPoint(x: x, y: top))
            vein.addCurve(to: CGPoint(x: x + CGFloat(Anim.signed(i, 81)) * 60, y: 30 + CGFloat(Anim.hash(i, 82)) * 150), control1: CGPoint(x: x - 30, y: top - 120), control2: CGPoint(x: x + 40, y: top - 240))
            Draw.stroke(c, vein, Metal.bloodDark.withAlphaComponent(0.8), width: 2 + CGFloat(Anim.hash(i, 83)) * 2)
        }
        // Fat and the skin's edge curling back.
        for i in 0..<9 {
            let p = CGPoint(x: 60 + CGFloat(Anim.hash(i, 84)) * 180, y: 80 + CGFloat(Anim.hash(i, 85)) * 250)
            Draw.fill(c, Draw.ellipse(at: p, rx: 8 + CGFloat(Anim.hash(i, 86)) * 10, ry: 6 + CGFloat(Anim.hash(i, 87)) * 6), UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 0.7))
        }
        c.restoreGState()
        Draw.stroke(c, flap, Metal.flesh, width: 10)
        Draw.stroke(c, flap, Metal.ink, width: 3)
    } }

    /// A dagger, point to the right, anchored at its middle.
    static let knifeSize = CGSize(width: 400, height: 90)

    static var knife: SKTexture { Textures.make("knife", size: knifeSize) { c, size in
        let mid = size.height / 2
        let blade = Draw.polygon([CGPoint(x: 150, y: mid + 18), CGPoint(x: 340, y: mid + 14), CGPoint(x: 395, y: mid), CGPoint(x: 340, y: mid - 18), CGPoint(x: 150, y: mid - 18)])
        Draw.cel(c, blade, base: UIColor(white: 0.85, alpha: 1), shadow: UIColor(white: 0.55, alpha: 1), core: UIColor(white: 0.35, alpha: 1), rim: .white, width: 3, depth: 14, light: CGVector(dx: 0, dy: 1))
        let edge = CGMutablePath()
        edge.move(to: CGPoint(x: 150, y: mid - 14))
        edge.addLine(to: CGPoint(x: 385, y: mid - 2))
        Draw.stroke(c, edge, UIColor.white.withAlphaComponent(0.9), width: 2.5)
        let fuller = CGMutablePath()
        fuller.move(to: CGPoint(x: 160, y: mid + 4))
        fuller.addLine(to: CGPoint(x: 320, y: mid + 4))
        Draw.stroke(c, fuller, UIColor(white: 0.4, alpha: 0.7), width: 3)
        let guardPath = CGPath(roundedRect: CGRect(x: 138, y: mid - 32, width: 16, height: 64), cornerWidth: 4, cornerHeight: 4, transform: nil)
        Draw.cel(c, guardPath, base: Metal.boneShade, shadow: Metal.boneDark, width: 3, depth: 6)
        let handle = CGPath(roundedRect: CGRect(x: 10, y: mid - 15, width: 130, height: 30), cornerWidth: 10, cornerHeight: 10, transform: nil)
        Draw.cel(c, handle, base: UIColor(white: 0.22, alpha: 1), shadow: UIColor(white: 0.06, alpha: 1), rim: UIColor(white: 0.45, alpha: 1), width: 3, depth: 10)
        for i in 0..<4 {
            Draw.fill(c, Draw.circle(at: CGPoint(x: 35 + CGFloat(i) * 28, y: mid), r: 4), Metal.boneShade)
        }
        Draw.cel(c, Draw.circle(at: CGPoint(x: 16, y: mid), r: 13), base: Metal.boneShade, shadow: Metal.boneDark, width: 3, depth: 6)
    } }

    /// A blood drop, point up, for splatter and the cut.
    static var bloodDrop: SKTexture { Textures.make("blood-drop", size: CGSize(width: 60, height: 80)) { c, size in
        let drop = CGMutablePath()
        drop.move(to: CGPoint(x: 30, y: 76))
        drop.addCurve(to: CGPoint(x: 30, y: 4), control1: CGPoint(x: 62, y: 36), control2: CGPoint(x: 58, y: 4))
        drop.addCurve(to: CGPoint(x: 30, y: 76), control1: CGPoint(x: 2, y: 4), control2: CGPoint(x: -2, y: 36))
        drop.closeSubpath()
        Draw.cel(c, drop, base: Metal.bloodBright, shadow: Metal.blood, core: Metal.bloodDark, rim: nil, width: 3, depth: 10)
        Draw.fill(c, Draw.ellipse(at: CGPoint(x: 21, y: 30), rx: 5, ry: 8), UIColor.white.withAlphaComponent(0.7))
    } }

    // MARK: Skull

    static let skullSize = CGSize(width: 300, height: 340)

    /// A skull facing the viewer; `variant` tilts and changes the damage.
    static func skull(_ variant: Int = 0) -> SKTexture {
        Textures.make("skull-\(variant)", size: skullSize) { c, size in
            c.saveGState()
            c.translateBy(x: size.width / 2, y: size.height / 2)
            c.rotate(by: CGFloat(Anim.signed(variant, 90)) * 0.25)
            c.translateBy(x: -size.width / 2, y: -size.height / 2)
            drawSkull(c, size: size, variant: variant)
            c.restoreGState()
        }
    }

    static func drawSkull(_ c: CGContext, size: CGSize, variant: Int) {
        let cx = size.width / 2
        let bone = { (path: CGPath, depth: CGFloat) in
            Draw.cel(c, path, base: Metal.bone, shadow: Metal.boneShade, core: Metal.boneDark.withAlphaComponent(0.5), rim: Metal.boneLight, width: 3.5, depth: depth)
        }
        // The lower jaw first, then the cranium over it.
        let jaw = Draw.smooth([CGPoint(x: cx - 78, y: 130), CGPoint(x: cx + 78, y: 130), CGPoint(x: cx + 66, y: 60), CGPoint(x: cx + 30, y: 22), CGPoint(x: cx - 30, y: 22), CGPoint(x: cx - 66, y: 60)], tension: 0.45)
        bone(jaw, 26)
        // Cranium: a big dome, the cheekbones flaring, narrowing to the upper jaw.
        let cranium = Draw.smooth([
            CGPoint(x: cx - 52, y: 92), CGPoint(x: cx + 52, y: 92), CGPoint(x: cx + 72, y: 118), CGPoint(x: cx + 118, y: 150), CGPoint(x: cx + 126, y: 215),
            CGPoint(x: cx + 110, y: 290), CGPoint(x: cx + 55, y: 332), CGPoint(x: cx - 55, y: 332), CGPoint(x: cx - 110, y: 290),
            CGPoint(x: cx - 126, y: 215), CGPoint(x: cx - 118, y: 150), CGPoint(x: cx - 72, y: 118),
        ], tension: 0.5)
        bone(cranium, 40)
        // Teeth: the upper row hangs from the cranium's edge, the lower stands on the jaw.
        for i in 0..<7 {
            let x = cx - 54 + CGFloat(i) * 18
            let upper = Draw.smooth([CGPoint(x: x - 7, y: 118), CGPoint(x: x + 7, y: 118), CGPoint(x: x + 6, y: 96), CGPoint(x: x, y: 90), CGPoint(x: x - 6, y: 96)], tension: 0.3)
            Draw.cel(c, upper, base: Metal.bone, shadow: Metal.boneShade, width: 2, depth: 5)
            let lower = Draw.smooth([CGPoint(x: x - 6, y: 62), CGPoint(x: x + 6, y: 62), CGPoint(x: x + 5, y: 86), CGPoint(x: x, y: 90), CGPoint(x: x - 5, y: 86)], tension: 0.3)
            Draw.cel(c, lower, base: Metal.boneShade, shadow: Metal.boneDark, width: 2, depth: 5)
        }
        // The gap between the rows.
        let gap = CGMutablePath()
        gap.move(to: CGPoint(x: cx - 60, y: 90))
        gap.addLine(to: CGPoint(x: cx + 60, y: 90))
        Draw.stroke(c, gap, Metal.ink, width: 3)
        // Eye sockets: deep, with the brow's shadow across the top.
        for s in [CGFloat(-1), 1] {
            let socket = Draw.smooth([CGPoint(x: cx + s * 20, y: 190), CGPoint(x: cx + s * 60, y: 170), CGPoint(x: cx + s * 92, y: 195), CGPoint(x: cx + s * 85, y: 240), CGPoint(x: cx + s * 40, y: 245)], tension: 0.5)
            Draw.fill(c, socket, Metal.ink)
            Draw.fill(c, socket.subtracting(Draw.translated(socket, s * 6, -14), using: .winding), UIColor(white: 0.18, alpha: 1))
            Draw.stroke(c, socket, Metal.ink, width: 3)
            // Cheekbone under the socket and the temple line.
            let cheek = CGMutablePath()
            cheek.move(to: CGPoint(x: cx + s * 118, y: 150))
            cheek.addQuadCurve(to: CGPoint(x: cx + s * 66, y: 130), control: CGPoint(x: cx + s * 92, y: 128))
            Draw.stroke(c, cheek, Metal.boneDark.withAlphaComponent(0.7), width: 3)
            let temple = CGMutablePath()
            temple.move(to: CGPoint(x: cx + s * 95, y: 275))
            temple.addQuadCurve(to: CGPoint(x: cx + s * 118, y: 210), control: CGPoint(x: cx + s * 118, y: 255))
            Draw.stroke(c, temple, Metal.boneDark.withAlphaComponent(0.5), width: 2.5)
        }
        // Nasal cavity: an upside-down heart.
        let nose = Draw.smooth([CGPoint(x: cx, y: 172), CGPoint(x: cx + 16, y: 150), CGPoint(x: cx + 14, y: 130), CGPoint(x: cx, y: 126), CGPoint(x: cx - 14, y: 130), CGPoint(x: cx - 16, y: 150)], tension: 0.5)
        Draw.fill(c, nose, Metal.ink)
        Draw.stroke(c, nose, Metal.ink, width: 3)
        let brow = CGMutablePath()
        brow.move(to: CGPoint(x: cx - 100, y: 232))
        brow.addQuadCurve(to: CGPoint(x: cx + 100, y: 232), control: CGPoint(x: cx, y: 262))
        Draw.stroke(c, brow, Metal.boneDark.withAlphaComponent(0.5), width: 3)
        let crackSeed = 90 + variant * 3
        Draw.cracks(c, around: CGPoint(x: cx + CGFloat(Anim.signed(variant, 91)) * 70, y: 290), count: 2 + variant % 2, length: 60, color: Metal.ink.withAlphaComponent(0.8), seed: crackSeed)
        if variant % 3 == 2 {
            // A hole knocked in the side.
            let hole = Draw.smooth([CGPoint(x: cx + 60, y: 300), CGPoint(x: cx + 95, y: 290), CGPoint(x: cx + 92, y: 258), CGPoint(x: cx + 62, y: 262)], tension: 0.4)
            Draw.fill(c, hole, Metal.ink)
            Draw.stroke(c, hole, Metal.ink, width: 3)
        }
    }
}
