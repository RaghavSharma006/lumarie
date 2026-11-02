# Software and hardware test record

| Check | Result |
| --- | --- |
| Existing Flutter source analysis and 26 tests | Passed in prior checkpoint; rerun after mobile source changes. |
| Android release ARM64 APK | Passed: `flutter build apk --release --split-per-abi`; 26,088,803-byte ARM64 APK. `apksigner verify` confirmed v2 signature and `aapt2` identified `io.lumarie.mobile`, version 0.1.0, min SDK 24. Signed with the Gradle development/debug key, not a production key. |
| ESP-IDF ESP32-C3 candidate compile | Not run. ESP-IDF source v5.5.6 was cloned, but the targeted tool installation was interrupted before completion. No firmware binary exists. |
| Real BLE provisioning and Wi-Fi station | Not verified. |
| Authenticated phone-to-ESP32 Wi-Fi image transfer | Not implemented in the current candidate. |
| Physical EL073TS1 display refresh | Not implemented; supplier electrical/driver documentation missing. |
| Buttonless standby and power draw | Not implemented or measured. |

No physical-hardware success is implied by software-only checks. Keep serial logs and measured current from prototype runs separate from this record.
