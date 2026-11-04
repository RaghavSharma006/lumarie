# LUMAIRIE XIAO EE04 V1.4 firmware — integration branch

**Status: CI compilation and Flutter pairing checks passed; physical hardware testing NOT complete.** The
source code is real, not a BLE simulator. Do not ship or flash over a working
device until the 16 MB partition layout and Security 2 compatibility are verified.

## Projects

- `device/` — combined EE04 firmware: ESP32-S3 Plus, Seeed_GFX ED2208
  Spectra 6, per-device QR on 800×480 ePaper, ESP Unified BLE provisioning,
  Wi-Fi events, NVS configuration and KEY0 recovery.
- `display-smoke/` — separate low-level display diagnostic, NOT the device
  provisioning firmware. Only use it to isolate a display hardware problem.
- `tests/` — offline app/firmware source-contract checks.
- `firmware/main/` — older ESP32-C3 candidate, not the EE04 build.

## Verified hardware

- Board: XIAO ESP32-S3 Plus on Seeed EE04 V1.4; 16 MB flash, 8 MB PSRAM.
- Select 50-pin panel jumper per [Seeed EE04 wiki](https://wiki.seeedstudio.com/epaper_ee04/).
- Seeed_GFX `BOARD_SCREEN_COMBO=509`: 7.3-inch ED2208 Spectra 6, 800x480.
- EE04 KEY0 is active-low GPIO2. An eight-second press forgets **only**
  Wi-Fi settings; it never erases the whole flash or the QR/SRP factory data.
- The PlatformIO configuration selects Seeed's exact `seeed-xiao-esp32-s3-plus`
  board, `qio_opi` PSRAM and a 16 MB Arduino partition layout.

## Source-of-truth BLE/QR protocol

This project DOES NOT introduce a new BLE UUID or JSON provisioning scheme.
The existing Flutter app's `PairingCredential.parse` accepts:

```text
lumairie://pair?id=<8..64 alnum_->&name=LUMAIRE-<6 uppercase HEX>&user=<username>&secret=<16..128 chars>
```

The firmware generates a stable per-device URI on a clean first boot, using
ESP32 hardware randomness, and stores it under `factory/qr_uri` in NVS. The
same random secret is used to generate `factory/srp_salt` and
`factory/srp_verifier` using Espressif's `esp_srp_gen_salt_verifier`. On later
boots it loads those values rather than changing the QR. If a partial/invalid
factory identity exists, setup fails closed rather than overwriting credentials.

**Security note:** This development build stores the QR URI in NVS so it can
be redrawn. Production units should enable flash/NVS encryption and secure
boot under an audited manufacturing/recovery policy. Do not automatically
burn eFuses or enable irreversible security options without an explicit plan.

BLE advertisement: `LUMAIRE-%02X%02X%02X` (Bluetooth MAC suffix). The 128-bit
service UUID is the same byte array as `firmware/main/main.c`. GATT endpoints
use Espressif's standard network_provisioning/protocomm scheme, with the
authenticated custom endpoint `frame` (`PING` -> `{"protocol":1}`).
ESP-IDF Security 2 protects all sessions with SRP6a + AES-GCM; no passwords are
logged. The standard `prov-config`, `prov-scan` and `prov-session` GATT
endpoints handle actual Wi-Fi provisioning; these are not custom mocks.

The Flutter pairing service now also exposes
`provisionStoredWifi(deviceId, ssid, passphrase)`, and the existing
"Connecting your frame" screen invokes it from a small Wi-Fi dialog after
pairing. It uses the encrypted per-device credential already stored on the
phone. There is no new app or backend.

## Real provisioning and display states

The event path transitions between BOOTING, INITIALIZING, WAITING_FOR_SETUP,
BLE_CONNECTED, CONFIGURING_WIFI, CONNECTING_WIFI, WIFI_CONNECTED,
PROVISIONING_FAILED, and NORMAL_OPERATION. The device considers Wi-Fi
connected **only after IP_EVENT_STA_GOT_IP**, not after simply receiving the
password. Failed connections display an error and the ESP provisioning
state machine can retry. A successful connection replaces the QR with
CONNECTED. Wi-Fi configuration uses ESP-IDF NVS flash storage.

The Spectra 6 panel needs a relatively long full refresh. State updates are
coalesced with a minimum five-second interval; very short transient states
may not appear individually on ePaper. Do not interpret that as a fake event.

## Build, artifacts and USB-C flash

Requires working PlatformIO and Seeed's platform and libraries (internet
access needed for first dependency install). On a development machine:

```sh
git checkout firmware/ee04-hardware-integration
python -m pip install -U platformio
python -m unittest discover -s firmware/lumairie-ee04/tests -p 'test_*.py' -v
cd firmware/lumairie-ee04/device
pio run -e ee04
```

Expected build output *after compilation succeeds*:
`device/.pio/build/ee04/firmware.bin`. The repository CI workflow
successfully compiled the integrated application and the standalone diagnostic,
ran eight offline firmware protocol tests, passed Flutter analyzer and the
existing pairing test. It uploaded `lumairie-ee04-integrated-firmware` and
`lumairie-ee04-flash-images` artifacts; the latter includes `bootloader.bin`,
`partitions.bin` and `firmware.bin`. See the passing
[GitHub Actions run](https://github.com/RaghavSharma006/lumarie/actions/runs/41820883985).
**No real EE04 display, BLE or Wi-Fi hardware test has been performed.**

**Before flashing**, confirm a 7.3-inch ED2208 Spectra 6 panel, 50-pin
jumper, Plus MCU, 16 MB capacity, and a USB-C DATA cable. Back up existing
firmware, partition table, factory NVS and eFuse encryption state securely.
Flashing a changed partition table/application can make existing firmware
unbootable or factory data inaccessible. Do not run `erase_flash`.
Once you explicitly approve replacing the installed firmware, use:

```sh
pio run -e ee04 -t upload --upload-port <SERIAL_PORT>
pio device monitor -b 115200 --port <SERIAL_PORT>
```

For a blank board, the normal PlatformIO upload writes the bootloader,
partition table and app as required; a single app `firmware.bin` is not
sufficient by itself. See Seeed's bootloader/BOOT+RESET entry instructions
if the port is not detected. Do not auto-erase flash.

## Validation still required

1. Compile/link on Seeed's PlatformIO platform and fix any version-specific
   framework/include/driver errors.
2. Verify Arduino ESP32 3.3.x's `network_provisioning` Security 2 GCM IV
   compatibility with the Flutter plugin on BOTH Android and iOS. A known
   upstream version mismatch may require a newer provisioning component.
3. Flash only after backup/confirmation and test 50-pin ePaper power sequence,
   first-boot QR, contrast/scanning, BLE discovery and authenticated `PING`.
4. Submit valid/invalid Wi-Fi credentials; verify real DHCP status, restart
   persistence, fail/retry behavior, and eight-second KEY0 Wi-Fi-only reset.
5. Enable/validate flash encryption, production credentials and ownership reset
   policy before deployment. Image-transfer and OTA functions from the old
   candidate firmware are NOT carried over; the existing app still disables
   live photo transfer and uses a simulator for image frames.

Never interpret source-level contract tests or a rendered diagnostic as
confirmation of successful provisioning on the actual EE04 board.
