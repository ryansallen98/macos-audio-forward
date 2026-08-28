import Darwin
import Foundation

@MainActor
enum DiagnosticRunner {
  static func run(arguments: [String]) -> Never {
    if arguments.contains("--diagnostic-outputs") {
      let current = try? CoreAudioUtility.defaultOutputDevice()
      for device in CoreAudioUtility.outputDevices() {
        print("\(device == current ? "*" : " ")\t\(CoreAudioUtility.name(of: device))")
      }
      exit(EXIT_SUCCESS)
    }

    if let option = arguments.firstIndex(of: "--diagnostic-select-output"),
      option + 1 < arguments.count
    {
      let name = arguments[option + 1]
      guard let device = CoreAudioUtility.outputDevice(named: name) else {
        fputs("No output named \(name) was found.\n", stderr)
        exit(EXIT_FAILURE)
      }
      do {
        try CoreAudioUtility.setDefaultOutputDevice(device)
        try? CoreAudioUtility.setDefaultOutputDevice(device, systemSounds: true)
        print("Selected \(CoreAudioUtility.name(of: device)).")
        exit(EXIT_SUCCESS)
      } catch {
        fputs("Could not select \(name): \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
      }
    }

    let listOnly = arguments.contains("--diagnostic-list")
    let captureMode = arguments.contains("--diagnostic-capture")
    let requestedPeer: String? = {
      let option = captureMode ? "--diagnostic-capture" : "--diagnostic-tone"
      guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }()

    let service = NetworkService(
      instanceID: "diagnostic-\(UUID().uuidString)",
      localName: "Audio Forward Diagnostics",
      appVersion: "diagnostic")
    var startedTone = false
    var timer: DispatchSourceTimer?
    var sequenceFrames = 0
    var capture: CoreAudioCapture?
    var capturedPackets = 0
    var capturedPeak: Float = 0

    service.onError = { message in
      fputs("Diagnostic error: \(message)\n", stderr)
    }
    service.onPeersChanged = { peers in
      if listOnly {
        for peer in peers {
          print("\(peer.name)\t\(peer.id)\t\(peer.interface.name)")
        }
        return
      }

      guard !startedTone, let requestedPeer else { return }
      guard let peer = peers.first(where: {
        $0.name.localizedCaseInsensitiveContains(requestedPeer)
          || requestedPeer.localizedCaseInsensitiveContains($0.name)
      }) else { return }
      startedTone = true
      print("Connecting to \(peer.name) on \(peer.interface.name)…")
      service.connect(to: peer)
    }
    service.onOutgoingReady = { peer in
      if captureMode {
        let audioCapture = CoreAudioCapture()
        audioCapture.onAudio = { payload, rate, channels, frames in
          var packetPeak: Float = 0
          payload.withUnsafeBytes { raw in
            guard let samples = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            for index in 0..<(payload.count / MemoryLayout<Float>.size) {
              packetPeak = max(packetPeak, abs(samples[index]))
            }
          }
          DispatchQueue.main.async {
            capturedPackets += 1
            capturedPeak = max(capturedPeak, packetPeak)
          }
          service.sendAudio(payload: payload, sampleRate: rate, channels: channels, frames: frames)
        }
        do {
          try audioCapture.start(remoteName: peer.name)
          capture = audioCapture
          print("Connected to \(peer.name); forwarding system audio for five seconds.")
          DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = ["/System/Library/Sounds/Glass.aiff"]
            try? process.run()
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            capture?.stop()
            capture = nil
            service.disconnect()
            service.stop()
            let peakText = String(format: "%.4f", capturedPeak)
            UserDefaults.standard.set(capturedPackets, forKey: "diagnostics.lastCapturedPacketCount")
            UserDefaults.standard.set(Double(capturedPeak), forKey: "diagnostics.lastCapturedPeak")
            UserDefaults.standard.set(Date(), forKey: "diagnostics.lastCapturedAt")
            print("Diagnostic system-audio capture complete: \(capturedPackets) packets, peak \(peakText).")
            exit(EXIT_SUCCESS)
          }
        } catch {
          fputs("Could not start system-audio capture: \(error.localizedDescription)\n", stderr)
          service.disconnect()
          service.stop()
          exit(EXIT_FAILURE)
        }
        return
      }

      print("Connected to \(peer.name); sending a quiet 440 Hz tone for two seconds.")
      let source = DispatchSource.makeTimerSource(queue: .main)
      source.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
      source.setEventHandler {
        let frames: UInt32 = 384
        let payload = tonePayload(startFrame: sequenceFrames, frameCount: Int(frames))
        sequenceFrames += Int(frames)
        service.sendAudio(payload: payload, sampleRate: 48_000, channels: 2, frames: frames)
      }
      source.resume()
      timer = source

      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        timer?.cancel()
        timer = nil
        service.disconnect()
        service.stop()
        print("Diagnostic tone complete.")
        exit(EXIT_SUCCESS)
      }
    }

    do {
      try service.start()
    } catch {
      fputs("Could not start diagnostics: \(error.localizedDescription)\n", stderr)
      exit(EXIT_FAILURE)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + (listOnly ? 4 : 10)) {
      if listOnly {
        service.stop()
        exit(EXIT_SUCCESS)
      }
      capture?.stop()
      service.disconnect()
      service.stop()
      let message = startedTone
        ? "The Thunderbolt connection did not become ready."
        : "No matching Thunderbolt peer was found."
      fputs("\(message)\n", stderr)
      exit(EXIT_FAILURE)
    }

    RunLoop.main.run()
    exit(EXIT_FAILURE)
  }

  private static func tonePayload(startFrame: Int, frameCount: Int) -> Data {
    var samples = [Float](repeating: 0, count: frameCount * 2)
    for frame in 0..<frameCount {
      let time = Double(startFrame + frame) / 48_000.0
      let value = Float(sin(2.0 * .pi * 440.0 * time) * 0.08)
      samples[frame * 2] = value
      samples[frame * 2 + 1] = value
    }
    return samples.withUnsafeBytes { Data($0) }
  }
}
