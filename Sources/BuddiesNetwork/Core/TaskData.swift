import Foundation
import Synchronization

public final class TaskData: Sendable {
    private struct State {
        var data = Data()
        var response: HTTPURLResponse?
        var didComplete = false
    }

    public let completionBlock: URLSessionClient.Completion
    private let streamDataBlock: URLSessionClient.StreamDataHandler?
    private let responseValidator: URLSessionClient.StreamResponseValidator?
    private let streamCompletionBlock: URLSessionClient.StreamCompletion?
    private let state = Mutex(State())

    init(completionBlock: @escaping URLSessionClient.Completion) {
        self.completionBlock = completionBlock
        streamDataBlock = nil
        responseValidator = nil
        streamCompletionBlock = nil
    }

    init(
        streamDataBlock: @escaping URLSessionClient.StreamDataHandler,
        responseValidator: URLSessionClient.StreamResponseValidator?,
        streamCompletionBlock: @escaping URLSessionClient.StreamCompletion
    ) {
        self.completionBlock = { result in
            switch result {
            case let .success((_, response)):
                streamCompletionBlock(.success(response))
            case let .failure(error):
                streamCompletionBlock(.failure(error))
            }
        }
        self.streamDataBlock = streamDataBlock
        self.responseValidator = responseValidator
        self.streamCompletionBlock = streamCompletionBlock
    }

    var data: Data {
        state.withLock { $0.data }
    }

    var response: HTTPURLResponse? {
        state.withLock { $0.response }
    }

    func append(additionalData: Data) {
        if let streamDataBlock {
            let shouldHandleData = state.withLock { !$0.didComplete }

            guard shouldHandleData else {
                return
            }

            streamDataBlock(additionalData)
            return
        }

        state.withLock { $0.data.append(additionalData) }
    }

    func reset(data: Data?) {
        guard let data, !data.isEmpty else {
            state.withLock { $0.data = Data() }
            return
        }

        state.withLock { $0.data = data }
    }

    func setData(_ data: Data) {
        state.withLock { $0.data = data }
    }

    func responseReceived(response: URLResponse) {
        if let httpResponse = response as? HTTPURLResponse {
            state.withLock { $0.response = httpResponse }
        }
    }

    func validationError(for response: HTTPURLResponse) -> (any Error)? {
        responseValidator?(response)
    }

    func complete(with result: Result<(Data, HTTPURLResponse), any Error>) {
        guard markCompleted() else {
            return
        }

        completionBlock(result)
    }

    func completeStream(with result: Result<HTTPURLResponse, any Error>) {
        guard markCompleted() else {
            return
        }

        guard let streamCompletionBlock else {
            switch result {
            case let .success(response):
                completionBlock(.success((Data(), response)))
            case let .failure(error):
                completionBlock(.failure(error))
            }
            return
        }

        streamCompletionBlock(result)
    }

    private func markCompleted() -> Bool {
        state.withLock { state in
            guard !state.didComplete else {
                return false
            }

            state.didComplete = true
            return true
        }
    }
}
