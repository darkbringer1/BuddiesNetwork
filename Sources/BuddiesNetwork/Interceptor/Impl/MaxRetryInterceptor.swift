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
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard currentHit <= maxRetry else {
            let error = RetryError.exceedRetryLimit(currentHit, operation.properties.requestName)

            chain.handleErrorAsync(
                error,
                operation: operation,
                response: response,
                completion: completion
            )

            return
        }

        currentHit += 1

        chain.proceed(
            operation: operation,
            interceptor: self,
            response: response,
            completion: completion
        )
    }
}
