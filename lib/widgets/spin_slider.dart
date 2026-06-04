import 'package:flutter/material.dart';

/// Vertical spin selector: +1 = top spin (up), -1 = back spin (down), 0 = centre.
/// Long-press activates fine-tune mode (5× slower).
class SpinSlider extends StatefulWidget {
  final double value; // -1.0 to 1.0
  final ValueChanged<double> onChanged;

  static const double height = 100;
  static const double width  = 28;

  const SpinSlider({super.key, required this.value, required this.onChanged});

  @override
  State<SpinSlider> createState() => _SpinSliderState();
}

class _SpinSliderState extends State<SpinSlider> {
  static const double _fineTuneFactor = 0.15;

  bool   _fineTune          = false;
  double _fineTuneBaseValue = 0.0;
  double _fineTuneBaseY     = 0.0;
  double _currentDragY      = 0.0;

  /// localY → spin value: centre = 0, top = +1, bottom = -1
  double _yToValue(double localY) =>
      (1.0 - localY / SpinSlider.height * 2.0).clamp(-1.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (d) {
        _currentDragY = d.localPosition.dy;
        if (!_fineTune) widget.onChanged(_yToValue(_currentDragY));
      },
      onVerticalDragUpdate: (d) {
        _currentDragY = d.localPosition.dy;
        if (_fineTune) {
          final deltaY = _currentDragY - _fineTuneBaseY;
          final delta  = -deltaY / SpinSlider.height * 2.0 * _fineTuneFactor;
          widget.onChanged((_fineTuneBaseValue + delta).clamp(-1.0, 1.0));
        } else {
          widget.onChanged(_yToValue(_currentDragY));
        }
      },
      onVerticalDragEnd: (_) {
        if (_fineTune) setState(() => _fineTune = false);
      },
      onLongPressStart: (d) {
        setState(() {
          _fineTune          = true;
          _fineTuneBaseValue = widget.value;
          _fineTuneBaseY     = d.localPosition.dy;
          _currentDragY      = d.localPosition.dy;
        });
      },
      onLongPressMoveUpdate: (d) {
        _currentDragY = d.localPosition.dy;
        final deltaY  = _currentDragY - _fineTuneBaseY;
        final delta   = -deltaY / SpinSlider.height * 2.0 * _fineTuneFactor;
        widget.onChanged((_fineTuneBaseValue + delta).clamp(-1.0, 1.0));
      },
      onLongPressEnd: (_) => setState(() => _fineTune = false),
      onTapDown: (d) => widget.onChanged(_yToValue(d.localPosition.dy)),
      child: SizedBox(
        width: SpinSlider.width,
        height: SpinSlider.height,
        child: CustomPaint(painter: _SpinPainter(widget.value, _fineTune)),
      ),
    );
  }
}

class _SpinPainter extends CustomPainter {
  final double value;   // -1 to +1
  final bool fineTune;
  _SpinPainter(this.value, this.fineTune);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );

    // Background
    canvas.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.07));

    // Top-spin fill (orange-red, above centre)
    if (value > 0) {
      final fillH   = size.height / 2 * value;
      final fillTop = size.height / 2 - fillH;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, fillTop, size.width, fillH),
          const Radius.circular(8),
        ),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xFFF39C12), Color(0xFFE74C3C)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // Back-spin fill (blue, below centre)
    if (value < 0) {
      final fillH = size.height / 2 * (-value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, size.height / 2, size.width, fillH),
          const Radius.circular(8),
        ),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3498DB), Color(0xFF1A5276)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // Centre divider
    canvas.drawLine(
      Offset(4, size.height / 2),
      Offset(size.width - 4, size.height / 2),
      Paint()..color = Colors.black38..strokeWidth = 1.5,
    );

    // Thumb
    final thumbY      = (1.0 - value) / 2.0 * size.height;
    final thumbRadius = fineTune ? 9.0 : 7.0;
    if (fineTune) {
      canvas.drawCircle(
        Offset(size.width / 2, thumbY),
        thumbRadius + 3,
        Paint()..color = Colors.blueAccent.withValues(alpha: 0.35),
      );
    }
    canvas.drawCircle(
      Offset(size.width / 2, thumbY + 1), thumbRadius,
      Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(size.width / 2, thumbY), thumbRadius,
      Paint()..color = Colors.white,
    );

    // Border
    canvas.drawRRect(
      rr,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SpinPainter old) =>
      old.value != value || old.fineTune != fineTune;
}
