import Foundation

public final class TokenProviderInterceptor: Interceptor {
    enum TokenProviderError: Error, LocalizedError {
        case tokenNotFound

        var errorDescription: String? {
            switch self {
            case .tokenNotFound: "Token is not found."
            }
        }
    }

    public let id: String = UUID().uuidString

    private let currentToken: @Sendable () -> String?

    public init(currentToken: @escaping @Sendable () -> String?) {
        self.currentToken = currentToken
    }

    public func intercept<Request>(
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        if let token = currentToken() {
            operation.addHeader(key: "Authorization", val: "Bearer \(token)")
        }

        chain.proceed(
            operation: operation,
            interceptor: self,
            response: response,
            completion: completion
        )
    }
}
