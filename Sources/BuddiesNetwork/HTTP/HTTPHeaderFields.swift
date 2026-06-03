import Foundation

public enum HTTPHeaderFields: Sendable {
    case contentType
    case accept

    var value: (String, String) {
        switch self {
        case .contentType:
            ("Content-Type", "application/json; charset=utf-8")
        case .accept:
            ("accept", "application/json")
        }
    }
}
