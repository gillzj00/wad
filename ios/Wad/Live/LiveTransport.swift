import Foundation

/// Opens WebSocket connections to the relay. `URLSessionLiveTransport` is
/// the real one; the tests use a fake that hands out scripted connections.
protocol LiveTransport: Sendable {
    /// Resolves once the handshake succeeded, or throws (a 401 without the
    /// token, no network).
    func connect(url: URL, headers: [String: String]) async throws -> any LiveConnection
}

/// One open connection: text frames out, text frames in until it closes.
protocol LiveConnection: Sendable {
    func send(_ text: String) async throws
    /// The incoming text frames. Ends when the connection closes and throws
    /// when it drops. Call it once.
    func frames() -> AsyncThrowingStream<String, Error>
    func close()
}

enum LiveTransportError: Error, Equatable {
    /// The handshake was refused: 401 without the token.
    case refused(status: Int?)
    case closed(code: Int)
}

/// `URLSessionWebSocketTask` behind the protocol. A session of its own per
/// connection, so that its delegate can report the handshake.
struct URLSessionLiveTransport: LiveTransport {
    var timeout: TimeInterval = 15

    func connect(url: URL, headers: [String: String]) async throws -> any LiveConnection {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let handshake = Handshake()
        let session = URLSession(configuration: .default, delegate: handshake, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        task.resume()
        do {
            try await handshake.opened()
        } catch {
            task.cancel(with: .abnormalClosure, reason: nil)
            session.invalidateAndCancel()
            throw error
        }
        return URLSessionLiveConnection(task: task, session: session)
    }

    /// Reports the handshake once: opened, or failed with the task's error.
    private final class Handshake: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var result: Result<Void, Error>?

        func opened() async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                defer { lock.unlock() }
                if let result {
                    continuation.resume(with: result)
                } else {
                    self.continuation = continuation
                }
            }
        }

        private func finish(_ result: Result<Void, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard self.result == nil else { return }
            self.result = result
            continuation?.resume(with: result)
            continuation = nil
        }

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
            finish(.success(()))
        }

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            finish(.failure(LiveTransportError.closed(code: closeCode.rawValue)))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let status = (task.response as? HTTPURLResponse)?.statusCode, status != 101 {
                finish(.failure(LiveTransportError.refused(status: status)))
            } else {
                finish(.failure(error ?? LiveTransportError.closed(code: URLSessionWebSocketTask.CloseCode.abnormalClosure.rawValue)))
            }
        }
    }
}

private struct URLSessionLiveConnection: LiveConnection {
    let task: URLSessionWebSocketTask
    let session: URLSession

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func frames() -> AsyncThrowingStream<String, Error> {
        let task = task
        return AsyncThrowingStream { continuation in
            let reader = Task {
                do {
                    while !Task.isCancelled {
                        switch try await task.receive() {
                        case .string(let text):
                            continuation.yield(text)
                        case .data(let data):
                            if let text = String(data: data, encoding: .utf8) {
                                continuation.yield(text)
                            }
                        @unknown default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
        session.finishTasksAndInvalidate()
    }
}
