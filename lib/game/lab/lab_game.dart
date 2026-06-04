import 'dart:math' show atan2, cos, min, pi, sin, sqrt;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Colors, Color, ValueNotifier;
import '../components/ball_component.dart';
import '../components/table_component.dart';
import 'lab_overlay.dart';
import 'lab_physics.dart';

enum LabState { aiming, rolling, done }

class LabGame extends Forge2DGame {
  LabGame() : super(gravity: Vector2.zero());

  @override
  Color backgroundColor() => const Color(0xFFFFFFFF);

  // ── Public notifiers ─────────────────────────────────────────────────────
  final stateNotifier = ValueNotifier<LabState>(LabState.aiming);

  // ── Ball references ───────────────────────────────────────────────────────
  late BallComponent cueBall;
  late BallComponent targetBall;

  // ── Table geometry ────────────────────────────────────────────────────────
  static const double tableW = LabTablePhysics.tableW;
  static const double tableH = LabTablePhysics.tableH;
  static const double rail   = LabTablePhysics.rail;

  // Fixed layout: target ball in upper-left half, pocket on mid-right side
  static Vector2 get targetPocket => Vector2(tableW, tableH / 2);
  static Vector2 get _targetPos   => Vector2(tableW * 0.35, tableH * 0.28);
  static const double _cueDist    = 3.5;

  final List<Vector2> _pocketPositions = [];
  final Map<BallComponent, Vector2> _prevPositions = {};

  // ── Shot state ────────────────────────────────────────────────────────────
  bool _gameLoaded    = false;
  bool _ballsMoving   = false;
  bool _collisionDone = false;
  double _lastPower   = 0.5;
  Vector2 _prevCueVel = Vector2.zero();
  Vector2 _shotDir    = Vector2(1, 0);

  // ── Camera ────────────────────────────────────────────────────────────────
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    const pad = 1.08;
    camera.viewfinder.zoom =
        min(size.x / (tableW * pad), size.y / (tableH * pad));
    camera.viewfinder.position = Vector2(tableW / 2, tableH / 2);
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _pocketPositions.addAll(LabTablePhysics.defaultPocketPositions());
    LabTablePhysics.buildWalls(world);
    LabTablePhysics.buildPocketSensors(world, _pocketPositions);

    await world.add(TableComponent(
      tableWidth: tableW,
      tableHeight: tableH,
      pocketPositions: _pocketPositions,
    ));

    await _spawnBalls(0);

    await world.add(LabAimOverlay(game: this));
    _gameLoaded = true;
  }

  Future<void> _spawnBalls(double cutAngleDeg) async {
    targetBall = BallComponent(
      position: _targetPos,
      color: const Color(0xFFE74C3C),
      number: 1,
    );
    await world.add(targetBall);

    cueBall = BallComponent(
      position: _clampedCuePos(cutAngleDeg),
      color: Colors.white,
      number: 0,
      isCue: true,
    );
    await world.add(cueBall);

    // Prevent Box2D from handling ball-ball collision — we do it manually.
    _disableBallCollision();
  }

  void _disableBallCollision() {
    final labFilter = Filter()..groupIndex = -1;
    for (final ball in [cueBall, targetBall]) {
      for (final fixture in ball.body.fixtures) {
        fixture.filterData = labFilter;
      }
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────
  LabState get state => stateNotifier.value;
  bool get isLoaded  => _gameLoaded;

  /// Reposition cue ball for the given cut angle and reset both balls.
  void setCutAngle(double degrees) {
    if (!_gameLoaded) return;
    final newPos = _clampedCuePos(degrees);

    for (final ball in [cueBall, targetBall]) {
      // pocket() sets body to static — restore to dynamic so it can move again
      if (ball.body.bodyType != BodyType.dynamic) {
        ball.body.setType(BodyType.dynamic);
      }
      ball.body.linearVelocity  = Vector2.zero();
      ball.body.angularVelocity = 0;
      ball.inPlay = true;
    }
    cueBall.body.setTransform(newPos, 0);
    targetBall.body.setTransform(_targetPos, 0);

    _collisionDone = false;
    _ballsMoving   = false;
    stateNotifier.value = LabState.aiming;
  }

  void shoot({required double power}) {
    if (stateNotifier.value != LabState.aiming) return;
    _lastPower     = power;
    _collisionDone = false;

    final angle = _autoAimAngle;
    _shotDir = Vector2(cos(angle), sin(angle));

    const kMaxForce = 80.0;
    cueBall.body.applyLinearImpulse(_shotDir * (power * power * kMaxForce));

    stateNotifier.value = LabState.rolling;
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────
  double get _autoAimAngle {
    final ghost = _ghostBall(targetBall.body.position, targetPocket);
    final diff  = ghost - cueBall.body.position;
    return atan2(diff.y, diff.x);
  }

  Vector2 _ghostBall(Vector2 obj, Vector2 pocket) {
    final dir = (pocket - obj).normalized();
    return obj - dir * (BallComponent.radius * 2);
  }

  Vector2 _cueBallPos(double cutAngleDeg) {
    final toP = (targetPocket - _targetPos)..normalize();
    final rad = cutAngleDeg * pi / 180.0;
    final incomingDir = Vector2(
      toP.x * cos(rad) - toP.y * sin(rad),
      toP.x * sin(rad) + toP.y * cos(rad),
    );
    return _targetPos - incomingDir * _cueDist;
  }

  Vector2 _clampedCuePos(double cutAngleDeg) {
    final pos = _cueBallPos(cutAngleDeg);
    final minX = rail + BallComponent.radius;
    final maxX = tableW - rail - BallComponent.radius;
    final minY = rail + BallComponent.radius;
    final maxY = tableH - rail - BallComponent.radius;
    return Vector2(pos.x.clamp(minX, maxX), pos.y.clamp(minY, maxY));
  }

  // ── Update loop ───────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    if (cueBall.isLoaded)   _prevPositions[cueBall]    = cueBall.body.position.clone();
    if (targetBall.isLoaded) _prevPositions[targetBall] = targetBall.body.position.clone();
    _prevCueVel = cueBall.isLoaded ? cueBall.body.linearVelocity.clone() : Vector2.zero();

    super.update(dt);

    _handleManualCollision();
    _checkPocketCollisions();
    _trackMotionState();
  }

  // ── Manual ball-ball collision ────────────────────────────────────────────
  //
  // Physics model (centre-ball hit only — lab has no spin):
  //
  //   • Standard elastic collision: target gets the normal velocity component,
  //     cue ball keeps the tangential component (90-degree rule).
  //
  //   • Forward "rolling follow" effect:
  //     At low power the cue ball has time to develop natural forward roll
  //     before contact, so it follows a little.  At high power it is still
  //     sliding → stops dead after transfer.
  //
  //     followFraction = clamp(1 − power / kFollowThreshold, 0, 1)
  //     power ≥ kFollowThreshold → 0 (pure stun, ball stops)
  //     power = 0               → 1 (maximum follow)
  //
  static const double kFollowThreshold = 0.65;
  static const double kFollowScale     = 0.45; // limits max forward carry

  void _handleManualCollision() {
    if (_collisionDone) return;
    if (stateNotifier.value != LabState.rolling) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) return;
    if (!targetBall.isLoaded || !targetBall.inPlay) return;

    final prevPos   = _prevPositions[cueBall] ?? cueBall.body.position;
    final currPos   = cueBall.body.position;
    final targetPos = targetBall.body.position;
    const collR     = BallComponent.radius * 2.0;

    // CCD: find the earliest point along prevPos→currPos within collR of targetPos
    final contactPt = _sweepContact(prevPos, currPos, targetPos, collR);
    if (contactPt == null) return;

    _collisionDone = true;

    // Collision normal: from contact point toward target center
    final normal = (targetPos - contactPt).normalized();
    final vCue   = _prevCueVel.clone();
    final normalComp = vCue.dot(normal);
    if (normalComp <= 0) return; // not approaching

    final tangVel = vCue - normal * normalComp;

    // Place cue ball exactly at the contact point (prevents sticking)
    cueBall.body.setTransform(contactPt, 0);

    // Target ball: full normal component (elastic, equal mass)
    targetBall.body.linearVelocity = normal * normalComp;

    // Cue ball: tangential only + rolling follow
    final followFraction =
        (1.0 - _lastPower / kFollowThreshold).clamp(0.0, 1.0);
    cueBall.body.linearVelocity =
        tangVel + normal * (normalComp * followFraction * kFollowScale);
  }

  /// Returns the first point on segment [from→to] that is within [r] of [center],
  /// or null if the segment never enters that radius.
  Vector2? _sweepContact(Vector2 from, Vector2 to, Vector2 center, double r) {
    final d = to - from;
    final f = from - center;
    final a = d.dot(d);
    if (a < 1e-12) return null; // zero-length segment
    final b = 2 * f.dot(d);
    final c = f.dot(f) - r * r;
    final disc = b * b - 4 * a * c;
    if (disc < 0) return null;
    final t = (-b - sqrt(disc)) / (2 * a);
    if (t < 0 || t > 1) {
      // Already overlapping at frame start? Use t=0 as fallback.
      if (f.dot(f) <= r * r) return from.clone();
      return null;
    }
    return from + d * t;
  }

  // ── Pocket detection ──────────────────────────────────────────────────────
  void _checkPocketCollisions() {
    if (!cueBall.isLoaded) return;
    const detectR = LabTablePhysics.pocketR + BallComponent.radius;

    bool inPocket(BallComponent ball) {
      final curr = ball.body.position;
      final prev = _prevPositions[ball] ?? curr;
      return _pocketPositions.any(
          (p) => LabTablePhysics.segmentHitsCircle(prev, curr, p, detectR));
    }

    for (final ball in [cueBall, targetBall]) {
      if (ball.inPlay && ball.isLoaded && inPocket(ball)) ball.pocket();
    }
  }

  // ── Motion state tracking ─────────────────────────────────────────────────
  bool get _anyMoving => [cueBall, targetBall]
      .any((b) => b.inPlay && b.body.linearVelocity.length2 > 0.01);

  void _trackMotionState() {
    final moving = _anyMoving;
    if (_ballsMoving && !moving) {
      _ballsMoving = false;
      if (stateNotifier.value == LabState.rolling) {
        stateNotifier.value = LabState.done;
      }
    } else if (moving) {
      _ballsMoving = true;
    }
  }
}
