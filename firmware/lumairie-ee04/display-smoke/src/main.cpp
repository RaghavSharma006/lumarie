// Physical EE04 screen/QR diagnostic only: not the production BLE firmware.
// Uses Seeed's original Spectra 6 pipeline (Seeed_GFX, combo 509).
#include <Arduino.h>
#include <ctype.h>
#include <nvs.h>
#include <nvs_flash.h>
#include <qrcode.h>
#include "driver.h"
#include "TFT_eSPI.h"

static EPaper panel;
static constexpr int kWidth = 800;
static constexpr int kHeight = 480;
static constexpr int kQrVersion = 10;  // 57 modules; ECC_LOW capacity >200 bytes
static constexpr int kModulePx = 5;
static constexpr int kQuiet = 4;
static constexpr int kQrSize = (57 + 2 * kQuiet) * kModulePx;
static constexpr int kQrX = 42;
static constexpr int kQrY = (kHeight - kQrSize) / 2;
static constexpr int kKey0 = 2;  // Verified EE04 KEY0 (active low)
static char qrUri[225] = {0};

// Only a per-device, preprovisioned QR is displayed. It is NEVER fabricated.
// The app's PairingCredential.parse expects:
// lumairie://pair?id=...&name=LUMAIRE-XXXXXX&user=...&secret=...
static bool startsWith(const char *s, const char *prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0;
}
static bool validQr(const char *uri) {
    static constexpr char prefix[] = "lumairie://pair?id=";
    if (!startsWith(uri, prefix)) return false;
    const char *id = uri + sizeof(prefix) - 1;
    const char *nameField = strstr(id, "&name=LUMAIRE-");
    if (!nameField) return false;
    size_t idSize = (size_t)(nameField - id);
    if (idSize < 8 || idSize > 64) return false;
    for (size_t i = 0; i < idSize; ++i) {
        char ch = id[i];
        if (!(isalnum((unsigned char)ch) || ch == '_' || ch == '-')) return false;
    }
    const char *name = nameField + strlen("&name=LUMAIRE-");
    for (int n = 0; n < 6; ++n) {
        char c = name[n];
        if (!((c >= '0' && c <= '9') ||
              (c >= 'A' && c <= 'F') ||
              (c >= 'a' && c <= 'f'))) return false;
    }
    if (name[6] != '&') return false;
    const char *userTag = name + 6;
    if (strncmp(userTag, "&user=", 6) != 0) return false;
    const char *user = userTag + 6;
    const char *secretTag = strstr(user, "&secret=");
    if (!secretTag) return false;
    size_t userSize = (size_t)(secretTag - user);
    size_t secretSize = strlen(secretTag + strlen("&secret="));
    return userSize >= 1 && userSize <= 64 &&
           secretSize >= 16 && secretSize <= 128 &&
           strlen(uri) <= 200;
}
static bool loadFactoryQr() {
    nvs_handle_t nvs;
    if (nvs_open("factory", NVS_READONLY, &nvs) != ESP_OK) return false;
    size_t len = sizeof(qrUri);
    esp_err_t err = nvs_get_str(nvs, "qr_uri", qrUri, &len);
    nvs_close(nvs);
    return err == ESP_OK && validQr(qrUri);
}
static void line(const char *message, int x, int y, uint8_t scale) {
    panel.setTextColor(TFT_BLACK, TFT_WHITE, true);
    panel.setTextSize(scale);
    panel.drawString(message, x, y);
}
static void showMissingIdentity() {
    panel.fillScreen(TFT_WHITE);
    line("LUMAIRIE", 60, 70, 4);
    line("FACTORY CONFIGURATION REQUIRED", 60, 180, 2);
    line("NVS factory/qr_uri is missing or invalid.", 60, 240, 2);
    line("BLE pairing not available in this diagnostic.", 60, 290, 2);
    panel.update();
    panel.sleep();
}
static void showQr() {
    // QRCode by Richard Moore: data buffer size determined by QR version.
    uint8_t qrData[512] = {};  // Version 10 requires 407 bytes
    QRCode qr;
    qrcode_initText(&qr, qrData, kQrVersion, ECC_LOW, qrUri);
    panel.fillScreen(TFT_WHITE);
    // Four modules of white on each side are mandatory QR quiet zones.
    panel.fillRect(kQrX, kQrY, kQrSize, kQrSize, TFT_WHITE);
    for (int y = 0; y < qr.size; ++y) {
        for (int x = 0; x < qr.size; ++x) {
            if (qrcode_getModule(&qr, x, y)) {
                panel.fillRect(kQrX + (x + kQuiet) * kModulePx,
                               kQrY + (y + kQuiet) * kModulePx,
                               kModulePx, kModulePx, TFT_BLACK);
            }
        }
    }
    line("LUMAIRIE", 405, 75, 4);
    line("WELCOME", 405, 150, 2);
    line("Scan with the LUMAIRIE", 405, 207, 2);
    line("App to connect.", 405, 239, 2);
    line("Connect your device", 405, 295, 2);
    line("to Wi-Fi.", 405, 327, 2);
    const char *name = strstr(qrUri, "&name=") + strlen("&name=");
    char safeName[20] = {};
    const char *end = strchr(name, '&');
    size_t size = end ? (size_t)(end - name) : 0;
    if (size > 0 && size < sizeof(safeName)) {
        memcpy(safeName, name, size);
        line(safeName, 405, 395, 2);
    }
    panel.update();
    panel.sleep();
}
void setup() {
    Serial.begin(115200);
    pinMode(kKey0, INPUT_PULLUP);
    if (nvs_flash_init() != ESP_OK) {
        Serial.println("NVS unavailable; refusing to erase it");
        return;
    }
    Serial.println("Initializing EE04 Spectra 6 7.3 inch (ED2208)");
    panel.begin();
    if (panel.width() != kWidth || panel.height() != kHeight) {
        Serial.println("Panel dimensions unexpected; not drawing");
        return;
    }
    if (!loadFactoryQr()) {
        Serial.println("No valid factory QR URI; no secret printed");
        showMissingIdentity();
    } else {
        Serial.println("Factory QR available; displaying pairing screen");
        showQr();
    }
}
void loop() {
    // KEY0 may request redraw; it deliberately never wipes credentials.
    static bool previous = true;
    bool now = digitalRead(kKey0);
    if (previous && !now) {
        delay(40);
        if (!digitalRead(kKey0)) {
            panel.begin();
            if (loadFactoryQr()) showQr();
            else showMissingIdentity();
        }
    }
    previous = now;
    delay(40);
}
