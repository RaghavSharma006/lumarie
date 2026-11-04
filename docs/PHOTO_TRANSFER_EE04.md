# LUMAIRIE EE04 photo transfer: local network prototype

## Purpose and readiness

This implementation connects the existing app's Send button to the Seeed XIAO
ESP32-S3 Plus + EE04 V1.4 + 7.3-inch Spectra 6 ED2208 display. It does not
replace the existing app QR format, Espressif BLE Security 2, or frame protocol
v1. The simulator still operates on Flutter Web; native Android/iOS uses the
real local-Wi-Fi transport after authenticated pairing and provisioning.

**Hardware validation remains required.** Software tests cannot prove a
particular EE04 panel's ribbon orientation, BUSY timing or full refresh.

## End-to-end data path

1. Pair using the existing `lumairie://pair?...&secret=...` QR, authenticated
   Security 2 `frame` / `PING` handshake, and encrypted device credential
   storage on the phone.
2. Join a 2.4 GHz Wi-Fi network from the existing Connecting page. Phone and
   frame must be on the **same LAN** with peer-to-peer connections allowed.
   A guest network with wireless isolation cannot work.
3. Choose a photo and press the existing Send button. The app scales/crops,
   dithers and packs the image as before: six palette indices, high nibble
   first, 800x480 landscape or 480x800 portrait, 192,000 bytes, CRC32.
4. App broadcasts `LMD1 + 8-byte random nonce` over UDP port 38343. Device
   replies with `LMD2 + 14-byte BLE name + 4-byte IPv4 + nonce + 32-byte
   HMAC-SHA256`. App accepts only exact name/nonce/HMAC matches against the
   paired device secret, never arbitrary IP responders.
5. App connects to TCP port 39393; device sends `LMF1 + 16 random bytes`.
   App proves the QR secret with HMAC-SHA256 over the greeting and exact device
   name. No plaintext secret or username travels over TCP.
6. Each v1 packet is sent with a u32 little-endian increasing sequence, u16
   little-endian payload length (1..261), payload, and HMAC over
   `REQ1 + device nonce + sequence/length + payload`. Firmware verifies
   exact sequence and MAC before touching staging RAM. It replies with
   matching sequence, 9-byte v1 acknowledgement and HMAC over
   `ACK1 + nonce + seq + ACK`. Any invalid MAC aborts the TCP session.
7. The original `CAPABILITIES`, `BEGIN`, `CHUNK`, `END` and `ABORT`
   opcodes and packet byte layouts remain unchanged. Each CHUNK has up to
   256 bytes; identical already-delivered chunks are idempotent, corrupted
   retransmissions fail. Incomplete/misordered requests never display.
8. The full 192 KB frame is staged in 8 MB PSRAM, verified by CRC32,
   translated to Seeed_GFX's actual six Spectra 6 colors and refreshed using
   Seeed's ED2208 driver. The firmware sends `DISPLAYED=2` only after
   `panel.update()` returns. The app reports success only on this ACK.
   Epaper status screens no longer overwrite a successfully displayed photo.

## Important security and operational limits

- **Prototype trusted-LAN only.** HMAC authenticates sender and ACKs and
  prevents sequence tampering, but **photo bytes are not application-layer
  encrypted**. A router admin or on-path attacker on the LAN may observe
  image data. Before production deployment add AEAD/TLS plus a security review.
  Do not advertise this as end-to-end encryption.
- Wi-Fi transport only runs after the board actually obtains an IP address.
  A guest network, client isolation, missing local-network permission, or
  blocked UDP broadcast may prevent discovery. Test on normal 2.4 GHz home
  Wi-Fi first.
- Device discovery and full display refresh are not instantaneous.
  A Spectra 6 refresh can be slow. END waits up to three minutes in the app.
- Staging is PSRAM, not a persistent flash image. Epaper keeps its visible
  picture when power is removed, but on firmware reboot the current
  welcome/status screen may overwrite it. Persistent image restore is not
  implemented.
- The existing prototype does not yet support firmware OTA or mass-production
  ownership transfer. MQTT/cloud are **not** used and this is not firmware
  for the supplier's different ESP32-C5 product.
- The source is on the photo-transfer feature branch until compiled and
  hardware-tested, and should not be merged as a production release yet.

## Verification

```sh
cd apps/mobile
flutter analyze lib
flutter test test/pairing_test.dart test/frame_wifi_transport_test.dart

cd ../../firmware/lumairie-ee04/device
pio run -e ee04
```

The loopback test uses a real TCP socket and exercises all 750 CHUNK requests,
with per-request HMAC verification and complete CRC/ACK semantics. It is still
a software emulator of the receiver, not evidence of physical hardware.

For the first real-board test, back up the existing flash as described in
`firmware/lumairie-ee04/README.md`, flash only with the Seeed ESP32-S3 Plus
16 MB configuration, scan the QR from the screen, join Wi-Fi, send a test
photo, and verify the 6-color image and next image replacement. No chip
erase, eFuse changes, or external wiring are required.
