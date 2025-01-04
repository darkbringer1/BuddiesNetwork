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
        operation: HTTPOperation<Request>,
        response: HTTPResponse<Request>?,
        completion: @escaping HTTPResultHandler<Request>
    ) where Request: Requestable {
        var urlRequest: URLRequest

        do {
            urlRequest = try URLProvider.urlRequest(from: operation.properties)
        } catch {
            chain.handleErrorAsync(
                error,
                operation: operation,
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
                    operation: operation,
                    interceptor: self,
                    response: httpResponse,
                    completion: completion
                )
            case let .failure(error):
                chain.handleErrorAsync(
                    error,
                    operation: operation,
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
