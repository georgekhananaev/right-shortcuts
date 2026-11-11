import Foundation

/// Lets the interface stop a long file operation that is running on another thread.
public final class OperationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.withLock { cancelled = true }
    }

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func checkCancelled() throws {
        if isCancelled { throw CancellationError() }
    }
}
