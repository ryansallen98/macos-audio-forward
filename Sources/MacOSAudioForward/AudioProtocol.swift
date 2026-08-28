import Foundation

enum ForwardMessageKind: UInt8 {
  case hello = 1
  case audio = 2
  case goodbye = 3
  case ping = 4
}

struct ForwardHandshake: Codable, Equatable {
  let id: String
  let name: String
  let version: String
}

struct ForwardMessage: Equatable {
  static let magic: UInt32 = 0x5241_4631 // RAF1
  static let version: UInt8 = 1
  static let headerSize = 24
  static let maximumPayloadSize = 1_048_576

  let kind: ForwardMessageKind
  let channels: UInt16
  let sampleRate: UInt32
  let frames: UInt32
  let sequence: UInt32
  let payload: Data

  func encoded() -> Data {
    var result = Data(capacity: Self.headerSize + payload.count)
    result.appendBigEndian(Self.magic)
    result.append(Self.version)
    result.append(kind.rawValue)
    result.appendBigEndian(channels)
    result.appendBigEndian(sampleRate)
    result.appendBigEndian(frames)
    result.appendBigEndian(sequence)
    result.appendBigEndian(UInt32(payload.count))
    result.append(payload)
    return result
  }

  static func hello(_ handshake: ForwardHandshake) throws -> ForwardMessage {
    ForwardMessage(
      kind: .hello,
      channels: 0,
      sampleRate: 0,
      frames: 0,
      sequence: 0,
      payload: try JSONEncoder().encode(handshake)
    )
  }
}

enum ForwardProtocolError: LocalizedError {
  case invalidMagic
  case unsupportedVersion(UInt8)
  case unknownMessageKind(UInt8)
  case oversizedPayload(Int)

  var errorDescription: String? {
    switch self {
    case .invalidMagic:
      return "The peer sent an invalid Audio Forward stream."
    case .unsupportedVersion(let version):
      return "The peer uses unsupported protocol version \(version)."
    case .unknownMessageKind(let kind):
      return "The peer sent unknown message type \(kind)."
    case .oversizedPayload(let size):
      return "The peer sent an oversized audio packet (\(size) bytes)."
    }
  }
}

final class ForwardStreamDecoder {
  private var buffered = Data()

  func append(_ data: Data) throws -> [ForwardMessage] {
    buffered.append(data)
    var messages: [ForwardMessage] = []

    while buffered.count >= ForwardMessage.headerSize {
      guard buffered.readUInt32BigEndian(at: 0) == ForwardMessage.magic else {
        throw ForwardProtocolError.invalidMagic
      }

      let version = buffered[4]
      guard version == ForwardMessage.version else {
        throw ForwardProtocolError.unsupportedVersion(version)
      }

      let rawKind = buffered[5]
      guard let kind = ForwardMessageKind(rawValue: rawKind) else {
        throw ForwardProtocolError.unknownMessageKind(rawKind)
      }

      let channels = buffered.readUInt16BigEndian(at: 6)
      let sampleRate = buffered.readUInt32BigEndian(at: 8)
      let frames = buffered.readUInt32BigEndian(at: 12)
      let sequence = buffered.readUInt32BigEndian(at: 16)
      let payloadSize = Int(buffered.readUInt32BigEndian(at: 20))
      guard payloadSize <= ForwardMessage.maximumPayloadSize else {
        throw ForwardProtocolError.oversizedPayload(payloadSize)
      }

      let messageSize = ForwardMessage.headerSize + payloadSize
      guard buffered.count >= messageSize else { break }

      let payload = buffered.subdata(in: ForwardMessage.headerSize..<messageSize)
      messages.append(
        ForwardMessage(
          kind: kind,
          channels: channels,
          sampleRate: sampleRate,
          frames: frames,
          sequence: sequence,
          payload: payload
        ))
      buffered.removeSubrange(0..<messageSize)
    }

    return messages
  }
}

private extension Data {
  mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
    var value = value.bigEndian
    Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
  }

  func readUInt16BigEndian(at offset: Int) -> UInt16 {
    (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
  }

  func readUInt32BigEndian(at offset: Int) -> UInt32 {
    (UInt32(self[offset]) << 24)
      | (UInt32(self[offset + 1]) << 16)
      | (UInt32(self[offset + 2]) << 8)
      | UInt32(self[offset + 3])
  }
}
