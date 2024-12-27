import Foundation

public protocol InterceptorProvider {
    func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [any Interceptor]

    func additionalErrorHandler<Request: Requestable>(for operation: HTTPOperation<Request>) -> ChainErrorHandler?
}

public extension InterceptorProvider {
    func additionalErrorHandler<Request: Requestable>(for operation: HTTPOperation<Request>) -> ChainErrorHandler? {
        nil
    }
}
