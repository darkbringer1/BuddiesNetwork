import Foundation

/// Production interceptor stack with retry, auth token injection, network fetch, status validation, and JSON decoding.
public final class AuthenticatedInterceptorProvider: InterceptorProvider {
    public let client: URLSessionClient
    public let currentToken: @Sendable () -> String?
    public let onUnauthorized: @MainActor @Sendable () async -> Void

    public init(
        client: URLSessionClient,
        accessToken: @escaping @Sendable () -> String?,
        onUnauthorized: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.client = client
        self.currentToken = accessToken
        self.onUnauthorized = onUnauthorized
    }

    public func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [any Interceptor] {
        [
            MaxRetryInterceptor(maxRetry: 3),
            TokenProviderInterceptor(currentToken: currentToken),
            NetworkFetchInterceptor(client: client),
            HTTPStatusCheckerInterceptor(),
            JSONDecodingInterceptor()
        ]
    }

    public func additionalErrorHandler<Request: Requestable>(for operation: HTTPOperation<Request>) -> (any ChainErrorHandler)? {
        AuthenticationErrorHandler(onUnauthorized: onUnauthorized)
    }
}
