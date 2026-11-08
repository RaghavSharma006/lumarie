"""Offline source contract checks, NOT proof of physical Wi-Fi or ePaper refresh."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
FW = ROOT / "firmware/lumairie-ee04/device"
APP = ROOT / "apps/mobile/lib/main.dart"
PAIR = ROOT / "apps/mobile/lib/services/pairing.dart"
KOTLIN = ROOT / "apps/mobile/android/app/src/main/kotlin/com/example/lumairie/MainActivity.kt"
TRANSPORT = ROOT / "apps/mobile/lib/services/frame_wifi_transport_io.dart"

def source(path):
    return path.read_text(encoding="utf-8")

class EE04DirectWifiContract(unittest.TestCase):
    def test_factory_identity_still_random_and_persistent(self):
        factory = source(FW / "src/factory_create.cpp")
        pairing = source(PAIR)
        self.assertIn("esp_fill_random", factory)
        self.assertIn("esp_srp_gen_salt_verifier", factory)
        self.assertIn("factory/qr_uri", source(ROOT / "firmware/lumairie-ee04/README.md"))
        self.assertIn("rememberDirectFrame(", pairing)
        self.assertIn("hotspotPassword", pairing)
        self.assertIn("String get hotspotSsid", pairing)

    def test_ap_uses_random_secret_not_shared_factory_password(self):
        main = source(FW / "src/main.cpp")
        self.assertIn("WiFi.softAPConfig(", main)
        self.assertIn("WiFi.softAP(ssid, password", main)
        self.assertIn('strstr(identity.qr_uri, "&secret=")', main)
        self.assertIn('memcpy(password, secret + 8, 20)', main)
        self.assertIn("192, 168, 4, 1", main)
        self.assertNotIn("provisioning_begin(", main)
        self.assertNotIn("Serial.println(password)", main)

    def test_discovery_uses_ap_interface(self):
        server = source(FW / "src/photo_transfer.cpp")
        self.assertIn("WiFi.softAPIP()", server)
        self.assertIn("Authenticated LAN photo server ready", server)
        self.assertIn("crc32(stage, kRasterBytes)", server)
        self.assertIn("equal_ct(authentication, actual, 32)", server)

    def test_direct_android_network_approval_and_release(self):
        kotlin = source(KOTLIN)
        app = source(APP)
        transport = source(TRANSPORT)
        self.assertIn("WifiNetworkSpecifier.Builder()", kotlin)
        self.assertIn("requestNetwork(request, newCallback", kotlin)
        self.assertIn("bindProcessToNetwork(network)", kotlin)
        self.assertIn("bindProcessToNetwork(null)", kotlin)
        self.assertIn("await hotspot.disconnect();", app)
        self.assertIn("FrameWifiTransport(directHotspot: true)", app)
        self.assertIn("InternetAddress('192.168.4.1')", transport)

    def test_display_target_unchanged(self):
        cfg = source(FW / "platformio.ini")
        self.assertIn("seeed-xiao-esp32-s3-plus", cfg)
        self.assertIn("BOARD_SCREEN_COMBO=509", cfg)
        self.assertIn("USE_XIAO_EPAPER_DISPLAY_BOARD_EE04", cfg)
        self.assertIn("default_16MB.csv", cfg)

if __name__ == "__main__":
    unittest.main()
