import Foundation

open class TokenProviderInterceptor: Interceptor {
    enum TokenProviderError: Error, LocalizedError {
        case tokenNotFound

        var errorDescription: String? {
            switch self {
            case .tokenNotFound: "Token is not found."
            }
        }
    }

    public var id: String = UUID().uuidString

    var currentToken: () -> String?

    public init(currentToken: @escaping () -> String?) {
        self.currentToken = currentToken
    }

    open func intercept<Request>(
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
