import Foundation
import Testing

@testable import ScreenToCodexCore

@Test func markdownEmphasisIsFormattedWithoutMarkers() throws {
  let block = try #require(MarkdownDocument("A **bold** word and `code`.").blocks.first)
  #expect(String(block.text.characters) == "A bold word and code.")
  #expect(
    block.text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
  #expect(block.text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
}

@Test func markdownListsKeepSeparateItemsAndNesting() {
  let blocks = MarkdownDocument("- First\n  - Nested\n- Last\n\n1. One\n2. Two").blocks
  #expect(blocks.map(\.marker) == ["•", "•", "•", "1.", "2."])
  #expect(blocks.map(\.indent) == [0, 1, 0, 0, 0])
}

@Test func markdownHeadingsAndParagraphsStaySeparate() {
  let blocks = MarkdownDocument("## Summary\n\nFirst paragraph.\n\nSecond paragraph.").blocks
  #expect(
    blocks.map { String($0.text.characters) } == [
      "Summary", "First paragraph.", "Second paragraph.",
    ])
  #expect(blocks.first?.heading == 2)
}

@Test func markdownCodeBlockKeepsLiteralContent() throws {
  let block = try #require(
    MarkdownDocument("```swift\nlet value = \"**literal**\"\n``` ").blocks.first)
  #expect(block.isCode)
  #expect(String(block.text.characters).contains("**literal**"))
}

@Test func markdownUnsafeLinksRemainReadableButInactive() {
  let blocks = MarkdownDocument("[bad](file:///etc/passwd) and [web](https://example.com)").blocks
  #expect(
    blocks.flatMap { $0.text.runs.compactMap(\.link) } == [URL(string: "https://example.com")!])
}

@Test func incompleteMarkdownRemainsReadable() {
  let blocks = MarkdownDocument("Still **typing").blocks
  #expect(blocks.map { String($0.text.characters) }.joined() == "Still **typing")
}

@Test func maximumMarkdownHasBoundedBlockCount() {
  let source = String(repeating: "x\n\n", count: 21_333)
  let document = MarkdownDocument(source)
  #expect(document.blocks.count <= 257)
  #expect(document.blocks.last.map { String($0.text.characters).contains("truncated") } == true)
}
