import Foundation

/// Course search and course detail, from the API or a fake.
protocol CourseLookupService: Sendable {
    /// False when the app was built without the API settings; every call then
    /// throws `.notConfigured`.
    var isConfigured: Bool { get }
    func search(query: String) async throws -> [CourseSummary]
    func course(id: String) async throws -> Course
}

/// What went wrong with a lookup, with what to tell the group.
enum CourseLookupError: Error, Equatable, Sendable {
    /// The build has no base URL or client token.
    case notConfigured
    /// No connection, or the API could not be reached.
    case offline
    /// The server rejected the client token (401).
    case unauthorized
    /// 400 query_too_short.
    case queryTooShort
    /// 404 course_not_found.
    case notFound
    /// 503 course_provider_rate_limited, or 429 from the API's throttling.
    case rateLimited
    /// 502 course_provider_unavailable, any other failure, or a response that could not be read.
    case unavailable

    var message: String {
        switch self {
        case .notConfigured: "Course lookup is not configured. Enter the course by hand."
        case .offline: "You seem to be offline. Courses already looked up on this phone still work."
        case .unauthorized: "This build is not allowed to look up courses. Enter the course by hand."
        case .queryTooShort: "Type at least \(CourseSearchModel.minimumQueryLength) characters."
        case .notFound: "That course is no longer available."
        case .rateLimited: "Course lookup has hit its daily limit. Try again tomorrow, or enter the course by hand."
        case .unavailable: "Course lookup is not available right now. Try again later, or enter the course by hand."
        }
    }
}

/// The API's base URL and the shared `x-wad-client` token (docs/api.md,
/// "Deployment (dev)"), from the WAD_API_BASE_URL and WAD_API_CLIENT_TOKEN
/// entries of Info.plist, which Config/Local.xcconfig sets. The token is a
/// secret: it is sent in the header and never shown or logged.
struct CourseLookupConfiguration: Sendable {
    static let baseURLKey = "WAD_API_BASE_URL"
    static let clientTokenKey = "WAD_API_CLIENT_TOKEN"

    var baseURL: URL?
    var clientToken: String

    init(baseURL: URL?, clientToken: String) {
        self.baseURL = baseURL
        self.clientToken = clientToken
    }

    init(info: [String: Any]) {
        let base = (info[Self.baseURLKey] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        baseURL = base.isEmpty ? nil : URL(string: base)
        clientToken = (info[Self.clientTokenKey] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var fromBundle: CourseLookupConfiguration {
        CourseLookupConfiguration(info: Bundle.main.infoDictionary ?? [:])
    }

    var isConfigured: Bool { baseURL != nil && !clientToken.isEmpty }
}

/// The courses API over URLSession: `GET /v1/courses?q=` and `GET /v1/courses/{id}`.
struct CourseLookupClient: CourseLookupService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let clientTokenHeader = "x-wad-client"

    let configuration: CourseLookupConfiguration
    private let transport: Transport

    init(configuration: CourseLookupConfiguration, transport: Transport? = nil) {
        self.configuration = configuration
        self.transport = transport ?? { request in try await URLSession.shared.data(for: request) }
    }

    var isConfigured: Bool { configuration.isConfigured }

    func search(query: String) async throws -> [CourseSummary] {
        let response: CourseSearchResponse = try await get(path: "v1/courses", query: [URLQueryItem(name: "q", value: query)])
        return response.courses
    }

    func course(id: String) async throws -> Course {
        let response: CourseResponse = try await get(path: "v1/courses/\(id)", query: [])
        return response.course
    }

    /// The request for a route, so a test can see the URL and the header.
    func request(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard configuration.isConfigured, let baseURL = configuration.baseURL else { throw CourseLookupError.notConfigured }
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw CourseLookupError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(configuration.clientToken, forHTTPHeaderField: Self.clientTokenHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get<Body: Decodable>(path: String, query: [URLQueryItem]) async throws -> Body {
        let request = try request(path: path, query: query)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            throw CourseLookupError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw CourseLookupError.unavailable }
        guard http.statusCode == 200 else {
            throw Self.map(status: http.statusCode, body: data)
        }
        do {
            return try JSONDecoder().decode(Body.self, from: data)
        } catch {
            throw CourseLookupError.unavailable
        }
    }

    /// The API's error codes (docs/api.md), falling back on the status.
    static func map(status: Int, body: Data) -> CourseLookupError {
        let code = (try? JSONDecoder().decode(CourseErrorResponse.self, from: body))?.error.code
        switch (status, code) {
        case (401, _): return .unauthorized
        case (400, "query_too_short"): return .queryTooShort
        case (404, _): return .notFound
        case (429, _), (503, "course_provider_rate_limited"): return .rateLimited
        default: return .unavailable
        }
    }

    static func map(_ error: URLError) -> CourseLookupError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
            .offline
        default:
            .unavailable
        }
    }
}
