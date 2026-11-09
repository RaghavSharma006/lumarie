# Lumairie Android 0.1.2 QR test build

Universal APK: `Lumairie-Android-0.1.2-QR-Fix.apk`

Package `io.lumarie.mobile`; version `0.1.2`, code `2003`; min SDK 24.
SHA-256: `20fcea8bd6f4dc9c4cdc38d8fbe851217346826a70b38122ae868e7b73f161b7`

The scan button is pinned to the bottom of the real-frame setup screen, even
with Demo Mode off. Version 0.1.2 fixes its Navigator lookup: the previous
button threw before the camera screen could open. A widget test now taps the
button and verifies the scanner route appears. The scanner shows camera errors
and rejects unrelated QR codes. Image transfer over local Wi-Fi accepts authenticated acknowledgements
for verified delivery, while reserving the word "displayed" for a real refresh.

Built with Flutter release mode and Android debug/development signing.
`flutter analyze --no-pub` and 29 tests passed. `apksigner verify` confirmed
APK Signature Scheme v2. The app's Wi-Fi transport passed a loopback receiver
test for delivered and refreshed acknowledgements.

This APK is a hardware test build, not a verified working frame system. The
ESP32-C3 firmware currently in the repository lacks the matching Wi-Fi image
receiver and does not have factory pairing credentials. Camera and real BLE,
Wi-Fi and panel behavior were not tested on physical devices from this host.
