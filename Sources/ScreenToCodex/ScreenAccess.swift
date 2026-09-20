import AppKit
import ScreenToCodexCore
import SwiftUI

enum ScreenAccessError: Error { case denied }

@MainActor enum PermissionRelaunch {
  static let argument = "--relaunch-after-permission-exit"

  static func runIfRequested() -> Bool {
    let arguments = CommandLine.arguments
    guard arguments.dropFirst().first == argument else { return false }
    guard arguments.count == 3, let pid = Int32(arguments[2]), pid > 1, pid != getpid()
    else { return true }
    let monitor = ProcessExitMonitor(pid: pid, timeout: 180) { outcome in
      guard outcome == .exited else { exit(0) }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.arguments = ["--permission-reopened"]
      NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
        _, error in
        if let error {
          flowLog.error("event=permission.relaunch_failed error=\(error.localizedDescription)")
        }
        exit(error == nil ? 0 : 1)
      }
    }
    withExtendedLifetime(monitor) { RunLoop.main.run(until: Date().addingTimeInterval(185)) }
    return true
  }
}

@MainActor final class ScreenAccess: NSObject, ObservableObject, NSWindowDelegate {
  @Published private(set) var granted = false
  @Published private(set) var status = ""
  private var panel: NSPanel?
  private var relaunch: Process?
  var capture: (() -> Void)?

  func prepareCapture() -> Bool {
    guard CGPreflightScreenCaptureAccess() else {
      show()
      return false
    }
    dismiss()
    return true
  }

  func show() {
    refresh()
    if panel == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 448, height: 370),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      panel.title = "Screen access"
      panel.isReleasedWhenClosed = false
      panel.hidesOnDeactivate = false
      panel.delegate = self
      panel.contentView = NSHostingView(rootView: ScreenAccessView(access: self))
      panel.center()
      self.panel = panel
    }
    NSApp.activate(ignoringOtherApps: true)
    panel?.makeKeyAndOrderFront(nil)
    flowLog.info("event=permission.setup_shown granted=\(self.granted)")
  }

  func refresh(preflight: () -> Bool = CGPreflightScreenCaptureAccess) {
    let wasGranted = granted
    granted = preflight()
    if granted {
      status = "Screen access is ready. Capture a region now, or use your configured shortcut."
    } else if status.isEmpty || wasGranted {
      status =
        "Allow screen-to-codex to capture the region you select. Nothing is sent until you press Send."
    }
  }

  func primaryAction(
    relaunchExecutable: URL? = Bundle.main.executableURL,
    requestAccess: () -> Bool = CGRequestScreenCaptureAccess,
    openSettings: (URL) -> Bool = { NSWorkspace.shared.open($0) }
  ) {
    if granted {
      guard prepareCapture() else { return }
      capture?()
      return
    }
    cancelRelaunch()
    do {
      let child = Process()
      child.executableURL = relaunchExecutable
      child.arguments = [PermissionRelaunch.argument, String(getpid())]
      child.standardInput = FileHandle.nullDevice
      child.standardOutput = FileHandle.nullDevice
      child.standardError = FileHandle.nullDevice
      child.terminationHandler = { [weak self] process in
        Task { @MainActor in
          guard self?.relaunch === process else { return }
          self?.relaunch = nil
          if self?.granted == false {
            self?.status = "Automatic reopening has ended. Open Settings again to resume setup."
          }
        }
      }
      try child.run()
      relaunch = child
      flowLog.info("event=permission.relaunch_armed")
      status =
        "Enable screen-to-codex in Screen & System Audio Recording. If macOS quits this app, it will reopen automatically."
    } catch {
      status =
        "Automatic reopening is unavailable. After allowing screen access, reopen screen-to-codex from Finder."
      flowLog.error("event=permission.relaunch_failed error=\(error.localizedDescription)")
    }
    if requestAccess() {
      refresh()
      return
    }
    let settings = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    if !openSettings(settings) {
      cancelRelaunch()
      status =
        "Open System Settings → Privacy & Security → Screen & System Audio Recording, then reopen screen-to-codex."
    }
  }

  func checkAgain() {
    refresh()
    if !granted {
      status = "Screen access is still unavailable. If it is already enabled, use the help below."
    }
  }

  func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }

  func dismiss() {
    cancelRelaunch()
    panel?.orderOut(nil)
    panel = nil
  }

  func cancelRelaunch() {
    let child = relaunch
    relaunch = nil
    if child?.isRunning == true { child?.terminate() }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    dismiss()
    return false
  }
}

private struct ScreenAccessView: View {
  @ObservedObject var access: ScreenAccess

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        Image(systemName: access.granted ? "checkmark.circle" : "viewfinder")
          .font(.system(size: 30)).accessibilityHidden(true)
        Text(access.granted ? "Ready to capture" : "Allow screenshots")
          .font(.title2.weight(.semibold))
      }
      Text(access.status).fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(access.status)
      if !access.granted {
        DisclosureGroup("Already enabled, but still blocked?") {
          VStack(alignment: .leading, spacing: 10) {
            Text(
              "An older app copy may hold the permission. Remove screen-to-codex with the − button in Settings, then add this copy with + and enable it."
            )
            Button("Show this app in Finder") { access.revealApp() }
          }.padding(.top, 8)
        }
        Text("Screenshots only. Audio and microphone recording are off.")
          .font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack {
        Button(access.granted ? "Close" : "Not Now") { access.dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        if !access.granted { Button("Check Again") { access.checkAgain() } }
        Button(access.granted ? "Capture Region" : "Open Settings") { access.primaryAction() }
          .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(minWidth: 448, minHeight: 370)
  }
}
