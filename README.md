# BuddiesNetwork

A lightweight, interceptor-driven HTTP networking library for Swift. It offers a composable request pipeline, clean request modeling via `Requestable`, and first-class async/await and callback APIs. Inspired in part by chain-based designs like Apollo's interceptor chain.


## Features
- **Composable interceptor chain**: Plug in retry, auth token, decoding, logging, etc.
- **Modern Swift APIs**: Async/await or callback-based completion.
- **Strong typing**: Each request declares its expected response `Data` type.
- **URLSession-backed**: A thin, testable wrapper around `URLSession`.
- **Encoding helpers**: Automatic URL or JSON encoding of `Encodable` requests.
- **Server-Sent Events**: Stream `text/event-stream` responses as typed `ServerSentEvent` values.
- **WebSockets**: Open bidirectional connections with async streams or callbacks, text/binary messages, ping, and close support.


## Requirements
- iOS 18+, macOS 15+
- Swift 6.0+
- Swift 6 language mode


## Installation
Add BuddiesNetwork to your `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [.iOS(.v18), .macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/your-org/BuddiesNetwork.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "YourApp",
            dependencies: [
                .product(name: "BuddiesNetwork", package: "BuddiesNetwork")
            ]
        )
    ]
)
```

Or add the URL in Xcode > Package Dependencies.


## Quickstart

### 1) Define a Request
Conform to `Requestable`. You specify the response `Data` type and return HTTP properties (URL, method, headers, payload):

```swift
import BuddiesNetwork

struct GetUserRequest: Requestable {
    struct Data: Decodable, Sendable { let id: String; let name: String }

    let userId: String

    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: URL(string: "https://api.example.com/v1/users/\(userId)")!,
            httpMethod: .get,
            additionalHeaders: [:],
            data: self // Encoded as URL query for GET, JSON for POST/PUT
        )
    }
}
```

Notes:
- `Requestable` conforms to `Sendable`, and `Requestable.Data` must be `Decodable & Sendable`.
- `data` is any `Encodable & Sendable`. Encoding strategy is automatic:
  - `.get` → URL query params
  - `.post`/`.put` → JSON body
- `additionalHeaders` merges into request headers (e.g., custom content types).

### 2) Perform the Request (async/await)
```swift
let client = APIClient(networkTransporter: DefaultRequestChainNetworkTransport(
    interceptorProvider: DefaultInterceptorProvider(client: URLSessionClient(sessionConfiguration: .default))
))

let user = try await client.perform(GetUserRequest(userId: "42"))
print(user.name)
```

### 3) Or use the Callback API
```swift
let cancellable = client.perform(GetUserRequest(userId: "42")) { result in
    switch result {
    case .success(let httpResult):
        print(httpResult.data)
    case .failure(let error):
        print(error)
    }
}

// If you implement your own chain that returns a cancellable, keep the token to cancel.
_ = cancellable
```

## Server-Sent Events

Use `ServerSentEventsClient` for endpoints that return `text/event-stream`. SSE requests still use the existing `Requestable` shape so URL, method, headers, and encoding stay consistent with normal HTTP calls.

```swift
struct EventsRequest: Requestable {
    struct Data: Decodable, Sendable {}

    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: URL(string: "https://api.example.com/v1/events")!,
            httpMethod: .get
        )
    }
}

let sseClient = ServerSentEventsClient(
    client: URLSessionClient(sessionConfiguration: .default),
    additionalHeaders: {
        ["Authorization": "Bearer \(accessToken)"]
    }
)

for try await event in sseClient.events(for: EventsRequest()) {
    print(event.id, event.event, event.data)
}
```

You can also make SSE part of your app-facing `APIClient`:

```swift
let apiClient = APIClient(
    networkTransporter: transport,
    serverSentEventsClient: sseClient
)

for try await event in apiClient.serverSentEvents(for: EventsRequest()) {
    print(event.data)
}
```

The client automatically sends `accept: text/event-stream`, validates `2xx` responses by default, parses standard SSE fields (`id`, `event`, `data`, `retry`), and supports callback-style consumption:

```swift
let cancellable = apiClient.connectServerSentEvents(EventsRequest()) { event in
    print(event.data)
} completion: { result in
    print(result)
}

_ = cancellable
```

## WebSockets

WebSocket handshakes reuse `Requestable` and `URLProvider`, so endpoint URLs, request headers, query encoding, and dynamically supplied authentication headers follow the same path as HTTP and SSE requests.

```swift
struct ChatSocketRequest: Requestable {
    struct Data: Decodable, Sendable {}

    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: URL(string: "wss://api.example.com/v1/chat")!,
            httpMethod: .get,
            additionalHeaders: ["Sec-WebSocket-Protocol": "chat.v1"]
        )
    }
}

let webSocketClient = WebSocketClient(
    client: URLSessionClient(sessionConfiguration: .default),
    additionalHeaders: {
        ["Authorization": "Bearer \(accessToken)"]
    }
)

let apiClient = APIClient(
    networkTransporter: transport,
    webSocketClient: webSocketClient
)
let connection = try apiClient.webSocketConnection(
    for: ChatSocketRequest()
)

let incomingMessages = Task {
    for try await message in connection.messages {
        switch message {
        case let .text(text):
            print(text)
        case let .data(data):
            print(data)
        }
    }
}

try await connection.send(.text("Hello"))
try await connection.ping()
connection.close(code: .normalClosure)
try await incomingMessages.value
```

The callback API returns the same `WebSocketConnection`; retain it while the socket should stay open and use it to send or close:

```swift
let connection = apiClient.connectWebSocket(
    ChatSocketRequest(),
    onMessage: { message in
        print(message)
    },
    completion: { result in
        print(result)
    }
)

connection?.send(.text("Hello")) { result in
    print(result)
}
```

Incoming messages use a bounded newest-100 buffer by default. If the consumer falls behind far enough to drop a message, the framework closes the connection with a policy-violation code and fails the stream with `WebSocketError.messageBufferOverflow`. Pass a different `WebSocketBufferingPolicy` when creating the connection if your endpoint needs another limit.

Handshake URLs must use `ws` or `wss`. Normal and going-away closes finish the message stream; other close codes fail it with `WebSocketError.connectionClosed`, preserving the close code and reason.


## Architecture
### Diagram 
``` mermaid 
flowchart TD

subgraph group_public["Public API"]
  node_package["Swift package<br/>module entry<br/>[Package.swift]"]
  node_api_client["APIClient<br/>public facade<br/>[APIClient.swift]"]
  node_request_model["Requestable &amp; operation<br/>typed HTTP model<br/>[HTTPRequest.swift]"]
  node_http_response["HTTPResponse<br/>result model<br/>[HTTPResponse.swift]"]
end

subgraph group_http["HTTP pipeline"]
  node_default_transport["Default transport<br/>chain transport"]
  node_intercept_chain["Network intercept chain<br/>pipeline executor"]
  node_default_provider["Default interceptor provider<br/>pipeline composition"]
  node_url_provider["URLProvider<br/>request builder<br/>[URLProvider.swift]"]
  node_parameter_encoding["Parameter encoding<br/>serialization boundary"]
  node_urlsession_client["URLSessionClient<br/>Apple transport adapter"]
  node_authenticated_provider["Authenticated provider<br/>authenticated composition"]
  node_auth_error_handler["Authentication error handler<br/>failure policy"]
end

subgraph group_streaming["Streaming"]
  node_sse_client["SSE client<br/>event-stream client"]
  node_sse_parser["SSE parser<br/>incremental parser"]
  node_websocket_connection["WebSocket connection<br/>socket runtime"]
end

subgraph group_extension["Extension points"]
  node_interceptor_protocol["Interceptor protocol<br/>pipeline extension<br/>[Interceptor.swift]"]
  node_mock_provider["Mock interceptor provider<br/>offline composition"]
  node_websocket_task["WebSocket task protocol<br/>task boundary"]
end

node_package -->|"exports"| node_api_client
node_api_client -->|"accepts"| node_request_model
node_api_client -->|"delegates HTTP"| node_default_transport
node_default_transport -->|"creates"| node_intercept_chain
node_default_transport -->|"uses"| node_default_provider
node_default_provider -->|"supplies ordered stages"| node_intercept_chain
node_intercept_chain -->|"builds request"| node_url_provider
node_url_provider -->|"encodes parameters"| node_parameter_encoding
node_intercept_chain -->|"fetches through"| node_urlsession_client
node_intercept_chain -->|"completes with"| node_http_response
node_authenticated_provider -.->|"extends pipeline"| node_default_provider
node_authenticated_provider -->|"uses on 401"| node_auth_error_handler
node_interceptor_protocol -.->|"defines stages"| node_default_provider
node_mock_provider -.->|"injects alternative pipeline"| node_default_transport
node_sse_client -->|"reuses operation"| node_request_model
node_sse_client -->|"builds request"| node_url_provider
node_sse_client -->|"streams through"| node_urlsession_client
node_sse_client -->|"parses chunks"| node_sse_parser
node_websocket_connection -->|"reuses handshake construction"| node_url_provider
node_websocket_connection -->|"abstracts task"| node_websocket_task

click node_package "https://github.com/darkbringer1/buddiesnetwork/blob/main/Package.swift"
click node_api_client "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Client/APIClient.swift"
click node_request_model "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/HTTP/HTTPRequest.swift"
click node_http_response "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/HTTP/HTTPResponse.swift"
click node_default_transport "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Interceptor/DefaultNetworkTransport.swift"
click node_intercept_chain "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Interceptor/NetworkInterceptChain.swift"
click node_default_provider "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Interceptor/DefaultInterceptorProvider.swift"
click node_url_provider "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/RequestEncoding/URLProvider.swift"
click node_parameter_encoding "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/RequestEncoding/ParameterEncoding.swift"
click node_urlsession_client "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Client/URLSessionClient.swift"
click node_authenticated_provider "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Interceptor/AuthenticatedInterceptorProvider.swift"
click node_auth_error_handler "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Interceptor/AuthenticationErrorHandler.swift"
click node_sse_client "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/SSE/ServerSentEventsClient.swift"
click node_sse_parser "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/SSE/ServerSentEventParser.swift"
click node_websocket_connection "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/WebSocket/WebSocketConnection.swift"
click node_interceptor_protocol "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Interceptor/Protocols/Interceptor.swift"
click node_mock_provider "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/Interceptor/MockInterceptorProvider.swift"
click node_websocket_task "https://github.com/darkbringer1/buddiesnetwork/blob/main/Sources/BuddiesNetwork/WebSocket/WebSocketTaskProtocol.swift"

classDef toneNeutral fill:#f8fafc,stroke:#334155,stroke-width:1.5px,color:#0f172a
classDef toneBlue fill:#dbeafe,stroke:#2563eb,stroke-width:1.5px,color:#172554
classDef toneAmber fill:#fef3c7,stroke:#d97706,stroke-width:1.5px,color:#78350f
classDef toneMint fill:#dcfce7,stroke:#16a34a,stroke-width:1.5px,color:#14532d
classDef toneRose fill:#ffe4e6,stroke:#e11d48,stroke-width:1.5px,color:#881337
classDef toneIndigo fill:#e0e7ff,stroke:#4f46e5,stroke-width:1.5px,color:#312e81
classDef toneTeal fill:#ccfbf1,stroke:#0f766e,stroke-width:1.5px,color:#134e4a
class node_package,node_api_client,node_request_model,node_http_response toneBlue
class node_default_transport,node_intercept_chain,node_default_provider,node_url_provider,node_parameter_encoding,node_urlsession_client,node_authenticated_provider,node_auth_error_handler toneAmber
class node_sse_client,node_sse_parser,node_websocket_connection toneMint
class node_interceptor_protocol,node_mock_provider,node_websocket_task toneRose
```
### Details
- `APIClient`: High-level facade. Delegates to a `NetworkTransportProtocol` to execute requests.
- `DefaultRequestChainNetworkTransport`: Implements a chain-of-responsibility request pipeline using `RequestChain`.
- `RequestChain`/`NetworkInterceptChain`: Drives interceptors, retries, error handling, and completion dispatch.
- `Interceptor`: Units of work (e.g., retry, fetch, decode). Interceptors can be cancellable.
- `URLSessionClient`: Minimal final wrapper over `URLSession` with synchronized task bookkeeping.
- `Requestable`: A `Sendable` request model (`Encodable`) with an associated `Data: Decodable & Sendable` response.
- `HTTPOperation`: Holds request metadata (URL, method, headers, payload) and cache policy, with mutable headers synchronized for interceptor use.
- `HTTPResponse`: A Sendable value type containing the raw `HTTPURLResponse`, raw `Data`, and decoded `parsedData`.
- `ServerSentEventsClient`: Streaming facade for SSE endpoints. It reuses `Requestable`/`HTTPOperation` request construction and receives incremental chunks through `URLSessionClient`.
- `WebSocketClient`: Builds WebSocket handshakes through `Requestable`/`HTTPOperation` and creates live `WebSocketConnection` values.
- `WebSocketConnection`: Owns the receive stream, text/binary sends, ping, close state, bounded buffering, and cancellation.
- `WebSocketTaskProvider`/`WebSocketTaskProtocol`: Injectable URLSession task boundaries for deterministic WebSocket tests.

Default interceptor pipeline provided by `DefaultInterceptorProvider`:
1. `MaxRetryInterceptor(maxRetry: 3)`
2. `NetworkFetchInterceptor` (builds `URLRequest` via `URLProvider`, executes with `URLSessionClient`)
3. `JSONDecodingInterceptor` (decodes to `Request.Data`)


## Interceptors and Customization

Create your own interceptor by conforming to `Interceptor`:
```swift
final class LoggingInterceptor: Interceptor {
    let id = UUID().uuidString

    func intercept<Request>(
        chain: any RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request : Requestable {
        print("➡️ Request: \(operation.properties.requestName) \(operation.properties.httpMethod)")
        chain.proceed(operation: operation, interceptor: self, response: response, completion: completion)
    }
}
```

Provide a custom `InterceptorProvider` to control the chain:
```swift
struct MyProvider: InterceptorProvider {
    let client: URLSessionClient

    func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [any Interceptor] {
        [
            LoggingInterceptor(),
            MaxRetryInterceptor(maxRetry: 2),
            NetworkFetchInterceptor(client: client),
            JSONDecodingInterceptor()
        ]
    }
}

let transport = DefaultRequestChainNetworkTransport(interceptorProvider: MyProvider(client: URLSessionClient(sessionConfiguration: .default)))
let client = APIClient(networkTransporter: transport)
```

You can also inject an `errorHandler` via `additionalErrorHandler(for:)` to centralize error mapping and retries.


## Request Encoding and Headers

`URLProvider` builds `URLRequest` from `HTTPOperation.HTTPProperties`:
- Headers: starts with `Accept: application/json`; merges `additionalHeaders`.
- Encoding:
  - `.get`: URL query (`URLParameterEncoder`)
  - `.post`/`.put`: JSON body (`JSONParameterEncoder`, sets `Content-Type: application/json` if missing)
- Add custom headers per-request with `operation.addHeader(key:val:)` in interceptors like auth token injection.


## Authentication Example

Use `AuthenticatedInterceptorProvider` for a production stack (retry, bearer token, fetch, HTTP status check, JSON decode) plus centralized 401 handling:

```swift
let transport = DefaultRequestChainNetworkTransport(
    interceptorProvider: AuthenticatedInterceptorProvider(
        client: URLSessionClient(sessionConfiguration: .default),
        accessToken: { Current.session?.accessToken },
        onUnauthorized: { @MainActor in
            await Authenticator.shared.logout()
        }
    )
)
let client = APIClient(networkTransporter: transport)
```

Pipeline order matches a typical app setup:
1. `MaxRetryInterceptor(maxRetry: 3)`
2. `TokenProviderInterceptor`
3. `NetworkFetchInterceptor`
4. `HTTPStatusCheckerInterceptor`
5. `JSONDecodingInterceptor`

`AuthenticationErrorHandler` runs on chain errors; when the response status is `401`, it invokes `onUnauthorized`, cancels the chain, and fails the request.

For manual composition, use `TokenProviderInterceptor` directly:

```swift
let tokenInterceptor = TokenProviderInterceptor { Current.session?.accessToken }

struct ProviderWithToken: InterceptorProvider {
    let client: URLSessionClient
    func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [any Interceptor] {
        [
            tokenInterceptor,
            NetworkFetchInterceptor(client: client),
            HTTPStatusCheckerInterceptor(),
            JSONDecodingInterceptor()
        ]
    }
}
```


## Cancellation and Concurrency
- Chains and some interceptors implement `Cancellable`. If your transport returns a cancellable token, keep and cancel it as needed.
- BuddiesNetwork builds in Swift 6 language mode and exposes Sendable-safe APIs.
- Request, response, result, header, method, transport, provider, interceptor, and cancellable boundaries are Sendable.
- Mutable request-chain state is synchronized with Swift's `Synchronization.Mutex`; the package does not rely on `@unchecked Sendable`.
- Completion handlers and token providers are `@Sendable`. Authentication unauthorized handlers are `@MainActor @Sendable`.
- Async/await API:
  - `try await client.perform(request)` returns `Request.Data`.
  - `try apiClient.webSocketConnection(for:)` returns a connection whose messages are an `AsyncThrowingStream`.
- Callback API:
  - `client.perform(request, completion:)` yields `Result<HTTPResult<Request>, any Error>`; access `httpResult.data` for the decoded payload.
  - `apiClient.connectWebSocket(request, onMessage:completion:)` returns a `WebSocketConnection` for sending and cancellation.


## Cache Policy
`CachePolicy` is carried on `HTTPOperation` and forwarded through the chain. The default transport does not implement a cache store yet. You can implement caching by adding interceptors for cache lookup/store and by setting appropriate policies:
- `.returnCacheDataElseFetch`
- `.fetchIgnoringCacheData`
- `.fetchIgnoringCacheCompletely`
- `.returnCacheDataDontFetch`
- `.returnCacheDataAndFetch`


## EncoderIgnorable
Use `@EncoderIgnorable` on `Requestable` properties that should not be encoded as parameters but may still be used to construct the URL path:
```swift
struct CityRequest: Requestable {
    @EncoderIgnorable var countryCode: String
    let subway: Bool

    struct Data: Decodable, Sendable { /* ... */ }

    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: URL(string: "https://api.example.com/v2/cities/\(countryCode)")!,
            httpMethod: .get,
            data: self
        )
    }
}
```


## Error Handling
Common errors are surfaced as `NetworkError` (e.g., `encodingFailed`, `missingURL`). You can map or recover from errors centrally by providing a custom `ChainErrorHandler` in your `InterceptorProvider`.


## Mocking (Offline / UI Development)

Use `MockInterceptorProvider` instead of `DefaultInterceptorProvider` to short-circuit the network and return fixture data from your requests.

### 1) Conform your request to `Mockable`

```swift
struct LoginRequest: Requestable, Mockable {
    let email: String

    struct Data: Decodable, Sendable {
        struct User: Decodable, Sendable {
            let id: Int
            let name: String
            let email: String
        }
        let user: User?
    }

    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: URL(string: "https://api.example.com/v1/login")!,
            httpMethod: .post,
            data: self
        )
    }

    func mock() -> Self.Data {
        .init(
            user: .init(
                id: 123,
                name: "Can Yoldas",
                email: email
            )
        )
    }
}
```

### 2) Wire the mock provider

```swift
let transport = DefaultRequestChainNetworkTransport(
    interceptorProvider: MockInterceptorProvider(responseDelaySeconds: 1 ... 2)
)
let client = APIClient(networkTransporter: transport)

let login = try await client.perform(LoginRequest(email: "dev@example.com"))
```

Requests that do not conform to `Mockable` fail the chain with a descriptive error. Optional `responseDelaySeconds` simulates network latency (default `1...2` seconds).


## Testing Tips
- Use `MockInterceptorProvider` for deterministic fixture responses without hitting the network.
- Inject a custom `InterceptorProvider` that uses a stub interceptor to return fixture data without hitting the network.
- Inject a custom `NetworkTransportProtocol` or interceptor to simulate errors, delays, cancellation, or decoding behavior.


## License
MIT. See the LICENSE file if provided. Credits to Can Yoldas for inspiration.
