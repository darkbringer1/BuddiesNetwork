import Foundation

/// The URLSession WebSocket operations used by ``WebSocketConnection``.
///
/// Conform a test double to this protocol to exercise socket behavior without
/// opening a real network connection.
public protocol WebSocketTaskProtocol: AnyObject, Cancellable {
    var closeCode: URLSessionWebSocketTask.CloseCode { get }
    var closeReason: Data? { get }
    var maximumMessageSize: Int { get set }

    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func sendPing(pongReceiveHandler: @escaping @Sendable ((any Error)?) -> Void)
    func cancel(
        with closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    )
}

extension URLSessionWebSocketTask: WebSocketTaskProtocol {}

/// Creates the URLSession task that backs a WebSocket connection.
public protocol WebSocketTaskProvider: Sendable {
    func webSocketTask(
        with request: URLRequest
    ) throws -> any WebSocketTaskProtocol
}

extension URLSessionClient: WebSocketTaskProvider {
    public func webSocketTask(
        with request: URLRequest
    ) throws -> any WebSocketTaskProtocol {
        guard let session else {
            throw URLSessionError.sessionInvalidated
        }

        return session.webSocketTask(with: request)
    }
}
