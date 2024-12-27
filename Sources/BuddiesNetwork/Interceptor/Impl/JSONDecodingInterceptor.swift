import Foundation

public class JSONDecodingInterceptor: Interceptor {
    enum JSONDecodingError: Error, LocalizedError {
        case responseNotFound

        var errorDescription: String? {
            switch self {
            case .responseNotFound: "There is no response found to decode."
            }
        }
    }

    public var id: String = UUID().uuidString

    open var decoder: JSONDecoder

    public init(decoder: JSONDecoder = .init()) {
        self.decoder = decoder
    }

    public func intercept<Request>(
        chain: RequestChain,
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        guard let createdResponse = response else {
            chain.handleErrorAsync(
                JSONDecodingError.responseNotFound,
                operation: operation,
                response: response,
                completion: completion
            )
            return
        }

        do {
            let data = try decoder.decode(Request.Data.self, from: createdResponse.rawData)

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
