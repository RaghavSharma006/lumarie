import 'package:flutter/services.dart';
import 'pairing.dart';

/// Android asks user to approve a local-only Wi-Fi connection to the frame.
/// No router credentials are involved. The OS uses the password from the QR.
class FrameApConnection {
  static const _channel = MethodChannel('io.lumarie.mobile/frame_ap');

  Future<void> connect(PairingCredential qr) async {
    try {
      final ok = await _channel.invokeMethod<bool>('connect', {
        'ssid': qr.hotspotSsid,
        'password': qr.hotspotPassword,
      });
      if (ok != true) {
        throw StateError('Android did not confirm frame Wi-Fi connection');
      }
    } on MissingPluginException {
      throw UnsupportedError(
          'Automatic direct Wi-Fi connection currently requires the Android app.');
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Could not connect to frame Wi-Fi');
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<bool>('disconnect');
    } on PlatformException catch (_) {
      // Never mask the actual send error while restoring the phone network.
    } on MissingPluginException catch (_) {
      // e.g. iOS or Web.
    }
  }
}
