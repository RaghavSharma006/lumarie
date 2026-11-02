# Lumairie status — 2 November 2026

The starter archive contained only `BUILD_PROMPT.md` and two reference collages. The project was scaffolded from those files. Flutter 3.47.9 and Dart 3.13.7 were installed locally for this build. The references were visually inspected before widget implementation.

## Implemented

- Flutter Android/iOS project with eight routes in light and dark themes, a reusable visual system and 16 golden renders. Demo Mode is explicit; sample artwork is original code-drawn art.
- Local photo picking and app-private copies; orientation, fit/fill, drag crop and rotate controls; six-color Floyd-Steinberg candidate codec; 4-bit packed stream, 192,000 bytes at 800×480; CRC32.
- Versioned BEGIN/CHUNK/END/ABORT serializer and mock receiver with ordered chunks, duplicate retry after lost ACK, bounded allocations and commit only after complete CRC validation. Unit tests include truncation, reorder, corruption and success.
- QR parser and scanner; BLE discovery and Espressif Security 2 authenticated PING via a native Android/iOS provisioning plugin. Credentials are stored with `flutter_secure_storage` only after authentication. This path awaits a provisioned physical unit for validation.
- ESP-IDF ESP32-C3 candidate project with custom secure protocomm BLE endpoint, flash staging partition, mock panel adapter, configured physical hold gate, verified GPIO deep-sleep wake and A/B signed-update receiver gated by signing configuration.

## Verified on this host

- `flutter analyze --no-pub`: no issues after the implemented changes.
- `flutter test --no-pub`: unit, widget and all 16 visual tests passed at the last run. Re-run after any further changes.
- Golden images were opened and compared to both supplied collages. Their layout, palette, framed image treatment, pill controls, dashed add surfaces and bottom nav match the reference structure. Illustrated art differs because no licensed source photographs were supplied.
- Android debug APK build was started; record its final outcome below.

## Blocked or incomplete

- Exact panel/controller and driver-board documents, GPIO/power schematic, flash size and prototype measurements were not supplied. Real display refresh and button integration cannot be validated or enabled safely.
- No physical unit was supplied, so BLE pairing, throughput, flash staging, deep sleep, OTA and rollback have not been hardware tested. ESP-IDF is not installed on this host; firmware compilation has not been run.
- Persistent real image and OTA delivery from the mobile app are not implemented. The provisioning plugin authenticates a short endpoint request but reconnects for each call, so it is not a suitable full-image transport. The UI does not claim a physical refresh.
- Exclusive ownership transfer, physical factory reset with credential rotation, manufacturing NVS/eFuse provisioning, and secure signing-key setup remain production requirements.
- iOS compilation needs macOS and Xcode. Android release distribution needs production signing and store account access. No live hosting URL applies to this offline native product.

## Next steps

1. Obtain exact panel and driver-board documentation plus a prototype, confirm candidate flash and GPIO configuration.
2. Build/test ESP-IDF on an installed toolchain and provision unique factory SRP credentials with protected NVS. Exercise physical wake and authentication.
3. Add a persistent native authenticated BLE transport for binary image and signed firmware chunks; test phone-to-hardware power-loss and corruption paths.
4. Implement the verified display adapter, measure power, run color-index fixtures, and complete safe credential rotation/ownership transfer.
