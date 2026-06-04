import 'dart:math' show sqrt;
import 'package:flame_forge2d/flame_forge2d.dart';
import '../components/table_component.dart';

/// Static utilities for building table walls and pocket sensors,
/// and for geometric collision helpers.
class LabTablePhysics {
  static const double tableW = 11.0;
  static const double tableH = 22.0;
  static const double rail = TableComponent.railThickness;
  static const double pocketR = TableComponent.pocketRadius;
  static const double _cornerGap = 1.0;
  static const double _midGap = 0.9;

  // Thickness of the invisible wall slab (extends outside the table).
  // Must be >> ball-radius so CCD always finds it even at max speed.
  static const double _wallThick = 10.0;

  static void buildWalls(Forge2DWorld world) {
    final hh = tableH / 2;

    // Each wall is a solid PolygonShape slab.  The inner face sits exactly at
    // the table edge (0 / tableW / tableH); the outer face goes _wallThick
    // units outside, giving CCD a large surface to intercept fast balls.
    //
    // Each entry: [x, y, halfWidth, halfHeight, centerX, centerY]
    // We build each segment as its own body positioned at the slab's centre.
    //
    // Horizontal slabs (top / bottom) ──────────────────────────────────────
    //   full width minus corner gaps, thickness in Y
    // Vertical slabs (left / right, split at mid-pocket) ───────────────────
    //   thickness in X, height from corner gap to mid-gap

    void addSlab(double cx, double cy, double hw, double hh2) {
      final shape = PolygonShape()..setAsBoxXY(hw, hh2);
      final bd = BodyDef()..type = BodyType.static..position = Vector2(cx, cy);
      world.createBody(bd).createFixture(
          FixtureDef(shape)..friction = 0.4..restitution = 0.60);
    }

    final t = _wallThick;

    // ── Top rail (inner face at y=0, slab extends upward) ─────────────────
    final topW = (tableW - 2 * _cornerGap) / 2;
    addSlab(tableW / 2, -t / 2, topW, t / 2);

    // ── Bottom rail (inner face at y=tableH, slab extends downward) ───────
    addSlab(tableW / 2, tableH + t / 2, topW, t / 2);

    // ── Left rail — top half (inner face at x=0, slab extends left) ───────
    final leftTopH = (hh - _midGap - _cornerGap) / 2;
    addSlab(-t / 2, _cornerGap + leftTopH, t / 2, leftTopH);

    // ── Left rail — bottom half ────────────────────────────────────────────
    final leftBotH = (tableH - _cornerGap - (hh + _midGap)) / 2;
    addSlab(-t / 2, hh + _midGap + leftBotH, t / 2, leftBotH);

    // ── Right rail — top half ──────────────────────────────────────────────
    addSlab(tableW + t / 2, _cornerGap + leftTopH, t / 2, leftTopH);

    // ── Right rail — bottom half ───────────────────────────────────────────
    addSlab(tableW + t / 2, hh + _midGap + leftBotH, t / 2, leftBotH);
  }

  static void buildPocketSensors(Forge2DWorld world, List<Vector2> positions) {
    for (final pos in positions) {
      final bd = BodyDef()..type = BodyType.static..position = pos;
      world.createBody(bd).createFixture(
          FixtureDef(CircleShape()..radius = pocketR)..isSensor = true);
    }
  }

  static List<Vector2> defaultPocketPositions() {
    final hh = tableH / 2;
    return [
      Vector2(0, 0),
      Vector2(tableW, 0),
      Vector2(0, hh),
      Vector2(tableW, hh),
      Vector2(0, tableH),
      Vector2(tableW, tableH),
    ];
  }

  static bool segmentHitsCircle(Vector2 a, Vector2 b, Vector2 c, double r) {
    final d = b - a;
    final f = a - c;
    final aq = d.dot(d);
    if (aq < 1e-10) return f.dot(f) < r * r;
    final bq = 2 * f.dot(d);
    final cq = f.dot(f) - r * r;
    final disc = bq * bq - 4 * aq * cq;
    if (disc < 0) return false;
    final s = sqrt(disc);
    final t1 = (-bq - s) / (2 * aq);
    final t2 = (-bq + s) / (2 * aq);
    return (t1 >= 0 && t1 <= 1) || (t2 >= 0 && t2 <= 1) || (t1 < 0 && t2 > 1);
  }
}
