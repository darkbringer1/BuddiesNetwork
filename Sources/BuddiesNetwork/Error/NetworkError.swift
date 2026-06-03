import Foundation

public enum NetworkError: String, LocalizedError, Sendable {
    case decodingFailed = "Problem occured during decoding."
    case encodingFailed = "Parameter encoding failed."
    case missingURL = "URL is nil."
    case tokenExpired = "Your session is expired. Please sign in again."

    public var errorDescription: String? {
        rawValue
    }
}
