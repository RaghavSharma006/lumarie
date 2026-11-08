# Lumairie ESP32-C3 Link Studio

A private, static Vercel-hosted ESP32-C3 USB ROM detection / local `.bin` flasher / serial PING web app. Uses Espressif's esptool-js and Chrome/Edge Web Serial.

## Quick start
- Open the deployed HTTPS site in **desktop Chrome or Edge**.
- Plug ESP32-C3 via a USB **data** cable.
- Click **Connect ESP32** to identify the chip (no firmware flashing needed).
- To flash: select a *compiled* `.bin` for ESP32-C3 and choose the correct offset: `0x0` for an ESP-IDF merged image, or `0x10000` for an app-only image (requires compatible existing bootloader/partition-table).
- Click **Flash selected file**. The flash operation modifies the chip and should be used only with compatible firmware.
- After reset: **Open serial monitor** -> **Send PING**. Expect `PONG LUMAIRIE ESP32-C3...` only when the diagnostic firmware is running.

## Build
`npm install && npm run build` (Node 20+). Vercel detects Vite, build output `dist`.

## Privacy
No backend/APIs/analytics or uploads; all firmware bytes remain local in the browser. Browser port-picker requires a user click.

## Not included
This app does *not* compile `.c` source or ZIP archives into flashable `.bin` files. The earlier diagnostic ZIP is ESP-IDF source only; build with ESP-IDF to get a `.bin`. Do not use an app-only `.bin` at offset 0.