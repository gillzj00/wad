import CoreLocation
import Foundation

/// One position of the phone, used only to rank the cached courses by
/// distance. It is never logged, stored or sent anywhere.
struct LocationFix: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

enum LocationError: Error, Equatable {
    /// The group has not allowed the app to use the location.
    case denied
    /// No fix came in time.
    case unavailable
}

protocol LocationProvider: Sendable {
    /// Asks for When In Use permission if it has not been decided, then waits for one fix.
    func currentFix() async throws -> LocationFix
}

/// CoreLocation's update stream, which asks for permission itself.
struct CoreLocationProvider: LocationProvider {
    var timeout: Duration = .seconds(15)

    func currentFix() async throws -> LocationFix {
        let timeout = timeout
        return try await withThrowingTaskGroup(of: LocationFix.self) { group in
            group.addTask { try await Self.firstFix() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocationError.unavailable
            }
            defer { group.cancelAll() }
            guard let fix = try await group.next() else { throw LocationError.unavailable }
            return fix
        }
    }

    private static func firstFix() async throws -> LocationFix {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return LocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
            if #available(iOS 18, *),
               update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw LocationError.denied
            }
        }
        throw LocationError.unavailable
    }
}
