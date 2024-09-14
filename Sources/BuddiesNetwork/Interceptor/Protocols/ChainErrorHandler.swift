import Foundation

public protocol ChainErrorHandler {
    func handleError<Request>(
        error: Error,
        chain: RequestChain,
        request: HTTPRequest<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable
}
