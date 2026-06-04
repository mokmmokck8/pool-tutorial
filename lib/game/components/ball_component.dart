import 'dart:ui';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Alignment, Color, Colors, RadialGradient;

class BallComponent extends BodyComponent {
  static const double radius = 0.30;

  final Vector2 startPosition;
  final Color color;
  final int number;
  final bool isCue;

  bool inPlay = true;
  /// Set by AimOverlay each frame to show target highlight
  bool isCurrentTarget = false;

  BallComponent({
    required Vector2 position,
    required this.color,
    required this.number,
    this.isCue = false,
  }) : startPosition = position.clone();

  // ── Tunable physics constants ─────────────────────────────────────────────
  /// Felt rolling resistance.  ↑ = ball stops sooner.  Range: 1.5–3.0
  static const double kLinearDamping  = 2.0;
  /// Spin decay rate.  ↓ = spin persists longer (better English/rail effect).  Range: 0.8–2.5
  static const double kAngularDamping = 1.4;
  /// Ball-to-ball elasticity.  ↑ = more energy kept on collision.  Range: 0.85–0.97
  static const double kRestitution    = 0.92;
  /// Ball surface friction.  Keep very low so ball-ball collisions follow the
  /// clean 90-degree rule (no tangential force bleed).  Range: 0.0–0.08
  static const double kFriction       = 0.02;

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type           = BodyType.dynamic
      ..position       = startPosition
      ..linearDamping  = kLinearDamping
      ..angularDamping = kAngularDamping
      ..bullet         = true;

    final shape = CircleShape()..radius = radius;
    return world.createBody(bodyDef)
      ..createFixture(FixtureDef(shape)
        ..density     = 1.0
        ..friction    = kFriction
        ..restitution = kRestitution);
  }

  void pocket() {
    inPlay = false;
    isCurrentTarget = false;
    body.setType(BodyType.static);
    body.linearVelocity  = Vector2.zero();
    body.angularVelocity = 0;
    body.setTransform(Vector2(-100, -100), 0);
  }

  @override
  void render(Canvas canvas) {
    if (!inPlay) return;

    // ── Target highlight ring ─────────────────────────────────────────────
    if (isCurrentTarget) {
      canvas.drawCircle(
        Offset.zero, radius * 1.55,
        Paint()
          ..color = const Color(0x552ECC71)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset.zero, radius * 1.55,
        Paint()
          ..color = const Color(0xCC2ECC71)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.06,
      );
    }

    // ── Shadow ────────────────────────────────────────────────────────────
    canvas.drawCircle(
      const Offset(0.07, 0.09), radius,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.12),
    );

    // ── Ball body ─────────────────────────────────────────────────────────
    final gradient = isCue
        ? RadialGradient(
            center: const Alignment(-0.4, -0.4),
            radius: 1.0,
            colors: const [Colors.white, Color(0xFFE0E0E0), Color(0xFFAAAAAA)],
            stops: const [0.0, 0.5, 1.0],
          )
        : RadialGradient(
            center: const Alignment(-0.4, -0.4),
            radius: 1.0,
            colors: [
              Color.lerp(Colors.white, color, 0.25)!,
              color,
              Color.lerp(color, Colors.black, 0.5)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          );

    canvas.drawCircle(
      Offset.zero, radius,
      Paint()..shader = gradient.createShader(
          Rect.fromCircle(center: Offset.zero, radius: radius)),
    );

    // ── Specular ──────────────────────────────────────────────────────────
    canvas.drawCircle(
      Offset(-radius * 0.32, -radius * 0.32), radius * 0.22,
      Paint()
        ..color = const Color(0xBBFFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.05),
    );

    // ── Ball number ───────────────────────────────────────────────────────
    if (!isCue) {
      // Small white dot as number hint (full text rendering requires ParagraphBuilder)
      // The number is shown in the UI sequence bar instead
    }
  }
}
