import SpriteKit

// The shows of the scores, bowling-alley style. Times in the comments are
// seconds into the show.

/// A bald eagle swoops in under a blood moon, screams and climbs away.
final class EagleScene: EventSKScene {
    override func build(still: Bool) {
        addBackground(top: Metal.black, bottom: UIColor(red: 0.45, green: 0.07, blue: 0.03, alpha: 1))
        addStars(count: 50, below: 0.9)
        let moonCenter = at(0.72, 0.68)
        addGlow(at: moonCenter, radius: w * 0.6, color: Metal.blood, alpha: 0.8, z: -85)
        sprite(Art.moon, size: CGSize(width: w * 0.6, height: w * 0.6), at: moonCenter, z: -75)
        for (i, x) in [CGFloat(0.15), 0.85, 0.5].enumerated() {
            let cloud = sprite(Art.cloud, size: CGSize(width: w * 0.8, height: w * 0.4), at: at(x, 0.5 + CGFloat(i) * 0.12), z: -60 + CGFloat(i))
            cloud.alpha = 0.85
            if !still {
                cloud.run(.repeatForever(.moveBy(x: -w * (0.08 + CGFloat(i) * 0.05), y: 0, duration: 3)))
            }
        }
        addTrees([(0.1, 0.5), (0.92, 0.6), (0.4, 0.35)], baseline: 0.0)
        addMist(y: 0.06, color: Metal.bloodDark)
        // Wind.
        let wind = Emitters.fall(width: h, height: w, rate: 40, speed: 900, texture: Textures.streak, scale: 1.2, color: Metal.bone, alpha: 0.25, angle: .pi)
        wind.position = at(1.1, 0.55)
        wind.particlePositionRange = CGVector(dx: 0, dy: h * 0.8)
        wind.zPosition = -20
        addChild(wind)
        if still { wind.advanceSimulationTime(2) }

        // The eagle: body, a wing in front and a darker one behind, flapping.
        let eagle = SKNode()
        eagle.zPosition = 10
        addChild(eagle)
        let scale = w * 0.95 / Art.eagleBodySize.width
        let body = SKSpriteNode(texture: Art.eagleBody, size: CGSize(width: Art.eagleBodySize.width * scale, height: Art.eagleBodySize.height * scale))
        body.anchorPoint = CGPoint(x: Art.eagleShoulder.x / Art.eagleBodySize.width, y: Art.eagleShoulder.y / Art.eagleBodySize.height)
        body.zPosition = 1
        eagle.addChild(body)
        let wingSize = CGSize(width: Art.eagleWingSize.width * scale, height: Art.eagleWingSize.height * scale)
        let near = SKSpriteNode(texture: Art.eagleWing, size: wingSize)
        near.anchorPoint = Art.eagleWingAnchor
        near.zPosition = 2
        near.zRotation = 0.5
        let far = SKSpriteNode(texture: Art.eagleWing, size: wingSize)
        far.anchorPoint = Art.eagleWingAnchor
        far.zPosition = 0
        far.color = .black
        far.colorBlendFactor = 0.45
        far.zRotation = 0.3
        far.xScale = 0.9
        eagle.addChild(far)
        eagle.addChild(near)
        let feathers = Emitters.fall(width: 10, height: 10, rate: 6, speed: 60, texture: Textures.streak, scale: 0.5, color: UIColor(red: 0.3, green: 0.18, blue: 0.08, alpha: 1), alpha: 0.9)
        feathers.particleLifetime = 2.5
        feathers.particleRotationSpeed = 3
        feathers.yAcceleration = -120
        feathers.targetNode = self
        feathers.position = CGPoint(x: -w * 0.1, y: -w * 0.05)
        eagle.addChild(feathers)

        // The hold: the wings beat high, so the whole bird, wingtips and
        // beak, stays inside a phone's width while it fills it.
        let hold = at(0.5, 0.47)
        let holdScale: CGFloat = 0.9
        if still {
            eagle.position = hold
            eagle.setScale(holdScale)
            eagle.zRotation = -0.05
            near.zRotation = 0.7
            far.zRotation = 0.55
            screech(from: eagle.position + CGPoint(x: w * 0.4, y: w * 0.1))
            return
        }

        // Swoop in from the left: 0 to 1.2, banking; hover in the middle; climb out.
        eagle.position = at(-0.5, 0.95)
        eagle.setScale(0.45)
        eagle.zRotation = -0.6
        near.run(Self.flap(from: 0.4, to: 2.1, period: 0.55), withKey: "flap")
        far.run(.sequence([.wait(forDuration: 0.04), Self.flap(from: 0.3, to: 1.9, period: 0.55)]), withKey: "flap")
        let swoop = SKAction.group([
            Self.move(to: at(0.5, 0.45), duration: 1.2, timing: .easeOut),
            Self.scale(to: 1.0, duration: 1.2, timing: .easeOut),
            Self.rotate(to: 0.05, duration: 1.2, timing: .easeOut),
        ])
        let hang = SKAction.group([
            Self.move(to: hold, duration: 0.9, timing: .easeInEaseOut),
            Self.scale(to: holdScale, duration: 0.9, timing: .easeInEaseOut),
            Self.rotate(to: -0.05, duration: 0.9, timing: .easeInEaseOut),
        ])
        // The wings come up for the hover as the swoop ends: 1.0 to 1.3.
        after(1.0) {
            near.removeAction(forKey: "flap")
            far.removeAction(forKey: "flap")
            near.run(.sequence([Self.rotate(to: 0.7, duration: 0.3, timing: .easeOut), Self.flap(from: 0.3, to: 0.7, period: 0.5)]))
            far.run(.sequence([Self.rotate(to: 0.55, duration: 0.3, timing: .easeOut), Self.flap(from: 0.2, to: 0.55, period: 0.5)]))
        }
        let climb = SKAction.group([
            Self.move(to: at(1.7, 1.1), duration: 0.9, timing: .easeIn),
            Self.scale(to: 1.4, duration: 0.9, timing: .easeIn),
            Self.rotate(to: 0.5, duration: 0.9, timing: .easeIn),
        ])
        eagle.run(.sequence([swoop, hang, climb]))
        zoom(to: 0.95, duration: 2.1, timing: .easeOut)
        after(2.1) { [self] in zoom(to: 1.05, duration: 0.9, timing: .easeIn) }
        for time in [0.1, 1.3] {
            after(time) { [self] in
                flash(Metal.bloodBright, peak: 0.35, duration: 0.3)
                shake(amplitude: 7, duration: 0.4)
                screech(from: eagle.position + CGPoint(x: w * 0.45 * eagle.xScale, y: w * 0.1 * eagle.xScale))
            }
        }
    }

    private func screech(from point: CGPoint) {
        for i in 0..<3 {
            after(Double(i) * 0.1) { [self] in
                ring(at: point, color: Metal.bone.withAlphaComponent(0.6), from: w * 0.03, to: w * 0.35, duration: 0.6, width: 2, z: 15)
            }
        }
        if still {
            ring(at: point, color: Metal.bone.withAlphaComponent(0.6), from: w * 0.05, to: w * 0.3, duration: 0.6, width: 2, z: 15)
        }
    }
}

/// The finale: the ball drops, the sky explodes and the champagne pops.
final class HoleInOneScene: EventSKScene {
    private let colors = [Metal.emberBright, Metal.bloodBright, Metal.bone, Metal.ember, UIColor(red: 0.6, green: 0.8, blue: 1, alpha: 1), UIColor(red: 1, green: 0.4, blue: 0.9, alpha: 1)]

    override func build(still: Bool) {
        addBackground(top: Metal.black, bottom: UIColor(red: 0.12, green: 0.02, blue: 0.05, alpha: 1))
        addStars(count: 90)
        // The green at the bottom, with the cup and the flag.
        let ground = SKSpriteNode(texture: Textures.linearGradient(top: UIColor(red: 0.1, green: 0.26, blue: 0.08, alpha: 1), bottom: Metal.black), size: CGSize(width: w, height: h * 0.26))
        ground.anchorPoint = CGPoint(x: 0.5, y: 0)
        ground.position = at(0.5, 0)
        ground.zPosition = -50
        addChild(ground)
        for i in 0..<3 {
            let grass = sprite(Art.grass, size: CGSize(width: w * 0.5, height: 30), at: at(0, 0.26), z: -45, anchor: CGPoint(x: 0, y: 0))
            grass.position.x = CGFloat(i) * w * 0.5 - w * 0.25
        }
        let hole = at(0.5, 0.15)
        sprite(Art.cup, size: CGSize(width: w * 0.14, height: w * 0.06), at: hole, z: -43)
        sprite(Art.flag, size: CGSize(width: w * 0.25, height: w * 0.5), at: hole + CGPoint(x: w * 0.03, y: 0), z: 5, anchor: CGPoint(x: 0.136, y: 0))
        addMist(y: 0.05, color: Metal.ash, rate: 4)
        let embers = Emitters.embers(width: w, rate: 20)
        embers.position = at(0.5, 0.2)
        embers.zPosition = 20
        addChild(embers)

        // The bottles, leaning in from the corners.
        let bottleSize = CGSize(width: w * 0.22, height: w * 0.68)
        let left = sprite(Art.bottle, size: bottleSize, at: at(0.1, -0.02), z: 30, anchor: CGPoint(x: 0.5, y: 0))
        left.zRotation = -0.45
        let right = sprite(Art.bottle, size: bottleSize, at: at(0.9, -0.02), z: 30, anchor: CGPoint(x: 0.5, y: 0))
        right.zRotation = 0.45
        let confetti = confettiRain()

        if still {
            for (i, x) in [CGFloat(0.28), 0.72, 0.5].enumerated() {
                let apex = at(x, 0.5 + CGFloat(i) * 0.1)
                frozenBurst(at: apex, color: colors[i], age: 0.5 + CGFloat(i) * 0.2, seed: i)
                addGlow(at: apex, radius: w * 0.3, color: colors[i], alpha: 0.35, z: 35)
            }
            pop(left, cork: true, elapsed: 0.5)
            pop(right, cork: true, elapsed: 0.25)
            confetti.advanceSimulationTime(3)
            embers.advanceSimulationTime(3)
            cameraNode.setScale(0.97)
            return
        }

        // The ball rolls in and drops: 0 to 0.6.
        let ball = sprite(Art.golfBall, size: CGSize(width: w * 0.09, height: w * 0.09), at: at(0.08, 0.17), z: 6)
        let roll = SKAction.move(to: hole + CGPoint(x: 0, y: w * 0.02), duration: 0.6)
        roll.timingMode = .easeOut
        ball.run(.sequence([.group([roll, .rotate(byAngle: -12, duration: 0.6)]), .group([.scale(to: 0.3, duration: 0.12), .fadeOut(withDuration: 0.12)]), .removeFromParent()]))
        after(0.65) { [self] in
            flash(.white, peak: 1, duration: 0.5)
            shake(amplitude: 12, duration: 0.5)
            zoom(to: 0.92, duration: 0.1, timing: .easeOut)
            after(0.1) { [self] in zoom(to: 1.0, duration: 5, timing: .easeOut) }
            burst(Emitters.burst(count: 90, speed: 500, color: Metal.bone, scale: 0.14, lifetime: 1.4), at: hole, z: 40)
            ring(at: hole, color: Metal.bone, from: w * 0.05, to: w * 1.5, duration: 0.8, width: 8, squash: 0.4)
            confetti.particleBirthRate = 70
        }
        // Rockets: each climbs on a trail, bursts, then crackles.
        for (n, launch) in [0.8, 1.5, 2.1, 2.8, 3.3, 3.9, 4.4, 4.9].enumerated() {
            after(launch) { [self] in rocket(n) }
        }
        // Corks: left, right, left.
        after(0.9) { [self] in pop(left, cork: true, elapsed: 0) }
        after(2.1) { [self] in pop(right, cork: true, elapsed: 0) }
        after(4.4) { [self] in pop(left, cork: false, elapsed: 0) }
    }

    /// A burst caught mid-air for the poster frame: sparks and their trails
    /// placed where they would be `age` seconds after going off.
    private func frozenBurst(at apex: CGPoint, color: UIColor, age: CGFloat, seed: Int) {
        for i in 0..<40 {
            let angle = CGFloat(i) / 40 * .pi * 2 + CGFloat(Anim.hash(seed, 310))
            let speed = w * (0.45 + CGFloat(Anim.hash(i + seed * 50, 311)) * 0.3)
            func at(_ t: CGFloat) -> CGPoint {
                CGPoint(x: apex.x + cos(angle) * speed * t * (1 - t * 0.3), y: apex.y + sin(angle) * speed * t * (1 - t * 0.3) - 220 * t * t)
            }
            let head = at(age), tail = at(max(0, age - 0.12))
            let trail = SKShapeNode(path: { let p = CGMutablePath(); p.move(to: tail); p.addLine(to: head); return p }())
            trail.strokeColor = color.withAlphaComponent(0.8)
            trail.lineWidth = 3
            trail.lineCap = .round
            trail.zPosition = 40
            addChild(trail)
            let spark = SKSpriteNode(texture: Textures.dot, size: CGSize(width: 14, height: 14))
            spark.position = head
            spark.color = i % 3 == 0 ? .white : color
            spark.colorBlendFactor = 1
            spark.blendMode = .add
            spark.zPosition = 41
            addChild(spark)
        }
    }

    private func rocket(_ n: Int) {
        let x = w * (0.15 + CGFloat(Anim.hash(n, 300)) * 0.7)
        let apex = CGPoint(x: x, y: h * (0.55 + CGFloat(Anim.hash(n, 301)) * 0.35))
        let color = colors[n % colors.count]
        let rocket = SKSpriteNode(texture: Textures.dot, size: CGSize(width: 14, height: 14))
        rocket.color = Metal.emberBright
        rocket.colorBlendFactor = 1
        rocket.blendMode = .add
        rocket.position = CGPoint(x: x + CGFloat(Anim.signed(n, 302)) * w * 0.15, y: 0)
        rocket.zPosition = 38
        let trail = Emitters.embers(width: 4, rate: 120, color: Metal.emberBright)
        trail.particleLifetime = 0.7
        trail.particleSpeed = 30
        trail.emissionAngle = -.pi / 2
        trail.particleScale = 0.1
        trail.targetNode = self
        rocket.addChild(trail)
        addChild(rocket)
        let climb = SKAction.move(to: apex, duration: 0.75)
        climb.timingMode = .easeOut
        rocket.run(.sequence([climb, .removeFromParent()]))
        after(0.75) { [self] in
            flash(color, peak: 0.3, duration: 0.4)
            shake(amplitude: 9, duration: 0.35)
            let big = Emitters.burst(count: 110, speed: 440, color: color, scale: 0.14, lifetime: 1.9, gravity: -220)
            burst(big, at: apex, z: 40)
            let bright = Emitters.burst(count: 60, speed: 380, color: .white, scale: 0.08, lifetime: 1.2, gravity: -220)
            burst(bright, at: apex, z: 41)
            let glow = addGlow(at: apex, radius: w * 0.35, color: color, alpha: 0.9, z: 35)
            glow.run(.sequence([.group([.scale(to: 2, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
            let smoke = Emitters.smoke(rate: 30, color: UIColor(white: 0.22, alpha: 1), speed: 30, scale: 0.45)
            smoke.numParticlesToEmit = 6
            burst(smoke, at: apex, z: 34)
            after(0.45) { [self] in
                let crackle = Emitters.burst(count: 50, speed: 180, color: Metal.emberBright, scale: 0.07, lifetime: 0.8, gravity: -300)
                crackle.particlePositionRange = CGVector(dx: w * 0.3, dy: w * 0.3)
                burst(crackle, at: apex, z: 42)
            }
        }
    }

    /// The cork flies out along the bottle, with foam. `elapsed` jumps in for a still.
    private func pop(_ bottle: SKSpriteNode, cork hasCork: Bool, elapsed: TimeInterval) {
        let axis = CGVector(dx: -sin(bottle.zRotation), dy: cos(bottle.zRotation))
        let mouth = CGPoint(x: bottle.position.x + axis.dx * bottle.size.height, y: bottle.position.y + axis.dy * bottle.size.height)
        if !still {
            bottle.run(.sequence([.scaleY(to: 0.93, duration: 0.08), .scaleY(to: 1.04, duration: 0.08), .scaleY(to: 1, duration: 0.1)]))
            flash(Metal.bone, peak: 0.25, duration: 0.25)
            shake(amplitude: 6, duration: 0.25)
        }
        let cork = sprite(Art.cork, size: CGSize(width: w * 0.06, height: w * 0.08), at: mouth, z: 32)
        cork.zRotation = bottle.zRotation
        let foam = Emitters.burst(count: 140, speed: 620, color: Metal.bone, scale: 0.16, lifetime: 1.3, gravity: -800)
        foam.emissionAngle = atan2(axis.dy, axis.dx)
        foam.emissionAngleRange = 0.5
        foam.particleScaleSpeed = 0.2
        foam.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [1, 0.8, 0], times: [0, 0.5, 1])
        burst(foam, at: mouth, z: 33)
        let mist = Emitters.smoke(rate: 60, color: Metal.bone, speed: 200, scale: 0.22)
        mist.numParticlesToEmit = 10
        mist.emissionAngle = foam.emissionAngle
        mist.emissionAngleRange = 0.6
        burst(mist, at: mouth, z: 31)
        if still {
            foam.advanceSimulationTime(elapsed)
            mist.advanceSimulationTime(elapsed)
            cork.position = CGPoint(x: mouth.x + axis.dx * w * 0.9 * elapsed, y: mouth.y + axis.dy * w * 0.9 * elapsed - 700 * elapsed * elapsed)
            cork.zRotation += 12 * elapsed
            return
        }
        cork.run(.sequence([Self.toss(velocity: CGVector(dx: axis.dx * w * 1.6, dy: axis.dy * w * 1.6 + h * 0.3), duration: 2.5, spin: 14), .removeFromParent()]))
    }

    private func confettiRain() -> SKEmitterNode {
        let piece = Textures.make("confetti", size: CGSize(width: 14, height: 9), scale: 1) { c, size in
            Art.fill(c, CGRect(origin: .zero, size: size), .white)
        }
        let e = Emitters.fall(width: w, height: h, rate: still ? 70 : 0, speed: 180, texture: piece, scale: 1.1, color: .white, alpha: 1)
        e.particleColorRedRange = 1
        e.particleColorGreenRange = 1
        e.particleColorBlueRange = 1
        e.particleColorBlendFactor = 1
        e.particleRotationRange = .pi * 2
        e.particleRotationSpeed = 4
        e.particleLifetime = 7
        e.particleAction = .repeatForever(.sequence([.scaleX(to: 0.1, duration: 0.3), .scaleX(to: 1, duration: 0.3)]))
        e.position = at(0.5, 1.05)
        e.zPosition = 50
        addChild(e)
        return e
    }
}

/// A huge albatross dives out of a thunderstorm, takes the flag and leaves with it.
final class AlbatrossScene: EventSKScene {
    override func build(still: Bool) {
        addBackground(top: Metal.black, bottom: UIColor(red: 0.16, green: 0.14, blue: 0.2, alpha: 1))
        for (i, x) in [CGFloat(0.1), 0.6, 0.95, 0.35].enumerated() {
            let cloud = sprite(Art.cloud, size: CGSize(width: w * (0.9 + CGFloat(i % 2) * 0.3), height: w * 0.45), at: at(x, 0.92 - CGFloat(i) * 0.08), z: -70 + CGFloat(i))
            if !still {
                cloud.run(.repeatForever(.sequence([.moveBy(x: -40 - CGFloat(i) * 20, y: 0, duration: 3.5), .moveBy(x: 40 + CGFloat(i) * 20, y: 0, duration: 3.5)])))
            }
        }
        // The green, the cup and the flag.
        let ground = SKSpriteNode(texture: Textures.linearGradient(top: UIColor(red: 0.1, green: 0.24, blue: 0.09, alpha: 1), bottom: Metal.black), size: CGSize(width: w, height: h * 0.22))
        ground.anchorPoint = CGPoint(x: 0.5, y: 0)
        ground.position = at(0.5, 0)
        ground.zPosition = -50
        addChild(ground)
        for i in 0..<3 {
            let grass = sprite(Art.grass, size: CGSize(width: w * 0.5, height: 30), at: at(0, 0.22), z: -45, anchor: CGPoint(x: 0, y: 0))
            grass.position.x = CGFloat(i) * w * 0.5 - w * 0.25
        }
        let hole = at(0.5, 0.13)
        sprite(Art.cup, size: CGSize(width: w * 0.14, height: w * 0.06), at: hole, z: -43)
        let flag = SKSpriteNode(texture: Art.flag, size: CGSize(width: w * 0.28, height: w * 0.56))
        flag.anchorPoint = CGPoint(x: 0.136, y: 0)
        flag.position = hole
        flag.zPosition = 5
        addChild(flag)
        // Rain, far and near.
        let farRain = Emitters.fall(width: w, height: h, rate: 160, speed: 900, texture: Textures.streak, scale: 0.5, color: Metal.bone, alpha: 0.3, angle: -.pi / 2 - 0.15)
        farRain.position = at(0.6, 1.05)
        farRain.zPosition = -30
        addChild(farRain)
        let nearRain = Emitters.fall(width: w, height: h, rate: 90, speed: 1500, texture: Textures.streak, scale: 1.1, color: Metal.bone, alpha: 0.45, angle: -.pi / 2 - 0.2)
        nearRain.position = at(0.6, 1.05)
        nearRain.zPosition = 60
        addChild(nearRain)
        farRain.advanceSimulationTime(2)
        nearRain.advanceSimulationTime(2)

        // The bird: body and two wings on a node that faces left.
        let bird = SKNode()
        bird.zPosition = 10
        bird.xScale = -1
        addChild(bird)
        let scale = w * 1.05 / Art.albatrossBodySize.width
        let body = SKSpriteNode(texture: Art.albatrossBody, size: CGSize(width: Art.albatrossBodySize.width * scale, height: Art.albatrossBodySize.height * scale))
        body.anchorPoint = CGPoint(x: Art.albatrossShoulder.x / Art.albatrossBodySize.width, y: Art.albatrossShoulder.y / Art.albatrossBodySize.height)
        body.zPosition = 1
        bird.addChild(body)
        let wingSize = CGSize(width: Art.albatrossWingSize.width * scale, height: Art.albatrossWingSize.height * scale)
        let near = SKSpriteNode(texture: Art.albatrossWing, size: wingSize)
        near.anchorPoint = Art.albatrossWingAnchor
        near.zPosition = 2
        let far = SKSpriteNode(texture: Art.albatrossWing, size: wingSize)
        far.anchorPoint = Art.albatrossWingAnchor
        far.zPosition = 0
        far.color = .black
        far.colorBlendFactor = 0.35
        far.xScale = 0.92
        bird.addChild(far)
        bird.addChild(near)
        let beak = CGPoint(x: -w * 0.62, y: w * 0.08)

        if still {
            bird.position = at(0.62, 0.52)
            bird.setScale(0.85)
            bird.xScale = -0.85
            bird.zRotation = 0.75
            near.zRotation = 1.1
            far.zRotation = 0.9
            strike(x: 0.25, strength: 0.5)
            cameraNode.setScale(0.96)
            return
        }

        // Lightning at 0.35 and the thunderclap at 1.6, one more as it leaves.
        after(0.35) { [self] in strike(x: 0.25, strength: 0.5) }
        after(1.6) { [self] in
            strike(x: 0.72, strength: 0.95)
            shake(amplitude: 18, duration: 0.6)
        }
        after(3.0) { [self] in strike(x: 0.5, strength: 0.4) }

        // The dive: 0.1 to 2.0, wings swept, growing as it comes.
        bird.position = at(1.4, 1.2)
        bird.setScale(0.35)
        bird.xScale = -0.35
        bird.zRotation = 0.9
        near.zRotation = 1.3
        far.zRotation = 1.2
        let grab = hole + CGPoint(x: 0, y: w * 0.2)
        let dive = SKAction.customAction(withDuration: 1.9) { [self] node, elapsed in
            let f = CGFloat(Anim.easeIn(Double(elapsed / 1.9)))
            node.position = CGPoint(x: Anim.lerp(1.4, 0.5, f) * w, y: Anim.lerp(1.2, grab.y / h, f) * h)
            let s = 0.35 + 0.65 * f
            node.xScale = -s
            node.yScale = s
            node.zRotation = 0.9 - 0.3 * f
        }
        bird.run(.sequence([.wait(forDuration: 0.1), dive]))
        near.run(.sequence([.wait(forDuration: 0.1), Self.flap(from: 1.0, to: 1.5, period: 0.9)]))
        far.run(.sequence([.wait(forDuration: 0.14), Self.flap(from: 0.9, to: 1.4, period: 0.9)]))
        zoom(to: 0.95, duration: 2.0, timing: .easeIn)

        // The grab: the flag comes with it, the green erupts.
        after(2.0) { [self] in
            flash(.white, peak: 0.7, duration: 0.3)
            shake(amplitude: 22, duration: 0.6)
            zoom(to: 1.0, duration: 0.3, timing: .easeOut)
            flag.removeFromParent()
            flag.position = beak + CGPoint(x: w * 0.05, y: -w * 0.5)
            flag.zRotation = -0.5
            flag.xScale = -1
            flag.zPosition = 3
            bird.addChild(flag)
            flag.run(Self.wiggle(0.15, period: 0.4))
            for e in Emitters.debris(count: 40, textures: Art.turf, speed: 560, scale: 0.5) { burst(e, at: hole) }
            burst(Emitters.burst(count: 60, speed: 300, color: Metal.bone, scale: 0.12, lifetime: 1.2), at: hole, z: 40)
            ring(at: hole, color: Metal.bone, from: w * 0.05, to: w * 1.2, duration: 0.7, width: 6, squash: 0.35)
            // Away, climbing, with heavy wingbeats.
            near.removeAllActions()
            far.removeAllActions()
            near.run(Self.flap(from: 0.2, to: 2.1, period: 0.5))
            far.run(.sequence([.wait(forDuration: 0.05), Self.flap(from: 0.1, to: 2.0, period: 0.5)]))
            let away = SKAction.customAction(withDuration: 2.0) { [self] node, elapsed in
                let f = CGFloat(Anim.easeIn(Double(elapsed / 2.0)))
                node.position = CGPoint(x: Anim.lerp(0.5, -0.9, f) * w, y: Anim.lerp(grab.y / h, 1.3, f) * h)
                let s = 1.0 - 0.45 * f
                node.xScale = -s
                node.yScale = s
                node.zRotation = 0.6 - 1.2 * f
            }
            bird.run(away)
        }
    }

    /// A bolt and a flash. `x` is where the bolt comes down.
    private func strike(x: CGFloat, strength: CGFloat) {
        let bolt = sprite(Art.bolt, size: CGSize(width: w * 0.35, height: h * 0.95), at: at(x, 0.52), z: -35)
        bolt.alpha = still ? 0.9 : 0
        let glow = addGlow(at: at(x, 0.85), radius: w * 0.9, color: UIColor(red: 0.7, green: 0.75, blue: 1, alpha: 1), alpha: strength * 0.8, z: -65)
        flash(UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1), peak: strength, duration: 0.3)
        guard !still else { return }
        bolt.run(.sequence([
            .fadeAlpha(to: 1, duration: 0.03), .fadeAlpha(to: 0.3, duration: 0.05), .fadeAlpha(to: 1, duration: 0.04), .fadeAlpha(to: 0.5, duration: 0.05), .fadeOut(withDuration: 0.25), .removeFromParent(),
        ]))
        glow.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
    }
}

/// A snowman wobbles, cracks and falls to pieces in the dark.
final class SnowmanScene: EventSKScene {
    override func build(still: Bool) {
        addBackground(top: Metal.black, bottom: UIColor(red: 0.08, green: 0.1, blue: 0.2, alpha: 1))
        addStars(count: 60)
        let moonCenter = at(0.2, 0.82)
        addGlow(at: moonCenter, radius: w * 0.35, color: Metal.blood, alpha: 0.6, z: -85)
        sprite(Art.moon, size: CGSize(width: w * 0.28, height: w * 0.28), at: moonCenter, z: -75)
        addTrees([(0.85, 0.5), (0.12, 0.42), (0.6, 0.3)], baseline: 0.2)
        let snowGround = SKSpriteNode(texture: Textures.linearGradient(top: UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1), bottom: UIColor(red: 0.25, green: 0.3, blue: 0.45, alpha: 1)), size: CGSize(width: w, height: h * 0.22))
        snowGround.anchorPoint = CGPoint(x: 0.5, y: 0)
        snowGround.position = at(0.5, 0)
        snowGround.zPosition = -50
        addChild(snowGround)
        let snow = Emitters.fall(width: w, height: h, rate: 70, speed: 90, texture: Textures.flake, scale: 0.16, color: .white, alpha: 0.95)
        snow.particleScaleRange = 0.1
        snow.particleColorBlendFactor = 0
        snow.xAcceleration = 10
        snow.position = at(0.5, 1.05)
        snow.zPosition = 70
        addChild(snow)
        snow.advanceSimulationTime(10)
        let ground: CGFloat = h * 0.2

        // The snowman, part by part, each its own node so it can come apart.
        let rb = w * 0.2, rm = w * 0.15, rh = w * 0.115
        let x = w * 0.5
        let bottom = sprite(Art.snowball("b"), size: CGSize(width: rb * 2.1, height: rb * 2.1), at: CGPoint(x: x, y: ground), z: 10, anchor: CGPoint(x: 0.5, y: 0.03))
        let middleY = ground + rb * 1.9
        let middle = SKNode()
        middle.position = CGPoint(x: x, y: middleY)
        middle.zPosition = 11
        addChild(middle)
        let middleBall = SKSpriteNode(texture: Art.snowball("m"), size: CGSize(width: rm * 2.1, height: rm * 2.1))
        middle.addChild(middleBall)
        for i in -1...1 {
            let coal = SKSpriteNode(texture: Art.coal, size: CGSize(width: rm * 0.22, height: rm * 0.22))
            coal.position = CGPoint(x: 0, y: CGFloat(i) * rm * 0.5)
            coal.zPosition = 1
            middle.addChild(coal)
        }
        let leftArm = SKSpriteNode(texture: Art.twig, size: CGSize(width: rm * 2.4, height: rm * 1.4))
        leftArm.anchorPoint = CGPoint(x: 0.04, y: 0.37)
        leftArm.position = CGPoint(x: -rm * 0.7, y: rm * 0.2)
        leftArm.xScale = -1
        leftArm.zRotation = -0.2
        leftArm.zPosition = -1
        middle.addChild(leftArm)
        let rightArm = SKSpriteNode(texture: Art.twig, size: CGSize(width: rm * 2.4, height: rm * 1.4))
        rightArm.anchorPoint = CGPoint(x: 0.04, y: 0.37)
        rightArm.position = CGPoint(x: rm * 0.7, y: rm * 0.2)
        rightArm.zRotation = 0.2
        rightArm.zPosition = -1
        middle.addChild(rightArm)
        let headY = middleY + rm * 1.85
        let head = SKNode()
        head.position = CGPoint(x: x, y: headY)
        head.zPosition = 12
        addChild(head)
        let headBall = SKSpriteNode(texture: Art.snowball("h"), size: CGSize(width: rh * 2.1, height: rh * 2.1))
        head.addChild(headBall)
        for s in [CGFloat(-1), 1] {
            let eye = SKSpriteNode(texture: Art.coal, size: CGSize(width: rh * 0.26, height: rh * 0.26))
            eye.position = CGPoint(x: s * rh * 0.35, y: rh * 0.25)
            eye.zPosition = 1
            head.addChild(eye)
        }
        for i in 0..<5 {
            let tooth = SKSpriteNode(texture: Art.coal, size: CGSize(width: rh * 0.14, height: rh * 0.14))
            tooth.position = CGPoint(x: CGFloat(i - 2) * rh * 0.22, y: -rh * 0.45 + abs(CGFloat(i - 2)) * rh * 0.08)
            tooth.zPosition = 1
            head.addChild(tooth)
        }
        let carrot = SKSpriteNode(texture: Art.carrot, size: CGSize(width: rh * 1.2, height: rh * 0.42))
        carrot.anchorPoint = CGPoint(x: 0, y: 0.5)
        carrot.position = CGPoint(x: rh * 0.05, y: -rh * 0.05)
        carrot.zPosition = 2
        head.addChild(carrot)
        let scarf = SKSpriteNode(texture: Art.scarf, size: CGSize(width: rh * 2.3, height: rh * 1.45))
        scarf.position = CGPoint(x: rh * 0.1, y: -rh * 0.95)
        scarf.zPosition = 3
        head.addChild(scarf)
        let hat = SKSpriteNode(texture: Art.topHat, size: CGSize(width: rh * 2.4, height: rh * 2.0))
        hat.anchorPoint = CGPoint(x: 0.5, y: 0.2)
        hat.position = CGPoint(x: 0, y: rh * 0.75)
        hat.zPosition = 4
        hat.zRotation = -0.1
        head.addChild(hat)

        if still {
            head.position = CGPoint(x: x + w * 0.38, y: ground + rh * 0.9)
            head.zRotation = -2.2
            hat.removeFromParent()
            hat.position = CGPoint(x: x - w * 0.3, y: headY + h * 0.08)
            hat.zRotation = 0.9
            addChild(hat)
            middleBall.isHidden = true
            for e in Emitters.debris(count: 40, textures: Art.shards, speed: 500, scale: 0.6) { burst(e, at: middle.position) }
            burst(Emitters.burst(count: 60, speed: 300, color: .white, scale: 0.14, lifetime: 1.4), at: middle.position)
            bottom.xScale = 1.12
            bottom.yScale = 0.78
            leftArm.zRotation = -1.2
            rightArm.zRotation = 1.0
            return
        }

        // Wobble, faster and wider: 0 to 1.0.
        let wobble = SKAction.sequence([
            .rotate(toAngle: 0.03, duration: 0.25), .rotate(toAngle: -0.04, duration: 0.22), .rotate(toAngle: 0.06, duration: 0.18), .rotate(toAngle: -0.08, duration: 0.15), .rotate(toAngle: 0.1, duration: 0.12),
        ])
        for node in [bottom, middle, head] { node.run(wobble) }
        // Cracks and dust: 0.7 to 1.0.
        for (i, time) in [0.7, 0.85, 1.0].enumerated() {
            after(time) { [self] in
                shake(amplitude: 4, duration: 0.15)
                burst(Emitters.burst(count: 15, speed: 120, color: .white, scale: 0.1, lifetime: 0.8), at: CGPoint(x: x + CGFloat(Anim.signed(i, 230)) * rm, y: middleY + CGFloat(Anim.signed(i, 231)) * rm))
                let crack = SKShapeNode(path: Draw.cracks(from: CGPoint(x: CGFloat(Anim.signed(i, 232)) * rm * 0.4, y: CGFloat(Anim.signed(i, 233)) * rm * 0.4), length: rm * 0.9, seed: 234 + i))
                crack.strokeColor = UIColor(red: 0.35, green: 0.4, blue: 0.55, alpha: 1)
                crack.lineWidth = 3
                crack.zPosition = 2
                middle.addChild(crack)
            }
        }
        // The head goes: 1.1.
        after(1.1) { [self] in
            flash(Metal.bone, peak: 0.25, duration: 0.3)
            shake(amplitude: 10, duration: 0.4)
            head.removeAllActions()
            head.run(.sequence([
                Self.toss(velocity: CGVector(dx: w * 0.5, dy: h * 0.25), gravity: -1500, duration: 0.62, spin: -4),
                .run { [self] in
                    burst(Emitters.burst(count: 30, speed: 200, color: .white, scale: 0.12, lifetime: 1), at: head.position)
                    shake(amplitude: 8, duration: 0.3)
                },
                .group([.moveBy(x: w * 0.1, y: 0, duration: 0.5), .rotate(byAngle: -1.2, duration: 0.5)]),
            ]))
            hat.removeFromParent()
            hat.position = CGPoint(x: x, y: headY + rh * 0.75)
            addChild(hat)
            hat.zPosition = 20
            hat.run(Self.toss(velocity: CGVector(dx: -w * 0.5, dy: h * 0.6), gravity: -1500, duration: 2, spin: 5))
            carrot.removeFromParent()
            carrot.position = CGPoint(x: x + rh * 0.3, y: headY)
            carrot.zPosition = 20
            addChild(carrot)
            carrot.run(Self.toss(velocity: CGVector(dx: w * 0.2, dy: h * 0.3), gravity: -1500, duration: 2, spin: 8))
        }
        // The middle shatters, the arms drop, the base slumps: 1.6.
        after(1.6) { [self] in
            shake(amplitude: 12, duration: 0.4)
            middleBall.isHidden = true
            middle.children.filter { $0 !== leftArm && $0 !== rightArm }.forEach { $0.removeFromParent() }
            for e in Emitters.debris(count: 40, textures: Art.shards, speed: 560, scale: 0.6) { burst(e, at: middle.position) }
            burst(Emitters.burst(count: 80, speed: 320, color: .white, scale: 0.14, lifetime: 1.4), at: middle.position)
            let dropLeft = SKAction.rotate(toAngle: -1.3, duration: 0.5)
            dropLeft.timingMode = .easeIn
            leftArm.run(.group([dropLeft, .moveBy(x: -rm * 0.3, y: -rm * 1.5, duration: 0.5)]))
            let dropRight = SKAction.rotate(toAngle: 1.1, duration: 0.45)
            dropRight.timingMode = .easeIn
            rightArm.run(.group([dropRight, .moveBy(x: rm * 0.3, y: -rm * 1.5, duration: 0.45)]))
            let slump = SKAction.scaleX(to: 1.12, y: 0.78, duration: 0.5)
            slump.timingMode = .easeOut
            bottom.run(slump)
        }
    }
}

/// The bird: a bony fist comes up, the middle finger with it, and a bird lands on it.
final class BirdieScene: EventSKScene {
    override func build(still: Bool) {
        addBackground(top: Metal.black, bottom: Metal.bloodDark)
        let center = at(0.5, 0.42)
        // A sunburst of blood red wedges, turning.
        let burstNode = SKNode()
        burstNode.position = center
        burstNode.zPosition = -80
        for i in 0..<14 {
            let a = CGFloat(i) / 14 * .pi * 2
            let wedge = SKShapeNode(path: Draw.polygon([.zero, CGPoint(x: cos(a) * w * 2, y: sin(a) * w * 2), CGPoint(x: cos(a + 0.22) * w * 2, y: sin(a + 0.22) * w * 2)]))
            wedge.fillColor = Metal.blood.withAlphaComponent(0.55)
            wedge.strokeColor = .clear
            burstNode.addChild(wedge)
        }
        addChild(burstNode)
        addGlow(at: center, radius: w * 0.8, color: Metal.ember, alpha: 0.5, z: -70)
        let embers = Emitters.embers(width: w, rate: 18)
        embers.position = at(0.5, 0.0)
        embers.zPosition = 30
        addChild(embers)
        if still { embers.advanceSimulationTime(3) }

        let scale = w * 0.92 / Art.handSize.width
        let handSize = CGSize(width: Art.handSize.width * scale, height: Art.handSize.height * scale)
        let frames = [
            Art.skeletonHand(curl: 0.8, middle: 0.8, thumb: 0.45, key: "fist"),
            Art.skeletonHand(curl: 0.8, middle: 0.45, thumb: 0.45, key: "fist-half"),
            Art.skeletonHand(curl: 0.8, middle: 0.0, thumb: 0.45, key: "bird"),
        ]
        let hand = SKNode()
        hand.position = at(0.5, 0.0)
        hand.zPosition = 10
        addChild(hand)
        let fist = SKSpriteNode(texture: frames[0], size: handSize)
        fist.anchorPoint = Art.handAnchor
        fist.zPosition = 1
        hand.addChild(fist)
        let band = SKSpriteNode(texture: Art.wristband, size: CGSize(width: handSize.width * 0.42, height: handSize.width * 0.18))
        band.position = CGPoint(x: 0, y: handSize.height * 0.06)
        band.zPosition = 2
        hand.addChild(band)
        let tip = CGPoint(x: hand.position.x + 2 * scale, y: hand.position.y + handSize.height * 0.62)
        let bird = sprite(Art.bird, size: CGSize(width: w * 0.3, height: w * 0.225), at: at(-0.3, 0.9), z: 20)

        if still {
            fist.texture = frames[2]
            burstNode.zRotation = 0.3
            bird.position = tip + CGPoint(x: 0, y: w * 0.04)
            return
        }

        burstNode.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 14)))
        // Up with a hitch, then the finger: 0 to 0.6.
        hand.position.y = -h * 0.6
        let up = SKAction.moveTo(y: h * 0.0 + h * 0.04, duration: 0.35)
        up.timingMode = .easeOut
        let settle = SKAction.moveTo(y: 0, duration: 0.15)
        settle.timingMode = .easeInEaseOut
        hand.run(.sequence([up, settle]))
        after(0.3) { [self] in
            fist.run(.sequence([.scaleY(to: 0.95, duration: 0.08), .scaleY(to: 1, duration: 0.08)]))
            after(0.16) { [self] in
                fist.run(.animate(with: frames, timePerFrame: 0.07))
                flash(Metal.bloodBright, peak: 0.5, duration: 0.35)
                shake(amplitude: 12, duration: 0.35)
                burst(Emitters.burst(count: 70, speed: 380, color: Metal.ember, scale: 0.14, lifetime: 1.2), at: tip, z: 25)
                burstNode.run(.sequence([.rotate(byAngle: 0.6, duration: 0.4), .rotate(byAngle: 0, duration: 0)]))
                hand.run(.sequence([.scale(to: 1.06, duration: 0.1), .scale(to: 1, duration: 0.2)]))
                hand.run(.sequence([.wait(forDuration: 0.4), Self.wiggle(0.03, period: 0.4)]))
            }
        }
        // The bird flies in and lands: 0.9 to 1.6.
        after(0.9) { [self] in
            let flight = SKAction.customAction(withDuration: 0.7) { [self] node, elapsed in
                let f = CGFloat(Anim.easeOut(Double(elapsed / 0.7)))
                node.position = CGPoint(x: Anim.lerp(-0.3, tip.x / w, f) * w, y: Anim.lerp(0.9, tip.y / h, f) * h + sin(f * .pi) * h * 0.08 + w * 0.04)
            }
            bird.run(.sequence([flight, .repeatForever(.sequence([.moveBy(x: 0, y: 6, duration: 0.18), .moveBy(x: 0, y: -6, duration: 0.18), .wait(forDuration: 0.3)]))]))
            bird.run(.sequence([.wait(forDuration: 0.7), .run { [self] in burst(Emitters.burst(count: 12, speed: 120, color: Metal.bloodBright, scale: 0.08, lifetime: 0.6), at: tip, z: 22) }]))
        }
        zoom(to: 0.95, duration: 2.5, timing: .easeOut)
    }
}

extension Draw {
    /// A single jagged crack path from a point, for shape nodes.
    static func cracks(from start: CGPoint, length: CGFloat, seed: Int) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        var p = start
        let angle = CGFloat(Anim.hash(seed, 240)) * .pi * 2
        for j in 1...5 {
            p = CGPoint(x: p.x + cos(angle + CGFloat(Anim.signed(j, seed)) * 0.9) * length / 5, y: p.y + sin(angle + CGFloat(Anim.signed(j, seed)) * 0.9) * length / 5)
            path.addLine(to: p)
        }
        return path
    }
}
