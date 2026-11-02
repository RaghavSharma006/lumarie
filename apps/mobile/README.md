# Lumairie mobile

Flutter Android/iOS companion for an offline Spectra 6 frame. The UI contains the eight supplied reference screens in light and dark themes. All sample art and widget data are visibly identified as Demo Mode; no screenshot photos are bundled. Chosen images are copied to the app's private documents directory. Preferences stay in local `SharedPreferences`; authenticated QR credentials are saved with `flutter_secure_storage` after a successful Espressif Security 2 handshake.

## Run

```text
flutter pub get
flutter analyze
flutter test
flutter run
```

The local Windows SDK used during development is `D:\flutter-sdk\bin\flutter.bat`. Android builds need Android SDK command-line tools, accepted licenses, and a configured device/emulator. iOS builds require macOS, Xcode and CocoaPods. The app has no backend or runtime internet requirement.

## Current vertical slice

- Home, gallery, preview, hub, settings, pairing, add widget and second frame preview routes use shared tokens and components.
- Photo picker persists selected files locally. Preview has portrait/landscape, fit/fill, drag-to-reframe and rotation controls. Processing uses center/focal crop, nearest resampling, basic Floyd-Steinberg six-color quantization and two indices per byte.
- Demo Mode transmits the 192,000-byte candidate buffer to a mock frame through the versioned binary request format. The mock rejects incomplete, reordered or corrupt data and refreshes only after complete verification. Retry after a lost ACK is idempotent.
- Real QR onboarding scans `lumairie://pair?id=...&name=LUMAIRE-XXXXXX&user=...&secret=...`, discovers the matching BLE name and attempts an authenticated SRP6a/AES-GCM `PING` on the firmware `frame` endpoint. This handshake has not been tested on hardware.
- The real image transfer and local firmware update buttons are not exposed until a persistent authenticated native BLE session and a verified board are available. Demo progress is labeled as simulated. A signed A/B OTA receiver exists in firmware but is disabled by default until signing is configured.

## Hardware boundary

The exact 7.3-inch Spectra 6 controller, driver board, part number, SPI pins, voltages, waveform and palette mapping were not supplied. The firmware uses a mock display adapter and does not claim to drive a physical panel. The candidate 800×480 raster and color ordering must be checked against the supplier's full specification. See `../../docs/STATUS.md` and `../../shared/protocol/README.md`.
