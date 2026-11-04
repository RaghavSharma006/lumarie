// LUMAIRIE EE04 combined firmware candidate: real panel + real Wi-Fi provisioning.
// No fake success acknowledgments; requires per-unit manufactured QR + SRP verifier.
#include <Arduino.h>
#include <nvs_flash.h>
#include "driver.h"
#include "identity.h"
#include "display.h"
#include "provisioning.h"

static constexpr uint8_t BUTTON_KEY0 = 2;  // Seeed EE04 active-low button
static constexpr uint32_t WIFI_RESET_HOLD_MS = 8000;
static constexpr uint32_t PANEL_REFRESH_GAP_MS = 5000;
static FactoryIdentity identity = {};
static FrameState displayed = FrameState::BOOTING;
static uint32_t refreshed_at = 0;
static uint32_t pressed_since = 0;
static bool reset_consumed = false;
static bool identity_ok = false;

static void show(FrameState state) {
  display_state(state,
    identity_ok ? identity.ble_name : "FACTORY CONFIGURATION REQUIRED",
    identity_ok ? identity.qr_uri : nullptr);
  displayed = state;
  refreshed_at = millis();
}
void setup() {
  Serial.begin(115200);
  pinMode(BUTTON_KEY0, INPUT_PULLUP);
  display_init();
  if (nvs_flash_init() != ESP_OK) {
    Serial.println("NVS cannot initialize; no implicit erase performed");
    show(FrameState::PROVISIONING_FAILED);
    return;
  }
  if (!factory_identity_load(&identity)) {
    Serial.println("Factory QR missing, invalid, or mismatched to BT MAC; BLE disabled");
    show(FrameState::PROVISIONING_FAILED);
    return;
  }
  identity_ok = true;
  show(FrameState::INITIALIZING);
  if (!provisioning_begin(identity.qr_uri, identity.ble_name)) {
    Serial.println("Security 2 provisioning initialization failed");
    show(FrameState::PROVISIONING_FAILED);
    return;
  }
  show(provisioning_state());
}
void loop() {
  if (!identity_ok) { delay(100); return; }
  provisioning_poll();
  const uint32_t now = millis();
  bool held = digitalRead(BUTTON_KEY0) == LOW;
  if (!held) { pressed_since = 0; reset_consumed = false; }
  else if (pressed_since == 0) pressed_since = now;
  else if (!reset_consumed && now - pressed_since >= WIFI_RESET_HOLD_MS) {
    reset_consumed = true;
    Serial.println("KEY0 long-press: forgetting Wi-Fi only; factory SRP retained");
    provisioning_reset_wifi();
  }
  FrameState next = provisioning_state();
  if (next != displayed && now - refreshed_at > PANEL_REFRESH_GAP_MS) show(next);
  delay(50);
}
