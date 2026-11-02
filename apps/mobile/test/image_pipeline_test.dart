import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lumairie/services/image_pipeline.dart';
import 'package:lumairie/services/frame_protocol.dart';
import 'package:lumairie/services/mock_frame.dart';

void main() {
  test('packs two palette indices per byte in deterministic order', () {
    final red = img.Image(width: 2, height: 1);
    red.setPixelRgb(0, 0, 255, 255, 255);
    red.setPixelRgb(1, 0, 0, 0, 0);
    final frame = ImagePipeline.process(
      Uint8List.fromList(img.encodePng(red)),
      profile: const PanelProfile(width: 2, height: 1),
    );
    expect(frame.pixels.length, 1);
    expect(frame.pixels[0], 0x01);
    expect(frame.crc32, ImagePipeline.crc32(frame.pixels));
  });

  test('candidate full frame is exactly 192000 bytes', () {
    final frame = ImagePipeline.demoFrame();
    expect(frame.pixels.length, 192000);
  });

  test('truncated, reordered, and corrupt transfers never refresh', () {
    final frame = ImagePipeline.demoFrame(
      profile: const PanelProfile(width: 4, height: 2),
    );
    final device = MockFrame();
    device.begin(frame);
    device.chunk(0, Uint8List.fromList(frame.pixels.sublist(0, 2)));
    expect(() => device.finish(frame), throwsStateError);
    expect(device.refreshed, false);

    device.begin(frame);
    expect(() => device.chunk(1, Uint8List.fromList([1])), throwsStateError);
    expect(device.refreshed, false);

    device.begin(frame);
    device.chunk(0, Uint8List.fromList([0, 0, 0, 0]));
    expect(() => device.finish(frame), throwsStateError);
    expect(device.refreshed, false);
  });

  test('complete verified transfer refreshes only at finish', () {
    final frame = ImagePipeline.demoFrame(
      profile: const PanelProfile(width: 4, height: 2),
    );
    final device = MockFrame();
    device.begin(frame);
    device.chunk(0, frame.pixels);
    expect(device.refreshed, false);
    device.finish(frame);
    expect(device.refreshed, true);
  });

  test('wire BEGIN uses little endian candidate dimensions and checksum', () {
    final frame = ImagePipeline.demoFrame();
    final packet = FrameProtocol.begin(frame);
    final data = ByteData.sublistView(packet);
    expect(packet[0], 0x02);
    expect(data.getUint32(1, Endian.little), 1);
    expect(data.getUint16(5, Endian.little), 800);
    expect(data.getUint16(7, Endian.little), 480);
    expect(data.getUint32(9, Endian.little), 192000);
    expect(data.getUint32(13, Endian.little), frame.crc32);
  });

  test('lost ACK retry is idempotent and still verifies before refresh',
      () async {
    final frame = ImagePipeline.demoFrame(
        profile: const PanelProfile(width: 4, height: 2));
    final device = MockFrame();
    await device.transfer(frame,
        onProgress: (fraction, status) {}, dropAckOnceAt: 0);
    expect(device.refreshed, true);
  });
}
