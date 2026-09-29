import Foundation

/// Links that open Venmo with a payment or a request filled in. The user
/// confirms it in Venmo; the app moves no money (docs/adr/0007).
///
/// Venmo publishes no reference for these links. The format used here is the
/// one its app has registered for years and that is described in:
/// - https://blog.alexbeals.com/posts/venmo-deeplinking
///   (`venmo://paycharge?txn=pay&recipients=<handle>&amount=10&note=Note`,
///   `txn=charge` for a request)
/// - https://goleary.com/posts/2020-07-29-venmo-deeplinking-including-from-web-apps
///   (`https://venmo.com/<handle>?txn=<charge|pay>&note=<note>&amount=<amount>`)
/// Because it is undocumented it can change; the app then falls back to
/// marking the payment by hand.
enum VenmoLink {
    enum Kind: String, Sendable {
        /// The payer sends money: the recipient is the payee.
        case pay
        /// The payee asks for money: the recipient is the payer.
        case request

        /// Venmo's `txn` value.
        var transaction: String {
            switch self {
            case .pay: "pay"
            case .request: "charge"
            }
        }
    }

    static let maxCourseNameLength = 40

    /// Opens the Venmo app.
    static func appURL(kind: Kind, recipient: String, amountCents: Int, note: String) -> URL? {
        guard isLinkable(recipient: recipient, amountCents: amountCents) else { return nil }
        var components = URLComponents()
        components.scheme = "venmo"
        components.host = "paycharge"
        components.percentEncodedQueryItems = [
            item("txn", kind.transaction),
            item("recipients", recipient),
            item("amount", Money.dollars(fromCents: amountCents)),
            item("note", note),
        ]
        return components.url
    }

    /// Opens venmo.com, which hands over to the app when it is installed.
    static func webURL(kind: Kind, recipient: String, amountCents: Int, note: String) -> URL? {
        guard isLinkable(recipient: recipient, amountCents: amountCents) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "venmo.com"
        components.path = "/" + recipient
        components.percentEncodedQueryItems = [
            item("txn", kind.transaction),
            item("amount", Money.dollars(fromCents: amountCents)),
            item("note", note),
        ]
        return components.url
    }

    /// "Wad: Pebble Beach Sep 29". The date is the day the round started.
    static func note(courseName: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d"
        let name = courseName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCourseNameLength)
        return "Wad: \(name) \(formatter.string(from: date))"
    }

    private static func isLinkable(recipient: String, amountCents: Int) -> Bool {
        VenmoHandle.isValid(recipient) && amountCents > 0
    }

    /// Letters, digits and "-._~" stay; everything else is percent-encoded, so
    /// that "&", "+", "=" or a space in a note cannot change the query.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func item(_ name: String, _ value: String) -> URLQueryItem {
        URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")
    }
}
