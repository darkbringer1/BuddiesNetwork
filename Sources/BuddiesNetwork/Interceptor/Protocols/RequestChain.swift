import Foundation

public protocol RequestChain: AnyObject, Cancellable {
    var interceptors: [Interceptor] { get set }
    var errorHandler: ChainErrorHandler? { get }
    var isCancelled: Bool { get }

    func kickoff<Request>(
        operation: HTTPOperation<Request>,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable

    func handleErrorAsync<Request>(
        _ error: Error,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable

    func retry<Request>(
        operation: HTTPOperation<Request>,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable

    func proceed<Request>(
        interceptorIndex: Int,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable

    func proceed<Request>(
        operation: HTTPOperation<Request>,
        interceptor: any Interceptor,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable

    func returnValue<Request>(
        for operation: HTTPOperation<Request>,
        result: HTTPResult<Request>,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable

    func cancel()
}
