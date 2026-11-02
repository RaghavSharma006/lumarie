import 'package:flutter/material.dart';

const brandName = 'LUMAIRE';

class Palette {
  const Palette(this.dark);
  final bool dark;
  Color get background =>
      dark ? const Color(0xFF1D1A18) : const Color(0xFFF7F4ED);
  Color get foreground =>
      dark ? const Color(0xFFF8F4ED) : const Color(0xFF30241E);
  Color get muted => dark ? const Color(0xFFB7A99A) : const Color(0xFF87766A);
  Color get surface => dark ? const Color(0xFF302A25) : const Color(0xFFECE6D9);
  Color get surface2 =>
      dark ? const Color(0xFF39322C) : const Color(0xFFE5DDCE);
  Color get stroke => dark ? const Color(0xFF53473D) : const Color(0xFFD4C9B8);
  Color get button => dark ? const Color(0xFFF5F1E9) : const Color(0xFF30241E);
  Color get onButton =>
      dark ? const Color(0xFF30241E) : const Color(0xFFF9F5EE);
}

class Design {
  static const double pageInset = 22;
  static const double radius = 15;
  static const double space = 12;
  static TextStyle title(Palette p, {double size = 23}) => TextStyle(
        color: p.foreground,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.8,
      );
  static TextStyle body(Palette p, {double size = 13, bool muted = false}) =>
      TextStyle(
        color: muted ? p.muted : p.foreground,
        fontSize: size,
        height: 1.25,
      );
  static TextStyle caption(Palette p, {bool muted = false}) => TextStyle(
        color: muted ? p.muted : p.foreground,
        fontSize: 11,
        height: 1.2,
      );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final p = Palette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(Design.radius),
      ),
      child: child,
    );
  }
}

class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final p = Palette(Theme.of(context).brightness == Brightness.dark);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 11 : 14,
          vertical: compact ? 7 : 8,
        ),
        decoration: BoxDecoration(
          color: selected ? p.foreground : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? p.foreground : p.stroke),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? p.background : p.foreground,
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.outline = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool outline;
  @override
  Widget build(BuildContext context) {
    final p = Palette(Theme.of(context).brightness == Brightness.dark);
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: outline ? Colors.transparent : p.button,
          foregroundColor: outline ? p.foreground : p.onButton,
          disabledForegroundColor: p.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: outline ? BorderSide(color: p.stroke) : BorderSide.none,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class DashedAdd extends StatelessWidget {
  const DashedAdd({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 48,
  });
  final String label;
  final VoidCallback onTap;
  final double height;
  @override
  Widget build(BuildContext context) {
    final p = Palette(Theme.of(context).brightness == Brightness.dark);
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashPainter(p.muted),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Center(child: Text(label, style: Design.caption(p))),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(9)),
      );
    final metric = path.computeMetrics().first;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double d = 0; d < metric.length; d += 8) {
      canvas.drawPath(
        metric.extractPath(d, (d + 4).clamp(0, metric.length)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) =>
      color != oldDelegate.color;
}

class FrameArt extends StatelessWidget {
  const FrameArt({
    super.key,
    required this.kind,
    this.landscape = false,
    this.image,
    this.padding = 12,
    this.alignment = Alignment.center,
    this.fit = BoxFit.cover,
    this.quarterTurns = 0,
  });
  final int kind;
  final bool landscape;
  final ImageProvider? image;
  final double padding;
  final Alignment alignment;
  final BoxFit fit;
  final int quarterTurns;
  @override
  Widget build(BuildContext context) {
    final p = Palette(Theme.of(context).brightness == Brightness.dark);
    return AspectRatio(
      aspectRatio: landscape ? 1.42 : 0.78,
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: p.dark ? const Color(0xFF5C5146) : const Color(0xFFE4DCCD),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Container(
          padding: const EdgeInsets.all(5),
          color: const Color(0xFF302921),
          child: Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFFF9F5E9),
            child: ClipRect(
              child: image == null
                  ? CustomPaint(
                      painter: _ArtPainter(kind),
                      child: const SizedBox.expand(),
                    )
                  : RotatedBox(
                      quarterTurns: quarterTurns,
                      child:
                          Image(image: image!, fit: fit, alignment: alignment)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.kind);
  final int kind;
  @override
  void paint(Canvas canvas, Size size) {
    final palettes = [
      [
        const Color(0xFFB27D3E),
        const Color(0xFF33453B),
        const Color(0xFFD7A45A),
      ],
      [
        const Color(0xFF58788A),
        const Color(0xFFD5B788),
        const Color(0xFF5C3C2E),
      ],
      [
        const Color(0xFF8A482C),
        const Color(0xFF263A45),
        const Color(0xFFDDAB4B),
      ],
      [
        const Color(0xFF78613D),
        const Color(0xFF2C3425),
        const Color(0xFFE7C888),
      ],
    ];
    final c = palettes[kind % palettes.length];
    canvas.drawRect(Offset.zero & size, Paint()..color = c[0]);
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .08,
        size.height * .08,
        size.width * .84,
        size.height * .84,
      ),
      Paint()..color = c[1],
    );
    canvas.drawCircle(
      Offset(size.width * .54, size.height * .40),
      size.shortestSide * .19,
      Paint()..color = c[2],
    );
    final path = Path()
      ..moveTo(size.width * .15, size.height)
      ..quadraticBezierTo(
        size.width * .5,
        size.height * .38,
        size.width * .87,
        size.height,
      );
    canvas.drawPath(path, Paint()..color = c[2]);
  }

  @override
  bool shouldRepaint(covariant _ArtPainter oldDelegate) =>
      kind != oldDelegate.kind;
}
