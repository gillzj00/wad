import Foundation

/// WCAG 2 contrast, so that the tests can hold the palette to 4.5:1 for text
/// and money on every surface, in both appearances.
enum Contrast {
    /// sRGB components in 0...1.
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// Text at least this readable passes WCAG AA.
    static let minimumForText = 4.5

    /// The relative luminance, 0 for black and 1 for white.
    static func luminance(_ color: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// The contrast ratio, from 1 (the same color) to 21 (black on white).
    static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let lighter = max(luminance(a), luminance(b))
        let darker = min(luminance(a), luminance(b))
        return (lighter + 0.05) / (darker + 0.05)
    }
}
