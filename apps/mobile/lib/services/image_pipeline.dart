import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Candidate six-color profile. The actual panel index order remains unverified.
class PanelProfile {
  const PanelProfile({this.width = 800, this.height = 480});
  final int width;
  final int height;
  static const palette = <List<int>>[
    [255, 255, 255], // white
    [0, 0, 0], // black
    [190, 35, 37], // red
    [241, 202, 46], // yellow
    [39, 86, 157], // blue
    [51, 125, 68], // green
  ];
}

class PackedFrame {
  const PackedFrame(this.width, this.height, this.pixels, this.crc32);
  final int width;
  final int height;
  final Uint8List pixels;
  final int crc32;
}

class ImagePipeline {
  static Uint8List previewPng(PackedFrame frame) {
    final output = img.Image(width: frame.width, height: frame.height);
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final index = y * frame.width + x;
        final packed = frame.pixels[index ~/ 2];
        final colorIndex = index.isEven ? packed >> 4 : packed & 0x0F;
        if (colorIndex >= PanelProfile.palette.length) {
          throw const FormatException('Unsupported palette index');
        }
        final color = PanelProfile.palette[colorIndex];
        output.setPixelRgb(x, y, color[0], color[1], color[2]);
      }
    }
    return Uint8List.fromList(img.encodePng(output));
  }

  static PackedFrame demoFrame({
    bool landscape = false,
    PanelProfile profile = const PanelProfile(),
  }) {
    final pixels = Uint8List((profile.width * profile.height + 1) ~/ 2);
    for (var y = 0; y < profile.height; y++) {
      for (var x = 0; x < profile.width; x++) {
        final color = y < profile.height ~/ 3
            ? 0
            : x < profile.width ~/ 2
                ? 3
                : 5;
        final index = y * profile.width + x;
        if (index.isEven) {
          pixels[index ~/ 2] = color << 4;
        } else {
          pixels[index ~/ 2] |= color;
        }
      }
    }
    return PackedFrame(profile.width, profile.height, pixels, crc32(pixels));
  }

  /// Center-crops or letterboxes to a candidate raster, Floyd-Steinberg dithers,
  /// and packs the left pixel in the high nibble. The panel adapter may replace
  /// this mapping after the exact supplier driver is identified.
  static PackedFrame process(
    Uint8List encoded, {
    bool landscape = true,
    bool fill = false,
    double focalX = .5,
    double focalY = .5,
    int quarterTurns = 0,
    PanelProfile profile = const PanelProfile(),
  }) {
    final decoded = img.decodeImage(encoded);
    if (decoded == null) throw const FormatException('Unsupported image');
    final source = quarterTurns % 4 == 0
        ? decoded
        : img.copyRotate(decoded, angle: (quarterTurns % 4) * 90);
    final width = landscape ? profile.width : profile.height;
    final height = landscape ? profile.height : profile.width;
    final target = Uint8List((width * height + 1) ~/ 2);
    final current = List<double>.filled((width + 2) * 3, 0);
    final next = List<double>.filled((width + 2) * 3, 0);
    final scale = fill
        ? math.max(width / source.width, height / source.height)
        : math.min(width / source.width, height / source.height);
    final shownW = source.width * scale;
    final shownH = source.height * scale;
    final startX = (width - shownW) * focalX.clamp(0, 1);
    final startY = (height - shownH) * focalY.clamp(0, 1);
    for (var y = 0; y < height; y++) {
      next.fillRange(0, next.length, 0);
      for (var x = 0; x < width; x++) {
        final sx = ((x - startX) / scale).floor();
        final sy = ((y - startY) / scale).floor();
        final inside =
            sx >= 0 && sx < source.width && sy >= 0 && sy < source.height;
        final pixel = inside ? source.getPixel(sx, sy) : null;
        final raw = <double>[
          inside ? pixel!.r.toDouble() : 255,
          inside ? pixel!.g.toDouble() : 255,
          inside ? pixel!.b.toDouble() : 255,
        ];
        final base = (x + 1) * 3;
        for (var c = 0; c < 3; c++) {
          raw[c] = (raw[c] + current[base + c]).clamp(0, 255);
        }
        var best = 0;
        var distance = double.infinity;
        for (var i = 0; i < PanelProfile.palette.length; i++) {
          final p = PanelProfile.palette[i];
          final d = math.pow(raw[0] - p[0], 2) +
              math.pow(raw[1] - p[1], 2) +
              math.pow(raw[2] - p[2], 2);
          if (d < distance) {
            distance = d.toDouble();
            best = i;
          }
        }
        final index = y * width + x;
        if (index.isEven) {
          target[index ~/ 2] = best << 4;
        } else {
          target[index ~/ 2] |= best;
        }
        for (var c = 0; c < 3; c++) {
          final error = raw[c] - PanelProfile.palette[best][c];
          current[base + 3 + c] += error * 7 / 16;
          next[base - 3 + c] += error * 3 / 16;
          next[base + c] += error * 5 / 16;
          next[base + 3 + c] += error / 16;
        }
      }
      current.setAll(0, next);
    }
    return PackedFrame(width, height, target, crc32(target));
  }

  static int crc32(Uint8List data) {
    var value = 0xFFFFFFFF;
    for (final byte in data) {
      value ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        value = (value & 1) != 0 ? (value >> 1) ^ 0xEDB88320 : value >> 1;
      }
    }
    return (value ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
