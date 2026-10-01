import SpriteKit
import UIKit

/// The creatures of the shows, drawn once into textures: layered paths with
/// gradients lit from the top left, fur and feather strokes, outlines.
/// Coordinates in the drawings are y up, like SpriteKit.
@MainActor
enum Art {
    // MARK: Wolf

    /// The head without its lower jaw, 560 points square; the mouth line is
    /// at `wolfMouthY` from the bottom. The jaw hangs under it.
    static let wolfHeadSize = CGSize(width: 560, height: 560)
    static let wolfMouthY: CGFloat = 253

    static var wolfHead: SKTexture { Textures.make("wolf-head", size: wolfHeadSize) { c, size in
        let u: CGFloat = 110
        let cx = size.width / 2, cy: CGFloat = 310
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * u, y: cy + y * u) }
        let furDark = UIColor(red: 0.16, green: 0.15, blue: 0.17, alpha: 1)
        let fur = UIColor(red: 0.36, green: 0.35, blue: 0.38, alpha: 1)
        let furLight = UIColor(red: 0.55, green: 0.54, blue: 0.56, alpha: 1)

        // The mane: spikes all round, darkest layer.
        var mane: [CGPoint] = []
        for i in 0..<36 {
            let a = CGFloat(i) / 36 * .pi * 2
            let r: CGFloat = i % 2 == 0 ? 1.55 : 1.2
            mane.append(p(cos(a) * r * 1.05, sin(a) * r * 0.95 + 0.05))
        }
        Draw.shadowed(c, blur: 30, offset: .zero, color: UIColor.black.withAlphaComponent(0.9)) {
            Draw.shade(c, Draw.polygon(mane), [UIColor(red: 0.24, green: 0.22, blue: 0.25, alpha: 1), furDark], from: p(0, 1.5), to: p(0, -1))
        }
        // Ears, behind the head.
        for s in [CGFloat(-1), 1] {
            let ear = Draw.polygon([p(s * 0.95, 0.75), p(s * 1.15, 1.85), p(s * 0.3, 1.05)])
            Draw.shade(c, ear, [fur, furDark], from: p(s * 0.9, 1.6), to: p(s * 0.5, 0.8))
            let inner = Draw.polygon([p(s * 0.9, 0.85), p(s * 1.05, 1.6), p(s * 0.45, 1.0)])
            Draw.shade(c, inner, [UIColor(red: 0.5, green: 0.28, blue: 0.3, alpha: 1), UIColor(red: 0.25, green: 0.1, blue: 0.12, alpha: 1)], from: p(s * 0.9, 1.5), to: p(s * 0.6, 0.9))
            Draw.fur(c, along: [p(s * 0.95, 0.75), p(s * 1.15, 1.85), p(s * 0.3, 1.05)], length: 14, color: furLight.withAlphaComponent(0.5), seed: 40 + Int(s))
        }
        // The head.
        let head = [
            p(-0.4, 1.05), p(0.4, 1.05), p(1.0, 0.85), p(1.2, 0.2), p(1.05, -0.45), p(0.6, -0.9), p(0, -1.0), p(-0.6, -0.9), p(-1.05, -0.45), p(-1.2, 0.2), p(-1.0, 0.85),
        ]
        let headPath = Draw.smooth(head, tension: 0.6)
        Draw.sphere(c, headPath, [furLight, fur, furDark], light: p(-0.3, 0.7), radius: 2.1 * u)
        Draw.fur(c, along: Draw.resample(head, count: 90), length: 16, color: furDark, seed: 7)
        Draw.fur(c, along: Draw.resample(head, count: 60), length: 10, color: furLight.withAlphaComponent(0.6), seed: 9)
        // Cheek tufts.
        for s in [CGFloat(-1), 1] {
            let tuft = Draw.polygon([p(s * 1.0, 0.1), p(s * 1.55, 0.3), p(s * 1.1, -0.15), p(s * 1.5, -0.35), p(s * 0.95, -0.5)])
            Draw.shade(c, tuft, [fur, furDark], from: p(s * 1.0, 0.2), to: p(s * 1.5, -0.4))
        }
        // Brow ridge, heavy and angry.
        for s in [CGFloat(-1), 1] {
            let brow = Draw.polygon([p(s * 1.0, 0.6), p(s * 0.18, 0.28), p(s * 0.15, 0.5), p(s * 0.95, 0.85)])
            Draw.shade(c, brow, [furDark, UIColor(red: 0.08, green: 0.07, blue: 0.08, alpha: 1)], from: p(s * 0.5, 0.7), to: p(s * 0.5, 0.3))
        }
        // Eyes: an ember glow, the iris, the slit and a glint.
        for s in [CGFloat(-1), 1] {
            let e = p(s * 0.55, 0.3)
            c.saveGState()
            c.drawRadialGradient(Draw.gradient([Metal.ember.withAlphaComponent(0.7), Metal.ember.withAlphaComponent(0)]), startCenter: e, startRadius: 0, endCenter: e, endRadius: 0.5 * u, options: [])
            c.restoreGState()
            c.saveGState()
            c.translateBy(x: e.x, y: e.y)
            c.rotate(by: s * 0.25)
            let eye = Draw.ellipse(at: .zero, rx: 0.3 * u, ry: 0.15 * u)
            Draw.sphere(c, eye, [Metal.emberBright, UIColor(red: 0.95, green: 0.55, blue: 0.05, alpha: 1), UIColor(red: 0.6, green: 0.2, blue: 0, alpha: 1)], light: CGPoint(x: -0.08 * u, y: 0.05 * u), radius: 0.32 * u)
            Draw.fill(c, Draw.ellipse(at: .zero, rx: 0.05 * u, ry: 0.13 * u), .black)
            Draw.fill(c, Draw.circle(at: CGPoint(x: -0.1 * u, y: 0.06 * u), r: 0.03 * u), UIColor.white.withAlphaComponent(0.9))
            Draw.stroke(c, eye, UIColor.black.withAlphaComponent(0.8), width: 3)
            c.restoreGState()
        }
        // Muzzle and nose.
        let muzzle = Draw.ellipse(at: p(0, -0.3), rx: 0.7 * u, ry: 0.55 * u)
        Draw.sphere(c, muzzle, [UIColor(red: 0.66, green: 0.65, blue: 0.67, alpha: 1), fur, furDark], light: p(-0.2, -0.05), radius: 0.9 * u)
        let nose = Draw.smooth([p(-0.26, 0.12), p(0.26, 0.12), p(0.2, -0.08), p(0, -0.24), p(-0.2, -0.08)], tension: 0.5)
        Draw.sphere(c, nose, [UIColor(white: 0.3, alpha: 1), .black], light: p(-0.08, 0.05), radius: 0.3 * u)
        Draw.fill(c, Draw.ellipse(at: p(-0.1, -0.02), rx: 0.05 * u, ry: 0.03 * u), UIColor.white.withAlphaComponent(0.35))
        // Mouth: the dark inside, the gums and the upper fangs. The lower jaw covers the bottom.
        let mouthTop = p(0, -0.52).y
        let inside = Draw.polygon([p(-0.72, -0.5), p(0.72, -0.5), p(0.66, -1.6), p(-0.66, -1.6)])
        Draw.shade(c, inside, [Metal.bloodDark, UIColor(red: 0.1, green: 0, blue: 0.01, alpha: 1)], from: CGPoint(x: cx, y: mouthTop), to: p(0, -1.6))
        Draw.fill(c, Draw.polygon([p(-0.72, -0.5), p(0.72, -0.5), p(0.72, -0.62), p(-0.72, -0.62)]), UIColor(red: 0.45, green: 0.12, blue: 0.16, alpha: 1))
        for i in 0..<9 {
            let x = -0.62 + CGFloat(i) * 0.155
            let fang = i == 0 || i == 8
            let len: CGFloat = fang ? 0.42 : (i % 2 == 0 ? 0.16 : 0.11)
            let tooth = Draw.polygon([p(x - 0.065, -0.52), p(x + 0.065, -0.52), p(x, -0.52 - len)])
            Draw.shadowed(c, blur: 3, offset: CGSize(width: 0, height: -2)) {
                Draw.shade(c, tooth, [Metal.bone, Metal.boneShade], from: p(x - 0.07, -0.5), to: p(x + 0.07, -0.9))
            }
        }
        // Drool from the fangs.
        for s in [CGFloat(-1), 1] {
            let drip = Draw.capsule(from: p(s * 0.6, -0.9), to: p(s * 0.58, -1.25), radius: 0.025 * u)
            Draw.fill(c, drip, UIColor(red: 0.85, green: 0.9, blue: 0.9, alpha: 0.55))
        }
        // Upper lip.
        let lip = CGMutablePath()
        lip.move(to: p(-0.75, -0.48))
        lip.addQuadCurve(to: p(0.75, -0.48), control: p(0, -0.4))
        Draw.stroke(c, lip, UIColor.black.withAlphaComponent(0.7), width: 5)
    } }

    /// The lower jaw, anchored at its top middle where it meets the head.
    static let wolfJawSize = CGSize(width: 360, height: 250)

    static var wolfJaw: SKTexture { Textures.make("wolf-jaw", size: wolfJawSize) { c, size in
        let u: CGFloat = 110
        let cx = size.width / 2, top = size.height - 10
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x * u, y: top + y * u) }
        let fur = UIColor(red: 0.34, green: 0.33, blue: 0.36, alpha: 1)
        let furDark = UIColor(red: 0.14, green: 0.13, blue: 0.15, alpha: 1)
        let chin = Draw.smooth([p(-0.8, 0), p(0.8, 0), p(0.72, -0.9), p(0.32, -1.4), p(-0.32, -1.4), p(-0.72, -0.9)], tension: 0.4)
        Draw.shadowed(c, blur: 12, offset: CGSize(width: 0, height: -6), color: UIColor.black.withAlphaComponent(0.8)) {
            Draw.shade(c, chin, [fur, furDark], from: p(0, 0), to: p(0, -2))
        }
        Draw.fur(c, along: Draw.resample([p(0.75, -0.3), p(0.72, -0.9), p(0.32, -1.4), p(-0.32, -1.4), p(-0.72, -0.9), p(-0.75, -0.3)], count: 40), length: 12, color: furDark, seed: 21)
        let inside = Draw.polygon([p(-0.68, 0), p(0.68, 0), p(0.52, -0.95), p(-0.52, -0.95)])
        Draw.shade(c, inside, [Metal.bloodDark, UIColor(red: 0.12, green: 0, blue: 0.02, alpha: 1)], from: p(0, -0.95), to: p(0, 0))
        let tongue = Draw.ellipse(at: p(0, -0.45), rx: 0.38 * u, ry: 0.3 * u)
        Draw.sphere(c, tongue, [UIColor(red: 0.95, green: 0.45, blue: 0.5, alpha: 1), UIColor(red: 0.6, green: 0.12, blue: 0.2, alpha: 1)], light: p(-0.1, -0.3), radius: 0.5 * u)
        Draw.fill(c, Draw.polygon([p(-0.68, 0), p(0.68, 0), p(0.68, -0.1), p(-0.68, -0.1)]), UIColor(red: 0.45, green: 0.12, blue: 0.16, alpha: 1))
        for i in 0..<8 {
            let x = -0.56 + CGFloat(i) * 0.16
            let fang = i == 0 || i == 7
            let len: CGFloat = fang ? 0.36 : (i % 2 == 0 ? 0.13 : 0.09)
            let tooth = Draw.polygon([p(x - 0.06, -0.06), p(x + 0.06, -0.06), p(x, -0.06 + len)])
            Draw.shade(c, tooth, [Metal.bone, Metal.boneShade], from: p(x - 0.06, 0.2), to: p(x + 0.06, -0.1))
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

    /// Evenly spaced points along a closed polyline, for fur along a smooth outline.
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
