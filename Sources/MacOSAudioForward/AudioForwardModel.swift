import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AudioForwardModel: ObservableObject {
  @Published private(set) var peers: [DiscoveredPeer] = []
  @Published private(set) var connectingPeerID: String?
  @Published private(set) var sendingPeerID: String?
  @Published private(set) var sendingPeerName: String?
  @Published private(set) var incomingPeerName: String?
  @Published private(set) var currentOutputName = CoreAudioUtility.currentOutputName()
  @Published private(set) var networkStatus = "Starting…"
  @Published private(set) var lastError: String?
  @Published private(set) var launchAtLogin = false
  @Published private(set) var loginRequiresApproval = false

  private let capture = CoreAudioCapture()
  private let playback = PlaybackEngine()
  private let network: NetworkService
  private var outputRefreshTimer: Timer?
  private var incomingPacketCount = 0
  private var incomingFrameCount: UInt64 = 0

  init() {
    let defaults = UserDefaults.standard
    let instanceID: String
    if let stored = defaults.string(forKey: "instanceID") {
      instanceID = stored
    } else {
      instanceID = UUID().uuidString
      defaults.set(instanceID, forKey: "instanceID")
    }

    let localName = Host.current().localizedName
      ?? ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
    network = NetworkService(instanceID: instanceID, localName: localName, appVersion: version)
    configureServices()
    refreshLaunchAtLoginState()
  }

  func start() {
    CoreAudioUtility.cleanupStaleAggregates()
    do {
      try network.start()
    } catch {
      lastError = "Could not start Audio Forward: \(error.localizedDescription)"
      networkStatus = "Receiver unavailable"
    }
    outputRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in self?.refreshOutputName() }
    }
  }

  func stop() {
    outputRefreshTimer?.invalidate()
    outputRefreshTimer = nil
    capture.stop()
    playback.stop()
    network.stop()
  }

  func toggleSending(to peer: DiscoveredPeer) {
    lastError = nil
    if sendingPeerID == peer.id || connectingPeerID == peer.id {
      connectingPeerID = nil
      network.disconnect()
      return
    }
    capture.stop()
    sendingPeerID = nil
    sendingPeerName = nil
    connectingPeerID = peer.id
    networkStatus = "Connecting to \(peer.name)…"
    network.connect(to: peer)
  }

  func stopSending() {
    connectingPeerID = nil
    network.disconnect()
  }

  func dismissError() {
    lastError = nil
  }

  func openSoundSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }

  func openPrivacySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
      NSWorkspace.shared.open(url)
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      lastError = "Could not update Launch at Login: \(error.localizedDescription)"
    }
    refreshLaunchAtLoginState()
  }

  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  var activityText: String {
    switch (sendingPeerName, incomingPeerName, connectingPeerID) {
    case let (sending?, receiving?, _):
      return "Sending to \(sending) · receiving from \(receiving)"
    case let (sending?, nil, _):
      return "Sending system audio to \(sending)"
    case let (nil, receiving?, _):
      return "Receiving audio from \(receiving)"
    case (nil, nil, .some):
      return "Connecting over Thunderbolt…"
    default:
      return networkStatus
    }
  }

  var isActive: Bool {
    sendingPeerName != nil || incomingPeerName != nil || connectingPeerID != nil
  }

  private func configureServices() {
    capture.onAudio = { [weak network] payload, rate, channels, frames in
      network?.sendAudio(payload: payload, sampleRate: rate, channels: channels, frames: frames)
    }

    playback.onError = { [weak self] message in
      self?.lastError = message
    }

    network.onPeersChanged = { [weak self] peers in
      self?.peers = peers
    }
    network.onStatus = { [weak self] status in
      self?.networkStatus = status
    }
    network.onError = { [weak self] error in
      self?.lastError = error
    }
    network.onOutgoingReady = { [weak self] peer in
      guard let self else { return }
      do {
        try self.capture.start(remoteName: peer.name)
        self.connectingPeerID = nil
        self.sendingPeerID = peer.id
        self.sendingPeerName = peer.name
        self.networkStatus = "Connected over Thunderbolt Bridge"
        self.refreshOutputName()
      } catch {
        self.connectingPeerID = nil
        self.lastError = "Could not capture this Mac's audio: \(error.localizedDescription)"
        self.network.disconnect()
      }
    }
    network.onOutgoingStopped = { [weak self] reason in
      guard let self else { return }
      self.capture.stop()
      self.connectingPeerID = nil
      self.sendingPeerID = nil
      self.sendingPeerName = nil
      self.refreshOutputName()
      if let reason { self.lastError = "Audio forwarding stopped: \(reason)" }
    }
    network.onIncomingStarted = { [weak self] handshake in
      self?.incomingPeerName = handshake.name
      self?.incomingPacketCount = 0
      self?.incomingFrameCount = 0
    }
    network.onIncomingStopped = { [weak self] in
      guard let self else { return }
      UserDefaults.standard.set(self.incomingPacketCount, forKey: "diagnostics.lastReceivedPacketCount")
      UserDefaults.standard.set(self.incomingFrameCount, forKey: "diagnostics.lastReceivedFrameCount")
      UserDefaults.standard.set(Date(), forKey: "diagnostics.lastReceivedAt")
      self.incomingPeerName = nil
      self.playback.stop()
    }
    network.onAudio = { [weak self] message in
      self?.incomingPacketCount += 1
      self?.incomingFrameCount += UInt64(message.frames)
      self?.playback.enqueue(message)
    }
  }

  private func refreshOutputName() {
    currentOutputName = CoreAudioUtility.currentOutputName()
  }

  private func refreshLaunchAtLoginState() {
    let status = SMAppService.mainApp.status
    launchAtLogin = status == .enabled
    loginRequiresApproval = status == .requiresApproval
  }
}
