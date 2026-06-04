import 'dart:ui';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Alignment, Color, LinearGradient, RRect, Radius;

/// Renders a minimalist portrait pool table:
///   - light-gray felt, rounded corners, NO wooden frame
///   - white circles at pocket positions (showing background through)
class TableComponent extends BodyComponent {
  final double tableWidth;
  final double tableHeight;
  final List<Vector2> pocketPositions;

  /// Physics offset for walls (kept small so pockets sit at edges).
  static const double railThickness = 0.25;
  static const double pocketRadius  = 0.50;

  static const _felt   = Color(0xFFCFD8DC); // blue-gray felt
  static const _feltDk = Color(0xFFB0BEC5); // slightly darker for subtle gradient
  static const _hole   = Color(0xFFFFFFFF); // white = shows background

  TableComponent({
    required this.tableWidth,
    required this.tableHeight,
    required this.pocketPositions,
  });

  @override
  int get priority => 0; // drawn first (below balls and overlay)

  @override
  Body createBody() {
    final bd = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();
    return world.createBody(bd); // no fixtures — walls created by PoolGame
  }

  @override
  void render(Canvas canvas) {
    _drawFelt(canvas);
    _drawPockets(canvas);
  }

  void _drawFelt(Canvas canvas) {
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, tableWidth, tableHeight),
      const Radius.circular(0.6),
    );

    // Subtle linear gradient to give depth
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [_felt, _feltDk],
        ).createShader(Rect.fromLTWH(0, 0, tableWidth, tableHeight)),
    );

    // Very light inner glow so table reads as a surface
    canvas.drawRRect(
      rr,
      Paint()
        ..color = const Color(0x0CFFFFFF)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawPockets(Canvas canvas) {
    for (final pos in pocketPositions) {
      canvas.drawCircle(Offset(pos.x, pos.y), pocketRadius, Paint()..color = _hole);
    }
  }
}
