import Foundation

public enum CachePolicy: Hashable, Sendable {
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
    public static let `default`: CachePolicy = .returnCacheDataElseFetch
}


public struct HTTPResult<Request: Requestable>: Sendable {
    /// Represents source of data
    public enum Source: Hashable, Sendable {
        case cache
        case server
    }

    public let source: Source
    public let data: Request.Data

    public init(source: Source, data: Request.Data) {
        self.source = source
        self.data = data
    }
}

public typealias HTTPResultHandler<Request: Requestable> = @Sendable (Result<HTTPResult<Request>, any Error>) -> Void

public final class APIClient: Sendable {
    public let networkTransporter: any NetworkTransportProtocol
    public let serverSentEventsClient: ServerSentEventsClient

    public init(
        networkTransporter: any NetworkTransportProtocol,
        serverSentEventsClient: ServerSentEventsClient = ServerSentEventsClient(
            client: URLSessionClient(sessionConfiguration: .default)
        )
    ) {
        self.networkTransporter = networkTransporter
        self.serverSentEventsClient = serverSentEventsClient
    }

    convenience init() {
        let client = URLSessionClient(sessionConfiguration: .default)
        let provider = DefaultInterceptorProvider(client: client)
        let transporter = DefaultRequestChainNetworkTransport(interceptorProvider: provider)
        let serverSentEventsClient = ServerSentEventsClient(client: client)

        self.init(
            networkTransporter: transporter,
            serverSentEventsClient: serverSentEventsClient
        )
    }

    public func perform<Request: Requestable>(
        _ request: Request,
        dispatchQueue: DispatchQueue = .main,
        cachePolicy: CachePolicy = .fetchIgnoringCacheCompletely,
        completion: @escaping HTTPResultHandler<Request>
    ) -> (any Cancellable)? {
        return networkTransporter.send(
            request: request,
            cachePolicy: cachePolicy,
            dispatchQueue: dispatchQueue,
            completion: completion
        )
    }


    public func perform<Request: Requestable>(
        _ request: Request,
        cachePolicy: CachePolicy = .fetchIgnoringCacheCompletely,
        dispatchQueue: DispatchQueue = .main
    ) async throws -> Request.Data {
        try await withCheckedThrowingContinuation { continuation in
            let _ = self.perform(
                request,
                dispatchQueue: dispatchQueue,
                cachePolicy: cachePolicy
            ) { result in
                switch result {
                case let .success(success):
                    continuation.resume(returning: success.data)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @discardableResult
    public func connectServerSentEvents<Request: Requestable>(
        _ request: Request,
        cachePolicy: CachePolicy = .fetchIgnoringCacheCompletely,
        dispatchQueue: DispatchQueue = .main,
        onEvent: @escaping ServerSentEventHandler,
        completion: @escaping ServerSentEventsCompletion = { _ in }
    ) -> (any Cancellable)? {
        serverSentEventsClient.connect(
            request,
            cachePolicy: cachePolicy,
            dispatchQueue: dispatchQueue,
            onEvent: onEvent,
            completion: completion
        )
    }

    public func serverSentEvents<Request: Requestable>(
        for request: Request,
        cachePolicy: CachePolicy = .fetchIgnoringCacheCompletely,
        dispatchQueue: DispatchQueue = .main
    ) -> AsyncThrowingStream<ServerSentEvent, Error> {
        serverSentEventsClient.events(
            for: request,
            cachePolicy: cachePolicy,
            dispatchQueue: dispatchQueue
        )
    }
}
