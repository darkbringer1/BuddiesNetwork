import Foundation

/// A complete text or binary WebSocket message.
public enum WebSocketMessage: Equatable, Sendable {
    case text(String)
    case data(Data)

    init(_ message: URLSessionWebSocketTask.Message) throws {
        switch message {
        case let .string(text):
            self = .text(text)
        case let .data(data):
            self = .data(data)
        @unknown default:
            throw WebSocketError.unsupportedMessage
        }
    }

    var urlSessionMessage: URLSessionWebSocketTask.Message {
        switch self {
        case let .text(text):
            .string(text)
        case let .data(data):
            .data(data)
        }
    }
}
