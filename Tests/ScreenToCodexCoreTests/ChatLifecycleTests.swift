import Foundation
import Testing

@testable import ScreenToCodexCore

@MainActor private final class Pause {
  private var continuation: CheckedContinuation<Void, Never>?
  var started = false
  func wait() async {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      started = true
    }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}

@Test @MainActor func chatOpeningIsReservedBeforeAsyncWork() async {
  let lifecycle = ChatLifecycle()
  let pause = Pause()
  var installed = 0
  lifecycle.open {
    await pause.wait()
    installed += 1
  }
  lifecycle.open { installed += 1 }
  while !pause.started { await Task.yield() }
  pause.release()
  await lifecycle.shutdown {}
  #expect(installed == 1)
}

@Test @MainActor func quitWaitsForPendingChatCleanup() async throws {
  let root = try TemporaryRoot()
  let session = try CaptureSession(root: root.url)
  _ = try session.writeCapture(Data([1]))
  let lifecycle = ChatLifecycle()
  let pause = Pause()
  var finished = false
  lifecycle.close {
    await pause.wait()
    try? session.close()
  }
  while !pause.started { await Task.yield() }
  let quit = Task {
    await lifecycle.shutdown {}
    finished = true
  }
  while !lifecycle.isTerminating { await Task.yield() }
  #expect(!finished)
  #expect(FileManager.default.fileExists(atPath: session.directory.path))
  pause.release()
  await quit.value
  #expect(!FileManager.default.fileExists(atPath: session.directory.path))
}

@Test @MainActor func quitWaitsForOpeningBeforeClosingActiveChat() async {
  let lifecycle = ChatLifecycle()
  let pause = Pause()
  var order: [String] = []
  lifecycle.open {
    await pause.wait()
    order.append("opened")
  }
  while !pause.started { await Task.yield() }
  let quit = Task { await lifecycle.shutdown { order.append("closed") } }
  while !lifecycle.isTerminating { await Task.yield() }
  lifecycle.open { order.append("unexpected") }
  pause.release()
  await quit.value
  #expect(order == ["opened", "closed"])
}
