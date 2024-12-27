import Foundation

open class DefaultInterceptorProvider: InterceptorProvider {
    let client: URLSessionClient

    public init(client: URLSessionClient) {
        self.client = client
    }
    
    open func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [Interceptor] {
        [
            MaxRetryInterceptor(maxRetry: 3),
            NetworkFetchInterceptor(client: client),
            JSONDecodingInterceptor()
        ]
    }
}
