import Foundation

public protocol NetworkTransportProtocol: Sendable {
    func send<Request: Requestable>(
        request: Request,
        cachePolicy: CachePolicy,
        dispatchQueue: DispatchQueue,
        completion: @escaping HTTPResultHandler<Request>
    ) -> (any Cancellable)?
}

public final class DefaultRequestChainNetworkTransport: NetworkTransportProtocol {
    let interceptorProvider: any InterceptorProvider

    public init(interceptorProvider: any InterceptorProvider) {
        self.interceptorProvider = interceptorProvider
    }
    @discardableResult
    public func send<Request: Requestable>(
        request: Request,
        cachePolicy: CachePolicy,
        dispatchQueue: DispatchQueue,
        completion: @escaping HTTPResultHandler<Request>
    ) -> (any Cancellable)? {
        
        
        let operation = HTTPOperation(request: request, cachePolicy: cachePolicy)
        let chain = makeRequestChain(for: operation, dispatchQueue: dispatchQueue)
        
        chain.kickoff(
            operation: operation,
            completion: completion
        )
        return chain
    }

    public func makeRequestChain<Request: Requestable>(for operation: HTTPOperation<Request>, dispatchQueue: DispatchQueue) -> any RequestChain {
        NetworkInterceptChain(
            interceptors: interceptorProvider.interceptors(for: operation),
            dispatchQueue: dispatchQueue,
            errorHandler: interceptorProvider.additionalErrorHandler(for: operation)
        )
    }
}
