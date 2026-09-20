import Foundation
import Testing

@testable import ScreenToCodexCore

@Test @MainActor func processExitIsObserved() async throws {
  let child = Process()
  child.executableURL = URL(fileURLWithPath: "/bin/sleep")
  child.arguments = ["0.1"]
  try child.run()
  var monitor: ProcessExitMonitor?
  let result = await withCheckedContinuation { continuation in
    monitor = ProcessExitMonitor(pid: child.processIdentifier, timeout: 2) {
      continuation.resume(returning: $0)
    }
  }
  #expect(result == .exited)
  withExtendedLifetime(monitor) {}
}

@Test @MainActor func processWatchExpiresWithoutRelaunch() async {
  var monitor: ProcessExitMonitor?
  let result = await withCheckedContinuation { continuation in
    monitor = ProcessExitMonitor(pid: ProcessInfo.processInfo.processIdentifier, timeout: 0.01) {
      continuation.resume(returning: $0)
    }
  }
  #expect(result == .timedOut)
  withExtendedLifetime(monitor) {}
}

@Test @MainActor func cancellingProcessWatchSuppressesRecovery() async throws {
  var calls = 0
  let monitor = ProcessExitMonitor(pid: ProcessInfo.processInfo.processIdentifier, timeout: 0.01) {
    _ in calls += 1
  }
  monitor.cancel()
  try await Task.sleep(for: .milliseconds(30))
  #expect(calls == 0)
}

@Test @MainActor func processExitIsDeliveredOnlyOnce() async throws {
  let child = Process()
  child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
  try child.run()
  child.waitUntilExit()
  var calls = 0
  let monitor = ProcessExitMonitor(pid: child.processIdentifier, timeout: 0.02) { _ in calls += 1 }
  try await Task.sleep(for: .milliseconds(60))
  #expect(calls == 1)
  withExtendedLifetime(monitor) {}
}
