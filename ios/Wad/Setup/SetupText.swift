import Foundation

/// Dollars text to and from integer cents. No floating point is involved.
enum Money {
    /// Largest number of whole-dollar digits accepted.
    static let maxDollarDigits = 4

    /// Parses "7", "7.5", "7.50" or "$7.50" into cents. Returns nil for anything
    /// else, including negatives and more than two decimal places.
    static func cents(fromDollars text: String) -> Int? {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("$") { text.removeFirst() }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }

        let dollars = parts[0]
        guard (1...maxDollarDigits).contains(dollars.count), let whole = SetupText.digits(dollars) else { return nil }
        guard parts.count == 2 else { return whole * 100 }

        let fraction = parts[1]
        guard (1...2).contains(fraction.count), let part = SetupText.digits(fraction) else { return nil }
        return whole * 100 + (fraction.count == 1 ? part * 10 : part)
    }

    /// "7.00" for 700, "-13.50" for -1350.
    static func dollars(fromCents cents: Int) -> String {
        let magnitude = cents.magnitude
        let fraction = magnitude % 100
        return "\(cents < 0 ? "-" : "")\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}

/// Parsing for the numeric text fields of the setup flow.
enum SetupText {
    /// The value of a non-empty run of ASCII digits (at most 9 of them).
    static func digits(_ text: some StringProtocol) -> Int? {
        guard (1...9).contains(text.count), text.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return Int(text)
    }

    /// An unsigned number with at most one decimal place, e.g. "72" or "72.5".
    static func oneDecimal(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, (1...3).contains(parts[0].count), digits(parts[0]) != nil else {
            return nil
        }
        if parts.count == 2 {
            guard parts[1].count == 1, digits(parts[1]) != nil else { return nil }
        }
        return Double(parts.joined(separator: "."))
    }

    /// A handicap index, 54.0 at most. Golfers write a plus handicap (better than
    /// scratch) with a leading "+"; it is a negative number in the handicap math.
    static func handicapIndex(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        let isPlus = text.hasPrefix("+")
        guard let value = oneDecimal(isPlus ? String(text.dropFirst()) : text), value <= 54 else { return nil }
        return isPlus ? -value : value
    }

    /// A whole course handicap. "+3" and "-3" both mean a plus handicap of 3.
    static func courseHandicap(_ text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespaces)
        let isPlus = text.hasPrefix("+") || text.hasPrefix("-")
        let body = isPlus ? text.dropFirst() : text[...]
        guard (1...2).contains(body.count), let value = digits(body) else { return nil }
        return isPlus ? -value : value
    }

    /// Course handicap the way golfers write it: "+3" for a plus handicap.
    static func display(courseHandicap: Int) -> String {
        courseHandicap < 0 ? "+\(-courseHandicap)" : "\(courseHandicap)"
    }

    /// Handicap index the way golfers write it, with one decimal place.
    static func display(handicapIndex: Double) -> String {
        let tenths = Int((abs(handicapIndex) * 10).rounded())
        return "\(handicapIndex < 0 ? "+" : "")\(tenths / 10).\(tenths % 10)"
    }
}
