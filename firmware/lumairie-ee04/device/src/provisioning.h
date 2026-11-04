#pragma once
#include <stdint.h>
enum class FrameState : uint8_t {
  BOOTING, INITIALIZING, WAITING_FOR_SETUP, BLE_CONNECTED,
  CONFIGURING_WIFI, CONNECTING_WIFI, WIFI_CONNECTED,
  PROVISIONING_FAILED, NORMAL_OPERATION
};
const char *frame_state_name(FrameState state);
bool provisioning_begin(const char *qr_uri, const char *ble_name);
void provisioning_poll();
void provisioning_reset_wifi(); // deliberately never clears factory QR or SRP materials
bool provisioning_is_connected();
FrameState provisioning_state();
