import Foundation

@main
enum AudioProtocolTests {
  static func main() throws {
    try messageRoundTripAcrossFragmentedReads()
    try multipleMessagesInOneRead()
    try rejectsInvalidMagic()
    print("Audio protocol tests passed.")
  }

  private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw TestFailure(message: message) }
  }

  private static func messageRoundTripAcrossFragmentedReads() throws {
    let source = ForwardMessage(
      kind: .audio,
      channels: 2,
      sampleRate: 48_000,
      frames: 256,
      sequence: 42,
      payload: Data((0..<97).map(UInt8.init))
    )
    let encoded = source.encoded()
    let decoder = ForwardStreamDecoder()

    try require(try decoder.append(encoded.prefix(7)).isEmpty, "Accepted an incomplete header")
    try require(try decoder.append(encoded.dropFirst(7).prefix(19)).isEmpty, "Accepted an incomplete payload")
    try require(try decoder.append(encoded.dropFirst(26)) == [source], "Fragmented round trip failed")
  }

  private static func multipleMessagesInOneRead() throws {
    let handshake = ForwardHandshake(id: "abc", name: "Mac Studio", version: "0.1.0")
    let hello = try ForwardMessage.hello(handshake)
    let ping = ForwardMessage(
      kind: .ping,
      channels: 0,
      sampleRate: 0,
      frames: 0,
      sequence: 1,
      payload: Data()
    )

    let messages = try ForwardStreamDecoder().append(hello.encoded() + ping.encoded())
    try require(messages == [hello, ping], "Multiple-message decoding failed")
    let decoded = try JSONDecoder().decode(ForwardHandshake.self, from: messages[0].payload)
    try require(decoded == handshake, "Handshake round trip failed")
  }

  private static func rejectsInvalidMagic() throws {
    var encoded = ForwardMessage(
      kind: .ping,
      channels: 0,
      sampleRate: 0,
      frames: 0,
      sequence: 0,
      payload: Data()
    ).encoded()
    encoded[0] = 0

    do {
      _ = try ForwardStreamDecoder().append(encoded)
      throw TestFailure(message: "Invalid magic was accepted")
    } catch is ForwardProtocolError {
      // Expected.
    }
  }
}

private struct TestFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
