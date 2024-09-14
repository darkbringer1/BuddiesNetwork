import Foundation

public protocol InterceptorProvider {
    func interceptors<Request: Requestable>(for request: Request) -> [any Interceptor]

    func additionalErrorHandler<Request: Requestable>(for request: Request) -> ChainErrorHandler?
}

public extension InterceptorProvider {
    func additionalErrorHandler(for request: some Requestable) -> ChainErrorHandler? {
        nil
    }
}
