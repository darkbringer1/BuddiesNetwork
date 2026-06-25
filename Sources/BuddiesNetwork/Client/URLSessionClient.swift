import Foundation
import Synchronization

// Delegate callbacks and session lifecycle are synchronized through `state`.
public final class URLSessionClient: NSObject, Sendable, URLSessionDelegate, URLSessionDataDelegate {
    public typealias Completion = @Sendable (Result<(Data, HTTPURLResponse), any Error>) -> Void
    public typealias StreamDataHandler = @Sendable (Data) -> Void
    public typealias StreamResponseValidator = @Sendable (HTTPURLResponse) -> (any Error)?
    public typealias StreamCompletion = @Sendable (Result<HTTPURLResponse, any Error>) -> Void

    private struct State {
        var hasBeenInvalidated = false
        var tasks: [Int: TaskData] = [:]
        var session: URLSession?
    }

    enum URLSessionError: Error, LocalizedError {
        case sessionInvalidated
        case noHttpResponse

        var errorDescription: String? {
            switch self {
            case .sessionInvalidated: "Session is invalidated."
            case .noHttpResponse: "No Http response has been received."
            }
        }
    }

    private let state = Mutex(State())

    public private(set) var session: URLSession! {
        get { state.withLock { $0.session } }
        set { state.withLock { $0.session = newValue } }
    }

    public init(
        sessionConfiguration: URLSessionConfiguration,
        callbackQueue: OperationQueue? = .main
    ) {
        super.init()

        session = URLSession(
            configuration: sessionConfiguration,
            delegate: self,
            delegateQueue: callbackQueue
        )
    }

    @discardableResult
    public func sendRequest(_ request: URLRequest,
                          completion: @escaping Completion) -> URLSessionTask? {
        guard !state.withLock({ $0.hasBeenInvalidated }) else {
            completion(.failure(URLSessionError.sessionInvalidated))
            return nil
        }

        guard let session else {
            completion(.failure(URLSessionError.sessionInvalidated))
            return nil
        }

        let task = session.dataTask(with: request)
        let taskData = TaskData(completionBlock: completion)
        state.withLock { $0.tasks[task.taskIdentifier] = taskData }

        task.resume()
        return task
    }

    @discardableResult
    public func sendStreamingRequest(
        _ request: URLRequest,
        responseValidator: StreamResponseValidator? = nil,
        onData: @escaping StreamDataHandler,
        completion: @escaping StreamCompletion
    ) -> URLSessionTask? {
        guard !state.withLock({ $0.hasBeenInvalidated }) else {
            completion(.failure(URLSessionError.sessionInvalidated))
            return nil
        }

        guard let session else {
            completion(.failure(URLSessionError.sessionInvalidated))
            return nil
        }

        let task = session.dataTask(with: request)
        let taskData = TaskData(
            streamDataBlock: onData,
            responseValidator: responseValidator,
            streamCompletionBlock: completion
        )
        state.withLock { $0.tasks[task.taskIdentifier] = taskData }

        task.resume()
        return task
    }

    public func invalidate() {
        let session = state.withLock {
            $0.hasBeenInvalidated = true
            let session = $0.session
            $0.session = nil
            $0.tasks.removeAll()
            return session
        }

        session?.invalidateAndCancel()
    }

    public func clear(task identifier: Int) {
        state.withLock { _ = $0.tasks.removeValue(forKey: identifier) }
    }

    public func clearAllTasks() {
        state.withLock { $0.tasks.removeAll() }
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard dataTask.state != .canceling else {
            // Task is in the process of cancelling, don't bother handling its data.
            return
        }

        guard let taskData = state.withLock({ $0.tasks[dataTask.taskIdentifier] }) else {
            assertionFailure("No data found for task \(dataTask.taskIdentifier), cannot append received data")
            return
        }

        taskData.append(additionalData: data)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer { self.clear(task: task.taskIdentifier) }

        guard let taskData = state.withLock({ $0.tasks[task.taskIdentifier] }) else {
            // This means that task is already cancelled or cleaned, time to return.
            return
        }

        let finalData = taskData.data
        let finalResponse = taskData.response

        if let error {
            taskData.complete(with: .failure(error))
        } else {
            guard let finalResponse else {
                taskData.complete(with: .failure(URLSessionError.noHttpResponse))
                return
            }

            taskData.complete(with: .success((finalData, finalResponse)))
        }
    }

    public func urlSession(_ session: URLSession,
                         dataTask: URLSessionDataTask,
                         willCacheResponse proposedResponse: CachedURLResponse,
                         completionHandler: @escaping (CachedURLResponse?) -> Void) {
        completionHandler(proposedResponse)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let taskData = state.withLock({ $0.tasks[dataTask.taskIdentifier] }) else {
            completionHandler(.allow)
            return
        }

        taskData.responseReceived(response: response)

        guard let httpResponse = response as? HTTPURLResponse,
              let validationError = taskData.validationError(for: httpResponse) else {
            completionHandler(.allow)
            return
        }

        taskData.completeStream(with: .failure(validationError))
        clear(task: dataTask.taskIdentifier)
        completionHandler(.cancel)
    }
}
