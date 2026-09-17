import Darwin
import Foundation

/// Owned by one chat; callers serialize writes and cleanup off the UI thread.
public final class CaptureSession: @unchecked Sendable {
  public static let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "screen-to-codex", isDirectory: true)
  private static let marker = Data("screen-to-codex-session-v1".utf8)
  public let directory: URL
  private var lockFD: Int32 = -1
  private let mutex = NSLock()

  public init(root: URL = CaptureSession.root) throws {
    try Self.prepareRoot(root)
    directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    lockFD = Darwin.open(
      directory.appendingPathComponent("owner.lock").path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW,
      0o600)
    guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
      throw AppError.message("Could not lock capture session.")
    }
    try Self.marker.write(to: directory.appendingPathComponent("owner"), options: .atomic)
  }
  deinit { if lockFD >= 0 { Darwin.close(lockFD) } }

  public func writeCapture(_ data: Data) throws -> URL {
    mutex.lock()
    defer { mutex.unlock() }
    guard lockFD >= 0 else { throw AppError.message("Capture session is closed.") }
    let url = directory.appendingPathComponent("capture.png")
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return url
  }
  public func removeCapture() throws {
    mutex.lock()
    defer { mutex.unlock() }
    let url = directory.appendingPathComponent("capture.png")
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
  public func close() throws {
    mutex.lock()
    defer { mutex.unlock() }
    guard lockFD >= 0 else { return }
    try Self.removeOwnedDirectory(directory)
    Darwin.close(lockFD)
    lockFD = -1
  }
  private static func removeOwnedDirectory(_ directory: URL) throws {
    // Keep retry evidence and the live lock until every payload has been removed.
    let bookkeeping = Set(["owner", "owner.lock"])
    for child in try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    {
      if !bookkeeping.contains(child.lastPathComponent) {
        try FileManager.default.removeItem(at: child)
      }
    }
    try FileManager.default.removeItem(at: directory)
  }
  private static func prepareRoot(_ root: URL) throws {
    if !FileManager.default.fileExists(atPath: root.path) {
      try FileManager.default.createDirectory(
        at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    var info = stat()
    guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid()
    else {
      throw AppError.message("Capture directory is not a private owned directory.")
    }
    guard chmod(root.path, 0o700) == 0 else {
      throw AppError.message("Cannot secure capture directory.")
    }
  }
  public static func sweep(root: URL = CaptureSession.root) throws {
    try prepareRoot(root)
    guard
      let iterator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.isSymbolicLinkKey],
        options: [.skipsSubdirectoryDescendants])
    else { return }
    var count = 0
    var firstFailure: Error?
    for case let directory as URL in iterator {
      guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
      var info = stat()
      guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
        info.st_uid == getuid()
      else { continue }
      let fd = Darwin.open(directory.appendingPathComponent("owner.lock").path, O_RDWR | O_NOFOLLOW)
      guard fd >= 0 else { continue }
      defer { Darwin.close(fd) }
      guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { continue }
      let markerURL = directory.appendingPathComponent("owner")
      var markerInfo = stat()
      guard lstat(markerURL.path, &markerInfo) == 0, markerInfo.st_mode & S_IFMT == S_IFREG,
        markerInfo.st_size == marker.count, (try? Data(contentsOf: markerURL)) == marker
      else { continue }
      do { try removeOwnedDirectory(directory) } catch {
        if firstFailure == nil { firstFailure = error }
      }
      count += 1
      // ponytail: bounded startup batches; next timer tick resumes remaining orphans.
      if count == 32 { break }
    }
    if let firstFailure { throw firstFailure }
  }
}
