import Observation
import UIKit

/// Opens links in other apps through the system. This is the only place the
/// app leaves itself; it makes no network calls of its own.
@MainActor
@Observable
final class LinkOpener {
    static let shared = LinkOpener()

    #if DEBUG
    /// `-debugLinkOpener opens|fails`: nothing is opened. The links are
    /// recorded and shown on the settlement screen, so that a UI test can check
    /// the exact link. With `fails` the Venmo app is "not installed": only
    /// web links open.
    enum Stub: String {
        case opens, fails
    }

    static let stubArgument = "debugLinkOpener"

    let stub: Stub?
    private(set) var recorded: [URL] = []

    init(stub: Stub? = UserDefaults.standard.string(forKey: LinkOpener.stubArgument).flatMap(Stub.init)) {
        self.stub = stub
    }
    #endif

    /// False when nothing could open the link, e.g. Venmo is not installed.
    func open(_ url: URL) async -> Bool {
        #if DEBUG
        if let stub {
            recorded.append(url)
            return stub == .opens || url.scheme == "https"
        }
        #endif
        return await UIApplication.shared.open(url)
    }
}
