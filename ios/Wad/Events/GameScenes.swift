import SwiftUI

// The shows of the games: Wolf, Greenies, Wad and Skins. Times in the comments
// are seconds into the show.

/// A wolf's head fills the screen, bares its teeth and howls at the moon.
struct WolfScene: EventScene {
    let stillProgress = 0.6

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.wolfHoleWon.duration
        c.fillBackground(size, top: Color(red: 0.02, green: 0.03, blue: 0.12), bottom: Color(red: 0.08, green: 0.1, blue: 0.25))
        for i in 0..<70 {
            let twinkle = 0.4 + 0.6 * abs(sin(seconds * 3 + Anim.hash(i, 3) * 6))
            c.fill(circleAt: CGPoint(x: Anim.hash(i) * w, y: Anim.hash(i, 1) * h * 0.7), radius: 1 + Anim.hash(i, 2) * 1.5, .white.opacity(twinkle))
        }
        let moon = CGPoint(x: w * 0.8, y: h * 0.16)
        c.fill(circleAt: moon, radius: w * 0.17, Color(red: 0.98, green: 0.95, blue: 0.75).opacity(0.25))
        c.fill(circleAt: moon, radius: w * 0.12, Color(red: 0.98, green: 0.95, blue: 0.78))
        for i in 0..<5 {
            c.fill(circleAt: moon + CGPoint(x: Anim.signed(i, 7) * w * 0.07, y: Anim.signed(i, 8) * w * 0.07), radius: w * (0.01 + Anim.hash(i, 9) * 0.015), Color(red: 0.85, green: 0.82, blue: 0.65))
        }
        // The forest.
        for i in 0..<26 {
            let x = CGFloat(i) / 25 * w
            let top = h * (0.72 - Anim.hash(i, 4) * 0.08)
            c.fill(polygon: [CGPoint(x: x - w * 0.04, y: h), CGPoint(x: x, y: top), CGPoint(x: x + w * 0.04, y: h)], Color(red: 0.03, green: 0.05, blue: 0.1))
        }

        // Howl rings from the mouth, from 1.0.
        let mouthWorld = CGPoint(x: w * 0.5, y: h * 0.56)
        for i in 0..<4 {
            let ring = Anim.seg(seconds, 1.0 + Double(i) * 0.4, 2.2 + Double(i) * 0.4)
            guard ring > 0, ring < 1 else { continue }
            var path = Path()
            path.addArc(center: mouthWorld, radius: w * 0.15 + ring * w * 0.6, startAngle: .degrees(-150), endAngle: .degrees(-30), clockwise: false)
            c.stroke(path, with: .color(.white.opacity(0.6 * (1 - ring))), lineWidth: 4)
        }

        // The head pops in, then tilts up to howl.
        let pop = 0.3 + 0.7 * Anim.back(Anim.seg(seconds, 0, 0.45))
        let tilt = -0.2 * Anim.easeInOut(Anim.seg(seconds, 1.0, 1.5)) * (1 - 0.3 * Anim.seg(seconds, 2.4, 3))
        let open = Anim.easeOut(Anim.seg(seconds, 0.4, 0.85))
        let shake = seconds > 1.0 ? sin(seconds * 40) * 2 : 0
        c.placed(at: CGPoint(x: w * 0.5 + shake, y: h * 0.47), rotation: tilt, scale: pop) { c in
            let u = w * 0.36
            let fur = Color(red: 0.36, green: 0.37, blue: 0.4)
            let darkFur = Color(red: 0.2, green: 0.21, blue: 0.25)
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * u, y: y * u) }
            // Ears and head.
            c.fill(polygon: [p(-0.55, -0.9), p(-0.85, -1.7), p(-0.15, -1.0)], darkFur)
            c.fill(polygon: [p(0.55, -0.9), p(0.85, -1.7), p(0.15, -1.0)], darkFur)
            c.fill(polygon: [p(-0.52, -1.0), p(-0.72, -1.5), p(-0.28, -1.05)], Color(red: 0.45, green: 0.3, blue: 0.32))
            c.fill(polygon: [p(0.52, -1.0), p(0.72, -1.5), p(0.28, -1.05)], Color(red: 0.45, green: 0.3, blue: 0.32))
            c.fill(polygon: [
                p(-1.0, -0.35), p(-0.9, -1.0), p(-0.3, -1.1), p(0.3, -1.1), p(0.9, -1.0), p(1.0, -0.35),
                p(0.75, 0.55), p(0.3, 1.05), p(-0.3, 1.05), p(-0.75, 0.55),
            ], fur)
            // Cheek fur tufts.
            for side in [-1.0, 1.0] {
                c.fill(polygon: [p(side * 0.95, -0.2), p(side * 1.35, 0.1), p(side * 0.9, 0.3), p(side * 1.25, 0.55), p(side * 0.7, 0.6)], fur)
            }
            // Muzzle, nose.
            c.fill(ellipseAt: p(0, 0.35), rx: 0.62 * u, ry: 0.55 * u, Color(red: 0.6, green: 0.6, blue: 0.62))
            c.fill(polygon: [p(-0.22, -0.02), p(0.22, -0.02), p(0, 0.22)], .black)
            c.fill(ellipseAt: p(0, -0.06), rx: 0.24 * u, ry: 0.12 * u, .black)
            // Brows and eyes.
            for side in [-1.0, 1.0] {
                c.fill(polygon: [p(side * 0.2, -0.62), p(side * 0.8, -0.85), p(side * 0.85, -0.6), p(side * 0.3, -0.45)], darkFur)
                c.fill(ellipseAt: p(side * 0.46, -0.45), rx: 0.2 * u, ry: 0.11 * u, Color(red: 1, green: 0.85, blue: 0.1))
                c.fill(ellipseAt: p(side * 0.46, -0.45), rx: 0.04 * u, ry: 0.1 * u, .black)
            }
            // The mouth opens: red inside, fangs top and bottom.
            let mouthTop = 0.5, depth = 0.08 + 0.5 * open
            c.fill(polygon: [p(-0.55, mouthTop), p(0.55, mouthTop), p(0.4, mouthTop + depth), p(-0.4, mouthTop + depth)], Color(red: 0.45, green: 0.02, blue: 0.05))
            c.fill(ellipseAt: p(0, mouthTop + depth * 0.75), rx: 0.22 * u, ry: depth * 0.3 * u, Color(red: 0.85, green: 0.3, blue: 0.4))
            for i in 0..<7 {
                let x = -0.48 + Double(i) * 0.16
                let fang = i == 0 || i == 6 ? 0.22 : 0.1
                c.fill(polygon: [p(x - 0.05, mouthTop), p(x + 0.05, mouthTop), p(x, mouthTop + fang * (0.3 + 0.7 * open))], .white)
            }
            for i in 0..<6 {
                let x = -0.38 + Double(i) * 0.152
                let fang = i == 0 || i == 5 ? 0.18 : 0.08
                let bottom = mouthTop + depth
                c.fill(polygon: [p(x - 0.045, bottom), p(x + 0.045, bottom), p(x, bottom - fang * open)], .white)
            }
        }
    }
}

/// A golf ball drops out of the sky and blows the green to pieces.
struct GreenieScene: EventScene {
    let stillProgress = 0.52

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.greenie.duration
        let impact = 1.5
        let boom = Anim.seg(seconds, impact, impact + 1.4)
        let shake = seconds > impact && seconds < impact + 0.7
            ? CGPoint(x: Anim.signed(Int(seconds * 60), 1) * 14, y: Anim.signed(Int(seconds * 60), 2) * 14) * CGFloat(1 - Anim.seg(seconds, impact, impact + 0.7))
            : .zero
        c.translateBy(x: shake.x, y: shake.y)
        c.fillBackground(CGSize(width: w, height: h * 0.6), top: Color(red: 0.45, green: 0.72, blue: 0.95), bottom: Color(red: 0.85, green: 0.92, blue: 0.98))
        c.fill(rect: CGRect(x: -20, y: h * 0.55, width: w + 40, height: h * 0.5), Color(red: 0.22, green: 0.52, blue: 0.2))
        let hole = CGPoint(x: w * 0.5, y: h * 0.72)
        c.fill(ellipseAt: hole, rx: w * 0.42, ry: h * 0.13, Color(red: 0.36, green: 0.7, blue: 0.3))
        if boom > 0 {
            // The crater and the smoke.
            c.fill(ellipseAt: hole, rx: w * (0.12 + 0.22 * Anim.easeOut(boom)), ry: h * (0.03 + 0.06 * Anim.easeOut(boom)), Color(red: 0.3, green: 0.18, blue: 0.08))
            c.fill(ellipseAt: hole, rx: w * (0.08 + 0.12 * Anim.easeOut(boom)), ry: h * (0.02 + 0.03 * Anim.easeOut(boom)), Color(red: 0.15, green: 0.08, blue: 0.03))
            for i in 0..<14 {
                let life = Anim.seg(seconds, impact + 0.1 + Anim.hash(i, 5) * 0.4, impact + 1.6)
                guard life > 0 else { continue }
                let x = hole.x + Anim.signed(i, 6) * w * (0.1 + 0.25 * life)
                let y = hole.y - h * (0.05 + 0.3 * Anim.easeOut(life))
                c.fill(circleAt: CGPoint(x: x, y: y), radius: w * (0.05 + 0.1 * life), Color(white: 0.4 + Anim.hash(i, 7) * 0.3).opacity(0.7 * (1 - life)))
            }
        } else {
            c.fill(ellipseAt: hole, rx: w * 0.025, ry: h * 0.008, .black)
        }

        // The flag stands until the blast, then spins away.
        let flagFly = Anim.seg(seconds, impact, impact + 1.5)
        let flagBase = flagFly == 0 ? hole : hole + CGPoint(x: w * 0.45 * flagFly, y: -h * 0.6 * flagFly + h * 0.7 * flagFly * flagFly)
        c.placed(at: flagBase, rotation: flagFly * 9) { c in
            c.stroke(line: [.zero, CGPoint(x: 0, y: -h * 0.18)], .white, width: 4)
            c.fill(polygon: [CGPoint(x: 0, y: -h * 0.18), CGPoint(x: w * 0.13, y: -h * 0.155), CGPoint(x: 0, y: -h * 0.13)], Color(red: 0.85, green: 0.1, blue: 0.1))
        }

        // The ball falls, growing as it gets near.
        let fall = Anim.seg(seconds, 0, impact)
        if fall < 1 {
            let ball = CGPoint(x: w * 0.5 + w * 0.15 * (1 - fall), y: Anim.lerp(-h * 0.08, hole.y, Anim.easeIn(fall) * 0.6 + fall * 0.4))
            let r = w * (0.03 + 0.05 * fall)
            c.fill(ellipseAt: hole, rx: r * (0.3 + fall), ry: r * 0.3 * (0.3 + fall), .black.opacity(0.35 * fall))
            for i in 1...6 {
                let back = ball + CGPoint(x: w * 0.012 * CGFloat(i), y: -h * 0.035 * CGFloat(i))
                c.fill(circleAt: back, radius: r * (1 - CGFloat(i) * 0.14), .white.opacity(0.35 - Double(i) * 0.05))
            }
            c.placed(at: ball, rotation: seconds * 6) { c in
                c.fill(circleAt: .zero, radius: r, .white)
                c.fill(circleAt: CGPoint(x: r * 0.3, y: r * 0.3), radius: r * 0.9, .white)
                for i in 0..<10 {
                    c.fill(circleAt: CGPoint(x: Anim.signed(i, 11) * r * 0.65, y: Anim.signed(i, 12) * r * 0.65), radius: r * 0.09, Color(white: 0.75))
                }
            }
        }

        if boom > 0 {
            // The blast: three jagged rings, then debris.
            let blast = Anim.seg(seconds, impact, impact + 0.45)
            for (layer, color) in [(1.0, Color(red: 1, green: 0.45, blue: 0.1)), (0.7, Color(red: 1, green: 0.8, blue: 0.2)), (0.4, .white)] {
                let points = (0..<24).map { i -> CGPoint in
                    let angle = Double(i) / 24 * 2 * .pi
                    let radius = w * (0.08 + 0.42 * Anim.easeOut(blast)) * layer * (0.7 + 0.5 * Anim.hash(i, 13 + Int(layer * 10)))
                    return hole.moved(radius, at: angle)
                }
                c.fill(polygon: points, color.opacity(1 - blast))
            }
            for i in 0..<2 {
                let ring = Anim.seg(seconds, impact + Double(i) * 0.15, impact + 0.9 + Double(i) * 0.15)
                guard ring < 1 else { continue }
                c.stroke(Path(ellipseIn: CGRect(x: hole.x - w * 0.6 * ring, y: hole.y - h * 0.18 * ring, width: w * 1.2 * ring, height: h * 0.36 * ring)), with: .color(.white.opacity(0.7 * (1 - ring))), lineWidth: 6 * (1 - ring) + 1)
            }
            for i in 0..<44 {
                let fly = seconds - impact
                let vx = Anim.signed(i, 20) * w * 0.9
                let vy = -(0.5 + Anim.hash(i, 21)) * h * 1.1
                let point = hole + CGPoint(x: vx * fly, y: vy * fly + h * 1.4 * fly * fly)
                guard point.y < h + 40 else { continue }
                let turf = i % 3 == 0 ? Color(red: 0.35, green: 0.2, blue: 0.08) : Color(red: 0.25, green: 0.55, blue: 0.2)
                c.placed(at: point, rotation: fly * (4 + Anim.hash(i, 22) * 6)) { c in
                    let s = w * (0.015 + Anim.hash(i, 23) * 0.035)
                    c.fill(polygon: [CGPoint(x: -s, y: -s * 0.5), CGPoint(x: s, y: -s * 0.7), CGPoint(x: s * 0.6, y: s * 0.6), CGPoint(x: -s * 0.8, y: s * 0.4)], turf)
                }
            }
        }
        c.flash(size, Anim.seg(seconds, impact, impact + 0.05) * (1 - Anim.seg(seconds, impact, impact + 0.35)))
    }
}

/// A skeleton hand makes it rain: bills and coins fly up and flutter down.
struct WadScene: EventScene {
    let stillProgress = 0.55

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.wadTaken.duration
        c.fillBackground(size, top: Color(red: 0.03, green: 0.06, blue: 0.04), bottom: Color(red: 0.08, green: 0.2, blue: 0.1))
        let u = w * 0.3
        let rise = Anim.back(Anim.seg(seconds, 0, 0.55))
        let origin = CGPoint(x: w * 0.5, y: Anim.lerp(h * 1.4, h * 0.72, rise))
        let flick = sin(seconds * 2 * .pi * 2.2)
        let hand = HandModel(u: u) { finger in
            let phase = Double(finger) * 0.5
            return finger == 4 ? -0.1 + 0.15 * sin(seconds * 2 * .pi * 2.2 + 1) : 0.15 + 0.45 * max(0, sin(seconds * 2 * .pi * 2.2 + phase)) * Anim.seg(seconds, 0.4, 0.8)
        }
        c.placed(at: origin, rotation: 0.05 * flick * Anim.seg(seconds, 0.4, 0.8)) { c in
            hand.drawBones(&c)
        }
        // Bills and coins leave the fingertips and fall; the sign is one
        // resolved text drawn many times.
        let sign = c.resolve(Text("$").font(.system(size: u * 0.12, weight: .black, design: .rounded)).foregroundStyle(Color(red: 0.1, green: 0.3, blue: 0.15)))
        for i in 0..<60 {
            let born = 0.45 + Anim.hash(i, 30) * 1.9
            let age = seconds - born
            guard age > 0 else { continue }
            let start = origin + CGPoint(x: Anim.signed(i, 31) * u * 0.5, y: -u * 1.1)
            let vx = Anim.signed(i, 32) * w * 0.7
            let vy = -(0.9 + Anim.hash(i, 33) * 0.8) * h
            let point = start + CGPoint(x: vx * age + sin(age * 7 + Double(i)) * w * 0.03, y: vy * age + h * 0.95 * age * age)
            guard point.y < h + 60, point.y > -80 else { continue }
            if i % 4 == 0 {
                c.fill(circleAt: point, radius: u * 0.07, Color(red: 0.95, green: 0.78, blue: 0.2))
                c.fill(circleAt: point, radius: u * 0.05, Color(red: 0.8, green: 0.6, blue: 0.1))
            } else {
                c.placed(at: point, rotation: age * (2 + Anim.hash(i, 34) * 4) + Double(i), scale: 1 + 0.15 * sin(age * 9)) { c in
                    let bw = u * 0.38, bh = u * 0.18
                    c.fill(rect: CGRect(x: -bw / 2, y: -bh / 2, width: bw, height: bh), radius: 2, Color(red: 0.45, green: 0.72, blue: 0.45))
                    c.fill(rect: CGRect(x: -bw / 2 + 4, y: -bh / 2 + 3, width: bw - 8, height: bh - 6), radius: 1, Color(red: 0.6, green: 0.85, blue: 0.6))
                    c.draw(sign, at: .zero)
                }
            }
        }
    }
}

/// A hand loses its skin, finger by finger, until only bone is left.
struct SkinScene: EventScene {
    let stillProgress = 0.72

    func draw(_ c: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let seconds = t * GameEventKind.skinWon.duration
        c.fillBackground(size, top: Color(red: 0.15, green: 0.01, blue: 0.03), bottom: Color(red: 0.42, green: 0.03, blue: 0.06))
        let u = w * 0.34
        // The tears come one at a time, from the fingertips down to the wrist.
        var peel = 0.0
        for tear in 0..<5 {
            let at = 0.15 + Double(tear) * 0.36
            peel += 0.2 * Anim.easeOut(Anim.seg(seconds, at, at + 0.3))
        }
        let shake = seconds > 2.0 && seconds < 2.3 ? Anim.signed(Int(seconds * 90)) * 8 : 0
        let origin = CGPoint(x: w * 0.5 + shake, y: h * 0.5)
        let hand = HandModel(u: u) { finger in finger == 4 ? 0.1 : 0.12 + 0.1 * sin(seconds * 25 + Double(finger)) * peel }
        let top = -u * 1.8, bottom = u * 1.7
        let line = Anim.lerp(top, bottom, peel)
        c.placed(at: origin) { c in
            hand.drawBones(&c)
            // The skin still on: the flesh below the peel line.
            c.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: -w, y: line, width: w * 2, height: h)))
                layer.fill(hand.fleshPath(), with: .color(HandModel.skin))
                for bone in hand.bones {
                    layer.fill(circleAt: bone.from, radius: bone.radius * 0.5, HandModel.skinShade.opacity(0.4))
                }
            }
            // The peeled skin hangs off the line, curling, until it drops.
            if peel > 0.02 {
                let drop = Anim.seg(seconds, 2.0, 2.5)
                let swing = sin(seconds * 8) * 0.12
                let length = min(peel, 0.6) * u * 2.2
                c.placed(at: CGPoint(x: u * 0.25, y: line + drop * drop * h * 1.5), rotation: swing + drop * 1.2) { c in
                    var flap = Path()
                    flap.move(to: CGPoint(x: -u * 0.55, y: 0))
                    flap.addLine(to: CGPoint(x: u * 0.5, y: 0))
                    flap.addCurve(to: CGPoint(x: u * 0.15, y: length), control1: CGPoint(x: u * 0.7, y: length * 0.5), control2: CGPoint(x: u * 0.6, y: length * 0.9))
                    flap.addCurve(to: CGPoint(x: -u * 0.55, y: 0), control1: CGPoint(x: -u * 0.4, y: length * 0.8), control2: CGPoint(x: -u * 0.8, y: length * 0.3))
                    c.fill(flap, with: .color(Color(red: 0.75, green: 0.12, blue: 0.14)))
                    c.stroke(flap, with: .color(HandModel.skin), lineWidth: 5)
                }
            }
            // Drips from the line.
            for i in 0..<12 {
                let born = 0.3 + Anim.hash(i, 40) * 1.8
                let age = seconds - born
                guard age > 0 else { continue }
                let x = Anim.signed(i, 41) * u * 0.6
                let y = line + age * age * h * 0.6
                c.capsule(from: CGPoint(x: x, y: y - u * 0.08 - age * u * 0.3), to: CGPoint(x: x, y: y), radius: u * 0.03, Color(red: 0.7, green: 0.05, blue: 0.08))
            }
        }
    }
}
