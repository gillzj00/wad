import SpriteKit

/// Set dressing shared by the shows.
extension EventSKScene {
    /// Tiny twinkling stars over the top of the sky.
    func addStars(count: Int, below: CGFloat = 0.85) {
        for i in 0..<count {
            let star = SKSpriteNode(texture: Textures.dot, size: CGSize(width: 6, height: 6))
            star.position = at(CGFloat(Anim.hash(i, 1)), CGFloat(Anim.hash(i, 2)) * below)
            star.setScale(0.4 + CGFloat(Anim.hash(i, 3)) * 0.9)
            star.alpha = 0.3 + CGFloat(Anim.hash(i, 4)) * 0.6
            star.zPosition = -90
            star.blendMode = .add
            addChild(star)
            guard !still else { continue }
            let twinkle = SKAction.sequence([
                .fadeAlpha(to: 0.15, duration: 0.6 + Anim.hash(i, 5) * 1.2),
                .fadeAlpha(to: star.alpha, duration: 0.6 + Anim.hash(i, 6) * 1.2),
            ])
            star.run(.repeatForever(twinkle))
        }
    }

    /// Dead trees along the bottom, the nearer ones bigger and darker.
    func addTrees(_ placements: [(x: CGFloat, scale: CGFloat)], baseline: CGFloat, z: CGFloat = -40) {
        for (i, placement) in placements.enumerated() {
            let tree = SKSpriteNode(texture: Art.deadTree)
            tree.anchorPoint = CGPoint(x: 0.5, y: 0)
            tree.position = at(placement.x, baseline)
            tree.setScale(placement.scale * w / 400)
            tree.xScale *= i % 2 == 0 ? 1 : -1
            tree.zPosition = z + CGFloat(i)
            tree.color = .black
            tree.colorBlendFactor = 0.2 + CGFloat(i) * 0.1
            addChild(tree)
        }
    }

    /// Low mist drifting along the ground.
    func addMist(y: CGFloat, color: UIColor = Metal.ash, rate: CGFloat = 6, z: CGFloat = -30) {
        let mist = Emitters.smoke(rate: rate, color: color, speed: 12, scale: 1.4)
        mist.particlePositionRange = CGVector(dx: w * 1.2, dy: 30)
        mist.emissionAngle = 0
        mist.emissionAngleRange = 0.3
        mist.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.25, 0.25, 0], times: [0, 0.2, 0.7, 1])
        mist.particleLifetime = 5
        mist.position = at(0.5, y)
        mist.zPosition = z
        addChild(mist)
        mist.advanceSimulationTime(6)
    }

    /// An expanding ring, for howls and shockwaves.
    func ring(at point: CGPoint, color: UIColor, from: CGFloat, to: CGFloat, duration: TimeInterval, width: CGFloat = 4, z: CGFloat = 50, squash: CGFloat = 1) {
        let node = SKShapeNode(circleOfRadius: 50)
        node.strokeColor = color
        node.lineWidth = width
        node.glowWidth = width
        node.fillColor = .clear
        node.position = point
        node.zPosition = z
        node.xScale = from / 50
        node.yScale = from / 50 * squash
        addChild(node)
        if still {
            node.xScale = (from + to) / 2 / 50
            node.yScale = node.xScale * squash
            node.alpha = 0.5
            return
        }
        let grow = SKAction.scaleX(to: to / 50, y: to / 50 * squash, duration: duration)
        grow.timingMode = .easeOut
        node.run(.sequence([.group([grow, .fadeOut(withDuration: duration)]), .removeFromParent()]))
    }

    /// A one-off emitter that removes itself once its particles are gone.
    func burst(_ emitter: SKEmitterNode, at point: CGPoint, z: CGFloat = 40) {
        emitter.position = point
        emitter.zPosition = z
        addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: TimeInterval(emitter.particleLifetime + emitter.particleLifetimeRange + 0.5)), .removeFromParent()]))
    }

    /// A fireball with the fire shader that grows and burns out.
    func fireball(at point: CGPoint, size: CGFloat, duration: TimeInterval, z: CGFloat = 45) {
        let node = SKSpriteNode(color: .white, size: CGSize(width: size, height: size))
        node.shader = Shaders.fire
        node.position = point
        node.zPosition = z
        node.blendMode = .add
        node.setScale(0.15)
        addChild(node)
        if still {
            node.setScale(0.9)
            return
        }
        let grow = SKAction.scale(to: 1.2, duration: duration * 0.45)
        grow.timingMode = .easeOut
        node.run(.sequence([grow, .group([.scale(to: 1.5, duration: duration * 0.55), .fadeOut(withDuration: duration * 0.55)]), .removeFromParent()]))
    }

    /// A pulsing glow with the pulse shader.
    func pulseGlow(at point: CGPoint, size: CGFloat, color: UIColor, z: CGFloat = -20) -> SKSpriteNode {
        let node = SKSpriteNode(color: color, size: CGSize(width: size, height: size))
        node.shader = Shaders.pulse
        node.position = point
        node.zPosition = z
        node.blendMode = .add
        addChild(node)
        return node
    }

    /// A wiggle around the node's current rotation, forever.
    static func wiggle(_ amplitude: CGFloat, period: TimeInterval) -> SKAction {
        let a = SKAction.rotate(byAngle: amplitude, duration: period / 2)
        a.timingMode = .easeInEaseOut
        let b = SKAction.rotate(byAngle: -amplitude * 2, duration: period)
        b.timingMode = .easeInEaseOut
        let c = SKAction.rotate(byAngle: amplitude, duration: period / 2)
        c.timingMode = .easeInEaseOut
        return .repeatForever(.sequence([a, b, c]))
    }

    /// Flapping: the wing swings between two angles, forever.
    static func flap(from: CGFloat, to: CGFloat, period: TimeInterval) -> SKAction {
        let down = SKAction.rotate(toAngle: to, duration: period / 2, shortestUnitArc: true)
        down.timingMode = .easeInEaseOut
        let up = SKAction.rotate(toAngle: from, duration: period / 2, shortestUnitArc: true)
        up.timingMode = .easeInEaseOut
        return .repeatForever(.sequence([down, up]))
    }

    /// Moves with easing.
    static func move(to point: CGPoint, duration: TimeInterval, timing: SKActionTimingMode) -> SKAction {
        let action = SKAction.move(to: point, duration: duration)
        action.timingMode = timing
        return action
    }

    static func scale(to value: CGFloat, duration: TimeInterval, timing: SKActionTimingMode) -> SKAction {
        let action = SKAction.scale(to: value, duration: duration)
        action.timingMode = timing
        return action
    }

    static func rotate(to angle: CGFloat, duration: TimeInterval, timing: SKActionTimingMode) -> SKAction {
        let action = SKAction.rotate(toAngle: angle, duration: duration, shortestUnitArc: true)
        action.timingMode = timing
        return action
    }

    /// A throw: `velocity` points per second from where the node is when it
    /// starts, under gravity, for `duration`. One action per throw.
    static func toss(velocity: CGVector, gravity: CGFloat = -1400, duration: TimeInterval, spin: CGFloat = 0) -> SKAction {
        var start: CGPoint?
        var startRotation: CGFloat = 0
        return .customAction(withDuration: duration) { node, elapsed in
            if start == nil {
                start = node.position
                startRotation = node.zRotation
            }
            guard let start else { return }
            let t = CGFloat(elapsed)
            node.position = CGPoint(x: start.x + velocity.dx * t, y: start.y + velocity.dy * t + 0.5 * gravity * t * t)
            node.zRotation = startRotation + spin * t
        }
    }
}
