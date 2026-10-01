import SpriteKit
import UIKit

/// A hand, palm to the viewer, from the same joints whether bone or flesh.
/// The origin is the middle of the palm; `u` is the palm's width. Fingers are
/// 0 (index) to 3 (little), the thumb is 4.
struct HandGeometry {
    struct Bone {
        var from: CGPoint
        var to: CGPoint
        var radius: CGFloat
        var finger: Int
        var joint: Int
    }

    var u: CGFloat
    var origin: CGPoint
    /// Per finger, radians: 0 straight, positive curls toward the palm.
    var curl: (Int) -> CGFloat

    var palm: CGRect { CGRect(x: origin.x - u / 2, y: origin.y - u * 0.6, width: u, height: u * 1.15) }
    var wrist: CGPoint { CGPoint(x: origin.x, y: palm.minY) }

    static let bases: [CGFloat] = [-0.34, -0.11, 0.12, 0.35]
    static let lengths: [CGFloat] = [0.95, 1.05, 0.95, 0.72]
    static let spreads: [CGFloat] = [0.14, 0.04, -0.05, -0.17]

    var bones: [Bone] {
        var bones: [Bone] = []
        for finger in 0..<4 {
            var point = CGPoint(x: origin.x + Self.bases[finger] * u, y: palm.maxY)
            var angle = CGFloat.pi / 2 + Self.spreads[finger]
            let c = curl(finger)
            if c >= 0.75 {
                // Folded into a fist: only the knuckle shows, as a short stub.
                let next = CGPoint(x: point.x + cos(angle) * 0.3 * u, y: point.y + sin(angle) * 0.3 * u)
                bones.append(Bone(from: point, to: next, radius: u * 0.1, finger: finger, joint: 0))
                continue
            }
            for (joint, share) in [CGFloat(0.42), 0.32, 0.26].enumerated() {
                angle -= c * (joint == 0 ? 0.6 : 1)
                let next = CGPoint(x: point.x + cos(angle) * Self.lengths[finger] * share * u, y: point.y + sin(angle) * Self.lengths[finger] * share * u)
                bones.append(Bone(from: point, to: next, radius: u * (0.085 - CGFloat(joint) * 0.012), finger: finger, joint: joint))
                point = next
            }
        }
        var point = CGPoint(x: palm.minX + u * 0.05, y: origin.y - u * 0.1)
        var angle = CGFloat(2.45) - curl(4)
        for (joint, length) in [CGFloat(0.5), 0.4].enumerated() {
            angle -= curl(4) * CGFloat(joint)
            let next = CGPoint(x: point.x + cos(angle) * length * u, y: point.y + sin(angle) * length * u)
            bones.append(Bone(from: point, to: next, radius: u * (0.1 - CGFloat(joint) * 0.015), finger: 4, joint: joint))
            point = next
        }
        return bones
    }

    /// The whole hand with skin on, as one silhouette.
    func fleshPath() -> CGPath {
        let path = CGMutablePath()
        path.addPath(CGPath(roundedRect: palm.insetBy(dx: -u * 0.06, dy: -u * 0.04), cornerWidth: u * 0.22, cornerHeight: u * 0.22, transform: nil))
        for bone in bones {
            path.addPath(Draw.capsule(from: bone.from, to: bone.to, radius: bone.radius * 1.55))
        }
        path.addPath(CGPath(roundedRect: CGRect(x: origin.x - u * 0.3, y: palm.minY - u * 0.95, width: u * 0.6, height: u * 1.05), cornerWidth: u * 0.15, cornerHeight: u * 0.15, transform: nil))
        return path
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

    /// A skeleton hand: `curl` 0 is open, 1 is a fist. Flicking fingers cycle a few of these.
    static func skeletonHand(curl: CGFloat, thumb: CGFloat = 0.1, key: String) -> SKTexture {
        Textures.make("skeleton-\(key)", size: handSize) { c, _ in
            let hand = geometry { $0 == 4 ? thumb : curl }
            drawBones(c, hand)
        }
    }

    static func drawBones(_ c: CGContext, _ hand: HandGeometry) {
        let u = hand.u, o = hand.origin
        let light = CGPoint(x: o.x - u * 0.4, y: o.y + u * 0.6)
        func bone(_ path: CGPath) {
            Draw.shadowed(c, blur: 6, offset: CGSize(width: 2, height: -4)) {
                Draw.shade(c, path, [Metal.bone, Metal.boneShade, Metal.boneDark], from: CGPoint(x: light.x, y: light.y), to: CGPoint(x: o.x + u * 0.7, y: o.y - u * 1.6))
            }
            Draw.stroke(c, path, Metal.boneDark.withAlphaComponent(0.7), width: 1.5)
        }
        // Forearm: radius and ulna with their knobs.
        bone(Draw.capsule(from: CGPoint(x: o.x - u * 0.2, y: hand.palm.minY), to: CGPoint(x: o.x - u * 0.24, y: hand.palm.minY - u * 1.2), radius: u * 0.085))
        bone(Draw.capsule(from: CGPoint(x: o.x + u * 0.18, y: hand.palm.minY), to: CGPoint(x: o.x + u * 0.22, y: hand.palm.minY - u * 1.2), radius: u * 0.07))
        bone(Draw.circle(at: CGPoint(x: o.x - u * 0.2, y: hand.palm.minY - u * 0.02), r: u * 0.12))
        bone(Draw.circle(at: CGPoint(x: o.x + u * 0.18, y: hand.palm.minY - u * 0.02), r: u * 0.1))
        // Carpals: a cluster of knobs.
        for i in 0..<7 {
            let x = o.x + CGFloat(i - 3) * u * 0.14 + CGFloat(Anim.signed(i, 70)) * u * 0.02
            let y = hand.palm.minY + u * 0.14 + CGFloat(i % 2) * u * 0.14
            bone(Draw.circle(at: CGPoint(x: x, y: y), r: u * 0.085))
        }
        // Metacarpals fanning out of the wrist.
        for base in HandGeometry.bases {
            let top = CGPoint(x: o.x + base * u, y: hand.palm.maxY)
            bone(Draw.capsule(from: CGPoint(x: o.x + base * u * 0.4, y: hand.palm.minY + u * 0.3), to: top, radius: u * 0.065))
        }
        for b in hand.bones {
            bone(Draw.capsule(from: b.from, to: b.to, radius: b.radius))
            bone(Draw.circle(at: b.from, r: b.radius * 1.15))
            Draw.fill(c, Draw.circle(at: b.from, r: b.radius * 0.45), Metal.boneDark.withAlphaComponent(0.35))
        }
        Draw.cracks(c, around: CGPoint(x: o.x + u * 0.1, y: hand.palm.midY), count: 3, length: u * 0.5, color: Metal.boneDark.withAlphaComponent(0.6), seed: 71)
    }

    // MARK: Flesh

    /// A hand with its skin on. `raise` lifts the middle finger out of a fist.
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
        let u = hand.u, o = hand.origin
        let path = hand.fleshPath()
        Draw.shadowed(c, blur: 18, offset: CGSize(width: 0, height: -10), color: UIColor.black.withAlphaComponent(0.75)) {
            Draw.fill(c, path, Metal.fleshShade)
        }
        // A tight dark shadow all round is the outline of the whole silhouette.
        Draw.shadowed(c, blur: 3, offset: .zero, color: Metal.fleshShade) {
            Draw.shade(c, path, [UIColor(red: 0.96, green: 0.78, blue: 0.64, alpha: 1), Metal.flesh, Metal.fleshShade], from: CGPoint(x: o.x - u * 0.6, y: o.y + u * 1.4), to: CGPoint(x: o.x + u * 0.8, y: o.y - u * 1.2))
        }
        c.saveGState()
        c.addPath(path)
        c.clip()
        // Shadow where the fingers meet the palm, knuckle creases and nails.
        for b in hand.bones where b.joint > 0 {
            let dx = b.to.x - b.from.x, dy = b.to.y - b.from.y
            let len = max(hypot(dx, dy), 0.001)
            let crease = CGMutablePath()
            crease.move(to: CGPoint(x: b.from.x - dy / len * b.radius * 1.2, y: b.from.y + dx / len * b.radius * 1.2))
            crease.addQuadCurve(to: CGPoint(x: b.from.x + dy / len * b.radius * 1.2, y: b.from.y - dx / len * b.radius * 1.2), control: CGPoint(x: b.from.x + dx / len * b.radius * 0.5, y: b.from.y + dy / len * b.radius * 0.5))
            Draw.stroke(c, crease, Metal.fleshShade.withAlphaComponent(0.6), width: 3)
        }
        // Knuckles of the folded fingers.
        for b in hand.bones where b.finger < 4 && b.joint == 0 && hand.curl(b.finger) >= 0.75 {
            let crease = CGMutablePath()
            crease.addArc(center: b.to, radius: b.radius * 0.9, startAngle: 0.2, endAngle: .pi - 0.2, clockwise: false)
            Draw.stroke(c, crease, Metal.fleshShade.withAlphaComponent(0.7), width: 3)
            Draw.fill(c, Draw.ellipse(at: CGPoint(x: b.to.x, y: b.to.y + b.radius * 0.2), rx: b.radius * 0.6, ry: b.radius * 0.35), UIColor.white.withAlphaComponent(0.25))
        }
        for b in hand.bones where b.joint == (b.finger == 4 ? 1 : 2) {
            let dx = b.to.x - b.from.x, dy = b.to.y - b.from.y
            let len = max(hypot(dx, dy), 0.001)
            let nailCenter = CGPoint(x: b.to.x - dx / len * b.radius * 0.6, y: b.to.y - dy / len * b.radius * 0.6)
            c.saveGState()
            c.translateBy(x: nailCenter.x, y: nailCenter.y)
            c.rotate(by: atan2(dy, dx))
            let nail = Draw.ellipse(at: .zero, rx: b.radius * 1.0, ry: b.radius * 0.75)
            Draw.sphere(c, nail, [UIColor(red: 1, green: 0.9, blue: 0.85, alpha: 1), UIColor(red: 0.9, green: 0.7, blue: 0.65, alpha: 1)], light: CGPoint(x: -b.radius * 0.3, y: b.radius * 0.2), radius: b.radius * 1.3)
            Draw.stroke(c, nail, Metal.fleshShade.withAlphaComponent(0.7), width: 1.5)
            c.restoreGState()
        }
        // Palm lines.
        for (i, line) in [(CGPoint(x: -0.35, y: 0.35), CGPoint(x: 0.3, y: 0.05)), (CGPoint(x: -0.4, y: 0.1), CGPoint(x: 0.35, y: -0.3)), (CGPoint(x: -0.1, y: -0.5), CGPoint(x: 0.3, y: -0.05))].enumerated() {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: o.x + line.0.x * u, y: o.y + line.0.y * u))
            path.addQuadCurve(to: CGPoint(x: o.x + line.1.x * u, y: o.y + line.1.y * u), control: CGPoint(x: o.x + (line.0.x + line.1.x) / 2 * u, y: o.y + (line.0.y + line.1.y) / 2 * u - u * 0.08 * CGFloat(i + 1)))
            Draw.stroke(c, path, Metal.fleshShade.withAlphaComponent(0.5), width: 2.5)
        }
        c.restoreGState()
    }

    /// A studded leather band round the wrist, for the fist.
    static let wristbandSize = CGSize(width: 260, height: 110)

    static var wristband: SKTexture { Textures.make("wristband", size: wristbandSize) { c, size in
        let band = CGPath(roundedRect: CGRect(x: 20, y: 20, width: size.width - 40, height: 70), cornerWidth: 14, cornerHeight: 14, transform: nil)
        Draw.shadowed(c, blur: 8, offset: CGSize(width: 0, height: -4)) {
            Draw.shade(c, band, [UIColor(white: 0.22, alpha: 1), UIColor(white: 0.05, alpha: 1)], from: CGPoint(x: 0, y: 90), to: CGPoint(x: 0, y: 20))
        }
        for i in 0..<5 {
            let cx = 45 + CGFloat(i) * 42.5
            let stud = Draw.polygon([CGPoint(x: cx - 16, y: 40), CGPoint(x: cx + 16, y: 40), CGPoint(x: cx + 10, y: 72), CGPoint(x: cx - 10, y: 72)])
            Draw.shade(c, stud, [Metal.bone, Metal.boneShade, Metal.boneDark], from: CGPoint(x: cx - 16, y: 72), to: CGPoint(x: cx + 16, y: 40))
            Draw.fill(c, Draw.circle(at: CGPoint(x: cx - 5, y: 60), r: 3), UIColor.white.withAlphaComponent(0.8))
        }
    } }

    // MARK: Skinning

    /// The skin peeled off: flesh outside, raw inside, hanging from its top edge.
    static let skinFlapSize = CGSize(width: 300, height: 440)

    static var skinFlap: SKTexture { Textures.make("skin-flap", size: skinFlapSize) { c, size in
        let top = size.height - 10
        let flap = Draw.smooth([CGPoint(x: 20, y: top), CGPoint(x: 280, y: top), CGPoint(x: 265, y: top - 180), CGPoint(x: 200, y: 40), CGPoint(x: 120, y: 20), CGPoint(x: 60, y: 120), CGPoint(x: 30, y: top - 160)], tension: 0.5)
        Draw.shadowed(c, blur: 14, offset: CGSize(width: 0, height: -8), color: UIColor.black.withAlphaComponent(0.8)) {
            Draw.shade(c, flap, [Metal.bloodBright, Metal.blood, Metal.bloodDark], from: CGPoint(x: 0, y: top), to: CGPoint(x: 0, y: 0))
        }
        c.saveGState()
        c.addPath(flap)
        c.clip()
        for i in 0..<14 {
            let vein = CGMutablePath()
            let x = 40 + CGFloat(Anim.hash(i, 80)) * 220
            vein.move(to: CGPoint(x: x, y: top))
            vein.addCurve(to: CGPoint(x: x + CGFloat(Anim.signed(i, 81)) * 60, y: 30 + CGFloat(Anim.hash(i, 82)) * 150), control1: CGPoint(x: x - 30, y: top - 120), control2: CGPoint(x: x + 40, y: top - 240))
            Draw.stroke(c, vein, UIColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 0.6), width: 2 + CGFloat(Anim.hash(i, 83)) * 2)
        }
        c.restoreGState()
        // The skin side curls back along the edges.
        Draw.stroke(c, flap, Metal.flesh, width: 9)
        Draw.stroke(c, flap, Metal.fleshShade.withAlphaComponent(0.8), width: 2)
    } }

    /// A dagger, point to the right, anchored at its middle.
    static let knifeSize = CGSize(width: 400, height: 90)

    static var knife: SKTexture { Textures.make("knife", size: knifeSize) { c, size in
        let mid = size.height / 2
        let blade = Draw.polygon([CGPoint(x: 150, y: mid + 18), CGPoint(x: 340, y: mid + 14), CGPoint(x: 395, y: mid), CGPoint(x: 340, y: mid - 18), CGPoint(x: 150, y: mid - 18)])
        Draw.shadowed(c, blur: 10, offset: CGSize(width: 0, height: -5)) {
            Draw.shade(c, blade, [.white, Metal.bone, Metal.boneShade, UIColor(white: 0.5, alpha: 1)], from: CGPoint(x: 0, y: mid + 18), to: CGPoint(x: 0, y: mid - 18))
        }
        let edge = CGMutablePath()
        edge.move(to: CGPoint(x: 150, y: mid - 16))
        edge.addLine(to: CGPoint(x: 385, y: mid - 2))
        Draw.stroke(c, edge, UIColor.white.withAlphaComponent(0.9), width: 2)
        let fuller = CGMutablePath()
        fuller.move(to: CGPoint(x: 160, y: mid + 4))
        fuller.addLine(to: CGPoint(x: 320, y: mid + 4))
        Draw.stroke(c, fuller, UIColor(white: 0.4, alpha: 0.5), width: 3)
        let guardPath = CGPath(roundedRect: CGRect(x: 138, y: mid - 32, width: 16, height: 64), cornerWidth: 4, cornerHeight: 4, transform: nil)
        Draw.shade(c, guardPath, [Metal.boneShade, Metal.boneDark], from: CGPoint(x: 138, y: 0), to: CGPoint(x: 154, y: 0))
        let handle = CGPath(roundedRect: CGRect(x: 10, y: mid - 15, width: 130, height: 30), cornerWidth: 10, cornerHeight: 10, transform: nil)
        Draw.shade(c, handle, [UIColor(white: 0.25, alpha: 1), UIColor(white: 0.02, alpha: 1)], from: CGPoint(x: 0, y: mid + 15), to: CGPoint(x: 0, y: mid - 15))
        for i in 0..<4 {
            Draw.fill(c, Draw.circle(at: CGPoint(x: 35 + CGFloat(i) * 28, y: mid), r: 4), Metal.boneShade)
        }
        Draw.fill(c, Draw.circle(at: CGPoint(x: 14, y: mid), r: 12), Metal.boneDark)
    } }

    // MARK: Skull

    static let skullSize = CGSize(width: 300, height: 340)

    static var skull: SKTexture { Textures.make("skull", size: skullSize) { c, size in
        let cx = size.width / 2
        let cranium = Draw.smooth([CGPoint(x: cx - 125, y: 200), CGPoint(x: cx - 100, y: 300), CGPoint(x: cx, y: 335), CGPoint(x: cx + 100, y: 300), CGPoint(x: cx + 125, y: 200), CGPoint(x: cx + 95, y: 120), CGPoint(x: cx + 60, y: 105), CGPoint(x: cx - 60, y: 105), CGPoint(x: cx - 95, y: 120)], tension: 0.5)
        Draw.shadowed(c, blur: 14, offset: CGSize(width: 0, height: -8), color: UIColor.black.withAlphaComponent(0.8)) {
            Draw.sphere(c, cranium, [Metal.bone, Metal.boneShade, Metal.boneDark], light: CGPoint(x: cx - 50, y: 270), radius: 220)
        }
        // Jaw.
        let jaw = Draw.smooth([CGPoint(x: cx - 70, y: 115), CGPoint(x: cx + 70, y: 115), CGPoint(x: cx + 60, y: 40), CGPoint(x: cx + 25, y: 15), CGPoint(x: cx - 25, y: 15), CGPoint(x: cx - 60, y: 40)], tension: 0.4)
        Draw.shade(c, jaw, [Metal.boneShade, Metal.boneDark], from: CGPoint(x: 0, y: 115), to: CGPoint(x: 0, y: 15))
        // Teeth: upper row on the cranium's edge, lower row on the jaw.
        for i in 0..<7 {
            let x = cx - 54 + CGFloat(i) * 18
            Draw.fill(c, CGPath(roundedRect: CGRect(x: x - 7, y: 95, width: 14, height: 26), cornerWidth: 3, cornerHeight: 3, transform: nil), Metal.bone)
            Draw.fill(c, CGPath(roundedRect: CGRect(x: x - 6, y: 62, width: 12, height: 24), cornerWidth: 3, cornerHeight: 3, transform: nil), Metal.boneShade)
        }
        // Eye sockets, nose, cheekbone shadows.
        for s in [CGFloat(-1), 1] {
            let socket = Draw.ellipse(at: CGPoint(x: cx + s * 52, y: 205), rx: 40, ry: 34)
            Draw.sphere(c, socket, [.black, UIColor(white: 0.1, alpha: 1), Metal.boneDark], light: CGPoint(x: cx + s * 52, y: 200), radius: 44)
            Draw.fill(c, Draw.ellipse(at: CGPoint(x: cx + s * 100, y: 150), rx: 22, ry: 14), Metal.boneDark.withAlphaComponent(0.5))
        }
        let nose = Draw.polygon([CGPoint(x: cx - 16, y: 150), CGPoint(x: cx + 16, y: 150), CGPoint(x: cx + 10, y: 125), CGPoint(x: cx - 10, y: 125)])
        Draw.fill(c, nose, .black)
        Draw.cracks(c, around: CGPoint(x: cx + 60, y: 290), count: 3, length: 70, color: Metal.boneDark, seed: 90)
    } }
}
