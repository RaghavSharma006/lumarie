# Lumairie Direct Wi-Fi — EE04 hardware preview

> Hardware-test code, not yet validated on a real EE04 panel. No release APK or
> firmware has been published for this branch. Do not flash unless the board is
> **Seeed XIAO ESP32-S3 Plus + EE04 V1.4 + ED2208 Spectra 6, 50-pin jumper**.
> An ESP32-S3 identification and 16MB flash alone do not establish panel match.

## User flow (Android 10+)

1. Plug the Lumairie frame into power. It creates a private 2.4 GHz WPA2 network
   named `LUMAIRIE-XXXXXX`. The frame keeps its unique pairing QR on screen.
2. Open the app, switch Demo Mode OFF and tap **Add a frame**.
3. Scan the QR on the physical frame, once. The phone saves the per-unit secret;
   it has **not** authenticated the frame merely by scanning the QR.
4. Pick a photo and tap **Send to LUMAIRIE frame**.
5. Android asks whether to connect to that particular `LUMAIRIE-XXXXXX`
   network. Tap **Connect**. The app then HMAC-authenticates the frame and
   sends the 192,000-byte image directly to `192.168.4.1:39393`.
6. The frame verifies CRC32 and completes the ePaper refresh before reporting
   success. The app releases the local Wi-Fi request afterwards.

No router, customer Wi-Fi credentials, BLE pairing, cloud service or internet
connection is required. The connection is intentionally local-only, so Android
may show **No internet**. That is normal. Keep phone Wi-Fi enabled.

Android 10+ is required for the automatic network approval prompt. Android
9 or lower, and iOS, are not supported for automatic joining by this preview.

## Security

- The factory generates a unique random 48-hex-character secret on first boot.
- The hotspot uses the first 20 characters as its WPA2 passphrase; the entire
  secret remains the existing HMAC authentication key.
- There is **no shared password across frames**. The password is not logged.
- The app does not call the BLE Security-2 provisioning path in this build.
  Scanning a QR alone is not authenticated identity verification; the subsequent
  TCP HMAC challenge authenticates the session.
- HMAC protects image integrity and authentication; TCP pixels are **not
  application-layer encrypted**, though WPA2 encrypts the Wi-Fi link.
- Keep the QR private. NVS flash encryption and secure boot are not enabled.
- Do not factory reset/erase NVS to solve a transfer problem: it rotates or
  destroys the credential needed by the app.

## Firmware configuration

`firmware/lumairie-ee04/device/src/main.cpp` starts `WiFi.mode(WIFI_AP)`,
`WiFi.softAPConfig(192.168.4.1/24)`, and `WiFi.softAP` after loading factory
identity. No station-side provisioning or home-network discovery is required.

The original authenticated photo server remains on TCP port 39393; its UDP
discovery reply now advertises `WiFi.softAPIP()`. The app bypasses broadcast
discovery and sends to the known SoftAP address.

Holding the EE04 KEY0 button for eight seconds restarts the preview without
erasing the secret. The hotspot is always on while the device is powered.
**This prototype consumes continuous Wi-Fi power and is unsuitable for
deep-sleep/battery-only deployment without a wake/control redesign.**

## Build

```sh
git checkout feature/ee04-self-wifi
python -m unittest discover -s firmware/lumairie-ee04/tests -p 'test_*.py' -v
cd firmware/lumairie-ee04/device
pio run -e ee04
cd ../../../apps/mobile
flutter pub get
flutter analyze --no-pub lib
flutter test test/pairing_test.dart test/frame_ap_test.dart test/frame_wifi_transport_test.dart
flutter build apk --release
```

GitHub Actions attached to the PR uploads the compiled firmware files and APK.
Only install the **matching** APK+firmware from the same successful CI run.

## Checks before calling it working

- AP appears as `LUMAIRIE-XXXXXX` on phone Wi-Fi scan.
- The QR can be scanned in the Android app.
- Android OS approves the app's local-only Wi-Fi request and the app connects.
- A full 192,000-byte send completes with authenticated ACKs and CRC32.
- The correct ED2208 panel visibly displays the image after full refresh.
- The phone returns to its previous network and repeated sends work.

These are **manual hardware tests still required**. CI compilation and
protocol simulation cannot prove the panel connection or screen refresh.
