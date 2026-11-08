// LUMAIRIE EE04 direct Wi-Fi hardware preview.
// The frame creates a per-device WPA2 hotspot; no home router/provisioning needed.
// Do not enable the physical ED2208 driver on unmatched display hardware.
#include <Arduino.h>
#include <WiFi.h>
#include <nvs_flash.h>
#include <string.h>
#include "identity.h"
#include "display.h"
#include "photo_transfer.h"

static constexpr uint8_t BUTTON_KEY0 = 2;  // Seeed EE04 active-low button
static constexpr uint32_t RESTART_HOLD_MS = 8000;
static FactoryIdentity identity = {};
static bool hotspot_ready = false;
static bool identity_ok = false;
static uint32_t pressed_since = 0;
static bool restart_consumed = false;

static void show(FrameState state) {
  display_state(state, identity_ok ? identity.ble_name : "CONFIGURATION ERROR",
                identity_ok ? identity.qr_uri : nullptr);
}

void setup() {
  Serial.begin(115200);
  pinMode(BUTTON_KEY0, INPUT_PULLUP);
  display_init();
  if (nvs_flash_init() != ESP_OK) {
    Serial.println("Cannot initialize NVS. No data erased.");
    show(FrameState::PROVISIONING_FAILED);
    return;
  }

  // Radio provides hardware entropy for the factory-generated pairing secret.
  WiFi.mode(WIFI_STA);
  if (!factory_identity_load(&identity)) {
    Serial.println("Factory identity invalid; refusing insecure hotspot.");
    show(FrameState::PROVISIONING_FAILED);
    return;
  }
  identity_ok = true;
  photo_transfer_begin(identity.ble_name, identity.qr_uri);

  // The same 48-character random secret is printed only in the physical QR.
  // Its first 20 hex characters are the per-device WPA2 password (80 bits).
  const char *secret = strstr(identity.qr_uri, "&secret=");
  if (!secret || strlen(secret + 8) < 20) {
    Serial.println("Pairing credential missing; hotspot disabled.");
    show(FrameState::PROVISIONING_FAILED);
    return;
  }
  char password[21] = {};
  memcpy(password, secret + 8, 20);
  char ssid[20] = {};
  snprintf(ssid, sizeof(ssid), "LUMAIRIE-%s", identity.ble_name + 8);

  WiFi.mode(WIFI_AP);
  const IPAddress local(192, 168, 4, 1);
  const IPAddress netmask(255, 255, 255, 0);
  hotspot_ready = WiFi.softAPConfig(local, local, netmask)
                  && WiFi.softAP(ssid, password, 1, 0, 1);
  memset(password, 0, sizeof(password));
  if (!hotspot_ready) {
    Serial.println("Failed to start password-protected frame hotspot.");
    show(FrameState::PROVISIONING_FAILED);
    return;
  }

  Serial.print("Frame Wi-Fi ready: ");
  Serial.println(ssid); // Never log the WPA2 password or the full pairing QR.
  Serial.print("Frame transfer IP: ");
  Serial.println(WiFi.softAPIP());
  show(FrameState::WAITING_FOR_SETUP); // Keep QR on screen for the first scan.
}

void loop() {
  if (!identity_ok || !hotspot_ready) {
    delay(100);
    return;
  }
  photo_transfer_poll(true); // AP is ready even if no phone is attached yet.

  // Optional recovery: hold KEY0 for 8 seconds to restart the hotspot.
  const uint32_t now = millis();
  const bool held = digitalRead(BUTTON_KEY0) == LOW;
  if (!held) {
    pressed_since = 0;
    restart_consumed = false;
  } else if (pressed_since == 0) {
    pressed_since = now;
  } else if (!restart_consumed && now - pressed_since >= RESTART_HOLD_MS) {
    restart_consumed = true;
    Serial.println("KEY0 long press: restarting without erasing credentials.");
    ESP.restart();
  }
  delay(20);
}
