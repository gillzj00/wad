import Foundation

/// A Venmo username as typed by the group. The rule is the one of the backend
/// profile API (backend/src/services/profile/validation.ts): 5 to 30 letters,
/// digits, hyphens or underscores, stored without the "@". It is not checked
/// against Venmo.
enum VenmoHandle {
    static let lengthRange = 5...30

    enum Parsed: Equatable, Sendable {
        /// Nothing was typed: the player has no handle.
        case none
        case valid(String)
        case invalid
    }

    static let rule = "A Venmo handle is 5 to 30 letters, digits, hyphens or underscores."

    /// Trims spaces and strips one leading "@".
    static func parse(_ text: String) -> Parsed {
        var handle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if handle.isEmpty { return .none }
        if handle.hasPrefix("@") { handle.removeFirst() }
        return isValid(handle) ? .valid(handle) : .invalid
    }

    /// The handle to store, nil for none or an invalid one.
    static func normalized(_ text: String) -> String? {
        guard case .valid(let handle) = parse(text) else { return nil }
        return handle
    }

    static func isValid(_ handle: String) -> Bool {
        lengthRange.contains(handle.unicodeScalars.count) && handle.unicodeScalars.allSatisfy(isAllowed)
    }

    static func display(_ handle: String) -> String {
        "@" + handle
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "-", "_": true
        default: false
        }
    }
}
