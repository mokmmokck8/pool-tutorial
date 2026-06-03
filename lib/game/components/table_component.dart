import 'dart:ui';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Color, Alignment, LinearGradient;

/// Renders the pool table in physics world coordinates (BodyComponent).
/// Uses a static body at origin; canvas is already in world space.
class TableComponent extends BodyComponent {
  final double tableWidth;
  final double tableHeight;
  final List<Vector2> pocketPositions;

  static const double pocketRadius = 0.55;
  static const double railThickness = 0.5;

  TableComponent({
    required this.tableWidth,
    required this.tableHeight,
    required this.pocketPositions,
  });

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();
    // No fixture needed — walls are created by PoolGame
    return world.createBody(bodyDef);
  }

  @override
  void render(Canvas canvas) {
    _drawTable(canvas);
    _drawPockets(canvas);
    _drawRails(canvas);
  }

  void _drawTable(Canvas canvas) {
    final feltPaint = Paint()
      ..shader = LinearGradient(
        colors: const [Color(0xFF1B6B3A), Color(0xFF1A5C32), Color(0xFF1B6B3A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, tableWidth, tableHeight));
    canvas.drawRect(Rect.fromLTWH(0, 0, tableWidth, tableHeight), feltPaint);

    // Felt texture
    final linePaint = Paint()
      ..color = const Color(0xFF1E7A41).withOpacity(0.3)
      ..strokeWidth = 0.015;
    for (double y = 0; y < tableHeight; y += 0.4) {
      canvas.drawLine(Offset(0, y), Offset(tableWidth, y), linePaint);
    }

    // Center and baulk lines
    final markPaint = Paint()
      ..color = const Color(0xFF2ECC71).withOpacity(0.15)
      ..strokeWidth = 0.03;
    canvas.drawLine(Offset(tableWidth / 2, railThickness),
        Offset(tableWidth / 2, tableHeight - railThickness), markPaint);
    canvas.drawLine(Offset(tableWidth * 0.25, railThickness),
        Offset(tableWidth * 0.25, tableHeight - railThickness), markPaint);

    // Baulk D arc
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(tableWidth * 0.25, tableHeight / 2),
          radius: tableHeight * 0.18),
      -1.5708, 3.1416, false,
      Paint()
        ..color = const Color(0xFF2ECC71).withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03,
    );
  }

  void _drawPockets(Canvas canvas) {
    for (final pos in pocketPositions) {
      final o = Offset(pos.x, pos.y);
      canvas.drawCircle(o, pocketRadius, Paint()..color = const Color(0xFF080808));
      canvas.drawCircle(
        o, pocketRadius * 0.8,
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.12),
      );
      canvas.drawCircle(
        o, pocketRadius,
        Paint()
          ..color = const Color(0xFF4A3520)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.06,
      );
    }
  }

  void _drawRails(Canvas canvas) {
    final railPaint = Paint()..color = const Color(0xFF5C3D1E);
    canvas.drawRect(Rect.fromLTWH(0, 0, tableWidth, railThickness), railPaint);
    canvas.drawRect(
        Rect.fromLTWH(0, tableHeight - railThickness, tableWidth, railThickness), railPaint);
    canvas.drawRect(Rect.fromLTWH(0, 0, railThickness, tableHeight), railPaint);
    canvas.drawRect(
        Rect.fromLTWH(tableWidth - railThickness, 0, railThickness, tableHeight), railPaint);

    final hlPaint = Paint()
      ..color = const Color(0xFF7A5230)
      ..strokeWidth = 0.04;
    canvas.drawLine(
        const Offset(0, railThickness), Offset(tableWidth, railThickness), hlPaint);
    canvas.drawLine(
        Offset(0, tableHeight - railThickness),
        Offset(tableWidth, tableHeight - railThickness),
        hlPaint);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, tableWidth, tableHeight),
      Paint()
        ..color = const Color(0xFF2C1A08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.12,
    );
  }
}
