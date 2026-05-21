import XCTest
@testable import BuddiesNetwork

private struct ProfileRequest: Requestable {
    struct Data: Decodable, Equatable {
        let name: String
    }

    func httpProperties() -> HTTPOperation<Self>.HTTPProperties {
        .init(
            url: URL(string: "https://api.example.com/v1/profile")!,
            httpMethod: .get
        )
    }
}

final class AuthenticatedInterceptorTests: XCTestCase {
    func testAuthenticatedProviderIncludesStatusCheckerAndTokenInterceptor() {
        let provider = AuthenticatedInterceptorProvider(
            client: URLSessionClient(sessionConfiguration: .default),
            accessToken: { "token" }
        )

        let interceptors = provider.interceptors(for: HTTPOperation(request: ProfileRequest(), cachePolicy: .default))

        XCTAssertTrue(interceptors.contains { $0 is MaxRetryInterceptor })
        XCTAssertTrue(interceptors.contains { $0 is TokenProviderInterceptor })
        XCTAssertTrue(interceptors.contains { $0 is NetworkFetchInterceptor })
        XCTAssertTrue(interceptors.contains { $0 is HTTPStatusCheckerInterceptor })
        XCTAssertTrue(interceptors.contains { $0 is JSONDecodingInterceptor })
    }

    func testAuthenticatedProviderRegistersAuthenticationErrorHandler() {
        let provider = AuthenticatedInterceptorProvider(
            client: URLSessionClient(sessionConfiguration: .default),
            accessToken: { nil }
        )

        let handler = provider.additionalErrorHandler(for: HTTPOperation(request: ProfileRequest(), cachePolicy: .default))

        XCTAssertTrue(handler is AuthenticationErrorHandler)
    }
}
