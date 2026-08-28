import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let model = AudioForwardModel()
  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private var settingsPanel: NSPanel?

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
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = statusItem.button else { return }
    button.image = NSImage(
      systemSymbolName: "speaker.wave.2.fill",
      accessibilityDescription: "macOS Audio Forward")
    button.image?.isTemplate = true
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
    if let settingsPanel, settingsPanel.isVisible {
      settingsPanel.close()
      return
    }
    if popover.isShown {
      popover.performClose(nil)
      return
    }

    let clickedScreen = screen(containing: NSEvent.mouseLocation)
    let statusItemScreen = button.window?.screen
    let contentHeight = preferredContentHeight(on: clickedScreen ?? statusItemScreen)
    if let clickedScreen, statusItemScreen?.frame != clickedScreen.frame {
      showSettingsPanel(on: clickedScreen, contentHeight: contentHeight)
      return
    }

    popover.contentSize = NSSize(width: 410, height: contentHeight)
    popover.contentViewController = NSHostingController(
      rootView: ContentView(model: model, contentHeight: contentHeight))
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }

  private func showSettingsPanel(on screen: NSScreen, contentHeight: CGFloat) {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 410, height: contentHeight),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    panel.title = "macOS Audio Forward"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isFloatingPanel = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.moveToActiveSpace, .transient]
    panel.delegate = self
    panel.contentViewController = NSHostingController(
      rootView: ContentView(model: model, contentHeight: contentHeight))

    let visible = screen.visibleFrame
    let mouseX = NSEvent.mouseLocation.x
    let x = min(max(mouseX - 205, visible.minX + 8), visible.maxX - 418)
    panel.setFrameTopLeftPoint(NSPoint(x: x, y: visible.maxY - 8))
    settingsPanel = panel
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private func preferredContentHeight(on screen: NSScreen?) -> CGFloat {
    let availableHeight = (screen?.visibleFrame.height ?? 610) - 24
    return max(330, min(600, availableHeight))
  }

  private func screen(containing point: NSPoint) -> NSScreen? {
    NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
  }

  func windowWillClose(_ notification: Notification) {
    if notification.object as? NSPanel === settingsPanel { settingsPanel = nil }
  }

  func windowDidResignKey(_ notification: Notification) {
    if notification.object as? NSPanel === settingsPanel { settingsPanel?.close() }
  }
}
