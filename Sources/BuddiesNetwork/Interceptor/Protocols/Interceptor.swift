import Foundation

public protocol Interceptor {
    var id: String { get set }

    func intercept<Request>(
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable
}

public protocol Cancellable {
    func cancel()
}
