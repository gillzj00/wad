import SwiftUI

// The shows of the scores, bowling-alley style. Times in the comments are
// seconds into the show.

/// A bald eagle soars across the sky.
struct EagleScene: EventScene {
    let stillProgress = 0.5

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.eagle.duration
        c.fillBackground(size, top: Color(red: 0.3, green: 0.6, blue: 0.95), bottom: Color(red: 0.8, green: 0.9, blue: 1))
        c.fill(circleAt: CGPoint(x: w * 0.8, y: h * 0.2), radius: w * 0.2, Color(red: 1, green: 0.95, blue: 0.7).opacity(0.5))
        c.fill(circleAt: CGPoint(x: w * 0.8, y: h * 0.2), radius: w * 0.12, Color(red: 1, green: 0.93, blue: 0.6))
        for i in 0..<5 {
            let x = (Anim.hash(i, 50) * 1.4 - 0.2) * w - seconds * w * 0.05
            let y = h * (0.12 + Anim.hash(i, 51) * 0.6)
            let r = w * (0.06 + Anim.hash(i, 52) * 0.05)
            for (dx, k) in [(-0.9, 0.7), (0.0, 1.0), (0.9, 0.75)] {
                c.fill(circleAt: CGPoint(x: x + r * dx, y: y + r * (1 - k) * 0.5), radius: r * k, .white.opacity(0.9))
            }
        }
        // Across the screen left to right, bobbing, with a slight climb.
        let path = Anim.easeInOut(t)
        let center = CGPoint(x: Anim.lerp(-w * 0.6, w * 1.6, path), y: h * 0.45 - h * 0.08 * path + sin(seconds * 2 * .pi * 1.6) * h * 0.02)
        let flap = sin(seconds * 2 * .pi * 1.6)
        let span = w * 0.42
        let dark = Color(red: 0.25, green: 0.16, blue: 0.08)
        let darker = Color(red: 0.15, green: 0.09, blue: 0.04)
        for i in 1...4 {
            c.capsule(from: center + CGPoint(x: -span * 0.6 - CGFloat(i) * w * 0.1, y: CGFloat(i - 2) * h * 0.03), to: center + CGPoint(x: -span * 0.9 - CGFloat(i) * w * 0.12, y: CGFloat(i - 2) * h * 0.03), radius: 2, .white.opacity(0.5))
        }
        c.placed(at: center, rotation: -0.12) { c in
            func wing(_ c: inout GraphicsContext, up: Bool, color: Color) {
                let dir: CGFloat = up ? -1 : 1
                let angle = CGFloat(flap) * 0.55 * dir
                c.placed(at: CGPoint(x: -span * 0.05, y: 0), rotation: angle) { c in
                    var points: [CGPoint] = [CGPoint(x: span * 0.1, y: 0), CGPoint(x: -span * 0.15, y: dir * span * 0.3), CGPoint(x: -span * 0.35, y: dir * span * 0.7), CGPoint(x: -span * 0.45, y: dir * span)]
                    for finger in 0..<5 {
                        let f = CGFloat(finger)
                        points.append(CGPoint(x: -span * 0.45 + f * span * 0.1, y: dir * span * (1.0 - f * 0.05)))
                        points.append(CGPoint(x: -span * 0.38 + f * span * 0.1, y: dir * span * (0.85 - f * 0.08)))
                    }
                    points.append(CGPoint(x: span * 0.12, y: dir * span * 0.3))
                    c.fill(polygon: points, color)
                }
            }
            wing(&c, up: true, color: darker)
            // Tail, body, head and beak.
            c.fill(polygon: [CGPoint(x: -span * 0.35, y: -span * 0.08), CGPoint(x: -span * 0.75, y: -span * 0.2), CGPoint(x: -span * 0.8, y: span * 0.12), CGPoint(x: -span * 0.35, y: span * 0.1)], .white)
            c.fill(ellipseAt: .zero, rx: span * 0.45, ry: span * 0.15, dark)
            c.fill(circleAt: CGPoint(x: span * 0.48, y: -span * 0.05), radius: span * 0.14, .white)
            c.fill(polygon: [CGPoint(x: span * 0.58, y: -span * 0.1), CGPoint(x: span * 0.78, y: -span * 0.02), CGPoint(x: span * 0.72, y: span * 0.06), CGPoint(x: span * 0.6, y: span * 0.03)], Color(red: 0.95, green: 0.72, blue: 0.1))
            c.fill(circleAt: CGPoint(x: span * 0.52, y: -span * 0.09), radius: span * 0.03, .black)
            c.fill(circleAt: CGPoint(x: span * 0.53, y: -span * 0.1), radius: span * 0.01, .white)
            c.fill(polygon: [CGPoint(x: span * 0.2, y: span * 0.1), CGPoint(x: span * 0.3, y: span * 0.28), CGPoint(x: span * 0.36, y: span * 0.24), CGPoint(x: span * 0.26, y: span * 0.08)], Color(red: 0.95, green: 0.72, blue: 0.1))
            wing(&c, up: false, color: dark)
            // Screech marks while the sound plays.
            let scream = max(Anim.seg(seconds, 0.1, 0.85), Anim.seg(seconds, 1.3, 2.05))
            if scream > 0, scream < 1 {
                for i in 0..<3 {
                    let d = span * (0.85 + CGFloat(i) * 0.15 + CGFloat(scream) * 0.2)
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: span * 0.7, y: 0), radius: d, startAngle: .degrees(-35), endAngle: .degrees(35), clockwise: false)
                    c.stroke(arc, with: .color(.white.opacity(0.8 - Double(i) * 0.2)), lineWidth: 3)
                }
            }
        }
    }
}

/// Fireworks, champagne corks, confetti and a flash per bang: the loudest show.
struct HoleInOneScene: EventScene {
    let stillProgress = 0.4

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.holeInOne.duration
        c.fillBackground(size, top: Color(red: 0.02, green: 0.02, blue: 0.1), bottom: Color(red: 0.12, green: 0.05, blue: 0.25))
        for i in 0..<80 {
            c.fill(circleAt: CGPoint(x: Anim.hash(i, 60) * w, y: Anim.hash(i, 61) * h), radius: 1 + Anim.hash(i, 62), .white.opacity(0.3 + 0.6 * abs(sin(seconds * 2 + Anim.hash(i, 63) * 6))))
        }
        let colors = [Color(red: 1, green: 0.82, blue: 0.2), Color(red: 1, green: 0.3, blue: 0.3), Color(red: 0.4, green: 1, blue: 0.5), Color(red: 1, green: 0.4, blue: 0.9), Color(red: 0.4, green: 0.9, blue: 1), .white]
        var flash = 0.0
        for (n, launch) in [0.2, 1.4, 2.6, 3.7, 1.0, 3.1].enumerated() {
            let x = w * (0.2 + Anim.hash(n, 64) * 0.6)
            let apex = CGPoint(x: x, y: h * (0.15 + Anim.hash(n, 65) * 0.3))
            let rise = Anim.seg(seconds, launch, launch + 0.75)
            if rise > 0, rise < 1 {
                let y = Anim.lerp(h, apex.y, Anim.easeOut(rise))
                c.capsule(from: CGPoint(x: x, y: y), to: CGPoint(x: x + sin(seconds * 30) * 3, y: y + h * 0.08), radius: 2, Color(red: 1, green: 0.8, blue: 0.4))
            }
            let life = Anim.seg(seconds, launch + 0.75, launch + 2.3)
            guard life > 0, life < 1 else { continue }
            flash = max(flash, (1 - Anim.seg(seconds, launch + 0.75, launch + 1.0)) * 0.35)
            let color = colors[n % colors.count]
            let age = (seconds - launch - 0.75)
            for i in 0..<32 {
                let angle = Double(i) / 32 * 2 * .pi + Anim.hash(n, 66)
                let speed = w * (0.25 + 0.2 * Anim.hash(i + n * 40, 67))
                func at(_ a: Double) -> CGPoint {
                    CGPoint(x: apex.x + cos(angle) * speed * a * (1 - a * 0.25), y: apex.y + sin(angle) * speed * a * (1 - a * 0.25) + h * 0.12 * a * a)
                }
                let fade = 1 - life
                c.capsule(from: at(max(0, age - 0.15)), to: at(age), radius: 2.5 * fade + 0.5, color.opacity(0.9 * fade))
                if (i + Int(seconds * 20)) % 3 == 0 {
                    c.fill(circleAt: at(age), radius: 3, .white.opacity(fade))
                }
            }
        }
        // Two bottles, corks and spray.
        for (side, pops) in [(-1.0, [0.9, 4.4]), (1.0, [2.1])] {
            let base = CGPoint(x: w * (0.5 + side * 0.36), y: h * 0.97)
            let tilt = -side * 0.42
            c.placed(at: base, rotation: tilt) { c in
                let bw = w * 0.1, bh = h * 0.26
                c.fill(rect: CGRect(x: -bw / 2, y: -bh, width: bw, height: bh), radius: bw * 0.25, Color(red: 0.08, green: 0.3, blue: 0.12))
                c.fill(rect: CGRect(x: -bw * 0.2, y: -bh - h * 0.1, width: bw * 0.4, height: h * 0.12), radius: bw * 0.1, Color(red: 0.08, green: 0.3, blue: 0.12))
                c.fill(rect: CGRect(x: -bw * 0.24, y: -bh - h * 0.1, width: bw * 0.48, height: h * 0.035), radius: 2, Color(red: 0.95, green: 0.75, blue: 0.2))
                c.fill(rect: CGRect(x: -bw * 0.35, y: -bh * 0.7, width: bw * 0.7, height: bh * 0.3), radius: 3, Color(red: 0.95, green: 0.9, blue: 0.8))
                let neck = CGPoint(x: 0, y: -bh - h * 0.1)
                for pop in pops {
                    let age = seconds - pop
                    let cork = age < 0 ? CGPoint(x: 0, y: -bh - h * 0.1 - bw * 0.2) : neck + CGPoint(x: side * -w * 0.1 * age, y: -h * 1.1 * age + h * 1.2 * age * age)
                    if cork.y < h {
                        c.placed(at: cork, rotation: max(0, age) * 12) { c in
                            c.fill(rect: CGRect(x: -bw * 0.14, y: -bw * 0.22, width: bw * 0.28, height: bw * 0.44), radius: bw * 0.08, Color(red: 0.8, green: 0.65, blue: 0.4))
                        }
                    }
                    guard age > 0, age < 1.2 else { continue }
                    for i in 0..<18 {
                        let born = Anim.hash(i, 70) * 0.5
                        let a = age - born
                        guard a > 0 else { continue }
                        let p = neck + CGPoint(x: Anim.signed(i, 71) * w * 0.25 * a, y: -h * (0.6 + Anim.hash(i, 72) * 0.5) * a + h * 1.0 * a * a)
                        c.fill(circleAt: p, radius: 3 + 5 * a, .white.opacity(max(0, 0.9 - a)))
                    }
                }
            }
        }
        // Confetti all along.
        for i in 0..<70 {
            let fall = (seconds * (0.12 + Anim.hash(i, 80) * 0.1) + Anim.hash(i, 81)).truncatingRemainder(dividingBy: 1)
            let p = CGPoint(x: Anim.hash(i, 82) * w + sin(seconds * 3 + Double(i)) * w * 0.03, y: fall * (h + 40) - 20)
            c.placed(at: p, rotation: seconds * 4 + Double(i)) { c in
                c.fill(rect: CGRect(x: -5, y: -3, width: 10, height: 6), colors[i % colors.count])
            }
        }
        c.flash(size, flash)
    }
}

/// Proposed, to confirm with the owner: an albatross dives out of a storm,
/// takes the flag and flies off with it.
struct AlbatrossScene: EventScene {
    let stillProgress = 0.5

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.albatross.duration
        c.fillBackground(size, top: Color(red: 0.1, green: 0.1, blue: 0.14), bottom: Color(red: 0.3, green: 0.32, blue: 0.38))
        for i in 0..<5 {
            let x = Anim.hash(i, 90) * w - seconds * w * 0.08
            c.fill(ellipseAt: CGPoint(x: x, y: h * (0.08 + Anim.hash(i, 91) * 0.2)), rx: w * 0.4, ry: h * 0.06, Color(red: 0.18, green: 0.18, blue: 0.22))
        }
        c.fill(rect: CGRect(x: -20, y: h * 0.78, width: w + 40, height: h * 0.3), Color(red: 0.15, green: 0.35, blue: 0.15))
        let hole = CGPoint(x: w * 0.5, y: h * 0.84)
        c.fill(ellipseAt: hole, rx: w * 0.03, ry: h * 0.01, .black)
        // Lightning: the screen flashes and a bolt comes down.
        for strike in [0.35, 1.6] {
            let age = seconds - strike
            guard age > 0, age < 0.25 else { continue }
            var bolt: [CGPoint] = []
            let x0 = w * (strike < 1 ? 0.25 : 0.7)
            for i in 0...10 {
                bolt.append(CGPoint(x: x0 + Anim.signed(i, Int(strike * 10)) * w * 0.08, y: h * 0.75 * CGFloat(i) / 10))
            }
            c.stroke(line: bolt, Color(red: 0.9, green: 0.95, blue: 1), width: 4 * (1 - age / 0.25) + 1)
            c.flash(size, 0.55 * (1 - age / 0.25))
        }
        for i in 0..<120 {
            let fall = (seconds * (0.9 + Anim.hash(i, 92) * 0.5) + Anim.hash(i, 93)).truncatingRemainder(dividingBy: 1)
            let x = Anim.hash(i, 94) * w * 1.2 - fall * w * 0.15
            let y = fall * h * 1.1 - h * 0.05
            c.capsule(from: CGPoint(x: x, y: y), to: CGPoint(x: x - w * 0.012, y: y + h * 0.03), radius: 1, .white.opacity(0.35))
        }
        // The dive to the flag (0.1 to 2.0), then away with it.
        let dive = Anim.easeIn(Anim.seg(seconds, 0.1, 2.0))
        let away = Anim.easeIn(Anim.seg(seconds, 2.0, 4.0))
        let grab = hole + CGPoint(x: 0, y: -h * 0.12)
        let bird = seconds < 2.0
            ? CGPoint(x: Anim.lerp(w * 1.4, grab.x, dive), y: Anim.lerp(-h * 0.3, grab.y, dive))
            : CGPoint(x: Anim.lerp(grab.x, -w * 0.9, away), y: Anim.lerp(grab.y, -h * 0.4, away))
        let heading: CGFloat = seconds < 2.0 ? 0.55 : -0.3
        let flagBase = seconds < 2.0 ? hole : bird + CGPoint(x: w * 0.02, y: h * 0.05)
        c.placed(at: flagBase, rotation: seconds < 2.0 ? 0 : 0.6 + sin(seconds * 6) * 0.1) { c in
            c.stroke(line: [.zero, CGPoint(x: 0, y: -h * 0.14)], .white, width: 4)
            c.fill(polygon: [CGPoint(x: 0, y: -h * 0.14), CGPoint(x: w * 0.12, y: -h * 0.12), CGPoint(x: 0, y: -h * 0.1)], Color(red: 0.85, green: 0.1, blue: 0.1))
        }
        if seconds > 2.0 {
            for i in 0..<10 {
                let a = seconds - 2.0
                let p = hole + CGPoint(x: Anim.signed(i, 95) * w * 0.3 * a, y: -h * 0.4 * a + h * 0.8 * a * a)
                c.fill(circleAt: p, radius: 4, Color(red: 0.3, green: 0.2, blue: 0.1))
            }
        }
        let span = w * 0.75
        let flap = sin(seconds * 2 * .pi * 1.3) * (seconds < 1.6 ? 0.25 : 0.6)
        c.placed(at: bird, rotation: heading) { c in
            for side in [-1.0, 1.0] {
                c.placed(at: .zero, rotation: CGFloat(side * flap)) { c in
                    let s = CGFloat(side)
                    c.fill(polygon: [CGPoint(x: 0, y: -span * 0.05), CGPoint(x: s * span * 0.5, y: -span * 0.22), CGPoint(x: s * span, y: -span * 0.3), CGPoint(x: s * span * 1.02, y: -span * 0.24), CGPoint(x: s * span * 0.55, y: -span * 0.06), CGPoint(x: 0, y: span * 0.05)], .white)
                    c.fill(polygon: [CGPoint(x: s * span * 0.75, y: -span * 0.27), CGPoint(x: s * span, y: -span * 0.3), CGPoint(x: s * span * 1.02, y: -span * 0.24), CGPoint(x: s * span * 0.75, y: -span * 0.14)], .black)
                }
            }
            c.fill(ellipseAt: .zero, rx: span * 0.2, ry: span * 0.07, .white)
            c.fill(polygon: [CGPoint(x: -span * 0.15, y: 0), CGPoint(x: -span * 0.32, y: -span * 0.04), CGPoint(x: -span * 0.32, y: span * 0.05)], .white)
            c.fill(circleAt: CGPoint(x: span * 0.2, y: -span * 0.02), radius: span * 0.07, .white)
            c.fill(polygon: [CGPoint(x: span * 0.25, y: -span * 0.04), CGPoint(x: span * 0.42, y: -span * 0.01), CGPoint(x: span * 0.4, y: span * 0.04), CGPoint(x: span * 0.26, y: span * 0.02)], Color(red: 0.95, green: 0.75, blue: 0.3))
            c.fill(circleAt: CGPoint(x: span * 0.22, y: -span * 0.04), radius: span * 0.014, .black)
        }
    }
}

/// A snowman wobbles, cracks and falls to pieces.
struct SnowmanScene: EventScene {
    let stillProgress = 0.62

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.snowman.duration
        c.fillBackground(size, top: Color(red: 0.55, green: 0.65, blue: 0.8), bottom: Color(red: 0.85, green: 0.9, blue: 0.96))
        let ground = h * 0.74
        c.fill(rect: CGRect(x: -20, y: ground, width: w + 40, height: h), Color(red: 0.95, green: 0.97, blue: 1))
        for i in 0..<60 {
            let fall = (seconds * (0.06 + Anim.hash(i, 100) * 0.05) + Anim.hash(i, 101)).truncatingRemainder(dividingBy: 1)
            c.fill(circleAt: CGPoint(x: Anim.hash(i, 102) * w + sin(seconds + Double(i)) * 10, y: fall * h), radius: 2 + Anim.hash(i, 103) * 3, .white.opacity(0.8))
        }
        let rb = w * 0.19, rm = w * 0.145, rh = w * 0.11
        let x = w * 0.5
        let wobble = sin(seconds * 2 * .pi * 3.5) * 0.06 * Anim.seg(seconds, 0, 0.7) * (1 - Anim.seg(seconds, 1.0, 1.2))
        let fall = seconds - 1.1
        let snow = Color(red: 0.98, green: 0.98, blue: 1)
        let shade = Color(red: 0.8, green: 0.85, blue: 0.92)
        // Bottom ball slumps, middle slides off and breaks, head tumbles away.
        let squash = 1 - 0.25 * Anim.easeOut(Anim.seg(seconds, 1.6, 2.2))
        c.placed(at: CGPoint(x: x, y: ground)) { c in
            c.fill(ellipseAt: CGPoint(x: 0, y: -rb * squash), rx: rb / squash * 0.95, ry: rb * squash, snow)
            c.fill(ellipseAt: CGPoint(x: -rb * 0.2, y: -rb * squash * 0.8), rx: rb * 0.5, ry: rb * squash * 0.5, shade.opacity(0.5))
            if seconds > 0.7 {
                let crack = Anim.seg(seconds, 0.7, 1.1)
                c.stroke(line: [CGPoint(x: -rb * 0.3, y: -rb * 1.9 * squash), CGPoint(x: -rb * 0.1, y: -rb * (1.9 - 0.4 * crack)), CGPoint(x: rb * 0.2, y: -rb * (1.9 - 0.7 * crack)), CGPoint(x: rb * 0.1, y: -rb * (1.9 - 1.0 * crack))], Color(red: 0.6, green: 0.65, blue: 0.75), width: 3)
            }
        }
        let middleFall = Anim.seg(seconds, 1.6, 2.6)
        let middleCenter = CGPoint(x: x - w * 0.22 * middleFall, y: ground - rb * 2 - rm + h * 0.1 * middleFall * middleFall + rm * 0.3 * Anim.seg(seconds, 1.6, 1.9))
        if seconds < 1.9 {
            c.placed(at: middleCenter, rotation: wobble + middleFall * 0.6) { c in
                c.fill(circleAt: .zero, radius: rm, snow)
                c.fill(circleAt: CGPoint(x: -rm * 0.25, y: rm * 0.2), radius: rm * 0.45, shade.opacity(0.5))
                for i in 0..<3 {
                    c.fill(circleAt: CGPoint(x: 0, y: CGFloat(i - 1) * rm * 0.45), radius: rm * 0.08, .black)
                }
                let droop = CGFloat(Anim.seg(seconds, 0.9, 1.8))
                c.stroke(line: [CGPoint(x: -rm * 0.8, y: 0), CGPoint(x: -rm * 1.9, y: -rm * 0.9 + rm * 1.6 * droop)], Color(red: 0.4, green: 0.25, blue: 0.1), width: 5)
                c.stroke(line: [CGPoint(x: rm * 0.8, y: 0), CGPoint(x: rm * 1.9, y: -rm * 0.9 + rm * 1.6 * droop)], Color(red: 0.4, green: 0.25, blue: 0.1), width: 5)
                if seconds > 0.9 {
                    c.stroke(line: [CGPoint(x: -rm * 0.6, y: -rm * 0.5), CGPoint(x: 0, y: 0), CGPoint(x: rm * 0.3, y: rm * 0.6)], Color(red: 0.6, green: 0.65, blue: 0.75), width: 3)
                }
            }
        } else {
            // In four pieces.
            let a = seconds - 1.9
            for i in 0..<4 {
                let p = middleCenter + CGPoint(x: Anim.signed(i, 110) * w * 0.4 * a, y: -h * 0.2 * Anim.hash(i, 111) * a + h * 0.9 * a * a)
                guard p.y < h + 50 else { continue }
                c.placed(at: p, rotation: a * (3 + Double(i))) { c in
                    var wedge = Path()
                    wedge.move(to: .zero)
                    wedge.addArc(center: .zero, radius: rm * 0.8, startAngle: .degrees(Double(i) * 90), endAngle: .degrees(Double(i) * 90 + 90), clockwise: false)
                    wedge.closeSubpath()
                    c.fill(wedge, with: .color(snow))
                }
            }
            for i in 0..<16 {
                let p = middleCenter + CGPoint(x: Anim.signed(i, 112) * w * 0.5 * a, y: -h * 0.3 * Anim.hash(i, 113) * a + h * 1.0 * a * a)
                c.fill(circleAt: p, radius: 3 + Anim.hash(i, 114) * 4, .white)
            }
        }
        // The head: tumbles off to the right and rolls.
        let headRest = ground - rb * 2 - rm * 2 - rh
        var head = CGPoint(x: x, y: headRest)
        var roll = wobble
        if fall > 0 {
            let vy = -h * 0.15
            let y = headRest + vy * fall + h * 1.2 * fall * fall
            let landed = y > ground - rh
            head = CGPoint(x: x + w * 0.45 * fall, y: landed ? ground - rh + rh * 0.1 : y)
            roll = fall * 5
        }
        c.placed(at: head, rotation: roll) { c in
            c.fill(circleAt: .zero, radius: rh, snow)
            c.fill(circleAt: CGPoint(x: -rh * 0.25, y: rh * 0.25), radius: rh * 0.35, shade.opacity(0.5))
            c.fill(circleAt: CGPoint(x: -rh * 0.3, y: -rh * 0.2), radius: rh * 0.08, .black)
            c.fill(circleAt: CGPoint(x: rh * 0.3, y: -rh * 0.2), radius: rh * 0.08, .black)
            c.fill(polygon: [CGPoint(x: 0, y: rh * 0.05), CGPoint(x: rh * 0.9, y: rh * 0.2), CGPoint(x: 0, y: rh * 0.25)], Color(red: 0.95, green: 0.5, blue: 0.1))
            for i in 0..<5 {
                c.fill(circleAt: CGPoint(x: CGFloat(i - 2) * rh * 0.22, y: rh * 0.55 - abs(CGFloat(i - 2)) * rh * 0.08), radius: rh * 0.05, .black)
            }
            if fall <= 0 {
                c.fill(rect: CGRect(x: -rh * 1.1, y: -rh * 0.95, width: rh * 2.2, height: rh * 0.2), .black)
                c.fill(rect: CGRect(x: -rh * 0.7, y: -rh * 1.75, width: rh * 1.4, height: rh * 0.85), .black)
            }
        }
        if fall > 0 {
            // The hat flies off on its own.
            let hat = CGPoint(x: x - w * 0.3 * fall, y: headRest - rh - h * 0.5 * fall + h * 1.0 * fall * fall)
            c.placed(at: hat, rotation: -fall * 4) { c in
                c.fill(rect: CGRect(x: -rh * 1.1, y: -rh * 0.1, width: rh * 2.2, height: rh * 0.2), .black)
                c.fill(rect: CGRect(x: -rh * 0.7, y: -rh * 0.9, width: rh * 1.4, height: rh * 0.85), .black)
            }
        }
    }
}

/// The bird: a fist raises its middle finger, and a small bird lands on it.
struct BirdieScene: EventScene {
    let stillProgress = 0.8

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.birdie.duration
        c.fill(rect: CGRect(origin: .zero, size: size), Color(red: 0.98, green: 0.75, blue: 0.15))
        let center = CGPoint(x: w * 0.5, y: h * 0.58)
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi + seconds * 0.4
            c.fill(polygon: [center, center.moved(w * 2, at: a), center.moved(w * 2, at: a + .pi / 12)], Color(red: 1, green: 0.55, blue: 0.1))
        }
        let u = w * 0.36
        let raise = Anim.back(Anim.seg(seconds, 0.2, 0.75))
        let wiggle = sin(seconds * 2 * .pi * 3) * 0.05 * Anim.seg(seconds, 0.75, 1.0)
        let hand = HandModel(u: u) { finger in
            finger == 4 ? 0.35 : finger == 1 ? 1.25 * (1 - raise) : 1.25
        }
        c.placed(at: center, rotation: wiggle) { c in
            c.fill(hand.fleshPath(), with: .color(HandModel.skin))
            c.stroke(hand.fleshPath(), with: .color(HandModel.skinShade), lineWidth: 3)
            for (i, bone) in hand.bones.enumerated() where i % 3 != 0 {
                c.fill(circleAt: bone.from, radius: bone.radius * 0.45, HandModel.skinShade.opacity(0.5))
            }
            // The nail, on the last bone of the middle finger.
            let last = hand.bones[5]
            c.fill(ellipseAt: last.to + CGPoint(x: 0, y: -last.radius * 0.2), rx: last.radius * 0.9, ry: last.radius * 1.2, Color(red: 0.98, green: 0.85, blue: 0.78))
        }
        // A bird lands on the fingertip once it is up.
        let land = Anim.easeOut(Anim.seg(seconds, 0.9, 1.5))
        if land > 0 {
            let tip = center + hand.bones[5].to + CGPoint(x: 0, y: -u * 0.12)
            let bird = CGPoint(x: Anim.lerp(-w * 0.2, tip.x, land), y: Anim.lerp(tip.y - h * 0.3, tip.y, land) - sin(land * .pi) * h * 0.1)
            let hop = land == 1 ? abs(sin(seconds * 2 * .pi * 2.5)) * u * 0.04 : 0
            c.placed(at: CGPoint(x: bird.x, y: bird.y - hop)) { c in
                let blue = Color(red: 0.2, green: 0.45, blue: 0.9)
                let flapWing = land < 1 ? sin(seconds * 2 * .pi * 8) * u * 0.1 : 0
                c.fill(ellipseAt: CGPoint(x: -u * 0.03, y: -u * 0.08 + flapWing), rx: u * 0.09, ry: u * 0.05, blue)
                c.fill(ellipseAt: CGPoint(x: 0, y: -u * 0.05), rx: u * 0.11, ry: u * 0.085, blue)
                c.fill(ellipseAt: CGPoint(x: 0, y: -u * 0.02), rx: u * 0.07, ry: u * 0.05, Color(red: 1, green: 0.85, blue: 0.4))
                c.fill(circleAt: CGPoint(x: u * 0.09, y: -u * 0.14), radius: u * 0.065, blue)
                c.fill(polygon: [CGPoint(x: u * 0.14, y: -u * 0.15), CGPoint(x: u * 0.24, y: -u * 0.12), CGPoint(x: u * 0.14, y: -u * 0.1)], Color(red: 1, green: 0.6, blue: 0.1))
                c.fill(circleAt: CGPoint(x: u * 0.11, y: -u * 0.16), radius: u * 0.015, .black)
                c.fill(polygon: [CGPoint(x: -u * 0.08, y: -u * 0.06), CGPoint(x: -u * 0.22, y: -u * 0.12), CGPoint(x: -u * 0.2, y: -u * 0.02)], blue)
                c.stroke(line: [CGPoint(x: -u * 0.02, y: u * 0.03), CGPoint(x: -u * 0.02, y: u * 0.08)], Color(red: 1, green: 0.6, blue: 0.1), width: 2)
                c.stroke(line: [CGPoint(x: u * 0.03, y: u * 0.03), CGPoint(x: u * 0.03, y: u * 0.08)], Color(red: 1, green: 0.6, blue: 0.1), width: 2)
            }
        }
    }
}
