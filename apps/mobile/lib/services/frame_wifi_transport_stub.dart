import 'image_pipeline.dart';
import 'pairing.dart';

typedef FrameSendProgress = void Function(double fraction, String message);

/// Flutter Web keeps using the existing local simulator; real frames require
/// Android/iOS socket access to the same Wi-Fi LAN.
class FrameWifiTransport {
  FrameWifiTransport({this.directHotspot = false});
  final bool directHotspot;
  Future<void> send(PackedFrame frame, PairingCredential qr,
      {required FrameSendProgress onProgress}) async {
    throw UnsupportedError(
        'Physical frame transfer requires the Android or iOS app.');
  }
}
