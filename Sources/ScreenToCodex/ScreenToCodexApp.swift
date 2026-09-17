import AppKit
import ScreenToCodexCore
import SwiftUI

@main struct ScreenToCodexApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let capture = RegionCapture()
  private let hotkey = GlobalHotkey()
  private var statusItem: NSStatusItem!
  private var panel: FloatingPanel?
  private var model: ChatModel?
  private var shortcutPanel: FloatingPanel?
  private var sweepTimer: Timer?
  private let lifecycle = ChatLifecycle()
  private var sweepRunning = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    flowLog.info("event=app.started")
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "viewfinder", accessibilityDescription: "screen-to-codex")
    let menu = NSMenu()
    menu.addItem(withTitle: "Capture region", action: #selector(beginCapture), keyEquivalent: "")
    menu.addItem(
      withTitle: "Change shortcut…", action: #selector(changeShortcut), keyEquivalent: "")
    menu.addItem(withTitle: "Retry pending cleanup", action: #selector(sweep), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit screen-to-codex", action: #selector(quit), keyEquivalent: "q")
    for item in menu.items { item.target = self }
    statusItem.menu = menu
    hotkey.pressed = { [weak self] in self?.beginCapture() }
    do { try hotkey.register() } catch { showError(error) }
    sweep()
    sweepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.sweep() }
    }
  }
  @objc private func beginCapture() {
    guard !lifecycle.isBusy, !lifecycle.isTerminating else {
      flowLog.info("event=capture.ignored reason=cleanup")
      return
    }
    if let panel {
      panel.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    capture.start { [weak self] result in
      switch result {
      case .success(let (png, rect)): self?.openChat(png: png, rect: rect)
      case .failure(let error): self?.showError(error)
      }
    }
  }
  private func openChat(png: Data, rect: CGRect) {
    guard panel == nil else { return }
    lifecycle.open { [self] in
      do {
        let session = try await Task.detached { () -> CaptureSession in
          let session = try CaptureSession()
          _ = try session.writeCapture(png)
          return session
        }.value
        guard !lifecycle.isTerminating else {
          try await Task.detached { try session.close() }.value
          return
        }
        let model = ChatModel(png: png, session: session)
        self.model = model
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main!
        let visible = screen.visibleFrame
        let width: CGFloat = min(410, visible.width - 24)
        let height: CGFloat = min(350, visible.height - 24)
        var x = rect.maxX + 14
        if x + width > visible.maxX { x = rect.minX - width - 14 }
        x = max(visible.minX + 12, min(x, visible.maxX - width - 12))
        let top = min(visible.maxY - 12, max(visible.minY + height + 12, rect.maxY))
        let panel = FloatingPanel(
          contentRect: CGRect(x: x, y: top - height, width: width, height: height),
          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
          rootView: OverlayView(model: model, close: { [weak self] in self?.closeChat() }))
        panel.escape = { [weak self] in self?.closeChat() }
        panel.delegate = self
        self.panel = panel
        model.onConversationStarted = { [weak self] in self?.growPanel() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        flowLog.info("event=chat.opened")
      } catch { showError(error) }
    }
  }
  private func growPanel() {
    guard let panel else { return }
    let visible = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
    let height = min(CGFloat(650), visible.height - 24)
    let top = min(visible.maxY - 12, max(visible.minY + height + 12, panel.frame.maxY))
    panel.setFrame(
      CGRect(x: panel.frame.minX, y: top - height, width: panel.frame.width, height: height),
      display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
  }
  private func closeChat() {
    guard !lifecycle.isBusy, let model else { return }
    panel?.orderOut(nil)
    panel = nil
    self.model = nil
    lifecycle.close { [self] in
      let cleaned = await model.close()
      if !cleaned { statusItem.button?.toolTip = "Cleanup pending; use Retry pending cleanup." }
    }
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    closeChat()
    return false
  }
  @objc private func sweep() {
    guard !sweepRunning else { return }
    sweepRunning = true
    Task {
      do { try await Task.detached { try CaptureSession.sweep() }.value } catch {
        statusItem.button?.toolTip = "Cleanup pending; use Retry pending cleanup."
      }
      sweepRunning = false
    }
  }
  @objc private func changeShortcut() {
    let window = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 110), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.title = "Choose global shortcut"
    let field = ShortcutRecorder(frame: NSRect(x: 20, y: 30, width: 340, height: 44))
    field.stringValue = "Press a key with ⌘, ⌃ or ⌥"
    field.isEditable = false
    field.isSelectable = false
    field.alignment = .center
    field.font = .systemFont(ofSize: 16)
    field.recorded = { [weak self, weak window] key, flags in
      do {
        try self?.hotkey.register(code: key, flags: flags)
        window?.orderOut(nil)
        self?.shortcutPanel = nil
      } catch { self?.showError(error) }
    }
    window.contentView?.addSubview(field)
    shortcutPanel = window
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(field)
  }
  private func showError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "screen-to-codex"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }
  @objc private func quit() { NSApp.terminate(nil) }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    capture.cancel()
    guard model != nil || lifecycle.isBusy else { return .terminateNow }
    guard !lifecycle.isTerminating else { return .terminateLater }
    panel?.orderOut(nil)
    Task {
      await lifecycle.shutdown { [self] in
        if let model { _ = await model.close() }
        model = nil
        panel = nil
      }
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
