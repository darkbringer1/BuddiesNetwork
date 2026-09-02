# BuddiesNetwork

A lightweight, interceptor-driven HTTP networking library for Swift. It offers a composable request pipeline, clean request modeling via `Requestable`, and first-class async/await and callback APIs. Inspired in part by chain-based designs like Apollo's interceptor chain.


## Features
- **Composable interceptor chain**: Plug in retry, auth token, decoding, logging, etc.
- **Modern Swift APIs**: Async/await or callback-based completion.
- **Strong typing**: Each request declares its expected response `Data` type.
- **URLSession-backed**: A thin, testable wrapper around `URLSession`.
- **Encoding helpers**: Automatic URL or JSON encoding of `Encodable` requests.
- **Server-Sent Events**: Stream `text/event-stream` responses as typed `ServerSentEvent` values.


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


## Architecture

- `APIClient`: High-level facade. Delegates to a `NetworkTransportProtocol` to execute requests.
- `DefaultRequestChainNetworkTransport`: Implements a chain-of-responsibility request pipeline using `RequestChain`.
- `RequestChain`/`NetworkInterceptChain`: Drives interceptors, retries, error handling, and completion dispatch.
- `Interceptor`: Units of work (e.g., retry, fetch, decode). Interceptors can be cancellable.
- `URLSessionClient`: Minimal final wrapper over `URLSession` with synchronized task bookkeeping.
- `Requestable`: A `Sendable` request model (`Encodable`) with an associated `Data: Decodable & Sendable` response.
- `HTTPOperation`: Holds request metadata (URL, method, headers, payload) and cache policy, with mutable headers synchronized for interceptor use.
- `HTTPResponse`: A Sendable value type containing the raw `HTTPURLResponse`, raw `Data`, and decoded `parsedData`.
- `ServerSentEventsClient`: Streaming facade for SSE endpoints. It reuses `Requestable`/`HTTPOperation` request construction and receives incremental chunks through `URLSessionClient`.

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
- Callback API:
  - `client.perform(request, completion:)` yields `Result<HTTPResult<Request>, any Error>`; access `httpResult.data` for the decoded payload.


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
