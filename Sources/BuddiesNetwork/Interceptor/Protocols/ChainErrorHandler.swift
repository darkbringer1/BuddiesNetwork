import Foundation

public protocol ChainErrorHandler {
    func handleError<Request>(
        error: Error,
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable
}
