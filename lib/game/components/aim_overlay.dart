import 'dart:math' show cos, sin;
import 'dart:ui';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Color;
import '../pool_game.dart';
import 'ball_component.dart';
import 'table_component.dart';

/// Renders all aiming guides in world (physics) coordinates.
class AimOverlay extends BodyComponent {
  final PoolGame game;
  AimOverlay({required this.game});

  @override
  int get priority => 5; // above table, below balls (balls default to 10)

  @override
  Body createBody() {
    return world.createBody(BodyDef()
      ..type     = BodyType.static
      ..position = Vector2.zero());
  }

  @override
  void render(Canvas canvas) {
    // Update target highlight on balls
    for (final ball in game.objectBalls) {
      ball.isCurrentTarget = (ball == game.currentTarget);
    }

    if (game.stateNotifier.value == GameState.rolling) return;

    final target = game.currentTarget;
    if (target == null) return;

    final cueBallPos = game.cueBall.body.position;
    final targetPos  = target.body.position;
    final pockets    = game.pocketPositions;

    // Use player-selected pocket, or auto-nearest as fallback.
    final selectedIdx = game.selectedPocketNotifier.value;
    final resolvedPocket = selectedIdx != null
        ? pockets[selectedIdx]
        : _nearestPocket(pockets, targetPos);
    final pocketDir = (resolvedPocket - targetPos).normalized();
    final ghostBall = targetPos - pocketDir * (BallComponent.radius * 2);

    // ── 1. All pockets as tap targets ─────────────────────────────────────
    _drawPocketTargets(canvas, pockets, resolvedPocket);

    // ── 2. Aim line: cue ball → ghost ball ────────────────────────────────
    _drawDashed(canvas, cueBallPos, ghostBall,
        Paint()..color = const Color(0x88444444)..strokeWidth = 0.04);

    // ── 3. Ghost ball ─────────────────────────────────────────────────────
    _drawGhostBall(canvas, ghostBall);

    // ── 4. Object → pocket line ───────────────────────────────────────────
    _drawObjectLine(canvas, targetPos, resolvedPocket);

    // ── 5. Predicted cue ball path (90°-rule + spin) ──────────────────────
    final predicted = game.predictedCueBallPath(3.5);
    _drawDeflectionPath(canvas, ghostBall, predicted);


    // ── 6. Good zone for next ball ────────────────────────────────────────
    final next = game.nextTarget;
    if (next != null) {
      _drawGoodZone(canvas, next.body.position, pockets, predicted);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Vector2 _nearestPocket(List<Vector2> pockets, Vector2 pos) {
    Vector2 best = pockets[0];
    double bestD = (pockets[0] - pos).length;
    for (int i = 1; i < pockets.length; i++) {
      final d = (pockets[i] - pos).length;
      if (d < bestD) { bestD = d; best = pockets[i]; }
    }
    return best;
  }

  void _drawDashed(Canvas canvas, Vector2 from, Vector2 to, Paint paint,
      {double dashLen = 0.28, double gapLen = 0.14}) {
    final dir   = (to - from).normalized();
    final total = (to - from).length;
    double covered = 0;
    bool drawing = true;
    while (covered < total) {
      final seg = drawing ? dashLen : gapLen;
      final end = (covered + seg).clamp(0.0, total);
      if (drawing) {
        canvas.drawLine(
          Offset(from.x + dir.x * covered, from.y + dir.y * covered),
          Offset(from.x + dir.x * end,     from.y + dir.y * end),
          paint,
        );
      }
      covered = end;
      drawing = !drawing;
    }
  }

  void _drawGhostBall(Canvas canvas, Vector2 pos) {
    canvas.drawCircle(Offset(pos.x, pos.y), BallComponent.radius,
        Paint()..color = const Color(0x44000000));
    canvas.drawCircle(Offset(pos.x, pos.y), BallComponent.radius,
        Paint()
          ..color = const Color(0x99000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.05);
  }

  void _drawObjectLine(Canvas canvas, Vector2 from, Vector2 to) {
    final paint = Paint()
      ..color = const Color(0xCC2ECC71)
      ..strokeWidth = 0.055;
    canvas.drawLine(Offset(from.x, from.y), Offset(to.x, to.y), paint);

    // Arrow at pocket
    final dir = (to - from).normalized();
    const arrLen = 0.3;
    const ang    = 0.4;
    final p = Path()
      ..moveTo(to.x, to.y)
      ..lineTo(to.x - dir.x * arrLen * cos(ang) + dir.y * arrLen * sin(ang),
               to.y - dir.y * arrLen * cos(ang) - dir.x * arrLen * sin(ang))
      ..moveTo(to.x, to.y)
      ..lineTo(to.x - dir.x * arrLen * cos(ang) - dir.y * arrLen * sin(ang),
               to.y - dir.y * arrLen * cos(ang) + dir.x * arrLen * sin(ang));
    canvas.drawPath(p, paint);
  }

  /// Draws all 6 pockets as tap-selectable circles.
  /// The active (resolved) pocket gets a green ring; others are dim gray rings.
  void _drawPocketTargets(Canvas canvas, List<Vector2> pockets, Vector2 active) {
    const r = TableComponent.pocketRadius * 1.6;
    for (final p in pockets) {
      final isActive = (p - active).length < 0.01;
      // Fill
      canvas.drawCircle(Offset(p.x, p.y), r,
          Paint()..color = isActive ? const Color(0x3322CC55) : const Color(0x11444444));
      // Ring
      canvas.drawCircle(Offset(p.x, p.y), r,
          Paint()
            ..color = isActive ? const Color(0xCC22CC55) : const Color(0x44888888)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isActive ? 0.08 : 0.04);
    }
  }

  void _drawDeflectionPath(Canvas canvas, Vector2 fromPos, Vector2 toPos) {
    // Dashed blue line showing predicted cue ball path after contact
    _drawDashed(
      canvas, fromPos, toPos,
      Paint()..color = const Color(0xAA2196F3)..strokeWidth = 0.05,
      dashLen: 0.2, gapLen: 0.1,
    );
    // Arrow tip
    final dir = (toPos - fromPos).normalized();
    final tip = toPos;
    const arrLen = 0.25;
    const ang    = 0.45;
    canvas.drawPath(
      Path()
        ..moveTo(tip.x, tip.y)
        ..lineTo(tip.x - dir.x * arrLen * cos(ang) + dir.y * arrLen * sin(ang),
                 tip.y - dir.y * arrLen * cos(ang) - dir.x * arrLen * sin(ang))
        ..moveTo(tip.x, tip.y)
        ..lineTo(tip.x - dir.x * arrLen * cos(ang) - dir.y * arrLen * sin(ang),
                 tip.y - dir.y * arrLen * cos(ang) + dir.x * arrLen * sin(ang)),
      Paint()..color = const Color(0xAA2196F3)..strokeWidth = 0.05,
    );
  }

  /// The "good zone" is the ideal area where the cue ball should land
  /// so the player has a clear shot at the NEXT target ball.
  void _drawGoodZone(
    Canvas canvas,
    Vector2 nextBallPos,
    List<Vector2> pockets,
    Vector2 predictedCuePos, // where cue ball is heading this shot
  ) {
    final nextPocket = _nearestPocket(pockets, nextBallPos);
    final nextGhost  = nextBallPos -
        (nextPocket - nextBallPos).normalized() * (BallComponent.radius * 2);

    const zoneRadius = 1.3; // world units

    // Determine if predicted landing is inside the zone
    final dist   = (predictedCuePos - nextGhost).length;
    final inside = dist < zoneRadius;

    // Zone circle — color depends on predicted accuracy
    final fillColor   = inside ? const Color(0x2200CC44) : const Color(0x22FF6600);
    final strokeColor = inside ? const Color(0x9900CC44) : const Color(0x99FF6600);

    canvas.drawCircle(Offset(nextGhost.x, nextGhost.y), zoneRadius,
        Paint()..color = fillColor);
    canvas.drawCircle(Offset(nextGhost.x, nextGhost.y), zoneRadius,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.07);

    // Center crosshair
    final cx = nextGhost.x;
    final cy = nextGhost.y;
    const cr = 0.22;
    final xPaint = Paint()..color = strokeColor..strokeWidth = 0.06;
    canvas.drawLine(Offset(cx - cr, cy), Offset(cx + cr, cy), xPaint);
    canvas.drawLine(Offset(cx, cy - cr), Offset(cx, cy + cr), xPaint);
    canvas.drawCircle(Offset(cx, cy), 0.08, Paint()..color = strokeColor);

    // Dashed line from next ball to its pocket (shows the shot opportunity)
    _drawDashed(
      canvas, nextBallPos, nextPocket,
      Paint()
        ..color = (inside ? const Color(0x6600CC44) : const Color(0x66FF6600))
        ..strokeWidth = 0.04,
      dashLen: 0.2, gapLen: 0.1,
    );
  }
}
