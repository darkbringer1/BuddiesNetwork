import Foundation
import Synchronization

public final class JSONDecodingInterceptor: Interceptor {
    enum JSONDecodingError: Error, LocalizedError {
        case responseNotFound

        var errorDescription: String? {
            switch self {
            case .responseNotFound: "There is no response found to decode."
            }
        }
    }

    public let id: String = UUID().uuidString

    private let decoder: Mutex<JSONDecoder>

    public init(decoder: JSONDecoder = .init()) {
        self.decoder = Mutex(decoder)
    }

    public func intercept<Request>(
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard var createdResponse = response else {
            chain.handleErrorAsync(
                JSONDecodingError.responseNotFound,
                operation: operation,
                response: response,
                completion: completion
            )
            return
        }

        do {
            let data = try decoder.withLock {
                try $0.decode(Request.Data.self, from: createdResponse.rawData)
            }

            createdResponse.parsedData = data

            chain.proceed(
                operation: operation,
                interceptor: self,
                response: createdResponse,
                completion: completion
            )
        } catch {
            chain.handleErrorAsync(
                error,
                operation: operation,
                response: response,
                completion: completion
            )
            return
        }
    }
}
