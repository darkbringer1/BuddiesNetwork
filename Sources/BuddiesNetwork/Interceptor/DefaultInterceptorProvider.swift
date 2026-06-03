import Foundation

public final class DefaultInterceptorProvider: InterceptorProvider {
    private let client: URLSessionClient

    public init(client: URLSessionClient) {
        self.client = client
    }
    
    public func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [any Interceptor] {
        [
            MaxRetryInterceptor(maxRetry: 3),
            NetworkFetchInterceptor(client: client),
            JSONDecodingInterceptor()
        ]
    }
}
