import Foundation

struct MapRequestable: Requestable {
    
    let id: String
    
    struct Data: Decodable { }
    
    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: URL(string: "https://api.example.com/v1/request")!,
            httpMethod: .get,
            additionalHeaders: [:],
            data: self
        )
    }
}


open class HTTPOperation<Request: Requestable> {
    
    public struct HTTPProperties {
        let url: URL
        let httpMethod: HTTPMethod
        var additionalHeaders: [String: String]
        let data: (any Encodable)?
        
        public var requestName: String {
            String(describing: Request.self)
        }
        
        public init(url: URL, httpMethod: HTTPMethod, additionalHeaders: [String : String] = [:], data: (any Encodable)? = nil) {
            self.url = url
            self.httpMethod = httpMethod
            self.additionalHeaders = additionalHeaders
            self.data = data
        }
    }
    
    public var rawRequest: Request
    public var properties: HTTPProperties
    public let cachePolicy: CachePolicy
    
    public init(
        request: Request,
        cachePolicy: CachePolicy
    ) {
        self.rawRequest = request
        self.properties = request.httpProperties()
        self.cachePolicy = cachePolicy
    }
    
//    func toUrlRequest() throws -> URLRequest {
//        var request = try rawRequest.toUrlRequest()
//        
//        for (fieldName, value) in properties.additionalHeaders {
//            request.addValue(value, forHTTPHeaderField: fieldName)
//        }
//        
//        return request
//    }

    public func addHeader(key: String, val: String) {
        properties.additionalHeaders[key] = val
    }
}
//
//open class HTTPRequest<Request: Requestable> {
////    associatedtype Request: Requestable
//
//    open var additionalHeaders: [String: String]
//    public var rawRequest: Request
//    public var cachePolicy: CachePolicy
//    
//    public var requestName: String {
//        String(describing: rawRequest.self)
//    }
//
//    public init(
//        request: Request,
//        cachePolicy: CachePolicy,
//        additionalHeaders: [String: String]
//    ) {
//        rawRequest = request
//        self.cachePolicy = cachePolicy
//        self.additionalHeaders = additionalHeaders
//    }
//
//    func toUrlRequest() throws -> URLRequest {
//        var request = try rawRequest.toUrlRequest()
//
//        for (fieldName, value) in additionalHeaders {
//            request.addValue(value, forHTTPHeaderField: fieldName)
//        }
//
//        return request
//    }
//
//    open func addHeader(key: String, val: String) {
//        additionalHeaders[key] = val
//    }
//}

public protocol Requestable: Encodable {
    associatedtype Data: Decodable

//    func toUrlRequest() throws -> URLRequest
    func httpProperties() -> HTTPOperation<Self>.HTTPProperties
    
}
