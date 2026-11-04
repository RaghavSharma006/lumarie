#include <Arduino.h>
#include <WiFi.h>
#include <esp_event.h>
#include <esp_wifi.h>
#include <esp_mac.h>
#include <nvs_flash.h>
#include <nvs.h>
#include <network_provisioning/manager.h>
#include <network_provisioning/scheme_ble.h>
#include "provisioning.h"

// The UUID is inherited verbatim from firmware/main/main.c.
// Characteristic discovery follows the standard Espressif protocomm descriptors.
static uint8_t service_uuid[16] = {
  0x2a,0x3f,0x17,0xc9,0x72,0x85,0x40,0x42,
  0x8d,0x55,0x30,0x1a,0x40,0x61,0x19,0x10
};
static volatile FrameState state = FrameState::BOOTING;
static volatile bool connected = false;
static volatile bool failed = false;
static bool manager_ready = false;
static uint32_t connected_at = 0;
static uint32_t connection_start = 0;
static uint8_t *salt = nullptr;
static uint8_t *verifier = nullptr;
static network_prov_security2_params_t sec2 = {};

const char *frame_state_name(FrameState s) {
  switch (s) {
    case FrameState::BOOTING: return "BOOTING";
    case FrameState::INITIALIZING: return "INITIALIZING";
    case FrameState::WAITING_FOR_SETUP: return "WAITING FOR SETUP";
    case FrameState::BLE_CONNECTED: return "BLE CONNECTED";
    case FrameState::CONFIGURING_WIFI: return "CONFIGURING WI-FI";
    case FrameState::CONNECTING_WIFI: return "CONNECTING TO WI-FI";
    case FrameState::WIFI_CONNECTED: return "WI-FI CONNECTED";
    case FrameState::PROVISIONING_FAILED: return "CONNECTION FAILED";
    case FrameState::NORMAL_OPERATION: return "READY";
  }
  return "UNKNOWN";
}
FrameState provisioning_state() { return state; }
bool provisioning_is_connected() { return connected; }

static esp_err_t frame_endpoint(uint32_t session_id, const uint8_t *in,
                                ssize_t length, uint8_t **out,
                                ssize_t *out_length, void *context) {
  (void)session_id; (void)context;
  if (!in || !out || !out_length || length != 4 ||
      memcmp(in, "PING", 4) != 0) return ESP_ERR_INVALID_ARG;
  // Never simulate a BLE connection: this callback follows a successful
  // authenticated Security 2 protocomm session.
  constexpr char answer[] = "{\"protocol\":1}";
  *out = static_cast<uint8_t *>(malloc(sizeof(answer) - 1));
  if (!*out) return ESP_ERR_NO_MEM;
  memcpy(*out, answer, sizeof(answer) - 1);
  *out_length = sizeof(answer) - 1;
  state = FrameState::BLE_CONNECTED;
  return ESP_OK;
}
static bool load_srp() {
  nvs_handle_t handle;
  if (nvs_open("factory", NVS_READONLY, &handle) != ESP_OK) return false;
  size_t salt_length = 0, verifier_length = 0;
  bool ok = nvs_get_blob(handle, "srp_salt", nullptr, &salt_length) == ESP_OK &&
    nvs_get_blob(handle, "srp_verifier", nullptr, &verifier_length) == ESP_OK &&
    salt_length >= 16 && salt_length <= 64 &&
    verifier_length >= 128 && verifier_length <= 512;
  if (ok) {
    salt = static_cast<uint8_t *>(malloc(salt_length));
    verifier = static_cast<uint8_t *>(malloc(verifier_length));
    ok = salt && verifier &&
      nvs_get_blob(handle, "srp_salt", salt, &salt_length) == ESP_OK &&
      nvs_get_blob(handle, "srp_verifier", verifier, &verifier_length) == ESP_OK;
  }
  nvs_close(handle);
  if (!ok) { free(salt); free(verifier); salt = verifier = nullptr; return false; }
  sec2.salt = reinterpret_cast<const char *>(salt); sec2.salt_len = salt_length;
  sec2.verifier = reinterpret_cast<const char *>(verifier); sec2.verifier_len = verifier_length;
  return true;
}
static void event_handler(void *ctx, esp_event_base_t base, int32_t id, void *data) {
  (void)ctx; (void)data;
  if (base == NETWORK_PROV_EVENT) {
    switch (id) {
      case NETWORK_PROV_START: state = FrameState::WAITING_FOR_SETUP; break;
      case NETWORK_PROV_WIFI_CRED_RECV:
        // event_data holds the Wi-Fi password. Do not print or store it here.
        state = FrameState::CONFIGURING_WIFI; break;
      case NETWORK_PROV_WIFI_CRED_SUCCESS:
        // The manager may report success after DHCP. Do not regress the state.
        if (!connected) state = FrameState::CONNECTING_WIFI;
        break;
      case NETWORK_PROV_WIFI_CRED_FAIL:
        failed = true; state = FrameState::PROVISIONING_FAILED; break;
      default: break;
    }
  } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
    connected = true; failed = false; connected_at = millis();
    state = FrameState::WIFI_CONNECTED;
  } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
    connected = false;
    if (!failed) state = FrameState::CONNECTING_WIFI;
  }
}
bool provisioning_begin(const char *qr_uri, const char *ble_name) {
  if (!qr_uri || !ble_name || !load_srp()) return false;
  // The QR name must be exactly the BLE MAC name from the existing firmware.
  uint8_t mac[6];
  if (esp_read_mac(mac, ESP_MAC_BT) != ESP_OK) return false;
  char actual_name[20] = {};
  snprintf(actual_name, sizeof(actual_name), "LUMAIRE-%02X%02X%02X",
           mac[3], mac[4], mac[5]);
  if (strcmp(actual_name, ble_name) != 0) {
    Serial.println("NVS pairing name does not match BLE MAC");
    return false;
  }

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  esp_wifi_set_storage(WIFI_STORAGE_FLASH);
  esp_event_handler_register(NETWORK_PROV_EVENT, ESP_EVENT_ANY_ID, event_handler, nullptr);
  esp_event_handler_register(WIFI_EVENT, WIFI_EVENT_STA_DISCONNECTED, event_handler, nullptr);
  esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, event_handler, nullptr);
  wifi_config_t saved = {};
  if (esp_wifi_get_config(WIFI_IF_STA, &saved) == ESP_OK && saved.sta.ssid[0]) {
    state = FrameState::CONNECTING_WIFI;
    connection_start = millis();
    WiFi.begin(); // ESP-IDF NVS settings; never log the password
    return true;
  }

  network_prov_mgr_config_t config = {};
  config.scheme = network_prov_scheme_ble;
  network_prov_event_handler_t handler = NETWORK_PROV_EVENT_HANDLER_NONE;
  config.scheme_event_handler = handler;
  if (network_prov_mgr_init(config) != ESP_OK) return false;
  manager_ready = true;
  if (network_prov_mgr_endpoint_create("frame") != ESP_OK) return false;
  network_prov_scheme_ble_set_service_uuid(service_uuid);
  // sec2 is static, not a temporary local struct; the verifier stays live.
  if (network_prov_mgr_start_provisioning(NETWORK_PROV_SECURITY_2, &sec2,
                                          ble_name, nullptr) != ESP_OK) return false;
  if (network_prov_mgr_endpoint_register("frame", frame_endpoint, nullptr) != ESP_OK) {
    network_prov_mgr_stop_provisioning();
    return false;
  }
  state = FrameState::WAITING_FOR_SETUP;
  return true;
}
void provisioning_poll() {
  if (connected && state == FrameState::WIFI_CONNECTED &&
      millis() - connected_at > 20000) state = FrameState::NORMAL_OPERATION;
  if (!connected && !manager_ready && state == FrameState::CONNECTING_WIFI &&
      millis() - connection_start > 45000) state = FrameState::PROVISIONING_FAILED;
  if (failed && manager_ready) {
    // Restore the manager state machine so the phone can retry.
    if (network_prov_mgr_reset_wifi_sm_state_on_failure() == ESP_OK) failed = false;
  }
}
void provisioning_reset_wifi() {
  // Only after intentional eight-second KEY0 hold. Do not erase the
  // whole flash, NVS partition, or Security 2 manufacturing material.
  if (manager_ready) {
    network_prov_mgr_stop_provisioning();
    network_prov_mgr_deinit();
    manager_ready = false;
  }
  esp_wifi_restore();
  ESP.restart();
}
