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
            let eye = Draw.smooth([CGPoint(x: -0.3 * u, y: 0), CGPoint(x: -0.12 * u, y: 0.15 * u), CGPoint(x: 0.14 * u, y: 0.14 * u), CGPoint(x: 0.3 * u, y: -0.02 * u), CGPoint(x: 0.1 * u, y: -0.15 * u), CGPoint(x: -0.14 * u, y: -0.13 * u)], tension: 0.5)
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
        // The mouth: nothing of the head below the lip, so the jaw shows through
        // when it drops; the dark inside as far down as the jaw drops; the gum line and the upper teeth.
        c.saveGState()
        c.setBlendMode(.clear)
        Draw.fill(c, Draw.polygon([p(-0.8, -0.5), p(0.85, -0.5), p(0.8, -2.9), p(-0.76, -2.9)]), .black)
        c.restoreGState()
        let inside = Draw.polygon([p(-0.8, -0.5), p(0.85, -0.5), p(0.8, -1.1), p(-0.76, -1.1)])
        Draw.fill(c, inside, UIColor(red: 0.16, green: 0.01, blue: 0.03, alpha: 1))
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

    static var eagleBody: SKTexture { Textures.make("eagle-body", size: eagleBodySize) { c, size in
        let u: CGFloat = 100
        let o = CGPoint(x: 230, y: 150)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        let brown = UIColor(red: 0.3, green: 0.18, blue: 0.08, alpha: 1)
        let brownDark = UIColor(red: 0.13, green: 0.07, blue: 0.03, alpha: 1)
        let brownLight = UIColor(red: 0.5, green: 0.33, blue: 0.16, alpha: 1)
        // Tail feathers: white, black tipped, fanned behind.
        for i in 0..<7 {
            let a = CGFloat(i - 3) * 0.13
            let base = p(-1.1, 0)
            let tip = CGPoint(x: base.x - cos(a) * 1.3 * u, y: base.y - sin(a) * 1.3 * u - 0.1 * u)
            let feather = Draw.capsule(from: base, to: tip, radius: 0.12 * u)
            Draw.shade(c, feather, [.white, UIColor(white: 0.8, alpha: 1)], from: p(-1.1, 0.3), to: p(-1.1, -0.4))
            Draw.fill(c, Draw.circle(at: tip, r: 0.11 * u), UIColor(white: 0.1, alpha: 1))
        }
        // Body with its feather rows.
        let body = Draw.smooth([p(-1.3, 0.15), p(-0.5, 0.5), p(0.6, 0.55), p(1.3, 0.35), p(1.35, -0.15), p(0.7, -0.55), p(-0.3, -0.55), p(-1.2, -0.25)], tension: 0.5)
        Draw.shadowed(c, blur: 14, offset: CGSize(width: 0, height: -6)) {
            Draw.sphere(c, body, [brownLight, brown, brownDark], light: p(0, 0.5), radius: 1.5 * u)
        }
        c.saveGState()
        c.addPath(body)
        c.clip()
        for row in 0..<5 {
            for i in 0..<9 {
                let x = -1.2 + CGFloat(i) * 0.3 + CGFloat(row % 2) * 0.15
                let y = 0.4 - CGFloat(row) * 0.2
                Draw.feather(c, at: p(x, y), rx: 0.17 * u, ry: 0.1 * u, dark: brownDark, light: brownLight)
            }
        }
        c.restoreGState()
        // Legs and talons.
        for x in [CGFloat(0.35), 0.65] {
            Draw.fill(c, Draw.capsule(from: p(x, -0.35), to: p(x + 0.1, -0.8), radius: 0.07 * u), UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1))
            for k in -1...1 {
                let claw = Draw.capsule(from: p(x + 0.1, -0.8), to: p(x + 0.1 + CGFloat(k) * 0.14, -1.0), radius: 0.035 * u)
                Draw.fill(c, claw, UIColor(red: 0.85, green: 0.65, blue: 0.1, alpha: 1))
                Draw.fill(c, Draw.circle(at: p(x + 0.1 + CGFloat(k) * 0.14, -1.0), r: 0.035 * u), .black)
            }
        }
        // Neck and head, white with feather strokes.
        let head = Draw.smooth([p(0.9, 0.55), p(1.5, 0.95), p(2.0, 0.9), p(2.15, 0.55), p(1.95, 0.25), p(1.5, 0.1), p(1.1, 0.1)], tension: 0.5)
        Draw.shadowed(c, blur: 8, offset: CGSize(width: 0, height: -3)) {
            Draw.sphere(c, head, [.white, UIColor(white: 0.85, alpha: 1), UIColor(white: 0.6, alpha: 1)], light: p(1.5, 0.8), radius: 0.9 * u)
        }
        c.saveGState()
        c.addPath(head)
        c.clip()
        for i in 0..<18 {
            let s = CGMutablePath()
            let x = 0.95 + CGFloat(Anim.hash(i, 61)) * 0.9, y = 0.15 + CGFloat(Anim.hash(i, 62)) * 0.7
            s.move(to: p(x, y))
            s.addLine(to: p(x - 0.18, y - 0.05))
            Draw.stroke(c, s, UIColor(white: 0.7, alpha: 0.7), width: 2)
        }
        c.restoreGState()
        // Beak: hooked, yellow with a dark tip; the brow and the eye.
        let beak = Draw.smooth([p(2.0, 0.75), p(2.55, 0.62), p(2.75, 0.35), p(2.6, 0.2), p(2.45, 0.32), p(2.05, 0.35)], tension: 0.4)
        Draw.sphere(c, beak, [Metal.emberBright, UIColor(red: 0.9, green: 0.6, blue: 0.05, alpha: 1), UIColor(red: 0.55, green: 0.3, blue: 0, alpha: 1)], light: p(2.2, 0.7), radius: 0.7 * u)
        Draw.fill(c, Draw.polygon([p(2.62, 0.4), p(2.75, 0.35), p(2.6, 0.2), p(2.5, 0.3)]), UIColor(white: 0.15, alpha: 1))
        let gape = CGMutablePath()
        gape.move(to: p(2.05, 0.4))
        gape.addLine(to: p(2.5, 0.33))
        Draw.stroke(c, gape, UIColor(red: 0.4, green: 0.2, blue: 0, alpha: 1), width: 2)
        Draw.fill(c, Draw.polygon([p(1.55, 0.78), p(2.05, 0.7), p(2.0, 0.6), p(1.6, 0.62)]), UIColor(white: 0.25, alpha: 1))
        Draw.fill(c, Draw.circle(at: p(1.8, 0.6), r: 0.09 * u), UIColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1))
        Draw.fill(c, Draw.circle(at: p(1.82, 0.6), r: 0.05 * u), .black)
        Draw.fill(c, Draw.circle(at: p(1.78, 0.64), r: 0.02 * u), .white)
    } }

    /// One wing, pointing up from the shoulder at the bottom. The far wing is
    /// the same sprite flipped and darkened.
    static let eagleWingSize = CGSize(width: 420, height: 440)
    /// Fraction of the texture where the shoulder is: the anchor of the sprite.
    static let eagleWingAnchor = CGPoint(x: 0.5, y: 0.04)

    static var eagleWing: SKTexture { Textures.make("eagle-wing", size: eagleWingSize) { c, size in
        wing(c, size: size, base: UIColor(red: 0.32, green: 0.2, blue: 0.09, alpha: 1), dark: UIColor(red: 0.12, green: 0.06, blue: 0.02, alpha: 1), light: UIColor(red: 0.5, green: 0.34, blue: 0.16, alpha: 1), tip: UIColor(red: 0.1, green: 0.05, blue: 0.02, alpha: 1), narrow: 1)
    } }

    /// A wing: a base silhouette, feather rows and separate primaries at the tip.
    private static func wing(_ c: CGContext, size: CGSize, base: UIColor, dark: UIColor, light: UIColor, tip: UIColor, narrow: CGFloat) {
        let u = size.height / 4.4
        let o = CGPoint(x: size.width / 2, y: size.height * 0.04)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u * narrow, y: o.y + y * u) }
        let outline = [
            p(0.15, 0), p(0.55, 0.4), p(0.65, 1.4), p(0.5, 2.6), p(0.2, 3.6), p(0.35, 4.1),
            p(0.0, 3.95), p(-0.2, 4.15), p(-0.35, 3.8), p(-0.6, 3.95), p(-0.65, 3.5), p(-0.9, 3.5), p(-0.85, 3.05), p(-1.05, 2.9), p(-0.9, 2.5), p(-0.85, 1.6), p(-0.55, 0.6), p(-0.3, 0.1),
        ]
        let path = Draw.smooth(outline, tension: 0.3)
        Draw.shadowed(c, blur: 16, offset: CGSize(width: -6, height: -6)) {
            Draw.shade(c, path, [light, base, dark], from: p(0.6, 0.2), to: p(-1, 3.6))
        }
        c.saveGState()
        c.addPath(path)
        c.clip()
        // Covert rows: scallops.
        for row in 0..<6 {
            for i in 0..<5 {
                let y = 0.4 + CGFloat(row) * 0.45
                let x = -0.75 + CGFloat(i) * 0.3 + CGFloat(row % 2) * 0.15
                Draw.feather(c, at: p(x, y), rx: 0.17 * u * narrow, ry: 0.22 * u, dark: dark, light: light)
            }
        }
        // Feather shafts radiating to the trailing edge.
        for i in 0..<10 {
            let s = CGMutablePath()
            s.move(to: p(0.1, 0.5))
            s.addLine(to: p(-1.0 + CGFloat(i) * 0.14, 2.6 + CGFloat(i) * 0.15))
            Draw.stroke(c, s, dark.withAlphaComponent(0.5), width: 2.5)
        }
        c.restoreGState()
        // Primaries: separate fingers at the tip.
        for i in 0..<6 {
            let root = p(0.25 - CGFloat(i) * 0.12, 2.3 + CGFloat(i) * 0.1)
            let end = p(0.3 - CGFloat(i) * 0.27, 4.2 - CGFloat(i) * 0.12)
            let feather = Draw.capsule(from: root, to: end, radius: 0.1 * u * narrow)
            Draw.shadowed(c, blur: 4, offset: CGSize(width: -2, height: -2)) {
                Draw.shade(c, feather, [base, tip], from: root, to: end)
            }
            let shaft = CGMutablePath()
            shaft.move(to: root)
            shaft.addLine(to: end)
            Draw.stroke(c, shaft, light.withAlphaComponent(0.5), width: 1.5)
        }
        Draw.stroke(c, path, dark, width: 2)
    }

    // MARK: Albatross

    static let albatrossBodySize = CGSize(width: 520, height: 260)
    static let albatrossShoulder = CGPoint(x: 240, y: 150)

    static var albatrossBody: SKTexture { Textures.make("albatross-body", size: albatrossBodySize) { c, size in
        let u: CGFloat = 90
        let o = CGPoint(x: 220, y: 130)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        let grey = UIColor(white: 0.72, alpha: 1)
        // Tail: short, wedge.
        let tail = Draw.polygon([p(-1.2, 0.25), p(-2.3, 0.15), p(-2.4, -0.1), p(-1.2, -0.3)])
        Draw.shade(c, tail, [.white, grey], from: p(-1.5, 0.3), to: p(-1.5, -0.3))
        Draw.fill(c, Draw.polygon([p(-2.1, 0.17), p(-2.4, 0.15), p(-2.4, -0.1), p(-2.1, -0.25)]), UIColor(white: 0.15, alpha: 1))
        // Body: long, white above, grey below.
        let body = Draw.smooth([p(-1.5, 0.1), p(-0.6, 0.45), p(0.8, 0.5), p(1.7, 0.3), p(1.8, -0.1), p(1.0, -0.45), p(-0.4, -0.5), p(-1.4, -0.25)], tension: 0.5)
        Draw.shadowed(c, blur: 12, offset: CGSize(width: 0, height: -6)) {
            Draw.sphere(c, body, [.white, UIColor(white: 0.93, alpha: 1), grey], light: p(0.2, 0.5), radius: 1.6 * u)
        }
        // Neck and head.
        let head = Draw.smooth([p(1.3, 0.5), p(1.9, 0.85), p(2.45, 0.8), p(2.6, 0.5), p(2.4, 0.25), p(1.9, 0.1), p(1.4, 0.05)], tension: 0.5)
        Draw.sphere(c, head, [.white, UIColor(white: 0.9, alpha: 1), grey], light: p(2.0, 0.75), radius: 0.9 * u)
        // The beak: long, hooked, pale pink to yellow.
        let beak = Draw.smooth([p(2.45, 0.68), p(3.25, 0.52), p(3.4, 0.3), p(3.2, 0.2), p(2.95, 0.3), p(2.45, 0.35)], tension: 0.4)
        Draw.sphere(c, beak, [UIColor(red: 1, green: 0.88, blue: 0.7, alpha: 1), UIColor(red: 0.95, green: 0.7, blue: 0.5, alpha: 1), UIColor(red: 0.7, green: 0.4, blue: 0.3, alpha: 1)], light: p(2.7, 0.65), radius: 0.9 * u)
        Draw.fill(c, Draw.polygon([p(3.25, 0.45), p(3.4, 0.3), p(3.2, 0.2), p(3.1, 0.32)]), UIColor(red: 0.5, green: 0.25, blue: 0.2, alpha: 1))
        let gape = CGMutablePath()
        gape.move(to: p(2.5, 0.45))
        gape.addLine(to: p(3.15, 0.33))
        Draw.stroke(c, gape, UIColor(red: 0.55, green: 0.3, blue: 0.25, alpha: 1), width: 2)
        // Dark eye patch and the eye.
        Draw.fill(c, Draw.ellipse(at: p(2.1, 0.55), rx: 0.2 * u, ry: 0.12 * u), UIColor(white: 0.35, alpha: 0.7))
        Draw.fill(c, Draw.circle(at: p(2.12, 0.55), r: 0.07 * u), .black)
        Draw.fill(c, Draw.circle(at: p(2.09, 0.58), r: 0.025 * u), .white)
        // Feet tucked back.
        for x in [CGFloat(-0.3), -0.05] {
            Draw.fill(c, Draw.capsule(from: p(x, -0.4), to: p(x - 0.4, -0.55), radius: 0.05 * u), UIColor(red: 0.85, green: 0.7, blue: 0.6, alpha: 1))
        }
    } }

    static let albatrossWingSize = CGSize(width: 300, height: 700)
    static let albatrossWingAnchor = CGPoint(x: 0.5, y: 0.03)

    static var albatrossWing: SKTexture { Textures.make("albatross-wing", size: albatrossWingSize) { c, size in
        wing(c, size: size, base: UIColor(white: 0.95, alpha: 1), dark: UIColor(white: 0.55, alpha: 1), light: .white, tip: UIColor(white: 0.08, alpha: 1), narrow: 0.75)
    } }

    // MARK: A small bird, for the birdie

    static let birdSize = CGSize(width: 160, height: 120)

    static var bird: SKTexture { Textures.make("bird", size: birdSize) { c, size in
        let u: CGFloat = 40
        let o = CGPoint(x: 70, y: 50)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * u, y: o.y + y * u) }
        let red = Metal.bloodBright
        let dark = Metal.bloodDark
        Draw.fill(c, Draw.polygon([p(-0.7, 0.1), p(-1.6, 0.5), p(-1.5, -0.2)]), dark)
        let body = Draw.ellipse(at: p(0, 0), rx: 0.95 * u, ry: 0.7 * u)
        Draw.sphere(c, body, [red, dark], light: p(-0.3, 0.4), radius: 1.3 * u)
        Draw.sphere(c, Draw.ellipse(at: p(0.1, -0.15), rx: 0.55 * u, ry: 0.4 * u), [Metal.bone, Metal.boneShade], light: p(0, 0), radius: 0.7 * u)
        let wing = Draw.smooth([p(-0.6, 0.3), p(0.1, 0.5), p(0.3, 0.1), p(-0.3, -0.1)], tension: 0.5)
        Draw.shade(c, wing, [red, dark], from: p(0, 0.5), to: p(0, -0.1))
        Draw.sphere(c, Draw.circle(at: p(0.85, 0.55), r: 0.5 * u), [red, dark], light: p(0.7, 0.75), radius: 0.7 * u)
        Draw.fill(c, Draw.polygon([p(1.25, 0.6), p(1.95, 0.5), p(1.25, 0.35)]), Metal.emberBright)
        Draw.fill(c, Draw.circle(at: p(1.0, 0.65), r: 0.1 * u), .black)
        Draw.fill(c, Draw.circle(at: p(0.97, 0.69), r: 0.035 * u), .white)
        for x in [CGFloat(-0.15), 0.2] {
            Draw.stroke(c, Draw.capsule(from: p(x, -0.6), to: p(x, -1.1), radius: 0.001), Metal.emberBright, width: 3)
        }
    } }
}

extension Draw {
    /// One feather of a row: a U-shaped tip, shadow below and a lit edge.
    static func feather(_ c: CGContext, at center: CGPoint, rx: CGFloat, ry: CGFloat, dark: UIColor, light: UIColor) {
        let tip = CGMutablePath()
        var transform = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: rx, y: ry)
        tip.addArc(center: .zero, radius: 1, startAngle: .pi, endAngle: 0, clockwise: true, transform: transform)
        stroke(c, tip, dark.withAlphaComponent(0.75), width: 3)
        transform = transform.translatedBy(x: 0, y: 2.5 / ry)
        let edge = CGMutablePath()
        edge.addArc(center: .zero, radius: 1, startAngle: .pi, endAngle: 0, clockwise: true, transform: transform)
        stroke(c, edge, light.withAlphaComponent(0.45), width: 1.5)
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
