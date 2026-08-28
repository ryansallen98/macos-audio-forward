# Changelog

All notable changes to macOS Audio Forward are documented here.

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
