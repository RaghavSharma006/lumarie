#pragma once
#include <stdint.h>

// Authenticated, LAN-only image-transfer endpoint.
// LUMAIRIE's original 0x01..0x05 frame packet semantics are preserved.
// The only new on-wire layer is TCP framing/HMAC over the already-paired QR
// secret. No external broker, MQTT, or hardcoded password is involved.
void photo_transfer_begin(const char *ble_name, const char *qr_uri);
void photo_transfer_poll(bool wifi_connected);
bool photo_transfer_has_photo();
