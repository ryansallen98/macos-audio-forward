# Privacy

Audio Forward does not collect personal data, use analytics, contact a cloud service, or connect to the internet.

When you explicitly start forwarding, the app captures the Mac's mixed system-audio output and sends it to the selected peer over the direct `bridge0` Thunderbolt network interface. Audio is held only in short-lived memory buffers for transport and playback. It is not written to disk by the app.

The app publishes a local Bonjour service containing a random app-instance identifier, the Mac's local display name, and the app version. Peers are shown only when discovered through `bridge0`.

Preferences stored in macOS UserDefaults include the random instance identifier, Launch at Login state managed by macOS, and local diagnostics such as route state, buffer depth, underrun count, and received-frame count. No captured audio is stored.

System Audio Recording and Local Network permissions are controlled by macOS and can be reviewed in **System Settings → Privacy & Security**.
