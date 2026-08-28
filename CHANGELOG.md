# Changelog

All notable changes to Audio Forward are documented here.

## [0.3.0] - 2026-08-28

### Added

- Add a preallocated, lock-free single-producer/single-consumer audio ring buffer
- Add adaptive receiver latency that grows after an underrun and contracts after sustained stability
- Add continuous clock-drift control bounded to ±0.1% and controlled fade recovery
- Show lossless PCM buffer health and arrival variation in the menu-bar dropdown
- Detect when macOS connects a route but does not deliver captured frames, with permission guidance
- Record low-frequency diagnostic metrics for support and performance verification

### Changed

- Keep the steady-state stream as uncompressed 32-bit floating-point stereo PCM
- Pull audio from the ring buffer in the real-time render callback instead of scheduling a new AVAudio buffer for every network packet
- Deliver incoming audio directly to the playback queue instead of routing every packet through the main UI thread
- Stop hidden SwiftUI animation and suppress telemetry-driven view updates while the menu is closed

### Fixed

- Prevent intermittent jitter caused by the previous 21 ms receiver cushion and main-thread scheduling stalls
- Reduce receiver CPU usage substantially during continuous video playback
- Re-prime cleanly after an underrun and bound accumulated latency after sleep, wake, or an output stall
- Recognize the selected forwarding device by its persistent Core Audio UID after launch or app replacement
- Restore a validated physical output before removing a stale aggregate left selected by an interrupted app update
- Cancel a Bonjour endpoint that remains stuck in preparation and retry against refreshed discovery state
- Restart Bonjour discovery before retrying a timed-out service endpoint
- Detect an unresponsive live stream with application-level heartbeats and reconnect automatically
- Reject half-open connections that never complete their audio handshake
- Enforce one Audio Forward process per Mac and make local installs terminate every older copy

## [0.2.0] - 2026-08-28

### Added

- Publish an app-managed `Audio Forward` device in macOS's native output picker
- Save a preferred destination Mac and reconnect automatically when it becomes available
- Start forwarding when `Audio Forward` is selected in Control Centre or Sound settings
- Stop forwarding when the user selects a different local output
- Add native output and destination controls to the menu-bar dropdown

### Fixed

- Preserve Bonjour peer metadata across incomplete discovery refreshes
- Match a saved destination by Mac name if its discovery identifier changes
- Restore the previous physical output and remove `Audio Forward` when the app quits
- Use the concise `Audio Forward.app` name in Applications and release archives
- Keep the menu-bar item icon-only while retaining its Bartender identity

## [0.1.2] - 2026-08-28

### Fixed

- Restore the app's menu-bar-only workflow
- Open controls exclusively as a dropdown anchored to the `Audio` status item
- Remove the standalone window and all launch/reopen window behavior
- Retain a stable status-item identity so Bartender 6 can index the item

## [0.1.1] - 2026-08-28

### Fixed

- Make the menu-bar control easier to find with a persistent `Audio` label
- Give the status item a stable autosave identity on macOS 26

## [0.1.0] - 2026-08-28

### Added

- Initial two-Mac Thunderbolt Bridge audio forwarding prototype
- Native menu-bar interface with symmetric sender and receiver roles
- Bonjour discovery restricted to the Thunderbolt Bridge interface
- Core Audio system tap with automatic local muting while forwarding
- Playback through the receiving Mac's current default output
