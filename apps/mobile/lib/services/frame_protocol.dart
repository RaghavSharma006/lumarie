import 'dart:typed_data';
import 'image_pipeline.dart';

/// Wire format shared with firmware/main/main.c, protocol version 1.
class FrameProtocol {
  static const int version = 1;
  static const int maxChunk = 256;

  static Uint8List capabilities() => Uint8List.fromList([0x01]);

  static Uint8List begin(PackedFrame frame) {
    final packet = Uint8List(17);
    final data = ByteData.sublistView(packet);
    packet[0] = 0x02;
    data.setUint32(1, version, Endian.little);
    data.setUint16(5, frame.width, Endian.little);
    data.setUint16(7, frame.height, Endian.little);
    data.setUint32(9, frame.pixels.length, Endian.little);
    data.setUint32(13, frame.crc32, Endian.little);
    return packet;
  }

  static Uint8List chunk(int offset, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxChunk || offset < 0) {
      throw const FormatException('Invalid chunk');
    }
    final packet = Uint8List(5 + bytes.length);
    packet[0] = 0x03;
    ByteData.sublistView(packet).setUint32(1, offset, Endian.little);
    packet.setRange(5, packet.length, bytes);
    return packet;
  }

  static Uint8List end() => Uint8List.fromList([0x04]);
  static Uint8List abort() => Uint8List.fromList([0x05]);
}
