import 'package:flutter_test/flutter_test.dart';
import 'package:lumairie/services/pairing.dart';

void main() {
  test('direct frame hotspot SSID and WPA2 passphrase derive from physical QR', () {
    const qr = PairingCredential(
      'EE04_AB12CD',
      'LUMAIRE-AB12CD',
      'unit',
      '0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    expect(qr.hotspotSsid, 'LUMAIRIE-AB12CD');
    expect(qr.hotspotPassword, '0123456789abcdef0123');
    expect(qr.hotspotPassword.length, 20);
  });

  test('direct Wi-Fi refuses older, short pairing credentials', () {
    const legacy = PairingCredential(
      'UNIT_AB12CD', 'LUMAIRE-AB12CD', 'unit', '0123456789abcdef');
    expect(() => legacy.hotspotPassword, throwsFormatException);
  });
}
