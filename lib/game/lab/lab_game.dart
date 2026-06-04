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

  // Fixed layout: target ball in centre, pocket at bottom-right corner
  static Vector2 get targetPocket => Vector2(tableW, tableH);
  static Vector2 get _targetPos   => Vector2(tableW * 0.50, tableH * 0.50);
  static const double _cueDist    = 6.0;

  final List<Vector2> _pocketPositions = [];
  final Map<BallComponent, Vector2> _prevPositions = {};

  // ── Shot state ────────────────────────────────────────────────────────────
  bool _gameLoaded        = false;
  bool _ballsMoving       = false;
  bool _ballsContacting   = false; // true while the two balls are touching
  bool _firstCollisionDone = false; // follow/spin only applies on the first hit
  double _lastPower       = 0.5;
  double _lastSpin        = 0.0;  // -1 back spin … 0 centre … +1 top spin
  Vector2 _prevCueVel     = Vector2.zero();
  Vector2 _prevTargetVel  = Vector2.zero();
  Vector2 _shotDir        = Vector2(1, 0);

  // ── Cue ball trail ────────────────────────────────────────────────────────
  /// Positions sampled while the cue ball is rolling.  Cleared on each new shot.
  final List<Vector2> cueTrail = [];
  static const double _trailSampleDist = 0.18; // min distance between samples

  // ── Post-collision spin state ──────────────────────────────────────────────
  // After the cue ball hits the target ball, we apply a decaying forward/back
  // force for a duration proportional to |spin|.
  static const double kSpinMaxDuration = 0.5;  // seconds at max spin
  static const double kSpinForce       = 28.0; // force magnitude
  double _spinRemaining = 0.0;

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

    _ballsContacting    = false;
    _firstCollisionDone = false;
    _ballsMoving        = false;
    cueTrail.clear();
    stateNotifier.value = LabState.aiming;
  }

  void shoot({required double power, double spin = 0.0}) {
    if (stateNotifier.value != LabState.aiming) return;
    _lastPower     = power;
    _lastSpin      = spin.clamp(-1.0, 1.0);
    _ballsContacting    = false;
    _firstCollisionDone = false;
    _spinRemaining      = 0.0;
    cueTrail.clear();

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
    const r = BallComponent.radius;
    return Vector2(pos.x.clamp(r, tableW - r), pos.y.clamp(r, tableH - r));
  }

  // ── Update loop ───────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    if (cueBall.isLoaded)    _prevPositions[cueBall]    = cueBall.body.position.clone();
    if (targetBall.isLoaded) _prevPositions[targetBall] = targetBall.body.position.clone();
    _prevCueVel    = cueBall.isLoaded    ? cueBall.body.linearVelocity.clone()    : Vector2.zero();
    _prevTargetVel = targetBall.isLoaded ? targetBall.body.linearVelocity.clone() : Vector2.zero();

    super.update(dt);

    _sampleTrail();
    _handleManualCollision();
    _applySpinForce(dt);
    _checkPocketCollisions();
    _clampBallsInBounds();
    _trackMotionState();
  }

  // ── Trail sampling ────────────────────────────────────────────────────────
  void _sampleTrail() {
    if (stateNotifier.value != LabState.rolling) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) return;
    final pos = cueBall.body.position.clone();
    if (cueTrail.isEmpty ||
        (pos - cueTrail.last).length >= _trailSampleDist) {
      cueTrail.add(pos);
    }
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
    if (stateNotifier.value != LabState.rolling) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) return;
    if (!targetBall.isLoaded || !targetBall.inPlay) return;

    const collR    = BallComponent.radius * 2.0;
    const separateR = collR + 0.06; // small hysteresis so we don't re-fire immediately

    final cuePos    = cueBall.body.position;
    final targetPos = targetBall.body.position;
    final dist      = (cuePos - targetPos).length;

    // Once balls have separated, allow the next collision
    if (_ballsContacting && dist > separateR) {
      _ballsContacting = false;
    }
    if (_ballsContacting) return;

    // ── Detect collision via CCD sweep ────────────────────────────────────
    final prevCuePos = _prevPositions[cueBall] ?? cuePos;
    Vector2? contactPt = _sweepContact(prevCuePos, cuePos, targetPos, collR);
    // Fallback: already overlapping this frame
    if (contactPt == null && dist <= collR) contactPt = cuePos.clone();
    if (contactPt == null) return;

    // Collision normal (cue→target)
    final normal = (targetPos - contactPt).normalized();

    // Use pre-step velocities to avoid using already-modified values
    final vCue    = _prevCueVel.clone();
    final vTarget = _prevTargetVel.clone();

    // Relative velocity along normal — must be approaching
    final relNormal = (vCue - vTarget).dot(normal);
    if (relNormal <= 0) return;

    _ballsContacting = true;

    // ── Separate the balls to the exact contact surface ───────────────────
    final overlap = collR - dist;
    if (overlap > 0) {
      cueBall.body.setTransform(cuePos - normal * overlap, 0);
    }

    // ── Elastic collision (equal mass) ────────────────────────────────────
    // Standard 1D elastic along normal; tangential components unchanged.
    final cueNorm    = vCue.dot(normal);
    final targetNorm = vTarget.dot(normal);
    final cueTang    = vCue    - normal * cueNorm;
    final targetTang = vTarget - normal * targetNorm;

    // Exchange normal components (equal mass → perfect swap)
    Vector2 newCueVel    = cueTang    + normal * targetNorm;
    Vector2 newTargetVel = targetTang + normal * cueNorm;

    // ── First-hit only: apply follow/draw on top of elastic result ────────
    if (!_firstCollisionDone) {
      _firstCollisionDone = true;
      // followFraction: 0 at high power (stun), 1 at low power (follow)
      final followFraction =
          (1.0 - _lastPower / kFollowThreshold).clamp(0.0, 1.0);
      // Override cue velocity: tangent + partial forward follow
      newCueVel = cueTang + normal * (cueNorm * followFraction * kFollowScale);

      // Arm spin force
      if (_lastSpin.abs() > 0.01) {
        _spinRemaining = _lastSpin.abs() * kSpinMaxDuration;
      }
    }

    cueBall.body.linearVelocity    = newCueVel;
    targetBall.body.linearVelocity = newTargetVel;
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

  // ── Post-collision spin force ─────────────────────────────────────────────
  //
  // After the cue ball strikes the target, we apply a continuous force along
  // the original shot direction for `_spinRemaining` seconds.
  //   top spin  (_lastSpin > 0): force is forward  → ball chases target
  //   back spin (_lastSpin < 0): force is backward → ball brakes / reverses
  //
  // The force fades linearly to zero over the remaining duration so it feels
  // like the spin energy "running out" naturally.
  //
  void _applySpinForce(double dt) {
    if (!_firstCollisionDone) return;
    if (_spinRemaining <= 0) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) {
      _spinRemaining = 0;
      return;
    }

    final totalDuration = _lastSpin.abs() * kSpinMaxDuration;
    // Linear fade: full force at start, zero at end
    final fade      = (_spinRemaining / totalDuration).clamp(0.0, 1.0);
    final spinDir   = _lastSpin > 0 ? _shotDir : -_shotDir;
    final forceMag  = _lastSpin.abs() * kSpinForce * fade;

    cueBall.body.applyForce(spinDir * forceMag);
    _spinRemaining = (_spinRemaining - dt).clamp(0.0, double.infinity);
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

  // ── Hard boundary clamp ───────────────────────────────────────────────────
  //
  // Safety net: if a ball somehow escapes the table (tunnelling at extreme
  // speed or a physics glitch), push it back inside and reflect its velocity.
  // Pocketed balls are moved off-screen intentionally — skip those.
  //
  void _clampBallsInBounds() {
    const r    = BallComponent.radius;
    const minX = r;
    const maxX = tableW - r;
    const minY = r;
    const maxY = tableH - r;

    for (final ball in [cueBall, targetBall]) {
      if (!ball.isLoaded || !ball.inPlay) continue;
      final pos = ball.body.position;
      final vel = ball.body.linearVelocity;

      double nx = pos.x, ny = pos.y;
      double vx = vel.x, vy = vel.y;
      bool clamped = false;

      if (pos.x < minX) { nx = minX; vx =  vx.abs(); clamped = true; }
      if (pos.x > maxX) { nx = maxX; vx = -vx.abs(); clamped = true; }
      if (pos.y < minY) { ny = minY; vy =  vy.abs(); clamped = true; }
      if (pos.y > maxY) { ny = maxY; vy = -vy.abs(); clamped = true; }

      if (clamped) {
        ball.body.setTransform(Vector2(nx, ny), ball.body.angle);
        ball.body.linearVelocity = Vector2(vx, vy);
      }
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
