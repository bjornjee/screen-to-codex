import Darwin
import Foundation
import Testing

@testable import ScreenToCodexCore

final class TemporaryRoot {
  let url: URL
  init() throws {
    url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: url) }
}

@Test func splitJSONLinesAreReassembled() throws {
  var framer = LineFramer(limit: 100)
  #expect(try framer.append(Data("{\"id\":".utf8)) == [])
  #expect(try framer.append(Data("1}\n{}\n".utf8)) == [Data("{\"id\":1}".utf8), Data("{}".utf8)])
}
@Test func oversizedUnterminatedFrameIsRejected() {
  var framer = LineFramer(limit: 8)
  #expect(throws: (any Error).self) { try framer.append(Data(repeating: 65, count: 9)) }
}
@Test func oversizedTerminatedFrameIsRejected() {
  var framer = LineFramer(limit: 8)
  #expect(throws: (any Error).self) { try framer.append(Data("123456789\n".utf8)) }
}
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
@Test func imagePayloadContainsBytesNotPath() throws {
  let input = try ImageInput.make(png: Data([137, 80, 78, 71]), limit: 8)
  #expect(input["url"] == "data:image/png;base64,iVBORw==")
  #expect(input["path"] == nil)
}
@Test func imageLimitRejectsLargeCapture() {
  #expect(throws: (any Error).self) {
    try ImageInput.make(png: Data(repeating: 0, count: 9), limit: 8)
  }
}

@Test func shortPipeReplyArrivesWhileServerStaysOpen() async throws {
  let root = try TemporaryRoot()
  let server = root.url.appendingPathComponent("server")
  try Data(
    """
    #!/bin/sh
    read -r request
    printf '%s\\n' '{"id":1,"result":{}}'
    read -r initialized
    read -r next
    """.utf8
  ).write(to: server)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: server.path)
  let rpc = CodexRPC()
  let deadline = Task {
    try? await Task.sleep(for: .seconds(2))
    await rpc.stop()
  }
  do {
    try await rpc.start(executable: server)
    deadline.cancel()
    await rpc.stop()
  } catch {
    deadline.cancel()
    await rpc.stop()
    throw error
  }
}
