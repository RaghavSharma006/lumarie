# LUMAIRIE Setup Studio

A lightweight, responsive standalone website for LUMAIRIE, designed to be
deployed alongside the company website (for example under an `/install`
route or an `install.` subdomain).

## What this first demo actually does

- Real GitHub Release v0.2.0-ee04-preview.2 Android APK direct download.
- Real full EE04 ESP32-S3 firmware-kit ZIP download.
- Chrome / Edge Web Serial device selection (HTTPS only); users are **not**
  asked to type COM numbers. Uses `navigator.serial.requestPort()` and
  `getInfo()`, but intentionally does **not** open the port, send commands,
  read flash or write firmware.
- ESP32-C3 USB board identification using Espressif esptool-js. The test opens
  the selected port, resets the board into its ROM bootloader, may upload a
  temporary RAM helper, and reads the chip family and flash size. It never
  invokes flash erase or write. The bundled library is Apache 2.0 licensed;
  see `vendor/esptool-js.LICENSE`.
- Optional ESP32-C3 developer flash: requires an identified C3 with at least
  8 MB flash, downloads a full flash backup, checks each bundled image with
  SHA-256, writes the ESP-IDF candidate images at their build offsets and
  reads them back to compare SHA-256. The user must explicitly acknowledge
  that this replaces existing firmware and confirm after the backup download.
- Accessible progress and error feedback, friendly mobile layout, and links
  back to release/source documentation.

The EE04 ESP32-S3 firmware kit above has no browser flasher because its board
has not been physically validated. The separate C3 flash flow is for a
developer candidate only and is not a production installer. It has not been
tested on physical C3 hardware. Keep the full-flash backup for recovery.

The ESP32-C3 test is separate from the EE04 ESP32-S3 download. It cannot
verify the exact development board or display wiring. The bundled C3 image
does not connect to the Android app: factory Security-2 pairing material is
absent, so the firmware keeps BLE disabled. The panel driver is mock-only and
all unverified GPIOs are disabled. Flashing it on a working frame will replace
the existing app with a build that cannot refresh the display. Its layout is
from `D:/startup/lumarie_gpt_sol6/firmware/build5/flasher_args.json`:
bootloader at 0x0, partition table at 0x8000, initial OTA data at 0xf000,
and app at 0x20000. It was compiled with ESP-IDF v5.5.6 for 8 MB flash.

## Deploy on Vercel (without touching the existing company website)

1. Sign in at https://vercel.com and click **Add New → Project**.
2. Import GitHub repository `RaghavSharma006/lumarie`.
3. Set **Root Directory** to `web/installer`.
4. Select **Framework Preset: Other**. The site is static HTML/CSS/JS;
   no install or build command is required. If Vercel requests a Build Command,
   turn on override and leave it blank.
5. Click **Deploy**. Use Vercel's generated HTTPS `*.vercel.app` domain.
6. Later, connect a dedicated domain such as `install.your-domain.example`
   if you own it. This does not require modifying the existing company
   website. Add a link from the company site's navigation when ready.

Do not route your existing company domain to this app unless you intend to
replace that website.

## Local preview

Open `index.html` in any browser to see the design. The USB demo only works
when served via HTTPS or `localhost`, using a desktop browser with Web Serial
support such as Chrome or Edge.

## QA before sharing

- The two download links resolve to the Android APK and EE04 firmware ZIP in
  the GitHub preview release.
- Chrome/Edge desktop: checking the checkbox enables USB selection; selecting
  a device produces a safe, non-flashing confirmation.
- Chrome/Edge without an attached board: no data is changed; the popup can be
  cancelled.
- Firefox/Safari/phone: show a browser-compatibility notice.
- Check the HTTPS lock and never allow the page to initiate unexpected USB
  writes. Do not claim physical BLE/Wi-Fi/display features are hardware-tested.

Source firmware: `firmware/lumairie-ee04/device/`.
Android app: `apps/mobile/`.
Release: https://github.com/RaghavSharma006/lumarie/releases/tag/v0.2.0-ee04-preview.2
