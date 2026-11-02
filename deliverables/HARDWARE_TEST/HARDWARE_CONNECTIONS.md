# EL073TS1 prototype connection status

The supplier listing supplied by the user identifies **EL073TS1**, 7.3-inch Spectra 6, 800×480, six-color, SPI, with a typical full refresh of about 19 seconds. This establishes the intended panel identity and advertised interface only. It does **not** identify the driver PCB, controller, ESP32 model, GPIO wiring, power rails, signal voltage, BUSY polarity, initialization sequence, color code mapping, pixel transfer order or refresh/sleep commands.

`firmware/main/board_profile.h` records the panel identity and sets all display GPIOs to `-1`. The compiled firmware must continue to use the MOCK DISPLAY driver until the supplier provides the exact schematic and driver documentation. Do not connect the panel to arbitrary ESP32 pins or energize it from guessed voltages.

Ask the supplier for: complete module BOM; ESP32 part/flash/PSRAM; exact EL073TS1 panel revision and FPC pinout; driver/controller PCB part number and schematic; supply and logic voltage limits; GPIO-to-driver mapping including SPI, reset, BUSY and power switches; initialization and waveform source; six-color code mapping and nibble/row order; refresh completion rules; and display power-down/sleep sequence.

The separate `Lumairie_Firmware_Test_Kit.zip` and supplier schematic were not found in the workspace at the time of this build. Good Display GDEP073E01 information must not be substituted for this panel without supplier confirmation.
