# Lumairie Android 0.1.1 QR test build

Universal APK: `Lumairie-Android-0.1.1-QR-Fix.apk`

Package `io.lumarie.mobile`; version `0.1.1`, code `2002`; min SDK 24.
SHA-256: `f45a9a26062ab8b4333cc0a902ad0ddaf256834928820f0b0974dd1803be954a`

The scan button is pinned to the bottom of the real-frame setup screen, even
with Demo Mode off. The scanner shows camera errors and rejects unrelated QR
codes. Image transfer over local Wi-Fi accepts authenticated acknowledgements
for verified delivery, while reserving the word "displayed" for a real refresh.

Built with Flutter release mode and Android debug/development signing.
`flutter analyze --no-pub` and 29 tests passed. `apksigner verify` confirmed
APK Signature Scheme v2. The app's Wi-Fi transport passed a loopback receiver
test for delivered and refreshed acknowledgements.

This APK is a hardware test build, not a verified working frame system. The
ESP32-C3 firmware currently in the repository lacks the matching Wi-Fi image
receiver and does not have factory pairing credentials. Camera and real BLE,
Wi-Fi and panel behavior were not tested on physical devices from this host.
