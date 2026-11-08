import 'package:flutter_test/flutter_test.dart';
import 'package:lumairie/services/pairing.dart';

void main() {
  test('pairing QR requires a per-unit credential and named frame', () {
    final qr = PairingCredential.parse(
        'lumairie://pair?id=UNIT_0001&name=LUMAIRE-A1B2C3&user=unit&secret=0123456789abcdef0123456789abcdef0123456789abcdef');
    expect(qr.name, 'LUMAIRE-A1B2C3');
    expect(qr.secret.length, 48);
    expect(() => PairingCredential.parse('lumairie://pair?name=LUMAIRE-A1B2C3'),
        throwsFormatException);
    expect(() => PairingCredential.parse('https://example.com'),
        throwsFormatException);
  });
}
