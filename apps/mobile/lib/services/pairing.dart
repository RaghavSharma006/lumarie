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
          'Frame not advertising. Check that it is powered and ready for setup.');
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


  /// Provision Wi-Fi using the same factory Security 2 credential used to pair.
  ///
  /// This method intentionally does not change the onboarding UI. The existing
  /// workflow can call it once it has obtained the SSID/password from the user.
  /// A successful return is the native Espressif provisioning result, not a mock.
  Future<void> provisionStoredWifi(
    String deviceId,
    String ssid,
    String passphrase,
  ) async {
    final saved = await _storage.read(key: 'frame_$deviceId');
    if (saved == null) {
      throw StateError('Pair this LUMAIRIE frame before provisioning Wi-Fi.');
    }
    final utf8SsidBytes = utf8.encode(ssid);
    if (utf8SsidBytes.isEmpty || utf8SsidBytes.length > 32) {
      throw const FormatException('Wi-Fi SSID must contain 1–32 UTF-8 bytes.');
    }
    final isOpen = passphrase.isEmpty;
    final isWpaPassphrase = passphrase.length >= 8 && passphrase.length <= 63;
    final isHexPsk =
        RegExp(r'^[a-fA-F0-9]{64} => _storage.delete(key: 'frame_$id');
}
).hasMatch(passphrase);
    if (!(isOpen || isWpaPassphrase || isHexPsk)) {
      throw const FormatException('Invalid Wi-Fi passphrase length.');
    }
    final json = jsonDecode(saved) as Map<String, dynamic>;
    final name = json['name'] as String;
    final username = json['user'] as String;
    final secret = json['secret'] as String;
    final devices = await _native.scanBleDevices('LUMAIRE-');
    if (!devices.contains(name)) {
      throw StateError('Frame not advertising. Hold the frame reset button to re-enter setup.');
    }
    final ok = await _native.provisionWifi(
      name,
      secret,
      ssid,
      passphrase,
      security: EspSecurityScheme.security2,
      username: username,
    );
    if (!ok) throw StateError('Wi-Fi provisioning was not confirmed.');
  }

  Future<void> forget(String id) => _storage.delete(key: 'frame_$id');
}
