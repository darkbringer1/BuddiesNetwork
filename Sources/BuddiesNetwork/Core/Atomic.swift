import Synchronization

/// Wrapper for a value protected by Swift's standard `Mutex`.
@propertyWrapper
public final class Atomic<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    /// Designated initializer
    ///
    /// - Parameter value: The value to begin with.
    public init(wrappedValue: Value) {
        storage = Mutex(wrappedValue)
    }

    /// The current value. Read-only. To update the underlying value, use ``mutate(block:)``.
    ///
    /// Allowing the ``wrappedValue`` to be set using a setter can cause concurrency issues when
    /// mutating the value of a wrapped value type such as an `Array`. This is due to the copying of
    /// value types as described in [this article](https://www.donnywals.com/why-your-atomic-property-wrapper-doesnt-work-for-collection-types/).
    public var wrappedValue: Value {
        storage.withLock { $0 }
    }

    public var projectedValue: Atomic { self }

    /// Mutates the underlying value within a lock.
    ///
    /// - Parameter block: The block executed to mutate the value.
    /// - Returns: The value returned by the block.
    public func mutate<Result: Sendable>(
        block: (inout sending Value) throws -> sending Result
    ) rethrows -> sending Result {
        try storage.withLock {
            try block(&$0)
        }
    }
}
