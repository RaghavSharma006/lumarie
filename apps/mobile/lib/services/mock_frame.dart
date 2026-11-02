import 'dart:async';
import 'dart:typed_data';

import 'image_pipeline.dart';
import 'frame_protocol.dart';

typedef ProgressCallback = void Function(double fraction, String status);

/// Transfer simulator with the same commit invariant required of firmware:
/// no visible refresh until length, chunk order and CRC are all verified.
class MockFrame {
  bool refreshed = false;
  int expectedOffset = 0;
  Uint8List? _staging;

  void begin(PackedFrame frame) {
    if (frame.width <= 0 ||
        frame.height <= 0 ||
        frame.pixels.length > 512000 ||
        frame.pixels.length != (frame.width * frame.height + 1) ~/ 2) {
      throw const FormatException('Invalid frame metadata');
    }
    refreshed = false;
    expectedOffset = 0;
    _staging = Uint8List(frame.pixels.length);
  }

  int chunk(int offset, Uint8List bytes) {
    final staging = _staging;
    if (staging != null &&
        offset < expectedOffset &&
        offset + bytes.length <= expectedOffset &&
        bytes.isNotEmpty) {
      for (var i = 0; i < bytes.length; i++) {
        if (staging[offset + i] != bytes[i]) {
          throw StateError('Mismatched retry');
        }
      }
      return expectedOffset;
    }
    if (staging == null ||
        offset != expectedOffset ||
        bytes.isEmpty ||
        bytes.length > FrameProtocol.maxChunk ||
        offset + bytes.length > staging.length) {
      throw StateError('Invalid or reordered chunk');
    }
    staging.setRange(offset, offset + bytes.length, bytes);
    expectedOffset += bytes.length;
    return expectedOffset;
  }

  void finish(PackedFrame frame) {
    final staging = _staging;
    if (staging == null ||
        expectedOffset != staging.length ||
        ImagePipeline.crc32(staging) != frame.crc32) {
      _staging = null;
      throw StateError('Incomplete or corrupt frame');
    }
    _staging = null;
    refreshed = true;
  }

  void abort() {
    _staging = null;
    expectedOffset = 0;
  }

  int handle(Uint8List request, PackedFrame frame) {
    if (request.isEmpty) throw const FormatException('Empty request');
    switch (request[0]) {
      case 0x02:
        if (request.length != 17) throw const FormatException('Bad BEGIN');
        final data = ByteData.sublistView(request);
        if (data.getUint32(1, Endian.little) != FrameProtocol.version ||
            data.getUint16(5, Endian.little) != frame.width ||
            data.getUint16(7, Endian.little) != frame.height ||
            data.getUint32(9, Endian.little) != frame.pixels.length ||
            data.getUint32(13, Endian.little) != frame.crc32) {
          throw const FormatException('Bad metadata');
        }
        begin(frame);
        return 0;
      case 0x03:
        if (request.length < 6) throw const FormatException('Bad CHUNK');
        return chunk(ByteData.sublistView(request).getUint32(1, Endian.little),
            Uint8List.sublistView(request, 5));
      case 0x04:
        finish(frame);
        return expectedOffset;
      case 0x05:
        abort();
        return 0;
      default:
        throw const FormatException('Unknown command');
    }
  }

  Future<void> transfer(
    PackedFrame frame, {
    required ProgressCallback onProgress,
    int? dropAckOnceAt,
  }) async {
    handle(FrameProtocol.begin(frame), frame);
    try {
      var lostAck = false;
      for (var offset = 0;
          offset < frame.pixels.length;
          offset += FrameProtocol.maxChunk) {
        final end =
            (offset + FrameProtocol.maxChunk).clamp(0, frame.pixels.length);
        final packet = FrameProtocol.chunk(
            offset, Uint8List.sublistView(frame.pixels, offset, end));
        var ack = handle(packet, frame);
        if (dropAckOnceAt == offset && !lostAck) {
          lostAck = true;
          ack = handle(packet, frame);
        }
        if (offset % 16384 == 0) {
          onProgress(
            ack / frame.pixels.length * .93,
            'Delivered ${ack ~/ 1024} KB',
          );
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      onProgress(.96, 'Verifying frame');
      handle(FrameProtocol.end(), frame);
      onProgress(1, 'Demo display refreshed');
    } catch (_) {
      abort();
      rethrow;
    }
  }
}
