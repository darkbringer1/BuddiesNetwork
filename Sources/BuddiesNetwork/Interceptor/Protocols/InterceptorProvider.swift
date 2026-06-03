import Foundation

public protocol InterceptorProvider: Sendable {
    func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [any Interceptor]

    func additionalErrorHandler<Request: Requestable>(for operation: HTTPOperation<Request>) -> (any ChainErrorHandler)?
}

public extension InterceptorProvider {
    func additionalErrorHandler<Request: Requestable>(for operation: HTTPOperation<Request>) -> (any ChainErrorHandler)? {
        nil
    }
}
