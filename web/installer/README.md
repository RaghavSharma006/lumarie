# LUMAIRIE Setup Studio (browser demo)

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
- Accessible progress and error feedback, friendly mobile layout, and links
  back to release/source documentation.

**This demo is not a working browser flasher.** We are explicitly not offering
one-click flash installation yet because the firmware uploader has never been
tested on physical EE04 hardware and Web Serial selection cannot guarantee
the board is the exact XIAO ESP32-S3 Plus with 16MB flash. Flashing existing
factory hardware can erase settings. A production one-click installer needs
hardware identity/flash security checks, full factory backup and recovery
instructions, a verified image/manifest, and physical validation.

The ESP32-C3 test is separate from the EE04 ESP32-S3 download. It cannot
verify the exact development board or display wiring. No C3 image on this
page connects to the Android app, and none is offered for flashing. A real
C3 board has not been available to test the probe flow.

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
