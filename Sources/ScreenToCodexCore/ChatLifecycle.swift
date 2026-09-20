/// Serializes opening and disposal so application termination can await both.
@MainActor public final class ChatLifecycle {
  private var opening: Task<Void, Never>?
  private var cleanup: Task<Void, Never>?
  public private(set) var isTerminating = false
  public var isBusy: Bool { opening != nil || cleanup != nil }

  public init() {}

  public func open(_ operation: @escaping @MainActor () async -> Void) {
    guard !isBusy, !isTerminating else { return }
    opening = Task {
      await operation()
      opening = nil
    }
  }

  public func close(_ operation: @escaping @MainActor () async -> Void) {
    guard cleanup == nil else { return }
    cleanup = Task {
      await operation()
      cleanup = nil
    }
  }

  public func shutdown(_ closeActiveChat: @MainActor () async -> Void) async {
    isTerminating = true
    await opening?.value
    await cleanup?.value
    await closeActiveChat()
  }
}
