import Foundation
import Testing

@testable import ScreenToCodexCore

private func catalog() throws -> [CodexModel] {
  let data = Data(
    """
    {"data":[
      {"id":"a","model":"vision-a","displayName":"Vision A","hidden":false,"isDefault":false,"inputModalities":["text","image"],"defaultReasoningEffort":"low","supportedReasoningEfforts":[{"reasoningEffort":"low","description":"Quick"},{"reasoningEffort":"high","description":"Thorough"}]},
      {"id":"b","model":"vision-b","displayName":"Vision B","hidden":false,"isDefault":true,"inputModalities":["text","image"],"defaultReasoningEffort":"medium","supportedReasoningEfforts":[{"reasoningEffort":"medium","description":"Balanced"},{"reasoningEffort":"high","description":"Thorough"}]},
      {"id":"c","model":"text-only","displayName":"Text Only","hidden":false,"isDefault":false,"inputModalities":["text"],"defaultReasoningEffort":"low","supportedReasoningEfforts":[]},
      {"id":"d","model":"hidden","displayName":"Hidden","hidden":true,"isDefault":false,"inputModalities":["text","image"],"defaultReasoningEffort":"low","supportedReasoningEfforts":[]}
    ],"nextCursor":null}
    """.utf8)
  return try JSONDecoder().decode(ModelPage.self, from: data).selectableModels
}

@Test func catalogOnlyOffersVisibleImageModels() throws {
  #expect(try catalog().map(\.id) == ["a", "b"])
}

@Test func modelSelectionUsesAdvertisedDefault() throws {
  let selection = try ModelSelection(models: catalog())
  #expect(selection.model.id == "b")
  #expect(selection.effort == "medium")
}

@Test func changingModelResetsUnsupportedEffort() throws {
  var selection = try ModelSelection(models: catalog())
  try selection.selectModel("a")
  #expect(selection.effort == "low")
}

@Test func changingModelPreservesSupportedEffort() throws {
  var selection = try ModelSelection(models: catalog())
  try selection.selectEffort("high")
  try selection.selectModel("a")
  #expect(selection.effort == "high")
}

@Test func unsupportedEffortIsRejected() throws {
  var selection = try ModelSelection(models: catalog())
  #expect(throws: (any Error).self) { try selection.selectEffort("ultra") }
  #expect(selection.effort == "medium")
}

@Test func emptyModelCatalogIsRejected() {
  #expect(throws: (any Error).self) { try ModelSelection(models: []) }
}

@Test func selectedSettingsAreIncludedOnEveryTurn() throws {
  var selection = try ModelSelection(models: catalog())
  let first = selection.turnParameters(
    threadID: "same-task", input: [["type": "text", "text": "First"]])
  #expect(first["model"] as? String == "vision-b")
  #expect(first["effort"] as? String == "medium")
  try selection.selectModel("a")
  try selection.selectEffort("high")
  let followup = selection.turnParameters(
    threadID: "same-task", input: [["type": "text", "text": "Follow-up"]])
  #expect(followup["model"] as? String == "vision-a")
  #expect(followup["effort"] as? String == "high")
  #expect(followup["threadId"] as? String == "same-task")
}

@Test func userDefaultsOverrideCatalogDefaults() throws {
  let defaults = CodexDefaults(model: "vision-a", effort: "high")
  let selection = try ModelSelection(models: catalog(), defaults: defaults)
  #expect(selection.model.model == "vision-a")
  #expect(selection.effort == "high")
}

@Test func configuredEffortAppliesWhenModelIsUnset() throws {
  let selection = try ModelSelection(models: catalog(), defaults: CodexDefaults(effort: "high"))
  #expect(selection.effort == "high")
}

@Test func missingConfiguredModelShowsNotice() throws {
  let selection = try ModelSelection(models: catalog(), defaults: CodexDefaults(model: "missing"))
  #expect(selection.model.id == "b")
  #expect(selection.notice != nil)
}

@Test func unsupportedConfiguredEffortShowsNotice() throws {
  let selection = try ModelSelection(models: catalog(), defaults: CodexDefaults(effort: "ultra"))
  #expect(selection.effort == "medium")
  #expect(selection.notice != nil)
}

@Test func codexConfigKeysDecodeWithoutOtherSettings() throws {
  let defaults = try JSONDecoder().decode(
    CodexDefaults.self,
    from: Data(#"{"model":"vision-a","model_reasoning_effort":"high","unrelated":true}"#.utf8))
  #expect(defaults.model == "vision-a")
  #expect(defaults.effort == "high")
}

@Test func changingSelectionDoesNotChangeNextChatDefaults() throws {
  let defaults = CodexDefaults(model: "vision-a", effort: "high")
  var first = try ModelSelection(models: catalog(), defaults: defaults)
  try first.selectModel("b")
  try first.selectEffort("medium")
  let next = try ModelSelection(models: catalog(), defaults: defaults)
  #expect(next.model.model == "vision-a")
  #expect(next.effort == "high")
}
