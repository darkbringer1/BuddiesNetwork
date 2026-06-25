import Foundation

public enum ServerSentEventsError: LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case unacceptableStatusCode(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "The server sent an event stream that is not valid UTF-8."
        case let .unacceptableStatusCode(statusCode):
            "Unacceptable HTTP status code: \(statusCode)"
        }
    }
}
