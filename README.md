# Lumairie

Offline Flutter companion and ESP-IDF candidate firmware for a Spectra 6 E-Ink photo frame. The starter bundle's eight-screen light/dark references are in `design/references`.

- Mobile app: [apps/mobile/README.md](apps/mobile/README.md)
- Current implementation and verification: [docs/STATUS.md](docs/STATUS.md)
- Hardware and security prerequisites: [docs/HARDWARE_AND_SECURITY.md](docs/HARDWARE_AND_SECURITY.md)
- Binary protocol: [shared/protocol/README.md](shared/protocol/README.md)
- Android APK, Windows simulator, checksums and test notes: [deliverables/BUILD_REPORT.md](deliverables/BUILD_REPORT.md) and [deliverables/README_TESTING.md](deliverables/README_TESTING.md)

The app's Demo Mode works without a device and remains clearly separated from real pairing. The ED2208 hardware display adapter is implemented, but real physical operation has not yet been verified.
The Windows simulator starts with `START_WINDOWS.bat` and serves the Flutter Web build only at `http://localhost:8787`. The EE04 native app photo-transfer path is now implemented and software-tested in the feature branch, but hardware testing and production security remain outstanding.

## EE04 Android + firmware hardware preview (2026-11-04)

The active ESP32-S3 Plus + EE04 Spectra 6 implementation is on the
[`feature/ee04-photo-transfer`](https://github.com/RaghavSharma006/lumarie/tree/feature/ee04-photo-transfer)
branch and is reviewed in [draft PR #2](https://github.com/RaghavSharma006/lumarie/pull/2).
It contains a real Wi-Fi image sender and ESP32-S3 receiver, 6-color panel
rendering code, authenticated v1 image packets, CRC32, and a Windows
backup-first installer. The older root `firmware/main` project is the original
ESP32-C3 candidate rather than the tested EE04 build.

**Downloads:** [GitHub Releases](https://github.com/RaghavSharma006/lumarie/releases).
Use only the clearly labeled `v0.2.0-ee04-preview.1` Android and firmware
assets. The APK uses a development signing certificate; the firmware requires
exactly the XIAO ESP32-S3 Plus (16 MB) and 7.3-inch Spectra 6 ED2208 on EE04,
NOT the supplier's ESP32-C5.

**Verification status:** GitHub CI has compiled the firmware and Android APK,
Flutter analyzer and the authenticated full-frame local TCP tests pass.
However, live phone-to-board BLE provisioning, Wi-Fi and actual panel output
have **not yet been verified on physical hardware**. Photo bytes are HMAC
authenticated but not end-to-end encrypted: trusted LAN prototype only.
See [preview safety and installation instructions](docs/RELEASE_EE04_PREVIEW.md).
The release is a prerelease, not a production-ready consumer product.
