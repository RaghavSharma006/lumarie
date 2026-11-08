#include <Arduino.h>
#include <qrcode.h>
#include "driver.h"
#include "TFT_eSPI.h"
#include "display.h"

static EPaper panel;
static bool ready = false;
static constexpr int QR_VERSION = 10; // 57 modules; low ECC, <=200 byte URI
static constexpr int MODULE = 5;
static constexpr int QUIET = 4;

static void label(const char *s, int x, int y, int size) {
  panel.setTextColor(TFT_BLACK, TFT_WHITE, true);
  panel.setTextSize(size);
  panel.drawString(s, x, y);
}
void display_init() {
  panel.begin();
  ready = panel.width() == 800 && panel.height() == 480;
  if (!ready) Serial.println("Unexpected EE04 resolution; display disabled");
}
static void draw_qr(const char *uri) {
  if (!uri || strlen(uri) > 200) return;
  uint8_t data[512] = {}; // QRCode version 10 requires 407 bytes
  QRCode qr;
  qrcode_initText(&qr, data, QR_VERSION, ECC_LOW, uri);
  for (int y = 0; y < qr.size; y++)
    for (int x = 0; x < qr.size; x++)
      if (qrcode_getModule(&qr, x, y))
        panel.fillRect(30 + (x + QUIET) * MODULE, 77 + (y + QUIET) * MODULE,
                       MODULE, MODULE, TFT_BLACK);
}
void display_state(FrameState state, const char *name, const char *uri) {
  if (!ready) return;
  panel.begin();
  panel.fillScreen(TFT_WHITE);
  label("LUMAIRIE", 30, 17, 4);
  panel.drawLine(30, 62, 770, 62, TFT_BLACK);
  bool setup = state == FrameState::WAITING_FOR_SETUP ||
               state == FrameState::BLE_CONNECTED ||
               state == FrameState::CONFIGURING_WIFI ||
               state == FrameState::CONNECTING_WIFI ||
               state == FrameState::PROVISIONING_FAILED;
  if (setup && uri && uri[0]) {
    draw_qr(uri); // Four-module white quiet zone surrounding black modules.
    label("WELCOME", 410, 93, 2);
    label("Scan with the LUMAIRIE", 410, 152, 2);
    label("App to connect.", 410, 185, 2);
    label("Frame makes its own", 410, 246, 2);
    label("private Wi-Fi.", 410, 280, 2);
    label(name, 410, 357, 2);
  } else {
    label(state == FrameState::WIFI_CONNECTED ||
          state == FrameState::NORMAL_OPERATION ? "CONNECTED" : "INITIALIZING",
          75, 155, 4);
    label(name, 75, 241, 2);
  }
  label(state == FrameState::WAITING_FOR_SETUP ? "FRAME WI-FI READY" : frame_state_name(state), 30, 427, 2);
  panel.update();
  panel.sleep();
}


bool display_photo(const uint8_t *pixels, uint16_t width, uint16_t height) {
  if (!ready || !pixels ||
      !((width == 800 && height == 480) ||
        (width == 480 && height == 800))) return false;

  // Input indices are LUMAIRIE app's established six-color nibble format.
  // Seeed_GFX's ED2208 driver supports these exact six TFT_* colors.
  static const uint16_t palette[6] = {
    TFT_WHITE, TFT_BLACK, TFT_RED, TFT_YELLOW, TFT_BLUE, TFT_GREEN
  };
  // Full ePaper refresh is allowed ONLY after the caller validates length
  // and CRC32 of the complete staging frame.
  panel.begin();
  panel.setRotation(0);
  for (uint32_t y = 0; y < height; ++y) {
    for (uint32_t x = 0; x < width; ++x) {
      const uint32_t index = y * width + x;
      const uint8_t packed = pixels[index >> 1];
      const uint8_t color = (index & 1) ? packed & 0x0f : packed >> 4;
      if (color > 5) {
        // Reject unsupported palette indices: never start hardware refresh.
        return false;
      }
      if (width == 800) {
        panel.drawPixel(x, y, palette[color]);
      } else {
        // Portrait 480x800 stream -> physical landscape 800x480 raster.
        panel.drawPixel(y, 479 - x, palette[color]);
      }
    }
    if ((y & 15) == 0) yield();
  }
  // Seeed_GFX update() waits for BUSY, then enters panel sleep.
  panel.update();
  panel.sleep();
  return true;
}
