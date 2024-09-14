import Foundation

public extension URLRequest {
    var headers: HTTPHeaders {
        get { allHTTPHeaderFields.map(HTTPHeaders.init) ?? HTTPHeaders() }
        set { allHTTPHeaderFields = newValue.dictionary }
    }
}
