import AppKit
import ScreenToCodexCore
import SwiftUI

struct GlassBackground: NSViewRepresentable {
  func makeNSView(context: Context) -> NSGlassEffectView {
    let view = NSGlassEffectView()
    view.style = .regular
    view.cornerRadius = 28
    return view
  }
  func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
}

struct OverlayView: View {
  @ObservedObject var model: ChatModel
  var close: () -> Void
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
          .frame(width: 22, height: 22)
          .clipShape(RoundedRectangle(cornerRadius: 5)).accessibilityHidden(true)
        Text("Screen to Codex").font(.system(size: 14, weight: .semibold))
        Spacer()
        Text("Temporary").font(.system(size: 11)).foregroundStyle(.secondary)
        Button(action: close) { Image(systemName: "xmark").frame(width: 28, height: 28) }
          .buttonStyle(.glass).buttonBorderShape(.circle)
          .accessibilityLabel("Close temporary chat").help("Close temporary chat (Esc)")
      }.padding(.horizontal, 18).padding(.vertical, 14)

      VStack(spacing: 14) {
        HStack(spacing: 10) {
          if let image = model.thumbnail {
            Image(nsImage: image).resizable().scaledToFit()
              .frame(
                width: model.messages.isEmpty ? 44 : 28, height: model.messages.isEmpty ? 44 : 28
              )
              .clipShape(RoundedRectangle(cornerRadius: 9))
              .accessibilityLabel("Selected screenshot")
          }
          VStack(alignment: .leading, spacing: 3) {
            Text("Screenshot attached")
              .font(.system(size: 12, weight: .medium))
            if model.messages.isEmpty {
              Text("Ready for your question").font(.system(size: 11)).foregroundStyle(.secondary)
            }
          }
          Spacer()
        }
        if !model.messages.isEmpty {
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 18) {
                if model.hasEarlierMessages {
                  Text(
                    "Earlier messages are outside this view; Codex retains the context until close."
                  ).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.messages) { message in
                  VStack(alignment: .leading, spacing: 6) {
                    if !message.isUser { Text("Codex").font(.system(size: 12, weight: .semibold)) }
                    if let document = message.document, !message.isUser {
                      MarkdownMessageView(document: document)
                    } else {
                      Text(message.text).font(.system(size: 14)).lineSpacing(3)
                        .textSelection(.enabled)
                    }
                  }
                  .padding(message.isUser ? 12 : 0)
                  .background(
                    message.isUser ? Color.blue.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 16)
                  )
                  .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                  .id(message.id)
                }
                Color.clear.frame(height: 1).id("bottom")
              }.padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: model.messages.last?.text) { _, _ in
              proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: model.messages.last?.document != nil) { _, _ in
              proxy.scrollTo("bottom", anchor: .bottom)
            }
          }
        } else {
          Spacer(minLength: 0)
        }
        if let request = model.approval {
          ApprovalView(request: request, respond: model.answerApproval)
        }
        if let error = model.error {
          Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !model.status.isEmpty {
          HStack(spacing: 8) {
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
          }.accessibilityElement(children: .combine)
        }
        VStack(spacing: 8) {
          VStack(spacing: 8) {
            TextField(
              model.messages.isEmpty ? "Ask about this…" : "Ask a follow-up…", text: $model.draft,
              axis: .vertical
            )
            .font(.system(size: 14)).lineLimit(2...4)
            .textFieldStyle(.plain).padding(.horizontal, 12).padding(.top, 12)
            .focused($focused).accessibilityLabel("Question")
            .onSubmit { model.send() }
            HStack(spacing: 8) {
              if let selection = model.modelSelection {
                HStack(spacing: 6) {
                  Picker(
                    "Model", selection: Binding(get: { selection.model.id }, set: model.selectModel)
                  ) {
                    ForEach(selection.models) { option in
                      Text(option.displayName).tag(option.id)
                    }
                  }
                  .accessibilityLabel("Model")
                  .help("Model for your next message. New chats use your Codex defaults.")
                  .frame(maxWidth: .infinity)
                  Picker(
                    "Effort", selection: Binding(get: { selection.effort }, set: model.selectEffort)
                  ) {
                    ForEach(selection.model.supportedReasoningEfforts) { option in
                      Text(option.label).tag(option.id).help(option.description)
                    }
                  }
                  .accessibilityLabel("Reasoning effort")
                  .help("Reasoning effort for your next message")
                  .fixedSize()
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!model.canChangeModel)
              } else if model.loadingModels {
                HStack(spacing: 8) {
                  ProgressView().controlSize(.small)
                  Text("Loading your defaults…").font(.caption).foregroundStyle(.secondary)
                  Spacer()
                }
              } else if let error = model.modelLoadError {
                VStack(alignment: .leading, spacing: 6) {
                  Text("Could not load Codex settings. \(error)").font(.caption).foregroundStyle(
                    .red)
                  Button("Retry", action: model.prepareModels).controlSize(.small)
                }.frame(maxWidth: .infinity, alignment: .leading)
              }
              Button(action: model.send) {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                  .frame(width: 28, height: 28)
              }.buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Send message").help("Send message (⌘Return)")
                .disabled(!model.canSend).keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
          }
          .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
          .overlay {
            RoundedRectangle(cornerRadius: 20).stroke(
              focused ? Color.accentColor.opacity(0.65) : .secondary.opacity(0.25),
              lineWidth: focused ? 1 : 0.5)
          }
          if let notice = model.modelSelection?.notice {
            Text(notice).font(.caption).foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          Text("⌘Return to send · Esc to close")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .background {
      if reduceTransparency {
        Color(nsColor: .windowBackgroundColor)
      } else {
        GlassBackground()
          .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.55))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 28))
    .onAppear {
      focused = true
      model.prepareModels()
    }
    .onExitCommand(perform: close)
  }
}

struct ApprovalView: View {
  let request: RPCMessage
  let respond: ([String: Any]) -> Void
  @State private var answers: [String: String] = [:]
  private var questions: [[String: Any]] { request.params["questions"] as? [[String: Any]] ?? [] }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Codex needs your input").font(.headline)
      if request.method == "item/tool/requestUserInput" {
        ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
          let id = question["id"] as? String ?? ""
          Text(question["question"] as? String ?? "Question").font(.callout)
          if let options = question["options"] as? [[String: Any]] {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
              let label = option["label"] as? String ?? ""
              Button(label) { answers[id] = label }.buttonStyle(.bordered)
            }
          }
          TextField(
            "Your answer", text: Binding(get: { answers[id] ?? "" }, set: { answers[id] = $0 }))
        }
        Button("Submit answers") {
          var result: [String: Any] = [:]
          for question in questions {
            if let id = question["id"] as? String { result[id] = ["answers": [answers[id] ?? ""]] }
          }
          respond(["answers": result])
        }.disabled(questions.contains { (answers[$0["id"] as? String ?? ""] ?? "").isEmpty })
      } else {
        Text(request.params["reason"] as? String ?? "Approve this action for this request only?")
          .font(.callout)
        if let command = request.params["command"] as? String {
          Text(command).font(.caption.monospaced()).textSelection(.enabled)
        }
        if let changes = request.params["fileChanges"] {
          Text(String(describing: changes).prefix(1500)).font(.caption).textSelection(.enabled)
        }
        HStack {
          Button("Decline") { respond(["decision": "decline"]) }
          Spacer()
          Button("Allow once") { respond(["decision": "accept"]) }.buttonStyle(.borderedProminent)
        }
      }
    }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12))
  }
}
