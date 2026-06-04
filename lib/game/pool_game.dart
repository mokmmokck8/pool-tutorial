import 'dart:math' show acos, atan2, cos, min, pi, sin, sqrt;
import 'dart:ui' show Offset;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Colors, Color, ValueNotifier;
import 'components/ball_component.dart';
import 'components/table_component.dart';
import 'components/aim_overlay.dart';
import 'shot_evaluator.dart';

enum GameState { idle, aiming, rolling, scored, scratch, cleared }

// ── Snapshot for undo ──────────────────────────────────────────────────────
class _BallState {
  final Vector2 position;
  final bool inPlay;
  _BallState(this.position, this.inPlay);
}

class _PoolSnapshot {
  final Vector2 cueBallPos;
  final List<_BallState> objectStates;
  final int targetIndex;
  _PoolSnapshot({
    required this.cueBallPos,
    required this.objectStates,
    required this.targetIndex,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class PoolGame extends Forge2DGame {
  final void Function(int score, String label) onShotEvaluated;

  PoolGame({required this.onShotEvaluated}) : super(gravity: Vector2.zero());

  @override
  Color backgroundColor() => const Color(0xFFFFFFFF);

  // ── Public notifiers ───────────────────────────────────────────────────────
  final stateNotifier = ValueNotifier<GameState>(GameState.aiming);

  /// Current hit-point set by the UI (-1..1 on both axes)
  final hitPointNotifier = ValueNotifier<Offset>(Offset.zero);

  /// Score of the last shot (null = no shot yet)
  final lastScoreNotifier = ValueNotifier<int?>(null);

  /// Whether undo is available
  final canUndoNotifier = ValueNotifier<bool>(false);

  // ── Game objects ───────────────────────────────────────────────────────────
  late BallComponent cueBall;
  final List<BallComponent> objectBalls = [];
  late TableComponent table;
  late AimOverlay aimOverlay;

  /// Which pocket the player has selected for the current target ball.
  /// null = auto (nearest pocket).
  final selectedPocketNotifier = ValueNotifier<int?>(null);

  /// Converts a tap position (logical pixels, origin = top-left of game widget)
  /// to world coordinates using the current camera transform.
  Vector2 tapToWorld(double screenX, double screenY) {
    final zoom = camera.viewfinder.zoom;
    final center = camera.viewfinder.position;
    return Vector2(
      center.x + (screenX - size.x / 2) / zoom,
      center.y + (screenY - size.y / 2) / zoom,
    );
  }

  int _currentTargetIndex = 0;
  bool _ballsMoving = false;
  int _prevPocketedCount = 0;
  bool _spinApplied = false;
  Vector2 _shotDir = Vector2(1, 0);

  /// True once onLoad() has fully populated cueBall and objectBalls.
  bool _gameLoaded = false;

  /// Cue ball velocity captured BEFORE the physics step each frame.
  Vector2 _prevCueVelocity = Vector2.zero();

  /// Top/back spin energy stored at shoot time; decays each frame after contact.
  /// Positive = back spin (draw) → force backward.
  /// Negative = top spin (follow) → force forward.
  double _spinDyEnergy = 0.0;

  /// Per-frame energy decay multiplier. Closer to 1.0 = longer-lasting effect.
  double _spinDyDecay = 0.93;

  /// Previous-frame positions for continuous pocket detection.
  final Map<BallComponent, Vector2> _prevPositions = {};

  final List<_PoolSnapshot> _snapshots = [];

  // ── Table geometry (PORTRAIT: narrow × tall) ───────────────────────────────
  static const double tableW = 11.0;
  static const double tableH = 22.0;
  static const double rail = TableComponent.railThickness;
  static const double pocketR = TableComponent.pocketRadius;

  // Gap cut into wall segments at pockets. Must be large enough that ball
  // (radius 0.30) can pass cleanly without hitting the wall endpoint.
  static const double _cornerGap = 1.0;
  static const double _midGap = 0.9;

  final List<Vector2> _pocketPositions = <Vector2>[];

  // ── Camera ─────────────────────────────────────────────────────────────────
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) return;
    const pad = 1.08;
    final zoomX = size.x / (tableW * pad);
    final zoomY = size.y / (tableH * pad);
    camera.viewfinder.zoom = min(zoomX, zoomY);
    camera.viewfinder.position = Vector2(tableW / 2, tableH / 2);
  }

  // ── Load ───────────────────────────────────────────────────────────────────
  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Pockets sit at the actual table edges/corners so that ball sensors
    // are reachable through the wall gaps.
    final hh = tableH / 2;
    _pocketPositions.addAll(<Vector2>[
      Vector2(0, 0), // top-left  corner
      Vector2(tableW, 0), // top-right corner
      Vector2(0, hh), // mid-left
      Vector2(tableW, hh), // mid-right
      Vector2(0, tableH), // bottom-left  corner
      Vector2(tableW, tableH), // bottom-right corner
    ]);

    _buildWalls();
    _buildPocketSensors();

    table = TableComponent(
      tableWidth: tableW,
      tableHeight: tableH,
      pocketPositions: _pocketPositions,
    );
    await world.add(table);

    _spawnBalls();

    aimOverlay = AimOverlay(game: this);
    await world.add(aimOverlay);

    _gameLoaded =
        true; // guard: prevents isCurrentShotPossible firing before load
  }

  // ── Physics setup ──────────────────────────────────────────────────────────
  void _buildWalls() {
    final hh = tableH / 2;

    // Each entry: [v1, v2, ghostV1, ghostV2].
    // Ghost vertices tell Box2D how the edge "continues" past its endpoints,
    // preventing spurious bounce-back when a ball rolls through a pocket gap.
    final segs = <List<Vector2>>[
      // Top short wall
      [
        Vector2(rail + _cornerGap, rail),
        Vector2(tableW - rail - _cornerGap, rail),
        Vector2(0, rail),
        Vector2(tableW, rail)
      ],
      // Bottom short wall
      [
        Vector2(rail + _cornerGap, tableH - rail),
        Vector2(tableW - rail - _cornerGap, tableH - rail),
        Vector2(0, tableH - rail),
        Vector2(tableW, tableH - rail)
      ],
      // Left wall — upper half
      [
        Vector2(rail, rail + _cornerGap),
        Vector2(rail, hh - _midGap),
        Vector2(rail, 0),
        Vector2(rail, hh)
      ],
      // Left wall — lower half
      [
        Vector2(rail, hh + _midGap),
        Vector2(rail, tableH - rail - _cornerGap),
        Vector2(rail, hh),
        Vector2(rail, tableH)
      ],
      // Right wall — upper half
      [
        Vector2(tableW - rail, rail + _cornerGap),
        Vector2(tableW - rail, hh - _midGap),
        Vector2(tableW - rail, 0),
        Vector2(tableW - rail, hh)
      ],
      // Right wall — lower half
      [
        Vector2(tableW - rail, hh + _midGap),
        Vector2(tableW - rail, tableH - rail - _cornerGap),
        Vector2(tableW - rail, hh),
        Vector2(tableW - rail, tableH)
      ],
    ];

    for (final seg in segs) {
      final bd = BodyDef()..type = BodyType.static;
      final shape = EdgeShape()
        ..set(seg[0], seg[1])
        ..vertex0.setFrom(seg[2])
        ..hasVertex0 = true
        ..vertex3.setFrom(seg[3])
        ..hasVertex3 = true;
      world.createBody(bd).createFixture(FixtureDef(shape)
        // kRailFriction ↑ = more English effect at rail.  Range: 0.5–1.5
        // Combined ball-rail friction = sqrt(ball.kFriction * rail) via Box2D.
        // With ball.kFriction=0.02: set rail to 1.0 → combined ≈ 0.14 (realistic).
        ..friction = 1.0
        ..restitution = 0.60);
    }
  }

  void _buildPocketSensors() {
    for (final pos in _pocketPositions) {
      final bd = BodyDef()
        ..type = BodyType.static
        ..position = pos;
      world.createBody(bd).createFixture(
          FixtureDef(CircleShape()..radius = pocketR)..isSensor = true);
    }
  }

  // ── Spawn 3 ordered balls ──────────────────────────────────────────────────
  void _spawnBalls() {
    cueBall = BallComponent(
      position: Vector2(tableW / 2, tableH * 0.78),
      color: Colors.white,
      number: 0,
      isCue: true,
    );
    world.add(cueBall);

    const defs = <(Vector2 Function(), Color, int)>[
      (_ball1Pos, Color(0xFFF1C40F), 1), // 1 — yellow
      (_ball2Pos, Color(0xFFE74C3C), 2), // 2 — red
      (_ball3Pos, Color(0xFF3498DB), 3), // 3 — blue
    ];

    for (final (posF, color, num) in defs) {
      final ball = BallComponent(
        position: posF(),
        color: color,
        number: num,
      );
      objectBalls.add(ball);
      world.add(ball);
    }
  }

  // Ball default positions (functions so they return fresh Vector2 each time)
  static Vector2 _ball1Pos() => Vector2(tableW * 0.18, tableH * 0.22);
  static Vector2 _ball2Pos() => Vector2(tableW * 0.72, tableH * 0.32);
  static Vector2 _ball3Pos() => Vector2(tableW * 0.50, tableH * 0.15);

  // ── Public getters ─────────────────────────────────────────────────────────
  List<Vector2> get pocketPositions => _pocketPositions;

  int get currentTargetIndex => _currentTargetIndex;

  BallComponent? get currentTarget {
    final alive = objectBalls.where((b) => b.inPlay).toList();
    if (alive.isEmpty) return null;
    // Always target the lowest-numbered remaining ball in sequence
    alive.sort((a, b) => a.number.compareTo(b.number));
    return alive.first;
  }

  BallComponent? get nextTarget {
    final alive = objectBalls.where((b) => b.inPlay).toList();
    if (alive.length < 2) return null;
    alive.sort((a, b) => a.number.compareTo(b.number));
    return alive[1];
  }

  // ── Pocket selection ────────────────────────────────────────────────────────
  void selectPocket(int idx) {
    if (idx >= 0 && idx < _pocketPositions.length) {
      selectedPocketNotifier.value = idx;
    }
  }

  /// Returns the player-selected pocket, or the nearest one if none is chosen.
  Vector2 _resolvedPocket(Vector2 objPos) {
    final idx = selectedPocketNotifier.value;
    if (idx != null) return _pocketPositions[idx];
    return _nearestPocket(objPos);
  }

  double get autoAimAngle {
    final target = currentTarget;
    if (target == null) return 0;
    final pocket = _resolvedPocket(target.body.position);
    final ghost = _ghostBall(target.body.position, pocket);
    final diff = ghost - cueBall.body.position;
    return atan2(diff.y, diff.x);
  }

  // Shots with cut angle beyond this are flagged impossible.
  static const double _maxCutAngle = 60.0;

  /// Cut angle in degrees (0 = straight-in, 90 = full cut).
  double get currentCutAngle {
    if (!_gameLoaded) return 0;
    final target = currentTarget;
    if (target == null || !cueBall.isLoaded) return 0;
    final pocket = _resolvedPocket(target.body.position);
    final ghost = _ghostBall(target.body.position, pocket);
    final cueDir = (ghost - cueBall.body.position).normalized();
    final objDir = (pocket - target.body.position).normalized();
    final dot = cueDir.dot(objDir).clamp(-1.0, 1.0);
    return acos(dot) * 180 / pi;
  }

  /// True when the current target ball can physically be potted.
  bool get isCurrentShotPossible {
    if (!_gameLoaded) return true; // show shoot button while loading
    if (currentTarget == null) return true; // cleared or not loaded
    return currentCutAngle <= _maxCutAngle;
  }

  /// Returns where the cue ball is PREDICTED to travel after impact
  /// given the current hitPoint spin setting.
  Vector2 predictedCueBallPath(double length) {
    final target = currentTarget;
    if (target == null) return cueBall.body.position;
    final pocket = _resolvedPocket(target.body.position);
    final ghostPos = _ghostBall(target.body.position, pocket);
    final cueDir = (ghostPos - cueBall.body.position).normalized();
    final perpDir = Vector2(-cueDir.y, cueDir.x);
    final spin = hitPointNotifier.value;
    final mixed = perpDir + cueDir * (-spin.dy * 0.8);
    return ghostPos + mixed.normalized() * length;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Vector2 _nearestPocket(Vector2 pos) {
    Vector2 best = _pocketPositions[0];
    double bestD = (_pocketPositions[0] - pos).length;
    for (int i = 1; i < _pocketPositions.length; i++) {
      final d = (_pocketPositions[i] - pos).length;
      if (d < bestD) {
        bestD = d;
        best = _pocketPositions[i];
      }
    }
    return best;
  }

  /// True if line segment A→B passes through (or ends inside) a circle at C with radius r.
  bool _segmentHitsCircle(Vector2 a, Vector2 b, Vector2 c, double r) {
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

  Vector2 _ghostBall(Vector2 obj, Vector2 pocket) {
    final dir = (pocket - obj).normalized();
    return obj - dir * (BallComponent.radius * 2);
  }

  // ── Shoot ──────────────────────────────────────────────────────────────────
  void shoot({required Offset hitPoint, required double power}) {
    if (stateNotifier.value == GameState.rolling) return;
    if (!isCurrentShotPossible)
      return; // guard: UI should hide button, but safety-net here
    hitPointNotifier.value = hitPoint;
    _saveSnapshot();

    final angle = autoAimAngle;
    _shotDir = Vector2(cos(angle), sin(angle)); // store for post-contact spin
    _spinApplied = false;

    // ── PHYSICS RULE: cue ball travels STRAIGHT to object ball.
    //    Spin is applied at the moment of contact, not at shoot time.
    //    (Lateral pre-shot impulse was the bug — it curved the ball before impact.)
    // ── Tunable shot constants ──────────────────────────────────────────────
    // kMaxForce: peak linear impulse at full power.  ↑ = harder max shot.  Range: 50–120
    // kVisualSpin: angular impulse for visual ball roll (cosmetic only).   Range: 1.0–4.0
    // Power is squared so low-power shots feel noticeably slower/shorter.
    const kMaxForce = 80.0;
    const kVisualSpin = 1.5;
    final effectivePower = power * power; // quadratic: 50% power → 25% force
    cueBall.body.applyLinearImpulse(_shotDir * (effectivePower * kMaxForce));
    // Left/right English → angular velocity (visual rolling + rail spin transfer).
    cueBall.body
        .applyAngularImpulse(hitPoint.dx * effectivePower * kVisualSpin);

    // Top/back spin energy for post-contact acceleration.
    // Heavier spin × more power → larger energy AND slower decay → longer effect.
    _spinDyEnergy = hitPoint.dy * effectivePower;
    // Decay range: 0.95 (no spin) → 0.98 (full spin × full power) = 1–3 second duration.
    _spinDyDecay = 0.95 + hitPoint.dy.abs() * effectivePower * 0.03;

    stateNotifier.value = GameState.rolling;
    _prevPocketedCount = objectBalls.where((b) => !b.inPlay).length;
    canUndoNotifier.value = _snapshots.isNotEmpty;
  }

  // ── Undo ───────────────────────────────────────────────────────────────────
  void undo() {
    if (_snapshots.isEmpty) return;
    final snap = _snapshots.removeLast();
    _restoreSnapshot(snap);
    canUndoNotifier.value = _snapshots.isNotEmpty;
  }

  void _saveSnapshot() {
    _snapshots.add(_PoolSnapshot(
      cueBallPos: cueBall.body.position.clone(),
      objectStates: objectBalls
          .map((b) => _BallState(b.body.position.clone(), b.inPlay))
          .toList(),
      targetIndex: _currentTargetIndex,
    ));
  }

  void _restoreSnapshot(_PoolSnapshot snap) {
    // Stop all motion
    for (final ball in [cueBall, ...objectBalls]) {
      if (ball.isLoaded) {
        ball.body.linearVelocity = Vector2.zero();
        ball.body.angularVelocity = 0;
      }
    }
    // Restore cue ball
    cueBall.body.setTransform(snap.cueBallPos, 0);
    cueBall.inPlay = true;

    // Restore object balls
    for (int i = 0; i < objectBalls.length; i++) {
      final ball = objectBalls[i];
      final state = snap.objectStates[i];
      ball.body.setTransform(state.position, 0);
      if (state.inPlay && !ball.inPlay) {
        // Was pocketed, restore
        ball.body.setType(BodyType.dynamic);
        ball.inPlay = true;
      } else if (!state.inPlay && ball.inPlay) {
        ball.pocket();
      }
    }
    _currentTargetIndex = snap.targetIndex;
    _spinApplied = false;
    _spinDyEnergy = 0.0;
    _ballsMoving = false; // prevent spurious _onBallsStopped after restore
    selectedPocketNotifier.value = null; // clear pocket so angle recalculates
    lastScoreNotifier.value = null;
    stateNotifier.value = GameState.aiming;
  }

  // ── Update loop ────────────────────────────────────────────────────────────
  bool get _anyBallMoving => <BallComponent>[cueBall, ...objectBalls]
      .any((b) => b.inPlay && b.body.linearVelocity.length2 > 0.01);

  /// Detects the first frame the cue ball contacts an object ball and applies
  /// the spin impulse.  Runs AFTER super.update() so Box2D has already resolved
  /// the elastic collision (90-degree rule is already applied).
  /// Spin impulse is scaled by PRE-collision speed so the effect feels consistent
  /// regardless of cut angle.
  /// Applies a single impulse the moment the cue ball contacts the object ball.
  ///
  /// Top spin (dy < 0):
  ///   – Cancels part of the natural 90° sideways deflection
  ///   – Adds forward impulse along the original shot direction
  ///   → Ball continues through, following the shot line
  ///
  /// Back spin (dy > 0):
  ///   – Cancels part of the natural 90° sideways deflection
  ///   – Adds backward impulse opposite the shot direction
  ///   → Ball reverses back toward the player
  ///
  /// No continuous force is applied; the ball travels in a straight line
  /// after this single impulse (combined with Box2D's natural deflection).
  /// Marks the moment of first contact and applies a side-English kick.
  /// Top/back spin (dy) is handled by the continuous force in
  /// [_applyContinuousFollowDraw], NOT by an impulse here — cancelling the
  /// natural 90° deflection at contact causes object-ball energy loss artefacts.
  void _applySpinAtContact() {
    if (_spinApplied || stateNotifier.value != GameState.rolling) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) return;

    for (final ball in objectBalls) {
      if (!ball.inPlay || !ball.isLoaded) continue;
      final dist = (cueBall.body.position - ball.body.position).length;
      if (dist > BallComponent.radius * 2.3) continue;

      _spinApplied = true;
      final spin = hitPointNotifier.value;
      final preSpeed = _prevCueVelocity.length;
      if (preSpeed < 0.3) return;

      final mass = cueBall.body.mass;

      // ── Top / Back spin — immediate impulse at contact ────────────────────
      // Gives the "馬上掉頭" (immediate reversal) feel for back spin and the
      // "follow-through" feel for top spin.  The continuous force in
      // _applyContinuousFollowDraw then sustains and builds the effect.
      //
      // kFollowImpulse: fraction of pre-collision speed added along shot dir.
      //   top spin  (dy < 0) → forward  (+_shotDir)
      //   back spin (dy > 0) → backward (-_shotDir)
      //   Range: 0.3–1.0
      const kFollowImpulse = 1.4;
      if (spin.dy.abs() > 0.05) {
        cueBall.body.applyLinearImpulse(
          _shotDir * (-spin.dy * preSpeed * kFollowImpulse * mass),
        );
      }

      // ── English (side spin) — shifts direction at contact ─────────────────
      // kEnglishFactor: Range: 0.2–0.6
      const kEnglishFactor = 0.45;
      final perp = Vector2(-_shotDir.y, _shotDir.x);
      if (spin.dx.abs() > 0.05) {
        cueBall.body.applyLinearImpulse(
          perp * (spin.dx * preSpeed * kEnglishFactor * mass),
        );
      }
      return;
    }
  }

  /// After contact, top/back spin energy pushes the cue ball forward or
  /// backward along the original shot direction every frame until the spin
  /// energy decays to zero.
  ///
  /// This creates the pool "follow/draw" arc: ball starts along the natural
  /// 90° tangent then gradually bends toward (follow) or away from (draw) the
  /// shot direction.
  ///
  /// kSpinForce ↑ = stronger push per unit of remaining energy.  Range: 5–20
  void _applyContinuousFollowDraw() {
    if (!_spinApplied) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) return;
    if (stateNotifier.value != GameState.rolling) return;
    if (_spinDyEnergy.abs() < 0.002) return;

    _spinDyEnergy *= _spinDyDecay; // spin exhausted by cloth friction

    // kSpinForce: acceleration per unit of remaining spin energy.
    // Must be large enough to visibly redirect the ball away from the tangent line.
    // With energy ≈ 0.2 (moderate spin × moderate power) and kSpinForce = 30:
    //   Δv/frame ≈ 0.2 × 30 × 0.016 = 0.096 units/s → ~2 units/s over 1 second.
    // Range: 15–50
    const kSpinForce = 30.0;
    // back spin (energy > 0) → force in -_shotDir (backward)
    // top spin  (energy < 0) → force in +_shotDir (forward)
    cueBall.body.applyForce(
      _shotDir * (-_spinDyEnergy * kSpinForce * cueBall.body.mass),
    );
  }

  @override
  void update(double dt) {
    // Snapshot state BEFORE physics step (used for CCD and pre-collision spin scaling).
    if (cueBall.isLoaded) {
      _prevPositions[cueBall] = cueBall.body.position.clone();
      _prevCueVelocity = cueBall.body.linearVelocity.clone();
    }
    for (final b in objectBalls) {
      if (b.isLoaded) _prevPositions[b] = b.body.position.clone();
    }

    super.update(dt);
    _applySpinAtContact();
    _applyContinuousFollowDraw();
    _checkPocketCollisions();

    final moving = _anyBallMoving;
    if (_ballsMoving && !moving) {
      _ballsMoving = false;
      _onBallsStopped();
    } else if (moving) {
      _ballsMoving = true;
    }
  }

  void _checkPocketCollisions() {
    if (!cueBall.isLoaded) return;
    // Use segment-circle intersection so fast-moving balls are never missed.
    // Detection radius = pocketR + ballRadius so the ball visually "falls in".
    const detectR = pocketR + BallComponent.radius;

    bool _inPocket(BallComponent ball) {
      final curr = ball.body.position;
      final prev = _prevPositions[ball] ?? curr;
      for (final pocket in _pocketPositions) {
        if (_segmentHitsCircle(prev, curr, pocket, detectR)) return true;
      }
      return false;
    }

    if (cueBall.inPlay && _inPocket(cueBall)) {
      _onCueScratch();
      return;
    }
    for (final ball in objectBalls) {
      if (ball.inPlay && ball.isLoaded && _inPocket(ball)) {
        ball.pocket();
      }
    }
  }

  void _onCueScratch() {
    // Stop all balls first so undo restores a clean state.
    for (final ball in [cueBall, ...objectBalls]) {
      if (ball.isLoaded) {
        ball.body.linearVelocity = Vector2.zero();
        ball.body.angularVelocity = 0;
      }
    }
    stateNotifier.value = GameState.scratch;

    Future.delayed(const Duration(milliseconds: 800), () {
      if (_snapshots.isNotEmpty) {
        undo(); // rewind to pre-shot position
      } else {
        // First shot — just reposition cue ball
        cueBall.body.setTransform(Vector2(tableW / 2, tableH * 0.78), 0);
        cueBall.inPlay = true;
        stateNotifier.value = GameState.aiming;
      }
    });
  }

  void _onBallsStopped() {
    final nowPocketed = objectBalls.where((b) => !b.inPlay).length;
    final justPocketed = nowPocketed - _prevPocketedCount;

    if (justPocketed > 0) {
      // Ball was pocketed — clear pocket selection for the next ball.
      selectedPocketNotifier.value = null;

      final alive = objectBalls.where((b) => b.inPlay).toList();
      if (alive.isEmpty) {
        stateNotifier.value = GameState.cleared;
        return;
      }

      stateNotifier.value = GameState.scored;
      final next = nextTarget ??
          (objectBalls.where((b) => b.inPlay).toList()
                ..sort((a, b) => a.number.compareTo(b.number)))
              .firstOrNull;
      if (next != null) {
        final eval = ShotEvaluator.evaluate(
          cueBallPos: cueBall.body.position,
          nextTarget: next.body.position,
          pockets: _pocketPositions,
          tableW: tableW,
          tableH: tableH,
        );
        lastScoreNotifier.value = eval.score;
        onShotEvaluated(eval.score, eval.label);
      }
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (stateNotifier.value != GameState.rolling) {
          stateNotifier.value = GameState.aiming;
        }
      });
    } else {
      // No ball was pocketed — automatically undo the shot.
      stateNotifier.value = GameState.scratch;
      Future.delayed(const Duration(milliseconds: 800), undo);
    }
  }
}
