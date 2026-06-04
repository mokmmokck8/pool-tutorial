import 'package:flutter/material.dart';

/// Vertical power slider with color gradient (green → yellow → red).
/// Drag tracks finger position directly. Long-press activates fine-tune mode (5× slower).
class PowerSlider extends StatefulWidget {
  final double value; // 0.0 to 1.0
  final ValueChanged<double> onChanged;
  static const double height = 100;
  static const double width = 28;

  const PowerSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<PowerSlider> createState() => _PowerSliderState();
}

class _PowerSliderState extends State<PowerSlider> {
  static const double _fineTuneFactor = 0.15;

  bool _fineTune = false;
  // The slider value at the moment fine-tune mode was activated
  double _fineTuneBaseValue = 0.0;
  // The finger Y at the moment fine-tune mode was activated
  double _fineTuneBaseY = 0.0;
  // Current finger Y (absolute within widget)
  double _currentDragY = 0.0;

  void _valueFromY(double localY) {
    final v = 1.0 - (localY / PowerSlider.height).clamp(0.0, 1.0);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (d) {
        _currentDragY = d.localPosition.dy;
        if (!_fineTune) {
          // Snap thumb to finger
          _valueFromY(_currentDragY);
        }
      },
      onVerticalDragUpdate: (d) {
        _currentDragY = d.localPosition.dy;
        if (_fineTune) {
          // Fine-tune: move relative to where long-press was activated
          final deltaY = _currentDragY - _fineTuneBaseY;
          final delta = -deltaY / PowerSlider.height * _fineTuneFactor;
          widget.onChanged((_fineTuneBaseValue + delta).clamp(0.0, 1.0));
        } else {
          _valueFromY(_currentDragY);
        }
      },
      onVerticalDragEnd: (_) {
        if (_fineTune) {
          setState(() => _fineTune = false);
        }
      },
      onLongPressStart: (d) {
        setState(() {
          _fineTune = true;
          _fineTuneBaseValue = widget.value;
          _fineTuneBaseY = d.localPosition.dy;
          _currentDragY = d.localPosition.dy;
        });
      },
      onLongPressMoveUpdate: (d) {
        _currentDragY = d.localPosition.dy;
        final deltaY = _currentDragY - _fineTuneBaseY;
        final delta = -deltaY / PowerSlider.height * _fineTuneFactor;
        widget.onChanged((_fineTuneBaseValue + delta).clamp(0.0, 1.0));
      },
      onLongPressEnd: (_) {
        setState(() => _fineTune = false);
      },
      onTapDown: (d) {
        _valueFromY(d.localPosition.dy);
      },
      child: SizedBox(
        width: PowerSlider.width,
        height: PowerSlider.height,
        child: CustomPaint(
          painter: _PowerPainter(widget.value, _fineTune),
        ),
      ),
    );
  }
}

class _PowerPainter extends CustomPainter {
  final double value;
  final bool fineTune;
  _PowerPainter(this.value, this.fineTune);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );

    // Track background
    final bgPaint = Paint()..color = Colors.black.withOpacity(0.07);
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

    // Thumb — larger + blue ring in fine-tune mode
    final thumbY = size.height - size.height * value;
    final thumbRadius = fineTune ? 9.0 : 7.0;
    if (fineTune) {
      canvas.drawCircle(
        Offset(size.width / 2, thumbY),
        thumbRadius + 3,
        Paint()..color = Colors.blueAccent.withOpacity(0.35),
      );
    }
    final thumbShadow = Paint()
      ..color = Colors.black26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(size.width / 2, thumbY + 1), thumbRadius, thumbShadow);
    canvas.drawCircle(Offset(size.width / 2, thumbY), thumbRadius, Paint()..color = Colors.white);

    // Border
    canvas.drawRRect(
      rr,
      Paint()
        ..color = Colors.black.withOpacity(0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PowerPainter old) => old.value != value || old.fineTune != fineTune;
}
