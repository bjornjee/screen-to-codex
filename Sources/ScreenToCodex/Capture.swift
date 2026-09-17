import AppKit
import Carbon
import OSLog
import ScreenCaptureKit
import ScreenToCodexCore

let flowLog = Logger(subsystem: "local.screen-to-codex", category: "flow")

@MainActor final class GlobalHotkey {
  private var hotkey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  var pressed: (() -> Void)?
  private(set) var keyCode: UInt32 = 49
  private(set) var modifiers: UInt32 = UInt32(controlKey | optionKey)
  init() {
    if UserDefaults.standard.object(forKey: "hotkeyCode") != nil {
      keyCode = UInt32(UserDefaults.standard.integer(forKey: "hotkeyCode"))
      modifiers = UInt32(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
    }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let result = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, data in
        guard let data else { return OSStatus(eventNotHandledErr) }
        let target = Unmanaged<GlobalHotkey>.fromOpaque(data).takeUnretainedValue()
        MainActor.assumeIsolated {
          flowLog.info("event=hotkey.pressed")
          target.pressed?()
        }
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    if result != noErr { flowLog.error("event=hotkey.handler_failed status=\(result)") }
  }
  func register(code: UInt32? = nil, flags: UInt32? = nil) throws {
    guard handler != nil else {
      throw AppError.message(
        "The global shortcut handler could not start. Quit and reopen screen-to-codex.")
    }
    let proposedCode = code ?? keyCode
    let proposedFlags = flags ?? modifiers
    var next: EventHotKeyRef?
    if let hotkey {
      UnregisterEventHotKey(hotkey)
      self.hotkey = nil
    }
    let result = RegisterEventHotKey(
      proposedCode, proposedFlags, EventHotKeyID(signature: 0x5354_4358, id: 1),
      GetApplicationEventTarget(), 0, &next)
    guard result == noErr else {
      RegisterEventHotKey(
        keyCode, modifiers, EventHotKeyID(signature: 0x5354_4358, id: 1),
        GetApplicationEventTarget(), 0, &hotkey)
      throw AppError.message("That shortcut is unavailable. Choose another combination.")
    }
    hotkey = next
    keyCode = proposedCode
    modifiers = proposedFlags
    flowLog.info("event=hotkey.registered key=\(proposedCode) modifiers=\(proposedFlags)")
    UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyCode")
    UserDefaults.standard.set(Int(modifiers), forKey: "hotkeyModifiers")
  }
  // Only the pressed event starts capture. Modifier release never cancels an active drag.
}

final class ShortcutRecorder: NSTextField {
  var recorded: ((UInt32, UInt32) -> Void)?
  override var acceptsFirstResponder: Bool { true }
  override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      window?.close()
      return
    }
    let f = event.modifierFlags
    guard f.contains(.command) || f.contains(.control) || f.contains(.option) else { return }
    var carbon: UInt32 = 0
    if f.contains(.command) { carbon |= UInt32(cmdKey) }
    if f.contains(.option) { carbon |= UInt32(optionKey) }
    if f.contains(.control) { carbon |= UInt32(controlKey) }
    if f.contains(.shift) { carbon |= UInt32(shiftKey) }
    recorded?(UInt32(event.keyCode), carbon)
  }
}

final class FloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  var escape: (() -> Void)?
  override func cancelOperation(_ sender: Any?) { escape?() }
}

@MainActor final class RegionCapture {
  private var panels: [FloatingPanel] = []
  private var completion: ((Result<(Data, CGRect), Error>) -> Void)?
  private var capturing = false

  func start(completion: @escaping (Result<(Data, CGRect), Error>) -> Void) {
    guard !capturing else {
      flowLog.info("event=selection.ignored reason=capturing")
      return
    }
    if !panels.isEmpty {
      for panel in panels { panel.orderFrontRegardless() }
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    self.completion = completion
    for screen in NSScreen.screens {
      let panel = FloatingPanel(
        contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false)
      panel.title = "Select screen region"
      panel.level = .screenSaver
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.hidesOnDeactivate = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.escape = { [weak self] in self?.cancel() }
      let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
      view.setAccessibilityElement(true)
      view.setAccessibilityRole(.group)
      view.setAccessibilityLabel(
        "Screenshot selection. Click and hold, drag a region, then release to open chat. Escape cancels."
      )
      view.done = { [weak self] rect in
        self?.selected(rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), screen: screen)
      }
      view.cancel = { [weak self] in self?.cancel() }
      panel.contentView = view
      panels.append(panel)
      panel.orderFrontRegardless()
      if screen.frame.contains(NSEvent.mouseLocation) {
        panel.makeKey()
        panel.makeFirstResponder(view)
      }
    }
    NSApp.activate(ignoringOtherApps: true)
    NSCursor.crosshair.set()
    flowLog.info("event=selection.ready")
  }
  func cancel() {
    hide()
    completion = nil
    flowLog.info("event=selection.cancelled")
  }
  private func hide() {
    for panel in panels { panel.orderOut(nil) }
    panels.removeAll()
  }
  private func selected(_ rect: CGRect, screen: NSScreen) {
    hide()
    guard rect.width >= 8, rect.height >= 8 else {
      completion = nil
      return
    }
    capturing = true
    flowLog.info("event=selection.released")
    Task {
      do {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
          flowLog.error("event=capture.denied reason=screen_permission")
          throw AppError.message(
            "Screen access is needed to capture this region. Enable screen-to-codex in System Settings → Privacy & Security → Screen & System Audio Recording. If macOS quits the app, reopen screen-to-codex once; then use the shortcut again. Audio and microphone recording are disabled."
          )
        }
        // One display per selection, explicit point-to-pixel conversion, app windows excluded.
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: true)
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
          throw AppError.message("The selected display is no longer available.")
        }
        let app = content.applications.filter {
          $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(
          display: display, excludingApplications: app, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(
          x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width,
          height: rect.height)
        let scale = min(screen.backingScaleFactor, 4096 / max(rect.width, rect.height))
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = false
        config.capturesAudio = false
        config.captureMicrophone = false
        config.captureResolution = .best
        let cgImage = try await SCScreenshotManager.captureImage(
          contentFilter: filter, configuration: config)
        let data = try await Task.detached { () -> Data in
          guard
            let png = NSBitmapImageRep(cgImage: cgImage).representation(
              using: .png, properties: [:])
          else {
            throw AppError.message("Could not encode the screenshot.")
          }
          _ = try ImageInput.make(png: png)
          return png
        }.value
        capturing = false
        flowLog.info("event=capture.completed")
        completion?(.success((data, rect)))
        completion = nil
      } catch {
        capturing = false
        completion?(.failure(error))
        completion = nil
      }
    }
  }
}

final class SelectionView: NSView {
  private var gesture = SelectionGesture()
  var done: ((CGRect) -> Void)?
  var cancel: (() -> Void)?
  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
  override func mouseDown(with event: NSEvent) {
    gesture.begin(at: convert(event.locationInWindow, from: nil))
    needsDisplay = true
    flowLog.info("event=selection.mouse_down")
  }
  override func mouseDragged(with event: NSEvent) {
    gesture.drag(to: convert(event.locationInWindow, from: nil), in: bounds)
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    let rectangle = gesture.end(at: convert(event.locationInWindow, from: nil), in: bounds)
    needsDisplay = true
    if let rectangle { done?(rectangle) }
  }
  override func keyDown(with event: NSEvent) { if event.keyCode == 53 { cancel?() } }
  override func draw(_ dirtyRect: NSRect) {
    let selection = gesture.rectangle
    NSColor.black.withAlphaComponent(0.18).setFill()
    let shade = NSBezierPath(rect: bounds)
    if !selection.isEmpty {
      shade.appendRect(selection)
      shade.windingRule = .evenOdd
    }
    shade.fill()
    if !selection.isEmpty {
      NSColor.controlAccentColor.setStroke()
      let border = NSBezierPath(rect: selection)
      border.lineWidth = 1.5
      border.stroke()
    }
    let text = "Click and drag to select · Release to ask · Esc to cancel"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white,
    ]
    text.draw(at: CGPoint(x: 24, y: 28), withAttributes: attributes)
  }
}
