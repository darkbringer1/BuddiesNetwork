import Foundation

open class HTTPResponse<Request: Requestable> {
    public var httpResponse: HTTPURLResponse
    public var rawData: Data
    public var parsedData: Request.Data?

    public init(
        httpResponse: HTTPURLResponse,
        rawData: Data
    ) {
        self.httpResponse = httpResponse
        self.rawData = rawData
    }
}
