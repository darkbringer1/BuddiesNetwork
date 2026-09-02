import Foundation
import Synchronization

public typealias WebSocketMessageHandler = @Sendable (WebSocketMessage) -> Void
public typealias WebSocketCompletion = @Sendable (Result<Void, any Error>) -> Void
public typealias WebSocketBufferingPolicy = AsyncThrowingStream<WebSocketMessage, Error>.Continuation.BufferingPolicy

/// A live, bidirectional WebSocket connection.
///
/// Consume ``messages`` from a single task, use ``send(_:)`` to write text or
/// binary messages, and call ``close(code:reason:)`` when the connection is no
/// longer needed.
public final class WebSocketConnection: Cancellable, Sendable {
    private final class State: Sendable {
        private let isClosedStorage = Mutex(false)

        var isClosed: Bool {
            isClosedStorage.withLock { $0 }
        }

        func markClosed() -> Bool {
            isClosedStorage.withLock { isClosed in
                guard !isClosed else {
                    return false
                }

                isClosed = true
                return true
            }
        }
    }

    public let messages: AsyncThrowingStream<WebSocketMessage, Error>

    public var isClosed: Bool {
        state.isClosed
    }

    public var closeCode: URLSessionWebSocketTask.CloseCode {
        task.closeCode
    }

    public var closeReason: Data? {
        task.closeReason
    }

    private let task: any WebSocketTaskProtocol
    private let continuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation
    private let state = State()

    init(
        task: any WebSocketTaskProtocol,
        bufferingPolicy: WebSocketBufferingPolicy
    ) {
        self.task = task

        let (messages, continuation) = AsyncThrowingStream.makeStream(
            of: WebSocketMessage.self,
            throwing: Error.self,
            bufferingPolicy: bufferingPolicy
        )
        self.messages = messages
        self.continuation = continuation
    }

    deinit {
        close(code: .goingAway)
    }

    func resume() {
        let task = task
        let state = state
        let continuation = continuation

        continuation.onTermination = { @Sendable _ in
            guard state.markClosed() else {
                return
            }

            task.cancel(with: .goingAway, reason: nil)
        }

        task.resume()

        Task {
            await Self.receiveMessages(
                from: task,
                state: state,
                continuation: continuation
            )
        }
    }

    public func send(_ message: WebSocketMessage) async throws {
        try Task.checkCancellation()

        guard !isClosed else {
            throw WebSocketError.connectionClosed(
                code: task.closeCode,
                reason: task.closeReason
            )
        }

        try await task.send(message.urlSessionMessage)
    }

    @discardableResult
    public func send(
        _ message: WebSocketMessage,
        dispatchQueue: DispatchQueue = .main,
        completion: @escaping WebSocketCompletion
    ) -> Task<Void, Never> {
        Task {
            let result: Result<Void, any Error>

            do {
                try await send(message)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            dispatchQueue.async {
                completion(result)
            }
        }
    }

    public func ping() async throws {
        try Task.checkCancellation()

        guard !isClosed else {
            throw WebSocketError.connectionClosed(
                code: task.closeCode,
                reason: task.closeReason
            )
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    @discardableResult
    public func ping(
        dispatchQueue: DispatchQueue = .main,
        completion: @escaping WebSocketCompletion
    ) -> Task<Void, Never> {
        Task {
            let result: Result<Void, any Error>

            do {
                try await ping()
                result = .success(())
            } catch {
                result = .failure(error)
            }

            dispatchQueue.async {
                completion(result)
            }
        }
    }

    public func close(
        code: URLSessionWebSocketTask.CloseCode = .normalClosure,
        reason: Data? = nil
    ) {
        guard state.markClosed() else {
            return
        }

        task.cancel(with: code, reason: reason)
        continuation.finish()
    }

    public func cancel() {
        close(code: .goingAway)
    }

    private static func receiveMessages(
        from task: any WebSocketTaskProtocol,
        state: State,
        continuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation
    ) async {
        do {
            while !state.isClosed {
                try Task.checkCancellation()
                let message = try await task.receive()

                switch continuation.yield(try WebSocketMessage(message)) {
                case .enqueued:
                    continue
                case .dropped:
                    guard state.markClosed() else {
                        return
                    }

                    task.cancel(
                        with: .policyViolation,
                        reason: Data("Message buffer overflow".utf8)
                    )
                    continuation.finish(
                        throwing: WebSocketError.messageBufferOverflow
                    )
                    return
                case .terminated:
                    guard state.markClosed() else {
                        return
                    }

                    task.cancel(with: .goingAway, reason: nil)
                    return
                @unknown default:
                    guard state.markClosed() else {
                        return
                    }

                    task.cancel(with: .protocolError, reason: nil)
                    continuation.finish(
                        throwing: WebSocketError.unsupportedMessage
                    )
                    return
                }
            }
        } catch is CancellationError {
            finishNormally(state: state, continuation: continuation)
        } catch {
            guard state.markClosed() else {
                return
            }

            switch task.closeCode {
            case .normalClosure, .goingAway:
                continuation.finish()
            case .invalid:
                task.cancel()
                continuation.finish(throwing: error)
            default:
                continuation.finish(
                    throwing: WebSocketError.connectionClosed(
                        code: task.closeCode,
                        reason: task.closeReason
                    )
                )
            }
        }
    }

    private static func finishNormally(
        state: State,
        continuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation
    ) {
        guard state.markClosed() else {
            return
        }

        continuation.finish()
    }
}
