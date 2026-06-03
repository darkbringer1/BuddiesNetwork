import Foundation
import Synchronization

public final class MaxRetryInterceptor: Interceptor {
    private struct State {
        var currentHit = 0
    }

    enum RetryError: Error, LocalizedError {
        case exceedRetryLimit(Int, String)

        var errorDescription: String? {
            switch self {
            case let .exceedRetryLimit(hitCount, requestName): "Request: \(requestName), retried \(hitCount) times without success."
            }
        }
    }

    public let id: String = UUID().uuidString

    private let maxRetry: Int
    private let state = Mutex(State())

    public init(maxRetry: Int) {
        self.maxRetry = maxRetry
    }

    public func intercept<Request>(
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        let hit = state.withLock { state in
            let hit = state.currentHit
            state.currentHit += 1
            return hit
        }

        guard hit <= maxRetry else {
            let error = RetryError.exceedRetryLimit(hit, operation.properties.requestName)

            chain.handleErrorAsync(
                error,
                operation: operation,
                response: response,
                completion: completion
            )

            return
        }

        chain.proceed(
            operation: operation,
            interceptor: self,
            response: response,
            completion: completion
        )
    }
}
