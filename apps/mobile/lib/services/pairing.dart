import 'dart:convert';
import 'package:esp_provisioning_wifi/esp_provisioning_wifi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PairingCredential {
  const PairingCredential(this.id, this.name, this.username, this.secret);
  final String id;
  final String name;
  final String username;
  final String secret;

  static PairingCredential parse(String data) {
    final uri = Uri.tryParse(data);
    if (uri == null || uri.scheme != 'lumairie' || uri.host != 'pair') {
      throw const FormatException('This is not a Lumairie pairing QR code');
    }
    final q = uri.queryParameters;
    final id = q['id'] ?? '';
    final name = q['name'] ?? '';
    final user = q['user'] ?? '';
    final secret = q['secret'] ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id) ||
        !RegExp(r'^LUMAIRE-[A-Fa-f0-9]{6}$').hasMatch(name) ||
        user.isEmpty ||
        user.length > 64 ||
        secret.length < 16 ||
        secret.length > 128) {
      throw const FormatException('Pairing QR code is incomplete');
    }
    return PairingCredential(id, name, user, secret);
  }
}

class PairingService {
  final _native = EspProvisioningService();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> pair(PairingCredential qr) async {
    final found = await _native.scanBleDevices('LUMAIRE-');
    if (!found.contains(qr.name)) {
      throw StateError(
          'Frame not advertising. Hold its pairing button and retry.');
    }
    final response = await _native.fetchCustomData(
      qr.name,
      qr.secret,
      endpoint: 'frame',
      payload: 'PING',
      security: EspSecurityScheme.security2,
      username: qr.username,
    );
    if (response == null || jsonDecode(response)['protocol'] != 1) {
      throw StateError('Frame identity or protocol could not be verified');
    }
    await _storage.write(
        key: 'frame_${qr.id}',
        value: jsonEncode({
          'id': qr.id,
          'name': qr.name,
          'user': qr.username,
          'secret': qr.secret,
        }));
  }

  Future<void> forget(String id) => _storage.delete(key: 'frame_$id');
}
