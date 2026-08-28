import Foundation
import Network

struct DiscoveredPeer: Identifiable {
  let id: String
  let name: String
  let version: String
  let endpoint: NWEndpoint
  let interface: NWInterface

  static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
    lhs.id == rhs.id && lhs.endpoint == rhs.endpoint && lhs.interface == rhs.interface
  }
}

extension DiscoveredPeer: Equatable {}

final class NetworkService {
  static let serviceType = "_rallenaudio._tcp"

  var onPeersChanged: (([DiscoveredPeer]) -> Void)?
  var onOutgoingReady: ((DiscoveredPeer) -> Void)?
  var onOutgoingStopped: ((String?) -> Void)?
  var onIncomingStarted: ((ForwardHandshake) -> Void)?
  var onIncomingStopped: (() -> Void)?
  var onAudio: ((ForwardMessage) -> Void)?
  var onStatus: ((String) -> Void)?
  var onError: ((String) -> Void)?

  private let instanceID: String
  private let localName: String
  private let appVersion: String
  private let queue = DispatchQueue(label: "dev.rallen.audio-forward.network", qos: .userInteractive)

  private var listener: NWListener?
  private var browser: NWBrowser?
  private var outgoingConnection: NWConnection?
  private var outgoingPeer: DiscoveredPeer?
  private var outgoingTimeout: DispatchWorkItem?
  private var outgoingHeartbeat: DispatchSourceTimer?
  private var lastOutgoingPong = DispatchTime.now().uptimeNanoseconds
  private var outgoingSequence: UInt32 = 0
  private var outgoingDecoder = ForwardStreamDecoder()
  private var incomingConnection: NWConnection?
  private var incomingDecoder = ForwardStreamDecoder()
  private var incomingHandshake: ForwardHandshake?
  private var incomingHandshakeTimeout: DispatchWorkItem?
  private var peerMetadataByService: [String: [String: String]] = [:]
  private var started = false

  init(instanceID: String, localName: String, appVersion: String) {
    self.instanceID = instanceID
    self.localName = localName
    self.appVersion = appVersion
  }

  func start() throws {
    let parameters = Self.tcpParameters()
    let listener = try NWListener(using: parameters)
    var service = NWListener.Service(
      name: localName,
      type: Self.serviceType,
      domain: nil,
      txtRecord: NWTXTRecord([
        "id": instanceID,
        "name": localName,
        "version": appVersion,
        "role": "sendrecv",
      ]))
    service.noAutoRename = false
    listener.service = service
    listener.newConnectionLimit = 2
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    listener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.reportStatus("Ready on Thunderbolt Bridge")
      case .waiting(let error):
        self.reportStatus("Waiting for network: \(error.localizedDescription)")
      case .failed(let error):
        self.reportError("Audio receiver failed: \(error.localizedDescription)")
      case .cancelled:
        self.reportStatus("Receiver stopped")
      default:
        break
      }
    }
    listener.start(queue: queue)
    self.listener = listener
    started = true
    startBrowserLocked(clearPeers: false)
  }

  func stop() {
    queue.async { [weak self] in
      guard let self else { return }
      self.started = false
      self.stopSendingLocked(reason: nil)
      self.incomingHandshakeTimeout?.cancel()
      self.incomingHandshakeTimeout = nil
      self.incomingConnection?.cancel()
      self.incomingConnection = nil
      self.listener?.cancel()
      self.browser?.cancel()
      self.listener = nil
      self.browser = nil
    }
  }

  func connect(to peer: DiscoveredPeer) {
    queue.async { [weak self] in
      guard let self else { return }
      self.stopSendingLocked(reason: nil)
      self.outgoingSequence = 0
      self.outgoingDecoder = ForwardStreamDecoder()
      self.outgoingPeer = peer

      let parameters = Self.tcpParameters()
      parameters.requiredInterface = peer.interface
      let connection = NWConnection(to: peer.endpoint, using: parameters)
      self.outgoingConnection = connection
      connection.stateUpdateHandler = { [weak self, weak connection] state in
        guard let self, let connection else { return }
        self.handleOutgoingState(state, connection: connection, peer: peer)
      }
      connection.start(queue: self.queue)
      let timeout = DispatchWorkItem { [weak self, weak connection] in
        guard let self, let connection, connection === self.outgoingConnection else { return }
        guard connection.state != .ready else { return }
        self.stopSendingLocked(reason: "The Thunderbolt connection attempt timed out and will retry.")
        self.restartBrowserLocked()
      }
      self.outgoingTimeout = timeout
      self.queue.asyncAfter(deadline: .now() + 6, execute: timeout)
    }
  }

  func disconnect() {
    queue.async { [weak self] in
      self?.stopSendingLocked(reason: nil)
    }
  }

  func sendAudio(payload: Data, sampleRate: UInt32, channels: UInt16, frames: UInt32) {
    queue.async { [weak self] in
      guard let self, let connection = self.outgoingConnection else { return }
      let message = ForwardMessage(
        kind: .audio,
        channels: channels,
        sampleRate: sampleRate,
        frames: frames,
        sequence: self.outgoingSequence,
        payload: payload
      )
      self.outgoingSequence &+= 1
      self.sendOutgoing(message, over: connection)
    }
  }

  private static func tcpParameters() -> NWParameters {
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    tcp.connectionTimeout = 5
    tcp.enableKeepalive = true
    tcp.keepaliveIdle = 2
    tcp.keepaliveInterval = 2
    let parameters = NWParameters(tls: nil, tcp: tcp)
    parameters.includePeerToPeer = false
    parameters.serviceClass = .interactiveVoice
    return parameters
  }

  private func startBrowserLocked(clearPeers: Bool) {
    guard started else { return }
    if clearPeers {
      peerMetadataByService.removeAll()
      DispatchQueue.main.async { [weak self] in self?.onPeersChanged?([]) }
    }

    let browser = NWBrowser(
      for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
      using: Self.tcpParameters())
    browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
      guard let self, let browser, browser === self.browser else { return }
      self.updatePeers(from: results)
    }
    browser.stateUpdateHandler = { [weak self, weak browser] state in
      guard let self, let browser, browser === self.browser else { return }
      if case .failed(let error) = state {
        self.reportError("Peer discovery failed: \(error.localizedDescription)")
        self.queue.asyncAfter(deadline: .now() + 1) { [weak self, weak browser] in
          guard let self, let browser, browser === self.browser else { return }
          self.restartBrowserLocked()
        }
      }
    }
    self.browser = browser
    browser.start(queue: queue)
  }

  private func restartBrowserLocked() {
    guard started else { return }
    browser?.browseResultsChangedHandler = nil
    browser?.stateUpdateHandler = nil
    browser?.cancel()
    browser = nil
    startBrowserLocked(clearPeers: true)
  }

  private func updatePeers(from results: Set<NWBrowser.Result>) {
    var byID: [String: DiscoveredPeer] = [:]
    var activeServices = Set<String>()

    for result in results {
      guard let bridgeInterface = result.interfaces.first(where: { $0.name == "bridge0" }) else {
        continue
      }

      let serviceName = Self.serviceName(from: result.endpoint)
      activeServices.insert(serviceName)
      var txt = peerMetadataByService[serviceName] ?? [:]
      if case .bonjour(let record) = result.metadata, !record.dictionary.isEmpty {
        txt = record.dictionary
        peerMetadataByService[serviceName] = txt
      }

      let peerID = txt["id"] ?? serviceName
      guard peerID != instanceID else { continue }
      let name = txt["name"] ?? serviceName
      let peer = DiscoveredPeer(
        id: peerID,
        name: name,
        version: txt["version"] ?? "Unknown",
        endpoint: result.endpoint,
        interface: bridgeInterface
      )
      byID[peerID] = peer
    }

    peerMetadataByService = peerMetadataByService.filter { activeServices.contains($0.key) }

    let peers = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    DispatchQueue.main.async { [weak self] in
      self?.onPeersChanged?(peers)
    }
  }

  private static func serviceName(from endpoint: NWEndpoint) -> String {
    if case .service(let name, _, _, _) = endpoint { return name }
    return endpoint.debugDescription
  }

  private func handleOutgoingState(
    _ state: NWConnection.State,
    connection: NWConnection,
    peer: DiscoveredPeer
  ) {
    guard connection === outgoingConnection else { return }
    switch state {
    case .ready:
      outgoingTimeout?.cancel()
      outgoingTimeout = nil
      let actualInterface = connection.currentPath?.availableInterfaces.first(where: { $0.name == "bridge0" })
      guard actualInterface != nil else {
        stopSendingLocked(reason: "The connection did not use Thunderbolt Bridge.")
        return
      }
      do {
        let hello = try ForwardMessage.hello(
          ForwardHandshake(id: instanceID, name: localName, version: appVersion))
        sendOutgoing(hello, over: connection)
        receiveOutgoingControl(on: connection)
        startOutgoingHeartbeat(on: connection)
        DispatchQueue.main.async { [weak self] in self?.onOutgoingReady?(peer) }
      } catch {
        stopSendingLocked(reason: error.localizedDescription)
      }
    case .waiting(let error):
      reportStatus("Connecting to \(peer.name): \(error.localizedDescription)")
    case .failed(let error):
      stopSendingLocked(reason: error.localizedDescription)
    case .cancelled:
      if outgoingConnection === connection {
        stopSendingLocked(reason: nil)
      }
    default:
      break
    }
  }

  private func stopSendingLocked(reason: String?) {
    outgoingTimeout?.cancel()
    outgoingTimeout = nil
    outgoingHeartbeat?.setEventHandler {}
    outgoingHeartbeat?.cancel()
    outgoingHeartbeat = nil
    if let connection = outgoingConnection {
      if connection.state == .ready {
        sendOutgoing(
          ForwardMessage(
            kind: .goodbye,
            channels: 0,
            sampleRate: 0,
            frames: 0,
            sequence: outgoingSequence,
            payload: Data()),
          over: connection)
      }
      connection.stateUpdateHandler = nil
      connection.cancel()
    }
    let hadConnection = outgoingConnection != nil || outgoingPeer != nil
    outgoingConnection = nil
    outgoingPeer = nil
    if hadConnection {
      DispatchQueue.main.async { [weak self] in self?.onOutgoingStopped?(reason) }
    } else if let reason {
      reportError(reason)
    }
  }

  private func accept(_ connection: NWConnection) {
    if let existing = incomingConnection {
      stopIncoming(existing, error: nil)
    }
    incomingConnection = connection
    incomingDecoder = ForwardStreamDecoder()
    incomingHandshake = nil
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection, connection === self.incomingConnection else { return }
      switch state {
      case .ready:
        guard
          let path = connection.currentPath,
          let bridgeInterface = path.availableInterfaces.first(where: { $0.name == "bridge0" }),
          path.usesInterfaceType(bridgeInterface.type)
        else {
          self.stopIncoming(connection, error: "Rejected a connection outside Thunderbolt Bridge.")
          return
        }
        let timeout = DispatchWorkItem { [weak self, weak connection] in
          guard let self, let connection,
            connection === self.incomingConnection,
            self.incomingHandshake == nil
          else { return }
          self.stopIncoming(connection, error: "The peer did not complete its audio handshake.")
        }
        self.incomingHandshakeTimeout = timeout
        self.queue.asyncAfter(deadline: .now() + 3, execute: timeout)
        self.receiveIncoming(on: connection)
      case .failed(let error):
        self.stopIncoming(connection, error: error.localizedDescription)
      case .cancelled:
        self.stopIncoming(connection, error: nil)
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  private func receiveIncoming(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) {
      [weak self, weak connection] content, _, isComplete, error in
      guard let self, let connection, connection === self.incomingConnection else { return }

      if let content, !content.isEmpty {
        do {
          for message in try self.incomingDecoder.append(content) {
            try self.handleIncoming(message)
          }
        } catch {
          self.stopIncoming(connection, error: error.localizedDescription)
          return
        }
      }

      if let error {
        self.stopIncoming(connection, error: error.localizedDescription)
      } else if isComplete {
        self.stopIncoming(connection, error: nil)
      } else {
        self.receiveIncoming(on: connection)
      }
    }
  }

  private func handleIncoming(_ message: ForwardMessage) throws {
    switch message.kind {
    case .hello:
      let handshake = try JSONDecoder().decode(ForwardHandshake.self, from: message.payload)
      incomingHandshakeTimeout?.cancel()
      incomingHandshakeTimeout = nil
      incomingHandshake = handshake
      DispatchQueue.main.async { [weak self] in self?.onIncomingStarted?(handshake) }
    case .audio:
      guard incomingHandshake != nil else { return }
      // Audio must never wait behind AppKit or SwiftUI work. PlaybackEngine owns
      // its dedicated producer queue and accepts packets directly from here.
      onAudio?(message)
    case .goodbye:
      if let connection = incomingConnection {
        stopIncoming(connection, error: nil)
      }
    case .ping:
      guard incomingHandshake != nil, let connection = incomingConnection else { return }
      sendIncomingControl(Self.pingMessage, over: connection)
    }
  }

  private func stopIncoming(_ connection: NWConnection, error: String?) {
    guard connection === incomingConnection else { return }
    incomingHandshakeTimeout?.cancel()
    incomingHandshakeTimeout = nil
    connection.stateUpdateHandler = nil
    connection.cancel()
    incomingConnection = nil
    incomingHandshake = nil
    DispatchQueue.main.async { [weak self] in
      self?.onIncomingStopped?()
      if let error { self?.onError?("Incoming stream ended: \(error)") }
    }
  }

  private func receiveOutgoingControl(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
      [weak self, weak connection] content, _, isComplete, error in
      guard let self, let connection, connection === self.outgoingConnection else { return }
      if let content, !content.isEmpty {
        do {
          let messages = try self.outgoingDecoder.append(content)
          if messages.contains(where: { $0.kind == .ping }) {
            self.lastOutgoingPong = DispatchTime.now().uptimeNanoseconds
          }
          if messages.contains(where: { $0.kind == .goodbye }) {
            self.stopSendingLocked(reason: nil)
            return
          }
        } catch {
          self.stopSendingLocked(reason: error.localizedDescription)
          return
        }
      }
      if let error {
        self.stopSendingLocked(reason: error.localizedDescription)
      } else if isComplete {
        self.stopSendingLocked(reason: nil)
      } else {
        self.receiveOutgoingControl(on: connection)
      }
    }
  }

  private func startOutgoingHeartbeat(on connection: NWConnection) {
    outgoingHeartbeat?.cancel()
    lastOutgoingPong = DispatchTime.now().uptimeNanoseconds
    let heartbeat = DispatchSource.makeTimerSource(queue: queue)
    heartbeat.schedule(
      deadline: .now() + 1,
      repeating: .seconds(1),
      leeway: .milliseconds(100))
    heartbeat.setEventHandler { [weak self, weak connection] in
      guard let self, let connection, connection === self.outgoingConnection else { return }
      let now = DispatchTime.now().uptimeNanoseconds
      let secondsSincePong = Double(now - self.lastOutgoingPong) / 1_000_000_000
      guard secondsSincePong <= 4 else {
        self.stopSendingLocked(
          reason: "The Thunderbolt audio link stopped responding and will reconnect.")
        self.restartBrowserLocked()
        return
      }
      self.sendOutgoing(Self.pingMessage, over: connection)
    }
    outgoingHeartbeat = heartbeat
    heartbeat.resume()
  }

  private static var pingMessage: ForwardMessage {
    ForwardMessage(
      kind: .ping,
      channels: 0,
      sampleRate: 0,
      frames: 0,
      sequence: 0,
      payload: Data())
  }

  private func sendOutgoing(_ message: ForwardMessage, over connection: NWConnection) {
    connection.send(content: message.encoded(), completion: .contentProcessed { [weak self] error in
      guard let self, connection === self.outgoingConnection else { return }
      if let error { self.stopSendingLocked(reason: error.localizedDescription) }
    })
  }

  private func sendIncomingControl(_ message: ForwardMessage, over connection: NWConnection) {
    connection.send(content: message.encoded(), completion: .contentProcessed { [weak self] error in
      guard let self, connection === self.incomingConnection else { return }
      if let error { self.stopIncoming(connection, error: error.localizedDescription) }
    })
  }

  private func reportStatus(_ message: String) {
    DispatchQueue.main.async { [weak self] in self?.onStatus?(message) }
  }

  private func reportError(_ message: String) {
    DispatchQueue.main.async { [weak self] in self?.onError?(message) }
  }
}
