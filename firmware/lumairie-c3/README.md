# ESP32-C3 mock-display candidate

This is the source for the four binaries in
`web/installer/firmware/esp32c3-mock/`. Built with ESP-IDF v5.5.6 for
ESP32-C3 and an 8 MB flash partition table. The web installer checks the
detected chip and capacity, downloads a full backup, writes these images,
and reads them back to verify the hashes.

Build: `idf.py set-target esp32c3 && idf.py build`. The image offsets are
`0x0` bootloader, `0x8000` partition table, `0xf000` initial OTA data,
and `0x20000` app. After rebuilding, update the binaries and SHA-256
values in `web/installer/c3-test.js` together.

This is **not** release firmware. The exact development board is unknown.
The EL073TS1 supplier listing lacks driver PCB pins, voltages and controller
commands; the display is therefore mock-only, with all panel GPIOs set to
`-1`. Factory Security-2 salt and verifier are absent, so the firmware
intentionally disables BLE; it cannot pair with the phone app. It has not
been tested on a physical C3. Do not use it as a product image.
