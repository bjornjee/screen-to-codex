import Darwin
import Foundation

public enum AppError: LocalizedError {
  case message(String)
  public var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}

public struct LineFramer {
  private var buffer = Data()
  private let limit: Int
  public init(limit: Int = 8 * 1024 * 1024) { self.limit = limit }
  public mutating func append(_ data: Data) throws -> [Data] {
    buffer.append(data)
    var lines: [Data] = []
    while let newline = buffer.firstIndex(of: 10) {
      guard buffer.distance(from: buffer.startIndex, to: newline) <= limit else {
        throw AppError.message("Codex sent an oversized message.")
      }
      lines.append(Data(buffer[..<newline]))
      buffer.removeSubrange(...newline)
    }
    guard buffer.count <= limit else { throw AppError.message("Codex sent an oversized message.") }
    return lines
  }
}

public enum ImageInput {
  public static func make(png: Data, limit: Int = 12 * 1024 * 1024) throws -> [String: String] {
    guard !png.isEmpty, png.count <= limit else {
      throw AppError.message("Capture exceeds 12 MB. Select a smaller region.")
    }
    return ["type": "image", "url": "data:image/png;base64," + png.base64EncodedString()]
  }
}

public struct RPCMessage: @unchecked Sendable {
  public let body: [String: Any]
  public var method: String { body["method"] as? String ?? "" }
  public var params: [String: Any] { body["params"] as? [String: Any] ?? [:] }
  public var requestID: Any? { body["id"] }
}

public actor CodexRPC {
  public nonisolated let events: AsyncThrowingStream<RPCMessage, Error>
  private let continuation: AsyncThrowingStream<RPCMessage, Error>.Continuation
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let writer = DispatchQueue(label: "screen-to-codex.protocol-writer")
  private var nextID = 0
  private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
  private var timers: [Int: Task<Void, Never>] = [:]
  private var reader: Task<Void, Never>?
  private var stopped = false

  public init() {
    let stream = AsyncThrowingStream<RPCMessage, Error>.makeStream(
      bufferingPolicy: .bufferingOldest(256))
    events = stream.stream
    continuation = stream.continuation
  }

  public func start(executable: URL) async throws {
    guard !process.isRunning, !stopped else { throw AppError.message("Session is closed.") }
    process.executableURL = executable
    process.arguments = ["app-server", "--stdio"]
    process.standardInput = input
    process.standardOutput = output
    // Never retain prompts, images, or model/provider diagnostics in application logs.
    process.standardError = FileHandle.nullDevice
    try process.run()
    let handle = output.fileHandleForReading
    reader = Task.detached(priority: .userInitiated) { [weak self] in
      var framer = LineFramer()
      var bytes = [UInt8](repeating: 0, count: 64 * 1024)
      do {
        while !Task.isCancelled {
          // Foundation's read(upToCount:) waits to fill its buffer on pipes.
          let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
          if count < 0, errno == EINTR { continue }
          guard count >= 0 else { throw AppError.message("Could not read the Codex connection.") }
          if count == 0 { break }
          let data = Data(bytes.prefix(count))
          for line in try framer.append(data) {
            guard !line.isEmpty else { continue }
            guard let body = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
              throw AppError.message("Invalid Codex protocol message.")
            }
            await self?.receive(body)
          }
        }
        await self?.fail(AppError.message("Codex disconnected. Close this chat and try again."))
      } catch { await self?.fail(error) }
    }
    _ = try await request(
      "initialize",
      params: [
        "clientInfo": ["name": "screen_to_codex", "title": "screen-to-codex", "version": "0.1.0"],
        "capabilities": ["experimentalApi": true],
      ])
    try write(["method": "initialized", "params": [:]])
  }

  public func request(_ method: String, params: [String: Any], timeout: Double = 90) async throws
    -> [String: Any]
  {
    guard !stopped, process.isRunning else { throw AppError.message("Codex is not connected.") }
    guard pending.count < 16 else { throw AppError.message("Too many pending Codex requests.") }
    nextID += 1
    let id = nextID
    return try await withCheckedThrowingContinuation { callback in
      pending[id] = callback
      timers[id] = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
        await self?.expire(id)
      }
      do { try write(["id": id, "method": method, "params": params]) } catch {
        resolve(id, .failure(error))
      }
    }
  }

  public func respond(id: Any, result: [String: Any]) throws {
    try write(["id": id, "result": result])
  }
  public func reject(id: Any) throws {
    try write([
      "id": id,
      "error": [
        "code": -32601,
        "message": "This client does not support this request; no permission granted.",
      ],
    ])
  }
  private func write(_ body: [String: Any]) throws {
    guard !stopped else { throw AppError.message("Session is closed.") }
    let data = try JSONSerialization.data(withJSONObject: body)
    guard data.count <= 20 * 1024 * 1024 else {
      throw AppError.message("Message exceeds the size limit.")
    }
    let handle = input.fileHandleForWriting
    // A full pipe must not prevent request deadlines or close from running.
    writer.async { [weak self] in
      do { try handle.write(contentsOf: data + Data([10])) } catch {
        Task { await self?.fail(error) }
      }
    }
  }
  private func receive(_ body: [String: Any]) {
    guard !stopped else { return }
    if body["method"] == nil, let id = body["id"] as? Int {
      if let error = body["error"] as? [String: Any] {
        resolve(
          id,
          .failure(AppError.message(error["message"] as? String ?? "Codex rejected the request.")))
      } else {
        resolve(id, .success(body["result"] as? [String: Any] ?? [:]))
      }
    } else if case .dropped = continuation.yield(RPCMessage(body: body)) {
      fail(
        AppError.message(
          "Codex produced updates faster than this window can display. Close and retry."))
    }
  }
  private func resolve(_ id: Int, _ result: Result<[String: Any], Error>) {
    timers.removeValue(forKey: id)?.cancel()
    pending.removeValue(forKey: id)?.resume(with: result)
  }
  private func expire(_ id: Int) {
    // Delivery may have occurred. Never automatically replay a timed-out turn.
    resolve(
      id,
      .failure(
        AppError.message("Codex timed out; delivery is uncertain. Close this chat before retrying.")
      ))
    fail(AppError.message("Codex timed out. Close this chat and try again."))
  }
  private func fail(_ error: Error) {
    guard !stopped else { return }
    for id in Array(pending.keys) { resolve(id, .failure(error)) }
    continuation.finish(throwing: error)
  }
  public func stop() async {
    guard !stopped else { return }
    stopped = true
    for id in Array(pending.keys) { resolve(id, .failure(AppError.message("Session closed."))) }
    continuation.finish()
    if process.isRunning { process.terminate() }
    let child = process
    await Task.detached {
      // Only the Process object created by this client is signalled.
      for _ in 0..<20 {
        if !child.isRunning { return }
        try? await Task.sleep(for: .milliseconds(100))
      }
      if child.isRunning { kill(child.processIdentifier, SIGKILL) }
      child.waitUntilExit()
    }.value
    reader?.cancel()
    // Terminating the child unblocks pipe writes. Close on the writer queue so
    // an already queued message never touches a closed Foundation handle.
    let handle = input.fileHandleForWriting
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      writer.async {
        try? handle.close()
        done.resume()
      }
    }
  }
}
