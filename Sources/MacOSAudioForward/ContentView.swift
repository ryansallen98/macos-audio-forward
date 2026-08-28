import AppKit
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AudioForwardModel
  let contentHeight: CGFloat

  init(model: AudioForwardModel, contentHeight: CGFloat = 570) {
    self.model = model
    self.contentHeight = contentHeight
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          activityCard
          nearbySection
          outputCard
          if let error = model.lastError { errorCard(error) }
        }
        .padding(16)
      }
      Divider()
      footer
    }
    .frame(width: 410, height: contentHeight)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: model.isActive ? "cable.connector.video" : "speaker.wave.2")
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(model.isActive ? .green : .secondary)
        .frame(width: 34)
      VStack(alignment: .leading, spacing: 2) {
        Text("macOS Audio Forward").font(.headline)
        Text(model.activityText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
    }
    .padding(16)
  }

  private var activityCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Thunderbolt Bridge", systemImage: "bolt.horizontal.circle.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      if let sending = model.sendingPeerName {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Sending to").font(.caption).foregroundStyle(.secondary)
            Text(sending).font(.body.weight(.medium))
          }
          Spacer()
          Button("Stop") { model.stopSending() }
            .controlSize(.small)
        }
      }

      if let incoming = model.incomingPeerName {
        VStack(alignment: .leading, spacing: 2) {
          Text("Receiving from").font(.caption).foregroundStyle(.secondary)
          Text(incoming).font(.body.weight(.medium))
        }
      }

      if model.sendingPeerName == nil && model.incomingPeerName == nil {
        Text("This Mac is available to receive. Choose another Mac below to send this Mac's system audio.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private var nearbySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Nearby Macs").font(.subheadline.weight(.semibold))
        Spacer()
        Text("Thunderbolt only").font(.caption2).foregroundStyle(.secondary)
      }

      if model.peers.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("No other Audio Forward app found.")
            .font(.callout)
          Text("Install and open the app on the other Mac, then confirm that Thunderbolt Bridge is connected in Network settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(model.peers.enumerated()), id: \.element.id) { index, peer in
            peerRow(peer)
            if index < model.peers.count - 1 { Divider().padding(.leading, 38) }
          }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.separator.opacity(0.5)))
      }
    }
  }

  private func peerRow(_ peer: DiscoveredPeer) -> some View {
    let sending = model.sendingPeerID == peer.id
    let connecting = model.connectingPeerID == peer.id
    return HStack(spacing: 10) {
      Image(systemName: "desktopcomputer")
        .foregroundStyle(sending ? .green : .secondary)
        .frame(width: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text(peer.name).lineLimit(1)
        Text("Audio Forward \(peer.version) · bridge0")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(sending ? "Stop" : (connecting ? "Connecting…" : "Send Audio")) {
        model.toggleSending(to: peer)
      }
      .controlSize(.small)
      .disabled(connecting)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
  }

  private var outputCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Current output on this Mac", systemImage: "hifispeaker.2")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(model.currentOutputName).font(.callout.weight(.medium))
      Text("Received audio follows this Mac's selected output automatically.")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
  }

  private func errorCard(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text(message).font(.caption).textSelection(.enabled)
        Spacer(minLength: 4)
        Button { model.dismissError() } label: { Image(systemName: "xmark") }
          .buttonStyle(.borderless)
          .accessibilityLabel("Dismiss error")
      }
      if message.localizedCaseInsensitiveContains("capture")
        || message.localizedCaseInsensitiveContains("permission")
      {
        Button("Open Privacy & Security") { model.openPrivacySettings() }
          .buttonStyle(.link)
          .font(.caption)
      }
    }
    .padding(10)
    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
  }

  private var footer: some View {
    VStack(spacing: 8) {
      HStack {
        Toggle(
          "Launch at Login",
          isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
          ))
          .toggleStyle(.checkbox)
        Spacer()
        Button("Sound Settings…") { model.openSoundSettings() }
          .buttonStyle(.borderless)
      }
      if model.loginRequiresApproval {
        HStack {
          Text("Launch at Login needs approval in System Settings.")
            .font(.caption2).foregroundStyle(.secondary)
          Spacer()
          Button("Open") { model.openLoginItemsSettings() }
            .buttonStyle(.link).font(.caption2)
        }
      }
      HStack {
        Text("Version \(appVersion) · Audio stays on your Thunderbolt link.")
          .font(.caption2).foregroundStyle(.tertiary)
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
          .buttonStyle(.borderless)
      }
    }
    .padding(12)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }
}
