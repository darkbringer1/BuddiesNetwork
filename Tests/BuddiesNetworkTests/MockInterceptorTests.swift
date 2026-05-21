import XCTest
@testable import BuddiesNetwork

private struct LoginRequest: Requestable, Mockable {
    let email: String

    struct User: Decodable, Equatable {
        let id: Int
        let name: String
        let email: String
    }

    struct Data: Decodable, Equatable {
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

final class MockInterceptorTests: XCTestCase {
    func testMockInterceptorReturnsMockData() async throws {
        let transport = DefaultRequestChainNetworkTransport(
            interceptorProvider: MockInterceptorProvider(responseDelaySeconds: 0 ... 0)
        )
        let client = APIClient(networkTransporter: transport)

        let response = try await client.perform(LoginRequest(email: "test@example.com"))

        XCTAssertEqual(
            response,
            LoginRequest.Data(
                user: .init(id: 123, name: "Can Yoldas", email: "test@example.com")
            )
        )
    }

    func testNonMockableRequestFails() async {
        let transport = DefaultRequestChainNetworkTransport(
            interceptorProvider: MockInterceptorProvider(responseDelaySeconds: 0 ... 0)
        )
        let client = APIClient(networkTransporter: transport)

        do {
            _ = try await client.perform(MapRequestable(id: "1"))
            XCTFail("Expected mock interceptor to reject non-mockable requests")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("not mockable"))
        }
    }
}
