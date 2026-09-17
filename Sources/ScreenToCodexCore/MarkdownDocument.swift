import Foundation

public struct MarkdownDocument: Sendable {
  public struct Block: Identifiable, Sendable {
    public let id: Int
    public var text: AttributedString
    public var heading: Int?
    public var isCode = false
    public var isQuote = false
    public var marker: String?
    public var indent = 0
  }

  public let blocks: [Block]

  public init(_ source: String) {
    let bounded = String(source.prefix(64_000))
    guard let parsed = try? AttributedString(markdown: bounded) else {
      blocks = [Block(id: 0, text: AttributedString(bounded))]
      return
    }
    var result: [Block] = []
    var markedItems: Set<Int> = []
    for (intent, range) in parsed.runs[\.presentationIntent] {
      guard result.count < 256 else {
        result.append(
          Block(
            id: result.count,
            text: AttributedString(
              "Response truncated for display. Ask a follow-up for the remaining detail.")))
        break
      }
      var block = Block(id: result.count, text: AttributedString(parsed[range]))
      let components = intent?.components ?? []
      var listItem: (id: Int, ordinal: Int)?
      var ordered: Bool?
      var listDepth = 0
      for component in components {
        switch component.kind {
        case .header(let level): block.heading = level
        case .codeBlock: block.isCode = true
        case .blockQuote: block.isQuote = true
        case .listItem(let ordinal):
          if listItem == nil { listItem = (component.identity, ordinal) }
        case .orderedList:
          if ordered == nil { ordered = true }
          listDepth += 1
        case .unorderedList:
          if ordered == nil { ordered = false }
          listDepth += 1
        default: break
        }
      }
      block.indent = min(4, max(0, listDepth - 1))
      if let item = listItem, markedItems.insert(item.id).inserted {
        block.marker = ordered == true ? "\(item.ordinal)." : "•"
      }
      // Model output may contain links, but it must not launch local files or app schemes.
      for run in block.text.runs {
        if let link = run.link, !["https", "http"].contains(link.scheme?.lowercased() ?? "") {
          block.text[run.range].link = nil
        }
      }
      block.text.presentationIntent = nil
      result.append(block)
    }
    blocks = result
  }
}
