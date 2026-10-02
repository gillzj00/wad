import SpriteKit
import UIKit

/// The creatures of the shows, drawn once into textures: layered paths with
/// cel shading from the top left, fur and feather strokes, ink outlines.
/// Coordinates in the drawings are y up, like SpriteKit.
@MainActor
enum Art {
    // MARK: Wolf

    /// The head without its lower jaw, 560 points square; the mouth line is
    /// at `wolfMouthY` from the bottom. The jaw hangs under it. Seen a little
    /// from the side: the muzzle points to the viewer's right.
    static let wolfHeadSize = CGSize(width: 560, height: 560)
    static let wolfMouthY: CGFloat = 253
    /// Where the eyes are, from the texture's middle, for the glow in the scene.
    static let wolfEyes = [CGPoint(x: -58, y: 70), CGPoint(x: 62, y: 72)]

    static var wolfHead: SKTexture { Textures.make("wolf-head", size: wolfHeadSize) { c, size in
        let u: CGFloat = 110
        let cx = size.width / 2, cy: CGFloat = 310
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * u, y: cy + y * u) }
        func furred(_ path: CGPath, base: UIColor = Metal.fur, depth: CGFloat) {
            Draw.cel(c, path, base: base, shadow: Metal.furDark, core: Metal.furDeep.withAlphaComponent(0.5), rim: Metal.furLight, width: 3.5, depth: depth)
        }
        // The ruff behind everything: a dark jagged mane, a mid tone, lit tufts on the lit side.
        Draw.cel(c, Draw.ruff(center: p(0.05, -0.05), rx: 1.3 * u, ry: 1.15 * u, spikes: 56, length: 0.3 * u, seed: 1), base: Metal.furDark, shadow: Metal.furDeep, rim: nil, width: 3.5, depth: 0.35 * u)
        let mid = Draw.ruff(center: p(0.05, -0.08), rx: 1.18 * u, ry: 1.0 * u, spikes: 48, length: 0.22 * u, seed: 5)
        Draw.fill(c, mid, Metal.fur)
        c.saveGState()
        c.addPath(mid)
        c.clip()
        Draw.fill(c, Draw.ruff(center: p(-0.2, 0.2), rx: 1.0 * u, ry: 0.85 * u, spikes: 36, length: 0.2 * u, seed: 9, from: 0.3, to: 2.9), Metal.furLight.withAlphaComponent(0.5))
        c.restoreGState()
        // Ears on top of the dome, the far one narrower.
        for s in [CGFloat(-1), 1] {
            let narrow: CGFloat = s < 0 ? 0.85 : 1
            let ear = Draw.smooth([p(s * 0.78, 0.9), p(s * 1.05 * narrow, 2.0), p(s * 0.28, 1.2)], tension: 0.25)
            furred(ear, depth: 0.25 * u)
            let inner = Draw.smooth([p(s * 0.78, 1.0), p(s * 0.98 * narrow, 1.75), p(s * 0.42, 1.18)], tension: 0.25)
            Draw.cel(c, inner, base: UIColor(red: 0.42, green: 0.22, blue: 0.26, alpha: 1), shadow: UIColor(red: 0.22, green: 0.08, blue: 0.11, alpha: 1), rim: nil, ink: Metal.furDeep, width: 2.5, depth: 0.15 * u)
        }
        // The head: a round cranium over the cheeks, which taper to the mouth.
        let skull = CGMutablePath()
        skull.addPath(Draw.ellipse(at: p(0, 0.5), rx: 1.1 * u, ry: 0.78 * u))
        skull.addPath(Draw.smooth([p(-1.1, 0.5), p(1.12, 0.5), p(1.22, 0.05), p(1.0, -0.45), p(0.75, -0.62), p(0.1, -0.68), p(-0.7, -0.62), p(-0.95, -0.45), p(-1.2, 0.05)], tension: 0.5))
        furred(skull, depth: 0.5 * u)
        // Cheek ruffs flaring out of the sides, three tones.
        for s in [CGFloat(-1), 1] {
            let cheek = Draw.ruff(center: p(s * 0.78, -0.12), rx: 0.5 * u, ry: 0.5 * u, spikes: 20, length: 0.34 * u, seed: 20 + Int(s) * 3, from: s > 0 ? -1.4 : 1.75, to: s > 0 ? 1.0 : 4.5)
            furred(cheek, depth: 0.3 * u)
        }
        // The muzzle: a lighter wedge from between the eyes down to the nose, set to the right.
        let muzzle = Draw.smooth([p(-0.42, 0.62), p(0.5, 0.62), p(0.68, 0.1), p(0.58, -0.4), p(0.12, -0.52), p(-0.42, -0.4), p(-0.56, 0.1)], tension: 0.5)
        Draw.cel(c, muzzle, base: Metal.furLight, shadow: Metal.fur, core: Metal.furDark.withAlphaComponent(0.4), rim: UIColor(white: 0.84, alpha: 1), width: 3.5, depth: 0.32 * u)
        // Brow ridge: heavy dark wedges angled down to the nose, furrowed between.
        for s in [CGFloat(-1), 1] {
            let brow = Draw.smooth([p(s * 1.05, 0.72), p(s * 0.6, 0.88), p(s * 0.1, 0.5), p(s * 0.18, 0.3), p(s * 0.65, 0.42)], tension: 0.35)
            Draw.cel(c, brow, base: Metal.furDark, shadow: Metal.furDeep, rim: Metal.fur, width: 3.5, depth: 0.14 * u)
        }
        let furrow = CGMutablePath()
        furrow.move(to: p(0.0, 0.62))
        furrow.addLine(to: p(0.06, 0.38))
        Draw.stroke(c, furrow, Metal.furDark, width: 3)
        // Eyes: almonds under the brows, ember irises with slit pupils.
        for (i, s) in [CGFloat(-1), 1].enumerated() {
            let e = CGPoint(x: cx + wolfEyes[i].x, y: cx + wolfEyes[i].y)
            c.saveGState()
            c.translateBy(x: e.x, y: e.y)
            c.rotate(by: s * 0.3)
            let q = Draw.point
            let eye = Draw.smooth([q(-0.3 * u, 0), q(-0.12 * u, 0.15 * u), q(0.14 * u, 0.14 * u), q(0.3 * u, -0.02 * u), q(0.1 * u, -0.15 * u), q(-0.14 * u, -0.13 * u)], tension: 0.5)
            Draw.fill(c, eye, Metal.emberBright)
            c.saveGState()
            c.addPath(eye)
            c.clip()
            Draw.fill(c, Draw.circle(at: CGPoint(x: 0.02 * u, y: -0.04 * u), r: 0.19 * u), Metal.ember)
            Draw.fill(c, Draw.circle(at: CGPoint(x: 0.04 * u, y: -0.08 * u), r: 0.11 * u), UIColor(red: 0.7, green: 0.2, blue: 0, alpha: 1))
            Draw.fill(c, Draw.ellipse(at: CGPoint(x: 0.02 * u, y: -0.01 * u), rx: 0.045 * u, ry: 0.15 * u), Metal.ink)
            Draw.fill(c, eye.subtracting(Draw.translated(eye, 0, -0.07 * u), using: .winding), Metal.furDeep.withAlphaComponent(0.7))
            c.restoreGState()
            Draw.fill(c, Draw.ellipse(at: CGPoint(x: -0.12 * u, y: 0.05 * u), rx: 0.045 * u, ry: 0.03 * u), UIColor.white.withAlphaComponent(0.9))
            Draw.stroke(c, eye, Metal.ink, width: 3.5)
            c.restoreGState()
        }
        // Nose: a wet dark pad with a highlight, nostrils, the split to the lip.
        let nose = Draw.smooth([p(-0.18, -0.02), p(0.4, -0.02), p(0.36, -0.22), p(0.12, -0.36), p(-0.14, -0.22)], tension: 0.5)
        Draw.cel(c, nose, base: UIColor(white: 0.22, alpha: 1), shadow: Metal.furDeep, rim: UIColor(white: 0.45, alpha: 1), width: 3, depth: 0.1 * u)
        Draw.fill(c, Draw.ellipse(at: p(0.0, -0.1), rx: 0.09 * u, ry: 0.045 * u), UIColor.white.withAlphaComponent(0.55))
        for x in [CGFloat(-0.08), 0.28] {
            Draw.fill(c, Draw.ellipse(at: p(x, -0.16), rx: 0.05 * u, ry: 0.035 * u), Metal.ink)
        }
        let split = CGMutablePath()
        split.move(to: p(0.12, -0.36))
        split.addLine(to: p(0.12, -0.52))
        Draw.stroke(c, split, Metal.ink, width: 3)
        // The mouth: nothing of the head below the lip, so the jaw and the dark
        // inside (`wolfMouth`, behind the jaw) show through when it drops; the gum line and the upper teeth.
        c.saveGState()
        c.setBlendMode(.clear)
        Draw.fill(c, Draw.polygon([p(-0.8, -0.5), p(0.85, -0.5), p(0.8, -2.9), p(-0.76, -2.9)]), .black)
        c.restoreGState()
        Draw.cel(c, Draw.smooth([p(-0.82, -0.46), p(0.86, -0.46), p(0.8, -0.66), p(0, -0.7), p(-0.78, -0.66)], tension: 0.3), base: Metal.gum, shadow: Metal.bloodDark, rim: UIColor(red: 0.7, green: 0.3, blue: 0.35, alpha: 1), width: 2.5, depth: 0.08 * u)
        for i in 0..<9 {
            let x = -0.68 + CGFloat(i) * 0.19
            let fang = i == 0 || i == 8
            let len: CGFloat = fang ? 0.52 : (i % 2 == 0 ? 0.18 : 0.12)
            let half: CGFloat = fang ? 0.1 : 0.065
            let tooth = Draw.smooth([p(x - half, -0.6), p(x + half, -0.6), p(x + half * 0.5, -0.6 - len * 0.6), p(x + (fang ? 0.03 : 0), -0.6 - len), p(x - half * 0.5, -0.6 - len * 0.6)], tension: 0.35)
            Draw.cel(c, tooth, base: Metal.bone, shadow: Metal.boneShade, rim: nil, width: 2.5, depth: half * 1.2 * u)
            if fang {
                // The tip goes a little translucent.
                Draw.fill(c, Draw.polygon([p(x - half * 0.45, -0.6 - len * 0.62), p(x + half * 0.45, -0.6 - len * 0.62), p(x + 0.03, -0.6 - len)]), UIColor(red: 0.85, green: 0.9, blue: 0.95, alpha: 0.45))
                // Drool.
                let drip = CGMutablePath()
                drip.move(to: p(x + 0.02, -0.6 - len + 0.05))
                drip.addQuadCurve(to: p(x + 0.01, -1.0), control: p(x + 0.06, -0.8))
                Draw.stroke(c, drip, UIColor(red: 0.9, green: 0.93, blue: 0.93, alpha: 0.6), width: 4)
                Draw.fill(c, Draw.ellipse(at: p(x + 0.01, -1.0), rx: 0.04 * u, ry: 0.06 * u), UIColor(red: 0.9, green: 0.93, blue: 0.93, alpha: 0.7))
            }
        }
        // Upper lip, snarling up over the fangs into the cheeks.
        let lip = CGMutablePath()
        lip.move(to: p(-0.98, -0.28))
        lip.addQuadCurve(to: p(-0.1, -0.52), control: p(-0.6, -0.58))
        lip.addQuadCurve(to: p(1.0, -0.26), control: p(0.6, -0.58))
        Draw.stroke(c, lip, Metal.ink, width: 5)
    } }

    /// The dark inside of the mouth, as far down as the jaw drops. It sits
    /// behind the jaw, so the lower teeth draw over it, and its middle is
    /// `wolfMouthOffset` from the head's middle.
    static let wolfMouthSize = CGSize(width: 190, height: 70)
    static let wolfMouthOffset = CGPoint(x: 3, y: -58)

    static var wolfMouth: SKTexture { Textures.make("wolf-mouth", size: wolfMouthSize) { c, size in
        let u: CGFloat = 110
        // The same points as the head's, about the texture's middle.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width / 2 + (x - 0.025) * u, y: size.height / 2 + (y + 0.8) * u) }
        Draw.fill(c, Draw.polygon([p(-0.8, -0.5), p(0.85, -0.5), p(0.8, -1.1), p(-0.76, -1.1)]), UIColor(red: 0.16, green: 0.01, blue: 0.03, alpha: 1))
    } }

    /// The lower jaw, anchored at its top middle where it meets the head.
    static let wolfJawSize = CGSize(width: 360, height: 250)

    static var wolfJaw: SKTexture { Textures.make("wolf-jaw", size: wolfJawSize) { c, size in
        let u: CGFloat = 110
        let cx = size.width / 2, top = size.height - 10
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * u, y: top + y * u) }
        // The chin: furred, with tufts hanging under it.
        let chin = Draw.smooth([p(-0.85, 0), p(0.88, 0), p(0.8, -0.7), p(0.5, -1.15), p(0.1, -1.3), p(-0.4, -1.22), p(-0.75, -0.8)], tension: 0.45)
        Draw.cel(c, chin, base: Metal.fur, shadow: Metal.furDark, core: Metal.furDeep.withAlphaComponent(0.5), rim: Metal.furLight, width: 3.5, depth: 0.3 * u)
        Draw.cel(c, Draw.ruff(center: p(0.05, -0.95), rx: 0.55 * u, ry: 0.3 * u, spikes: 14, length: 0.28 * u, seed: 21, from: .pi + 0.2, to: .pi * 2 - 0.2), base: Metal.furDark, shadow: Metal.furDeep, rim: nil, width: 3, depth: 0.15 * u)
        // The inside, the tongue filling it, and the lower gum with its teeth.
        let inside = Draw.smooth([p(-0.74, 0.02), p(0.76, 0.02), p(0.62, -0.62), p(0, -0.78), p(-0.6, -0.62)], tension: 0.4)
        Draw.fill(c, inside, UIColor(red: 0.16, green: 0.01, blue: 0.03, alpha: 1))
        let tongue = Draw.smooth([p(-0.5, -0.02), p(0.52, -0.02), p(0.48, -0.4), p(0.02, -0.68), p(-0.46, -0.4)], tension: 0.5)
        Draw.cel(c, tongue, base: UIColor(red: 0.85, green: 0.35, blue: 0.42, alpha: 1), shadow: UIColor(red: 0.6, green: 0.14, blue: 0.22, alpha: 1), rim: UIColor(red: 0.98, green: 0.6, blue: 0.65, alpha: 1), width: 3, depth: 0.2 * u)
        let groove = CGMutablePath()
        groove.move(to: p(0.02, -0.08))
        groove.addLine(to: p(0.02, -0.58))
        Draw.stroke(c, groove, UIColor(red: 0.55, green: 0.12, blue: 0.2, alpha: 0.8), width: 3)
        Draw.fill(c, Draw.ellipse(at: p(-0.18, -0.2), rx: 0.1 * u, ry: 0.05 * u), UIColor.white.withAlphaComponent(0.35))
        Draw.cel(c, Draw.smooth([p(-0.8, 0.06), p(0.82, 0.06), p(0.76, -0.14), p(0, -0.18), p(-0.74, -0.14)], tension: 0.3), base: Metal.gum, shadow: Metal.bloodDark, rim: UIColor(red: 0.7, green: 0.3, blue: 0.35, alpha: 1), width: 2.5, depth: 0.08 * u)
        for i in 0..<8 {
            let x = -0.6 + CGFloat(i) * 0.172
            let fang = i == 0 || i == 7
            let len: CGFloat = fang ? 0.42 : (i % 2 == 0 ? 0.14 : 0.1)
            let half: CGFloat = fang ? 0.09 : 0.06
            let tooth = Draw.smooth([p(x - half, -0.1), p(x + half, -0.1), p(x + half * 0.5, -0.1 + len * 0.6), p(x, -0.1 + len), p(x - half * 0.5, -0.1 + len * 0.6)], tension: 0.35)
            Draw.cel(c, tooth, base: Metal.bone, shadow: Metal.boneShade, rim: nil, width: 2.5, depth: half * 1.2 * u)
        }
    } }

    // MARK: Eagle

    /// The body, head and tail, facing right. The shoulder, where the wings
    /// attach, is at `eagleShoulder` from the bottom left.
    static let eagleBodySize = CGSize(width: 520, height: 300)
    static let eagleShoulder = CGPoint(x: 250, y: 165)

    /// One tail or wing feather: a rounded quill from `root` to `tip`.
    static func featherPath(from root: CGPoint, to tip: CGPoint, width: CGFloat) -> CGPath {
        let dx = tip.x - root.x, dy = tip.y - root.y
        let length = max(hypot(dx, dy), 0.001)
        let q = Draw.point
        let shape = Draw.smooth([
            q(0, width * 0.35), q(length * 0.4, width * 0.5), q(length * 0.85, width * 0.42), q(length, 0),
            q(length * 0.85, -width * 0.42), q(length * 0.4, -width * 0.5), q(0, -width * 0.35),
        ], tension: 0.5)
        var transform = CGAffineTransform(translationX: root.x, y: root.y).rotated(by: atan2(dy, dx))
        return shape.copy(using: &transform) ?? shape
    }

    /// A feather with its shaft line, cel shaded, the tip dipped in `tip` if given.
    static func feather(_ c: CGContext, from root: CGPoint, to tip: CGPoint, width: CGFloat, base: UIColor, shadow: UIColor, tip tipColor: UIColor? = nil, ink: UIColor = Metal.ink, lineWidth: CGFloat = 2.5) {
        let path = featherPath(from: root, to: tip, width: width)
        Draw.cel(c, path, base: base, shadow: shadow, rim: nil, ink: nil, width: lineWidth, depth: width * 0.45)
        if let tipColor {
            c.saveGState()
            c.addPath(path)
            c.clip()
            let dx = tip.x - root.x, dy = tip.y - root.y
            Draw.fill(c, Draw.circle(at: tip, r: hypot(dx, dy) * 0.42), tipColor)
            c.restoreGState()
        }
        let shaft = CGMutablePath()
        shaft.move(to: CGPoint(x: root.x + (tip.x - root.x) * 0.1, y: root.y + (tip.y - root.y) * 0.1))
        shaft.addLine(to: CGPoint(x: root.x + (tip.x - root.x) * 0.9, y: root.y + (tip.y - root.y) * 0.9))
        Draw.stroke(c, shaft, ink.withAlphaComponent(0.45), width: lineWidth * 0.6)
        Draw.stroke(c, path, ink, width: lineWidth)
    }

    /// Rows of U-shaped feather tips over a body or covert area, clipped to `clip`.
    static func scallops(_ c: CGContext, clip: CGPath, origin: CGPoint, columns: Int, rows: Int, dx: CGFloat, dy: CGFloat, rx: CGFloat, ry: CGFloat, color: UIColor, light: UIColor, skew: CGFloat = 0) {
        c.saveGState()
        c.addPath(clip)
        c.clip()
        for row in 0..<rows {
            for i in 0..<columns {
                let x = origin.x + CGFloat(i) * dx + CGFloat(row % 2) * dx / 2 + CGFloat(row) * skew
                let y = origin.y - CGFloat(row) * dy
                Draw.feather(c, at: CGPoint(x: x, y: y), rx: rx, ry: ry, dark: color, light: light)
            }
        }
        c.restoreGState()
    }

    static var eagleBody: SKTexture { Textures.make("eagle-body", size: eagleBodySize) { c, size in
        let u: CGFloat = 100
        let o = CGPoint(x: 230, y: 150)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        // Tail: white feathers fanned behind, the middle ones on top.
        for i in [0, 6, 1, 5, 2, 4, 3] {
            let a = CGFloat(i - 3) * 0.14
            feather(c, from: p(-1.0, 0.0), to: p(-1.0 - cos(a) * 1.35, -0.1 - sin(a) * 1.35), width: 0.3 * u, base: .white, shadow: UIColor(white: 0.78, alpha: 1))
        }
        // Body: a deep chest, tapering to the tail.
        let body = Draw.smooth([p(-1.25, 0.2), p(-0.5, 0.52), p(0.6, 0.58), p(1.3, 0.38), p(1.35, -0.15), p(0.7, -0.58), p(-0.3, -0.58), p(-1.2, -0.25)], tension: 0.5)
        Draw.cel(c, body, base: Metal.eagleBrown, shadow: Metal.eagleDark, core: Metal.eagleDeep.withAlphaComponent(0.6), rim: Metal.eagleLight, width: 3.5, depth: 0.4 * u)
        scallops(c, clip: body, origin: p(-1.3, 0.3), columns: 10, rows: 4, dx: 0.3 * u, dy: 0.22 * u, rx: 0.15 * u, ry: 0.1 * u, color: Metal.eagleDeep, light: Metal.eagleLight)
        // Legs and talons, feathered thighs over them.
        for x in [CGFloat(0.3), 0.62] {
            let leg = Draw.capsule(from: p(x, -0.35), to: p(x + 0.1, -0.82), radius: 0.07 * u)
            Draw.cel(c, leg, base: Metal.beakYellow, shadow: Metal.beakShade, width: 2.5, depth: 0.08 * u)
            for k in -1...1 {
                let toe = Draw.capsule(from: p(x + 0.1, -0.82), to: p(x + 0.12 + CGFloat(k) * 0.15, -0.98), radius: 0.04 * u)
                Draw.cel(c, toe, base: Metal.beakYellow, shadow: Metal.beakShade, width: 2.5, depth: 0.04 * u)
                let claw = Draw.smooth([p(x + 0.09 + CGFloat(k) * 0.15, -0.95), p(x + 0.16 + CGFloat(k) * 0.15, -0.97), p(x + 0.14 + CGFloat(k) * 0.15, -1.12)], tension: 0.3)
                Draw.cel(c, claw, base: UIColor(white: 0.2, alpha: 1), shadow: Metal.ink, width: 2, depth: 0.03 * u)
            }
            let thigh = Draw.smooth([p(x - 0.2, -0.3), p(x + 0.22, -0.3), p(x + 0.2, -0.5), p(x + 0.05, -0.6), p(x - 0.15, -0.5)], tension: 0.5)
            Draw.cel(c, thigh, base: Metal.eagleBrown, shadow: Metal.eagleDark, rim: nil, width: 3, depth: 0.1 * u)
        }
        // Neck and head: white, with a fierce brow over the eye.
        let head = Draw.smooth([p(0.9, 0.58), p(1.35, 0.95), p(1.9, 1.0), p(2.2, 0.72), p(2.1, 0.32), p(1.6, 0.1), p(1.1, 0.1)], tension: 0.5)
        Draw.cel(c, head, base: .white, shadow: UIColor(white: 0.78, alpha: 1), core: UIColor(white: 0.6, alpha: 0.6), rim: nil, width: 3.5, depth: 0.35 * u)
        scallops(c, clip: head, origin: p(0.95, 0.5), columns: 5, rows: 3, dx: 0.28 * u, dy: 0.2 * u, rx: 0.13 * u, ry: 0.08 * u, color: UIColor(white: 0.7, alpha: 1), light: .white)
        // Beak: hooked, the upper mandible over the lower, dark at the tip.
        let upper = Draw.smooth([p(2.05, 0.8), p(2.5, 0.72), p(2.78, 0.45), p(2.72, 0.22), p(2.6, 0.3), p(2.5, 0.4), p(2.08, 0.42)], tension: 0.4)
        let lower = Draw.smooth([p(2.08, 0.44), p(2.5, 0.4), p(2.6, 0.26), p(2.1, 0.3)], tension: 0.3)
        Draw.cel(c, lower, base: Metal.beakShade, shadow: UIColor(red: 0.55, green: 0.32, blue: 0.05, alpha: 1), width: 2.5, depth: 0.06 * u)
        Draw.cel(c, upper, base: Metal.beakYellow, shadow: Metal.beakShade, rim: UIColor(red: 1, green: 0.92, blue: 0.5, alpha: 1), width: 3, depth: 0.16 * u)
        c.saveGState()
        c.addPath(upper)
        c.clip()
        Draw.fill(c, Draw.circle(at: p(2.74, 0.26), r: 0.16 * u), UIColor(white: 0.15, alpha: 1))
        c.restoreGState()
        Draw.fill(c, Draw.ellipse(at: p(2.2, 0.72), rx: 0.05 * u, ry: 0.03 * u), Metal.ink)
        // The brow and the eye under it.
        let brow = Draw.smooth([p(1.55, 0.82), p(2.08, 0.78), p(2.05, 0.66), p(1.85, 0.6), p(1.6, 0.64)], tension: 0.4)
        Draw.cel(c, brow, base: UIColor(white: 0.85, alpha: 1), shadow: UIColor(white: 0.6, alpha: 1), rim: nil, width: 3, depth: 0.08 * u)
        Draw.fill(c, Draw.circle(at: p(1.85, 0.6), r: 0.1 * u), Metal.beakYellow)
        Draw.fill(c, Draw.circle(at: p(1.87, 0.59), r: 0.06 * u), Metal.ink)
        Draw.fill(c, Draw.circle(at: p(1.83, 0.63), r: 0.02 * u), .white)
        Draw.stroke(c, Draw.circle(at: p(1.85, 0.6), r: 0.1 * u), Metal.ink, width: 2.5)
    } }

    /// One wing, pointing up from the shoulder at the bottom. The far wing is
    /// the same sprite flipped and darkened.
    static let eagleWingSize = CGSize(width: 420, height: 440)
    /// Fraction of the texture where the shoulder is: the anchor of the sprite.
    static let eagleWingAnchor = CGPoint(x: 0.5, y: 0.04)

    static var eagleWing: SKTexture { Textures.make("eagle-wing", size: eagleWingSize) { c, size in
        wing(c, size: size, base: Metal.eagleBrown, dark: Metal.eagleDark, deep: Metal.eagleDeep, light: Metal.eagleLight, tip: Metal.eagleDeep, narrow: 1)
    } }

    /// A wing in three feather layers: separate primaries fanned at the tip,
    /// secondaries along the trailing edge, and the coverts over their roots.
    private static func wing(_ c: CGContext, size: CGSize, base: UIColor, dark: UIColor, deep: UIColor, light: UIColor, tip: UIColor, narrow: CGFloat) {
        let u = size.height / 4.4
        let o = CGPoint(x: size.width / 2, y: size.height * 0.04)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u * narrow, y: o.y + y * u) }
        let count = 7
        // Primaries: long fingers from the wrist, the outermost on top.
        let wrist = p(0.15, 2.15)
        for i in (0..<count).reversed() {
            let f = CGFloat(i) / CGFloat(count - 1)
            let end = p(0.5 - f * 1.75, 4.3 - f * 0.9 - f * f * 0.45)
            let root = CGPoint(x: wrist.x - f * 0.3 * u * narrow, y: wrist.y - f * 0.1 * u)
            feather(c, from: root, to: end, width: 0.34 * u * narrow, base: base, shadow: dark, tip: tip, lineWidth: 3)
        }
        // Secondaries: shorter, rounder, along the trailing edge down to the body.
        for i in (0..<8).reversed() {
            let f = CGFloat(i) / 7
            let root = p(0.25 - f * 0.4, 2.1 - f * 1.85)
            let end = p(-1.0 + f * f * 0.6, 2.75 - f * 2.3)
            feather(c, from: root, to: end, width: 0.38 * u * narrow, base: base, shadow: dark, lineWidth: 3)
        }
        // Coverts: the wing's arm, tapering from the shoulder to the wrist. Over
        // it three rows of short feathers, one per secondary, lie over the
        // secondaries' roots and step back toward the leading edge, each row
        // shorter and narrower; the marginal coverts cover their roots along the edge.
        let arm = Draw.smooth([p(0.2, -0.05), p(0.5, 0.6), p(0.52, 1.4), p(0.38, 2.05), p(0.12, 2.28), p(-0.12, 2.08), p(-0.24, 1.4), p(-0.22, 0.6), p(-0.15, 0.0)], tension: 0.5)
        Draw.cel(c, arm, base: base, shadow: dark, core: deep.withAlphaComponent(0.6), rim: light, width: 3.5, depth: 0.3 * u)
        let rows: [(reach: CGFloat, least: CGFloat, width: CGFloat)] = [(0.62, 0.34, 0.27), (0.5, 0.3, 0.23), (0.4, 0.26, 0.2)]
        for (row, spec) in rows.enumerated() {
            let shift = CGFloat(row) * 0.14
            for i in (0..<8).reversed() {
                let f = CGFloat(i) / 7
                let root = p(0.1 - f * 0.22 + shift, 1.95 - f * 1.7 + shift * 0.2)
                let tip = p(-1.0 + f * f * 0.6, 2.75 - f * 2.3)
                let dx = tip.x - root.x, dy = tip.y - root.y
                let length = max(hypot(dx, dy), 0.001)
                let reach = max(length * spec.reach, spec.least * u) / length
                let end = CGPoint(x: root.x + dx * reach, y: root.y + dy * reach)
                feather(c, from: root, to: end, width: spec.width * u * narrow, base: base, shadow: dark)
            }
        }
        let edge = Draw.smooth([p(0.2, -0.05), p(0.5, 0.6), p(0.52, 1.4), p(0.38, 2.05), p(0.12, 2.28), p(0.05, 2.0), p(0.28, 1.4), p(0.28, 0.6), p(0.02, 0.0)], tension: 0.5)
        Draw.cel(c, edge, base: base, shadow: dark, rim: light, width: 3, depth: 0.12 * u)
    }

    // MARK: Albatross

    static let albatrossBodySize = CGSize(width: 520, height: 260)
    static let albatrossShoulder = CGPoint(x: 240, y: 150)

    static var albatrossBody: SKTexture { Textures.make("albatross-body", size: albatrossBodySize) { c, size in
        let u: CGFloat = 90
        let o = CGPoint(x: 220, y: 130)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        let grey = UIColor(white: 0.74, alpha: 1)
        let greyDark = UIColor(white: 0.5, alpha: 1)
        // Tail: a short white wedge with dark tips.
        for i in [0, 4, 1, 3, 2] {
            let a = CGFloat(i - 2) * 0.12
            feather(c, from: p(-1.2, 0.0), to: p(-1.2 - cos(a) * 1.15, -0.05 - sin(a) * 1.15), width: 0.26 * u, base: .white, shadow: grey, tip: UIColor(white: 0.2, alpha: 1))
        }
        // Body: long and slim, white above, grey below.
        let body = Draw.smooth([p(-1.5, 0.12), p(-0.6, 0.46), p(0.8, 0.5), p(1.7, 0.3), p(1.8, -0.1), p(1.0, -0.46), p(-0.4, -0.5), p(-1.4, -0.25)], tension: 0.5)
        Draw.cel(c, body, base: .white, shadow: grey, core: greyDark.withAlphaComponent(0.5), rim: nil, width: 3.5, depth: 0.35 * u)
        // Feet tucked back under the tail: pink and webbed.
        for x in [CGFloat(-0.35), -0.05] {
            let foot = Draw.smooth([p(x, -0.3), p(x - 0.5, -0.42), p(x - 0.62, -0.58), p(x - 0.42, -0.6), p(x - 0.15, -0.5), p(x + 0.05, -0.42)], tension: 0.4)
            Draw.cel(c, foot, base: UIColor(red: 0.9, green: 0.72, blue: 0.65, alpha: 1), shadow: UIColor(red: 0.7, green: 0.48, blue: 0.42, alpha: 1), width: 2.5, depth: 0.08 * u)
            for k in 0..<2 {
                let web = CGMutablePath()
                web.move(to: p(x - 0.15, -0.42))
                web.addLine(to: p(x - 0.35 - CGFloat(k) * 0.2, -0.5 - CGFloat(k) * 0.06))
                Draw.stroke(c, web, UIColor(red: 0.7, green: 0.48, blue: 0.42, alpha: 0.8), width: 2)
            }
        }
        // Neck and head.
        let head = Draw.smooth([p(1.3, 0.5), p(1.9, 0.85), p(2.45, 0.8), p(2.6, 0.5), p(2.4, 0.25), p(1.9, 0.1), p(1.4, 0.05)], tension: 0.5)
        Draw.cel(c, head, base: .white, shadow: grey, core: greyDark.withAlphaComponent(0.4), rim: nil, width: 3.5, depth: 0.3 * u)
        // The bill: long, pale pink to yellow, with the hooked tip and the plates along it.
        let billShade = UIColor(red: 0.85, green: 0.6, blue: 0.5, alpha: 1)
        let upper = Draw.smooth([p(2.45, 0.7), p(3.0, 0.62), p(3.35, 0.5), p(3.48, 0.3), p(3.3, 0.24), p(3.1, 0.38), p(2.5, 0.42)], tension: 0.4)
        let lower = Draw.smooth([p(2.5, 0.43), p(3.1, 0.38), p(3.25, 0.26), p(2.95, 0.22), p(2.5, 0.3)], tension: 0.3)
        Draw.cel(c, lower, base: UIColor(red: 0.95, green: 0.78, blue: 0.62, alpha: 1), shadow: billShade, width: 2.5, depth: 0.06 * u)
        Draw.cel(c, upper, base: UIColor(red: 1, green: 0.9, blue: 0.72, alpha: 1), shadow: billShade, rim: .white, width: 3, depth: 0.12 * u)
        c.saveGState()
        c.addPath(upper)
        c.clip()
        Draw.fill(c, Draw.circle(at: p(3.5, 0.28), r: 0.2 * u), UIColor(red: 0.95, green: 0.75, blue: 0.3, alpha: 1))
        c.restoreGState()
        let plate = CGMutablePath()
        plate.move(to: p(2.6, 0.62))
        plate.addQuadCurve(to: p(3.3, 0.5), control: p(3.0, 0.56))
        Draw.stroke(c, plate, billShade, width: 2)
        Draw.fill(c, Draw.ellipse(at: p(2.72, 0.6), rx: 0.05 * u, ry: 0.03 * u), Metal.ink)
        // The dark eye patch and the eye.
        Draw.fill(c, Draw.ellipse(at: p(2.1, 0.55), rx: 0.22 * u, ry: 0.13 * u), UIColor(white: 0.4, alpha: 0.6))
        Draw.fill(c, Draw.circle(at: p(2.12, 0.55), r: 0.08 * u), Metal.ink)
        Draw.fill(c, Draw.circle(at: p(2.09, 0.58), r: 0.025 * u), .white)
    } }

    static let albatrossWingSize = CGSize(width: 300, height: 700)
    static let albatrossWingAnchor = CGPoint(x: 0.5, y: 0.03)

    static var albatrossWing: SKTexture { Textures.make("albatross-wing", size: albatrossWingSize) { c, size in
        wing(c, size: size, base: UIColor(white: 0.96, alpha: 1), dark: UIColor(white: 0.74, alpha: 1), deep: UIColor(white: 0.5, alpha: 1), light: .white, tip: UIColor(white: 0.12, alpha: 1), narrow: 0.6)
    } }

    // MARK: A small bird, for the birdie

    static let birdSize = CGSize(width: 160, height: 120)

    static var bird: SKTexture { Textures.make("bird", size: birdSize) { c, size in
        let u: CGFloat = 40
        let o = CGPoint(x: 70, y: 50)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        let red = Metal.bloodBright
        let dark = Metal.bloodDark
        Draw.cel(c, Draw.polygon([p(-0.7, 0.15), p(-1.65, 0.5), p(-1.5, -0.2)]), base: Metal.blood, shadow: dark, width: 2.5, depth: 8)
        let body = Draw.ellipse(at: p(0, 0), rx: 0.95 * u, ry: 0.7 * u)
        Draw.cel(c, body, base: red, shadow: Metal.blood, core: dark.withAlphaComponent(0.6), rim: nil, width: 2.5, depth: 14)
        c.saveGState()
        c.addPath(body)
        c.clip()
        Draw.fill(c, Draw.ellipse(at: p(0.15, -0.2), rx: 0.55 * u, ry: 0.38 * u), Metal.bone)
        c.restoreGState()
        let wing = Draw.smooth([p(-0.6, 0.3), p(0.1, 0.5), p(0.3, 0.1), p(-0.3, -0.1)], tension: 0.5)
        Draw.cel(c, wing, base: Metal.blood, shadow: dark, width: 2.5, depth: 8)
        Draw.cel(c, Draw.circle(at: p(0.85, 0.55), r: 0.5 * u), base: red, shadow: Metal.blood, width: 2.5, depth: 10)
        Draw.cel(c, Draw.polygon([p(1.25, 0.62), p(1.95, 0.5), p(1.25, 0.35)]), base: Metal.emberBright, shadow: Metal.ember, width: 2, depth: 4)
        Draw.fill(c, Draw.circle(at: p(1.0, 0.65), r: 0.11 * u), Metal.ink)
        Draw.fill(c, Draw.circle(at: p(0.97, 0.69), r: 0.035 * u), .white)
        for x in [CGFloat(-0.15), 0.2] {
            Draw.stroke(c, Draw.capsule(from: p(x, -0.6), to: p(x, -1.1), radius: 0.001), Metal.ink, width: 5)
            Draw.stroke(c, Draw.capsule(from: p(x, -0.6), to: p(x, -1.1), radius: 0.001), Metal.emberBright, width: 2.5)
        }
    } }
}

extension Draw {
    /// One feather of a row: a U-shaped tip, shadow below and a lit edge.
    static func feather(_ c: CGContext, at center: CGPoint, rx: CGFloat, ry: CGFloat, dark: UIColor, light: UIColor) {
        let tip = CGMutablePath()
        var transform = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: rx, y: ry)
        tip.addArc(center: .zero, radius: 1, startAngle: .pi, endAngle: 0, clockwise: true, transform: transform)
        stroke(c, tip, dark.withAlphaComponent(0.85), width: 2.5)
        transform = transform.translatedBy(x: 0, y: 2.5 / ry)
        let edge = CGMutablePath()
        edge.addArc(center: .zero, radius: 1, startAngle: .pi, endAngle: 0, clockwise: true, transform: transform)
        stroke(c, edge, light.withAlphaComponent(0.5), width: 1.5)
    }

    /// Evenly spaced points along a closed polyline, for Metal.fur along a smooth outline.
    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        var lengths: [CGFloat] = [0]
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            lengths.append(lengths[i] + hypot(b.x - a.x, b.y - a.y))
        }
        let total = lengths[points.count]
        var out: [CGPoint] = []
        for k in 0..<count {
            let d = total * CGFloat(k) / CGFloat(count)
            var i = 0
            while i < points.count - 1, lengths[i + 1] < d { i += 1 }
            let a = points[i], b = points[(i + 1) % points.count]
            let seg = max(lengths[i + 1] - lengths[i], 0.001)
            let f = (d - lengths[i]) / seg
            out.append(CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
        }
        return out
    }
}
