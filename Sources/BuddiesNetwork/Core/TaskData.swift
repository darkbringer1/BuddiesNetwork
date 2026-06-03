import Foundation
import Synchronization

public final class TaskData: Sendable {
    private struct State {
        var data = Data()
        var response: HTTPURLResponse?
    }

    public let completionBlock: URLSessionClient.Completion
    private let state = Mutex(State())

    init(completionBlock: @escaping URLSessionClient.Completion) {
        self.completionBlock = completionBlock
    }

    var data: Data {
        state.withLock { $0.data }
    }

    var response: HTTPURLResponse? {
        state.withLock { $0.response }
    }

    func append(additionalData: Data) {
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
}
