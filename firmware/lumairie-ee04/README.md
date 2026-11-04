# LUMAIRIE EE04 integration — work in progress

**This is not finished production firmware and must not be used as a pairing-ready release.**

The existing Flutter app is the protocol source of truth:
- QR: `lumairie://pair?id=<8..64 alnum/_/->&name=LUMAIRE-<6 hex>&user=<username>&secret=<secret>`.
- Scan prefix `LUMAIRE-`; Espressif `esp_provisioning_wifi` Security 2 (SRP6a/AES-GCM), custom endpoint `frame`, `PING` -> `{"protocol":1}`.
- The existing app **does not submit Wi-Fi credentials**: `apps/mobile/lib/services/pairing.dart` calls `scanBleDevices` and `fetchCustomData` only. Do not invent an app Wi-Fi API.
- The older `firmware/` project is an ESP32-C3 candidate. It is *not* the EE04 production firmware and `mock_display_refresh` does not energize a display.

## Hardware verified upstream
- Seeed EE04 V1.4/XIAO ESP32-S3 Plus; 50-pin FPC set by hardware jumper.
- Seeed_GFX `BOARD_SCREEN_COMBO=509`: ED2208, 7.3-inch Spectra 6, 800 × 480.
- `USE_XIAO_EPAPER_DISPLAY_BOARD_EE04` selects Seeed's own pin map, power and initialization sequence. No raw SPI GPIO map is fabricated.
- KEY0 GPIO2, KEY1 GPIO3, KEY2 GPIO5 (active low).
- XIAO ESP32-S3 Plus: 16 MB flash, 8 MB PSRAM (enable Octal PSRAM).
- Seeed PlatformIO instructions use `seeed-xiao-esp32-s3-sense` and `qio_opi` memory settings for EE0x boards; validate on actual Plus hardware.

## Display diagnostic (NOT BLE provisioning)
`display-smoke/` is a *standalone flashable project* using the official Seeed_GFX driver and ricmoo QRCode. It displays the exact QR URI supplied in NVS namespace `factory`, key `qr_uri` (string). It does not generate a fake identity, embed a universal secret, operate BLE, or configure Wi-Fi. Missing credentials are displayed as an error. It neither prints nor transmits QR secrets.

Before this can display a real pairing QR, manufacturing/provisioning must install a unique `qr_uri` for the board and the matching Security-2 SRP salt/verifier for the *application firmware*. Do not commit secrets to Git or use sample QR credentials. Protect factory NVS with flash encryption on shipping units; the existing firmware expects `factory/srp_salt` and `factory/srp_verifier`. **Writing a qr_uri alone does not enable pairing.** These two components are not yet merged into one running firmware image.

### Build (only in an environment with PlatformIO + Seeed platform access)
```sh
cd firmware/lumairie-ee04/display-smoke
pio run -e ee04_spectra6
```
The environment used for this commit has no PlatformIO or ESP-IDF installation and no outbound network access. **This has not been compiled**. The expected output is `.pio/build/ee04_spectra6/firmware.bin` only after a successful build.

### USB flash — only after explicit backup/approval
1. Confirm your physical panel is 7.3-inch Spectra 6 ED2208, not Seeed's 7.5-inch monochrome panel, and verify the 50-pin jumper.
2. Backup any existing firmware and NVS (including encryption/partition metadata) before flashing. Flashing a different partition table or application may make existing credentials inaccessible or replace the current app.
3. Connect XIAO ESP32-S3 Plus using a data-capable USB-C cable. Locate the serial port. If needed, enter ROM download mode using Seeed's BOOT/RESET instructions.
4. Only when ready to replace the currently installed application, run `pio run -e ee04_spectra6 -t upload --upload-port <PORT>`. Monitor with `pio device monitor -b 115200`. **Do not run `erase_flash` or `idf.py erase-flash`**.
5. Expect the branded pairing QR only if a valid factory NVS `qr_uri` was preinstalled. KEY0 (GPIO2) redraws without clearing NVS.

## Blocking integration work
- Merge the display driver/QR screen into an ESP32-S3 firmware that includes the current protocomm Security 2 `frame` endpoint and consistent NVS credential lifecycle (two standalone flash images cannot operate at once).
- Integrate actual ESP-IDF Wi-Fi provisioning with persistent status reporting. The current app exposes no Wi-Fi-credential submission call, so end-to-end Wi-Fi onboarding cannot be completed without an *existing* app path being identified or a separately approved minimal compatibility change.
- Compile for physical hardware, resolve dependency/API errors, verify the GATT endpoint/security handshake, panel refresh, QR scanning, successful Wi-Fi DHCP, failure recovery and physical reset behavior. No physical tests have been performed.
