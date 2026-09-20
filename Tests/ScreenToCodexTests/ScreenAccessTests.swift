import AppKit
import Testing

@testable import ScreenToCodex

// Missing executable deterministically exercises a real Process.run failure.
private let missingHelper = URL(fileURLWithPath: "/dev/null/screen-to-codex")

@Test @MainActor func failedRecoveryStillOpensSettings() {
  let access = ScreenAccess()
  var destination: URL?
  access.primaryAction(
    relaunchExecutable: missingHelper, requestAccess: { false },
    openSettings: {
      destination = $0
      return true
    })
  #expect(
    destination?.absoluteString
      == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
}

@Test @MainActor func failedRecoveryExplainsManualReopen() {
  let access = ScreenAccess()
  access.primaryAction(
    relaunchExecutable: missingHelper, requestAccess: { false }, openSettings: { _ in true })
  #expect(access.status.contains("reopen screen-to-codex from Finder"))
}

@Test @MainActor func failedSettingsOpenExplainsManualNavigation() {
  let access = ScreenAccess()
  access.primaryAction(
    relaunchExecutable: missingHelper, requestAccess: { false }, openSettings: { _ in false })
  #expect(access.status.contains("Open System Settings → Privacy & Security"))
}

@Test @MainActor func successfulPermissionRequestDoesNotOpenSettings() {
  let access = ScreenAccess()
  var openedSettings = false
  access.primaryAction(
    relaunchExecutable: missingHelper, requestAccess: { true },
    openSettings: { _ in
      openedSettings = true
      return true
    })
  #expect(!openedSettings)
}

@Test @MainActor func failedRecoveryStillRequestsPermission() {
  let access = ScreenAccess()
  var requestedAccess = false
  access.primaryAction(
    relaunchExecutable: missingHelper,
    requestAccess: {
      requestedAccess = true
      return true
    },
    openSettings: { _ in true })
  #expect(requestedAccess)
}

@Test @MainActor func returningFromSettingsPreservesRecoveryGuidance() {
  let access = ScreenAccess()
  access.primaryAction(
    relaunchExecutable: missingHelper, requestAccess: { false }, openSettings: { _ in true })
  access.refresh(preflight: { false })
  #expect(access.status.contains("reopen screen-to-codex from Finder"))
}
