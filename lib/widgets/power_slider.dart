import 'package:flutter/material.dart';

/// Vertical power slider with color gradient (green → yellow → red).
class PowerSlider extends StatelessWidget {
  final double value; // 0.0 to 1.0
  final ValueChanged<double> onChanged;
  static const double _height = 100;
  static const double _width = 28;

  const PowerSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        // drag up = more power
        final delta = -d.delta.dy / _height;
        onChanged((value + delta).clamp(0.0, 1.0));
      },
      onTapDown: (d) {
        final newVal = 1.0 - (d.localPosition.dy / _height).clamp(0.0, 1.0);
        onChanged(newVal);
      },
      child: SizedBox(
        width: _width,
        height: _height,
        child: CustomPaint(
          painter: _PowerPainter(value),
        ),
      ),
    );
  }
}

class _PowerPainter extends CustomPainter {
  final double value;
  _PowerPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );

    // Track background
    final bgPaint = Paint()..color = Colors.white10;
    canvas.drawRRect(rr, bgPaint);

    // Filled portion (bottom up)
    final fillHeight = size.height * value;
    if (fillHeight > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight),
        const Radius.circular(8),
      );
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFFE74C3C),
            Color(0xFFF39C12),
            Color(0xFF2ECC71),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawRRect(fillRect, fillPaint);
    }

    // Notch marks
    final notchPaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1;
    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), notchPaint);
    }

    // Thumb
    final thumbY = size.height - size.height * value;
    final thumbPaint = Paint()..color = Colors.white;
    final thumbShadow = Paint()
      ..color = Colors.black38
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(size.width / 2, thumbY + 1), 7, thumbShadow);
    canvas.drawCircle(Offset(size.width / 2, thumbY), 7, thumbPaint);

    // Border
    canvas.drawRRect(
      rr,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PowerPainter old) => old.value != value;
}
