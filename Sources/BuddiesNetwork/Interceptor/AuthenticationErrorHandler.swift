import Foundation

/// Handles HTTP 401 responses by running a logout (or session reset) hook and cancelling the chain.
public final class AuthenticationErrorHandler: ChainErrorHandler {
    private let onUnauthorized: @MainActor @Sendable () async -> Void

    public init(onUnauthorized: @escaping @MainActor @Sendable () async -> Void) {
        self.onUnauthorized = onUnauthorized
    }

    public func handleError<Request>(
        error: Error,
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        if response?.httpResponse.statusCode == 401 {
            let onUnauthorized = onUnauthorized
            Task { @MainActor in
                await onUnauthorized()
                chain.cancel()
                completion(.failure(error))
            }
        } else {
            completion(.failure(error))
        }
    }
}
