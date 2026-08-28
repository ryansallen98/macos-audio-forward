import CoreAudio
import Foundation

enum CoreAudioUtility {
  static let aggregateUIDPrefix = "dev.rallen.macos-audio-forward.aggregate."

  static func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
  }

  static func defaultOutputDevice(systemSounds: Bool = false) throws -> AudioDeviceID {
    let selector = systemSounds
      ? kAudioHardwarePropertyDefaultSystemOutputDevice
      : kAudioHardwarePropertyDefaultOutputDevice
    var address = propertyAddress(selector)
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    try check(
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device),
      operation: "Read the default output device")
    return device
  }

  static func setDefaultOutputDevice(_ device: AudioDeviceID, systemSounds: Bool = false) throws {
    let selector = systemSounds
      ? kAudioHardwarePropertyDefaultSystemOutputDevice
      : kAudioHardwarePropertyDefaultOutputDevice
    var address = propertyAddress(selector)
    var device = device
    try check(
      AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        UInt32(MemoryLayout<AudioDeviceID>.size),
        &device),
      operation: "Set the default output device")
  }

  static func name(of object: AudioObjectID) -> String {
    stringProperty(kAudioObjectPropertyName, object: object) ?? "Unknown output"
  }

  static func uid(of device: AudioDeviceID) throws -> String {
    guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, object: device), !uid.isEmpty else {
      throw CoreAudioError(operation: "Read the output device identifier", status: kAudioHardwareUnspecifiedError)
    }
    return uid
  }

  static func currentOutputName() -> String {
    guard let id = try? defaultOutputDevice() else { return "No output selected" }
    return name(of: id)
  }

  static func cleanupStaleAggregates() {
    var address = propertyAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr
    else { return }

    for device in devices {
      guard
        let uid = stringProperty(kAudioDevicePropertyDeviceUID, object: device),
        uid.hasPrefix(aggregateUIDPrefix)
      else { continue }
      _ = AudioHardwareDestroyAggregateDevice(device)
    }
  }

  static func stringProperty(
    _ selector: AudioObjectPropertySelector,
    object: AudioObjectID
  ) -> String? {
    var address = propertyAddress(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    guard status == noErr, let value else { return nil }
    return value as String
  }

  static func check(_ status: OSStatus, operation: String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
  }
}

struct CoreAudioError: LocalizedError {
  let operation: String
  let status: OSStatus

  var errorDescription: String? {
    "\(operation) failed (\(Self.describe(status)))."
  }

  private static func describe(_ status: OSStatus) -> String {
    let raw = UInt32(bitPattern: status)
    let bytes: [UInt8] = [
      UInt8((raw >> 24) & 0xff),
      UInt8((raw >> 16) & 0xff),
      UInt8((raw >> 8) & 0xff),
      UInt8(raw & 0xff),
    ]
    if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }), let text = String(bytes: bytes, encoding: .ascii) {
      return "'\(text)' / \(status)"
    }
    return String(status)
  }
}
