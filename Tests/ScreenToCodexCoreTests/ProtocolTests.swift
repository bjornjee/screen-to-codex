import Foundation
import Testing

@testable import ScreenToCodexCore

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
