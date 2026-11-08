import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credential printed on each physical frame. Scanning is not authentication;
/// the authenticated photo socket verifies possession of the secret.
class PairingCredential {
  const PairingCredential(this.id, this.name, this.username, this.secret);

  final String id;
  final String name;
  final String username;
  final String secret;

  String get hotspotSsid => 'LUMAIRIE-${name.substring(8)}';

  String get hotspotPassword {
    if (!RegExp(r'^[a-fA-F0-9]{48}$').hasMatch(secret)) {
      throw const FormatException('Frame QR is incompatible with direct Wi-Fi');
    }
    return secret.substring(0, 20);
  }

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
        !RegExp(r'^[a-fA-F0-9]{48}$').hasMatch(secret)) {
      throw const FormatException('Pairing QR is incomplete or incompatible');
    }
    return PairingCredential(id, name, user, secret);
  }
}

class PairingService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Save QR locally. Identity will be HMAC-authenticated on first photo send.
  Future<void> rememberDirectFrame(PairingCredential qr) async {
    qr.hotspotPassword;
    await _storage.write(
      key: 'frame_${qr.id}',
      value: jsonEncode({
        'id': qr.id,
        'name': qr.name,
        'user': qr.username,
        'secret': qr.secret,
      }),
    );
  }

  Future<PairingCredential> loadPairedCredential(String id) async {
    final saved = await _storage.read(key: 'frame_$id');
    if (saved == null) {
      throw StateError('Scan the QR on your physical Lumairie frame first.');
    }
    final data = jsonDecode(saved) as Map<String, dynamic>;
    return PairingCredential(
      data['id'] as String,
      data['name'] as String,
      data['user'] as String,
      data['secret'] as String,
    );
  }

  Future<void> forget(String id) => _storage.delete(key: 'frame_$id');
}
