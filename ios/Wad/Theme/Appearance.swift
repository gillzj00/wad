import SwiftUI
import UIKit

enum Appearance {
    /// The titles of the navigation bars in the serif design, in the ink color.
    @MainActor
    static func apply() {
        let ink = UIColor(named: "Ink") ?? .label
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: serif(.largeTitle, weight: .bold),
            .foregroundColor: ink,
        ]
        bar.titleTextAttributes = [
            .font: serif(.headline, weight: .semibold),
            .foregroundColor: ink,
        ]
    }

    /// The system's serif font in a text style, scaled with Dynamic Type.
    private static func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        let font = system.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? system
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    #if DEBUG
    /// `-debugColorScheme light|dark` shows the app in that color scheme
    /// whatever the simulator is set to. For the screenshots of the UI tests.
    static var debugColorScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: LaunchArgument.debugColorScheme) {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
    #endif
}
