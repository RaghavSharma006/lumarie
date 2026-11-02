# GPT Sol 6 — Build Lumairie Mobile App + ESP32 Firmware

You are the lead mobile engineer, embedded firmware engineer, security engineer, and UI implementation specialist for Lumairie (domain: lumarie.io), a consumer product that displays artwork and photos on 7.3-inch E Ink Spectra 6 frames. **Your task is to IMPLEMENT a real working project, not merely write a plan or demonstrate static screens.** Inspect the repository first, reuse sensible existing code, then work incrementally. If the repository is empty, scaffold it. Keep the app buildable and provide clear run commands and test results after each milestone. Do not repeatedly ask for decisions that can be handled with documented, reversible defaults.

## Absolute product requirements

- **Zero cloud dependence:** NO backend, Supabase, Firebase, hosted API, login, online accounts, remote servers, telemetry, or cloud photo storage. Device state, photos, previews, cropping, color quantization, layouts, and credentials reside on the phone. The phone communicates directly with the ESP32. The app can run with no internet access.
- **Mobile platforms:** Flutter/Dart, Android and iOS from one codebase. Use native platform integration where required for BLE and local network permissions. Do not make a web-only app or a React web mockup.
- **Firmware:** ESP-IDF, C/C++, start with ESP32-C3 as a cost-optimized *candidate*, not a guaranteed final choice. Structure board/panel-specific modules to allow switching to another ESP32 if necessary. The hardware is a 7.3-inch Spectra 6 E-Ink display, expected around 800x480, six pigments/colors (black, white, red, yellow, blue, green). **Exact panel/controller/driver board/pinout must be verified against the Alibaba supplier's part number and datasheet. Do NOT invent pins, initialization commands, LUTs, timing, voltage requirements, or claim a real display is supported without verification.** Build a mock display adapter so app/transport development continues before hardware confirmation.
- **Cost and simplicity:** Do all image composition, processing and dithering on the phone. Send a compact panel-ready pixel stream to ESP32, which only receives/verifies data, drives the SPI interface, refreshes the display, and manages power. Do not require PSRAM or a full image framebuffer unless tests show it is necessary. E-paper displays require compatible driver/power electronics; do not wire bare panel pins directly to random MCU pins.
- **No mandatory Wi-Fi / IP for first pairing:** QR -> authenticated BLE provisioning; BLE works without IP. Optional local Wi-Fi image transfer later: phone supplies SSID/password securely over BLE, ESP32 gets a DHCP address, advertises mDNS, phone discovers it and authenticates. No static IP, router, or internet requirement for BLE-only operation.

## Source-of-truth visuals (MANDATORY)

Two screenshots are supplied as files:
- `design/references/dark.webp` (dark theme UI collage)
- `design/references/light.webp` (light theme UI collage)

**Analyze both screenshots closely before writing widgets.** Reproduce the actual visual system faithfully; do not substitute a generic Material UI design. Match, as closely as practical: warm near-black/espresso backgrounds and warm off-white/cream backgrounds; dark brown or ivory primary buttons; compact elegant typography and tiny uppercase wordmark; subtle separators; 12–16px-ish rounded content panels; photo frames with realistic mat/border treatment; small pill toggles and filters; selected states; narrow outlined dashed add-buttons; thumbnail grid; compact bottom navigation with an enclosing pill and selected inner pill; thin icons; screen-specific spacing and alignment. Both themes must follow the supplied screenshots. Match screen hierarchy and relative sizing, not merely color. Create responsive layouts for Android/iPhone, handle safe areas and small screens. The reference shows the wordmark `LUMAIRE`; use the visual wordmark from the screenshots and centralize branding strings to easily change later. Do not embed random brand fonts or unauthorized photo assets.

Implement and visually verify these eight reference screens in BOTH themes:
1. **Home:** branded header, featured Hub card, two frame cards (Living room, Hallway), connected/offline indicators, outlined `Add device`, bottom Home/Hub/Profile navigation.
2. **Frame detail / Gallery:** title Living room with device size, Now showing Gallery card, 3-column thumbnails, outlined Add photos tile, bottom Preview action.
3. **Photo Preview:** image inside physical-frame mockup; Sending to title, Portrait/Landscape chips, Fit/Fill controls, advisory text, strong Send to frame button, Choose another photo.
4. **Hub dashboard:** framed widget composite preview, Day/Week/Focus mode chips, toggles for Calendar/Weather/To-do, outlined Add widget button, same bottom navigation style. Offline-local functionality only; no live data unless locally sourced and transparently labeled.
5. **Profile / Settings:** match reference layout, but DO NOT create fake account or email. Replace account-specific text with Local Settings / This phone, local device settings, privacy and support; use visually equivalent cards/rows.
6. **Connecting / Add device:** back arrow, concentric device illustration, real states Frame found / Joining Wi-Fi (optional) / Syncing your display, Cancel button, errors and retry states. BLE-only pairing must skip Wi-Fi step appropriately.
7. **Add widget:** All / Time / Home / Notes filter chips, 2-column cards for Calendar, Weather, Clock, To-do, Notes, Photo of the day, Countdown, Home status. Clearly indicate local-only capabilities; no deceptive live cloud widgets.
8. **Second frame preview:** Hallway with landscape example, same visual language and correct orientation switch.

Build a reusable design system (colors, spacings, typography, card surface, pill controls, nav bar, image frame components). Use light and dark golden/screenshot tests where feasible. If sample photographs are unavailable, use local placeholder/illustrative assets and allow using the device gallery; NEVER treat copyrighted sample pictures in screenshots as bundled assets by default.

## Scope — IMPLEMENT NOW (required)

**A. Secure device ownership / pairing**
- A factory-provisioned unique device identifier, per-unit QR credential or proof of possession (PoP), and a physical pairing window (button hold / hardware trigger). QR must not merely expose a static unprotected BLE MAC address.
- Use vetted ESP-IDF secure BLE provisioning mechanisms or a well-reviewed authenticated key exchange, authenticated encrypted transfer, secure local credential storage using Android Keystore and iOS Keychain. Do not invent cryptographic algorithms. Do not record PoP, Wi-Fi passwords, or keys in logs.
- Pair without an IP address, locally record the paired device, enforce authorization of later sessions, and support a physically initiated factory reset / ownership transfer. Explain limitations of proving exclusive ownership without a central server.
- Show clear pairing error/retry states in the UI. iOS/Android permissions and BLE handling must be correct.

**B. Interrupted transfer protection**
- A versioned binary protocol for panel descriptor/capabilities, begin-transfer, metadata (dimensions, orientation, format, length), chunks with offsets/sequence numbers, acknowledgements/flow control, timeout/retry, end-transfer and integrity check (e.g. CRC32 for accidental corruption plus authenticated channel; optionally SHA-256), refresh/complete status. Do not equate checksum with authentication.
- No partial refresh. If BLE disconnects or payload is corrupt, preserve the last *visible* E-Ink picture. Restart or resume transfers only when provably safe for the chosen driver/storage design; otherwise cleanly restart. Bound allocations and reject bad input.
- Include mock-device integration tests that intentionally drop/corrupt/reorder chunks, and prove the failure path never triggers a panel refresh.

**C. Low-power management**
- Minimal wake -> advertise/receive -> draw/refresh -> power down display-driving circuitry safely -> deep sleep cycle. Investigate whether button press, periodic wake, or BLE advertising schedule makes sense for the physical board. Deep sleeping ESP32 does NOT maintain permanent BLE or Wi-Fi reachability; reflect that accurately in the app.
- Include power states (Awake, Advertising, Transferring, Refreshing, Sleeping, Error), a configurable but safe wake strategy, wake-button requirements, and timeouts. Do not promise a continuously connected battery frame.
- Add battery status only if board-level battery gauge/ADC and power source are actually available. Clearly document power/current measurements required on the prototype.

**D. Offline firmware updates**
- Firmware binary delivered from a bundled app asset or locally selected signed update file; no cloud OTA endpoint. The app should show firmware version, update progress, failures and recovery instructions.
- Use verified firmware signatures / ESP-IDF secure boot strategy, appropriate OTA A/B partitions and rollback where supported by flash size. Validate update and boot before marking success. Prefer local Wi-Fi for larger binary transfer if provisioned, BLE fallback if performance allows. Do not claim BLE OTA is instantaneous.
- No firmware downgrade unless explicitly permitted by versioning/anti-rollback policy; no hardcoded private signing keys in the app or repo.

**E. Core app and content workflow**
- Local device registry and photo library references/app-private cached assets, local persistence for preferences/layouts, device discovery and accurate statuses.
- Pick photos from phone, crop/rotate, portrait/landscape, Fit/Fill, generate a Spectra 6 palette preview, quantize/dither on-device and serialize a panel-ready frame buffer. For an 800x480 six-color target, the initial candidate is a documented 4-bit/pixel packed layout (192,000 bytes), but adapt packing/color index order to the VERIFIED panel driver and preserve swappable codecs. Favor predictable memory and performance over premature complex optimization.
- Send image directly over secure BLE, with optional direct local Wi-Fi transport abstraction. Include progress and delivered vs actually displayed confirmation.
- Light and dark theme. Full navigation and useful local sample data in a clearly identified Demo Mode; production UI must use real local state and must not pretend a mock frame is connected.

## Explicitly LATER (architect for but do NOT build now)
- Spectra 6 advanced color calibration: physical color characterization, multiple selectable dithering presets, brightness/contrast/saturation tuning and panel-specific calibration profiles. For V1 provide a reliable basic six-color quantizer/dither and correct palette mapping; do not spend early effort on a sophisticated calibration suite.
- Do NOT implement: encrypted export/phone-replacement backup, guaranteed time-based photo scheduling, manufacturing diagnostic suite, cloud login/backend, remote access, Google account integrations, or always-on online widgets. The visual UI may show local/demo widgets, but never misrepresent a simulated weather source as live.

## Recommended implementation layout

```
lumarie/
  apps/mobile/                 # Flutter + Dart Android/iOS
    lib/design_system/
    lib/features/home/
    lib/features/devices/
    lib/features/gallery/
    lib/features/preview/
    lib/features/pairing/
    lib/features/hub/
    lib/features/settings/
    lib/services/              # local storage, image processing, BLE/Wi-Fi, OTA
    test/
    integration_test/
  firmware/                    # ESP-IDF (C/C++)
    main/
    components/ble_protocol/
    components/device_security/
    components/image_transport/
    components/spectra6/
    components/power_manager/
    components/local_ota/
    boards/
  shared/protocol/             # versions, canonical payload schemas, fixtures
  design/references/dark.webp
  design/references/light.webp
  docs/                        # architecture, protocol, hardware dependencies, test logs
```

You may adjust folder layout if you can justify a clearly better structure. Avoid unnecessary frameworks and dependencies. Keep one authoritative protocol definition for both app and firmware, and test protocol compatibility. Use Flutter platform channels for native BLE/provisioning integrations if direct Flutter libraries do not support secure provisioning adequately. Local Wi-Fi communication, when enabled, needs authenticated encryption too. mDNS is discovery, not authentication.

## Execution order (WRITE CODE)

1. **Inspect repo and reference images.** Summarize current files, toolchain availability, panel unknowns and concrete plan in a short `docs/STATUS.md`. Begin work immediately.
2. **Flutter foundation and exact design.** Implement reusable tokens/components and all eight routes with responsive dark/light theme. Make navigation, photo picking, preview controls, toggles and demo mode actually work. Run formatter, analyzer, tests and capture screenshots/golden tests where available. Compare visuals to both supplied references and iteratively correct discrepancies.
3. **On-device image pipeline.** Define versioned panel profile and image codec. Implement crop, resize, six-color quantization/initial dithering and packed binary output with deterministic fixture tests; verify size, orientation, pixel order and endianness against the panel reference code when obtained.
4. **BLE/QR protocol and mock frame.** Build QR scanning, secure pairing structure, transport abstraction, state machine, encrypted device storage and mock ESP32 simulator. Demonstrate end-to-end send and interruption recovery even if hardware is not yet connected. Separate mock behavior behind explicit demo flags.
5. **Real ESP-IDF firmware.** Implement buildable ESP32-C3 project, event-driven BLE transport, authentication/provisioning, chunk validation, display adapter interface, power states. Implement real Spectra 6 driver ONLY after verifying exact supplier controller, driver board, pins, electrical spec and full initialization example. Otherwise provide a safe mock display driver, mark the missing board details clearly, and avoid imaginary hardware success.
6. **Offline OTA.** Implement firmware OTA partition and signature verification design, local package selection/transport and failure handling. Validate if device flash/secure boot configuration supports A/B rollback.
7. **Verification and handoff.** Report exact build commands, actual tests executed and outputs, screenshots, unimplemented hardware prerequisites, and a short prioritized next-steps list. Do not claim compilation or physical hardware testing unless actually performed.

## Definition of done

- Flutter project launches on supported Android/iOS environments, with light and dark visual designs demonstrably based on the supplied images.
- Eight reference screens are implemented with working navigation and relevant interactive controls.
- Entire app works without cloud, server or internet; demo mode works without the physical frame.
- QR/BLE pairing path is implemented, authentication design is vetted, and local credentials are securely stored.
- A selected photo can become a deterministic, six-color packed frame and be transferred through the protocol to the simulator; frame acknowledgment is not confused with actual display completion.
- Corrupted or aborted transfers never cause a refresh.
- ESP-IDF firmware and secure OTA path are built to the extent possible with the available hardware documentation; all remaining unknowns are explicit.
- Power/sleep behavior is realistic and avoids hidden always-on assumptions.
- No placeholder cloud account, fake login, or unrequested backend is introduced.

Be autonomous and implementation-first. Never stop after presenting an architecture diagram when code can be written. At each stage, give a concise status of what was changed, what was tested, and what genuinely remains blocked by hardware or platform requirements. Prioritize the visual fidelity of the two references and the working phone-to-frame vertical slice.
