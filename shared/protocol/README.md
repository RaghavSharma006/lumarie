# Lumairie frame protocol v1 (candidate)

All integers are unsigned little endian. Physical sessions must be protected by Espressif protocomm Security 2 (SRP6a plus AES-GCM) with a per-unit QR secret and an open physical pairing window. CRC32 only detects accidental corruption; it is not authentication. The app currently authenticates a short BLE pairing request but does not expose a real image-transfer link yet.

The payload is a six-color index stream, two 4-bit indices per byte, left pixel in the high nibble. `white=0`, `black=1`, `red=2`, `yellow=3`, `blue=4`, `green=5` are **candidate indices** pending exact panel driver verification. Candidate raster is 800×480 landscape or 480×800 portrait, 192,000 bytes. The display adapter must map or reject the stream when hardware details arrive.

Transaction:

1. `CAPABILITIES`: protocol version and maximum chunk size. Raster and firmware version exchange is planned.
2. `BEGIN`: protocol version, width, height, total length and CRC32. Firmware checks bounds and erases only staging flash. Explicit transaction IDs and codec negotiation are planned.
3. `CHUNK`: byte offset and up to 256 data bytes. Receiver acknowledges the next expected offset. Identical duplicates may be acknowledged after a lost ACK; out-of-order or mismatched data is rejected. Sender restarts after disconnect unless a proven resume token is later implemented.
4. `END`: firmware verifies length and CRC over staging; only then calls the display adapter. `DELIVERED` means verified staging; `DISPLAYED` means adapter reports refresh complete. The app keeps these states separate.
5. `ABORT`: invalidate staging without touching the visible E-Ink image.

Storage/power constraints: a 512 KiB data partition is a candidate for staging, pending flash-size confirmation. A sleeping frame cannot receive BLE. User must wake it before discovery or transfer. Image bytes must never be rendered directly from a partial transfer.

## Exact v1 request bytes

| Opcode | Request | Response |
| --- | --- | --- |
| `0x01` | capabilities, 1 byte | 9 bytes: opcode, protocol `u32`, max chunk `u32` |
| `0x02` | begin, 17 bytes: opcode, version `u32`, width `u16`, height `u16`, length `u32`, CRC32 `u32` | 9 bytes, final byte status |
| `0x03` | chunk: opcode, offset `u32`, 1–256 payload bytes | 9 bytes, next offset `u32`, final byte status |
| `0x04` | end, 1 byte | 9 bytes, byte 5: `1=verified/staged`, `2=physically displayed`; final byte status |
| `0x05` | abort, 1 byte | 9 bytes, final byte status |
| `0x10` | OTA begin, opcode + signed image length `u32` | 9 bytes, final byte status |
| `0x11` | OTA chunk, opcode + offset `u32` + 1–256 bytes | 9 bytes, next offset `u32`, final byte status |
| `0x12` | OTA end, 1 byte | 9 bytes, final byte status; reboot follows on success |
| `0x13` | OTA abort, 1 byte | 9 bytes, final byte status |

The app's `FrameProtocol` serializer and mock endpoint use the same begin/chunk/end layout. Firmware does not yet have a native mobile transport with a persistent BLE session, so real image and OTA transfer are intentionally disabled in the app. The authenticated `PING`/JSON handshake is a provisioning check, outside the binary transfer protocol.
