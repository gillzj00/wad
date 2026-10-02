import SpriteKit

// The shows of the games. Times in the comments are seconds into the show.

/// A wolf lunges out of the dark, bares its teeth and howls at a blood moon.
final class WolfScene: EventSKScene {
    override func build(still: Bool) {
        addBackground(top: Metal.black, bottom: UIColor(red: 0.16, green: 0.02, blue: 0.04, alpha: 1))
        addStars(count: 70)
        let moonCenter = at(0.76, 0.8)
        addGlow(at: moonCenter, radius: w * 0.42, color: Metal.blood, alpha: 0.7, z: -80)
        let moon = sprite(Art.moon, size: CGSize(width: w * 0.42, height: w * 0.42), at: moonCenter, z: -70)
        moon.alpha = 0.95
        addTrees([(0.08, 0.55), (0.9, 0.7), (0.3, 0.4), (0.68, 0.45)], baseline: 0.02)
        addMist(y: 0.08, color: Metal.bloodDark, rate: 5)
        let embers = Emitters.embers(width: w, rate: 24)
        embers.position = at(0.5, -0.02)
        embers.zPosition = 30
        addChild(embers)
        if still { embers.advanceSimulationTime(3) }

        // The head, its jaw and the inside of the mouth behind both, as one node.
        let scale = w * 0.98 / Art.wolfHeadSize.width
        let wolf = SKNode()
        wolf.position = at(0.5, 0.47)
        wolf.zPosition = 10
        addChild(wolf)
        let mouthInside = SKSpriteNode(texture: Art.wolfMouth, size: CGSize(width: Art.wolfMouthSize.width * scale, height: Art.wolfMouthSize.height * scale))
        mouthInside.position = CGPoint(x: Art.wolfMouthOffset.x * scale, y: Art.wolfMouthOffset.y * scale)
        mouthInside.zPosition = 0
        wolf.addChild(mouthInside)
        let head = SKSpriteNode(texture: Art.wolfHead, size: CGSize(width: Art.wolfHeadSize.width * scale, height: Art.wolfHeadSize.height * scale))
        head.zPosition = 2
        let jaw = SKSpriteNode(texture: Art.wolfJaw, size: CGSize(width: Art.wolfJawSize.width * scale, height: Art.wolfJawSize.height * scale))
        jaw.anchorPoint = CGPoint(x: 0.5, y: 1)
        let jawClosed = CGPoint(x: 0, y: (Art.wolfMouthY - Art.wolfHeadSize.height / 2 + 14) * scale)
        jaw.position = jawClosed
        jaw.zPosition = 1
        wolf.addChild(jaw)
        wolf.addChild(head)
        // Ember light in the eyes, pulsing.
        for eye in Art.wolfEyes {
            let glow = SKSpriteNode(color: Metal.ember, size: CGSize(width: 110 * scale, height: 110 * scale))
            glow.shader = Shaders.pulse
            glow.blendMode = .add
            glow.position = CGPoint(x: eye.x * scale, y: eye.y * scale)
            glow.zPosition = 3
            wolf.addChild(glow)
        }
        let mouth = CGPoint(x: wolf.position.x, y: wolf.position.y + jawClosed.y - 40 * scale)
        let open = CGFloat(56) * scale

        if still {
            jaw.position = CGPoint(x: 0, y: jawClosed.y - open)
            wolf.zRotation = 0.14
            cameraNode.setScale(0.92)
            ring(at: mouth, color: Metal.bone.withAlphaComponent(0.3), from: w * 0.2, to: w * 0.9, duration: 1, width: 2)
            return
        }

        // Anticipation in the dark, then the lunge: 0 to 0.4.
        wolf.setScale(0.55)
        wolf.alpha = 0
        wolf.run(.sequence([
            .group([.fadeIn(withDuration: 0.25), Self.scale(to: 0.7, duration: 0.25, timing: .easeIn)]),
            Self.scale(to: 1.12, duration: 0.15, timing: .easeOut),
            Self.scale(to: 1.0, duration: 0.2, timing: .easeInEaseOut),
        ]))
        after(0.4) { [self] in
            flash(Metal.bloodBright, peak: 0.7, duration: 0.4)
            shake(amplitude: 16, duration: 0.5)
        }
        // The jaw drops, overshoots and settles: 0.5 to 0.95.
        after(0.5) {
            let drop = SKAction.moveTo(y: jawClosed.y - open * 1.15, duration: 0.3)
            drop.timingMode = .easeOut
            let settle = SKAction.moveTo(y: jawClosed.y - open, duration: 0.15)
            settle.timingMode = .easeInEaseOut
            jaw.run(.sequence([drop, settle]))
        }
        // The howl: the head tilts up, breath and rings pour out: from 1.0.
        after(1.0) { [self] in
            let tilt = SKAction.rotate(toAngle: 0.16, duration: 0.5)
            tilt.timingMode = .easeInEaseOut
            wolf.run(tilt)
            wolf.run(.sequence([.wait(forDuration: 0.6), Self.wiggle(0.01, period: 0.12)]))
            let breath = Emitters.smoke(rate: 10, color: Metal.bone, speed: 90, scale: 0.35)
            breath.position = CGPoint(x: 0, y: jawClosed.y - open * 0.5)
            breath.emissionAngle = .pi / 2 + 0.3
            breath.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.35, 0], times: [0, 0.3, 1])
            breath.zPosition = 4
            wolf.addChild(breath)
            for i in 0..<3 {
                after(Double(i) * 0.45) { [self] in
                    ring(at: mouth, color: Metal.bone.withAlphaComponent(0.35), from: w * 0.12, to: w * 1.1, duration: 1.3, width: 2)
                }
            }
        }
        zoom(to: 0.9, duration: 3.0, timing: .easeOut)
        after(2.5) {
            let back = SKAction.rotate(toAngle: 0.06, duration: 0.5)
            back.timingMode = .easeInEaseOut
            wolf.run(back)
        }
    }
}

/// A golf ball falls out of a burning sky and blows the green apart.
final class GreenieScene: EventSKScene {
    override func build(still: Bool) {
        let horizon: CGFloat = 0.42
        addBackground(top: Metal.black, bottom: UIColor(red: 0.5, green: 0.08, blue: 0.03, alpha: 1))
        addStars(count: 40, below: 0.95)
        addGlow(at: at(0.5, horizon), radius: w * 0.9, color: Metal.ember, alpha: 0.45, z: -90)
        for (i, x) in [CGFloat(0.2), 0.75, 0.5].enumerated() {
            let cloud = sprite(Art.cloud, size: CGSize(width: w * (0.7 + CGFloat(i) * 0.15), height: w * 0.35), at: at(x, 0.9 - CGFloat(i) * 0.1), z: -60 + CGFloat(i))
            cloud.alpha = 0.9
            if !still {
                cloud.run(.repeatForever(.sequence([.moveBy(x: -30 - CGFloat(i) * 15, y: 0, duration: 4), .moveBy(x: 30 + CGFloat(i) * 15, y: 0, duration: 4)])))
            }
        }
        // The ground and the green.
        let ground = SKSpriteNode(texture: Textures.linearGradient(top: UIColor(red: 0.12, green: 0.3, blue: 0.1, alpha: 1), bottom: UIColor(red: 0.02, green: 0.08, blue: 0.02, alpha: 1)), size: CGSize(width: w, height: h * horizon))
        ground.anchorPoint = CGPoint(x: 0.5, y: 0)
        ground.position = at(0.5, 0)
        ground.zPosition = -50
        addChild(ground)
        for i in 0..<3 {
            let grass = sprite(Art.grass, size: CGSize(width: w * 0.5, height: 36), at: at(CGFloat(i) * 0.5 - 0.25 + 0.25, horizon), z: -45, anchor: CGPoint(x: 0, y: 0))
            grass.position.x = CGFloat(i) * w * 0.5 - w * 0.25
        }
        let green = SKShapeNode(ellipseOf: CGSize(width: w * 0.9, height: h * 0.2))
        green.fillColor = UIColor(red: 0.2, green: 0.45, blue: 0.14, alpha: 1)
        green.strokeColor = UIColor(red: 0.3, green: 0.55, blue: 0.2, alpha: 1)
        green.lineWidth = 3
        green.position = at(0.5, 0.2)
        green.zPosition = -44
        addChild(green)
        let hole = at(0.5, 0.2)
        let cup = sprite(Art.cup, size: CGSize(width: w * 0.16, height: w * 0.07), at: hole, z: -43)
        let flag = sprite(Art.flag, size: CGSize(width: w * 0.3, height: w * 0.6), at: hole, z: 5, anchor: CGPoint(x: 0.136, y: 0))

        let impact = 1.5
        let ball = SKSpriteNode(texture: Art.golfBall, size: CGSize(width: w * 0.22, height: w * 0.22))
        ball.zPosition = 20
        let trail = Emitters.embers(width: 10, rate: 90, color: Metal.emberBright)
        trail.particleSpeed = 20
        trail.emissionAngle = .pi / 2
        trail.emissionAngleRange = 0.5
        trail.particleLifetime = 0.9
        trail.particleScale = 0.12
        trail.particleScaleSpeed = -0.1
        trail.targetNode = self
        trail.zPosition = -1
        ball.addChild(trail)
        let smokeTrail = Emitters.smoke(rate: 30, color: Metal.ash, speed: 20, scale: 0.3)
        smokeTrail.targetNode = self
        smokeTrail.particleLifetime = 1.2
        smokeTrail.zPosition = -2
        ball.addChild(smokeTrail)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 0.22, height: w * 0.08))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.6)
        shadow.strokeColor = .clear
        shadow.position = hole
        shadow.zPosition = -42
        addChild(shadow)
        addChild(ball)

        if still {
            // Mid-blast: the fireball, the shockwave, the debris in the air.
            ball.removeFromParent()
            shadow.removeFromParent()
            fireball(at: hole, size: w * 1.1, duration: 1)
            ring(at: hole, color: Metal.bone, from: w * 0.3, to: w * 1.6, duration: 1, width: 8, squash: 0.35)
            crater(at: hole)
            for e in Emitters.debris(count: 50, textures: Art.turf, speed: 700, scale: 0.6) { burst(e, at: hole) }
            burst(Emitters.burst(count: 140, speed: 520, color: Metal.emberBright, scale: 0.14, lifetime: 1.8), at: hole, z: 46)
            let smoke = Emitters.smoke(rate: 40, color: UIColor(white: 0.3, alpha: 1), speed: 120, scale: 1.0)
            smoke.position = hole
            smoke.zPosition = 30
            addChild(smoke)
            flag.position = hole + CGPoint(x: w * 0.3, y: h * 0.3)
            flag.zRotation = 2.2
            cameraNode.setScale(0.95)
            return
        }

        // The fall: 0 to 1.5, speeding up, growing as it comes near.
        ball.position = at(0.72, 1.15)
        ball.setScale(0.3)
        shadow.setScale(0.2)
        shadow.alpha = 0
        let fall = SKAction.move(to: hole + CGPoint(x: 0, y: w * 0.06), duration: impact)
        fall.timingMode = .easeIn
        ball.run(.group([fall, Self.scale(to: 1.0, duration: impact, timing: .easeIn), .rotate(byAngle: -9, duration: impact)]))
        shadow.run(.group([.fadeAlpha(to: 0.7, duration: impact), Self.scale(to: 1, duration: impact, timing: .easeIn)]))
        zoom(to: 1.04, duration: impact, timing: .easeIn)

        after(impact) { [self] in
            ball.removeFromParent()
            shadow.removeFromParent()
            flash(.white, peak: 1, duration: 0.45)
            shake(amplitude: 26, duration: 0.8)
            zoom(to: 0.9, duration: 0.12, timing: .easeOut)
            after(0.12) { [self] in zoom(to: 1.0, duration: 1.2, timing: .easeOut) }
            fireball(at: hole, size: w * 1.1, duration: 1.7)
            ring(at: hole, color: Metal.bone, from: w * 0.1, to: w * 2.2, duration: 0.9, width: 10, squash: 0.35)
            ring(at: hole, color: Metal.ember, from: w * 0.05, to: w * 1.6, duration: 1.1, width: 6, squash: 0.35)
            crater(at: hole)
            for e in Emitters.debris(count: 70, textures: Art.turf, speed: 760, scale: 0.45) { burst(e, at: hole) }
            burst(Emitters.burst(count: 160, speed: 560, color: Metal.emberBright, scale: 0.14, lifetime: 1.8), at: hole, z: 46)
            burst(Emitters.burst(count: 60, speed: 300, color: Metal.ember, scale: 0.25, lifetime: 2.2, gravity: -120), at: hole, z: 44)
            let smoke = Emitters.smoke(rate: 45, color: UIColor(white: 0.3, alpha: 1), speed: 140, scale: 1.1)
            smoke.position = hole
            smoke.zPosition = 30
            smoke.numParticlesToEmit = 70
            addChild(smoke)
            flag.run(.group([Self.toss(velocity: CGVector(dx: w * 0.55, dy: h * 1.2), duration: 2.5, spin: 7)]))
        }
    }

    private func crater(at point: CGPoint) {
        let crater = SKShapeNode(ellipseOf: CGSize(width: w * 0.55, height: h * 0.11))
        crater.fillColor = UIColor(red: 0.12, green: 0.05, blue: 0.02, alpha: 1)
        crater.strokeColor = UIColor(red: 0.3, green: 0.15, blue: 0.05, alpha: 1)
        crater.lineWidth = 6
        crater.position = point
        crater.zPosition = -41
        addChild(crater)
        let glow = pulseGlow(at: point, size: w * 0.5, color: Metal.ember, z: -40)
        glow.yScale = 0.35
        if !still {
            crater.setScale(0.1)
            crater.run(Self.scale(to: 1, duration: 0.4, timing: .easeOut))
        }
    }
}

/// A skeleton hand rises from the dead and makes it rain.
final class WadScene: EventSKScene {
    override func build(still: Bool) {
        addBackground(top: Metal.black, bottom: UIColor(red: 0.04, green: 0.1, blue: 0.05, alpha: 1))
        // A shaft of light from above.
        let beam = SKShapeNode(path: Draw.polygon([at(0.3, 1.1), at(0.7, 1.1), at(1.1, -0.1), at(-0.1, -0.1)]))
        beam.fillColor = Metal.bone.withAlphaComponent(0.035)
        beam.strokeColor = .clear
        beam.zPosition = -80
        addChild(beam)
        addGlow(at: at(0.5, 0.05), radius: w * 0.8, color: UIColor(red: 0.2, green: 0.6, blue: 0.25, alpha: 1), alpha: 0.5, z: -70)
        addMist(y: 0.06, color: UIColor(red: 0.3, green: 0.5, blue: 0.3, alpha: 1), rate: 5)
        // The pile of the dead along the bottom.
        for i in 0..<9 {
            let x = 0.08 + CGFloat(i) * 0.105 + CGFloat(Anim.signed(i, 200)) * 0.03
            let size = w * (0.2 + CGFloat(Anim.hash(i, 201)) * 0.1)
            let skull = sprite(Art.skull(i % 4), size: CGSize(width: size, height: size * 1.13), at: at(x, 0.02 + CGFloat(Anim.hash(i, 202)) * 0.06), z: CGFloat(i % 3) - 10)
            skull.zRotation = CGFloat(Anim.signed(i, 203)) * 0.4
            skull.color = .black
            skull.colorBlendFactor = i % 3 == 0 ? 0.05 : 0.4
        }
        for (i, x) in [CGFloat(0.12), 0.85].enumerated() {
            let stone = sprite(Art.gravestone, size: CGSize(width: w * 0.22, height: w * 0.29), at: at(x, 0.0), z: -12, anchor: CGPoint(x: 0.5, y: 0))
            stone.zRotation = i == 0 ? 0.12 : -0.08
        }

        let scale = w * 0.95 / Art.handSize.width
        let frames = [
            Art.skeletonHand(curl: 0.1, key: "open"),
            Art.skeletonHand(curl: 0.45, key: "half"),
            Art.skeletonHand(curl: 0.85, thumb: 0.3, key: "closed"),
            Art.skeletonHand(curl: 0.45, key: "half"),
        ]
        let hand = SKSpriteNode(texture: frames[0], size: CGSize(width: Art.handSize.width * scale, height: Art.handSize.height * scale))
        hand.anchorPoint = Art.handAnchor
        hand.zPosition = 20
        let rest = at(0.5, 0.0)
        addChild(hand)
        let fingertips = CGPoint(x: rest.x, y: rest.y + Art.handSize.height * scale * 0.64)
        let gold = Emitters.embers(width: w * 0.3, rate: 0, color: Metal.emberBright)
        gold.position = CGPoint(x: 0, y: Art.handSize.height * scale * 0.55)
        gold.targetNode = self
        gold.zPosition = 25
        hand.addChild(gold)

        if still {
            hand.position = rest
            hand.texture = frames[2]
            hand.zRotation = -0.05
            rain(from: fingertips, count: 50, continuous: false)
            rain(from: fingertips, count: 0, continuous: true)
            gold.particleBirthRate = 60
            return
        }

        // Up out of the pile with a jolt, then the flicking: 0 to 0.7.
        hand.position = CGPoint(x: rest.x, y: rest.y - h * 0.9)
        let rise = SKAction.moveTo(y: rest.y + h * 0.05, duration: 0.55)
        rise.timingMode = .easeOut
        let settle = SKAction.moveTo(y: rest.y, duration: 0.2)
        settle.timingMode = .easeInEaseOut
        hand.run(.sequence([rise, settle]))
        after(0.55) { [self] in
            shake(amplitude: 8, duration: 0.3)
            flash(Metal.emberBright, peak: 0.35, duration: 0.4)
        }
        after(0.7) { [self] in
            hand.run(.repeatForever(.animate(with: frames, timePerFrame: 0.09)))
            hand.run(Self.wiggle(0.04, period: 0.36))
            gold.particleBirthRate = 60
            rain(from: fingertips, count: 90, continuous: false)
            rain(from: fingertips, count: 0, continuous: true)
        }
        zoom(to: 0.94, duration: 3, timing: .easeOut)
    }

    /// Bills and coins flung up out of the hand, flipping as they fall.
    private func rain(from point: CGPoint, count: Int, continuous: Bool) {
        let bills = Emitters.burst(count: count, speed: 640, color: .white, texture: Art.bill, scale: 0.55, lifetime: 3.2, gravity: -950)
        if continuous {
            bills.numParticlesToEmit = 0
            bills.particleBirthRate = 28
        }
        bills.emissionAngle = .pi / 2
        bills.emissionAngleRange = 1.0
        bills.particleColorBlendFactor = 0
        bills.particleScaleSpeed = 0
        bills.particleRotationSpeed = 5
        bills.particleRotationRange = .pi * 2
        bills.particlePositionRange = CGVector(dx: w * 0.4, dy: 20)
        bills.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [1, 1, 0], times: [0, 0.9, 1])
        let flip = SKAction.repeatForever(.sequence([.scaleX(to: 0.1, duration: 0.25), .scaleX(to: 1, duration: 0.25)]))
        bills.particleAction = flip
        burst(bills, at: point, z: 30)
        let coins = Emitters.burst(count: max(count / 4, 1), speed: 560, color: .white, texture: Art.coin, scale: 0.4, lifetime: 3, gravity: -950)
        if continuous {
            coins.numParticlesToEmit = 0
            coins.particleBirthRate = 10
        }
        coins.emissionAngle = .pi / 2
        coins.emissionAngleRange = 1.2
        coins.particleColorBlendFactor = 0
        coins.particleScaleSpeed = 0
        coins.particleRotationSpeed = 2
        coins.particleAction = flip
        burst(coins, at: point, z: 31)
    }
}

/// A hand loses its skin to a dagger, one tear at a time, down to the bone.
final class SkinScene: EventSKScene {
    override func build(still: Bool) {
        addBackground(top: Metal.black, bottom: Metal.bloodDark)
        addGlow(at: at(0.5, 0.45), radius: w * 0.75, color: Metal.blood, alpha: 0.6, z: -80)
        addMist(y: 0.05, color: Metal.bloodDark, rate: 5)
        let scale = w * 0.92 / Art.handSize.width
        let handSize = CGSize(width: Art.handSize.width * scale, height: Art.handSize.height * scale)
        let wrist = at(0.5, 0.06)
        let top = wrist.y + handSize.height * 0.9
        let bones = sprite(Art.skeletonHand(curl: 0.1, key: "open"), size: handSize, at: wrist, z: 10, anchor: Art.handAnchor)
        // The skin, in a crop that uncovers the bones from the fingertips down.
        let crop = SKCropNode()
        crop.zPosition = 11
        let mask = SKSpriteNode(color: .white, size: CGSize(width: w * 2, height: h * 2))
        mask.anchorPoint = CGPoint(x: 0.5, y: 1)
        mask.position = CGPoint(x: wrist.x, y: top)
        crop.maskNode = mask
        let flesh = SKSpriteNode(texture: Art.fleshHand(curl: 0.1, key: "open"), size: handSize)
        flesh.anchorPoint = Art.handAnchor
        flesh.position = wrist
        crop.addChild(flesh)
        addChild(crop)
        let flap = sprite(Art.skinFlap, size: CGSize(width: w * 0.5, height: w * 0.73), at: CGPoint(x: wrist.x + w * 0.1, y: top), z: 14, anchor: CGPoint(x: 0.5, y: 0.98))
        flap.yScale = 0.05
        let drips = Emitters.fall(width: w * 0.5, height: h, rate: 0, speed: 420, texture: Textures.streak, scale: 0.6, color: Metal.bloodBright, alpha: 1)
        drips.yAcceleration = -900
        drips.particleScaleSpeed = 0.3
        drips.position = CGPoint(x: wrist.x, y: top)
        drips.zPosition = 16
        addChild(drips)
        let knife = sprite(Art.knife, size: CGSize(width: w * 0.9, height: w * 0.2), at: at(1.5, 0.9), z: 20)
        knife.zRotation = -0.5
        let tearTimes = (0..<5).map { 0.15 + Double($0) * 0.36 }
        let step = (top - wrist.y - handSize.height * 0.05) / 5
        let swing = Self.wiggle(0.12, period: 0.5)

        if still {
            let line = top - step * 3
            mask.position.y = line
            flap.position.y = line
            flap.yScale = 0.65
            flap.zRotation = 0.1
            knife.position = CGPoint(x: wrist.x + w * 0.2, y: line + w * 0.1)
            knife.zRotation = -0.35
            drips.particleBirthRate = 30
            drips.position.y = line
            drips.advanceSimulationTime(2)
            splatter(at: CGPoint(x: wrist.x - w * 0.2, y: line + w * 0.1))
            splatter(at: CGPoint(x: wrist.x + w * 0.3, y: line - w * 0.2))
            cameraNode.setScale(0.94)
            bones.alpha = 1
            return
        }
        bones.alpha = 1
        zoom(to: 0.93, duration: 2.5, timing: .easeOut)
        flap.run(swing)
        for (i, time) in tearTimes.enumerated() {
            let line = top - step * CGFloat(i + 1)
            after(time - 0.12) { [self] in
                // The dagger comes in from the right and slashes along the line.
                knife.removeAllActions()
                knife.position = CGPoint(x: wrist.x + w * 0.75, y: line + w * 0.2)
                knife.zRotation = -0.2
                let slash = SKAction.move(to: CGPoint(x: wrist.x - w * 0.55, y: line - w * 0.05), duration: 0.3)
                slash.timingMode = .easeIn
                knife.run(.sequence([.group([slash, .rotate(toAngle: -0.55, duration: 0.3)]), .move(to: at(-0.6, 0.3), duration: 0.3)]))
            }
            after(time) { [self] in
                flash(Metal.bloodBright, peak: 0.45, duration: 0.3)
                shake(amplitude: 10, duration: 0.3)
                let peel = SKAction.moveTo(y: line, duration: 0.3)
                peel.timingMode = .easeOut
                mask.run(peel)
                flap.run(.group([peel, .scaleY(to: 0.15 + 0.2 * CGFloat(i + 1), duration: 0.3)]))
                drips.run(peel)
                drips.particleBirthRate = 12 + CGFloat(i) * 8
                burst(Emitters.drops(count: 30, speed: 420, scale: 0.22, lifetime: 1.2), at: CGPoint(x: wrist.x, y: line), z: 18)
                splatter(at: CGPoint(x: wrist.x + CGFloat(Anim.signed(i, 210)) * w * 0.3, y: line + CGFloat(Anim.signed(i, 211)) * w * 0.15))
            }
        }
        // The last tear: the skin drops off and the hand shakes bare.
        after(2.0) { [self] in
            flap.removeAllActions()
            flap.run(.sequence([.group([Self.toss(velocity: CGVector(dx: w * 0.2, dy: -h * 0.2), duration: 1.0, spin: 1.5), .fadeOut(withDuration: 1.0)]), .removeFromParent()]))
            bones.run(Self.wiggle(0.03, period: 0.1))
            drips.particleBirthRate = 60
            shake(amplitude: 14, duration: 0.5)
        }
    }

    /// Blood on the wall behind the hand: flat drops, the big ones running.
    private func splatter(at point: CGPoint) {
        for i in 0..<7 {
            let r = w * (0.015 + CGFloat(Anim.hash(i, 220)) * 0.04)
            let drop = sprite(Art.bloodDrop, size: CGSize(width: r * 1.5, height: r * 2), at: CGPoint(x: point.x + CGFloat(Anim.signed(i, 221)) * w * 0.14, y: point.y + CGFloat(Anim.signed(i, 222)) * w * 0.14), z: -60)
            drop.zRotation = CGFloat(Anim.signed(i, 224)) * 0.4
            if !still {
                drop.setScale(0.2)
                drop.run(Self.scale(to: 1, duration: 0.25, timing: .easeOut))
            }
        }
    }
}
