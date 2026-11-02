# Hardware and security boundary

## Required supplier details

Before enabling a physical display adapter, obtain the exact panel part number, controller and compatible driver-board schematic, power sequencing, logic and panel voltages, SPI timing, initialization commands, refresh waveform or vendor driver, BUSY polarity/timing, sleep instructions, orientation, color-index order and expected packed pixel order. None were in the starter bundle. The firmware's `mock_display_refresh()` intentionally returns `ESP_ERR_NOT_SUPPORTED` after verifying a complete frame.

The ESP32-C3 and 8 MB flash partition table are candidates. Confirm RAM, flash, power source, button wiring, wake-capable GPIO and display driver electronics on a prototype. Do not connect a bare E-Ink panel directly to ESP32 GPIO. Measure active advertising, transfer, refresh, idle and deep-sleep currents on the final board. No battery percentage is shown without a verified gauge/ADC circuit.

## Pairing and ownership

The firmware fails closed if factory `srp_salt` and `srp_verifier` NVS blobs or a verified active-low pairing GPIO are absent. It advertises for 120 seconds only after a three-second physical hold. Its protocomm BLE service uses Espressif Security 2 (SRP6a and AES-GCM). The mobile client scans a per-unit QR containing an identifier, advertised device name, username and high-entropy secret; after an authenticated endpoint response it stores that credential in Android encrypted preferences/Keystore or iOS Keychain. Firmware never logs credentials.

Production manufacturing must generate each unit's random secret and SRP salt/verifier using Espressif's vetted tooling, inject the verifier and salt into protected NVS, print the matching QR, and retain no plaintext secret in firmware or a central service. The NVS namespace is `factory`, keys `srp_salt` and `srp_verifier`. Exact NVS encryption/eFuse procedures depend on the chosen board and manufacturing process. A BLE name or MAC address alone is never the proof of possession.

This implementation does not enforce exclusive ownership or provide a safe ownership-transfer reset yet. A copied QR plus physical access can authenticate; a local-only device has no central authority to prove that another phone no longer holds a copy. Production reset must rotate the SRP credential and issue a new QR, with a hardware-confirmed long-hold sequence. Do not ship the current static credential lifecycle as an ownership guarantee.

## Power and update

Deep sleep ends BLE reachability. Firmware enters it only when a configured GPIO is valid for deep-sleep wake; otherwise it stays awake and logs the configuration error. A physical wake is required before pairing or transfer. The E-Ink image remains visible without power. A real display adapter must switch driver power off only after BUSY and refresh completion.

The firmware has 3 MB A/B OTA slots and a gated local update receiver. It rejects updates when signed-app verification/secure boot is not configured, validates image/version before changing the boot slot and uses ESP-IDF rollback support. The pending slot is accepted only after NVS, staging partition and factory security material initialize. Panel self-test, anti-rollback eFuse policy and signed update delivery from the mobile app remain to be completed and tested with actual hardware. Keep private signing keys outside the repository and application bundle.

Primary references: [Espressif protocomm Security 2](https://docs.espressif.com/projects/esp-idf/en/release-v5.5/esp32c3/api-reference/provisioning/protocomm.html), [ESP32-C3 sleep modes](https://docs.espressif.com/projects/esp-idf/en/release-v5.5/esp32c3/api-reference/system/sleep_modes.html), [ESP-IDF OTA and rollback](https://docs.espressif.com/projects/esp-idf/en/release-v5.5/esp32c3/api-reference/system/ota.html).
