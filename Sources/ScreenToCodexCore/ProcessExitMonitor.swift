import Foundation

@MainActor public final class ProcessExitMonitor {
  public enum Outcome { case exited, timedOut }
  private let source: DispatchSourceProcess
  private var deadline: DispatchWorkItem?
  private var completion: ((Outcome) -> Void)?

  public init(pid: pid_t, timeout: TimeInterval, completion: @escaping (Outcome) -> Void) {
    self.completion = completion
    source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    source.setEventHandler { [weak self] in self?.finish(.exited) }
    let deadline = DispatchWorkItem { [weak self] in self?.finish(.timedOut) }
    self.deadline = deadline
    source.resume()
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: deadline)
    // Cover a parent that exited before the event source was registered.
    if kill(pid, 0) != 0 && errno == ESRCH {
      DispatchQueue.main.async { [weak self] in self?.finish(.exited) }
    }
  }

  public func cancel() {
    completion = nil
    source.cancel()
    deadline?.cancel()
    deadline = nil
  }

  private func finish(_ outcome: Outcome) {
    let callback = completion
    cancel()
    callback?(outcome)
  }
}
