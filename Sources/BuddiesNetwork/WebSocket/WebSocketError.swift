import Foundation

public enum WebSocketError: LocalizedError, Equatable, Sendable {
    case connectionClosed(
        code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    )
    case messageBufferOverflow
    case unsupportedURLScheme(String?)
    case unsupportedMessage

    public var errorDescription: String? {
        switch self {
        case let .connectionClosed(code, reason):
            let reasonDescription = reason.flatMap {
                String(data: $0, encoding: .utf8)
            }

            if let reasonDescription {
                return "The WebSocket closed with code \(code.rawValue): \(reasonDescription)"
            }

            return "The WebSocket closed with code \(code.rawValue)."
        case .messageBufferOverflow:
            return "The WebSocket message buffer overflowed because messages arrived faster than they were consumed."
        case let .unsupportedURLScheme(scheme):
            return "WebSocket URLs must use ws or wss, not \(scheme ?? "a missing scheme")."
        case .unsupportedMessage:
            return "The server sent a WebSocket message type that is not supported."
        }
    }
}
