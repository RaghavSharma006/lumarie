# LUMAIRIE EE04 — Android + ESP32-S3 preview

This is a **developer preview / physical-hardware test build**, not a general
consumer-ready release. Do not market it as secure, production-tested, or
guaranteed to run on an unverified display assembly.

## Hardware
- Seeed EE04 V1.4 with **XIAO ESP32-S3 Plus**, 16MB flash, 8MB PSRAM
- **7.3-inch 800x480 ED2208 Spectra 6** ePaper; board jumper **50 PIN**
- USB-C data cable; use 2.4GHz Wi-Fi network shared with the Android phone
- It does **not** target the supplier's ESP32-C5 board

## Release downloads
- `LUMAIRIE-Android-EE04-PREVIEW.apk`: an Android hardware-test APK
  **signed with the development/debug certificate**, not a production app
- `LUMAIRIE-EE04-ESP32S3-FLASH-IMAGES.zip`: official PlatformIO-built
  bootloader, partitions, and firmware, a backup-first Windows launcher
  (`START_LUMAIRIE_WINDOWS.bat`), and safety instructions
- `SHA256SUMS.txt`: file integrity hashes

**Never flash the old pre-photo-transfer firmware** if you intend to test
sending photographs. The updated source branch is
`feature/ee04-photo-transfer`.

## Beginner Windows installation
1. Download the two GitHub Release assets (Android APK and EE04 flash ZIP).
2. On Windows, extract the flash ZIP and double-click
   `START_LUMAIRIE_WINDOWS.bat`. Install Python 3.11+ only if prompted.
3. Read the safety warnings, check the **50 PIN** jumper while unplugged,
   select the actual XIAO ESP32-S3 Plus USB COM port and verify its chip and
   security state.
4. Let the installer back up all 16 MB of existing flash. Store the backup
   privately; it may contain passwords and QR credentials.
5. Only if the board is the exact verified EE04 target and you agree to
   replace installed bootloader/partitions, type `FLASH` at the final prompt.
6. Install the APK on an Android test phone, pair, provision Wi-Fi and send
   a photo on the same trusted LAN.

The Windows uploader has source-level checks, but it has **not** been run on
the user's physical Windows PC; it refuses operations when verification
information is missing.

## Flashing
- Prior to flashing, inspect jumper/cable, back up the existing **entire
  16MB flash** and device identity/settings, verify chip and flash size, and
  check secure boot/encryption status; any incompatible security state is a
  blocker, not something to bypass.
- Do not use `erase_flash`. Programming the bootloader/partition table is
  destructive to previously installed firmware and **may invalidate existing
  NVS/credentials** even without a whole-chip erase.
- Recommended install via PlatformIO from the source branch:
  ```sh
  cd firmware/lumairie-ee04/device
  pio run -e ee04
  pio run -e ee04 -t upload --upload-port COM5
  ```
  Replace COM5 with the actual serial port. Read
  `firmware/lumairie-ee04/README.md` first.
- If using raw images, verify the board is ESP32-S3 Plus with 16 MB flash.
  Use esptool only with the correct offsets:
  ```sh
  python -m esptool --chip esp32s3 --port COM5 write-flash 0x0 bootloader.bin 0x8000 partitions.bin 0x10000 firmware.bin
  ```
  The raw-image command **writes bootloader/partition regions**. It is
  presented for experienced users only; backup and physical verification
  are essential. It is not an alternative to verifying the assembly.

## Mobile / photo transfer
1. Install APK on an Android test phone (accept sideloading only if you
   trust the GitHub release and verified SHA256). The previous app may need
   to be uninstalled because a debug-signed APK cannot update an existing
   app signed with a different key; this can delete locally stored QR
   credentials.
2. On initial setup choose **real device mode**, scan the EE04 QR, establish
   authenticated BLE Security2 pairing and submit Wi-Fi credentials.
3. Put phone and frame on the same non-isolated 2.4 GHz Wi-Fi LAN.
4. Select a photo and tap Send. The software sends a 192KB six-color frame
   with ordered chunks, HMAC authentication and a full CRC32 check. The
   physical display should refresh before the app reports success.
5. If a step fails, collect log output with sensitive QR secrets/passwords
   removed, and file a GitHub issue. Do not claim pairing or image
   rendering successful unless the physical board demonstrates it.

## Known limits
- Wi-Fi photo content is **not end-to-end encrypted**. HMAC authenticates
  messages and checks integrity, but an on-path observer can inspect
  pixels. Use only on trusted test LANs.
- The real ED2208 screen color order and refresh behavior have **not been
  validated on a user's physical device**.
- No persistent photo restore after reboot, production secure boot,
  ownership transfer, firmware OTA, signed mobile release, or iOS install.
- The two draft source PRs are intentionally not merged to `master`
  until physical tests and production security review pass.
