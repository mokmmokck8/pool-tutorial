import 'dart:ui';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Alignment, Color, Colors, RadialGradient;

class BallComponent extends BodyComponent {
  static const double radius = 0.28;

  final Vector2 startPosition;
  final Color color;
  final int number;
  final bool isCue;

  bool inPlay = true;

  BallComponent({
    required Vector2 position,
    required this.color,
    required this.number,
    this.isCue = false,
  }) : startPosition = position.clone();

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = startPosition
      ..linearDamping = 1.3
      ..angularDamping = 2.2
      ..bullet = true;

    final shape = CircleShape()..radius = radius;
    final fixtureDef = FixtureDef(shape)
      ..density = 1.0
      ..friction = 0.3
      ..restitution = 0.75;

    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  void pocket() {
    inPlay = false;
    body.setType(BodyType.static);
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0;
    body.setTransform(Vector2(-100, -100), 0);
  }

  @override
  void render(Canvas canvas) {
    if (!inPlay) return;

    // In BodyComponent, canvas is already transformed to body center.
    const center = Offset.zero;

    // Shadow
    canvas.drawCircle(
      const Offset(0.08, 0.1),
      radius,
      Paint()
        ..color = const Color(0x44000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.12),
    );

    // Ball with radial gradient
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          radius: 1.0,
          colors: [
            Color.lerp(Colors.white, color, 0.25)!,
            color,
            Color.lerp(color, Colors.black, 0.5)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );

    // Specular
    canvas.drawCircle(
      Offset(-radius * 0.32, -radius * 0.32),
      radius * 0.22,
      Paint()
        ..color = const Color(0xBBFFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.05),
    );
  }
}
