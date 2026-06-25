import Foundation

public struct ServerSentEvent: Decodable, Equatable, Sendable {
    public let id: String?
    public let event: String?
    public let data: String
    public let retry: Int?

    public init(
        id: String? = nil,
        event: String? = nil,
        data: String,
        retry: Int? = nil
    ) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
    }
}
