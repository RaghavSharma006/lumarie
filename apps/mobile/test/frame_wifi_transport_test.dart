import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumairie/services/frame_wifi_transport_io.dart';
import 'package:lumairie/services/frame_protocol.dart';
import 'package:lumairie/services/image_pipeline.dart';
import 'package:lumairie/services/mock_frame.dart';
import 'package:lumairie/services/pairing.dart';

class _Reader {
  _Reader(Socket socket) : chunks = StreamIterator<Uint8List>(socket);
  final StreamIterator<Uint8List> chunks;
  Uint8List data = Uint8List(0);
  int offset = 0;
  Future<Uint8List> read(int length) async {
    final result = Uint8List(length);
    var done = 0;
    while (done < length) {
      if (offset == data.length) {
        if (!await chunks.moveNext().timeout(const Duration(seconds: 20))) {
          throw StateError('TCP stream unexpectedly closed');
        }
        data = chunks.current;
        offset = 0;
      }
      final take = (length - done < data.length - offset)
          ? length - done
          : data.length - offset;
      result.setRange(done, done + take, data, offset);
      done += take;
      offset += take;
    }
    return result;
  }

  Future<void> close() => chunks.cancel();
}

Uint8List _auth(String key, List<int> data) =>
    Uint8List.fromList(Hmac(sha256, utf8.encode(key)).convert(data).bytes);

void main() {
  for (final deliveryOnly in [false, true]) {
    test(
        'authenticated local transfer accepts ${deliveryOnly ? 'verified delivery' : 'completed refresh'}',
        () async {
      const qr = PairingCredential(
        'EE04_AB12CD',
        'LUMAIRE-AB12CD',
        'unit',
        '0123456789abcdef0123456789abcdef0123456789abcdef',
      );
      final frame = ImagePipeline.demoFrame(landscape: true);
      final mock = MockFrame();
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 39393);
      final serverResult = Completer<int>();
      final subscription = server.listen((socket) async {
        final input = _Reader(socket);
        try {
          final nonce = List<int>.generate(16, (i) => i + 13);
          final greeting =
              Uint8List.fromList([...ascii.encode('LMF1'), ...nonce]);
          socket.add(greeting);
          await socket.flush();
          final signedName = [...greeting, ...ascii.encode(qr.name)];
          expect(await input.read(32), _auth(qr.secret, signedName));
          socket.add(ascii.encode('OK'));
          await socket.flush();
          var expectedSeq = 1;
          var packets = 0;
          while (true) {
            final header = await input.read(6);
            final sequence =
                ByteData.sublistView(header).getUint32(0, Endian.little);
            final length =
                ByteData.sublistView(header).getUint16(4, Endian.little);
            expect(sequence, expectedSeq);
            expect(length, inInclusiveRange(1, 261));
            final bytes = await input.read(length);
            final signature = await input.read(32);
            expect(
              signature,
              _auth(qr.secret, [
                ...ascii.encode('REQ1'),
                ...nonce,
                ...header,
                ...bytes,
              ]),
            );
            final response = Uint8List(9);
            response[0] = bytes[0];
            switch (bytes[0]) {
              case 0x01:
                ByteData.sublistView(response)
                  ..setUint32(1, FrameProtocol.version, Endian.little)
                  ..setUint32(5, FrameProtocol.maxChunk, Endian.little);
              case 0x02:
                mock.handle(bytes, frame);
              case 0x03:
                final next = mock.handle(bytes, frame);
                ByteData.sublistView(response)
                    .setUint32(1, next, Endian.little);
              case 0x04:
                mock.handle(bytes, frame);
                response[5] = deliveryOnly ? 1 : 2;
              default:
                throw StateError('Unexpected protocol opcode ${bytes[0]}');
            }
            final seq = header.sublist(0, 4);
            socket.add([
              ...seq,
              ...response,
              ..._auth(qr.secret, [
                ...ascii.encode('ACK1'),
                ...nonce,
                ...seq,
                ...response,
              ]),
            ]);
            await socket.flush();
            ++expectedSeq;
            ++packets;
            if (bytes[0] == 0x04) break;
          }
          expect(mock.visibleFrame?.crc32, frame.crc32);
          serverResult.complete(packets);
        } catch (error, trace) {
          serverResult.completeError(error, trace);
        } finally {
          await input.close();
          socket.destroy();
        }
      });
      try {
        final updates = <double>[];
        await FrameWifiTransport(
          discoveryOverride: (_) async => InternetAddress.loopbackIPv4,
        ).send(frame, qr, onProgress: (fraction, _) => updates.add(fraction));
        expect(await serverResult.future.timeout(const Duration(seconds: 30)),
            1 + 1 + 750 + 1);
        expect(updates.last, 1);
        expect(mock.refreshed, isTrue);
        expect(mock.visibleFrame?.pixels, frame.pixels);
      } finally {
        await subscription.cancel();
        await server.close();
      }
    });
  }
}
