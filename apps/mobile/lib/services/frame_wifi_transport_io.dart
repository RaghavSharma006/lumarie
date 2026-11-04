import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'frame_protocol.dart';
import 'image_pipeline.dart';
import 'pairing.dart';

typedef FrameSendProgress = void Function(double fraction, String message);

/// Local Wi-Fi transport for existing FrameProtocol v1 bytes.
///
/// UDP 38343 finds the device and verifies an HMAC over its name/IP and our
/// random challenge. TCP 39393 uses a new random server challenge, the same
/// per-device QR secret, per-request sequence numbers and HMAC-SHA256.
/// Wi-Fi image bytes are not encrypted at the application layer: production
/// deployment should use an audited AEAD/TLS transport before untrusted LANs.
class FrameWifiTransport {
  FrameWifiTransport({this.discoveryOverride});

  /// Allows a deterministic loopback receiver in tests. Production uses the
  /// authenticated UDP discovery mechanism, not this override.
  final Future<InternetAddress> Function(PairingCredential)? discoveryOverride;

  static const int _tcpPort = 39393;
  static const int _udpPort = 38343;
  final Random _random = Random.secure();

  Uint8List _mac(String secret, List<int> input) => Uint8List.fromList(
        Hmac(sha256, utf8.encode(secret)).convert(input).bytes,
      );

  bool _equal(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var different = 0;
    for (var i = 0; i < left.length; i++) {
      different |= left[i] ^ right[i];
    }
    return different == 0;
  }

  /// Verify reply from the paired device, never trust name or bare IP alone.
  Future<InternetAddress> discover(PairingCredential qr) async {
    final name = ascii.encode(qr.name);
    if (name.length != 14) throw const FormatException('Invalid BLE name');
    final nonce = Uint8List.fromList(
        List<int>.generate(8, (_) => _random.nextInt(256)));
    final query = Uint8List.fromList([...ascii.encode('LMD1'), ...nonce]);
    final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    udp.broadcastEnabled = true;
    final result = Completer<InternetAddress>();
    late final StreamSubscription<RawSocketEvent> subscription;
    subscription = udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = udp.receive()) != null) {
        final bytes = datagram!.data;
        if (bytes.length != 62 ||
            !_equal(bytes.sublist(0, 4), ascii.encode('LMD2')) ||
            !_equal(bytes.sublist(4, 18), name) ||
            !_equal(bytes.sublist(22, 30), nonce) ||
            !_equal(bytes.sublist(30), _mac(qr.secret, bytes.sublist(0, 30)))) {
          continue;
        }
        if (!result.isCompleted) {
          result.complete(InternetAddress.fromRawAddress(bytes.sublist(18, 22)));
        }
      }
    });
    try {
      for (var attempt = 0; attempt < 4; ++attempt) {
        udp.send(query, InternetAddress('255.255.255.255'), _udpPort);
        try {
          return await result.future.timeout(const Duration(milliseconds: 1300));
        } on TimeoutException {
          // Wi-Fi multicast/broadcast can take a second to start on phones.
        }
      }
      throw StateError(
          'LUMAIRIE frame not found. Connect the phone and frame to the same Wi-Fi network; check router isolation and local-network permissions.');
    } finally {
      await subscription.cancel();
      udp.close();
    }
  }

  Future<void> send(
    PackedFrame frame,
    PairingCredential qr, {
    required FrameSendProgress onProgress,
  }) async {
    if (!((frame.width == 800 && frame.height == 480) ||
          (frame.width == 480 && frame.height == 800)) ||
        frame.pixels.length != 192000 ||
        ImagePipeline.crc32(frame.pixels) != frame.crc32) {
      throw const FormatException('Invalid six-color frame or CRC32');
    }
    onProgress(0.02, 'Finding your frame on Wi-Fi');
    final address = await (discoveryOverride?.call(qr) ?? discover(qr));
    final socket = await Socket.connect(
      address,
      _tcpPort,
      timeout: const Duration(seconds: 8),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    final incoming = _SocketBuffer(socket);
    try {
      final greeting = await incoming.readExact(20);
      if (!_equal(greeting.sublist(0, 4), ascii.encode('LMF1'))) {
        throw StateError('Frame has an incompatible transfer protocol');
      }
      final serverNonce = greeting.sublist(4);
      final identityProof = _mac(qr.secret, [
        ...greeting,
        ...ascii.encode(qr.name),
      ]);
      socket.add(identityProof);
      await socket.flush();
      final accepted = await incoming.readExact(2);
      if (!_equal(accepted, ascii.encode('OK'))) {
        throw StateError('Frame rejected the paired-device credential');
      }
      var sequence = 1;
      Future<Uint8List> exchange(Uint8List packet,
          {Duration timeout = const Duration(seconds: 20)}) async {
        final header = Uint8List(6);
        final byteData = ByteData.sublistView(header);
        byteData.setUint32(0, sequence, Endian.little);
        byteData.setUint16(4, packet.length, Endian.little);
        final proof = _mac(qr.secret, [
          ...ascii.encode('REQ1'),
          ...serverNonce,
          ...header,
          ...packet,
        ]);
        socket.add([...header, ...packet, ...proof]);
        await socket.flush();
        final response = await incoming.readExact(4 + 9 + 32, timeout: timeout);
        if (!_equal(response.sublist(0, 4), header.sublist(0, 4)) ||
            !_equal(
              response.sublist(13),
              _mac(qr.secret, [
                ...ascii.encode('ACK1'),
                ...serverNonce,
                ...response.sublist(0, 13),
              ]),
            )) {
          throw StateError('Unauthenticated or out-of-order frame ACK');
        }
        final payload = Uint8List.fromList(response.sublist(4, 13));
        if (payload[0] != packet[0] || payload[8] != 0) {
          throw StateError('Frame rejected request 0x${packet[0].toRadixString(16)}');
        }
        sequence += 1;
        return payload;
      }

      final capabilities = await exchange(FrameProtocol.capabilities());
      final capabilityData = ByteData.sublistView(capabilities);
      if (capabilityData.getUint32(1, Endian.little) != FrameProtocol.version ||
          capabilityData.getUint32(5, Endian.little) != FrameProtocol.maxChunk) {
        throw StateError('Frame protocol version or chunk size mismatch');
      }
      await exchange(FrameProtocol.begin(frame));
      onProgress(0.05, 'Sending six-color pixels');
      for (var offset = 0; offset < frame.pixels.length;
          offset += FrameProtocol.maxChunk) {
        final end = (offset + FrameProtocol.maxChunk)
            .clamp(0, frame.pixels.length);
        final acknowledgement = await exchange(
          FrameProtocol.chunk(
            offset,
            Uint8List.sublistView(frame.pixels, offset, end),
          ),
        );
        final ackOffset = ByteData.sublistView(acknowledgement)
            .getUint32(1, Endian.little);
        if (ackOffset != end) {
          throw StateError('Frame acknowledged an unexpected image offset');
        }
        if (offset % 4096 == 0 || end == frame.pixels.length) {
          onProgress(0.05 + 0.88 * end / frame.pixels.length,
              'Transferred ${end ~/ 1024} of 187 KB');
        }
      }
      onProgress(0.96, 'Verifying and refreshing Spectra 6 display');
      final confirmation = await exchange(
        FrameProtocol.end(),
        timeout: const Duration(seconds: 180),
      );
      if (confirmation[5] != 2) {
        throw StateError('Frame verified the data but did not confirm display');
      }
      onProgress(1.0, 'Photo displayed on the physical frame');
    } finally {
      await incoming.cancel();
      await socket.close();
      socket.destroy();
    }
  }
}

/// A single subscription avoids losing bytes across small TCP reads.
class _SocketBuffer {
  _SocketBuffer(Socket socket) : _source = StreamIterator<Uint8List>(socket);

  final StreamIterator<Uint8List> _source;
  Uint8List _current = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> readExact(
    int length, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final result = Uint8List(length);
    var written = 0;
    final deadline = DateTime.now().add(timeout);
    while (written < length) {
      if (_offset == _current.length) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero ||
            !await _source.moveNext().timeout(remaining)) {
          throw TimeoutException('Frame closed connection or timed out');
        }
        _current = _source.current;
        _offset = 0;
        continue;
      }
      final count = min(length - written, _current.length - _offset);
      result.setRange(written, written + count, _current, _offset);
      written += count;
      _offset += count;
    }
    return result;
  }

  Future<void> cancel() => _source.cancel();
}
