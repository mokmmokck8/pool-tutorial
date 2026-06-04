import 'dart:math' show cos, sin;
import 'dart:ui' show Canvas, Offset, Paint, PaintingStyle, Path, Color, StrokeCap;
import 'package:flame_forge2d/flame_forge2d.dart';
import '../components/ball_component.dart';
import 'lab_game.dart';

/// Draws the static aiming guides while in the aiming state.
class LabAimOverlay extends BodyComponent {
  final LabGame game;
  LabAimOverlay({required this.game});

  @override
  int get priority => 5;

  @override
  Body createBody() => world.createBody(BodyDef()
    ..type = BodyType.static
    ..position = Vector2.zero());

  @override
  void render(Canvas canvas) {
    if (!game.isLoaded) return;

    // Trail: visible while rolling and after the ball stops
    if (game.state == LabState.rolling || game.state == LabState.done) {
      _drawTrail(canvas, game.cueTrail);
    }

    if (game.state != LabState.aiming) return;

    final cueBallPos = game.cueBall.body.position;
    final targetPos = game.targetBall.body.position;
    final pocket = LabGame.targetPocket;

    final pocketDir = (pocket - targetPos).normalized();
    final ghostBall = targetPos - pocketDir * (BallComponent.radius * 2);

    // Aim line: cue → ghost ball
    _drawDashed(canvas, cueBallPos, ghostBall,
        Paint()..color = const Color(0x88444444)..strokeWidth = 0.04);

    // Ghost ball outline
    canvas.drawCircle(Offset(ghostBall.x, ghostBall.y), BallComponent.radius,
        Paint()..color = const Color(0x33000000));
    canvas.drawCircle(
      Offset(ghostBall.x, ghostBall.y),
      BallComponent.radius,
      Paint()
        ..color = const Color(0x88000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05,
    );

    // Target → pocket guide line with arrowhead
    final linePaint = Paint()
      ..color = const Color(0xCC2ECC71)
      ..strokeWidth = 0.055;
    canvas.drawLine(
        Offset(targetPos.x, targetPos.y), Offset(pocket.x, pocket.y), linePaint);
    _drawArrow(canvas, pocket, pocketDir, linePaint);
  }

  void _drawArrow(Canvas canvas, Vector2 tip, Vector2 dir, Paint paint) {
    const arrLen = 0.30;
    const ang = 0.40;
    canvas.drawPath(
      Path()
        ..moveTo(tip.x, tip.y)
        ..lineTo(tip.x - dir.x * arrLen * cos(ang) + dir.y * arrLen * sin(ang),
                 tip.y - dir.y * arrLen * cos(ang) - dir.x * arrLen * sin(ang))
        ..moveTo(tip.x, tip.y)
        ..lineTo(tip.x - dir.x * arrLen * cos(ang) - dir.y * arrLen * sin(ang),
                 tip.y - dir.y * arrLen * cos(ang) + dir.x * arrLen * sin(ang)),
      paint,
    );
  }

  void _drawTrail(Canvas canvas, List<Vector2> trail) {
    if (trail.length < 2) return;
    final n = trail.length;
    for (int i = 0; i < n - 1; i++) {
      // Fade: older segments are more transparent, newest are bright
      final t = i / (n - 2).clamp(1, n);
      final alpha = (60 + (t * 170)).round().clamp(0, 255);
      final paint = Paint()
        ..color = Color.fromARGB(alpha, 255, 255, 255)
        ..strokeWidth = 0.06
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      _drawDashed(canvas, trail[i], trail[i + 1], paint,
          dashLen: 0.22, gapLen: 0.14);
    }
  }

  void _drawDashed(Canvas canvas, Vector2 from, Vector2 to, Paint paint,
      {double dashLen = 0.28, double gapLen = 0.14}) {
    final dir = (to - from).normalized();
    final total = (to - from).length;
    double covered = 0;
    bool drawing = true;
    while (covered < total) {
      final seg = drawing ? dashLen : gapLen;
      final end = (covered + seg).clamp(0.0, total);
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
}
