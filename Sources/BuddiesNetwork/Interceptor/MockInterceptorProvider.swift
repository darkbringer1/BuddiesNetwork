import Foundation
import OSLog

private let logger = Logger(subsystem: "BuddiesNetwork", category: "network-request")

public final class MockInterceptorProvider: InterceptorProvider {

    public let responseDelaySeconds: ClosedRange<Int>

    public init(responseDelaySeconds: ClosedRange<Int> = 1 ... 2) {
        self.responseDelaySeconds = responseDelaySeconds
    }

    public final class MockInterceptor: Interceptor {
        public var id: String = UUID().uuidString

        private let responseDelaySeconds: ClosedRange<Int>

        init(responseDelaySeconds: ClosedRange<Int>) {
            self.responseDelaySeconds = responseDelaySeconds
        }

        enum MockError: LocalizedError {
            case notMockableType(any Requestable)

            var errorDescription: String? {
                switch self {
                case .notMockableType(let request):
                    "Request type is not mockable: \(request)"
                }
            }
        }

        public func intercept<Request>(
            chain: RequestChain,
            operation: HTTPOperation<Request>,
            response: HTTPResponse<Request>?,
            completion: @escaping HTTPResultHandler<Request>
        ) where Request: Requestable {
            guard let mockableRequest = operation.rawRequest as? any Mockable else {
                let error = MockError.notMockableType(operation.rawRequest)
                logger.error("\(#function): \(error.localizedDescription)")
                chain.handleErrorAsync(
                    error,
                    operation: operation,
                    response: response,
                    completion: completion
                )
                return
            }

            let url = operation.properties.url
            let randomSleep = Int.random(in: responseDelaySeconds)

            guard let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ) else {
                return
            }

            let mockResponse = HTTPResponse<Request>(
                httpResponse: httpResponse,
                rawData: Data()
            )

            mockResponse.parsedData = mockableRequest.erasedMockData as? Request.Data

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(randomSleep)) {
                chain.proceed(
                    operation: operation,
                    interceptor: self,
                    response: mockResponse,
                    completion: completion
                )
            }
        }
    }

    public func interceptors<Request: Requestable>(for operation: HTTPOperation<Request>) -> [any Interceptor] {
        [
            MockInterceptor(responseDelaySeconds: responseDelaySeconds)
        ]
    }
}
