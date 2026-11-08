"""Static, offline source-of-truth regression checks; not BLE or hardware tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]

class ProtocolContract(unittest.TestCase):
    def test_existing_app_qr_contract(self):
        app = (ROOT / "apps/mobile/lib/services/pairing.dart").read_text()
        self.assertIn("uri.scheme != 'lumairie'", app)
        self.assertIn("uri.host != 'pair'", app)
        for field in ["q['id']", "q['name']", "q['user']", "q['secret']"]:
            self.assertIn(field, app)
        self.assertIn("LUMAIRE-", app)

    def test_legacy_protocomm_preserved_in_older_firmware(self):
        firmware = (ROOT / "firmware/main/main.c").read_text()
        for token in ['"frame"', '"PING"', "protocomm_security2", "protocol"]:
            self.assertIn(token, firmware)

    def test_direct_wifi_does_not_require_ble_provisioning(self):
        pairing = (ROOT / "apps/mobile/lib/services/pairing.dart").read_text()
        transport = (ROOT / "apps/mobile/lib/services/frame_wifi_transport_io.dart").read_text()
        self.assertIn("rememberDirectFrame", pairing)
        self.assertIn("hotspotPassword", pairing)
        self.assertNotIn("EspSecurityScheme.security2", pairing)
        self.assertIn("Hmac(sha256", transport)
        self.assertIn("192.168.4.1", transport)

    def test_ee04_driver_selection(self):
        pio = (ROOT / "firmware/lumairie-ee04/display-smoke/platformio.ini").read_text()
        header = (ROOT / "firmware/lumairie-ee04/display-smoke/src/driver.h").read_text()
        self.assertIn("BOARD_SCREEN_COMBO=509", pio)
        self.assertIn("USE_XIAO_EPAPER_DISPLAY_BOARD_EE04", header)
        self.assertIn("BOARD_HAS_PSRAM", pio)

    def test_not_a_wifi_submission_app(self):
        app = (ROOT / "apps/mobile/lib/services/pairing.dart").read_text()
        self.assertNotIn(".sendWifiConfig(", app)
        self.assertNotIn(".applyWifiConfig(", app)

if __name__ == "__main__":
    unittest.main()
