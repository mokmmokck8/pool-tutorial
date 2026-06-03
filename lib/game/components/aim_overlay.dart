import 'dart:math';
import 'dart:ui';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Color;
import '../pool_game.dart';
import 'ball_component.dart';
import 'table_component.dart';

/// Renders aiming guides in physics world coordinates.
class AimOverlay extends BodyComponent {
  final PoolGame game;

  AimOverlay({required this.game});

  @override
  int get priority => 5; // above table (0), below balls (default 10)

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();
    return world.createBody(bodyDef);
  }

  @override
  void render(Canvas canvas) {
    if (game.stateNotifier.value == GameState.rolling) return;

    final target = game.currentTarget;
    if (target == null) return;

    final cueBallPos = game.cueBall.body.position;
    final targetPos = target.body.position;
    final pockets = game.pocketPositions;

    final nearestPocket = _nearestPocket(pockets, targetPos);

    final pocketDir = (nearestPocket - targetPos).normalized();
    final ghostBall = targetPos - pocketDir * (BallComponent.radius * 2);

    _drawPocketZone(canvas, nearestPocket);
    _drawPositionZone(canvas, targetPos, pockets);
    _drawAimLine(canvas, cueBallPos, ghostBall);
    _drawGhostBall(canvas, ghostBall);
    _drawObjectLine(canvas, targetPos, nearestPocket);
    _drawDeflectionLine(canvas, cueBallPos, ghostBall);
  }

  void _drawDashedLine(
    Canvas canvas,
    Vector2 from,
    Vector2 to,
    Paint paint, {
    double dashLen = 0.3,
    double gapLen = 0.15,
  }) {
    final dir = (to - from).normalized();
    final total = (to - from).length;
    double covered = 0;
    bool drawing = true;
    while (covered < total) {
      final segLen = drawing ? dashLen : gapLen;
      final end = (covered + segLen).clamp(0.0, total);
      if (drawing) {
        canvas.drawLine(
          Offset(from.x + dir.x * covered, from.y + dir.y * covered),
          Offset(from.x + dir.x * end, from.y + dir.y * end),
          paint,
        );
      }
      covered = end;
      drawing = !drawing;
    }
  }

  void _drawAimLine(Canvas canvas, Vector2 from, Vector2 to) {
    _drawDashedLine(
      canvas, from, to,
      Paint()
        ..color = const Color(0xAAFFFFFF)
        ..strokeWidth = 0.03,
    );
  }

  void _drawGhostBall(Canvas canvas, Vector2 pos) {
    canvas.drawCircle(
      Offset(pos.x, pos.y), BallComponent.radius,
      Paint()..color = const Color(0x44FFFFFF),
    );
    canvas.drawCircle(
      Offset(pos.x, pos.y), BallComponent.radius,
      Paint()
        ..color = const Color(0x88FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.04,
    );
  }

  void _drawObjectLine(Canvas canvas, Vector2 from, Vector2 to) {
    final paint = Paint()
      ..color = const Color(0xCC2ECC71)
      ..strokeWidth = 0.05;
    canvas.drawLine(Offset(from.x, from.y), Offset(to.x, to.y), paint);

    // Arrow
    final dir = (to - from).normalized();
    const arrLen = 0.28;
    const ang = 0.4;
    final p = Path()
      ..moveTo(to.x, to.y)
      ..lineTo(
        to.x - dir.x * arrLen * cos(ang) + dir.y * arrLen * sin(ang),
        to.y - dir.y * arrLen * cos(ang) - dir.x * arrLen * sin(ang),
      )
      ..moveTo(to.x, to.y)
      ..lineTo(
        to.x - dir.x * arrLen * cos(ang) - dir.y * arrLen * sin(ang),
        to.y - dir.y * arrLen * cos(ang) + dir.x * arrLen * sin(ang),
      );
    canvas.drawPath(p, paint);
  }

  void _drawDeflectionLine(Canvas canvas, Vector2 cueBall, Vector2 ghost) {
    final cueDir = (ghost - cueBall).normalized();
    final perp = Vector2(-cueDir.y, cueDir.x);
    final endPos = ghost + perp * 4.0;

    _drawDashedLine(
      canvas,
      ghost,
      endPos,
      Paint()
        ..color = const Color(0x882196F3)
        ..strokeWidth = 0.04,
      dashLen: 0.2,
      gapLen: 0.1,
    );
  }

  void _drawPocketZone(Canvas canvas, Vector2 pocket) {
    canvas.drawCircle(
      Offset(pocket.x, pocket.y),
      TableComponent.pocketRadius * 1.6,
      Paint()..color = const Color(0x1A2ECC71),
    );
    canvas.drawCircle(
      Offset(pocket.x, pocket.y),
      TableComponent.pocketRadius * 1.6,
      Paint()
        ..color = const Color(0x552ECC71)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05,
    );
  }

  Vector2 _nearestPocket(List<Vector2> pockets, Vector2 pos) {
    Vector2 best = pockets[0];
    double bestDist = (pockets[0] - pos).length;
    for (int i = 1; i < pockets.length; i++) {
      final d = (pockets[i] - pos).length;
      if (d < bestDist) { bestDist = d; best = pockets[i]; }
    }
    return best;
  }

  void _drawPositionZone(Canvas canvas, Vector2 currentTarget, List<Vector2> pockets) {
    final alive = game.objectBalls.where((b) => b.inPlay).toList();
    if (alive.length < 2) return;

    final nextPos = alive[1].body.position;
    final nextPocket = _nearestPocket(pockets, nextPos);
    final ghostNext = nextPos - (nextPocket - nextPos).normalized() * (BallComponent.radius * 2);

    canvas.drawCircle(
      Offset(ghostNext.x, ghostNext.y), 1.2,
      Paint()..color = const Color(0x15F39C12),
    );
    canvas.drawCircle(
      Offset(ghostNext.x, ghostNext.y), 1.2,
      Paint()
        ..color = const Color(0x77F39C12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06,
    );
  }
}
