# Lumairie

Offline Flutter companion and ESP-IDF candidate firmware for a Spectra 6 E-Ink photo frame. The starter bundle's eight-screen light/dark references are in `design/references`.

- Mobile app: [apps/mobile/README.md](apps/mobile/README.md)
- Current implementation and verification: [docs/STATUS.md](docs/STATUS.md)
- Hardware and security prerequisites: [docs/HARDWARE_AND_SECURITY.md](docs/HARDWARE_AND_SECURITY.md)
- Binary protocol: [shared/protocol/README.md](shared/protocol/README.md)
- Android APK, Windows simulator, checksums and test notes: [deliverables/BUILD_REPORT.md](deliverables/BUILD_REPORT.md) and [deliverables/README_TESTING.md](deliverables/README_TESTING.md)

The app's Demo Mode works without a device and remains clearly separated from real pairing. Physical display output remains disabled until the exact supplier panel and driver documentation is available.
The Windows simulator starts with `START_WINDOWS.bat` and serves the Flutter Web build only at `http://localhost:8787`. Real-device Wi-Fi transfer and buttonless standby are still unimplemented; see the status report before treating the firmware as hardware-ready.
