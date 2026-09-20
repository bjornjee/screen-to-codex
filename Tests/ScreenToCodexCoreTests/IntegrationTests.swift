import AppKit
import Foundation
import Testing

@testable import ScreenToCodexCore

private func completedReply(_ rpc: CodexRPC) async throws -> String {
  try await withThrowingTaskGroup(of: String.self) { group in
    group.addTask {
      var reply = ""
      for try await event in rpc.events {
        if event.requestID != nil {
          throw AppError.message("Unexpected request in image-only test: \(event.method)")
        }
        if event.method == "item/agentMessage/delta" {
          reply += event.params["delta"] as? String ?? ""
        }
        if event.method == "turn/completed" {
          let turn = event.params["turn"] as? [String: Any] ?? [:]
          guard turn["status"] as? String == "completed" else {
            throw AppError.message("Test turn failed: \(turn["error"] ?? "unknown")")
          }
          return reply
        }
      }
      throw AppError.message("Connection ended before reply.")
    }
    group.addTask {
      try await Task.sleep(for: .seconds(100))
      throw AppError.message("Reply timed out.")
    }
    defer { group.cancelAll() }
    return try await group.next()!
  }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SCREEN_TO_CODEX_INTEGRATION"] == "1"))
func realImageFollowupAndEphemeralDisposal() async throws {
  try await exerciseImageConversation(
    binary: URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
    checkExtendedThreadMetadata: true)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SCREEN_TO_CODEX_TEST_RUNTIME"] != nil))
func compatibleRuntimeImageFollowupAndEphemeralDisposal() async throws {
  let path = try #require(ProcessInfo.processInfo.environment["SCREEN_TO_CODEX_TEST_RUNTIME"])
  // 0.145 supports image conversations but omits model/effort in thread/read.
  try await exerciseImageConversation(
    binary: URL(fileURLWithPath: path), checkExtendedThreadMetadata: false)
}

private func exerciseImageConversation(binary: URL, checkExtendedThreadMetadata: Bool) async throws
{
  let root = try TemporaryRoot()
  let session = try CaptureSession(root: root.url)
  let png: Data = await MainActor.run {
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 200).fill()
    NSColor.systemBlue.setFill()
    NSBezierPath(ovalIn: NSRect(x: 150, y: 50, width: 100, height: 100)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
  }
  let source = try session.writeCapture(png)
  let rpc = CodexRPC()
  do {
    try await rpc.start(executable: binary)
    let models = try await ModelPage.load(using: rpc)
    let defaults = try await CodexDefaults.load(using: rpc)
    var selection = try ModelSelection(models: models, defaults: defaults)
    if let configured = defaults.model, models.contains(where: { $0.model == configured }) {
      #expect(selection.model.model == configured)
    }
    if let configured = defaults.effort,
      selection.model.supportedReasoningEfforts.contains(where: { $0.id == configured })
    {
      #expect(selection.effort == configured)
    }
    let result = try await rpc.request(
      "thread/start",
      params: [
        "cwd": session.directory.path, "ephemeral": true, "sandbox": "read-only",
        "approvalPolicy": "on-request", "approvalsReviewer": "user",
        "model": selection.model.model,
        "developerInstructions":
          "Answer this image integration test without using tools. Keep answers to one short sentence.",
      ])
    let thread = try #require(result["thread"] as? [String: Any])
    #expect(thread["ephemeral"] as? Bool == true)
    let id = try #require(thread["id"] as? String)
    let input: [[String: Any]] = [
      ["type": "text", "text": "Name the color and shape in this image."],
      try ImageInput.make(png: png),
    ]
    _ = try await rpc.request(
      "turn/start", params: selection.turnParameters(threadID: id, input: input))
    try session.removeCapture()
    #expect(!FileManager.default.fileExists(atPath: source.path))
    let first = try await completedReply(rpc).lowercased()
    #expect(first.contains("blue") && first.contains("circle"))
    if checkExtendedThreadMetadata {
      let initialSettings = try await rpc.request(
        "thread/read", params: ["threadId": id, "includeTurns": false])
      let initialThread = try #require(initialSettings["thread"] as? [String: Any])
      #expect(initialThread["model"] as? String == selection.model.model)
      #expect(initialThread["reasoningEffort"] as? String == selection.effort)
    }
    if let alternate = models.first(where: { $0.id != selection.model.id }) {
      try selection.selectModel(alternate.id)
    }
    if let effort = selection.model.supportedReasoningEfforts.first(where: {
      $0.id != selection.effort
    }) {
      try selection.selectEffort(effort.id)
    }
    _ = try await rpc.request(
      "turn/start",
      params: selection.turnParameters(
        threadID: id,
        input: [
          [
            "type": "text",
            "text": "From the previous image, repeat the color and shape. Do not use tools.",
          ]
        ]))
    let second = try await completedReply(rpc).lowercased()
    #expect(second.contains("blue") && second.contains("circle"))
    if checkExtendedThreadMetadata {
      let settings = try await rpc.request(
        "thread/read", params: ["threadId": id, "includeTurns": false])
      let updatedThread = try #require(settings["thread"] as? [String: Any])
      #expect(updatedThread["model"] as? String == selection.model.model)
      #expect(updatedThread["reasoningEffort"] as? String == selection.effort)
    }
    await rpc.stop()
    try session.close()
    #expect(!FileManager.default.fileExists(atPath: session.directory.path))
    let fresh = CodexRPC()
    do {
      try await fresh.start(executable: binary)
      do {
        _ = try await fresh.request("thread/resume", params: ["threadId": id])
        Issue.record("Ephemeral thread was resumable from a fresh runtime.")
      } catch {
        #expect(
          error.localizedDescription.lowercased().contains("not found")
            || error.localizedDescription.lowercased().contains("no rollout"),
          "Fresh runtime returned: \(error.localizedDescription)")
      }
      await fresh.stop()
    } catch {
      await fresh.stop()
      throw error
    }
  } catch {
    await rpc.stop()
    throw error
  }
}
