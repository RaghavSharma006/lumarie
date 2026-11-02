# Lumairie local builds

## Android

Install `android/Lumairie-debug.apk` on an Android device with `adb install -r android/Lumairie-debug.apk`, or open the APK on the device. This is a debug build for evaluation, not a signed store release. Demo Mode is the usable image-transfer simulation. Real-frame image transfer is deliberately disabled until a secure device transport and physical validation exist.

## Windows simulator

Extract `windows/Lumairie-Windows-Simulator.zip` to a folder. Double-click `START_WINDOWS.bat`. It starts a Node.js server bound to `127.0.0.1:8787` and opens `http://localhost:8787` in the default browser. Node.js must be installed. Keep the minimized server window running while using the simulator. The simulator uses the compiled Flutter app, stores photos only in the browser session, and connects to no hosted service. The right panel is visibly labeled **LOCAL SIMULATOR** and **Fake ESP32-C3**.

Choose a photograph, adjust crop/orientation, and press **Send to Living room**. The panel displays a six-color preview generated from the packed frame. Select **Drop ACK**, **Corrupt**, or **Interrupt** before another send to exercise retry or failed-transfer behavior. Disconnect Wi-Fi to simulate an unavailable frame. Failed transfers preserve the last displayed preview. These results do not validate a physical panel or power consumption.

To rerun source checks from `apps/mobile`: `flutter analyze --no-pub`, `flutter test --no-pub`, `flutter build web --release --no-pub`, and `flutter build apk --debug --no-pub`. Android builds on this host used JDK 21. The simulator end-to-end test in `simulator/e2e_test.js` requires `playwright-core`, Chrome, Node.js, a local server, and a real photograph at `LUMAIRIE_TEST_PHOTO` (or the Windows wallpaper fallback in the test source). Its fixed 1280×900 viewport checks a changed display after sending and pixel-identical retention after corrupt and interrupted transfers.
