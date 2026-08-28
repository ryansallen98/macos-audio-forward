<p align="center">
  <img src="Resources/AppIcon.png" alt="Audio Forward app icon" width="160">
</p>

# Audio Forward

Audio Forward is a native menu-bar app that sends live system audio between two Macs over a direct Thunderbolt Bridge. Install the same app on both Macs, choose a destination in the dropdown, then select **Audio Forward** like any other speaker in Control Centre or Sound settings.

It is designed for a MacBook and desktop Mac that already share a Thunderbolt network link. It does not use AirPlay, so Universal Control can remain available for linked keyboard and mouse use.

## Features

- Two-way operation: either Mac can send and either Mac can receive
- Automatic peer discovery limited to the `bridge0` Thunderbolt interface
- An app-managed **Audio Forward** device in macOS's native output picker
- A saved destination that reconnects automatically after login, wake, or a temporary disconnect
- Received sound follows the destination Mac's current output device
- Low-latency stereo PCM transport with buffering and clock-drift correction
- Automatic restoration of the sender's previous output when forwarding stops
- Optional Launch at Login using Apple's `SMAppService`
- Native Swift/AppKit/SwiftUI app with no third-party dependencies
- No accounts, cloud service, analytics, or internet connection

## Requirements

- Two Apple Silicon Macs running macOS 26 Tahoe or later
- A direct Thunderbolt cable between the Macs
- Thunderbolt Bridge enabled in **System Settings → Network** on both Macs

Version 0.2.0 is an Apple Silicon preview build. Intel Macs and older macOS releases are not currently supported.

## Install

Install the app on both Macs:

1. Download the latest `Audio-Forward` ZIP from Releases.
2. Unzip it and move **Audio Forward.app** into `/Applications` on each Mac.
3. Open the app on both Macs. A speaker icon appears in each menu bar; click it to open the dropdown.
4. Allow **System Audio Recording** when macOS asks.
5. In the dropdown, select the destination Mac and optionally enable **Launch at Login**.
6. Select **Audio Forward** in Control Centre, **System Settings → Sound**, or with **Use as Output** in the dropdown.

### Bartender 6

Audio Forward gives its status item a stable identity and accessible name so Bartender can index it consistently. Place **Audio Forward** in Bartender's **Always Shown**, **Hidden**, or grouped section. Clicking its speaker icon opens the same anchored menu-bar dropdown; the app never opens a standalone window or adds a Dock icon.

**Audio Forward** remains in the native output list while the app is running. Selecting it starts the saved route. Selecting headphones, built-in speakers, or another output stops forwarding. If the destination is unavailable while **Audio Forward** remains selected, the app waits and reconnects automatically when that Mac returns. Quitting the app restores the previous physical output and removes **Audio Forward**. The receiving Mac plays the stream through whichever physical output it currently uses.

The preview archive is ad-hoc signed because the project does not yet have an Apple Developer ID certificate. macOS may require you to Control-click the app, choose **Open**, then confirm once.

## How it works

The app uses macOS's public Core Audio process-tap API to create an app-managed aggregate output named **Audio Forward**. The device is prepared while the app runs, but its capture I/O starts only when the user selects it. The tap uses `mutedWhenTapped` so active playback is forwarded instead of duplicated locally. No permanent virtual-audio driver, system extension, privileged helper, or reboot is required.

The two app instances advertise and discover a Bonjour service. Discovery, outgoing connections, and accepted incoming connections are all checked against the `bridge0` interface. Audio is transported as 32-bit floating-point stereo PCM over TCP with a small receiver buffer and bounded clock-rate correction.

Because it uses Thunderbolt networking instead of AirPlay, it does not take over the Continuity/AirPlay session used by Universal Control.

## Build

Only the Xcode Command Line Tools and macOS 26 SDK are required:

```sh
./scripts/check.sh
./scripts/build.sh
```

The app bundle is written to `build/Audio Forward.app`. Install the local build with:

```sh
./scripts/install.sh
```

Create the release archive and SHA-256 checksum with:

```sh
./scripts/package-release.sh
```

## Known limitations

- The current release carries stereo system audio only; microphone forwarding is not included.
- Audio is uncompressed and intended for a direct Thunderbolt Bridge, not ordinary Wi-Fi or routed networks.
- Each sending Mac requires macOS System Audio Recording permission.
- An abrupt system crash or forced power-off can leave a temporary aggregate device behind. The app removes its stale devices at the next launch.
- This preview is ad-hoc signed and not notarized.

## Uninstall

Turn off **Launch at Login**, quit the app on both Macs, and move it from `/Applications` to the Trash. Preferences can be removed with:

```sh
defaults delete dev.rallen.macos-audio-forward
```

## Distribution

Local builds are ad-hoc signed. For a trusted public distribution, install a valid **Developer ID Application** certificate and build with:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-release.sh
```

Submit the archive with Apple's `notarytool`, staple the accepted ticket to the app, and recreate the archive before publishing. Signing credentials and notarization profiles must never be committed.

## Privacy and security

Captured audio is sent only while the user has an active forwarding session. The app accepts and initiates streams only through the Thunderbolt Bridge interface. It does not record audio to disk or send analytics. The direct-link stream is not encrypted, so do not route `bridge0` through an untrusted network. See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Project provenance

This is an independent implementation built from scratch with public Apple APIs. The app icon is original artwork generated specifically for this project.

## Contributing

Bug reports and focused pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing.

## License

MIT © 2026 Ryan Allen. See [LICENSE](LICENSE).
