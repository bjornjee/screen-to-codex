import Foundation

public struct ReasoningOption: Decodable, Identifiable, Sendable {
  public let reasoningEffort: String
  public let description: String
  public var id: String { reasoningEffort }
  public var label: String {
    reasoningEffort == "xhigh" ? "Extra high" : reasoningEffort.capitalized
  }
}

public struct CodexModel: Decodable, Identifiable, Sendable {
  public let id: String
  public let model: String
  public let displayName: String
  public let hidden: Bool
  public let isDefault: Bool
  public let inputModalities: [String]
  public let defaultReasoningEffort: String
  public let supportedReasoningEfforts: [ReasoningOption]
}

public struct ModelPage: Decodable, Sendable {
  public let data: [CodexModel]
  public let nextCursor: String?
  public var selectableModels: [CodexModel] {
    data.filter {
      !$0.hidden && $0.inputModalities.contains("image")
        && !$0.supportedReasoningEfforts.isEmpty
    }
  }

  public static func load(using rpc: CodexRPC) async throws -> [CodexModel] {
    var models: [CodexModel] = []
    var seen = Set<String>()
    var cursor: String?
    // Catalog work is bounded to 250 entries and never reads task history.
    for _ in 0..<5 {
      var params: [String: Any] = ["limit": 50, "includeHidden": false]
      if let cursor { params["cursor"] = cursor }
      let result = try await rpc.request("model/list", params: params, timeout: 15)
      let page = try JSONDecoder().decode(
        Self.self, from: JSONSerialization.data(withJSONObject: result))
      guard page.data.count <= 50 else { throw AppError.message("Codex returned too many models.") }
      models += page.selectableModels.filter { seen.insert($0.id).inserted }
      guard let next = page.nextCursor else { return models }
      cursor = next
    }
    throw AppError.message("Codex model catalog exceeded its page limit.")
  }
}

public struct CodexDefaults: Decodable, Sendable {
  public let model: String?
  public let effort: String?

  public init(model: String? = nil, effort: String? = nil) {
    self.model = model
    self.effort = effort
  }

  private enum CodingKeys: String, CodingKey {
    case model
    case effort = "model_reasoning_effort"
  }

  public static func load(using rpc: CodexRPC) async throws -> Self {
    // Omitting cwd requests user-level defaults without this app's project layers.
    let result = try await rpc.request("config/read", params: ["includeLayers": false], timeout: 15)
    guard let config = result["config"] as? [String: Any] else {
      throw AppError.message("Codex did not return its default settings.")
    }
    return try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: config))
  }
}

public struct ModelSelection: Sendable {
  public let models: [CodexModel]
  public private(set) var model: CodexModel
  public private(set) var effort: String
  public private(set) var notice: String?

  public init(models: [CodexModel], defaults: CodexDefaults = CodexDefaults()) throws {
    let preferred = models.first { $0.model == defaults.model }
    guard let chosen = preferred ?? models.first(where: \.isDefault) ?? models.first,
      let fallback = Self.defaultEffort(for: chosen)
    else { throw AppError.message("No image-capable Codex models are available.") }
    self.models = models
    model = chosen
    effort = chosen.supportedReasoningEfforts.first { $0.id == defaults.effort }?.id ?? fallback
    var notices: [String] = []
    if defaults.model != nil && preferred == nil {
      notices.append(
        "Your Codex model is unavailable for screenshots. Using \(chosen.displayName).")
    }
    if let configured = defaults.effort, configured != effort {
      notices.append("Your default effort is unsupported here. Using \(effort.capitalized).")
    }
    notice = notices.isEmpty ? nil : notices.joined(separator: " ")
  }

  public mutating func selectModel(_ id: String) throws {
    guard let chosen = models.first(where: { $0.id == id }),
      let fallback = Self.defaultEffort(for: chosen)
    else { throw AppError.message("This model is no longer available.") }
    model = chosen
    notice = nil
    if !chosen.supportedReasoningEfforts.contains(where: { $0.id == effort }) { effort = fallback }
  }

  public mutating func selectEffort(_ value: String) throws {
    guard model.supportedReasoningEfforts.contains(where: { $0.id == value }) else {
      throw AppError.message("This model does not support that effort level.")
    }
    effort = value
    notice = nil
  }

  public func turnParameters(threadID: String, input: [[String: Any]]) -> [String: Any] {
    ["threadId": threadID, "input": input, "model": model.model, "effort": effort]
  }

  private static func defaultEffort(for model: CodexModel) -> String? {
    let options = model.supportedReasoningEfforts
    return options.first(where: { $0.id == model.defaultReasoningEffort })?.id ?? options.first?.id
  }
}
