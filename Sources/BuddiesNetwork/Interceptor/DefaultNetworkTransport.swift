import Foundation

public protocol NetworkTransportProtocol {
    func send<Request: Requestable>(
        request: Request,
        cachePolicy: CachePolicy,
        dispatchQueue: DispatchQueue,
        completion: @escaping HTTPResultHandler<Request>
    ) -> (any Cancellable)?
}

open class DefaultRequestChainNetworkTransport: NetworkTransportProtocol {
    let interceptorProvider: InterceptorProvider

    public init(interceptorProvider: InterceptorProvider) {
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

    open func makeRequestChain<Request: Requestable>(for operation: HTTPOperation<Request>, dispatchQueue: DispatchQueue) -> RequestChain {
        NetworkInterceptChain(
            interceptors: interceptorProvider.interceptors(for: operation),
            dispatchQueue: dispatchQueue,
            errorHandler: interceptorProvider.additionalErrorHandler(for: operation)
        )
    }
}
