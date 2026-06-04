import 'package:flutter/material.dart';

/// Horizontal side-spin selector: +1 = right spin, -1 = left spin, 0 = centre.
/// Long-press activates fine-tune mode (5× slower).
class SideSpinSlider extends StatefulWidget {
  final double value; // -1.0 to 1.0
  final ValueChanged<double> onChanged;

  static const double height = 28;
  static const double width  = 100;

  const SideSpinSlider({super.key, required this.value, required this.onChanged});

  @override
  State<SideSpinSlider> createState() => _SideSpinSliderState();
}

class _SideSpinSliderState extends State<SideSpinSlider> {
  static const double _fineTuneFactor = 0.15;

  bool   _fineTune          = false;
  double _fineTuneBaseValue = 0.0;
  double _fineTuneBaseX     = 0.0;
  double _currentDragX      = 0.0;

  /// localX → spin value: centre = 0, right = +1, left = -1
  double _xToValue(double localX) =>
      ((localX / SideSpinSlider.width) * 2.0 - 1.0).clamp(-1.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: (d) {
        _currentDragX = d.localPosition.dx;
        if (!_fineTune) widget.onChanged(_xToValue(_currentDragX));
      },
      onHorizontalDragUpdate: (d) {
        _currentDragX = d.localPosition.dx;
        if (_fineTune) {
          final deltaX = _currentDragX - _fineTuneBaseX;
          final delta  = deltaX / SideSpinSlider.width * 2.0 * _fineTuneFactor;
          widget.onChanged((_fineTuneBaseValue + delta).clamp(-1.0, 1.0));
        } else {
          widget.onChanged(_xToValue(_currentDragX));
        }
      },
      onHorizontalDragEnd: (_) {
        if (_fineTune) setState(() => _fineTune = false);
      },
      onLongPressStart: (d) {
        setState(() {
          _fineTune          = true;
          _fineTuneBaseValue = widget.value;
          _fineTuneBaseX     = d.localPosition.dx;
          _currentDragX      = d.localPosition.dx;
        });
      },
      onLongPressMoveUpdate: (d) {
        _currentDragX = d.localPosition.dx;
        final deltaX  = _currentDragX - _fineTuneBaseX;
        final delta   = deltaX / SideSpinSlider.width * 2.0 * _fineTuneFactor;
        widget.onChanged((_fineTuneBaseValue + delta).clamp(-1.0, 1.0));
      },
      onLongPressEnd: (_) => setState(() => _fineTune = false),
      onTapDown: (d) => widget.onChanged(_xToValue(d.localPosition.dx)),
      child: SizedBox(
        width: SideSpinSlider.width,
        height: SideSpinSlider.height,
        child: CustomPaint(painter: _SideSpinPainter(widget.value, _fineTune)),
      ),
    );
  }
}

class _SideSpinPainter extends CustomPainter {
  final double value;   // -1 to +1
  final bool fineTune;
  _SideSpinPainter(this.value, this.fineTune);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );

    // Background
    canvas.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.07));

    final cx = size.width / 2;

    // Right spin fill (purple, right of centre)
    if (value > 0) {
      final fillW = cx * value;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx, 0, fillW, size.height),
          const Radius.circular(8),
        ),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF9B59B6), Color(0xFF6C3483)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // Left spin fill (teal, left of centre)
    if (value < 0) {
      final fillW = cx * (-value);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - fillW, 0, fillW, size.height),
          const Radius.circular(8),
        ),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Color(0xFF1ABC9C), Color(0xFF0E6655)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // Centre divider
    canvas.drawLine(
      Offset(cx, 4),
      Offset(cx, size.height - 4),
      Paint()..color = Colors.black38..strokeWidth = 1.5,
    );

    // Thumb
    final thumbX      = (value + 1.0) / 2.0 * size.width;
    final thumbRadius = fineTune ? 9.0 : 7.0;
    if (fineTune) {
      canvas.drawCircle(
        Offset(thumbX, size.height / 2),
        thumbRadius + 3,
        Paint()..color = Colors.blueAccent.withValues(alpha: 0.35),
      );
    }
    canvas.drawCircle(
      Offset(thumbX + 1, size.height / 2), thumbRadius,
      Paint()..color = Colors.black26..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(thumbX, size.height / 2), thumbRadius,
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
  bool shouldRepaint(_SideSpinPainter old) =>
      old.value != value || old.fineTune != fineTune;
}
