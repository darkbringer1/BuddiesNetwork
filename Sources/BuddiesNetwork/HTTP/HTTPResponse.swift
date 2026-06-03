import Foundation

public struct HTTPResponse<Request: Requestable>: Sendable {
    public let httpResponse: HTTPURLResponse
    public let rawData: Data
    public var parsedData: Request.Data?

    public init(
        httpResponse: HTTPURLResponse,
        rawData: Data
    ) {
        self.httpResponse = httpResponse
        self.rawData = rawData
    }
}
