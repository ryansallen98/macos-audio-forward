import CoreAudio
import Foundation

final class CoreAudioCapture {
  typealias AudioHandler = (_ payload: Data, _ sampleRate: UInt32, _ channels: UInt16, _ frames: UInt32) -> Void

  var onAudio: AudioHandler?

  private let captureQueue = DispatchQueue(
    label: "dev.rallen.audio-forward.capture",
    qos: .userInteractive,
    attributes: [],
    autoreleaseFrequency: .workItem)

  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggregateID = AudioDeviceID(kAudioObjectUnknown)
  private var ioProcID: AudioDeviceIOProcID?
  private var originalOutput = AudioDeviceID(kAudioObjectUnknown)
  private var originalSystemOutput = AudioDeviceID(kAudioObjectUnknown)
  private var sampleRate: UInt32 = 48_000
  private var running = false

  var isPrepared: Bool {
    aggregateID != kAudioObjectUnknown && tapID != kAudioObjectUnknown
  }

  var outputDeviceID: AudioDeviceID? {
    aggregateID == kAudioObjectUnknown ? nil : aggregateID
  }

  func prepare(outputName: String = "Audio Forward") throws {
    guard !isPrepared else { return }
    CoreAudioUtility.cleanupStaleAggregates()

    originalOutput = try CoreAudioUtility.defaultOutputDevice()
    originalSystemOutput = (try? CoreAudioUtility.defaultOutputDevice(systemSounds: true)) ?? originalOutput
    let baseDeviceUID = try CoreAudioUtility.uid(of: originalOutput)

    let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
    tapDescription.name = "Audio Forward system tap"
    tapDescription.bundleIDs = [Bundle.main.bundleIdentifier ?? "dev.rallen.macos-audio-forward"]
    tapDescription.muteBehavior = .mutedWhenTapped
    tapDescription.isPrivate = false
    tapDescription.isProcessRestoreEnabled = true

    var createdTap = AudioObjectID(kAudioObjectUnknown)
    try CoreAudioUtility.check(
      AudioHardwareCreateProcessTap(tapDescription, &createdTap),
      operation: "Create the system audio tap")
    tapID = createdTap

    do {
      let tapUID = try readTapUID(createdTap)
      sampleRate = try readTapSampleRate(createdTap)
      let aggregateDescription: [String: Any] = [
        kAudioAggregateDeviceUIDKey: CoreAudioUtility.forwardOutputUID,
        kAudioAggregateDeviceNameKey: outputName,
        kAudioAggregateDeviceSubDeviceListKey: [
          [kAudioSubDeviceUIDKey: baseDeviceUID]
        ],
        kAudioAggregateDeviceMainSubDeviceKey: baseDeviceUID,
        kAudioAggregateDeviceTapListKey: [
          [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: true,
            kAudioSubTapDriftCompensationQualityKey: kAudioAggregateDriftCompensationMaxQuality,
          ]
        ],
        kAudioAggregateDeviceIsPrivateKey: false,
        kAudioAggregateDeviceIsStackedKey: false,
      ]

      var createdAggregate = AudioDeviceID(kAudioObjectUnknown)
      try CoreAudioUtility.check(
        AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &createdAggregate),
        operation: "Create the Audio Forward output")
      aggregateID = createdAggregate
      try setPreferredBufferSize(on: createdAggregate)
    } catch {
      teardown(restoreOutput: false)
      throw error
    }
  }

  func start(remoteName _: String) throws {
    guard !running else { return }
    try prepare()
    do {
      try startForwarding()
      try selectForwardOutput()
    } catch {
      stop()
      throw error
    }
  }

  func startForwarding() throws {
    guard !running else { return }
    guard aggregateID != kAudioObjectUnknown else {
      throw CoreAudioError(
        operation: "Start Audio Forward",
        status: kAudioHardwareBadDeviceError)
    }
    do {
      try createAndStartIO(on: aggregateID)
      running = true
    } catch {
      stopForwarding()
      throw error
    }
  }

  func stopForwarding() {
    if aggregateID != kAudioObjectUnknown, let ioProcID {
      _ = AudioDeviceStop(aggregateID, ioProcID)
      _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
    }
    ioProcID = nil
    running = false
  }

  func selectForwardOutput() throws {
    guard aggregateID != kAudioObjectUnknown else {
      throw CoreAudioError(
        operation: "Select Audio Forward",
        status: kAudioHardwareBadDeviceError)
    }
    try CoreAudioUtility.setDefaultOutputDevice(aggregateID)
    try? CoreAudioUtility.setDefaultOutputDevice(aggregateID, systemSounds: true)
  }

  func isForwardOutput(_ device: AudioDeviceID) -> Bool {
    aggregateID != kAudioObjectUnknown && device == aggregateID
  }

  func rememberFallbackOutput(_ device: AudioDeviceID) {
    guard device != kAudioObjectUnknown, !isForwardOutput(device) else { return }
    originalOutput = device
    originalSystemOutput = device
  }

  func restoreFallbackOutput() {
    if originalOutput != kAudioObjectUnknown {
      try? CoreAudioUtility.setDefaultOutputDevice(originalOutput)
    }
    if originalSystemOutput != kAudioObjectUnknown {
      try? CoreAudioUtility.setDefaultOutputDevice(originalSystemOutput, systemSounds: true)
    }
  }

  func stop() {
    teardown(restoreOutput: true)
  }

  func teardown(restoreOutput: Bool = true) {
    if restoreOutput,
      let current = try? CoreAudioUtility.defaultOutputDevice(),
      isForwardOutput(current)
    {
      restoreFallbackOutput()
    }

    stopForwarding()

    if aggregateID != kAudioObjectUnknown {
      _ = AudioHardwareDestroyAggregateDevice(aggregateID)
    }
    aggregateID = kAudioObjectUnknown

    if tapID != kAudioObjectUnknown {
      _ = AudioHardwareDestroyProcessTap(tapID)
    }
    tapID = kAudioObjectUnknown
    originalOutput = kAudioObjectUnknown
    originalSystemOutput = kAudioObjectUnknown
  }

  private func readTapUID(_ tap: AudioObjectID) throws -> String {
    var address = CoreAudioUtility.propertyAddress(kAudioTapPropertyUID)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var uid: CFString?
    let status = withUnsafeMutablePointer(to: &uid) {
      AudioObjectGetPropertyData(tap, &address, 0, nil, &size, $0)
    }
    try CoreAudioUtility.check(status, operation: "Read the system audio tap identifier")
    guard let uid else {
      throw CoreAudioError(operation: "Read the system audio tap identifier", status: kAudioHardwareUnspecifiedError)
    }
    return uid as String
  }

  private func readTapSampleRate(_ tap: AudioObjectID) throws -> UInt32 {
    var address = CoreAudioUtility.propertyAddress(kAudioTapPropertyFormat)
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    try CoreAudioUtility.check(
      AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format),
      operation: "Read the system audio tap format")
    return UInt32(format.mSampleRate.rounded())
  }

  private func setPreferredBufferSize(on device: AudioDeviceID) throws {
    var address = CoreAudioUtility.propertyAddress(kAudioDevicePropertyBufferFrameSize)
    var frames: UInt32 = 256
    let status = AudioObjectSetPropertyData(
      device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
    if status != noErr && status != kAudioHardwareUnsupportedOperationError {
      try CoreAudioUtility.check(status, operation: "Set the audio forwarding buffer size")
    }
  }

  private func createAndStartIO(on device: AudioDeviceID) throws {
    var createdIOProc: AudioDeviceIOProcID?
    let status = AudioDeviceCreateIOProcIDWithBlock(
      &createdIOProc,
      device,
      captureQueue
    ) { [weak self] _, inputData, _, _, _ in
      self?.consume(inputData)
    }
    try CoreAudioUtility.check(status, operation: "Connect to the system audio tap")
    guard let createdIOProc else {
      throw CoreAudioError(operation: "Connect to the system audio tap", status: kAudioHardwareUnspecifiedError)
    }
    ioProcID = createdIOProc
    try CoreAudioUtility.check(
      AudioDeviceStart(device, createdIOProc),
      operation: "Start system audio forwarding")
  }

  private func consume(_ inputData: UnsafePointer<AudioBufferList>) {
    let mutableList = UnsafeMutablePointer<AudioBufferList>(mutating: inputData)
    let buffers = UnsafeMutableAudioBufferListPointer(mutableList)
    guard let packet = Self.interleavedStereo(from: buffers) else { return }
    onAudio?(packet.data, sampleRate, packet.channels, packet.frames)
  }

  private static func interleavedStereo(
    from buffers: UnsafeMutableAudioBufferListPointer
  ) -> (data: Data, channels: UInt16, frames: UInt32)? {
    let populated = buffers.filter { $0.mData != nil && $0.mDataByteSize > 0 }
    guard !populated.isEmpty else { return nil }

    if let interleaved = populated.first(where: { $0.mNumberChannels >= 2 }),
      let source = interleaved.mData
    {
      let channels = Int(interleaved.mNumberChannels)
      let frameBytes = MemoryLayout<Float>.size * channels
      let frames = Int(interleaved.mDataByteSize) / frameBytes
      guard frames > 0 else { return nil }

      if channels == 2 {
        return (Data(bytes: source, count: frames * frameBytes), 2, UInt32(frames))
      }

      let sourceFloats = source.assumingMemoryBound(to: Float.self)
      var output = Data(count: frames * 2 * MemoryLayout<Float>.size)
      output.withUnsafeMutableBytes { raw in
        guard let destination = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
        for frame in 0..<frames {
          destination[frame * 2] = sourceFloats[frame * channels]
          destination[frame * 2 + 1] = sourceFloats[frame * channels + 1]
        }
      }
      return (output, 2, UInt32(frames))
    }

    guard let leftData = populated[0].mData else { return nil }
    let leftFrames = Int(populated[0].mDataByteSize) / MemoryLayout<Float>.size
    guard leftFrames > 0 else { return nil }
    let rightBuffer = populated.count > 1 ? populated[1] : populated[0]
    guard let rightData = rightBuffer.mData else { return nil }
    let rightFrames = Int(rightBuffer.mDataByteSize) / MemoryLayout<Float>.size
    let frames = min(leftFrames, rightFrames)
    let left = leftData.assumingMemoryBound(to: Float.self)
    let right = rightData.assumingMemoryBound(to: Float.self)
    var output = Data(count: frames * 2 * MemoryLayout<Float>.size)
    output.withUnsafeMutableBytes { raw in
      guard let destination = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
      for frame in 0..<frames {
        destination[frame * 2] = left[frame]
        destination[frame * 2 + 1] = right[frame]
      }
    }
    return (output, 2, UInt32(frames))
  }
}
