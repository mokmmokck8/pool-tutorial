import 'dart:math' show atan2, cos, min, sin, sqrt;
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

  PoolGame({required this.onShotEvaluated})
      : super(gravity: Vector2.zero());

  @override
  Color backgroundColor() => const Color(0xFFFFFFFF);

  // ── Public notifiers ───────────────────────────────────────────────────────
  final stateNotifier   = ValueNotifier<GameState>(GameState.aiming);
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

  int _currentTargetIndex = 0;
  bool _ballsMoving = false;
  int _prevPocketedCount = 0;

  final List<_PoolSnapshot> _snapshots = [];

  // ── Table geometry (PORTRAIT: narrow × tall) ───────────────────────────────
  static const double tableW  = 11.0;
  static const double tableH  = 22.0;
  static const double rail    = TableComponent.railThickness;
  static const double pocketR = TableComponent.pocketRadius;

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

    // Portrait table pocket positions:
    //   4 corners + 2 mid-side pockets on the long (left/right) walls
    final hw = tableW / 2;
    final hh = tableH / 2;
    _pocketPositions.addAll(<Vector2>[
      Vector2(rail, rail),                   // top-left  corner
      Vector2(tableW - rail, rail),           // top-right corner
      Vector2(rail * 0.5, hh),               // mid-left
      Vector2(tableW - rail * 0.5, hh),      // mid-right
      Vector2(rail, tableH - rail),           // bottom-left  corner
      Vector2(tableW - rail, tableH - rail),  // bottom-right corner
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
  }

  // ── Physics setup ──────────────────────────────────────────────────────────
  void _buildWalls() {
    // Portrait table: short top/bottom, long left/right (with mid-pocket gaps)
    final segs = <List<Vector2>>[
      // Top short wall (one piece — no mid pocket on short sides)
      [Vector2(rail + pocketR, rail), Vector2(tableW - rail - pocketR, rail)],
      // Bottom short wall
      [Vector2(rail + pocketR, tableH - rail), Vector2(tableW - rail - pocketR, tableH - rail)],
      // Left long wall — upper half
      [Vector2(rail, rail + pocketR), Vector2(rail, tableH / 2 - pocketR)],
      // Left long wall — lower half
      [Vector2(rail, tableH / 2 + pocketR), Vector2(rail, tableH - rail - pocketR)],
      // Right long wall — upper half
      [Vector2(tableW - rail, rail + pocketR), Vector2(tableW - rail, tableH / 2 - pocketR)],
      // Right long wall — lower half
      [Vector2(tableW - rail, tableH / 2 + pocketR), Vector2(tableW - rail, tableH - rail - pocketR)],
    ];
    for (final seg in segs) {
      final bd = BodyDef()..type = BodyType.static;
      final shape = EdgeShape()..set(seg[0], seg[1]);
      world.createBody(bd).createFixture(FixtureDef(shape)
        ..friction = 0.25
        ..restitution = 0.65);
    }
  }

  void _buildPocketSensors() {
    for (final pos in _pocketPositions) {
      final bd = BodyDef()
        ..type = BodyType.static
        ..position = pos;
      world.createBody(bd)
          .createFixture(FixtureDef(CircleShape()..radius = pocketR)..isSensor = true);
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
      (_ball1Pos, Color(0xFFF1C40F), 1),  // 1 — yellow
      (_ball2Pos, Color(0xFFE74C3C), 2),  // 2 — red
      (_ball3Pos, Color(0xFF3498DB), 3),  // 3 — blue
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
  static Vector2 _ball1Pos() => Vector2(tableW * 0.28, tableH * 0.22);
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

  double get autoAimAngle {
    final target = currentTarget;
    if (target == null) return 0;
    final pocket = _nearestPocket(target.body.position);
    final ghost  = _ghostBall(target.body.position, pocket);
    final diff   = ghost - cueBall.body.position;
    return atan2(diff.y, diff.x);
  }

  /// Returns where the cue ball is PREDICTED to travel after impact
  /// given the current hitPoint spin setting.
  Vector2 predictedCueBallPath(double length) {
    final target = currentTarget;
    if (target == null) return cueBall.body.position;
    final pocket      = _nearestPocket(target.body.position);
    final ghostPos    = _ghostBall(target.body.position, pocket);
    final cueDir      = (ghostPos - cueBall.body.position).normalized();
    final perpDir     = Vector2(-cueDir.y, cueDir.x);
    final spin        = hitPointNotifier.value;
    // Back spin (dy>0) reverses, topspin (dy<0) follows through
    final mixed       = perpDir + cueDir * (-spin.dy * 0.8);
    return ghostPos + mixed.normalized() * length;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Vector2 _nearestPocket(Vector2 pos) {
    Vector2 best = _pocketPositions[0];
    double bestD = (_pocketPositions[0] - pos).length;
    for (int i = 1; i < _pocketPositions.length; i++) {
      final d = (_pocketPositions[i] - pos).length;
      if (d < bestD) { bestD = d; best = _pocketPositions[i]; }
    }
    return best;
  }

  Vector2 _ghostBall(Vector2 obj, Vector2 pocket) {
    final dir = (pocket - obj).normalized();
    return obj - dir * (BallComponent.radius * 2);
  }

  // ── Shoot ──────────────────────────────────────────────────────────────────
  void shoot({required Offset hitPoint, required double power}) {
    if (stateNotifier.value == GameState.rolling) return;
    hitPointNotifier.value = hitPoint;

    // Save snapshot BEFORE shot
    _saveSnapshot();

    final angle   = autoAimAngle;
    const maxForce = 190.0;
    final force   = Vector2(cos(angle), sin(angle)) * (power * maxForce);
    final lateral = Vector2(-sin(angle), cos(angle)) * (hitPoint.dx * power * 12.0);
    final angImp  = hitPoint.dx * power * 3.5;

    cueBall.body.applyLinearImpulse(force);
    cueBall.body.applyLinearImpulse(lateral);
    cueBall.body.applyAngularImpulse(angImp);

    stateNotifier.value    = GameState.rolling;
    _prevPocketedCount     = objectBalls.where((b) => !b.inPlay).length;
    canUndoNotifier.value  = _snapshots.isNotEmpty;
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
      objectStates: objectBalls.map((b) =>
          _BallState(b.body.position.clone(), b.inPlay)).toList(),
      targetIndex: _currentTargetIndex,
    ));
  }

  void _restoreSnapshot(_PoolSnapshot snap) {
    // Stop all motion
    for (final ball in [cueBall, ...objectBalls]) {
      if (ball.isLoaded) {
        ball.body.linearVelocity  = Vector2.zero();
        ball.body.angularVelocity = 0;
      }
    }
    // Restore cue ball
    cueBall.body.setTransform(snap.cueBallPos, 0);
    cueBall.inPlay = true;

    // Restore object balls
    for (int i = 0; i < objectBalls.length; i++) {
      final ball  = objectBalls[i];
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
    lastScoreNotifier.value = null;
    stateNotifier.value = GameState.aiming;
  }

  // ── Update loop ────────────────────────────────────────────────────────────
  bool get _anyBallMoving => <BallComponent>[cueBall, ...objectBalls]
      .any((b) => b.inPlay && b.body.linearVelocity.length2 > 0.01);

  @override
  void update(double dt) {
    super.update(dt);
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
    if (cueBall.inPlay) {
      for (final pocket in _pocketPositions) {
        if ((cueBall.body.position - pocket).length < pocketR * 0.9) {
          _onCueScratch();
          return;
        }
      }
    }
    for (final ball in objectBalls) {
      if (!ball.inPlay || !ball.isLoaded) continue;
      for (final pocket in _pocketPositions) {
        if ((ball.body.position - pocket).length < pocketR * 0.9) {
          ball.pocket();
          break;
        }
      }
    }
  }

  void _onCueScratch() {
    stateNotifier.value = GameState.scratch;
    cueBall.body.linearVelocity  = Vector2.zero();
    cueBall.body.angularVelocity = 0;
    cueBall.body.setTransform(Vector2(tableW / 2, tableH * 0.78), 0);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (stateNotifier.value != GameState.rolling) {
        stateNotifier.value = GameState.aiming;
      }
    });
  }

  void _onBallsStopped() {
    final nowPocketed   = objectBalls.where((b) => !b.inPlay).length;
    final justPocketed  = nowPocketed - _prevPocketedCount;

    if (justPocketed > 0) {
      final alive = objectBalls.where((b) => b.inPlay).toList();
      if (alive.isEmpty) {
        stateNotifier.value = GameState.cleared;
        return;
      }

      stateNotifier.value = GameState.scored;
      final next = nextTarget ?? (objectBalls.where((b) => b.inPlay).toList()..sort((a,b)=>a.number.compareTo(b.number))).firstOrNull;
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
    } else {
      stateNotifier.value = GameState.aiming;
    }

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (stateNotifier.value != GameState.rolling) {
        stateNotifier.value = GameState.aiming;
      }
    });
  }
}
