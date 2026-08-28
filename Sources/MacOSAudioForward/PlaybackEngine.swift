import AudioForwardBuffer
import AVFoundation
import Foundation

struct PlaybackMetrics: Equatable {
  static let idle = PlaybackMetrics(
    bufferedMilliseconds: 0,
    targetMilliseconds: 70,
    arrivalJitterMilliseconds: 0,
    playbackRate: 1,
    underrunEvents: 0,
    overflowEvents: 0,
    trimmedFrames: 0,
    receivedPackets: 0,
    receivedFrames: 0,
    isPrimed: false,
    isRecovering: false)

  let bufferedMilliseconds: Double
  let targetMilliseconds: Double
  let arrivalJitterMilliseconds: Double
  let playbackRate: Double
  let underrunEvents: UInt64
  let overflowEvents: UInt64
  let trimmedFrames: UInt64
  let receivedPackets: UInt64
  let receivedFrames: UInt64
  let isPrimed: Bool
  let isRecovering: Bool

  var qualityText: String {
    if !isPrimed { return "Buffering" }
    if isRecovering { return "Adapting" }
    return "Stable"
  }
}

final class PlaybackEngine {
  var onError: ((String) -> Void)?
  var onMetrics: ((PlaybackMetrics) -> Void)?
  var onSessionEnded: ((PlaybackMetrics) -> Void)?

  private let queue = DispatchQueue(label: "dev.rallen.audio-forward.playback", qos: .userInteractive)
  private var engine: AVAudioEngine?
  private var sourceNode: AVAudioSourceNode?
  private var varispeed: AVAudioUnitVarispeed?
  private var format: AVAudioFormat?
  private var ringBuffer: OpaquePointer?
  private var controllerTimer: DispatchSourceTimer?

  private var sampleRate = 48_000.0
  private var targetLatencySeconds = 0.070
  private let minimumLatencySeconds = 0.055
  private let maximumLatencySeconds = 0.180
  private var filteredBufferError = 0.0
  private var integralBufferError = 0.0
  private var playbackRate = 1.0
  private var controllerTicks = 0
  private var stableTicks = 0
  private var lastUnderrunTick = -1_000
  private var lastControllerUnderruns: UInt64 = 0

  private var lastSequence: UInt32?
  private var lastArrivalNanoseconds: UInt64?
  private var previousPacketDurationNanoseconds: Double?
  private var arrivalJitterMilliseconds = 0.0
  private var receivedPackets: UInt64 = 0
  private var receivedFrames: UInt64 = 0
  private var lastMetrics = PlaybackMetrics.idle
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
    controllerTimer?.cancel()
    if let ringBuffer {
      AFAudioRingBufferDestroy(ringBuffer)
    }
  }

  func enqueue(_ message: ForwardMessage) {
    guard message.kind == .audio else { return }
    let arrivalNanoseconds = DispatchTime.now().uptimeNanoseconds
    queue.async { [weak self] in
      self?.enqueueLocked(message, arrivalNanoseconds: arrivalNanoseconds)
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self else { return }
      let summary = self.currentMetrics()
      self.tearDownLocked(resetSession: true)
      DispatchQueue.main.async { [weak self] in
        self?.onSessionEnded?(summary)
        self?.onMetrics?(.idle)
      }
    }
  }

  private func enqueueLocked(_ message: ForwardMessage, arrivalNanoseconds: UInt64) {
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
      resetBufferedAudioLocked()
    }
    lastSequence = message.sequence
    updateArrivalJitter(for: message, arrivalNanoseconds: arrivalNanoseconds)

    do {
      try ensureEngine(
        sampleRate: Double(message.sampleRate),
        channels: AVAudioChannelCount(message.channels))
    } catch {
      reportError("Could not start the receiving output: \(error.localizedDescription)")
      return
    }

    guard let ringBuffer else { return }
    let writtenFrames = message.payload.withUnsafeBytes { rawBuffer -> UInt32 in
      guard let samples = rawBuffer.baseAddress?.assumingMemoryBound(to: Float.self) else { return 0 }
      return AFAudioRingBufferWriteStereoInterleaved(ringBuffer, samples, message.frames)
    }
    receivedPackets &+= 1
    receivedFrames &+= UInt64(writtenFrames)
  }

  private func ensureEngine(sampleRate: Double, channels: AVAudioChannelCount) throws {
    if let format,
      abs(format.sampleRate - sampleRate) < 1,
      format.channelCount == channels,
      engine?.isRunning == true,
      ringBuffer != nil
    {
      return
    }

    tearDownAudioGraphLocked()
    guard
      let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: false)
    else {
      throw PlaybackError.invalidFormat
    }

    let capacityFrames = UInt32(max(16_384, Int(sampleRate * 0.5)))
    let startupFrames = UInt32(sampleRate * targetLatencySeconds)
    let fadeFrames = UInt32(max(64, Int(sampleRate * 0.005)))
    guard let ringBuffer = AFAudioRingBufferCreate(capacityFrames, startupFrames, fadeFrames) else {
      throw PlaybackError.bufferAllocationFailed
    }

    let engine = AVAudioEngine()
    let sourceNode = AVAudioSourceNode(format: sourceFormat) {
      _, _, frameCount, audioBufferList -> OSStatus in
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      guard
        buffers.count >= 2,
        let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
        let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
      else {
        for buffer in buffers {
          if let data = buffer.mData {
            memset(data, 0, Int(buffer.mDataByteSize))
          }
        }
        return noErr
      }
      _ = AFAudioRingBufferReadStereoPlanar(ringBuffer, left, right, frameCount)
      return noErr
    }
    let varispeed = AVAudioUnitVarispeed()
    varispeed.rate = 1

    engine.attach(sourceNode)
    engine.attach(varispeed)
    engine.connect(sourceNode, to: varispeed, format: sourceFormat)
    engine.connect(varispeed, to: engine.mainMixerNode, format: sourceFormat)
    engine.mainMixerNode.outputVolume = 1
    engine.prepare()

    do {
      try engine.start()
    } catch {
      engine.detach(sourceNode)
      engine.detach(varispeed)
      AFAudioRingBufferDestroy(ringBuffer)
      throw error
    }

    self.engine = engine
    self.sourceNode = sourceNode
    self.varispeed = varispeed
    self.format = sourceFormat
    self.ringBuffer = ringBuffer
    self.sampleRate = sampleRate
    resetControllerLocked()
    startControllerTimerLocked()
  }

  private func startControllerTimerLocked() {
    guard controllerTimer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(5))
    timer.setEventHandler { [weak self] in self?.controllerTickLocked() }
    timer.resume()
    controllerTimer = timer
  }

  private func controllerTickLocked() {
    guard let ringBuffer, let varispeed else { return }
    let stats = AFAudioRingBufferGetStats(ringBuffer)
    controllerTicks += 1

    if stats.underrun_events > lastControllerUnderruns {
      let addedLatency = Double(stats.underrun_events - lastControllerUnderruns) * 0.015
      targetLatencySeconds = min(maximumLatencySeconds, targetLatencySeconds + addedLatency)
      AFAudioRingBufferSetStartupFrames(ringBuffer, UInt32(sampleRate * targetLatencySeconds))
      stableTicks = 0
      filteredBufferError = 0
      integralBufferError = 0
      lastUnderrunTick = controllerTicks
    } else if stats.primed {
      stableTicks += 1
      if stableTicks >= 600, targetLatencySeconds > minimumLatencySeconds {
        targetLatencySeconds = max(minimumLatencySeconds, targetLatencySeconds - 0.005)
        AFAudioRingBufferSetStartupFrames(ringBuffer, UInt32(sampleRate * targetLatencySeconds))
        stableTicks = 0
      }
    }
    lastControllerUnderruns = stats.underrun_events

    let targetFrames = max(1, sampleRate * targetLatencySeconds)
    let rawError = (Double(stats.available_frames) - targetFrames) / targetFrames
    filteredBufferError = (filteredBufferError * 0.92) + (rawError * 0.08)
    integralBufferError = max(-2, min(2, integralBufferError + (filteredBufferError * 0.1)))

    if stats.primed {
      let correction = max(
        -0.001,
        min(0.001, (filteredBufferError * 0.0006) + (integralBufferError * 0.00005)))
      playbackRate = 1 + correction
    } else {
      playbackRate = 1
    }
    varispeed.rate = Float(playbackRate)

    let trimThreshold = UInt32(max(sampleRate * 0.250, targetFrames * 3))
    if stats.available_frames > trimThreshold {
      AFAudioRingBufferRequestTrim(ringBuffer, UInt32(targetFrames + (sampleRate * 0.010)))
    }

    if controllerTicks.isMultiple(of: 5) {
      publishMetrics(currentMetrics(stats: stats))
    }
  }

  private func updateArrivalJitter(for message: ForwardMessage, arrivalNanoseconds: UInt64) {
    if let lastArrivalNanoseconds, let previousPacketDurationNanoseconds {
      let actual = Double(arrivalNanoseconds &- lastArrivalNanoseconds)
      let deviationMilliseconds = abs(actual - previousPacketDurationNanoseconds) / 1_000_000
      arrivalJitterMilliseconds = arrivalJitterMilliseconds == 0
        ? deviationMilliseconds
        : (arrivalJitterMilliseconds * 0.95) + (deviationMilliseconds * 0.05)
    }
    lastArrivalNanoseconds = arrivalNanoseconds
    previousPacketDurationNanoseconds = Double(message.frames) / Double(message.sampleRate) * 1_000_000_000
  }

  private func currentMetrics(stats suppliedStats: AFAudioRingBufferStats? = nil) -> PlaybackMetrics {
    let stats: AFAudioRingBufferStats
    if let suppliedStats {
      stats = suppliedStats
    } else if let ringBuffer {
      stats = AFAudioRingBufferGetStats(ringBuffer)
    } else {
      return lastMetrics
    }

    return PlaybackMetrics(
      bufferedMilliseconds: Double(stats.available_frames) / sampleRate * 1_000,
      targetMilliseconds: targetLatencySeconds * 1_000,
      arrivalJitterMilliseconds: arrivalJitterMilliseconds,
      playbackRate: playbackRate,
      underrunEvents: stats.underrun_events,
      overflowEvents: stats.overflow_events,
      trimmedFrames: stats.trimmed_frames,
      receivedPackets: receivedPackets,
      receivedFrames: receivedFrames,
      isPrimed: stats.primed,
      isRecovering: controllerTicks - lastUnderrunTick < 50)
  }

  private func publishMetrics(_ metrics: PlaybackMetrics) {
    lastMetrics = metrics
    DispatchQueue.main.async { [weak self] in self?.onMetrics?(metrics) }
  }

  private func resetBufferedAudioLocked() {
    // A sequence reset is rare and is handled by rebuilding the graph so the
    // real-time reader is never racing a producer-side ring-buffer reset.
    tearDownAudioGraphLocked()
  }

  private func resetControllerLocked() {
    filteredBufferError = 0
    integralBufferError = 0
    playbackRate = 1
    controllerTicks = 0
    stableTicks = 0
    lastUnderrunTick = -1_000
    lastControllerUnderruns = 0
    varispeed?.rate = 1
  }

  private func restartAfterOutputChange() {
    guard engine != nil else { return }
    tearDownAudioGraphLocked()
  }

  private func tearDownLocked(resetSession: Bool) {
    controllerTimer?.cancel()
    controllerTimer = nil
    tearDownAudioGraphLocked()
    if resetSession {
      targetLatencySeconds = 0.070
      lastSequence = nil
      lastArrivalNanoseconds = nil
      previousPacketDurationNanoseconds = nil
      arrivalJitterMilliseconds = 0
      receivedPackets = 0
      receivedFrames = 0
      lastMetrics = .idle
    }
  }

  private func tearDownAudioGraphLocked() {
    engine?.stop()
    if let sourceNode, let engine { engine.detach(sourceNode) }
    if let varispeed, let engine { engine.detach(varispeed) }
    sourceNode = nil
    varispeed = nil
    engine = nil
    format = nil
    if let ringBuffer {
      AFAudioRingBufferDestroy(ringBuffer)
      self.ringBuffer = nil
    }
    resetControllerLocked()
  }

  private func reportError(_ message: String) {
    DispatchQueue.main.async { [weak self] in self?.onError?(message) }
  }
}

private enum PlaybackError: LocalizedError {
  case invalidFormat
  case bufferAllocationFailed

  var errorDescription: String? {
    switch self {
    case .invalidFormat:
      return "The received PCM format is not supported."
    case .bufferAllocationFailed:
      return "The adaptive audio buffer could not be allocated."
    }
  }
}
