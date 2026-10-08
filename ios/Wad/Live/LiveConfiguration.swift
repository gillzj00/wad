import Foundation

/// The live relay's WebSocket URL and the shared `x-wad-client` token, from
/// the WAD_LIVE_URL and WAD_API_CLIENT_TOKEN entries of Info.plist, which
/// Config/Local.xcconfig sets. A nil URL means the build has no relay: the
/// app then says live sharing is not configured and never connects. The
/// token is a secret: it is sent in the header and never shown or logged.
struct LiveConfiguration: Sendable {
    static let urlKey = "WAD_LIVE_URL"
    static let clientTokenHeader = CourseLookupClient.clientTokenHeader

    var url: URL?
    var clientToken: String

    init(url: URL?, clientToken: String) {
        self.url = url
        self.clientToken = clientToken
    }

    init(info: [String: Any]) {
        let value = (info[Self.urlKey] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        url = value.isEmpty ? nil : URL(string: value)
        clientToken = (info[CourseLookupConfiguration.clientTokenKey] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var fromBundle: LiveConfiguration {
        LiveConfiguration(info: Bundle.main.infoDictionary ?? [:])
    }

    /// A build without the relay settings.
    static let unconfigured = LiveConfiguration(url: nil, clientToken: "")

    /// Nothing is offered without both the URL and the token.
    var isConfigured: Bool { url != nil && !clientToken.isEmpty }

    /// The headers of the connection: the token, without which the relay
    /// refuses the connection.
    var headers: [String: String] { [Self.clientTokenHeader: clientToken] }
}

/// The 6-character code a scoring phone shares and the following phones type.
enum LiveCode {
    /// No 0, O, 1 or I, which are read for each other.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 6

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    static func generate(using generator: inout some RandomNumberGenerator) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// What the relay accepts: `^[A-Z0-9]{6}$`.
    static func isValid(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { $0.isASCII && (("A"..."Z").contains($0) || ("0"..."9").contains($0)) }
    }

    /// Typed input as a code: uppercase, without spaces.
    static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { !$0.isWhitespace })
    }
}
