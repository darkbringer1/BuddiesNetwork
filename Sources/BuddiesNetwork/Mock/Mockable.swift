import Foundation

public protocol Mockable: Requestable {
    func mock() -> Self.Data

    /// Type-erased mock payload for use in the interceptor chain.
    var erasedMockData: Any { get }
}

public extension Mockable {
    var erasedMockData: Any { mock() }
}
