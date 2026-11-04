"""Offline source-contract checks. These are not BLE, Wi-Fi, or hardware tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
FW = ROOT / 'firmware/lumairie-ee04/device'
PAIR = ROOT / 'apps/mobile/lib/services/pairing.dart'
APP = ROOT / 'apps/mobile/lib/main.dart'

def source(path):
    return path.read_text(encoding='utf-8')

class EE04Contract(unittest.TestCase):
    def test_existing_qr_and_security(self):
        p, generation = source(PAIR), source(FW/'src/factory_create.cpp')
        self.assertIn("uri.scheme != 'lumairie'", p)
        self.assertIn("uri.host != 'pair'", p)
        for field in ("q['id']", "q['name']", "q['user']", "q['secret']"):
            self.assertIn(field, p)
        self.assertIn('lumairie://pair?id=', generation)
        self.assertIn('esp_fill_random', generation)
        self.assertIn('esp_srp_gen_salt_verifier', generation)

    def test_protected_frame_endpoint(self):
        p, fw = source(PAIR), source(FW/'src/provisioning.cpp')
        self.assertIn("EspSecurityScheme.security2", p)
        self.assertIn("NETWORK_PROV_SECURITY_2", fw)
        self.assertIn('network_prov_mgr_endpoint_create("frame")', fw)
        self.assertIn('memcmp(in, "PING", 4)', fw)
        self.assertIn('"{\\\"protocol\\\":1}"', fw)
        self.assertIn('0x2a,0x3f,0x17,0xc9', fw)

    def test_real_wifi_and_reset(self):
        f = source(FW/'src/provisioning.cpp')
        app = source(PAIR)
        ui = source(APP)
        self.assertIn('IP_EVENT_STA_GOT_IP', f)
        self.assertIn('WIFI_STORAGE_FLASH', f)
        self.assertIn('esp_wifi_restore()', f)
        self.assertNotIn('nvs_flash_erase', f)
        self.assertIn('_native.provisionWifi(', app)
        self.assertIn('provisionStoredWifi(', ui)

    def test_display_and_target(self):
        cfg = source(FW/'platformio.ini')
        screen = source(FW/'src/display.cpp')
        identity = source(FW/'src/identity.cpp')
        for text in ('seeed-xiao-esp32-s3-plus', 'BOARD_SCREEN_COMBO=509',
                     'USE_XIAO_EPAPER_DISPLAY_BOARD_EE04',
                     'default_16MB.csv'):
            self.assertIn(text, cfg)
        self.assertIn('QUIET = 4', screen)
        self.assertIn('TFT_BLACK', screen)
        self.assertIn('TFT_WHITE', screen)
        self.assertIn('esp_read_mac(mac,ESP_MAC_BT)', identity)

if __name__ == '__main__':
    unittest.main()
