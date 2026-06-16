import 'dart:math' show atan2, cos, min, pi, sin;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Colors, Color, ValueNotifier;
import '../components/ball_component.dart';
import '../components/table_component.dart';
import 'lab_overlay.dart';
import 'lab_physics.dart';
import 'lab_simulation.dart';

export 'lab_simulation.dart' show LabSimulation;

enum LabState { aiming, rolling, done }

class LabGame extends Forge2DGame {
  LabGame() : super(gravity: Vector2.zero());

  @override
  Color backgroundColor() => const Color(0xFFFFFFFF);

  // ── Trail sampling threshold ───────────────────────────────────────────────
  static const double kTrailSampleDist = 0.18;

  // ── Public notifiers ───────────────────────────────────────────────────────
  final stateNotifier = ValueNotifier<LabState>(LabState.aiming);

  /// Cushion softness slider value — kept for UI compatibility (0 = hard, 1 = soft).
  /// Currently not wired into the simulation (kCushionMaxAngleReduction = 0).
  double cushionSoftness = 0.3;

  // ── Ball references ────────────────────────────────────────────────────────
  late BallComponent cueBall;
  late BallComponent targetBall;

  // ── Table geometry ─────────────────────────────────────────────────────────
  static const double tableW = LabSimulation.tableW;
  static const double tableH = LabSimulation.tableH;
  static const double rail   = LabTablePhysics.rail;

  static Vector2 get targetPocket => Vector2(tableW, tableH);
  static Vector2 get _targetPos   => Vector2(tableW * 0.30, tableH * 0.30);
  double _cueDist = 4.0;

  final List<Vector2> _pocketPositions = [];

  // ── Shot state ─────────────────────────────────────────────────────────────
  bool _gameLoaded  = false;
  bool _ballsMoving = false;
  double _lastCutAngle = 0.0;
  Vector2 _shotDir     = Vector2(1, 0);

  // ── Physics simulation ─────────────────────────────────────────────────────
  late LabSimulation _sim;

  // ── Cue ball trail ─────────────────────────────────────────────────────────
  final List<Vector2> cueTrail = [];

  // ── Camera ─────────────────────────────────────────────────────────────────
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    const pad = 1.08;
    camera.viewfinder.zoom = min(size.x / (tableW * pad), size.y / (tableH * pad));
    camera.viewfinder.position = Vector2(tableW / 2, tableH / 2);
  }

  // ── Load ───────────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _pocketPositions.addAll(LabTablePhysics.defaultPocketPositions());

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
    final targetPos = _targetPos;
    final cuePos    = _clampedCuePos(cutAngleDeg);

    _sim = LabSimulation(cuePos: cuePos, targetPos: targetPos);
    _sim.onCueBallRailBounce = _onRailBounce;
    _sim.onBallCollision     = _onBallCollision;

    targetBall = BallComponent(
      position: targetPos,
      color: const Color(0xFFE74C3C),
      number: 1,
    );
    await world.add(targetBall);

    cueBall = BallComponent(
      position: cuePos,
      color: Colors.white,
      number: 0,
      isCue: true,
    );
    await world.add(cueBall);

    _makeKinematic();
  }

  /// Make both ball bodies kinematic so Box2D does not apply forces or
  /// integrate physics — the simulation owns all ball movement.
  void _makeKinematic() {
    final filter = Filter()..groupIndex = -1;
    for (final ball in [cueBall, targetBall]) {
      ball.body.setType(BodyType.kinematic);
      for (final f in ball.body.fixtures) {
        f.filterData = filter;
      }
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  LabState get state     => stateNotifier.value;
  bool     get isLoaded  => _gameLoaded;

  void setCutAngle(double degrees) {
    if (!_gameLoaded) return;
    _lastCutAngle = degrees;
    final cuePos  = _clampedCuePos(degrees);

    // Reset Box2D bodies to the new positions
    for (final ball in [cueBall, targetBall]) {
      if (ball.body.bodyType != BodyType.kinematic) {
        ball.body.setType(BodyType.kinematic);
      }
      ball.body.linearVelocity = Vector2.zero();
      ball.inPlay = true;
    }
    cueBall.body.setTransform(cuePos, 0);
    targetBall.body.setTransform(_targetPos, 0);

    // Reset simulation
    _sim = LabSimulation(cuePos: cuePos, targetPos: _targetPos);
    _sim.onCueBallRailBounce = _onRailBounce;
    _sim.onBallCollision     = _onBallCollision;

    _ballsMoving = false;
    cueTrail.clear();
    stateNotifier.value = LabState.aiming;
  }

  void setDistance(double dist) {
    _cueDist = dist;
    if (_gameLoaded) setCutAngle(_lastCutAngle);
  }

  void shoot({required double power, double spin = 0.0, double sideSpin = 0.0}) {
    if (stateNotifier.value != LabState.aiming) return;
    cueTrail.clear();

    final angle = _autoAimAngle;
    _shotDir = Vector2(cos(angle), sin(angle));

    // Initialise the cue ball: velocity from power, plus top/back and side spin.
    // Follow / draw / stun then emerge from the slip→roll cloth physics.
    _sim.fire(
      power: power,
      spin: spin,
      sideSpin: sideSpin,
      dir: _shotDir,
    );

    stateNotifier.value = LabState.rolling;
  }

  // ── Simulation event callbacks ─────────────────────────────────────────────

  void _onRailBounce(bool isX, Vector2 prevVel) {
    // Reserved for future audio / visual feedback.
  }

  void _onBallCollision() {
    // Reserved for future audio / visual feedback.
  }

  // ── Geometry helpers ───────────────────────────────────────────────────────
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
    final rad  = cutAngleDeg * pi / 180.0;
    final incomingDir = Vector2(
      toP.x * cos(rad) - toP.y * sin(rad),
      toP.x * sin(rad) + toP.y * cos(rad),
    );
    return _targetPos - incomingDir * _cueDist;
  }

  Vector2 _clampedCuePos(double cutAngleDeg) {
    final pos = _cueBallPos(cutAngleDeg);
    const r   = BallComponent.radius;
    return Vector2(pos.x.clamp(r, tableW - r), pos.y.clamp(r, tableH - r));
  }

  // ── Update loop ────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    // 1. Advance our physics simulation
    if (stateNotifier.value == LabState.rolling) {
      _sim.step(dt);
    }

    // 2. Box2D update (handles rendering sync for BodyComponents)
    super.update(dt);

    // 3. Override Box2D body positions with simulation truth
    _syncToBox2D();

    // 4. Game-level bookkeeping
    _sampleTrail();
    _checkPocketCollisions();
    _trackMotionState();
  }

  /// Copy simulation positions/velocities into the Box2D kinematic bodies so
  /// that Flame's BodyComponent renders them at the correct location.
  void _syncToBox2D() {
    for (int i = 0; i < 2; i++) {
      final simBall  = _sim.balls[i];
      final bodyCmp  = i == 0 ? cueBall : targetBall;
      if (!bodyCmp.isLoaded || !simBall.inPlay) continue;
      bodyCmp.body.setTransform(simBall.pos, 0);
      bodyCmp.body.linearVelocity = simBall.vel;
    }
  }

  // ── Trail sampling ─────────────────────────────────────────────────────────
  void _sampleTrail() {
    if (stateNotifier.value != LabState.rolling) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) return;
    final pos = _sim.balls[0].pos.clone();
    if (cueTrail.isEmpty || (pos - cueTrail.last).length >= kTrailSampleDist) {
      cueTrail.add(pos);
    }
  }

  // ── Pocket detection ───────────────────────────────────────────────────────
  void _checkPocketCollisions() {
    const detectR = LabTablePhysics.pocketR + BallComponent.radius;
    for (int i = 0; i < 2; i++) {
      final simBall = _sim.balls[i];
      final bodyCmp = i == 0 ? cueBall : targetBall;
      if (!simBall.inPlay || !bodyCmp.isLoaded) continue;
      final inPocket = _pocketPositions.any((p) => (simBall.pos - p).length <= detectR);
      if (inPocket) {
        bodyCmp.pocket();
        simBall.inPlay = false;
        simBall.vel    = Vector2.zero();
      }
    }
  }

  // ── Motion state tracking ──────────────────────────────────────────────────
  void _trackMotionState() {
    final moving = _sim.anyMoving;
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
