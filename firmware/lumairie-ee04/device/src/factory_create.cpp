// First boot only: use Espressif's SRP6a generator, not a homegrown verifier.
#include <Arduino.h>
#include <nvs.h>
#include <esp_mac.h>
#include <esp_random.h>
#include <esp_srp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

bool factory_create_identity() {
  // Caller starts Wi-Fi first to ensure hardware RNG has RF entropy.
  uint8_t mac[6];
  if (esp_read_mac(mac, ESP_MAC_BT) != ESP_OK) return false;
  uint8_t randomness[24];
  esp_fill_random(randomness, sizeof(randomness));
  char secret[49];
  static const char hexdigits[] = "0123456789abcdef";
  for (size_t i = 0; i < sizeof(randomness); i++) {
    secret[2*i] = hexdigits[randomness[i] >> 4];
    secret[2*i+1] = hexdigits[randomness[i] & 0x0f];
  }
  secret[48] = 0;
  memset(randomness, 0, sizeof(randomness));
  char uri[225] = {};
  int count = snprintf(uri, sizeof(uri),
     "lumairie://pair?id=EE04_%02X%02X%02X&name=LUMAIRE-%02X%02X%02X&user=unit&secret=%s",
     mac[3], mac[4], mac[5], mac[3], mac[4], mac[5], secret);
  if (count <= 0 || count >= (int)sizeof(uri)) {
    memset(secret, 0, sizeof(secret)); return false;
  }
  char *salt = nullptr;
  char *verifier = nullptr;
  int verifier_length = 0;
  esp_err_t err = esp_srp_gen_salt_verifier("unit", 4, secret, 48,
                                &salt, 16, &verifier, &verifier_length);
  memset(secret, 0, sizeof(secret));
  if (err != ESP_OK || !salt || !verifier ||
      verifier_length < 128 || verifier_length > 512) {
    free(salt); free(verifier); return false;
  }
  nvs_handle_t h;
  err = nvs_open("factory", NVS_READWRITE, &h);
  if (err == ESP_OK) {
    err = nvs_set_str(h, "qr_uri", uri);
    if (err == ESP_OK) err = nvs_set_blob(h, "srp_salt", salt, 16);
    if (err == ESP_OK) err = nvs_set_blob(h, "srp_verifier", verifier, verifier_length);
    if (err == ESP_OK) err = nvs_commit(h);
    nvs_close(h);
  }
  memset(uri, 0, sizeof(uri));
  memset(salt, 0, 16);
  memset(verifier, 0, verifier_length);
  free(salt); free(verifier);
  return err == ESP_OK;
}
