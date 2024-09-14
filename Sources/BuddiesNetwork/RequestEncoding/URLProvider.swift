import Foundation

public enum URLProvider {
    public static func returnUrlRequest(
        method: HTTPMethod = .get,
        url: URL,
        data: (some Encodable)?
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.headers = headers()

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
        data: (some Encodable)?,
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

    private static func headers() -> HTTPHeaders {
        var httpHeaders = HTTPHeaders()

        httpHeaders.add(
            HTTPHeader(
                name: HTTPHeaderFields.accept.value.0,
                value: HTTPHeaderFields.accept.value.1
            )
        )
        return httpHeaders
    }
}

public struct EmptyEncodable: Encodable {}
