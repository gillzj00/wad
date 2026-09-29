#!/usr/bin/env swift
// Draws the app icon: a red flag with a W on a putting green, with a ball
// beside the hole. Writes the 1024 x 1024 PNGs of AppIcon.appiconset (light,
// dark and tinted), opaque and without an alpha channel.
// Usage: swift ios/scripts/make-app-icon.swift

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Palette {
    var skyTop: CGColor
    var skyBottom: CGColor
    var fringe: CGColor
    var green: CGColor
    var greenLight: CGColor
    var hole: CGColor
    var stick: CGColor
    var flag: CGColor
    var flagShade: CGColor
    var letter: CGColor
    var ball: CGColor
    var ballShade: CGColor
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func gray(_ white: CGFloat) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: 1)
}

let light = Palette(
    skyTop: rgb(0x0F3A26), skyBottom: rgb(0x1B6E42),
    fringe: rgb(0x2C8A55), green: rgb(0x45A86B), greenLight: rgb(0x58BB7D),
    hole: rgb(0x0B2A1B), stick: rgb(0xFFF9EA),
    flag: rgb(0xD2382F), flagShade: rgb(0xA8261F), letter: rgb(0xFFF9EA),
    ball: rgb(0xFFFFFF), ballShade: rgb(0xD9DED9)
)

let dark = Palette(
    skyTop: rgb(0x070C09), skyBottom: rgb(0x12241A),
    fringe: rgb(0x16402A), green: rgb(0x1F5A3A), greenLight: rgb(0x287049),
    hole: rgb(0x050A07), stick: rgb(0xF1EEE4),
    flag: rgb(0xE5554B), flagShade: rgb(0xB83A32), letter: rgb(0xFFF9EA),
    ball: rgb(0xF4F4F0), ballShade: rgb(0xB9C0BA)
)

// The system tints a grayscale image.
let tinted = Palette(
    skyTop: gray(0), skyBottom: gray(0.08),
    fringe: gray(0.2), green: gray(0.3), greenLight: gray(0.38),
    hole: gray(0.04), stick: gray(0.95),
    flag: gray(0.8), flagShade: gray(0.62), letter: gray(0.1),
    ball: gray(1), ballShade: gray(0.7)
)

func draw(_ palette: Palette, to url: URL) throws {
    let size = 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    // The origin at the top left, like on screen.
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)

    // Background.
    let gradient = CGGradient(
        colorsSpace: space, colors: [palette.skyTop, palette.skyBottom] as CFArray, locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Fringe and green, running off the bottom of the icon.
    context.setFillColor(palette.fringe)
    context.fillEllipse(in: CGRect(x: -190, y: 560, width: 1404, height: 760))
    context.setFillColor(palette.green)
    context.fillEllipse(in: CGRect(x: -130, y: 600, width: 1284, height: 720))
    context.setFillColor(palette.greenLight)
    context.fillEllipse(in: CGRect(x: -40, y: 660, width: 1104, height: 640))

    // The hole.
    let hole = CGPoint(x: 400, y: 800)
    context.setFillColor(palette.hole)
    context.fillEllipse(in: CGRect(x: hole.x - 92, y: hole.y - 30, width: 184, height: 60))

    // The flag: a rectangle that waves a little, with a shaded fold.
    let stickWidth: CGFloat = 30
    let top: CGFloat = 150
    let flagLeft = hole.x + stickWidth / 2 - 2
    let flagRight: CGFloat = 860
    let flagTop = top + 18
    let flagBottom: CGFloat = 520
    let flag = CGMutablePath()
    flag.move(to: CGPoint(x: flagLeft, y: flagTop))
    flag.addCurve(
        to: CGPoint(x: flagRight, y: flagTop + 34),
        control1: CGPoint(x: flagLeft + 150, y: flagTop - 44),
        control2: CGPoint(x: flagRight - 150, y: flagTop + 78)
    )
    flag.addLine(to: CGPoint(x: flagRight, y: flagBottom + 34))
    flag.addCurve(
        to: CGPoint(x: flagLeft, y: flagBottom),
        control1: CGPoint(x: flagRight - 150, y: flagBottom + 78),
        control2: CGPoint(x: flagLeft + 150, y: flagBottom - 44)
    )
    flag.closeSubpath()
    context.addPath(flag)
    context.setFillColor(palette.flag)
    context.fillPath()

    context.saveGState()
    context.addPath(flag)
    context.clip()
    context.setFillColor(palette.flagShade)
    context.fill(CGRect(x: flagRight - 70, y: 0, width: 200, height: 1024))
    context.restoreGState()

    // The W on the flag.
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 300, nil)!
    let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: palette.letter]
    let line = CTLineCreateWithAttributedString(
        CFAttributedStringCreate(nil, "W" as CFString, attributes as CFDictionary)!
    )
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let center = CGPoint(x: (flagLeft + flagRight - 70) / 2 + 6, y: (flagTop + flagBottom) / 2 + 14)
    context.saveGState()
    // Text is drawn with the origin at the bottom left.
    context.translateBy(x: center.x, y: center.y)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
    CTLineDraw(line, context)
    context.restoreGState()

    // The flagstick, in front of the flag's edge.
    context.setFillColor(palette.stick)
    let stick = CGPath(
        roundedRect: CGRect(x: hole.x - stickWidth / 2, y: top, width: stickWidth, height: hole.y - top),
        cornerWidth: stickWidth / 2, cornerHeight: stickWidth / 2, transform: nil
    )
    context.addPath(stick)
    context.fillPath()
    context.fillEllipse(in: CGRect(x: hole.x - 26, y: top - 30, width: 52, height: 52))

    // The ball.
    let ball = CGRect(x: 650, y: 770, width: 130, height: 130)
    context.setFillColor(palette.ballShade)
    context.fillEllipse(in: ball)
    context.setFillColor(palette.ball)
    context.fillEllipse(in: ball.insetBy(dx: 9, dy: 9).offsetBy(dx: -7, dy: -7))

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

for (name, palette) in [("AppIcon.png", light), ("AppIcon-dark.png", dark), ("AppIcon-tinted.png", tinted)] {
    let url = iconSet.appendingPathComponent(name)
    try draw(palette, to: url)
    print("Wrote \(url.path)")
}
