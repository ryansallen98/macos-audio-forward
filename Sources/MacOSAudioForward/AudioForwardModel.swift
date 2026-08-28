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
  @Published private(set) var preferredPeerID: String?
  @Published private(set) var preferredPeerName: String?
  @Published private(set) var audioForwardReady = false
  @Published private(set) var isAudioForwardSelected = false
  @Published private(set) var currentOutputName = CoreAudioUtility.currentOutputName()
  @Published private(set) var networkStatus = "Starting…"
  @Published private(set) var lastError: String?
  @Published private(set) var launchAtLogin = false
  @Published private(set) var loginRequiresApproval = false

  private let capture = CoreAudioCapture()
  private let playback = PlaybackEngine()
  private let network: NetworkService
  private var routeMonitorTimer: Timer?
  private var incomingPacketCount = 0
  private var incomingFrameCount: UInt64 = 0
  private var nextConnectionAttempt = Date.distantPast

  init() {
    let defaults = UserDefaults.standard
    let instanceID: String
    if let stored = defaults.string(forKey: "instanceID") {
      instanceID = stored
    } else {
      instanceID = UUID().uuidString
      defaults.set(instanceID, forKey: "instanceID")
    }
    preferredPeerID = defaults.string(forKey: "preferredPeerID")
    preferredPeerName = defaults.string(forKey: "preferredPeerName")

    let localName = Host.current().localizedName
      ?? ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
    network = NetworkService(instanceID: instanceID, localName: localName, appVersion: version)
    configureServices()
    refreshLaunchAtLoginState()
  }

  func start() {
    do {
      try network.start()
    } catch {
      lastError = "Could not start Audio Forward: \(error.localizedDescription)"
      networkStatus = "Receiver unavailable"
    }
    prepareAudioForwardOutput()
    refreshOutputState()
    routeMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in self?.refreshOutputState() }
    }
  }

  func stop() {
    routeMonitorTimer?.invalidate()
    routeMonitorTimer = nil
    capture.stop()
    playback.stop()
    network.stop()
  }

  func toggleSending(to peer: DiscoveredPeer) {
    lastError = nil
    if sendingPeerID == peer.id || connectingPeerID == peer.id {
      stopSending()
      return
    }
    selectDestination(peer)
    useAudioForward()
  }

  func stopSending() {
    capture.stopForwarding()
    capture.restoreFallbackOutput()
    connectingPeerID = nil
    sendingPeerID = nil
    sendingPeerName = nil
    network.disconnect()
    refreshOutputState()
  }

  func selectDestination(_ peer: DiscoveredPeer) {
    let changed = preferredPeerID != peer.id
    preferredPeerID = peer.id
    preferredPeerName = peer.name
    UserDefaults.standard.set(peer.id, forKey: "preferredPeerID")
    UserDefaults.standard.set(peer.name, forKey: "preferredPeerName")

    guard changed, isAudioForwardSelected else { return }
    capture.stopForwarding()
    connectingPeerID = nil
    sendingPeerID = nil
    sendingPeerName = nil
    nextConnectionAttempt = Date().addingTimeInterval(0.5)
    networkStatus = "Switching destination to \(peer.name)…"
    network.disconnect()
  }

  func useAudioForward() {
    lastError = nil
    if !audioForwardReady {
      prepareAudioForwardOutput()
      guard audioForwardReady else { return }
    }
    if preferredPeerID == nil, let onlyPeer = peers.first, peers.count == 1 {
      selectDestination(onlyPeer)
    }
    guard preferredPeerID != nil else {
      lastError = "Choose a destination Mac before using the Audio Forward output."
      return
    }
    do {
      try capture.selectForwardOutput()
      refreshOutputState()
    } catch {
      lastError = "Could not select Audio Forward: \(error.localizedDescription)"
    }
  }

  func retryAudioForwardOutput() {
    lastError = nil
    prepareAudioForwardOutput()
    refreshOutputState()
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

  var preferredPeerIsAvailable: Bool {
    preferredPeer != nil
  }

  var audioForwardDetail: String {
    guard let preferredPeerName else { return "Choose a destination below" }
    if sendingPeerID != nil { return "Forwarding to \(preferredPeerName)" }
    if connectingPeerID != nil { return "Connecting to \(preferredPeerName)…" }
    if preferredPeerIsAvailable { return "Routes to \(preferredPeerName)" }
    return isAudioForwardSelected
      ? "Waiting for \(preferredPeerName)"
      : "Routes to \(preferredPeerName) when available"
  }

  private func configureServices() {
    capture.onAudio = { [weak network] payload, rate, channels, frames in
      network?.sendAudio(payload: payload, sampleRate: rate, channels: channels, frames: frames)
    }

    playback.onError = { [weak self] message in
      self?.lastError = message
    }

    network.onPeersChanged = { [weak self] peers in
      guard let self else { return }
      self.peers = peers
      if self.preferredPeerID == nil, peers.count == 1, let peer = peers.first {
        self.selectDestination(peer)
      } else if let preferredPeerName = self.preferredPeerName,
        let matchingPeer = peers.first(where: {
          $0.name.localizedCaseInsensitiveCompare(preferredPeerName) == .orderedSame
        }), self.preferredPeerID != matchingPeer.id
      {
        self.preferredPeerID = matchingPeer.id
        UserDefaults.standard.set(matchingPeer.id, forKey: "preferredPeerID")
      }
      self.attemptConnectionIfNeeded()
    }
    network.onStatus = { [weak self] status in
      self?.networkStatus = status
    }
    network.onError = { [weak self] error in
      self?.lastError = error
    }
    network.onOutgoingReady = { [weak self] peer in
      guard let self else { return }
      guard self.isAudioForwardSelected, peer.id == self.preferredPeerID else {
        self.network.disconnect()
        return
      }
      do {
        try self.capture.startForwarding()
        self.connectingPeerID = nil
        self.sendingPeerID = peer.id
        self.sendingPeerName = peer.name
        self.networkStatus = "Connected over Thunderbolt Bridge"
        self.refreshOutputState()
      } catch {
        self.connectingPeerID = nil
        self.lastError = "Could not capture this Mac's audio: \(error.localizedDescription)"
        self.network.disconnect()
      }
    }
    network.onOutgoingStopped = { [weak self] reason in
      guard let self else { return }
      self.capture.stopForwarding()
      self.connectingPeerID = nil
      self.sendingPeerID = nil
      self.sendingPeerName = nil
      self.nextConnectionAttempt = Date().addingTimeInterval(2)
      self.refreshOutputState()
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

  private var preferredPeer: DiscoveredPeer? {
    if let preferredPeerID, let exact = peers.first(where: { $0.id == preferredPeerID }) {
      return exact
    }
    guard let preferredPeerName else { return nil }
    return peers.first {
      $0.name.localizedCaseInsensitiveCompare(preferredPeerName) == .orderedSame
    }
  }

  private func prepareAudioForwardOutput() {
    guard !audioForwardReady else { return }
    do {
      try capture.prepare()
      audioForwardReady = true
    } catch {
      audioForwardReady = false
      lastError = "Could not create the Audio Forward output: \(error.localizedDescription)"
    }
  }

  private func refreshOutputState() {
    guard let outputID = try? CoreAudioUtility.defaultOutputDevice() else {
      currentOutputName = "No output selected"
      return
    }

    let wasSelected = isAudioForwardSelected
    isAudioForwardSelected = capture.isForwardOutput(outputID)
    currentOutputName = CoreAudioUtility.name(of: outputID)

    if isAudioForwardSelected {
      attemptConnectionIfNeeded()
    } else {
      capture.rememberFallbackOutput(outputID)
      if wasSelected || sendingPeerID != nil || connectingPeerID != nil {
        capture.stopForwarding()
        connectingPeerID = nil
        sendingPeerID = nil
        sendingPeerName = nil
        network.disconnect()
        networkStatus = "Ready on Thunderbolt Bridge"
      }
    }
  }

  private func attemptConnectionIfNeeded() {
    guard isAudioForwardSelected,
      sendingPeerID == nil,
      connectingPeerID == nil,
      Date() >= nextConnectionAttempt
    else { return }

    guard let peer = preferredPeer else {
      if let preferredPeerName {
        networkStatus = "Waiting for \(preferredPeerName)…"
      } else {
        networkStatus = "Choose a destination for Audio Forward"
      }
      return
    }

    connectingPeerID = peer.id
    networkStatus = "Connecting to \(peer.name)…"
    nextConnectionAttempt = Date().addingTimeInterval(2)
    network.connect(to: peer)
  }

  private func refreshLaunchAtLoginState() {
    let status = SMAppService.mainApp.status
    launchAtLogin = status == .enabled
    loginRequiresApproval = status == .requiresApproval
  }
}
