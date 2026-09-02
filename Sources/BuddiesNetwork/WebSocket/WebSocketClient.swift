import Foundation

public final class WebSocketClient: Sendable {
    public let client: any WebSocketTaskProvider
    public let additionalHeaders: @Sendable () -> [String: String]
    public let maximumMessageSize: Int?

    public init(
        client: any WebSocketTaskProvider,
        maximumMessageSize: Int? = nil,
        additionalHeaders: @escaping @Sendable () -> [String: String] = { [:] }
    ) {
        self.client = client
        self.maximumMessageSize = maximumMessageSize
        self.additionalHeaders = additionalHeaders
    }

    public func connection<Request: Requestable>(
        for request: Request,
        cachePolicy: CachePolicy = .fetchIgnoringCacheCompletely,
        bufferingPolicy: WebSocketBufferingPolicy = .bufferingNewest(100)
    ) throws -> WebSocketConnection {
        let operation = HTTPOperation(
            request: request,
            cachePolicy: cachePolicy
        )

        for (key, value) in additionalHeaders() {
            operation.addHeader(key: key, val: value)
        }

        let properties = operation.properties
        let scheme = properties.url.scheme?.lowercased()

        guard scheme == "ws" || scheme == "wss" else {
            throw WebSocketError.unsupportedURLScheme(scheme)
        }

        let urlRequest = try URLProvider.urlRequest(from: properties)
        let task = try client.webSocketTask(with: urlRequest)

        if let maximumMessageSize {
            task.maximumMessageSize = maximumMessageSize
        }

        let connection = WebSocketConnection(
            task: task,
            bufferingPolicy: bufferingPolicy
        )
        connection.resume()
        return connection
    }

    /// Opens a WebSocket and consumes its messages with callbacks.
    ///
    /// Retain the returned connection for as long as the socket should remain
    /// open. It can also be used to send messages, ping, or close the socket.
    @discardableResult
    public func connect<Request: Requestable>(
        _ request: Request,
        cachePolicy: CachePolicy = .fetchIgnoringCacheCompletely,
        bufferingPolicy: WebSocketBufferingPolicy = .bufferingNewest(100),
        dispatchQueue: DispatchQueue = .main,
        onMessage: @escaping WebSocketMessageHandler,
        completion: @escaping WebSocketCompletion = { _ in }
    ) -> WebSocketConnection? {
        let connection: WebSocketConnection

        do {
            connection = try self.connection(
                for: request,
                cachePolicy: cachePolicy,
                bufferingPolicy: bufferingPolicy
            )
        } catch {
            dispatchQueue.async {
                completion(.failure(error))
            }
            return nil
        }

        let messages = connection.messages

        Task {
            let result: Result<Void, any Error>

            do {
                for try await message in messages {
                    dispatchQueue.async {
                        onMessage(message)
                    }
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }

            dispatchQueue.async {
                completion(result)
            }
        }

        return connection
    }
}
