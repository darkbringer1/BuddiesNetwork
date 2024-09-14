import Foundation

public class TaskData {
    public let completionBlock: URLSessionClient.Completion
    private(set) var data: Data = Data()
    private(set) var response: HTTPURLResponse?

    init(completionBlock: @escaping URLSessionClient.Completion) {
        self.completionBlock = completionBlock
    }

    func append(additionalData: Data) {
        data.append(additionalData)
    }

    func reset(data: Data?) {
        guard let data, !data.isEmpty else {
            self.data = Data()
            return
        }

        self.data = data
    }

    func setData(_ data: Data) {
        self.data = data
    }

    func responseReceived(response: URLResponse) {
        if let httpResponse = response as? HTTPURLResponse {
            self.response = httpResponse
        }
    }
}
