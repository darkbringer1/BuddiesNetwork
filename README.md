# BuddiesNetwork

A lightweight, interceptor-driven HTTP networking library for Swift. It offers a composable request pipeline, clean request modeling via `Requestable`, and first-class async/await and callback APIs. Inspired in part by chain-based designs like Apollo's interceptor chain.


## Features
- **Composable interceptor chain**: Plug in retry, auth token, decoding, logging, etc.
- **Modern Swift APIs**: Async/await or callback-based completion.
- **Strong typing**: Each request declares its expected response `Data` type.
- **URLSession-backed**: A thin, testable wrapper around `URLSession`.
- **Encoding helpers**: Automatic URL or JSON encoding of `Encodable` requests.


## Requirements
- iOS 17+, macOS 14+
- Swift 5.10+


## Installation
Add BuddiesNetwork to your `Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
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
    struct Data: Decodable { let id: String; let name: String }

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
- `data` is any `Encodable`. Encoding strategy is automatic:
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


## Architecture

- `APIClient`: High-level facade. Delegates to a `NetworkTransportProtocol` to execute requests.
- `DefaultRequestChainNetworkTransport`: Implements a chain-of-responsibility request pipeline using `RequestChain`.
- `RequestChain`/`NetworkInterceptChain`: Drives interceptors, retries, error handling, and completion dispatch.
- `Interceptor`: Units of work (e.g., retry, fetch, decode). Interceptors can be cancellable.
- `URLSessionClient`: Minimal wrapper over `URLSession` with task bookkeeping.
- `Requestable`: A request model (Encodable) with an associated `Data: Decodable` response.
- `HTTPOperation`: Holds request metadata (URL, method, headers, payload) and cache policy.
- `HTTPResponse`: Captures the raw `HTTPURLResponse`, raw `Data`, and decoded `parsedData`.

Default interceptor pipeline provided by `DefaultInterceptorProvider`:
1. `MaxRetryInterceptor(maxRetry: 3)`
2. `NetworkFetchInterceptor` (builds `URLRequest` via `URLProvider`, executes with `URLSessionClient`)
3. `JSONDecodingInterceptor` (decodes to `Request.Data`)


## Interceptors and Customization

Create your own interceptor by conforming to `Interceptor`:
```swift
final class LoggingInterceptor: Interceptor {
    var id = UUID().uuidString

    func intercept<Request>(
        chain: RequestChain,
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

    func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [Interceptor] {
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

Use `TokenProviderInterceptor` to attach a bearer token when available:
```swift
let tokenInterceptor = TokenProviderInterceptor { Current.session?.accessToken }

struct ProviderWithToken: InterceptorProvider {
    let client: URLSessionClient
    func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [Interceptor] {
        [
            tokenInterceptor,
            NetworkFetchInterceptor(client: client),
            JSONDecodingInterceptor()
        ]
    }
}
```


## Cancellation and Concurrency
- Chains and some interceptors implement `Cancellable`. If your transport returns a cancellable token, keep and cancel it as needed.
- Async/await API:
  - `try await client.perform(request)` returns `Request.Data`.
- Callback API:
  - `client.perform(request, completion:)` yields `Result<HTTPResult<Request>, Error>`; access `httpResult.data` for the decoded payload.


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

    struct Data: Decodable { /* ... */ }

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


## Testing Tips
- Inject a custom `InterceptorProvider` that uses a stub interceptor to return fixture data without hitting the network.
- Replace `URLSessionClient` with a specialized client to simulate errors, delays, or data races.


## License
MIT. See the LICENSE file if provided. Credits to Can Yoldas for inspiration.
