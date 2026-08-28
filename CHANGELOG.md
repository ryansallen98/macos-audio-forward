# Changelog

All notable changes to macOS Audio Forward are documented here.

## [0.1.1] - 2026-08-28

### Fixed

- Show the control panel whenever the app launches or is reopened from Finder
- Make the menu-bar control easier to find with a persistent `Audio` label
- Give the status item a stable autosave identity on macOS 26
- Open a standalone control panel when Bartender 6 relays a menu-bar click
- Keep the Bartender-compatible panel open until it is explicitly closed

## [0.1.0] - 2026-08-28

### Added

- Initial two-Mac Thunderbolt Bridge audio forwarding prototype
- Native menu-bar interface with symmetric sender and receiver roles
- Bonjour discovery restricted to the Thunderbolt Bridge interface
- Core Audio system tap with automatic local muting while forwarding
- Playback through the receiving Mac's current default output
