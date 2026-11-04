#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <esp_random.h>
#include <esp_heap_caps.h>
#include <mbedtls/md.h>
#include <string.h>
#include "photo_transfer.h"
#include "display.h"

namespace {
constexpr uint16_t kTcpPort = 39393;
constexpr uint16_t kDiscoveryPort = 38343;
constexpr uint32_t kRasterBytes = 800u * 480u / 2u;
constexpr size_t kMaxChunk = 256;
constexpr size_t kMaxPacket = kMaxChunk + 5;
WiFiServer server(kTcpPort);
WiFiUDP udp;
bool started = false;
bool photo_visible = false;
char name[15] = {};
char secret[129] = {};
uint8_t *stage = nullptr;
uint32_t next_offset = 0;
uint32_t expected_crc = 0;
uint16_t width = 0, height = 0;
bool receiving = false;

uint16_t le16(const uint8_t *x) {
  return static_cast<uint16_t>(x[0] | (uint16_t(x[1]) << 8));
}
uint32_t le32(const uint8_t *x) {
  return uint32_t(x[0]) | (uint32_t(x[1]) << 8) |
         (uint32_t(x[2]) << 16) | (uint32_t(x[3]) << 24);
}
void put32(uint8_t *p, uint32_t v) {
  for (int i = 0; i < 4; i++) p[i] = uint8_t(v >> (i * 8));
}
bool equal_ct(const uint8_t *a, const uint8_t *b, size_t n) {
  uint8_t different = 0;
  for (size_t i = 0; i < n; ++i) different |= a[i] ^ b[i];
  return different == 0;
}
bool mac(const uint8_t *message, size_t length, uint8_t out[32]) {
  const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (!info || !secret[0]) return false;
  return mbedtls_md_hmac(info, reinterpret_cast<const uint8_t *>(secret),
                         strlen(secret), message, length, out) == 0;
}
uint32_t crc32(const uint8_t *bytes, size_t length) {
  uint32_t crc = 0xffffffffu;
  for (size_t i = 0; i < length; ++i) {
    crc ^= bytes[i];
    for (int bit = 0; bit < 8; ++bit)
      crc = (crc & 1) ? (crc >> 1) ^ 0xedb88320u : crc >> 1;
  }
  return crc ^ 0xffffffffu;
}
bool read_fully(WiFiClient &client, uint8_t *out, size_t n,
                uint32_t timeout_ms = 20000) {
  const uint32_t started_at = millis();
  size_t done = 0;
  while (done < n && millis() - started_at < timeout_ms) {
    int available = client.available();
    if (available > 0) {
      int count = client.read(out + done, min(size_t(available), n - done));
      if (count > 0) done += size_t(count);
    } else if (!client.connected()) {
      return false;
    } else {
      delay(1);
    }
  }
  return done == n;
}
bool write_fully(WiFiClient &client, const uint8_t *data, size_t length) {
  size_t sent = 0;
  const uint32_t started_at = millis();
  while (sent < length && millis() - started_at < 20000) {
    size_t count = client.write(data + sent, length - sent);
    sent += count;
    if (!count) delay(1);
  }
  return sent == length;
}
void packet(const uint8_t *p, uint16_t n, uint8_t reply[9]) {
  memset(reply, 0, 9);
  if (!n) { reply[8] = 1; return; }
  reply[0] = p[0];
  bool ok = false;
  switch (p[0]) {
    case 0x01: {  // CAPABILITIES, original protocol v1
      if (n != 1) break;
      put32(reply + 1, 1);
      put32(reply + 5, kMaxChunk);
      ok = true;
      break;
    }
    case 0x02: {  // BEGIN
      if (n != 17) break;
      const uint32_t version = le32(p + 1);
      const uint16_t new_width = le16(p + 5);
      const uint16_t new_height = le16(p + 7);
      const uint32_t length = le32(p + 9);
      if (version != 1 || length != kRasterBytes ||
          !((new_width == 800 && new_height == 480) ||
            (new_width == 480 && new_height == 800))) break;
      if (!stage) stage = static_cast<uint8_t *>(
        heap_caps_malloc(kRasterBytes, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
      if (!stage) { Serial.println("Photo staging PSRAM unavailable"); break; }
      width = new_width;
      height = new_height;
      expected_crc = le32(p + 13);
      next_offset = 0;
      receiving = true;
      ok = true;
      break;
    }
    case 0x03: {  // CHUNK, ordered and idempotent for lost ACK
      if (!receiving || n < 6 || n > kMaxPacket || !stage) break;
      const uint32_t offset = le32(p + 1);
      const uint32_t count = n - 5;
      if (offset == next_offset && count <= kRasterBytes - next_offset) {
        memcpy(stage + next_offset, p + 5, count);
        next_offset += count;
        ok = true;
      } else if (offset < next_offset && count <= next_offset - offset &&
                 memcmp(stage + offset, p + 5, count) == 0) {
        ok = true;
      }
      put32(reply + 1, next_offset);
      break;
    }
    case 0x04: {  // END: no display until full CRC verified
      if (n != 1 || !receiving || !stage || next_offset != kRasterBytes) break;
      receiving = false;
      if (crc32(stage, kRasterBytes) != expected_crc) {
        Serial.println("Rejected photo: CRC32 mismatch");
        break;
      }
      // Seeed's real driver waits for BUSY/refresh completion. It blocks
      // until panel.update() returns; only then report DISPLAYED=2.
      if (!display_photo(stage, width, height)) break;
      photo_visible = true;
      reply[5] = 2;
      ok = true;
      break;
    }
    case 0x05: {  // ABORT
      if (n != 1) break;
      receiving = false;
      next_offset = 0;
      ok = true;
      break;
    }
    default: break;
  }
  // The final byte has the same status semantics as the original v1 handler.
  if (p[0] != 0x01) reply[8] = ok ? 0 : 1;
}
void discovery() {
  int length = udp.parsePacket();
  if (length <= 0) return;
  if (length != 12) { udp.flush(); return; }
  uint8_t request[12];
  if (udp.read(request, sizeof(request)) != sizeof(request) ||
      memcmp(request, "LMD1", 4) != 0) return;
  uint8_t response[62] = {};
  memcpy(response, "LMD2", 4);
  memcpy(response + 4, name, 14);
  IPAddress ip = WiFi.localIP();
  for (int i = 0; i < 4; ++i) response[18 + i] = ip[i];
  memcpy(response + 22, request + 4, 8);
  if (!mac(response, 30, response + 30)) return;
  udp.beginPacket(udp.remoteIP(), udp.remotePort());
  udp.write(response, sizeof(response));
  udp.endPacket();
}
void client_session(WiFiClient client) {
  client.setNoDelay(true);
  uint8_t welcome[20];
  memcpy(welcome, "LMF1", 4);
  esp_fill_random(welcome + 4, 16);
  if (!write_fully(client, welcome, sizeof(welcome))) { client.stop(); return; }
  uint8_t authentication[32], actual[32];
  uint8_t greeting[34];
  memcpy(greeting, welcome, 20);
  memcpy(greeting + 20, name, 14);
  if (!read_fully(client, authentication, 32) ||
      !mac(greeting, sizeof(greeting), actual) ||
      !equal_ct(authentication, actual, 32)) {
    Serial.println("Photo session rejected: authentication failed");
    client.stop(); return;
  }
  const uint8_t ok[2] = {'O', 'K'};
  if (!write_fully(client, ok, 2)) { client.stop(); return; }
  uint32_t expected_sequence = 1;
  for (;;) {
    uint8_t header[6];
    if (!read_fully(client, header, sizeof(header))) break;
    uint32_t sequence = le32(header);
    uint16_t length = le16(header + 4);
    if (sequence != expected_sequence || length < 1 || length > kMaxPacket) break;
    uint8_t body[kMaxPacket], received_mac[32], computed_mac[32];
    if (!read_fully(client, body, length) ||
        !read_fully(client, received_mac, sizeof(received_mac))) break;
    uint8_t signed_request[4 + 16 + 6 + kMaxPacket] = {};
    memcpy(signed_request, "REQ1", 4);
    memcpy(signed_request + 4, welcome + 4, 16);
    memcpy(signed_request + 20, header, 6);
    memcpy(signed_request + 26, body, length);
    if (!mac(signed_request, 26 + length, computed_mac) ||
        !equal_ct(computed_mac, received_mac, 32)) {
      Serial.println("Photo request rejected: invalid HMAC");
      break;
    }
    uint8_t response[9];
    packet(body, length, response);
    uint8_t signed_reply[4 + 16 + 4 + 9] = {};
    memcpy(signed_reply, "ACK1", 4);
    memcpy(signed_reply + 4, welcome + 4, 16);
    memcpy(signed_reply + 20, header, 4);
    memcpy(signed_reply + 24, response, 9);
    if (!mac(signed_reply, sizeof(signed_reply), computed_mac) ||
        !write_fully(client, header, 4) ||
        !write_fully(client, response, sizeof(response)) ||
        !write_fully(client, computed_mac, sizeof(computed_mac))) break;
    ++expected_sequence;
    if (body[0] == 0x04 || body[0] == 0x05) break;
    delay(0);
  }
  client.stop();
}
}  // namespace

void photo_transfer_begin(const char *ble_name, const char *qr_uri) {
  if (!ble_name || strlen(ble_name) != 14 || !qr_uri) return;
  const char *value = strstr(qr_uri, "&secret=");
  if (!value) return;
  value += 8;
  size_t len = strlen(value);
  if (len < 16 || len > 128 || strchr(value, '&')) return;
  memcpy(name, ble_name, 14);
  name[14] = 0;
  memcpy(secret, value, len);
  secret[len] = 0;
}
void photo_transfer_poll(bool wifi_connected) {
  if (!secret[0] || !wifi_connected) return;
  if (!started) {
    server.begin();
    udp.begin(kDiscoveryPort);
    started = true;
    Serial.println("Authenticated LAN photo server ready (TCP 39393, UDP 38343)");
  }
  discovery();
  WiFiClient client = server.available();
  if (client) client_session(client);
}
bool photo_transfer_has_photo() { return photo_visible; }
