#!/usr/bin/env swift
// Draws the app icon: a skull over two crossed flagsticks, in flames. Writes
// the 1024 x 1024 PNGs of AppIcon.appiconset: the light one on black and
// opaque, the dark one on a transparent background (the system puts its own
// behind it) and the tinted one in grays on a transparent background (the
// system tints it).
// Usage: swift ios/scripts/make-app-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Palette {
    /// Nil for a transparent background.
    var background: CGColor?
    var glow: CGColor
    var flame: CGColor
    var flameCore: CGColor
    var stick: CGColor
    var flag: CGColor
    var bone: CGColor
    var hollow: CGColor
    var ember: CGColor
}

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gray(_ white: CGFloat, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

let colors = Palette(
    background: rgb(0x0A0909),
    glow: rgb(0xFF8324, alpha: 0.55),
    flame: rgb(0xB5131F), flameCore: rgb(0xFF8C2E),
    stick: rgb(0xEFE8DC), flag: rgb(0xFF353E),
    bone: rgb(0xEFE8DC), hollow: rgb(0x0A0909), ember: rgb(0xFF8C2E)
)

let dark = Palette(
    background: nil,
    glow: colors.glow, flame: colors.flame, flameCore: colors.flameCore,
    stick: colors.stick, flag: colors.flag,
    bone: colors.bone, hollow: colors.hollow, ember: colors.ember
)

// Grays on transparent: the system tints the image.
let tinted = Palette(
    background: nil,
    glow: gray(0.5, alpha: 0.4),
    flame: gray(0.45), flameCore: gray(0.7),
    stick: gray(0.9), flag: gray(0.6),
    bone: gray(0.95), hollow: gray(0.05), ember: gray(0.85)
)

let size: CGFloat = 1024

/// The drawing is laid out on a unit square around the skull's center.
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: (x - 0.5) * 1000 + size / 2, y: (y - 0.45) * 1000 + size / 2)
}

func flame(x: CGFloat, width: CGFloat, tip: CGFloat, base: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: p(x - width / 2, base))
    path.addCurve(
        to: p(x + width * 0.1, tip),
        control1: p(x - width / 2, base - (base - tip) * 0.5),
        control2: p(x - width * 0.3, tip + (base - tip) * 0.25)
    )
    path.addCurve(
        to: p(x + width / 2, base),
        control1: p(x + width * 0.45, tip + (base - tip) * 0.3),
        control2: p(x + width / 2, base - (base - tip) * 0.4)
    )
    path.closeSubpath()
    return path
}

func draw(_ palette: Palette, to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha: CGImageAlphaInfo = palette.background == nil ? .premultipliedLast : .noneSkipLast
    guard let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: alpha.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    // The origin at the top left, like on screen.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)

    if let background = palette.background {
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // The ember glow behind everything.
    let glow = CGGradient(
        colorsSpace: space,
        colors: [palette.glow, palette.glow.copy(alpha: 0)!] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow, startCenter: p(0.5, 0.8), startRadius: 0, endCenter: p(0.5, 0.8), endRadius: 560, options: []
    )

    // The flagsticks, crossed like bones, with their flags up.
    for sign in [CGFloat(-1), 1] {
        let bottom = p(0.5 + sign * 0.46, 0.98)
        let top = p(0.5 - sign * 0.38, 0.03)
        context.setLineCap(.round)
        context.setStrokeColor(palette.hollow)
        context.setLineWidth(40)
        context.move(to: bottom)
        context.addLine(to: top)
        context.strokePath()
        context.setStrokeColor(palette.stick)
        context.setLineWidth(28)
        context.move(to: bottom)
        context.addLine(to: top)
        context.strokePath()

        context.move(to: top)
        context.addLine(to: CGPoint(x: top.x - sign * 210, y: top.y + 75))
        context.addLine(to: CGPoint(x: top.x, y: top.y + 160))
        context.closePath()
        context.setFillColor(palette.flag)
        context.fillPath()
    }

    // Flames, rising behind the jaw.
    let tongues: [(x: CGFloat, w: CGFloat, tip: CGFloat)] = [
        (0.2, 0.16, 0.5), (0.35, 0.18, 0.36), (0.5, 0.22, 0.28), (0.65, 0.18, 0.38), (0.8, 0.16, 0.53),
    ]
    for (x, w, tip) in tongues {
        context.addPath(flame(x: x, width: w, tip: tip, base: 1.1))
        context.setFillColor(palette.flame)
        context.fillPath()
        context.addPath(flame(x: x, width: w * 0.5, tip: tip + 0.2, base: 1.1))
        context.setFillColor(palette.flameCore)
        context.fillPath()
    }

    // The skull: cranium, cheekbones and jaw in one outline.
    let skull = CGMutablePath()
    skull.move(to: p(0.5, 0.1))
    skull.addCurve(to: p(0.78, 0.42), control1: p(0.7, 0.1), control2: p(0.78, 0.26))
    skull.addCurve(to: p(0.66, 0.58), control1: p(0.78, 0.5), control2: p(0.72, 0.56))
    skull.addCurve(to: p(0.6, 0.76), control1: p(0.63, 0.62), control2: p(0.63, 0.72))
    skull.addCurve(to: p(0.4, 0.76), control1: p(0.56, 0.82), control2: p(0.44, 0.82))
    skull.addCurve(to: p(0.34, 0.58), control1: p(0.37, 0.72), control2: p(0.37, 0.62))
    skull.addCurve(to: p(0.22, 0.42), control1: p(0.28, 0.56), control2: p(0.22, 0.5))
    skull.addCurve(to: p(0.5, 0.1), control1: p(0.22, 0.26), control2: p(0.3, 0.1))
    skull.closeSubpath()
    context.addPath(skull)
    context.setStrokeColor(palette.hollow)
    context.setLineWidth(24)
    context.strokePath()
    context.addPath(skull)
    context.setFillColor(palette.bone)
    context.fillPath()

    // Eye sockets with an ember in each.
    for sign in [CGFloat(-1), 1] {
        context.setFillColor(palette.hollow)
        context.fillEllipse(in: CGRect(origin: p(0.5 + sign * 0.1 - 0.08, 0.37), size: CGSize(width: 150, height: 150)))
        let ember = CGRect(origin: p(0.5 + sign * 0.1 - 0.03, 0.44), size: CGSize(width: 60, height: 60))
        context.setFillColor(palette.ember.copy(alpha: 0.35)!)
        context.fillEllipse(in: ember.insetBy(dx: -20, dy: -20))
        context.setFillColor(palette.ember)
        context.fillEllipse(in: ember)
    }

    // The nose.
    context.move(to: p(0.5, 0.5))
    context.addLine(to: p(0.465, 0.59))
    context.addQuadCurve(to: p(0.535, 0.59), control: p(0.5, 0.63))
    context.closePath()
    context.setFillColor(palette.hollow)
    context.fillPath()

    // Teeth: the gaps between them.
    context.setStrokeColor(palette.hollow)
    context.setLineWidth(8)
    context.addPath(CGPath(
        roundedRect: CGRect(origin: p(0.38, 0.64), size: CGSize(width: 240, height: 110)),
        cornerWidth: 12, cornerHeight: 12, transform: nil
    ))
    context.strokePath()
    for gap in 1...5 {
        let x = 0.38 + 0.24 * CGFloat(gap) / 6
        context.move(to: p(x, 0.64))
        context.addLine(to: p(x, 0.75))
        context.strokePath()
    }
    context.setLineWidth(10)
    context.move(to: p(0.38, 0.695))
    context.addLine(to: p(0.62, 0.695))
    context.strokePath()

    // A crack across the cranium.
    context.setLineWidth(8)
    context.setLineJoin(.round)
    context.move(to: p(0.58, 0.12))
    context.addLine(to: p(0.62, 0.2))
    context.addLine(to: p(0.58, 0.25))
    context.addLine(to: p(0.63, 0.33))
    context.strokePath()

    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let script = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let iconSet = script
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Wad/Assets.xcassets/AppIcon.appiconset")

for (name, palette) in [("AppIcon.png", colors), ("AppIcon-dark.png", dark), ("AppIcon-tinted.png", tinted)] {
    let url = iconSet.appendingPathComponent(name)
    try draw(palette, to: url)
    print("Wrote \(url.path)")
}
