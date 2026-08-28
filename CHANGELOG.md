# Changelog

All notable changes to Audio Forward are documented here.

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
