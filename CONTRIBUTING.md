# Contributing

Focused bug reports and pull requests are welcome.

## Development

You need Apple Silicon, macOS 26 or later, and the macOS 26 SDK. Run the full local check before submitting a change:

```sh
./scripts/check.sh
```

Keep the application dependency-free and use public macOS APIs. Never commit signing identities, notarization credentials, captured audio, machine identifiers, or other private data.

Changes to the wire format must preserve explicit version handling and include protocol tests. Changes to audio capture, playback, or networking should be tested in both directions across a direct Thunderbolt Bridge.

## Pull requests

Describe the user-visible behavior, the Macs and macOS versions tested, and any changes to permissions, privacy, or network exposure. Small, reviewable changes are preferred.
