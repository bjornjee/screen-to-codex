import ScreenToCodexCore
import SwiftUI

struct MarkdownMessageView: View {
  let document: MarkdownDocument

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(document.blocks) { block in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          if let marker = block.marker {
            Text(marker).foregroundStyle(.secondary).frame(minWidth: 12, alignment: .trailing)
              .accessibilityLabel(marker == "•" ? "Bullet" : "Item \(marker)")
          }
          Text(styledText(block))
            .font(blockFont(block))
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(block.isCode ? 10 : 0)
            .background(
              block.isCode ? Color.primary.opacity(0.05) : .clear,
              in: RoundedRectangle(cornerRadius: 10)
            )
            .foregroundStyle(block.isQuote ? .secondary : .primary)
            .accessibilityAddTraits(block.heading == nil ? [] : .isHeader)
        }
        .padding(.leading, CGFloat(block.indent) * 14)
        .padding(.top, block.heading != nil && block.id != 0 ? 4 : 0)
      }
    }
    .font(.system(size: 14))
  }

  private func blockFont(_ block: MarkdownDocument.Block) -> Font {
    if block.isCode { return .system(size: 12, design: .monospaced) }
    if let level = block.heading { return .system(size: level <= 2 ? 16 : 14, weight: .semibold) }
    return .system(size: 14)
  }

  private func styledText(_ block: MarkdownDocument.Block) -> AttributedString {
    var text = block.text
    for run in text.runs where run.inlinePresentationIntent?.contains(.code) == true {
      text[run.range].font = .system(size: 13, design: .monospaced)
      text[run.range].backgroundColor = .primary.opacity(0.07)
    }
    return text
  }
}
