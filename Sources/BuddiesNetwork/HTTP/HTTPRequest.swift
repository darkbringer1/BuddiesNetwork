import Foundation

open class HTTPRequest<Request: Requestable> {
//    associatedtype Request: Requestable

    open var additionalHeaders: [String: String]
    public var rawRequest: Request

    public var requestName: String {
        String(describing: rawRequest.self)
    }

    public init(
        request: Request,
        additionalHeaders: [String: String]
    ) {
        rawRequest = request
        self.additionalHeaders = additionalHeaders
    }

    func toUrlRequest() throws -> URLRequest {
        var request = try rawRequest.toUrlRequest()

        for (fieldName, value) in additionalHeaders {
            request.addValue(value, forHTTPHeaderField: fieldName)
        }

        return request
    }

    open func addHeader(key: String, val: String) {
        additionalHeaders[key] = val
    }
}

public protocol Requestable: Encodable {
    associatedtype Data: Decodable

    func toUrlRequest() throws -> URLRequest
}
