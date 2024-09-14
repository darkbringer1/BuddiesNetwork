import Foundation

public class NetworkFetchInterceptor: Interceptor {
    public var id: String = UUID().uuidString

    @Atomic var currentTask: URLSessionTask?

    let client: URLSessionClient

    public init(client: URLSessionClient) {
        self.client = client
    }

    public func intercept<Request>(
        chain: RequestChain,
        request: HTTPRequest<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping (Result<Request.Data, Error>) -> Void
    ) where Request: Requestable {
        let urlRequest: URLRequest

        do {
            urlRequest = try request.toUrlRequest()
        } catch {
            chain.handleErrorAsync(
                error,
                request: request,
                response: response,
                completion: completion
            )
            return
        }

        let task = client.sendRequest(urlRequest) { [weak self] result in
            guard let self else { return }

            guard !chain.isCancelled else {
                return
            }

            switch result {
            case let .success((data, rawResponse)):
                let httpResponse = HTTPResponse<Request>(
                    httpResponse: rawResponse,
                    rawData: data
                )

                chain.proceed(
                    request: request,
                    interceptor: self,
                    response: httpResponse,
                    completion: completion
                )
            case let .failure(error):
                chain.handleErrorAsync(
                    error,
                    request: request,
                    response: response,
                    completion: completion
                )
            }
        }

        $currentTask.mutate { $0 = task }
    }

    public func cancel() {
        guard let task = currentTask else {
            return
        }

        task.cancel()
    }
}
