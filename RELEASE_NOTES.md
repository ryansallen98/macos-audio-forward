# Audio Forward 0.2.0

This release makes Audio Forward behave like a native macOS speaker while preserving its menu-bar-only workflow.

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

## Compatibility

- macOS 26 Tahoe or newer
- Apple Silicon

## Preview limitations

- This is an early preview intended for direct Thunderbolt-connected Macs.
- Both directions are supported, but only one forwarding route should be active at a time.
- The initial public build is ad-hoc signed and not notarized.
