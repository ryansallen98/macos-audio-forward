# Audio Forward 0.3.0

This release rebuilds the receiver as a production-style real-time audio pipeline while preserving the native speaker and menu-bar workflow.

## Highlights

- Install the same app on both Macs.
- Configure and save a destination Mac in the speaker-icon menu-bar dropdown.
- Select **Audio Forward** in Control Centre or Sound settings like any other speaker.
- Reconnect to the saved Mac automatically after login, wake, or a temporary disconnect.
- Switch to another local output to stop forwarding.
- Restore the previous output and remove the app-managed device when the app quits.
- Keep the controls in an anchored menu-bar dropdown compatible with Bartender 6.
- Run without any standalone window or Dock icon.
- Play through the receiving Mac's current default output.
- Carry uncompressed 32-bit floating-point stereo PCM without a lossy codec or audio enhancement stage.
- Use a preallocated pull-based ring buffer so playback never waits for SwiftUI or AppKit.
- Adapt the latency target after real underruns and reduce it again after sustained stability.
- Correct independent Mac audio clocks continuously with a tightly bounded ±0.1% rate adjustment.
- Re-prime with click-resistant fades after a genuine interruption.
- Verify the live Thunderbolt stream continuously and reconnect if its heartbeat stops.
- Prevent two app processes from competing for the same virtual output or connection.
- Display buffer health and arrival variation in the menu-bar dropdown.
- Detect missing System Audio Recording delivery and explain how to restore permission.

## Compatibility

- macOS 26 Tahoe or newer
- Apple Silicon

## Preview limitations

- This is an early preview intended for direct Thunderbolt-connected Macs.
- Both directions are supported, but only one forwarding route should be active at a time.
- The initial public build is ad-hoc signed and not notarized.
