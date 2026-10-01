import SwiftUI
import UIKit

enum Appearance {
    /// The bars and the controls that SwiftUI leaves to UIKit, in the palette:
    /// both appearances are dark, so the system's light bars would glare.
    @MainActor
    static func apply() {
        let bone = UIColor(named: "Bone") ?? .label
        let ash = UIColor(named: "Ash") ?? .secondaryLabel
        let charcoal = UIColor(named: "Charcoal") ?? .systemBackground
        let rule = UIColor(named: "Rule") ?? .separator
        let crimson = UIColor(named: "Crimson") ?? .systemRed
        let blood = UIColor(named: "Blood") ?? .systemRed

        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: serif(.largeTitle, weight: .black),
            .foregroundColor: bone,
        ]
        bar.titleTextAttributes = [
            .font: serif(.headline, weight: .bold),
            .foregroundColor: bone,
        ]

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = charcoal
        tabs.shadowColor = rule
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = ash
            item.normal.titleTextAttributes = [.foregroundColor: ash]
            item.selected.iconColor = blood
            item.selected.titleTextAttributes = [.foregroundColor: blood]
        }
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabs
        tabBar.scrollEdgeAppearance = tabs

        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = charcoal
        segmented.selectedSegmentTintColor = crimson
        segmented.setTitleTextAttributes([.foregroundColor: bone], for: .normal)
        segmented.setTitleTextAttributes([.foregroundColor: bone], for: .selected)

        UITextField.appearance().keyboardAppearance = .dark
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
