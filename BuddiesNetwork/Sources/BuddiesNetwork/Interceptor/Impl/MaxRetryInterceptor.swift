import Foundation

public class MaxRetryInterceptor: Interceptor {
    enum RetryError: Error, LocalizedError {
        case exceedRetryLimit(Int, String)

        var errorDescription: String? {
            switch self {
            case let .exceedRetryLimit(hitCount, requestName): "Request: \(requestName), retried \(hitCount) times without success."
            }
        }
    }

    public var id: String = UUID().uuidString

    private(set) var maxRetry: Int
    private(set) var currentHit: Int = 0

    public init(maxRetry: Int) {
        self.maxRetry = maxRetry
    }

    public func intercept<Request>(
        chain: RequestChain,
        request: HTTPRequest<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable {
        guard currentHit <= maxRetry else {
            let error = RetryError.exceedRetryLimit(currentHit, request.requestName)

            chain.handleErrorAsync(
                error,
                request: request,
                response: response,
                completion: completion
            )

            return
        }

        currentHit += 1

        chain.proceed(
            request: request,
            interceptor: self,
            response: response,
            completion: completion
        )
    }
}
