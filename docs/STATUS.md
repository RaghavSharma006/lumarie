# Lumairie implementation status — 2 November 2026

## Working and verified

- Flutter Android/iOS source with eight reference screens in light and dark themes, reusable visual components, functional local photo picking, crop/orientation, and a distinct Demo Mode. Sixteen golden renders were compared with the supplied reference collages.
- Shared six-color candidate image pipeline: crop/fit, Floyd–Steinberg dithering, 800×480 raster, 4-bit two-pixels-per-byte packing (192,000 bytes), CRC32, and a packed-frame PNG preview. Actual panel color indices remain unverified.
- Versioned chunk protocol and mock receiver with sequence checks, duplicate ACK handling, CRC validation, and previous-frame retention on corrupt or interrupted sends.
- Android debug APK compiled successfully. The Windows simulator is a Flutter Web build served only on localhost; browser end-to-end checks used a real photograph and verified retained frame pixels on both failure modes.
- QR parser, BLE discovery, and ESP-IDF Security 2 endpoint authentication structure. Secrets are stored in Android Keystore/iOS Keychain via `flutter_secure_storage` after the authenticated PING.
- ESP32-C3 candidate ESP-IDF source with flash staging, CRC verification, mock display adapter and signed A/B OTA receiver structure. It has not been compiled or tested on hardware.

## Production gaps

- The cited Alibaba product page was inaccessible to the browser research tool. Good Display publishes a GDEP073E01 800×480 Spectra 6 module and an ESP32 sample-code page, but no evidence yet connects those parts to the actual Alibaba offering. Supplier BOM, exact panel/controller, driver board, schematic, pin map, power rails, and waveform/command documentation are required. The real display driver remains a mock.
- The current firmware candidate requires a physical pairing GPIO and may deep sleep. That design conflicts with the final **buttonless, Wi-Fi-connected standby** requirement. Do not flash it as production firmware. Wi-Fi provisioning, mDNS discovery, authenticated encrypted local transfer, exclusive ownership/rotation and light-sleep power behavior still need implementation and physical measurements.
- The mobile app authenticates a short BLE PING but has no persistent physical image or OTA transport. Real-device Send remains disabled and the UI does not claim a physical refresh. Signed OTA receiver logic cannot substitute for phone-side delivery or verified factory signing and rollback tests.
- `idf.py` and ESP-IDF toolchain are unavailable on this host. No firmware binaries are delivered. iOS compilation requires macOS/Xcode; no IPA is delivered.
- The Windows browser simulator keeps its photos in memory for the browser session. Native app photos use app-private local files. Browser simulator behavior is not a hardware or battery validation.

## Hardware references

- Intended module: https://www.alibaba.com/product-detail/7-3-Inch-Color-E-Ink_1601965065583.html (identity and wiring unconfirmed).
- Candidate panel: https://www.good-display.com/product/533.html.
- Candidate sample code: https://www.good-display.com/companyfile/1435.html.
- Possible adapter: https://www.good-display.com/product/522.html (compatibility unconfirmed).
