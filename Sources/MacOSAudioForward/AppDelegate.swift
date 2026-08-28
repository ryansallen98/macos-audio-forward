import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = AudioForwardModel()
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configurePopover()
    configureStatusItem()
    model.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    model.stop()
  }

  private func configureStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = "dev.rallen.macos-audio-forward.status-item"
    statusItem.isVisible = true
    guard let button = statusItem.button else { return }
    button.image = NSImage(
      systemSymbolName: "speaker.wave.2.fill",
      accessibilityDescription: "macOS Audio Forward")
    button.image?.isTemplate = true
    button.title = " Audio"
    button.toolTip = "macOS Audio Forward"
    button.target = self
    button.action = #selector(togglePopover)
  }

  private func configurePopover() {
    popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
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
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }

  private func preferredContentHeight(on screen: NSScreen?) -> CGFloat {
    let availableHeight = (screen?.visibleFrame.height ?? 610) - 24
    return max(330, min(600, availableHeight))
  }
}
