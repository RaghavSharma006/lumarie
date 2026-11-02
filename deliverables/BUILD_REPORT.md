# Lumairie build report — 2 November 2026

## Artifacts

| Deliverable | Bytes | SHA-256 | Verification |
| --- | ---: | --- | --- |
| `android/Lumairie-debug.apk` | 209,517,857 | `ef839b971ce44967984dd0006475a2c600f7a2a8ee40d6b521cdfd9f5ec12bbd` | `flutter build apk --debug --no-pub` succeeded; Android `apksigner verify` confirmed APK Signature Scheme v2; `aapt2 dump badging` identified `io.lumarie.mobile`, version 0.1.0, min SDK 24. |
| `windows/Lumairie-Windows-Simulator.zip` | 14,811,675 | `1ae9fdfca3345c6fabb6ca8f022406240beb37655167de64c6d76b3cd400e630` | ZIP entries checked, extracted launcher started a server at `127.0.0.1:8787`, and HTTP `/` returned 200. The launcher sleep command was then corrected and the ZIP rebuilt; the updated launcher entry was checked. |
| `HARDWARE_TEST/Lumairie-arm64-release.apk` | 26,088,803 | `8a5d7a8adfb952e23a041aaf1ba4d180938bd739d2472980739789f0ef483bcf` | `flutter build apk --release --split-per-abi` succeeded; ABI-specific ARM64 APK verified with `apksigner` v2 and `aapt2`. Uses the development/debug signing key. |

No firmware `.bin` or iOS `.ipa` is included. ESP-IDF source was cloned but the toolchain installation and firmware compilation were not completed; iOS requires macOS/Xcode. Both APKs use development/debug signing.

## Source checks

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 26 passed, including 16 light/dark reference-screen goldens, image codec, protocol, pairing QR, and failure-retention tests.
- `flutter build web --release --no-pub`: succeeded; JavaScript output used by the Windows simulator. Flutter warned that the secure-storage web plugin does not support a WebAssembly build; this deliverable uses JavaScript.
- Chrome/Playwright end-to-end test: a real local photograph was uploaded, converted and transferred in Demo Mode. A screenshot crop changed after successful transfer; the same pixels were retained after corrupt and interrupted sends. The test also exercised the packed-frame preview on the fake display. This does not validate real hardware color or power.
- `idf.py`: unavailable, so no firmware compilation or physical tests. No proprietary display commands or pinouts have been assumed.

## Hardware and integration status

The intended Alibaba module (product 1601965065583) could not be fetched by the research tool. Good Display lists a potentially related GDEP073E01 7.3-inch 800×480 Spectra 6 panel and ESP32 sample code, but no supplier evidence establishes that it is the exact Alibaba assembly, its controller, adapter, wiring, power circuit, or MCU. The firmware deliberately uses a mock display adapter.

The current ESP32-C3 source is an **uncompiled candidate** with physical-button pairing and deep sleep. It does not satisfy the final buttonless Wi-Fi standby requirement. The phone app authenticates a short BLE endpoint exchange but cannot yet securely send a full image or signed OTA update to a real frame. There is no verified Wi-Fi provisioning, mDNS, encrypted local transfer, exclusive ownership reset, or measured idle responsiveness. Real-device Send remains disabled rather than reporting a fake refresh. The OTA receiver structure depends on secure signing configuration and has no phone-side delivery or hardware rollback test.

Production work requires the exact supplier BOM/schematic and panel driver documentation, a factory provisioning and signing process, an ESP-IDF build host, and a prototype for transport, display and power tests. The final product must use no Lumairie cloud service. The local simulator runs at `http://localhost:8787`; there is no external deployment URL.
