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
        request: HTTPRequest<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable {
        guard let createdResponse = response else {
            chain.handleErrorAsync(
                JSONDecodingError.responseNotFound,
                request: request,
                response: response,
                completion: completion
            )
            return
        }

        do {
            let data = try decoder.decode(Request.Data.self, from: createdResponse.rawData)

            createdResponse.parsedData = data

            chain.proceed(
                request: request,
                interceptor: self,
                response: createdResponse,
                completion: completion
            )
        } catch {
            chain.handleErrorAsync(
                error,
                request: request,
                response: response,
                completion: completion
            )
            return
        }
    }
}
