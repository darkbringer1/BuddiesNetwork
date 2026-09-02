import Foundation
import Synchronization
import XCTest
@testable import BuddiesNetwork

private struct SocketRequest: Requestable {
    struct Data: Decodable, Sendable {}

    let url: URL

    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: url,
            httpMethod: .get,
            additionalHeaders: ["X-Request-ID": "request-123"]
        )
    }
}

final class WebSocketClientTests: XCTestCase {
    func testAPIClientBuildsAndStartsWebSocketConnection() throws {
        let url = try XCTUnwrap(URL(string: "wss://example.com/socket"))
        let task = WebSocketTaskStub()
        let provider = WebSocketTaskProviderStub(task: task)
        let webSocketClient = WebSocketClient(
            client: provider,
            maximumMessageSize: 2_048,
            additionalHeaders: {
                ["Authorization": "Bearer token"]
            }
        )
        let transport = DefaultRequestChainNetworkTransport(
            interceptorProvider: MockInterceptorProvider(responseDelaySeconds: 0 ... 0)
        )
        let apiClient = APIClient(
            networkTransporter: transport,
            webSocketClient: webSocketClient
        )

        let connection = try apiClient.webSocketConnection(
            for: SocketRequest(url: url)
        )
        defer { connection.close() }

        let request = try XCTUnwrap(provider.lastRequest)
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.httpMethod, HTTPMethod.get.rawValue)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer token"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Request-ID"),
            "request-123"
        )
        XCTAssertTrue(task.didResume)
        XCTAssertEqual(task.maximumMessageSize, 2_048)
    }

    func testConnectionStreamsTextAndDataUntilNormalClosure() async throws {
        let url = try XCTUnwrap(URL(string: "wss://example.com/socket"))
        let binary = Data([0x01, 0x02, 0x03])
        let task = WebSocketTaskStub(
            receiveActions: [
                .message(.string("hello")),
                .message(.data(binary)),
                .close(code: .normalClosure, reason: nil)
            ]
        )
        let client = WebSocketClient(
            client: WebSocketTaskProviderStub(task: task)
        )
        let connection = try client.connection(
            for: SocketRequest(url: url)
        )

        var messages: [WebSocketMessage] = []
        for try await message in connection.messages {
            messages.append(message)
        }

        XCTAssertEqual(messages, [.text("hello"), .data(binary)])
        XCTAssertTrue(connection.isClosed)
        XCTAssertEqual(connection.closeCode, .normalClosure)
    }

    func testConnectionSurfacesAbnormalClosure() async throws {
        let url = try XCTUnwrap(URL(string: "wss://example.com/socket"))
        let reason = Data("not allowed".utf8)
        let task = WebSocketTaskStub(
            receiveActions: [
                .close(code: .policyViolation, reason: reason)
            ]
        )
        let client = WebSocketClient(
            client: WebSocketTaskProviderStub(task: task)
        )
        let connection = try client.connection(
            for: SocketRequest(url: url)
        )

        do {
            for try await _ in connection.messages {
                XCTFail("Unexpected message")
            }

            XCTFail("Expected an abnormal close error")
        } catch {
            XCTAssertEqual(
                error as? WebSocketError,
                .connectionClosed(code: .policyViolation, reason: reason)
            )
        }
    }

    func testConnectionSendsMessagesAndPing() async throws {
        let url = try XCTUnwrap(URL(string: "wss://example.com/socket"))
        let task = WebSocketTaskStub()
        let client = WebSocketClient(
            client: WebSocketTaskProviderStub(task: task)
        )
        let connection = try client.connection(
            for: SocketRequest(url: url)
        )
        defer { connection.close() }

        try await connection.send(.text("outgoing"))
        try await connection.send(.data(Data([0xCA, 0xFE])))
        try await connection.ping()

        XCTAssertEqual(
            try task.sentMessages.map(WebSocketMessage.init),
            [.text("outgoing"), .data(Data([0xCA, 0xFE]))]
        )
        XCTAssertEqual(task.pingCount, 1)
    }

    func testConnectionRejectsNonWebSocketURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/socket"))
        let task = WebSocketTaskStub()
        let provider = WebSocketTaskProviderStub(task: task)
        let client = WebSocketClient(client: provider)

        XCTAssertThrowsError(
            try client.connection(for: SocketRequest(url: url))
        ) { error in
            XCTAssertEqual(
                error as? WebSocketError,
                .unsupportedURLScheme("https")
            )
        }
        XCTAssertNil(provider.lastRequest)
        XCTAssertFalse(task.didResume)
    }

    func testCloseForwardsCodeAndReasonAndFinishesMessages() async throws {
        let url = try XCTUnwrap(URL(string: "wss://example.com/socket"))
        let reason = Data("done".utf8)
        let task = WebSocketTaskStub()
        let client = WebSocketClient(
            client: WebSocketTaskProviderStub(task: task)
        )
        let connection = try client.connection(
            for: SocketRequest(url: url)
        )

        connection.close(code: .normalClosure, reason: reason)

        var iterator = connection.messages.makeAsyncIterator()
        let message = try await iterator.next()
        XCTAssertNil(message)
        XCTAssertTrue(connection.isClosed)
        XCTAssertEqual(task.cancelCall?.code, .normalClosure)
        XCTAssertEqual(task.cancelCall?.reason, reason)
    }

    func testCallbackAPIReceivesMessagesAndCompletes() async throws {
        let url = try XCTUnwrap(URL(string: "wss://example.com/socket"))
        let task = WebSocketTaskStub(
            receiveActions: [
                .message(.string("callback")),
                .close(code: .normalClosure, reason: nil)
            ]
        )
        let client = WebSocketClient(
            client: WebSocketTaskProviderStub(task: task)
        )
        let receivedMessage = Mutex<WebSocketMessage?>(nil)
        let completedSuccessfully = Mutex<Bool?>(nil)
        let messageExpectation = expectation(description: "Receives a message")
        let completionExpectation = expectation(description: "Completes")
        let callbackQueue = DispatchQueue(
            label: "buddiesnetwork.websocket.callback.test"
        )

        let connection = client.connect(
            SocketRequest(url: url),
            dispatchQueue: callbackQueue,
            onMessage: { message in
                receivedMessage.withLock { $0 = message }
                messageExpectation.fulfill()
            },
            completion: { result in
                completedSuccessfully.withLock { success in
                    switch result {
                    case .success:
                        success = true
                    case .failure:
                        success = false
                    }
                }
                completionExpectation.fulfill()
            }
        )
        defer { connection?.close() }

        await fulfillment(
            of: [messageExpectation, completionExpectation],
            timeout: 1
        )
        XCTAssertEqual(receivedMessage.withLock { $0 }, .text("callback"))
        XCTAssertEqual(completedSuccessfully.withLock { $0 }, true)
    }
}

private final class WebSocketTaskProviderStub: WebSocketTaskProvider {
    private let requestStorage = Mutex<URLRequest?>(nil)
    private let task: WebSocketTaskStub

    var lastRequest: URLRequest? {
        requestStorage.withLock { $0 }
    }

    init(task: WebSocketTaskStub) {
        self.task = task
    }

    func webSocketTask(
        with request: URLRequest
    ) throws -> any WebSocketTaskProtocol {
        requestStorage.withLock { $0 = request }
        return task
    }
}

private final class WebSocketTaskStub: WebSocketTaskProtocol {
    enum ReceiveAction: Sendable {
        case message(URLSessionWebSocketTask.Message)
        case close(code: URLSessionWebSocketTask.CloseCode, reason: Data?)
    }

    struct CancelCall: Equatable, Sendable {
        let code: URLSessionWebSocketTask.CloseCode
        let reason: Data?
    }

    private struct State {
        var closeCode: URLSessionWebSocketTask.CloseCode = .invalid
        var closeReason: Data?
        var maximumMessageSize = 1_048_576
        var didResume = false
        var sentMessages: [URLSessionWebSocketTask.Message] = []
        var pingCount = 0
        var cancelCall: CancelCall?
        var receiveActions: [ReceiveAction]
        var pendingReceive: CheckedContinuation<URLSessionWebSocketTask.Message, any Error>?
    }

    private enum StubError: Error {
        case connectionClosed
    }

    private let state: Mutex<State>

    var closeCode: URLSessionWebSocketTask.CloseCode {
        state.withLock { $0.closeCode }
    }

    var closeReason: Data? {
        state.withLock { $0.closeReason }
    }

    var maximumMessageSize: Int {
        get { state.withLock { $0.maximumMessageSize } }
        set { state.withLock { $0.maximumMessageSize = newValue } }
    }

    var didResume: Bool {
        state.withLock { $0.didResume }
    }

    var sentMessages: [URLSessionWebSocketTask.Message] {
        state.withLock { $0.sentMessages }
    }

    var pingCount: Int {
        state.withLock { $0.pingCount }
    }

    var cancelCall: CancelCall? {
        state.withLock { $0.cancelCall }
    }

    init(receiveActions: [ReceiveAction] = []) {
        state = Mutex(State(receiveActions: receiveActions))
    }

    func resume() {
        state.withLock { $0.didResume = true }
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try Task.checkCancellation()
        state.withLock { $0.sentMessages.append(message) }
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        let action: ReceiveAction? = state.withLock { state in
            guard !state.receiveActions.isEmpty else {
                return nil
            }

            return state.receiveActions.removeFirst()
        }

        if let action {
            return try resolve(action)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let isClosed = state.withLock { state in
                guard state.cancelCall == nil else {
                    return true
                }

                state.pendingReceive = continuation
                return false
            }

            if isClosed {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    func sendPing(
        pongReceiveHandler: @escaping @Sendable ((any Error)?) -> Void
    ) {
        state.withLock { $0.pingCount += 1 }
        pongReceiveHandler(nil)
    }

    func cancel() {
        cancel(with: .goingAway, reason: nil)
    }

    func cancel(
        with closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let continuation = state.withLock { state in
            guard state.cancelCall == nil else {
                return nil as CheckedContinuation<URLSessionWebSocketTask.Message, any Error>?
            }

            state.cancelCall = CancelCall(code: closeCode, reason: reason)
            state.closeCode = closeCode
            state.closeReason = reason
            let continuation = state.pendingReceive
            state.pendingReceive = nil
            return continuation
        }

        continuation?.resume(throwing: CancellationError())
    }

    private func resolve(
        _ action: ReceiveAction
    ) throws -> URLSessionWebSocketTask.Message {
        switch action {
        case let .message(message):
            return message
        case let .close(code, reason):
            state.withLock { state in
                state.closeCode = code
                state.closeReason = reason
            }
            throw StubError.connectionClosed
        }
    }
}
