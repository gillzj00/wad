import SwiftUI

/// The app's look: colors, type, spacing and corner radii. The colors are in
/// the asset catalog, each with a light and a dark variant.
enum Theme {
    enum Palette {
        /// The brand color and the tint of the controls.
        static let fairway = Color("Fairway")
        /// Surfaces that stand out, such as the hole header. Text on it is `onGreen`.
        static let deepGreen = Color("DeepGreen")
        /// Behind the lists and cards.
        static let sand = Color("Sand")
        /// Cards and list rows.
        static let card = Color("Card")
        /// Warnings, debts and the flag.
        static let flagRed = Color("FlagRed")
        /// Money won, on `card` and `sand`.
        static let gold = Color("Gold")
        /// Money on `deepGreen`.
        static let goldOnGreen = Color("GoldOnGreen")
        static let ink = Color("Ink")
        static let inkSecondary = Color("InkSecondary")
        /// The lines of the scorecard and the outlines of the cards.
        static let rule = Color("Rule")
        /// Text on `deepGreen`.
        static let onGreen = Color("OnGreen")
        /// Text on `fairway`.
        static let onFairway = Color("OnFairway")

        /// Won is gold, owed is red and even is quiet. The text says which it
        /// is as well ("Won", "Owes", "+", "-"); the color only supports it.
        static func money(cents: Int) -> Color {
            if cents > 0 { return gold }
            return cents < 0 ? flagRed : inkSecondary
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
        /// Screen and empty-state titles.
        static let display = Font.system(.title, design: .serif, weight: .bold)
        /// Course names and the titles of cards.
        static let cardTitle = Font.system(.title3, design: .serif, weight: .semibold)
        /// Small capitals above a value.
        static let overline = Font.system(.caption, design: .default, weight: .semibold)
        /// Scores on the scoring screen.
        static let score = Font.system(.title, design: .rounded, weight: .bold)
        /// Amounts that are the point of a row.
        static let money = Font.system(.title3, design: .rounded, weight: .bold)
        /// The amount of a headline card.
        static let moneyLarge = Font.system(.largeTitle, design: .rounded, weight: .bold)
    }
}
