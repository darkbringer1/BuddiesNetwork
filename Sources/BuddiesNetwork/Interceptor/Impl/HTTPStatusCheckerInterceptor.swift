import Foundation

public final class HTTPStatusCheckerInterceptor: Interceptor {
    public enum HTTPStatusError: LocalizedError {
        case missingResponse
        case unacceptableStatusCode(Int)

        public var errorDescription: String? {
            switch self {
            case .missingResponse:
                "There is no HTTP response to validate."
            case .unacceptableStatusCode(let code):
                "Unacceptable HTTP status code: \(code)"
            }
        }
    }

    public var id: String = UUID().uuidString

    public let acceptableStatusCodes: Range<Int>

    public init(acceptableStatusCodes: Range<Int> = 200 ..< 300) {
        self.acceptableStatusCodes = acceptableStatusCodes
    }

    public func intercept<Request>(
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard let response else {
            chain.handleErrorAsync(
                HTTPStatusError.missingResponse,
                operation: operation,
                response: nil,
                completion: completion
            )
            return
        }

        let statusCode = response.httpResponse.statusCode
        if acceptableStatusCodes.contains(statusCode) {
            chain.proceed(
                operation: operation,
                interceptor: self,
                response: response,
                completion: completion
            )
        } else {
            chain.handleErrorAsync(
                HTTPStatusError.unacceptableStatusCode(statusCode),
                operation: operation,
                response: response,
                completion: completion
            )
        }
    }
}
