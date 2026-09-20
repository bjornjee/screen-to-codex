import Darwin
import Foundation
import Testing

@testable import ScreenToCodexCore

@Test func liveSessionIsNotSwept() throws {
  let root = try TemporaryRoot()
  let session = try CaptureSession(root: root.url)
  _ = try session.writeCapture(Data([1, 2, 3]))
  try CaptureSession.sweep(root: root.url)
  #expect(FileManager.default.fileExists(atPath: session.directory.path))
  try session.close()
}

@Test func orphanIsSweptAfterOwnerReleasesLock() throws {
  let root = try TemporaryRoot()
  var session: CaptureSession? = try CaptureSession(root: root.url)
  let directory = session!.directory
  weak var releasedSession: CaptureSession?
  releasedSession = session
  _ = try session!.writeCapture(Data([1, 2, 3]))
  session = nil
  try CaptureSession.sweep(root: root.url)
  let exists = FileManager.default.fileExists(atPath: directory.path)
  if exists {
    let lock = directory.appendingPathComponent("owner.lock")
    let fd = Darwin.open(lock.path, O_RDWR | O_NOFOLLOW)
    let probe: String
    if fd < 0 {
      probe = "open errno=\(errno) \(String(cString: strerror(errno)))"
    } else {
      let result = flock(fd, LOCK_EX | LOCK_NB)
      let error = errno
      if result == 0 { _ = flock(fd, LOCK_UN) }
      Darwin.close(fd)
      probe =
        result == 0
        ? "acquired"
        : "flock errno=\(error) \(String(cString: strerror(error)))"
    }
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    Issue.record(
      "orphan survived sweep: weakOwnerAlive=\(releasedSession != nil); lock=\(probe); entries=\(entries.sorted())"
    )
  }
  #expect(!exists)
}

@Test func unrelatedDirectorySurvivesSweep() throws {
  let root = try TemporaryRoot()
  let other = root.url.appendingPathComponent("not-ours")
  try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
  try CaptureSession.sweep(root: root.url)
  #expect(FileManager.default.fileExists(atPath: other.path))
}

@Test func childProcessDoesNotRetainSessionLock() throws {
  let root = try TemporaryRoot()
  var session: CaptureSession? = try CaptureSession(root: root.url)
  let directory = session!.directory
  let child = Process()
  let input = Pipe()
  child.executableURL = URL(fileURLWithPath: "/bin/cat")
  child.standardInput = input
  child.standardOutput = FileHandle.nullDevice
  try child.run()
  defer {
    try? input.fileHandleForWriting.close()
    child.waitUntilExit()
  }
  session = nil
  try CaptureSession.sweep(root: root.url)
  #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func symlinkCannotRedirectCleanup() throws {
  let root = try TemporaryRoot()
  let victim = root.url.appendingPathComponent("keep")
  try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
  let link = root.url.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
  try CaptureSession.sweep(root: root.url)
  #expect(FileManager.default.fileExists(atPath: victim.path))
}

@Test func captureRemovalDoesNotRemoveSessionLock() throws {
  let root = try TemporaryRoot()
  let session = try CaptureSession(root: root.url)
  let capture = try session.writeCapture(Data([1]))
  try session.removeCapture()
  #expect(!FileManager.default.fileExists(atPath: capture.path))
  #expect(
    FileManager.default.fileExists(
      atPath: session.directory.appendingPathComponent("owner.lock").path))
  try session.close()
}

@Test func failedCleanupCanBeRetriedAfterOwnerExits() throws {
  let root = try TemporaryRoot()
  var session: CaptureSession? = try CaptureSession(root: root.url)
  let directory = session!.directory
  let blocked = directory.appendingPathComponent("blocked")
  try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
  try Data([1]).write(to: blocked.appendingPathComponent("content"))
  try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: blocked.path)
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
  }
  #expect(throws: (any Error).self) { try session!.close() }
  session = nil
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
  try CaptureSession.sweep(root: root.url)
  #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func closeRemovesUnsentScreenshotAndIsRepeatable() throws {
  let root = try TemporaryRoot()
  let session = try CaptureSession(root: root.url)
  _ = try session.writeCapture(Data([1, 2, 3]))
  try session.close()
  try session.close()
  #expect(!FileManager.default.fileExists(atPath: session.directory.path))
}

@Test func oneFailedOrphanDoesNotPreventOtherCleanup() throws {
  let root = try TemporaryRoot()
  var sessions: [CaptureSession]? = try [
    CaptureSession(root: root.url), CaptureSession(root: root.url),
  ]
  let directories = sessions!.map(\.directory)
  sessions = nil
  let iterator = try #require(
    FileManager.default.enumerator(
      at: root.url, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]))
  let first = try #require(iterator.nextObject() as? URL)
  let other = try #require(directories.first { $0.lastPathComponent != first.lastPathComponent })
  let blocked = first.appendingPathComponent("blocked")
  try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
  try Data([1]).write(to: blocked.appendingPathComponent("content"))
  try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: blocked.path)
  defer {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
  }
  #expect(throws: (any Error).self) { try CaptureSession.sweep(root: root.url) }
  #expect(!FileManager.default.fileExists(atPath: other.path))
}
