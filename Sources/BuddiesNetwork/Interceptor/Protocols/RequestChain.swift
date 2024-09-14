import Foundation

public protocol RequestChain: AnyObject {
    var interceptors: [Interceptor] { get set }
    var errorHandler: ChainErrorHandler? { get }
    var isCancelled: Bool { get }

    func kickoff<Request>(
        request: HTTPRequest<Request>,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable

    func handleErrorAsync<Request>(
        _ error: Error,
        request: HTTPRequest<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable

    func retry<Request>(
        request: HTTPRequest<Request>,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable

    func proceed<Request>(
        interceptorIndex: Int,
        request: HTTPRequest<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable

    func proceed<Request>(
        request: HTTPRequest<Request>,
        interceptor: any Interceptor,
        response: HTTPResponse<Request>?,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable

    func returnValue<Request>(
        for request: HTTPRequest<Request>,
        value: Request.Data,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable

    func cancel()
}
