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

  static void buildWalls(Forge2DWorld world) {
    final hh = tableH / 2;
    final segs = <List<Vector2>>[
      [Vector2(rail + _cornerGap, rail), Vector2(tableW - rail - _cornerGap, rail), Vector2(0, rail), Vector2(tableW, rail)],
      [Vector2(rail + _cornerGap, tableH - rail), Vector2(tableW - rail - _cornerGap, tableH - rail), Vector2(0, tableH - rail), Vector2(tableW, tableH - rail)],
      [Vector2(rail, rail + _cornerGap), Vector2(rail, hh - _midGap), Vector2(rail, 0), Vector2(rail, hh)],
      [Vector2(rail, hh + _midGap), Vector2(rail, tableH - rail - _cornerGap), Vector2(rail, hh), Vector2(rail, tableH)],
      [Vector2(tableW - rail, rail + _cornerGap), Vector2(tableW - rail, hh - _midGap), Vector2(tableW - rail, 0), Vector2(tableW - rail, hh)],
      [Vector2(tableW - rail, hh + _midGap), Vector2(tableW - rail, tableH - rail - _cornerGap), Vector2(tableW - rail, hh), Vector2(tableW - rail, tableH)],
    ];
    for (final seg in segs) {
      final shape = EdgeShape()
        ..set(seg[0], seg[1])
        ..vertex0.setFrom(seg[2])
        ..hasVertex0 = true
        ..vertex3.setFrom(seg[3])
        ..hasVertex3 = true;
      final bd = BodyDef()..type = BodyType.static;
      world.createBody(bd).createFixture(
          FixtureDef(shape)..friction = 1.0..restitution = 0.60);
    }
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
