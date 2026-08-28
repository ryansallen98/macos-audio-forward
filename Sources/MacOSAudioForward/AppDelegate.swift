import AppKit
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private lazy var model = AudioForwardModel()
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private var instanceLockFileDescriptor: Int32 = -1
  private var isPrimaryInstance = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard claimPrimaryInstance() else {
      activateExistingInstance()
      NSApp.terminate(nil)
      return
    }
    isPrimaryInstance = true
    NSApp.setActivationPolicy(.accessory)
    configurePopover()
    configureStatusItem()
    model.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    if isPrimaryInstance {
      model.stop()
    }
    releasePrimaryInstance()
  }

  private func claimPrimaryInstance() -> Bool {
    guard let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return true }

    let lockURL = applicationSupport.appendingPathComponent(
      "dev.rallen.macos-audio-forward.instance.lock",
      isDirectory: false)
    let descriptor = Darwin.open(
      lockURL.path,
      O_CREAT | O_RDWR,
      S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { return true }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(descriptor)
      return false
    }
    instanceLockFileDescriptor = descriptor
    return true
  }

  private func releasePrimaryInstance() {
    guard instanceLockFileDescriptor >= 0 else { return }
    flock(instanceLockFileDescriptor, LOCK_UN)
    Darwin.close(instanceLockFileDescriptor)
    instanceLockFileDescriptor = -1
  }

  private func activateExistingInstance() {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
      .activate()
  }

  private func configureStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = "dev.rallen.macos-audio-forward.status-item"
    statusItem.isVisible = true
    guard let button = statusItem.button else { return }
    button.image = NSImage(
      systemSymbolName: "speaker.wave.2.fill",
      accessibilityDescription: "Audio Forward")
    button.image?.isTemplate = true
    button.toolTip = "Audio Forward"
    button.target = self
    button.action = #selector(togglePopover)
  }

  private func configurePopover() {
    popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
    popover.contentViewController = NSHostingController(rootView: ContentView(model: model))
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(nil)
      return
    }

    let contentHeight = preferredContentHeight(on: button.window?.screen)
    popover.contentSize = NSSize(width: 410, height: contentHeight)
    popover.contentViewController = NSHostingController(
      rootView: ContentView(model: model, contentHeight: contentHeight))
    model.setInterfaceVisible(true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }

  func popoverDidClose(_ notification: Notification) {
    model.setInterfaceVisible(false)
  }

  private func preferredContentHeight(on screen: NSScreen?) -> CGFloat {
    let availableHeight = (screen?.visibleFrame.height ?? 610) - 24
    return max(330, min(600, availableHeight))
  }
}
