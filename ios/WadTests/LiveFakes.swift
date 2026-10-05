import Foundation
@testable import Wad

/// The relay as the tests script it: every connect hands out a connection
/// the test pushes frames into and drops, or fails as told.
final class FakeLiveTransport: LiveTransport, @unchecked Sendable {
    struct Request: Equatable {
        var url: URL
        var headers: [String: String]
    }

    private let lock = NSLock()
    private var storedConnections: [FakeLiveConnection] = []
    private var storedRequests: [Request] = []
    private var failures: [Error] = []

    var connections: [FakeLiveConnection] { lock.withLock { storedConnections } }
    var requests: [Request] { lock.withLock { storedRequests } }

    /// The next connects fail with these, in order, before any succeeds.
    func failNextConnects(with errors: [Error]) {
        lock.withLock { failures.append(contentsOf: errors) }
    }

    func connect(url: URL, headers: [String: String]) async throws -> any LiveConnection {
        let outcome: Result<FakeLiveConnection, Error> = lock.withLock {
            storedRequests.append(Request(url: url, headers: headers))
            if !failures.isEmpty {
                return .failure(failures.removeFirst())
            }
            let connection = FakeLiveConnection()
            storedConnections.append(connection)
            return .success(connection)
        }
        return try outcome.get()
    }
}

final class FakeLiveConnection: LiveConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSent: [String] = []
    private var closed = false
    private let stream: AsyncThrowingStream<String, Error>
    private let continuation: AsyncThrowingStream<String, Error>.Continuation

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }

    var sent: [String] { lock.withLock { storedSent } }
    var isClosed: Bool { lock.withLock { closed } }

    /// What was sent, decoded.
    var sentFrames: [LiveClientFrame] {
        sent.compactMap { try? JSONDecoder().decode(LiveClientFrame.self, from: Data($0.utf8)) }
    }

    func send(_ text: String) async throws {
        lock.withLock { storedSent.append(text) }
    }

    func frames() -> AsyncThrowingStream<String, Error> {
        stream
    }

    func close() {
        lock.withLock { closed = true }
        continuation.finish()
    }

    /// The relay sends a frame.
    func push(_ frame: LiveServerFrame) {
        push(try! String(data: JSONEncoder().encode(frame), encoding: .utf8)!)
    }

    func push(_ text: String) {
        continuation.yield(text)
    }

    /// The connection drops.
    func drop(_ error: Error = URLError(.networkConnectionLost)) {
        continuation.finish(throwing: error)
    }
}

/// Sleeps that end when the test says so, so the backoff and the pings are
/// checked without waiting.
final class FakeSleeper: @unchecked Sendable {
    private struct Pending {
        var id: Int
        var duration: Duration
        var continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var pending: [Pending] = []
    private var storedRequested: [Duration] = []
    private var nextID = 0

    /// Every duration asked for, in order.
    var requested: [Duration] { lock.withLock { storedRequested } }
    /// The sleeps still going, oldest first.
    var pendingDurations: [Duration] { lock.withLock { pending.map(\.duration) } }

    /// What the session is given in place of `Task.sleep`.
    var sleep: LiveSession.Sleep {
        { [self] duration in try await self.suspend(duration) }
    }

    /// Returns when the test fires it, or throws when the task is cancelled.
    func suspend(_ duration: Duration) async throws {
        let id = lock.withLock {
            nextID += 1
            storedRequested.append(duration)
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock { pending.append(Pending(id: id, duration: duration, continuation: continuation)) }
                if Task.isCancelled {
                    cancel(id)
                }
            }
        } onCancel: {
            cancel(id)
        }
    }

    private func cancel(_ id: Int) {
        let cancelled = lock.withLock { () -> Pending? in
            guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
            return pending.remove(at: index)
        }
        cancelled?.continuation.resume(throwing: CancellationError())
    }

    /// Ends the oldest sleep.
    func fire() {
        let fired = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
        fired?.continuation.resume()
    }
}

/// Waits for the session's tasks to get there, a few milliseconds at a time.
@MainActor
func eventually(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Settles what is in flight, to check that nothing more happens.
@MainActor
func settle() async {
    for _ in 0..<10 {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }
}
