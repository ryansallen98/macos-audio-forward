import AVFoundation
import Foundation

final class PlaybackEngine {
  var onError: ((String) -> Void)?

  private let queue = DispatchQueue(label: "dev.rallen.audio-forward.playback", qos: .userInteractive)
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var varispeed: AVAudioUnitVarispeed?
  private var format: AVAudioFormat?
  private var queuedFrames: Int = 0
  private var startedPlayback = false
  private var lastSequence: UInt32?
  private var configurationObserver: NSObjectProtocol?

  init() {
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.queue.async { self?.restartAfterOutputChange() }
    }
  }

  deinit {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
  }

  func enqueue(_ message: ForwardMessage) {
    guard message.kind == .audio else { return }
    queue.async { [weak self] in
      self?.enqueueLocked(message)
    }
  }

  func stop() {
    queue.async { [weak self] in self?.tearDownLocked() }
  }

  private func enqueueLocked(_ message: ForwardMessage) {
    guard message.channels == 2, message.sampleRate > 0, message.frames > 0 else {
      reportError("The peer sent an unsupported audio format.")
      return
    }

    let expectedByteCount = Int(message.frames) * Int(message.channels) * MemoryLayout<Float>.size
    guard message.payload.count == expectedByteCount else {
      reportError("The peer sent a malformed audio buffer.")
      return
    }

    if let lastSequence, message.sequence != lastSequence &+ 1 {
      // TCP preserves order, so a sequence discontinuity means the sender restarted.
      player?.stop()
      player?.reset()
      queuedFrames = 0
      startedPlayback = false
    }
    lastSequence = message.sequence

    do {
      try ensureEngine(sampleRate: Double(message.sampleRate), channels: AVAudioChannelCount(message.channels))
    } catch {
      reportError("Could not start the receiving output: \(error.localizedDescription)")
      return
    }

    guard let format, let player else { return }
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(message.frames))
    else {
      reportError("Could not allocate an audio playback buffer.")
      return
    }

    buffer.frameLength = AVAudioFrameCount(message.frames)
    guard let destinationChannels = buffer.floatChannelData else {
      reportError("Could not access the audio playback buffer.")
      return
    }
    message.payload.withUnsafeBytes { raw in
      guard let source = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
      for frame in 0..<Int(message.frames) {
        destinationChannels[0][frame] = source[frame * 2]
        destinationChannels[1][frame] = source[frame * 2 + 1]
      }
    }

    let frameCount = Int(message.frames)
    queuedFrames += frameCount
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      self?.queue.async {
        guard let self else { return }
        self.queuedFrames = max(0, self.queuedFrames - frameCount)
        self.adjustClockRate()
      }
    }

    if !startedPlayback, queuedFrames >= 1_024 {
      player.play()
      startedPlayback = true
    }
    adjustClockRate()

    if queuedFrames > 12_000 {
      // Cap runaway latency after sleep/wake or an output-device stall.
      player.stop()
      player.reset()
      queuedFrames = 0
      startedPlayback = false
    }
  }

  private func ensureEngine(sampleRate: Double, channels: AVAudioChannelCount) throws {
    if let format,
      abs(format.sampleRate - sampleRate) < 1,
      format.channelCount == channels,
      engine?.isRunning == true
    {
      return
    }

    tearDownLocked()
    guard
      let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: false)
    else {
      throw PlaybackError.invalidFormat
    }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let varispeed = AVAudioUnitVarispeed()
    engine.attach(player)
    engine.attach(varispeed)
    engine.connect(player, to: varispeed, format: sourceFormat)
    engine.connect(varispeed, to: engine.mainMixerNode, format: sourceFormat)
    engine.prepare()
    try engine.start()

    self.engine = engine
    self.player = player
    self.varispeed = varispeed
    self.format = sourceFormat
    queuedFrames = 0
    startedPlayback = false
  }

  private func adjustClockRate() {
    guard let varispeed else { return }
    let targetFrames = 2_048
    let error = queuedFrames - targetFrames
    let correction = max(-0.002, min(0.002, Double(error) / 1_000_000.0))
    varispeed.rate = Float(1.0 + correction)
  }

  private func restartAfterOutputChange() {
    guard engine != nil else { return }
    tearDownLocked()
  }

  private func tearDownLocked() {
    player?.stop()
    engine?.stop()
    if let player, let engine { engine.detach(player) }
    if let varispeed, let engine { engine.detach(varispeed) }
    player = nil
    varispeed = nil
    engine = nil
    format = nil
    queuedFrames = 0
    startedPlayback = false
    lastSequence = nil
  }

  private func reportError(_ message: String) {
    DispatchQueue.main.async { [weak self] in self?.onError?(message) }
  }
}

private enum PlaybackError: LocalizedError {
  case invalidFormat

  var errorDescription: String? {
    "The received PCM format is not supported."
  }
}
