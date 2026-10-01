import Testing
import UIKit
@testable import Wad

/// The palette in the asset catalog reads: text and money reach 4.5:1 on the
/// surfaces they are put on, in the light appearance and the dark one.
struct PaletteContrastTests {
    @Test func blackOnWhiteIsTheMaximum() {
        let black = Contrast.RGB(red: 0, green: 0, blue: 0)
        let white = Contrast.RGB(red: 1, green: 1, blue: 1)
        #expect(Contrast.ratio(black, white) == 21)
        #expect(Contrast.ratio(white, black) == 21)
        #expect(Contrast.ratio(white, white) == 1)
    }

    @Test func luminanceFollowsTheSRGBCurve() {
        let gray = Contrast.RGB(red: 0.5, green: 0.5, blue: 0.5)
        #expect(abs(Contrast.luminance(gray) - 0.2140) < 0.001)
        let red = Contrast.RGB(red: 1, green: 0, blue: 0)
        #expect(abs(Contrast.luminance(red) - 0.2126) < 0.0001)
    }

    /// Foreground on background, as the views combine them.
    static let pairs: [(text: String, surface: String)] = [
        ("Bone", "Charcoal"), ("Bone", "Card"), ("Bone", "Maroon"), ("Bone", "Crimson"),
        ("Ash", "Charcoal"), ("Ash", "Card"),
        ("Blood", "Charcoal"), ("Blood", "Card"), ("Blood", "Maroon"),
        ("Ember", "Charcoal"), ("Ember", "Card"), ("Ember", "Maroon"),
        ("Charcoal", "Blood"),
        ("AccentColor", "Card"),
    ]

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func textAndMoneyReadOnEverySurface(style: UIUserInterfaceStyle) throws {
        for pair in Self.pairs {
            let ratio = Contrast.ratio(try color(pair.text, style), try color(pair.surface, style))
            #expect(
                ratio >= Contrast.minimumForText,
                "\(pair.text) on \(pair.surface) is \(ratio) in \(style == .dark ? "dark" : "light")"
            )
        }
    }

    private func color(_ name: String, _ style: UIUserInterfaceStyle) throws -> Contrast.RGB {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let color = try #require(UIColor(named: name, in: Bundle(for: Round.self), compatibleWith: traits))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #expect(color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(alpha == 1, "\(name) is translucent")
        return Contrast.RGB(red: red, green: green, blue: blue)
    }
}
