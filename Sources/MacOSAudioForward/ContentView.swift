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
          audioForwardOutput
          nearbySection
          if model.incomingPeerName != nil { receivingStatus }
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
        Text("Audio Forward").font(.headline)
        Text(model.activityText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
    }
    .padding(16)
  }

  private var audioForwardOutput: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Image(systemName: "hifispeaker.2.fill")
            .font(.title3)
            .foregroundStyle(model.isAudioForwardSelected ? Color.accentColor : .secondary)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 1) {
            Text("Audio Forward").font(.body.weight(.medium))
            Text(model.audioForwardDetail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if model.audioForwardReady {
            Button(model.isAudioForwardSelected ? "Stop" : "Use as Output") {
              if model.isAudioForwardSelected {
                model.stopSending()
              } else {
                model.useAudioForward()
              }
            }
            .controlSize(.small)
          } else {
            Button("Retry") { model.retryAudioForwardOutput() }
              .controlSize(.small)
          }
        }

        Divider()

        LabeledContent("Current output") {
          Text(model.currentOutputName)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .font(.caption)

        Text("Audio Forward also appears in Control Centre and System Settings while this app is running.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 2)
    } label: {
      Label("Output", systemImage: "speaker.wave.2")
        .font(.subheadline.weight(.semibold))
    }
  }

  private var nearbySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Label("Destination", systemImage: "desktopcomputer")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("Thunderbolt Bridge").font(.caption2).foregroundStyle(.secondary)
      }

      if model.peers.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("No other Mac found.")
            .font(.callout)
          Text("The saved destination will reconnect automatically when it appears.")
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
    let selected = model.preferredPeerID == peer.id
    return HStack(spacing: 10) {
      Image(systemName: selected ? "checkmark.circle.fill" : "desktopcomputer")
        .foregroundStyle(sending ? .green : (selected ? Color.accentColor : .secondary))
        .frame(width: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text(peer.name).lineLimit(1)
        Text("Audio Forward \(peer.version) · bridge0")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(selected ? (sending ? "Active" : (connecting ? "Connecting…" : "Selected")) : "Select") {
        model.selectDestination(peer)
      }
      .controlSize(.small)
      .disabled(selected)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
  }

  private var receivingStatus: some View {
    GroupBox {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Receiving from").font(.caption).foregroundStyle(.secondary)
          Text(model.incomingPeerName ?? "Another Mac").font(.body.weight(.medium))
        }
        Spacer()
        Image(systemName: "waveform")
          .symbolEffect(.variableColor.iterative)
          .foregroundStyle(.green)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Label("Incoming Audio", systemImage: "arrow.down.circle")
        .font(.subheadline.weight(.semibold))
    }
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
