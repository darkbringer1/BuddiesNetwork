import Foundation

/// Production interceptor stack with retry, auth token injection, network fetch, status validation, and JSON decoding.
open class AuthenticatedInterceptorProvider: InterceptorProvider {
    public let client: URLSessionClient
    public var currentToken: () -> String?
    public let onUnauthorized: @Sendable () async -> Void

    public init(
        client: URLSessionClient,
        accessToken: @escaping () -> String?,
        onUnauthorized: @escaping @Sendable () async -> Void = {}
    ) {
        self.client = client
        self.currentToken = accessToken
        self.onUnauthorized = onUnauthorized
    }

    open func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [Interceptor] {
        [
            MaxRetryInterceptor(maxRetry: 3),
            TokenProviderInterceptor(currentToken: currentToken),
            NetworkFetchInterceptor(client: client),
            HTTPStatusCheckerInterceptor(),
            JSONDecodingInterceptor()
        ]
    }

    open func additionalErrorHandler<Request: Requestable>(for operation: HTTPOperation<Request>) -> ChainErrorHandler? {
        AuthenticationErrorHandler(onUnauthorized: onUnauthorized)
    }
}
