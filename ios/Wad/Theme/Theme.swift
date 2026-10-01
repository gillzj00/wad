import SwiftUI

/// The app's look: colors, type, spacing and corner radii. The colors are in
/// the asset catalog. Both appearances are dark: the light one is ash (lifted
/// charcoal) and the dark one is pitch (near black), and the text, blood and
/// ember colors read at 4.5:1 or better on every surface of both.
enum Theme {
    enum Palette {
        /// Behind the lists and cards.
        static let charcoal = Color("Charcoal")
        /// Cards and list rows.
        static let card = Color("Card")
        /// The lines of the scorecard and the outlines of the cards.
        static let rule = Color("Rule")
        /// Surfaces that stand out, such as the hole header and the payments.
        /// Text on it is `bone`, money on it is `ember`.
        static let maroon = Color("Maroon")
        /// Filled controls: the main button, selected chips, scored holes.
        /// Text on it is `bone`.
        static let crimson = Color("Crimson")
        /// The tint of the controls, warnings, debts and holes that need fixing.
        /// Bright enough to be text on `card` and `charcoal`.
        static let blood = Color("Blood")
        /// Money won and anything that burns: paid, final, settled.
        static let ember = Color("Ember")
        /// Text.
        static let bone = Color("Bone")
        /// Secondary text.
        static let ash = Color("Ash")

        /// Won is ember, owed is blood and even is quiet. The text says which
        /// it is as well ("Won", "Owes", "+", "-"); the color only supports it.
        static func money(cents: Int) -> Color {
            if cents > 0 { return ember }
            return cents < 0 ? blood : ash
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let chip: CGFloat = 10
        static let card: CGFloat = 16
    }

    enum Typography {
        /// Screen and empty-state titles: the heaviest serif the system has.
        static let display = Font.system(.title, design: .serif, weight: .black)
        /// Course names and the titles of cards.
        static let cardTitle = Font.system(.title3, design: .serif, weight: .bold)
        /// Small capitals above a value.
        static let overline = Font.system(.caption, design: .default, weight: .bold)
        /// Scores on the scoring screen.
        static let score = Font.system(.title, design: .rounded, weight: .black)
        /// Amounts that are the point of a row.
        static let money = Font.system(.title3, design: .rounded, weight: .black)
        /// The amount of a headline card.
        static let moneyLarge = Font.system(.largeTitle, design: .rounded, weight: .black)
    }
}
