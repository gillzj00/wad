import SpriteKit
import UIKit

/// The look of every show: the app's death metal palette (black, blood,
/// bone and ember from the asset catalog) with the shades the drawings need.
enum Metal {
    private static func asset(_ name: String, _ fallback: UIColor) -> UIColor {
        UIColor(named: name) ?? fallback
    }

    static let black = UIColor(red: 0.02, green: 0.01, blue: 0.02, alpha: 1)
    static let charcoal = asset("Charcoal", UIColor(red: 0.1, green: 0.08, blue: 0.09, alpha: 1))
    static let blood = asset("Blood", UIColor(red: 0.62, green: 0.03, blue: 0.06, alpha: 1))
    static let bloodBright = UIColor(red: 0.85, green: 0.08, blue: 0.1, alpha: 1)
    static let bloodDark = UIColor(red: 0.28, green: 0.01, blue: 0.03, alpha: 1)
    static let bone = asset("Bone", UIColor(red: 0.93, green: 0.89, blue: 0.8, alpha: 1))
    static let boneShade = UIColor(red: 0.7, green: 0.64, blue: 0.52, alpha: 1)
    static let boneDark = UIColor(red: 0.42, green: 0.36, blue: 0.28, alpha: 1)
    static let ember = asset("Ember", UIColor(red: 1, green: 0.42, blue: 0.06, alpha: 1))
    static let emberBright = UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1)
    static let ash = asset("Ash", UIColor(red: 0.45, green: 0.42, blue: 0.42, alpha: 1))
    static let flesh = UIColor(red: 0.89, green: 0.68, blue: 0.54, alpha: 1)
    static let fleshShade = UIColor(red: 0.62, green: 0.38, blue: 0.28, alpha: 1)
    /// The ink outline that holds every drawn form.
    static let ink = UIColor(red: 0.07, green: 0.04, blue: 0.05, alpha: 1)
    static let boneLight = UIColor(red: 1, green: 0.99, blue: 0.94, alpha: 1)
    static let fleshLight = UIColor(red: 0.98, green: 0.82, blue: 0.7, alpha: 1)
    static let fleshDark = UIColor(red: 0.45, green: 0.24, blue: 0.18, alpha: 1)
    static let furLight = UIColor(red: 0.64, green: 0.62, blue: 0.64, alpha: 1)
    static let fur = UIColor(red: 0.42, green: 0.4, blue: 0.43, alpha: 1)
    static let furDark = UIColor(red: 0.21, green: 0.19, blue: 0.21, alpha: 1)
    static let furDeep = UIColor(red: 0.11, green: 0.09, blue: 0.11, alpha: 1)
    static let gum = UIColor(red: 0.45, green: 0.1, blue: 0.14, alpha: 1)
    static let eagleBrown = UIColor(red: 0.36, green: 0.22, blue: 0.1, alpha: 1)
    static let eagleDark = UIColor(red: 0.2, green: 0.11, blue: 0.05, alpha: 1)
    static let eagleDeep = UIColor(red: 0.1, green: 0.05, blue: 0.02, alpha: 1)
    static let eagleLight = UIColor(red: 0.55, green: 0.38, blue: 0.2, alpha: 1)
    static let beakYellow = UIColor(red: 0.98, green: 0.75, blue: 0.15, alpha: 1)
    static let beakShade = UIColor(red: 0.8, green: 0.5, blue: 0.08, alpha: 1)
    static let snowShade = UIColor(red: 0.7, green: 0.77, blue: 0.92, alpha: 1)
    static let snowDeep = UIColor(red: 0.5, green: 0.56, blue: 0.76, alpha: 1)
}

/// One show: a SpriteKit scene with a camera, a flash layer and a vignette,
/// built once in `build(still:)`. With `still` the scene is the poster frame:
/// everything in its most dramatic place, no actions, emitters advanced so
/// particles are there, and the scene paused.
///
/// Main actor throughout: SpriteKit drives the scene on the main thread, and
/// the SDKs differ on whether `SKNode` says so, so the shows say it themselves.
@MainActor
class EventSKScene: SKScene {
    let event: GameEvent
    let still: Bool
    let cameraNode = SKCameraNode()
    private var flashNode: SKSpriteNode?

    /// Nodes drawn after everything else (flash, vignette).
    static let overlayZ: CGFloat = 1000

    init(event: GameEvent, still: Bool) {
        self.event = event
        self.still = still
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        backgroundColor = Metal.black
    }

    @available(*, unavailable)
    nonisolated required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var builtSize: CGSize?

    nonisolated override func didMove(to view: SKView) {
        MainActor.assumeIsolated {
            view.ignoresSiblingOrder = true
            buildIfNeeded()
        }
    }

    /// The scene takes the view's size; if that arrives after `didMove`, the
    /// show is laid out again for it.
    nonisolated override func didChangeSize(_ oldSize: CGSize) {
        MainActor.assumeIsolated {
            super.didChangeSize(oldSize)
            guard view != nil, let builtSize, abs(builtSize.width - size.width) > 1 || abs(builtSize.height - size.height) > 1 else { return }
            removeAllActions()
            removeAllChildren()
            self.builtSize = nil
            isPaused = false
            buildIfNeeded()
        }
    }

    private func buildIfNeeded() {
        guard builtSize == nil, size.width > 0, size.height > 0 else { return }
        builtSize = size
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        let flash = SKSpriteNode(color: .white, size: CGSize(width: size.width * 3, height: size.height * 3))
        flash.alpha = 0
        flash.zPosition = Self.overlayZ
        flash.position = cameraNode.position
        addChild(flash)
        flashNode = flash
        build(still: still)
        addVignette()
        if still {
            for case let emitter as SKEmitterNode in allEmitters(in: self) {
                emitter.advanceSimulationTime(1.5)
            }
            isPaused = true
        }
    }

    /// The scene's content. `seconds` helpers below schedule the choreography.
    func build(still: Bool) {}

    func tearDown() {
        removeAllActions()
        removeAllChildren()
    }

    // MARK: Geometry

    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    var center: CGPoint { CGPoint(x: w / 2, y: h / 2) }

    /// A point from fractions of the width and height, measured from the bottom left.
    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }

    // MARK: Choreography

    /// Runs `body` after `delay` seconds (right away in a still).
    func after(_ delay: TimeInterval, _ body: @escaping () -> Void) {
        guard !still else { return }
        run(.sequence([.wait(forDuration: delay), .run(body)]))
    }

    /// A white (or colored) frame over everything.
    func flash(_ color: UIColor = .white, peak: CGFloat = 0.9, duration: TimeInterval = 0.35) {
        guard let flashNode, !still else { return }
        flashNode.color = color
        flashNode.removeAllActions()
        flashNode.alpha = peak
        flashNode.run(.fadeOut(withDuration: duration))
    }

    /// Shakes the camera: a burst of small random offsets that die down.
    func shake(amplitude: CGFloat, duration: TimeInterval) {
        guard !still else { return }
        let steps = max(4, Int(duration / 0.04))
        var actions: [SKAction] = []
        for i in 0..<steps {
            let decay = 1 - CGFloat(i) / CGFloat(steps)
            let dx = CGFloat.random(in: -amplitude...amplitude) * decay
            let dy = CGFloat.random(in: -amplitude...amplitude) * decay
            actions.append(.move(to: CGPoint(x: center.x + dx, y: center.y + dy), duration: 0.04))
        }
        actions.append(.move(to: center, duration: 0.04))
        cameraNode.run(.sequence(actions), withKey: "shake")
    }

    /// Zooms the camera in (scale below 1) or out, with easing.
    func zoom(to scale: CGFloat, duration: TimeInterval, timing: SKActionTimingMode = .easeInEaseOut) {
        guard !still else {
            cameraNode.setScale(scale)
            return
        }
        let action = SKAction.scale(to: scale, duration: duration)
        action.timingMode = timing
        cameraNode.run(action, withKey: "zoom")
    }

    // MARK: Layers

    /// A full-screen gradient behind everything, top color to bottom color.
    @discardableResult
    func addBackground(top: UIColor, bottom: UIColor, z: CGFloat = -100) -> SKSpriteNode {
        let node = SKSpriteNode(texture: Textures.linearGradient(top: top, bottom: bottom), size: CGSize(width: w, height: h))
        node.position = center
        node.zPosition = z
        addChild(node)
        return node
    }

    /// A soft glow: a radial gradient from `color` to clear.
    @discardableResult
    func addGlow(at point: CGPoint, radius: CGFloat, color: UIColor, alpha: CGFloat = 1, z: CGFloat = -50) -> SKSpriteNode {
        let node = SKSpriteNode(texture: Textures.radialGlow(color: color), size: CGSize(width: radius * 2, height: radius * 2))
        node.position = point
        node.zPosition = z
        node.alpha = alpha
        node.blendMode = .add
        addChild(node)
        return node
    }

    /// Darkens the edges of the screen, with a shader so it costs one quad.
    private func addVignette() {
        let node = SKSpriteNode(color: .white, size: CGSize(width: w, height: h))
        node.position = center
        node.zPosition = Self.overlayZ - 1
        node.shader = Shaders.vignette
        addChild(node)
    }

    /// A sprite from a drawing, at `size` points, anchored at the middle unless told otherwise.
    func sprite(_ texture: SKTexture, size: CGSize, at point: CGPoint, z: CGFloat = 0, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture, size: size)
        node.anchorPoint = anchor
        node.position = point
        node.zPosition = z
        addChild(node)
        return node
    }

    private func allEmitters(in node: SKNode) -> [SKNode] {
        node.children.flatMap { [$0] + allEmitters(in: $0) }
    }
}

// MARK: - Textures

/// Drawings turned into textures. Each is rendered once and kept, so a show
/// never draws while it runs.
@MainActor
enum Textures {
    private static var cache: [String: SKTexture] = [:]

    /// The texture drawn by `draw` into a context `size` points across (y up,
    /// origin at the bottom left like SpriteKit), cached under `key`.
    static func make(_ key: String, size: CGSize, scale: CGFloat = 2, draw: (CGContext, CGSize) -> Void) -> SKTexture {
        if let cached = cache[key] {
            return cached
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            // Flip to SpriteKit's orientation so the drawings and the sprites agree.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            draw(context, size)
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    static func linearGradient(top: UIColor, bottom: UIColor) -> SKTexture {
        make("gradient-\(top)-\(bottom)", size: CGSize(width: 8, height: 256), scale: 1) { context, size in
            context.drawLinearGradient(
                Draw.gradient([bottom, top]),
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    static func radialGlow(color: UIColor) -> SKTexture {
        make("glow-\(color)", size: CGSize(width: 256, height: 256), scale: 1) { context, size in
            context.drawRadialGradient(
                Draw.gradient([color, color.withAlphaComponent(0.35), color.withAlphaComponent(0)]),
                startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                endCenter: CGPoint(x: 128, y: 128), endRadius: 128,
                options: []
            )
        }
    }

    /// A soft dot for sparks, embers and foam.
    static var dot: SKTexture { radialGlow(color: .white) }

    /// A hard-edged flake with a dark rim, for snow and dust in the foreground.
    static var flake: SKTexture { make("flake", size: CGSize(width: 32, height: 32), scale: 2) { context, size in
        let disc = Draw.circle(at: CGPoint(x: 16, y: 16), r: 12)
        Draw.fill(context, disc, UIColor(white: 0.55, alpha: 1))
        Draw.fill(context, Draw.circle(at: CGPoint(x: 15, y: 17), r: 10), .white)
    } }

    /// A streak for rain and trails.
    static var streak: SKTexture { make("streak", size: CGSize(width: 4, height: 32), scale: 2) { context, size in
        context.drawLinearGradient(
            Draw.gradient([UIColor.white.withAlphaComponent(0), .white, UIColor.white.withAlphaComponent(0)]),
            start: .zero, end: CGPoint(x: 0, y: size.height), options: []
        )
    } }

    /// A soft irregular blob for smoke and clouds.
    static var smoke: SKTexture { make("smoke", size: CGSize(width: 128, height: 128), scale: 1) { context, size in
        for i in 0..<6 {
            let r = CGFloat(30 + (i * 7) % 20)
            let c = CGPoint(x: 64 + CGFloat((i * 37) % 40) - 20, y: 64 + CGFloat((i * 23) % 40) - 20)
            context.drawRadialGradient(
                Draw.gradient([UIColor.white.withAlphaComponent(0.55), UIColor.white.withAlphaComponent(0)]),
                startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: []
            )
        }
    } }
}

// MARK: - Drawing helpers (Core Graphics)

enum Draw {
    static func gradient(_ colors: [UIColor]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    }

    static func fill(_ context: CGContext, _ rect: CGRect, _ color: UIColor) {
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    static func fill(_ context: CGContext, _ path: CGPath, _ color: UIColor) {
        context.saveGState()
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    static func stroke(_ context: CGContext, _ path: CGPath, _ color: UIColor, width: CGFloat, cap: CGLineCap = .round) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(cap)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    /// Fills the path with a gradient from `from` to `to`: the light side first.
    static func shade(_ context: CGContext, _ path: CGPath, _ colors: [UIColor], from: CGPoint, to: CGPoint) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient(colors), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    /// Fills the path with a radial gradient: a lit sphere when `light` is off center.
    static func sphere(_ context: CGContext, _ path: CGPath, _ colors: [UIColor], light: CGPoint, radius: CGFloat) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawRadialGradient(gradient(colors), startCenter: light, startRadius: 0, endCenter: light, endRadius: radius, options: [.drawsAfterEndLocation])
        context.restoreGState()
    }

    /// A drop shadow under whatever `body` draws.
    static func shadowed(_ context: CGContext, blur: CGFloat, offset: CGSize = CGSize(width: 0, height: -4), color: UIColor = UIColor.black.withAlphaComponent(0.6), _ body: () -> Void) {
        context.saveGState()
        context.setShadow(offset: offset, blur: blur, color: color.cgColor)
        body()
        context.restoreGState()
    }

    static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    static func ellipse(at c: CGPoint, rx: CGFloat, ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    static func circle(at c: CGPoint, r: CGFloat) -> CGPath { ellipse(at: c, rx: r, ry: r) }

    static func capsule(from a: CGPoint, to b: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        return path.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }

    /// A smooth closed curve through the points (Catmull-Rom), for organic shapes.
    static func smooth(_ points: [CGPoint], tension: CGFloat = 0.5) -> CGPath {
        let path = CGMutablePath()
        guard points.count > 2 else { return polygon(points) }
        let n = points.count
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * tension / 3, y: p1.y + (p2.y - p0.y) * tension / 3)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * tension / 3, y: p2.y - (p3.y - p1.y) * tension / 3)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    /// Short strokes along the outline of a path, for fur and grass.
    static func fur(_ context: CGContext, along points: [CGPoint], length: CGFloat, color: UIColor, seed: Int, every: Int = 1) {
        let n = points.count
        for i in stride(from: 0, to: n, by: every) {
            let p = points[i], q = points[(i + 1) % n]
            let dx = q.x - p.x, dy = q.y - p.y
            let len = max(hypot(dx, dy), 0.001)
            // Outward normal, with a random lean.
            let lean = CGFloat(Anim.signed(i, seed)) * 0.6
            let nx = dy / len, ny = -dx / len
            let tip = CGPoint(x: p.x + (nx + lean * dx / len) * length * CGFloat(0.6 + Anim.hash(i, seed + 1) * 0.8), y: p.y + (ny + lean * dy / len) * length * CGFloat(0.6 + Anim.hash(i, seed + 1) * 0.8))
            let path = CGMutablePath()
            path.move(to: p)
            path.addLine(to: tip)
            stroke(context, path, color, width: 2.5)
        }
    }

    /// The key light of every drawing: from the top left.
    static let keyLight = CGVector(dx: -0.6, dy: 0.8)

    static func translated(_ path: CGPath, _ dx: CGFloat, _ dy: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: dx, y: dy)
        return path.copy(using: &transform) ?? path
    }

    /// Cel shading: a flat base, a shadow crescent on the side away from the
    /// key light (the shape minus itself moved toward the light, so the
    /// shadow follows the form), an optional darker core along the edge, a
    /// rim light sliver on that dark edge, and the ink outline.
    static func cel(_ context: CGContext, _ path: CGPath, base: UIColor, shadow: UIColor, core: UIColor? = nil, rim: UIColor? = nil, ink: UIColor? = Metal.ink, width: CGFloat = 3, depth: CGFloat, light: CGVector = keyLight) {
        let shape = path.normalized(using: .winding)
        fill(context, shape, base)
        let crescent = shape.subtracting(translated(shape, light.dx * depth, light.dy * depth), using: .winding)
        fill(context, crescent, shadow)
        if let core {
            fill(context, shape.subtracting(translated(shape, light.dx * depth * 0.45, light.dy * depth * 0.45), using: .winding), core)
        }
        if let rim {
            fill(context, shape.subtracting(translated(shape, light.dx * width * 1.1, light.dy * width * 1.1), using: .winding), rim)
        }
        if let ink {
            stroke(context, shape, ink, width: width)
        }
    }

    /// A cartoon highlight: a soft-edged flat blob toward the light.
    static func highlight(_ context: CGContext, _ clip: CGPath, at point: CGPoint, rx: CGFloat, ry: CGFloat, color: UIColor = UIColor.white.withAlphaComponent(0.5)) {
        context.saveGState()
        context.addPath(clip)
        context.clip()
        fill(context, ellipse(at: point, rx: rx, ry: ry), color)
        context.restoreGState()
    }

    /// A jagged ring of fur tufts round an ellipse, the tufts leaning down.
    static func ruff(center: CGPoint, rx: CGFloat, ry: CGFloat, spikes: Int, length: CGFloat, seed: Int, from: CGFloat = 0, to: CGFloat = .pi * 2) -> CGPath {
        var points: [CGPoint] = []
        for i in 0...spikes {
            let a = from + (to - from) * CGFloat(i) / CGFloat(spikes)
            let out = i % 2 == 0 ? length * (0.6 + CGFloat(Anim.hash(i + seed, 400)) * 0.7) : 0
            let lean = -0.25 * sin(a) * CGFloat(i % 2)
            points.append(CGPoint(x: center.x + cos(a + lean) * (rx + out), y: center.y + sin(a + lean) * (ry + out)))
        }
        return polygon(points)
    }

    /// Fine cracks: a few jagged lines, for bone and ice.
    static func cracks(_ context: CGContext, around c: CGPoint, count: Int, length: CGFloat, color: UIColor, seed: Int) {
        for i in 0..<count {
            let path = CGMutablePath()
            var p = CGPoint(x: c.x + CGFloat(Anim.signed(i, seed)) * length * 0.3, y: c.y + CGFloat(Anim.signed(i, seed + 1)) * length * 0.3)
            path.move(to: p)
            let angle = CGFloat(Anim.hash(i, seed + 2)) * .pi * 2
            for j in 1...4 {
                p = CGPoint(x: p.x + cos(angle + CGFloat(Anim.signed(j + i * 7, seed + 3)) * 0.8) * length / 4, y: p.y + sin(angle + CGFloat(Anim.signed(j + i * 7, seed + 3)) * 0.8) * length / 4)
                path.addLine(to: p)
            }
            stroke(context, path, color, width: 1.5, cap: .butt)
        }
    }
}

// MARK: - Shaders

@MainActor
enum Shaders {
    /// Darkens toward the edges.
    static let vignette: SKShader = {
        let shader = SKShader(source: """
        void main() {
            vec2 uv = v_tex_coord - vec2(0.5);
            uv.x *= 0.78;
            float d = length(uv);
            float a = smoothstep(0.28, 0.72, d) * 0.92;
            gl_FragColor = vec4(0.0, 0.0, 0.0, a);
        }
        """)
        return shader
    }()

    /// Rolling fire from scrolling noise: a fireball or a burning sky.
    static let fire: SKShader = {
        let shader = SKShader(source: """
        float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
        float noise(vec2 p) {
            vec2 i = floor(p);
            vec2 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
        }
        void main() {
            vec2 uv = v_tex_coord;
            float n = noise(uv * 5.0 + vec2(0.0, -u_time * 2.2)) * 0.6 + noise(uv * 11.0 + vec2(u_time * 0.7, -u_time * 4.0)) * 0.4;
            float d = distance(uv, vec2(0.5, 0.42));
            float flame = smoothstep(0.52, 0.08, d + n * 0.3);
            vec3 color = mix(vec3(0.8, 0.05, 0.0), vec3(1.0, 0.5, 0.05), smoothstep(0.1, 0.5, flame));
            color = mix(color, vec3(1.0, 0.95, 0.6), smoothstep(0.6, 0.95, flame));
            gl_FragColor = vec4(color * flame, flame) * v_color_mix.a;
        }
        """)
        return shader
    }()

    /// A flickering glow, for lightning and the mouth of a howling wolf.
    static let pulse: SKShader = {
        let shader = SKShader(source: """
        void main() {
            float d = distance(v_tex_coord, vec2(0.5));
            float pulse = 0.65 + 0.35 * sin(u_time * 31.0) * sin(u_time * 7.0);
            float a = (1.0 - smoothstep(0.05, 0.5, d)) * pulse;
            gl_FragColor = vec4(v_color_mix.rgb * a, a) * v_color_mix.a;
        }
        """)
        return shader
    }()
}

// MARK: - Emitters

/// Particle systems configured in code.
@MainActor
enum Emitters {
    /// Sparks rising and flickering, like a fire's.
    static func embers(width: CGFloat, rate: CGFloat = 30, color: UIColor = Metal.ember) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.dot
        e.particleBirthRate = rate
        e.particleLifetime = 2.5
        e.particleLifetimeRange = 1.5
        e.particlePositionRange = CGVector(dx: width, dy: 20)
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = 0.6
        e.particleSpeed = 70
        e.particleSpeedRange = 50
        e.xAcceleration = 8
        e.particleScale = 0.05
        e.particleScaleRange = 0.03
        e.particleScaleSpeed = -0.01
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 0.8, 0], times: [0, 0.1, 0.6, 1])
        e.particleBlendMode = .add
        return e
    }

    /// Smoke drifting up and spreading.
    static func smoke(rate: CGFloat = 12, color: UIColor = Metal.ash, speed: CGFloat = 40, scale: CGFloat = 0.6) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = Textures.smoke
        e.particleBirthRate = rate
        e.particleLifetime = 2.5
        e.particleLifetimeRange = 1
        e.emissionAngle = .pi / 2
        e.emissionAngleRange = 0.8
        e.particleSpeed = speed
        e.particleSpeedRange = speed / 2
        e.particleScale = scale
        e.particleScaleRange = scale / 2
        e.particleScaleSpeed = scale * 0.5
        e.particleRotationRange = .pi
        e.particleRotationSpeed = 0.4
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 0.7, 0.4, 0], times: [0, 0.15, 0.6, 1])
        return e
    }

    /// One burst of `count` particles in every direction, falling under gravity.
    static func burst(count: Int, speed: CGFloat, color: UIColor, texture: SKTexture = Textures.dot, scale: CGFloat = 0.12, lifetime: CGFloat = 1.6, gravity: CGFloat = -260) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.numParticlesToEmit = count
        e.particleBirthRate = CGFloat(count) * 20
        e.particleLifetime = lifetime
        e.particleLifetimeRange = lifetime * 0.5
        e.emissionAngleRange = .pi * 2
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.6
        e.yAcceleration = gravity
        e.particleScale = scale
        e.particleScaleRange = scale * 0.5
        e.particleScaleSpeed = -scale * 0.4
        e.particleRotationRange = .pi * 2
        e.particleRotationSpeed = 3
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [1, 1, 0], times: [0, 0.6, 1])
        return e
    }

    /// Streaks falling from the top: rain, or snow with a soft dot.
    static func fall(width: CGFloat, height: CGFloat, rate: CGFloat, speed: CGFloat, texture: SKTexture, scale: CGFloat, color: UIColor, alpha: CGFloat = 0.6, angle: CGFloat = -.pi / 2) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleBirthRate = rate
        e.particleLifetime = (height / speed) * 1.3
        e.particlePositionRange = CGVector(dx: width * 1.3, dy: 0)
        e.emissionAngle = angle
        e.emissionAngleRange = 0.05
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.3
        e.particleScale = scale
        e.particleScaleRange = scale * 0.4
        e.particleRotation = angle + .pi / 2
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleAlpha = alpha
        e.particleAlphaRange = alpha * 0.4
        return e
    }

    /// Blood drops flung out, falling point first.
    static func drops(count: Int, speed: CGFloat, scale: CGFloat, lifetime: CGFloat) -> SKEmitterNode {
        let e = burst(count: count, speed: speed, color: .white, texture: Art.bloodDrop, scale: scale, lifetime: lifetime, gravity: -1100)
        e.particleColorBlendFactor = 0
        e.particleRotationSpeed = 0
        e.particleRotationRange = 0.6
        e.particleScaleSpeed = 0
        return e
    }

    /// Chunks thrown up that fall and tumble: turf, ice, bone.
    static func debris(count: Int, textures: [SKTexture], speed: CGFloat, scale: CGFloat, spread: CGFloat = 0.9) -> [SKEmitterNode] {
        textures.map { texture in
            let e = burst(count: count / textures.count, speed: speed, color: .white, texture: texture, scale: scale, lifetime: 2.2, gravity: -900)
            e.emissionAngle = .pi / 2
            e.emissionAngleRange = spread
            e.particleColorBlendFactor = 0
            e.particleScaleSpeed = 0
            e.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [1, 1, 0], times: [0, 0.85, 1])
            return e
        }
    }
}
