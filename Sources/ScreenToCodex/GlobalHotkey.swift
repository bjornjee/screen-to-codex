import AppKit
import Carbon
import ScreenToCodexCore

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
