import Foundation
import Synchronization

public final class NetworkInterceptChain: RequestChain {
    private struct State {
        var currentIndex = 0
        var isCancelled = false
    }

    public enum InterceptChainError: Error, LocalizedError {
        case interceptorNotFound
        case interceptorIndexNotFound(Int)

        public var errorDescription: String? {
            switch self {
            case .interceptorNotFound: "There is no interceptor available."
            case let .interceptorIndexNotFound(index): "There is no interceptor found at index: \(index)"
            }
        }
    }

    // MARK: Public
    public let interceptors: [any Interceptor]
    public let errorHandler: (any ChainErrorHandler)?

    public var isCancelled: Bool {
        state.withLock { $0.isCancelled }
    }

    // MARK: Private
    private let state = Mutex(State())
    private let interceptorIndexes: [String: Int]
    private let dispatchQueue: DispatchQueue

    public init(
        interceptors: [any Interceptor],
        dispatchQueue: DispatchQueue = .main,
        errorHandler: (any ChainErrorHandler)? = nil
    ) {
        self.interceptors = interceptors
        self.errorHandler = errorHandler
        self.dispatchQueue = dispatchQueue

        var interceptorIndexes: [String: Int] = [:]
        for (index, interceptor) in interceptors.enumerated() {
            interceptorIndexes[interceptor.id] = index
        }
        self.interceptorIndexes = interceptorIndexes
    }

    public func kickoff<Request>(
        operation: HTTPOperation<Request>,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        assert(state.withLock { $0.currentIndex } == 0)

        guard let firstInterceptor = interceptors.first else {
            handleErrorAsync(
                InterceptChainError.interceptorNotFound,
                operation: operation,
                response: nil,
                completion: completion
            )
            return
        }

        firstInterceptor.intercept(
            chain: self,
            operation: operation,
            response: nil,
            completion: completion
        )
    }

    public func retry<Request>(
        operation: HTTPOperation<Request>,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard !isCancelled else {
            return
        }

        state.withLock { $0.currentIndex = 0 }
        kickoff(
            operation: operation,
            completion: completion
        )
    }

    public func handleErrorAsync<Request>(
        _ error: Error,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard !isCancelled else {
            return
        }

        // Handle error if there is an error handler assigned.
        guard let errorHandler else {
            // if not return error directly.
            dispatchQueue.async {
                completion(.failure(error))
            }
            return
        }

        let dispatchQueue = dispatchQueue
        errorHandler.handleError(
            error: error,
            chain: self,
            operation: operation,
            response: response
        ) { result in
            dispatchQueue.async {
                completion(result)
            }
        }
    }

    public func proceed<Request>(
        interceptorIndex: Int,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard !isCancelled else {
            return
        }

        if interceptors.indices.contains(interceptorIndex) {
            state.withLock { $0.currentIndex = interceptorIndex }

            let currentInterceptor = interceptors[interceptorIndex]

            currentInterceptor.intercept(
                chain: self,
                operation: operation,
                response: response,
                completion: { result in
                    // Somehow dispatchQueue is dellocated that this doesn't get called unless it's like this.
                    // TODO: Investigate!
                    self.dispatchQueue.async {
                        completion(result)
                    }
                }
            )
        } else {
            // If we already have the parsedData, then we can return it.
            if let parsedData = response?.parsedData {
                let result = HTTPResult<Request>(source: .server, data: parsedData)
                returnValue(
                    for: operation,
                    result: result,
                    completion: completion
                )
            } else {
                // this means that index is not found on interceptors, and we don't have parsedData.
                handleErrorAsync(
                    InterceptChainError.interceptorIndexNotFound(interceptorIndex),
                    operation: operation,
                    response: response,
                    completion: completion
                )
            }
        }
    }

    public func proceed<Request>(
        operation: HTTPOperation<Request>,
        interceptor: any Interceptor,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard let interceptorIndex = interceptorIndexes[interceptor.id] else {
            handleErrorAsync(
                InterceptChainError.interceptorNotFound,
                operation: operation,
                response: response,
                completion: completion
            )
            return
        }

        let nextIndex = interceptorIndex + 1

        proceed(
            interceptorIndex: nextIndex,
            operation: operation,
            response: response,
            completion: completion
        )
    }

    public func returnValue<Request>(
        for operation: HTTPOperation<Request>,
        result: HTTPResult<Request>,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard !isCancelled else {
            return
        }

        completion(.success(result))
    }

    public func cancel() {
        guard !isCancelled else {
            return
        }

        state.withLock { $0.isCancelled = true }

        for interceptor in interceptors {
            if let cancellableInterceptor = interceptor as? Cancellable {
                cancellableInterceptor.cancel()
            }
        }
    }
}
