import 'package:flutter/material.dart';

/// A circular cue ball diagram for selecting the hit point (English/spin).
/// The tap point maps to -1..1 in both axes.
class HitPointSelector extends StatelessWidget {
  final Offset value;
  final ValueChanged<Offset> onChanged;
  static const double _size = 72;
  static const double _radius = _size / 2;

  const HitPointSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => _handleDrag(details.localPosition),
      onTapDown: (details) => _handleDrag(details.localPosition),
      child: SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(
          painter: _HitPointPainter(value),
        ),
      ),
    );
  }

  void _handleDrag(Offset localPos) {
    final center = const Offset(_radius, _radius);
    final delta = localPos - center;
    final normalized = Offset(delta.dx / _radius, delta.dy / _radius);
    // Clamp to unit circle
    final len = normalized.distance;
    final clamped = len > 1.0
        ? Offset(normalized.dx / len, normalized.dy / len) * 0.95
        : normalized;
    onChanged(clamped);
  }
}

class _HitPointPainter extends CustomPainter {
  final Offset hitPoint;
  _HitPointPainter(this.hitPoint);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Ball body
    final ballPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 1.0,
        colors: [Colors.white, const Color(0xFFD0D0D0), const Color(0xFF909090)],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, ballPaint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, r, borderPaint);

    // Center crosshair
    final crossPaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 0.5;
    canvas.drawLine(center - Offset(r * 0.6, 0), center + Offset(r * 0.6, 0), crossPaint);
    canvas.drawLine(center - Offset(0, r * 0.6), center + Offset(0, r * 0.6), crossPaint);

    // Hit point marker
    final dotX = center.dx + hitPoint.dx * r * 0.85;
    final dotY = center.dy + hitPoint.dy * r * 0.85;

    final dotShadow = Paint()
      ..color = Colors.black54
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(dotX + 1, dotY + 1), 5, dotShadow);

    final dotPaint = Paint()
      ..color = const Color(0xFFE74C3C);
    canvas.drawCircle(Offset(dotX, dotY), 5, dotPaint);

    final dotBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(dotX, dotY), 5, dotBorder);
  }

  @override
  bool shouldRepaint(_HitPointPainter old) => old.hitPoint != hitPoint;
}
