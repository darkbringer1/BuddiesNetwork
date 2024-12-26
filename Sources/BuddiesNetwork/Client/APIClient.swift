import Foundation

public enum CachePolicy: Hashable {
    /// Return data from the cache if available, else fetch results from the server.
    case returnCacheDataElseFetch
    ///  Always fetch results from the server.
    case fetchIgnoringCacheData
    ///  Always fetch results from the server, and don't store these in the cache.
    case fetchIgnoringCacheCompletely
    /// Return data from the cache if available, else return an error.
    case returnCacheDataDontFetch
    /// Return data from the cache if available, and always fetch results from the server.
    case returnCacheDataAndFetch
    
    /// The current default cache policy.
    public static var `default`: CachePolicy = .returnCacheDataElseFetch
}

public class APIClient {
    public private(set) var networkTransporter: NetworkTransportProtocol

    public init(
        networkTransporter: NetworkTransportProtocol
    ) {
        self.networkTransporter = networkTransporter
    }

    convenience init() {
        let provider = DefaultInterceptorProvider(client: URLSessionClient(sessionConfiguration: .default))
        let transporter = DefaultRequestChainNetworkTransport(interceptorProvider: provider)

        self.init(networkTransporter: transporter)
    }

    public func perform<Request: Requestable>(
        _ request: Request,
        dispatchQueue: DispatchQueue = .main,
        cachePolicy: CachePolicy = .default,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) {
        networkTransporter.send(
            request: request,
            cachePolicy: cachePolicy,
            dispatchQueue: dispatchQueue,
            completion: completion
        )
    }

    public func perform<Request: Requestable>(
        _ request: Request,
        cachePolicy: CachePolicy = .default,
        dispatchQueue: DispatchQueue = .main
    ) async throws -> Request.Data {
        try await withCheckedThrowingContinuation { continuation in
            self.perform(
                request,
                dispatchQueue: dispatchQueue
            ) { result in

                switch result {
                case let .success(success):
                    continuation.resume(returning: success)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
