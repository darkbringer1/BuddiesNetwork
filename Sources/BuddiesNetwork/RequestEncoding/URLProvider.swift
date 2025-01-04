import Foundation

public enum URLProvider {
    
    public static func urlRequest<Request: Requestable>(from properties: HTTPOperation<Request>.HTTPProperties) throws -> URLRequest {
        try returnUrlRequest(
            method: properties.httpMethod,
            url: properties.url,
            data: properties.data,
            additionalHeaders: properties.additionalHeaders
        )
    }
    
    public static func returnUrlRequest(
        method: HTTPMethod = .get,
        url: URL,
        data: (any Encodable)?,
        additionalHeaders: [String: String]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.headers = headers(additionalHeaders)
        
        try configureEncoding(
            method: method,
            data: data,
            request: &request
        )

        return request
    }

    public static func returnUrlRequest(
        method: HTTPMethod = .get,
        url: URL
    ) throws -> URLRequest {
        try returnUrlRequest(
            method: method,
            url: url,
            data: EmptyEncodable()
        )
    }

    private static func configureEncoding(
        method: HTTPMethod,
        data: (any Encodable)?,
        request: inout URLRequest
    ) throws {
        let params = data?.asDictionary()

        switch method {
        case .post, .put:
            try ParameterEncoding.jsonEncoding.encode(urlRequest: &request, parameters: params)
        case .get:
            try ParameterEncoding.urlEncoding.encode(urlRequest: &request, parameters: params)
        default:
            try ParameterEncoding.urlEncoding.encode(urlRequest: &request, parameters: params)
        }
    }

    private static func headers(_ appendingHeaders: [String: String]?) -> HTTPHeaders {
        var httpHeaders = HTTPHeaders()

        httpHeaders.add(
            HTTPHeader(
                name: HTTPHeaderFields.accept.value.0,
                value: HTTPHeaderFields.accept.value.1
            )
        )
        if let headers = appendingHeaders {
            for (fieldName, value) in headers {
                httpHeaders.add(
                    HTTPHeader(
                        name: fieldName,
                        value: value
                    )
                )
            }
        }
        return httpHeaders
    }
}

public struct EmptyEncodable: Encodable {}
