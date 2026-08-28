# Security Policy

## Supported versions

Security fixes are provided for the latest published version.

## Reporting a vulnerability

Please report a vulnerability privately to `ryan@rallen.dev`. Do not include passwords, tokens, private keys, recordings, or other sensitive information. A minimal description and safe reproduction steps are enough for an initial report.

## Security design

macOS Audio Forward uses public macOS frameworks and does not run with elevated privileges. It discovers peers, opens outgoing connections, and accepts incoming audio only when the connection uses the `bridge0` Thunderbolt interface. Audio capture begins only after the user selects a peer and macOS has granted System Audio Recording access.

The version 0.1 protocol is unencrypted and does not authenticate the peer beyond its presence on the direct Thunderbolt Bridge. Do not bridge or route that interface onto an untrusted network. A future version may add mutually authenticated encryption if the app expands beyond direct-cable use.

The app does not write captured audio to disk. Release artifacts include a SHA-256 checksum. Public binaries should be Developer ID signed and notarized when signing infrastructure is available.
