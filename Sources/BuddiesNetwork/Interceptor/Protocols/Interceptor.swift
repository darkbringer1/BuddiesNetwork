import Foundation

public protocol Interceptor: AnyObject, Sendable {
    var id: String { get }

    func intercept<Request>(
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable
}

public protocol Cancellable: Sendable {
    func cancel()
}
