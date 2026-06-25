import Foundation
import Synchronization
import XCTest
@testable import BuddiesNetwork

private struct EventsRequest: Requestable {
    struct Data: Decodable, Sendable {}

    let url: URL

    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: url,
            httpMethod: .get
        )
    }
}

final class ServerSentEventsClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ServerSentEventsURLProtocol.reset()
    }

    func testAsyncStreamYieldsEventsAndSendsSSEHeaders() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/events"))
        ServerSentEventsURLProtocol.setResponse(
            .init(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream"],
                chunks: [
                    Data("id: 1\nevent: greeting\ndata: hello".utf8),
                    Data("\ndata: world\n\n".utf8),
                    Data("data: done\n\n".utf8)
                ]
            )
        )

        let client = makeClient()
        let eventQueue = DispatchQueue(label: "buddiesnetwork.sse.client.test")
        var events: [ServerSentEvent] = []

        for try await event in client.events(
            for: EventsRequest(url: url),
            dispatchQueue: eventQueue
        ) {
            events.append(event)
        }

        XCTAssertEqual(
            events,
            [
                ServerSentEvent(
                    id: "1",
                    event: "greeting",
                    data: "hello\nworld"
                ),
                ServerSentEvent(
                    id: "1",
                    data: "done"
                )
            ]
        )

        let headers = try XCTUnwrap(ServerSentEventsURLProtocol.lastRequestHeaders())
        XCTAssertEqual(headers.value(forHTTPHeaderField: "accept"), "text/event-stream")
        XCTAssertEqual(headers.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testAsyncStreamFailsForUnacceptableStatusCode() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/events"))
        ServerSentEventsURLProtocol.setResponse(
            .init(
                statusCode: 503,
                headers: ["Content-Type": "text/event-stream"],
                chunks: [Data("data: unavailable\n\n".utf8)]
            )
        )

        let client = makeClient()
        let eventQueue = DispatchQueue(label: "buddiesnetwork.sse.status.test")

        do {
            for try await _ in client.events(
                for: EventsRequest(url: url),
                dispatchQueue: eventQueue
            ) {
                XCTFail("Unexpected event for an unacceptable status code")
            }

            XCTFail("Expected the stream to fail")
        } catch {
            XCTAssertEqual(error as? ServerSentEventsError, .unacceptableStatusCode(503))
        }
    }

    private func makeClient() -> ServerSentEventsClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServerSentEventsURLProtocol.self]

        return ServerSentEventsClient(
            client: URLSessionClient(
                sessionConfiguration: configuration,
                callbackQueue: nil
            )
        )
    }
}

private final class ServerSentEventsURLProtocol: URLProtocol {
    struct StubResponse: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let chunks: [Data]
    }

    private struct State {
        var response: StubResponse?
        var lastRequestHeaders: [String: String]?
    }

    private static let state = Mutex(State())

    static func setResponse(_ response: StubResponse) {
        state.withLock {
            $0.response = response
            $0.lastRequestHeaders = nil
        }
    }

    static func lastRequestHeaders() -> [String: String]? {
        state.withLock { $0.lastRequestHeaders }
    }

    static func reset() {
        state.withLock {
            $0.response = nil
            $0.lastRequestHeaders = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let stubResponse = Self.state.withLock { state in
            state.lastRequestHeaders = request.allHTTPHeaderFields
            return state.response
        }

        guard let stubResponse,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: stubResponse.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: stubResponse.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        for chunk in stubResponse.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension Dictionary where Key == String, Value == String {
    func value(forHTTPHeaderField headerField: String) -> String? {
        first { key, _ in
            key.caseInsensitiveCompare(headerField) == .orderedSame
        }?.value
    }
}
