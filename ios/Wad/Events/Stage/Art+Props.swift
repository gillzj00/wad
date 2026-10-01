import SpriteKit
import UIKit

extension Art {
    // MARK: Golf

    static var golfBall: SKTexture { Textures.make("golf-ball", size: CGSize(width: 200, height: 200)) { c, size in
        let center = CGPoint(x: 100, y: 100)
        let ball = Draw.circle(at: center, r: 92)
        Draw.shadowed(c, blur: 10, offset: CGSize(width: 0, height: -6), color: UIColor.black.withAlphaComponent(0.7)) {
            Draw.sphere(c, ball, [.white, UIColor(white: 0.92, alpha: 1), UIColor(white: 0.55, alpha: 1), UIColor(white: 0.3, alpha: 1)], light: CGPoint(x: 70, y: 135), radius: 125)
        }
        c.saveGState()
        c.addPath(ball)
        c.clip()
        for row in 0..<9 {
            for col in 0..<9 {
                let x = 20 + CGFloat(col) * 20 + CGFloat(row % 2) * 10
                let y = 20 + CGFloat(row) * 20
                let d = hypot(x - center.x, y - center.y)
                guard d < 80 else { continue }
                // Dimples shrink toward the edge as the sphere turns away.
                let r = 6 * (1 - d / 95)
                let shade = 0.45 + 0.4 * (1 - (x - 70 + y - 135) / 300)
                Draw.fill(c, Draw.circle(at: CGPoint(x: x, y: y), r: r), UIColor(white: shade, alpha: 0.35))
                Draw.fill(c, Draw.circle(at: CGPoint(x: x - 1.5, y: y + 1.5), r: r * 0.5), UIColor.white.withAlphaComponent(0.5))
            }
        }
        c.restoreGState()
    } }

    /// Pole and flag, anchored at the bottom of the pole.
    static let flagSize = CGSize(width: 220, height: 440)

    static var flag: SKTexture { Textures.make("flag", size: flagSize) { c, size in
        let x: CGFloat = 30
        let pole = CGPath(roundedRect: CGRect(x: x - 5, y: 0, width: 10, height: 420), cornerWidth: 5, cornerHeight: 5, transform: nil)
        Draw.shadowed(c, blur: 6, offset: CGSize(width: 3, height: -3)) {
            Draw.shade(c, pole, [Metal.bone, Metal.boneShade, Metal.boneDark], from: CGPoint(x: x - 5, y: 0), to: CGPoint(x: x + 5, y: 0))
        }
        Draw.fill(c, Draw.circle(at: CGPoint(x: x, y: 422), r: 9), Metal.boneShade)
        let cloth = Draw.smooth([CGPoint(x: x + 5, y: 415), CGPoint(x: 200, y: 370), CGPoint(x: 150, y: 330), CGPoint(x: 205, y: 290), CGPoint(x: x + 5, y: 270)], tension: 0.3)
        Draw.shadowed(c, blur: 8, offset: CGSize(width: 4, height: -4)) {
            Draw.shade(c, cloth, [Metal.bloodBright, Metal.blood, Metal.bloodDark], from: CGPoint(x: x, y: 415), to: CGPoint(x: 200, y: 290))
        }
        // A fold.
        Draw.fill(c, Draw.polygon([CGPoint(x: 90, y: 395), CGPoint(x: 150, y: 330), CGPoint(x: 90, y: 285)]), Metal.bloodDark.withAlphaComponent(0.5))
        // A skull on the flag, small.
        c.saveGState()
        c.translateBy(x: 55, y: 310)
        c.scaleBy(x: 0.2, y: 0.2)
        skullStamp(c)
        c.restoreGState()
    } }

    private static func skullStamp(_ c: CGContext) {
        let cranium = Draw.ellipse(at: CGPoint(x: 150, y: 220), rx: 115, ry: 110)
        Draw.fill(c, cranium, Metal.bone)
        Draw.fill(c, CGPath(roundedRect: CGRect(x: 80, y: 60, width: 140, height: 90), cornerWidth: 25, cornerHeight: 25, transform: nil), Metal.bone)
        for s in [CGFloat(-1), 1] {
            Draw.fill(c, Draw.ellipse(at: CGPoint(x: 150 + s * 50, y: 210), rx: 36, ry: 32), Metal.bloodDark)
        }
        Draw.fill(c, Draw.polygon([CGPoint(x: 135, y: 160), CGPoint(x: 165, y: 160), CGPoint(x: 150, y: 125)]), Metal.bloodDark)
        for i in 0..<5 {
            Draw.fill(c, CGRect(x: 100 + CGFloat(i) * 22, y: 60, width: 12, height: 35), Metal.bloodDark)
        }
    }

    static func fill(_ c: CGContext, _ rect: CGRect, _ color: UIColor) {
        c.setFillColor(color.cgColor)
        c.fill(rect)
    }

    /// The cup in the green, seen from above at an angle.
    static var cup: SKTexture { Textures.make("cup", size: CGSize(width: 160, height: 70)) { c, size in
        Draw.fill(c, Draw.ellipse(at: CGPoint(x: 80, y: 35), rx: 78, ry: 30), UIColor(red: 0.05, green: 0.12, blue: 0.04, alpha: 1))
        Draw.sphere(c, Draw.ellipse(at: CGPoint(x: 80, y: 33), rx: 68, ry: 24), [UIColor(white: 0.12, alpha: 1), .black], light: CGPoint(x: 80, y: 20), radius: 70)
        Draw.stroke(c, Draw.ellipse(at: CGPoint(x: 80, y: 35), rx: 72, ry: 27), UIColor(white: 0.85, alpha: 0.7), width: 3)
    } }

    /// Chunks of green blown out of the ground.
    static var turf: [SKTexture] { (0..<3).map { (i: Int) -> SKTexture in
        Textures.make("turf-\(i)", size: CGSize(width: 90, height: 70)) { c, size in
            let points = (0..<7).map { k -> CGPoint in
                let a = CGFloat(k) / 7 * .pi * 2
                let r = 28 + CGFloat(Anim.hash(k + i * 10, 95)) * 14
                return CGPoint(x: 45 + cos(a) * r, y: 35 + sin(a) * r * 0.8)
            }
            let chunk = Draw.polygon(points)
            Draw.shade(c, chunk, [UIColor(red: 0.25, green: 0.5, blue: 0.15, alpha: 1), UIColor(red: 0.3, green: 0.18, blue: 0.08, alpha: 1), UIColor(red: 0.15, green: 0.08, blue: 0.03, alpha: 1)], from: CGPoint(x: 0, y: 60), to: CGPoint(x: 0, y: 10))
            Draw.fur(c, along: Array(points.prefix(4)), length: 10, color: UIColor(red: 0.35, green: 0.65, blue: 0.2, alpha: 1), seed: 96 + i)
        }
    } }

    // MARK: Champagne

    static let bottleSize = CGSize(width: 180, height: 560)
    /// Where the neck opens, as a fraction of the texture.
    static let bottleMouth = CGPoint(x: 0.5, y: 0.985)

    static var bottle: SKTexture { Textures.make("bottle", size: bottleSize) { c, size in
        let cx = size.width / 2
        let body = Draw.smooth([CGPoint(x: cx - 70, y: 20), CGPoint(x: cx + 70, y: 20), CGPoint(x: cx + 72, y: 300), CGPoint(x: cx + 40, y: 380), CGPoint(x: cx + 22, y: 420), CGPoint(x: cx + 22, y: 540), CGPoint(x: cx - 22, y: 540), CGPoint(x: cx - 22, y: 420), CGPoint(x: cx - 40, y: 380), CGPoint(x: cx - 72, y: 300)], tension: 0.35)
        Draw.shadowed(c, blur: 16, offset: CGSize(width: 0, height: -8), color: UIColor.black.withAlphaComponent(0.8)) {
            Draw.shade(c, body, [UIColor(red: 0.03, green: 0.14, blue: 0.06, alpha: 1), UIColor(red: 0.12, green: 0.38, blue: 0.16, alpha: 1), UIColor(red: 0.05, green: 0.2, blue: 0.08, alpha: 1), UIColor(red: 0.01, green: 0.06, blue: 0.02, alpha: 1)], from: CGPoint(x: cx - 72, y: 0), to: CGPoint(x: cx + 72, y: 0))
        }
        // A highlight stripe down the left and the base.
        Draw.fill(c, CGPath(roundedRect: CGRect(x: cx - 50, y: 60, width: 14, height: 300), cornerWidth: 7, cornerHeight: 7, transform: nil), UIColor.white.withAlphaComponent(0.18))
        Draw.fill(c, Draw.ellipse(at: CGPoint(x: cx, y: 24), rx: 66, ry: 12), UIColor.black.withAlphaComponent(0.5))
        // Foil and label.
        let foil = Draw.polygon([CGPoint(x: cx - 24, y: 470), CGPoint(x: cx + 24, y: 470), CGPoint(x: cx + 24, y: 545), CGPoint(x: cx - 24, y: 545)])
        Draw.shade(c, foil, [UIColor(red: 0.6, green: 0.45, blue: 0.05, alpha: 1), Metal.emberBright, UIColor(red: 0.75, green: 0.55, blue: 0.1, alpha: 1)], from: CGPoint(x: cx - 24, y: 0), to: CGPoint(x: cx + 24, y: 0))
        Draw.fill(c, CGRect(x: cx - 24, y: 478, width: 48, height: 6), Metal.bloodDark)
        let label = CGPath(roundedRect: CGRect(x: cx - 52, y: 120, width: 104, height: 150), cornerWidth: 6, cornerHeight: 6, transform: nil)
        Draw.shade(c, label, [Metal.bone, Metal.boneShade], from: CGPoint(x: cx - 52, y: 0), to: CGPoint(x: cx + 52, y: 0))
        Draw.fill(c, CGRect(x: cx - 52, y: 230, width: 104, height: 14), Metal.blood)
        Draw.fill(c, CGRect(x: cx - 52, y: 140, width: 104, height: 8), Metal.blood)
        c.saveGState()
        c.translateBy(x: cx - 30, y: 150)
        c.scaleBy(x: 0.2, y: 0.2)
        skullStamp(c)
        c.restoreGState()
    } }

    static var cork: SKTexture { Textures.make("cork", size: CGSize(width: 60, height: 80)) { c, size in
        let shape = Draw.smooth([CGPoint(x: 14, y: 6), CGPoint(x: 46, y: 6), CGPoint(x: 50, y: 40), CGPoint(x: 56, y: 70), CGPoint(x: 30, y: 78), CGPoint(x: 4, y: 70), CGPoint(x: 10, y: 40)], tension: 0.4)
        Draw.shade(c, shape, [UIColor(red: 0.85, green: 0.7, blue: 0.45, alpha: 1), UIColor(red: 0.6, green: 0.42, blue: 0.22, alpha: 1)], from: CGPoint(x: 10, y: 0), to: CGPoint(x: 50, y: 0))
        for y in [CGFloat(20), 36] {
            Draw.fill(c, CGRect(x: 12, y: y, width: 36, height: 3), UIColor(red: 0.5, green: 0.32, blue: 0.15, alpha: 0.7))
        }
    } }

    // MARK: Money

    static let billSize = CGSize(width: 160, height: 72)

    static var bill: SKTexture { Textures.make("bill", size: billSize) { c, size in
        let outer = CGPath(roundedRect: CGRect(x: 2, y: 2, width: 156, height: 68), cornerWidth: 4, cornerHeight: 4, transform: nil)
        Draw.shade(c, outer, [UIColor(red: 0.55, green: 0.75, blue: 0.5, alpha: 1), UIColor(red: 0.35, green: 0.58, blue: 0.33, alpha: 1)], from: CGPoint(x: 0, y: 70), to: CGPoint(x: 160, y: 0))
        Draw.stroke(c, CGPath(rect: CGRect(x: 9, y: 9, width: 142, height: 54), transform: nil), UIColor(red: 0.15, green: 0.3, blue: 0.15, alpha: 1), width: 2.5)
        Draw.fill(c, Draw.ellipse(at: CGPoint(x: 80, y: 36), rx: 24, ry: 20), UIColor(red: 0.8, green: 0.88, blue: 0.75, alpha: 1))
        c.saveGState()
        c.translateBy(x: 65, y: 22)
        c.scaleBy(x: 0.1, y: 0.1)
        skullStamp(c)
        c.restoreGState()
        for corner in [CGPoint(x: 24, y: 36), CGPoint(x: 136, y: 36)] {
            Draw.fill(c, Draw.circle(at: corner, r: 12), UIColor(red: 0.15, green: 0.3, blue: 0.15, alpha: 1))
            dollar(c, at: corner, size: 18, color: UIColor(red: 0.8, green: 0.9, blue: 0.75, alpha: 1))
        }
    } }

    static var coin: SKTexture { Textures.make("coin", size: CGSize(width: 90, height: 90)) { c, size in
        let center = CGPoint(x: 45, y: 45)
        Draw.shadowed(c, blur: 6, offset: CGSize(width: 0, height: -3)) {
            Draw.sphere(c, Draw.circle(at: center, r: 40), [Metal.emberBright, UIColor(red: 0.85, green: 0.6, blue: 0.1, alpha: 1), UIColor(red: 0.5, green: 0.3, blue: 0.02, alpha: 1)], light: CGPoint(x: 32, y: 58), radius: 55)
        }
        Draw.stroke(c, Draw.circle(at: center, r: 33), UIColor(red: 0.55, green: 0.35, blue: 0.05, alpha: 0.8), width: 3)
        dollar(c, at: center, size: 40, color: UIColor(red: 0.55, green: 0.35, blue: 0.05, alpha: 1))
    } }

    /// A dollar sign drawn as a path, so nothing depends on a font.
    static func dollar(_ c: CGContext, at p: CGPoint, size s: CGFloat, color: UIColor) {
        let path = CGMutablePath()
        let r = s * 0.22
        path.move(to: CGPoint(x: p.x + r, y: p.y + r * 1.1))
        path.addArc(center: CGPoint(x: p.x, y: p.y + r * 0.7), radius: r, startAngle: 0.2, endAngle: .pi * 1.5, clockwise: false)
        path.addArc(center: CGPoint(x: p.x, y: p.y - r * 0.7), radius: r, startAngle: .pi / 2, endAngle: .pi * 2.2, clockwise: true)
        Draw.stroke(c, path, color, width: s * 0.13, cap: .round)
        let bar = CGMutablePath()
        bar.move(to: CGPoint(x: p.x, y: p.y + s * 0.5))
        bar.addLine(to: CGPoint(x: p.x, y: p.y - s * 0.5))
        Draw.stroke(c, bar, color, width: s * 0.1)
    }

    // MARK: Snowman

    /// A snowball lit from the top left, with a cold shadow.
    static func snowball(_ key: String) -> SKTexture {
        Textures.make("snowball-\(key)", size: CGSize(width: 300, height: 300)) { c, size in
            let center = CGPoint(x: 150, y: 150)
            let ball = Draw.circle(at: center, r: 140)
            Draw.shadowed(c, blur: 12, offset: CGSize(width: 0, height: -8), color: UIColor.black.withAlphaComponent(0.7)) {
                Draw.sphere(c, ball, [.white, UIColor(red: 0.93, green: 0.95, blue: 1, alpha: 1), UIColor(red: 0.6, green: 0.68, blue: 0.82, alpha: 1), UIColor(red: 0.35, green: 0.4, blue: 0.55, alpha: 1)], light: CGPoint(x: 100, y: 200), radius: 200)
            }
            c.saveGState()
            c.addPath(ball)
            c.clip()
            for i in 0..<40 {
                let p = CGPoint(x: 30 + CGFloat(Anim.hash(i, 100)) * 240, y: 30 + CGFloat(Anim.hash(i, 101)) * 240)
                Draw.fill(c, Draw.circle(at: p, r: 1.5 + CGFloat(Anim.hash(i, 102)) * 2), UIColor.white.withAlphaComponent(0.6))
            }
            c.restoreGState()
        }
    }

    static var topHat: SKTexture { Textures.make("top-hat", size: CGSize(width: 240, height: 200)) { c, size in
        let brim = Draw.ellipse(at: CGPoint(x: 120, y: 40), rx: 115, ry: 22)
        Draw.shadowed(c, blur: 10, offset: CGSize(width: 0, height: -6)) {
            Draw.shade(c, brim, [UIColor(white: 0.22, alpha: 1), UIColor(white: 0.03, alpha: 1)], from: CGPoint(x: 0, y: 62), to: CGPoint(x: 0, y: 18))
        }
        let crown = CGPath(roundedRect: CGRect(x: 48, y: 40, width: 144, height: 150), cornerWidth: 8, cornerHeight: 8, transform: nil)
        Draw.shade(c, crown, [UIColor(white: 0.3, alpha: 1), UIColor(white: 0.1, alpha: 1), UIColor(white: 0.02, alpha: 1)], from: CGPoint(x: 48, y: 0), to: CGPoint(x: 192, y: 0))
        Draw.fill(c, CGRect(x: 48, y: 50, width: 144, height: 22), Metal.blood)
        Draw.fill(c, Draw.ellipse(at: CGPoint(x: 120, y: 190), rx: 72, ry: 10), UIColor(white: 0.18, alpha: 1))
    } }

    static var carrot: SKTexture { Textures.make("carrot", size: CGSize(width: 140, height: 50)) { c, size in
        let shape = Draw.polygon([CGPoint(x: 4, y: 25), CGPoint(x: 30, y: 46), CGPoint(x: 136, y: 28), CGPoint(x: 30, y: 4)])
        Draw.shade(c, shape, [Metal.emberBright, Metal.ember, UIColor(red: 0.6, green: 0.2, blue: 0, alpha: 1)], from: CGPoint(x: 0, y: 46), to: CGPoint(x: 0, y: 4))
        for x in [CGFloat(40), 70, 100] {
            Draw.fill(c, CGRect(x: x, y: 12, width: 3, height: 26), UIColor(red: 0.6, green: 0.2, blue: 0, alpha: 0.5))
        }
    } }

    static var coal: SKTexture { Textures.make("coal", size: CGSize(width: 40, height: 40)) { c, size in
        let lump = Draw.polygon([CGPoint(x: 6, y: 14), CGPoint(x: 14, y: 4), CGPoint(x: 30, y: 6), CGPoint(x: 36, y: 20), CGPoint(x: 28, y: 36), CGPoint(x: 10, y: 32)])
        Draw.sphere(c, lump, [UIColor(white: 0.3, alpha: 1), .black], light: CGPoint(x: 14, y: 26), radius: 30)
    } }

    /// A twig arm with branches, root at the left.
    static var twig: SKTexture { Textures.make("twig", size: CGSize(width: 280, height: 160)) { c, size in
        func branch(_ from: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, depth: Int) {
            let to = CGPoint(x: from.x + cos(angle) * length, y: from.y + sin(angle) * length)
            Draw.stroke(c, Draw.capsule(from: from, to: to, radius: 0.001), UIColor(red: 0.28, green: 0.17, blue: 0.08, alpha: 1), width: width)
            Draw.stroke(c, Draw.capsule(from: from, to: to, radius: 0.001), UIColor(red: 0.45, green: 0.3, blue: 0.15, alpha: 0.6), width: width * 0.4)
            guard depth > 0 else { return }
            branch(to, angle: angle + 0.55, length: length * 0.6, width: width * 0.6, depth: depth - 1)
            branch(to, angle: angle - 0.4, length: length * 0.7, width: width * 0.65, depth: depth - 1)
        }
        branch(CGPoint(x: 10, y: 60), angle: 0.25, length: 120, width: 12, depth: 3)
    } }

    static var scarf: SKTexture { Textures.make("scarf", size: CGSize(width: 220, height: 140)) { c, size in
        let wrap = Draw.smooth([CGPoint(x: 20, y: 110), CGPoint(x: 200, y: 110), CGPoint(x: 205, y: 80), CGPoint(x: 15, y: 80)], tension: 0.2)
        Draw.shadowed(c, blur: 8, offset: CGSize(width: 0, height: -5)) {
            Draw.shade(c, wrap, [Metal.bloodBright, Metal.blood, Metal.bloodDark], from: CGPoint(x: 0, y: 110), to: CGPoint(x: 0, y: 80))
        }
        let tail = Draw.smooth([CGPoint(x: 120, y: 95), CGPoint(x: 165, y: 90), CGPoint(x: 190, y: 20), CGPoint(x: 150, y: 10)], tension: 0.3)
        Draw.shade(c, tail, [Metal.blood, Metal.bloodDark], from: CGPoint(x: 0, y: 95), to: CGPoint(x: 0, y: 10))
        for i in 0..<4 {
            Draw.fill(c, CGRect(x: 150 + CGFloat(i) * 10, y: 8, width: 4, height: 16), Metal.bloodDark)
        }
    } }

    /// Shards of ice and snow, for the shattering.
    static var shards: [SKTexture] { (0..<3).map { (i: Int) -> SKTexture in
        Textures.make("shard-\(i)", size: CGSize(width: 80, height: 80)) { c, size in
            let points = (0..<5).map { k -> CGPoint in
                let a = CGFloat(k) / 5 * .pi * 2 + CGFloat(i)
                let r = 22 + CGFloat(Anim.hash(k + i * 5, 105)) * 16
                return CGPoint(x: 40 + cos(a) * r, y: 40 + sin(a) * r)
            }
            Draw.shade(c, Draw.polygon(points), [.white, UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1), UIColor(red: 0.45, green: 0.55, blue: 0.75, alpha: 1)], from: CGPoint(x: 10, y: 70), to: CGPoint(x: 70, y: 10))
        }
    } }

    // MARK: Sky and ground

    /// A blood moon with its craters.
    static var moon: SKTexture { Textures.make("moon", size: CGSize(width: 400, height: 400)) { c, size in
        let center = CGPoint(x: 200, y: 200)
        let disc = Draw.circle(at: center, r: 150)
        Draw.sphere(c, disc, [UIColor(red: 1, green: 0.45, blue: 0.25, alpha: 1), UIColor(red: 0.85, green: 0.15, blue: 0.1, alpha: 1), UIColor(red: 0.45, green: 0.03, blue: 0.05, alpha: 1)], light: CGPoint(x: 150, y: 250), radius: 220)
        c.saveGState()
        c.addPath(disc)
        c.clip()
        for i in 0..<9 {
            let p = CGPoint(x: 70 + CGFloat(Anim.hash(i, 110)) * 260, y: 70 + CGFloat(Anim.hash(i, 111)) * 260)
            let r = 8 + CGFloat(Anim.hash(i, 112)) * 26
            Draw.sphere(c, Draw.circle(at: p, r: r), [UIColor(red: 0.35, green: 0.02, blue: 0.04, alpha: 0.9), UIColor(red: 0.6, green: 0.08, blue: 0.08, alpha: 0.2)], light: CGPoint(x: p.x + r * 0.3, y: p.y - r * 0.3), radius: r)
        }
        c.restoreGState()
    } }

    /// A dead tree silhouette, roots at the bottom middle.
    static var deadTree: SKTexture { Textures.make("dead-tree", size: CGSize(width: 400, height: 600)) { c, size in
        func branch(_ from: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, depth: Int, seed: Int) {
            let to = CGPoint(x: from.x + cos(angle) * length, y: from.y + sin(angle) * length)
            let path = CGMutablePath()
            path.move(to: from)
            path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2 + CGFloat(Anim.signed(seed, 120)) * length * 0.2, y: (from.y + to.y) / 2))
            Draw.stroke(c, path, Metal.black, width: width)
            guard depth > 0 else { return }
            let spread = 0.35 + CGFloat(Anim.hash(seed, 121)) * 0.4
            branch(to, angle: angle + spread, length: length * (0.6 + CGFloat(Anim.hash(seed, 122)) * 0.15), width: width * 0.6, depth: depth - 1, seed: seed * 2 + 1)
            branch(to, angle: angle - spread * 0.8, length: length * (0.65 + CGFloat(Anim.hash(seed, 123)) * 0.15), width: width * 0.65, depth: depth - 1, seed: seed * 2 + 2)
        }
        branch(CGPoint(x: 200, y: 0), angle: .pi / 2 + 0.05, length: 180, width: 34, depth: 5, seed: 1)
    } }

    /// Jagged lightning, top to bottom, with its glow.
    static var bolt: SKTexture { Textures.make("bolt", size: CGSize(width: 300, height: 900)) { c, size in
        func zigzag(from: CGPoint, to: CGPoint, segments: Int, jitter: CGFloat, seed: Int) -> CGMutablePath {
            let path = CGMutablePath()
            path.move(to: from)
            for i in 1...segments {
                let f = CGFloat(i) / CGFloat(segments)
                let p = CGPoint(x: from.x + (to.x - from.x) * f + CGFloat(Anim.signed(i, seed)) * jitter, y: from.y + (to.y - from.y) * f)
                path.addLine(to: i == segments ? to : p)
            }
            return path
        }
        let main = zigzag(from: CGPoint(x: 150, y: 900), to: CGPoint(x: 140, y: 0), segments: 14, jitter: 55, seed: 130)
        c.saveGState()
        c.setShadow(offset: .zero, blur: 30, color: UIColor(red: 0.6, green: 0.7, blue: 1, alpha: 1).cgColor)
        Draw.stroke(c, main, UIColor(red: 0.75, green: 0.8, blue: 1, alpha: 0.9), width: 14)
        c.restoreGState()
        for i in 0..<4 {
            let y = 700 - CGFloat(i) * 160
            let side = i % 2 == 0 ? CGFloat(1) : -1
            let branch = zigzag(from: CGPoint(x: 150, y: y), to: CGPoint(x: 150 + side * 110, y: y - 200), segments: 5, jitter: 25, seed: 131 + i)
            Draw.stroke(c, branch, UIColor(red: 0.8, green: 0.85, blue: 1, alpha: 0.8), width: 5)
        }
        Draw.stroke(c, main, .white, width: 5)
    } }

    /// A storm cloud: dark, heavy, lit from below by embers.
    static var cloud: SKTexture { Textures.make("cloud", size: CGSize(width: 520, height: 260)) { c, size in
        let blobs: [(CGFloat, CGFloat, CGFloat)] = [(120, 110, 90), (230, 150, 110), (350, 120, 95), (430, 100, 70), (60, 90, 60), (290, 90, 80)]
        for (x, y, r) in blobs {
            Draw.sphere(c, Draw.circle(at: CGPoint(x: x, y: y), r: r), [UIColor(white: 0.26, alpha: 1), UIColor(white: 0.12, alpha: 1), UIColor(white: 0.04, alpha: 1)], light: CGPoint(x: x - r * 0.3, y: y + r * 0.5), radius: r * 1.3)
        }
        for (x, y, r) in blobs {
            Draw.sphere(c, Draw.circle(at: CGPoint(x: x, y: y - r * 0.6), r: r * 0.8), [Metal.blood.withAlphaComponent(0.35), Metal.blood.withAlphaComponent(0)], light: CGPoint(x: x, y: y - r * 0.9), radius: r)
        }
    } }

    /// Grass along the horizon, as a strip of tufts.
    static var grass: SKTexture { Textures.make("grass", size: CGSize(width: 512, height: 60)) { c, size in
        for i in 0..<120 {
            let x = CGFloat(i) * 4.3
            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: x, y: 0))
            blade.addQuadCurve(to: CGPoint(x: x + CGFloat(Anim.signed(i, 140)) * 12, y: 14 + CGFloat(Anim.hash(i, 141)) * 40), control: CGPoint(x: x + 4, y: 20))
            Draw.stroke(c, blade, UIColor(red: 0.12, green: 0.32, blue: 0.1, alpha: 1), width: 3, cap: .round)
        }
    } }

    /// A gravestone, for the pile of the dead.
    static var gravestone: SKTexture { Textures.make("gravestone", size: CGSize(width: 200, height: 260)) { c, size in
        let stone = Draw.smooth([CGPoint(x: 30, y: 10), CGPoint(x: 170, y: 10), CGPoint(x: 175, y: 170), CGPoint(x: 150, y: 235), CGPoint(x: 100, y: 252), CGPoint(x: 50, y: 235), CGPoint(x: 25, y: 170)], tension: 0.3)
        Draw.shadowed(c, blur: 12, offset: CGSize(width: 0, height: -6)) {
            Draw.shade(c, stone, [UIColor(white: 0.4, alpha: 1), UIColor(white: 0.22, alpha: 1), UIColor(white: 0.08, alpha: 1)], from: CGPoint(x: 40, y: 250), to: CGPoint(x: 170, y: 10))
        }
        Draw.cracks(c, around: CGPoint(x: 120, y: 120), count: 4, length: 80, color: UIColor(white: 0.05, alpha: 0.8), seed: 150)
        Draw.fill(c, CGPath(roundedRect: CGRect(x: 85, y: 110, width: 30, height: 90), cornerWidth: 4, cornerHeight: 4, transform: nil), UIColor(white: 0.1, alpha: 1))
        Draw.fill(c, CGPath(roundedRect: CGRect(x: 60, y: 160, width: 80, height: 22), cornerWidth: 4, cornerHeight: 4, transform: nil), UIColor(white: 0.1, alpha: 1))
    } }
}
