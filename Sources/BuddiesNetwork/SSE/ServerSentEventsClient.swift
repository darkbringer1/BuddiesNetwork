import Foundation
import Synchronization

public typealias ServerSentEventHandler = @Sendable (ServerSentEvent) -> Void
public typealias ServerSentEventsCompletion = @Sendable (Result<Void, any Error>) -> Void

public final class ServerSentEventsClient: Sendable {
    public let client: URLSessionClient
    public let acceptableStatusCodes: Range<Int>
    public let additionalHeaders: @Sendable () -> [String: String]

    public init(
        client: URLSessionClient,
        acceptableStatusCodes: Range<Int> = 200 ..< 300,
        additionalHeaders: @escaping @Sendable () -> [String: String] = { [:] }
    ) {
        self.client = client
        self.acceptableStatusCodes = acceptableStatusCodes
        self.additionalHeaders = additionalHeaders
    }

    @discardableResult
    public func connect<Request: Requestable>(
        _ request: Request,
        cachePolicy: CachePolicy = .fetchIgnoringCacheCompletely,
        dispatchQueue: DispatchQueue = .main,
        onEvent: @escaping ServerSentEventHandler,
        completion: @escaping ServerSentEventsCompletion = { _ in }
    ) -> (any Cancellable)? {
        let operation = HTTPOperation(
            request: request,
            cachePolicy: cachePolicy
        )
        operation.addHeader(key: "accept", val: "text/event-stream")
        operation.addHeader(key: "Cache-Control", val: "no-cache")

        for (key, value) in additionalHeaders() {
            operation.addHeader(key: key, val: value)
        }

        let urlRequest: URLRequest

        do {
            urlRequest = try URLProvider.urlRequest(from: operation.properties)
        } catch {
            dispatchQueue.async {
                completion(.failure(error))
            }
            return nil
        }

        let parser = ServerSentEventParser()
        let eventsTask = ServerSentEventsTask()
        let acceptableStatusCodes = acceptableStatusCodes

        let task = client.sendStreamingRequest(
            urlRequest,
            responseValidator: { response in
                guard acceptableStatusCodes.contains(response.statusCode) else {
                    return ServerSentEventsError.unacceptableStatusCode(response.statusCode)
                }

                return nil
            },
            onData: { data in
                guard !eventsTask.isCompleted else {
                    return
                }

                do {
                    let events = try parser.parse(data)
                    for event in events {
                        eventsTask.yield(
                            event,
                            dispatchQueue: dispatchQueue,
                            onEvent: onEvent
                        )
                    }
                } catch {
                    eventsTask.failAndCancel(
                        error,
                        dispatchQueue: dispatchQueue,
                        completion: completion
                    )
                }
            },
            completion: { result in
                switch result {
                case .success:
                    do {
                        let events = try parser.finish()
                        for event in events {
                            eventsTask.yield(
                                event,
                                dispatchQueue: dispatchQueue,
                                onEvent: onEvent
                            )
                        }

                        eventsTask.finish(
                            .success(()),
                            dispatchQueue: dispatchQueue,
                            completion: completion
                        )
                    } catch {
                        eventsTask.finish(
                            .failure(error),
                            dispatchQueue: dispatchQueue,
                            completion: completion
                        )
                    }
                case let .failure(error):
                    eventsTask.finish(
                        .failure(error),
                        dispatchQueue: dispatchQueue,
                        completion: completion
                    )
                }
            }
        )

        eventsTask.setTask(task)

        guard task != nil else {
            return nil
        }

        return eventsTask
    }

    public func events<Request: Requestable>(
        for request: Request,
        cachePolicy: CachePolicy = .fetchIgnoringCacheCompletely,
        dispatchQueue: DispatchQueue = .main
    ) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = connect(
                request,
                cachePolicy: cachePolicy,
                dispatchQueue: dispatchQueue,
                onEvent: { event in
                    continuation.yield(event)
                },
                completion: { result in
                    switch result {
                    case .success:
                        continuation.finish()
                    case let .failure(error):
                        continuation.finish(throwing: error)
                    }
                }
            )

            continuation.onTermination = { @Sendable _ in
                task?.cancel()
            }
        }
    }
}

private final class ServerSentEventsTask: Cancellable {
    private struct State {
        var task: URLSessionTask?
        var isCompleted = false
        var isCancelled = false
    }

    private let state = Mutex(State())

    var isCompleted: Bool {
        state.withLock { $0.isCompleted }
    }

    func setTask(_ task: URLSessionTask?) {
        let shouldCancel = state.withLock { state in
            guard !state.isCompleted, !state.isCancelled else {
                return true
            }

            state.task = task
            return false
        }

        if shouldCancel {
            task?.cancel()
        }
    }

    func yield(
        _ event: ServerSentEvent,
        dispatchQueue: DispatchQueue,
        onEvent: @escaping ServerSentEventHandler
    ) {
        guard !isCompleted else {
            return
        }

        dispatchQueue.async {
            onEvent(event)
        }
    }

    func finish(
        _ result: Result<Void, any Error>,
        dispatchQueue: DispatchQueue,
        completion: @escaping ServerSentEventsCompletion
    ) {
        let shouldFinish = state.withLock { state in
            guard !state.isCompleted else {
                return false
            }

            state.isCompleted = true
            state.task = nil
            return true
        }

        guard shouldFinish else {
            return
        }

        dispatchQueue.async {
            completion(result)
        }
    }

    func failAndCancel(
        _ error: any Error,
        dispatchQueue: DispatchQueue,
        completion: @escaping ServerSentEventsCompletion
    ) {
        let task = state.withLock { state in
            guard !state.isCompleted else {
                return nil as URLSessionTask?
            }

            state.isCompleted = true
            let task = state.task
            state.task = nil
            return task
        }

        task?.cancel()

        dispatchQueue.async {
            completion(.failure(error))
        }
    }

    func cancel() {
        let task = state.withLock { state in
            guard !state.isCancelled else {
                return nil as URLSessionTask?
            }

            state.isCancelled = true
            state.isCompleted = true
            let task = state.task
            state.task = nil
            return task
        }

        task?.cancel()
    }
}
