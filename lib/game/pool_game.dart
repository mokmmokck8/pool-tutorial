import 'dart:math';
import 'dart:ui' show Offset;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Colors, Color, ValueNotifier;
import 'components/ball_component.dart';
import 'components/table_component.dart';
import 'components/aim_overlay.dart';
import 'shot_evaluator.dart';

enum GameState { idle, aiming, rolling, scored, scratch }

class PoolGame extends Forge2DGame {
  final void Function(int score, String label) onShotEvaluated;

  PoolGame({required this.onShotEvaluated})
      : super(gravity: Vector2.zero(), zoom: 10);

  final stateNotifier = ValueNotifier<GameState>(GameState.aiming);

  late BallComponent cueBall;
  final List<BallComponent> objectBalls = [];
  late TableComponent table;
  late AimOverlay aimOverlay;

  int _currentTargetIndex = 0;
  bool _ballsMoving = false;
  int _prevPocketedCount = 0;

  static const double tableW = 22.0;
  static const double tableH = 11.0;
  static const double rail = TableComponent.railThickness;
  static const double pocketR = TableComponent.pocketRadius;

  final List<Vector2> _pocketPositions = <Vector2>[];

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Fix camera position: use setter (not setValues which modifies a copy)
    // forge2d 0.14 and flame both use vector_math 32-bit Vector2 — no type conflict
    camera.viewfinder.position = Vector2(tableW / 2, tableH / 2);
    camera.viewfinder.zoom = 10;

    // Pocket positions
    final hw = tableW / 2;
    _pocketPositions.addAll(<Vector2>[
      Vector2(rail, rail),
      Vector2(hw, rail * 0.5),
      Vector2(tableW - rail, rail),
      Vector2(rail, tableH - rail),
      Vector2(hw, tableH - rail * 0.5),
      Vector2(tableW - rail, tableH - rail),
    ]);

    _buildWalls();
    _buildPocketSensors();

    table = TableComponent(
      tableWidth: tableW,
      tableHeight: tableH,
      pocketPositions: _pocketPositions,
    );
    await add(table);

    _spawnBalls();

    aimOverlay = AimOverlay(game: this);
    await add(aimOverlay);
  }

  void _buildWalls() {
    final segs = <List<Vector2>>[
      [Vector2(rail + pocketR, rail), Vector2(tableW / 2 - pocketR, rail)],
      [Vector2(tableW / 2 + pocketR, rail), Vector2(tableW - rail - pocketR, rail)],
      [Vector2(rail + pocketR, tableH - rail), Vector2(tableW / 2 - pocketR, tableH - rail)],
      [Vector2(tableW / 2 + pocketR, tableH - rail), Vector2(tableW - rail - pocketR, tableH - rail)],
      [Vector2(rail, rail + pocketR), Vector2(rail, tableH - rail - pocketR)],
      [Vector2(tableW - rail, rail + pocketR), Vector2(tableW - rail, tableH - rail - pocketR)],
    ];
    for (final seg in segs) {
      final bd = BodyDef()..type = BodyType.static;
      final shape = EdgeShape()..set(seg[0], seg[1]);
      world.createBody(bd)
          .createFixture(FixtureDef(shape)
            ..friction = 0.2
            ..restitution = 0.65);
    }
  }

  void _buildPocketSensors() {
    for (final pos in _pocketPositions) {
      final bd = BodyDef()
        ..type = BodyType.static
        ..position = pos;
      final shape = CircleShape()..radius = pocketR;
      world.createBody(bd).createFixture(FixtureDef(shape)..isSensor = true);
    }
  }

  void _spawnBalls() {
    cueBall = BallComponent(
      position: Vector2(tableW * 0.25, tableH / 2),
      color: Colors.white,
      number: 0,
      isCue: true,
    );
    add(cueBall);

    final rackCenter = Vector2(tableW * 0.65, tableH / 2);
    const spacing = BallComponent.radius * 2.1;
    final positions = _rackPositions(rackCenter, spacing);

    const colors = <Color>[
      Color(0xFFF1C40F), Color(0xFF3498DB), Color(0xFFE74C3C),
      Color(0xFF9B59B6), Color(0xFFE67E22), Color(0xFF1ABC9C),
      Color(0xFF8B0000), Color(0xFF111111), Color(0xFFF1C40F),
      Color(0xFF3498DB), Color(0xFFE74C3C), Color(0xFF9B59B6),
      Color(0xFFE67E22), Color(0xFF1ABC9C), Color(0xFF8B0000),
    ];

    for (int i = 0; i < positions.length; i++) {
      final ball = BallComponent(
        position: positions[i],
        color: colors[i % colors.length],
        number: i + 1,
      );
      objectBalls.add(ball);
      add(ball);
    }
  }

  List<Vector2> _rackPositions(Vector2 center, double s) {
    final r = sqrt(3) / 2;
    return <Vector2>[
      center.clone(),
      center + Vector2(-s, -s * r),
      center + Vector2(-s, s * r),
      center + Vector2(-2 * s, -2 * s * r),
      center + Vector2(-2 * s, 0),
      center + Vector2(-2 * s, 2 * s * r),
      center + Vector2(-3 * s, -3 * s * r),
      center + Vector2(-3 * s, -s * r),
      center + Vector2(-3 * s, s * r),
      center + Vector2(-3 * s, 3 * s * r),
      center + Vector2(-4 * s, -4 * s * r),
      center + Vector2(-4 * s, -2 * s * r),
      center + Vector2(-4 * s, 0),
      center + Vector2(-4 * s, 2 * s * r),
      center + Vector2(-4 * s, 4 * s * r),
    ];
  }

  List<Vector2> get pocketPositions => _pocketPositions;

  BallComponent? get currentTarget {
    final alive = objectBalls.where((b) => b.inPlay).toList();
    if (alive.isEmpty) return null;
    if (_currentTargetIndex >= alive.length) _currentTargetIndex = 0;
    return alive[_currentTargetIndex];
  }

  double get autoAimAngle {
    final target = currentTarget;
    if (target == null) return 0;
    final pocket = _nearestPocket(target.body.position);
    final ghost = _ghostBall(target.body.position, pocket);
    final diff = ghost - cueBall.body.position;
    return atan2(diff.y, diff.x);
  }

  Vector2 _nearestPocket(Vector2 ballPos) {
    Vector2 best = _pocketPositions[0];
    double bestDist = (_pocketPositions[0] - ballPos).length;
    for (int i = 1; i < _pocketPositions.length; i++) {
      final d = (_pocketPositions[i] - ballPos).length;
      if (d < bestDist) { bestDist = d; best = _pocketPositions[i]; }
    }
    return best;
  }

  Vector2 _ghostBall(Vector2 obj, Vector2 pocket) {
    final dir = (pocket - obj).normalized();
    return obj - dir * (BallComponent.radius * 2);
  }

  void shoot({required Offset hitPoint, required double power}) {
    if (stateNotifier.value == GameState.rolling) return;

    final angle = autoAimAngle;
    const maxForce = 180.0;
    final force = Vector2(cos(angle), sin(angle)) * (power * maxForce);
    final lateral = Vector2(-sin(angle), cos(angle)) * (hitPoint.dx * power * 10.0);
    final angularImpulse = hitPoint.dx * power * 3.5;

    cueBall.body.applyLinearImpulse(force);
    cueBall.body.applyLinearImpulse(lateral);
    cueBall.body.applyAngularImpulse(angularImpulse);

    stateNotifier.value = GameState.rolling;
    _prevPocketedCount = objectBalls.where((b) => !b.inPlay).length;
  }

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
    cueBall.body.linearVelocity = Vector2.zero();
    cueBall.body.angularVelocity = 0;
    cueBall.body.setTransform(Vector2(tableW * 0.25, tableH / 2), 0);
    Future.delayed(const Duration(milliseconds: 1500), () {
      stateNotifier.value = GameState.aiming;
    });
  }

  void _onBallsStopped() {
    final nowPocketed = objectBalls.where((b) => !b.inPlay).length;
    final justPocketed = nowPocketed - _prevPocketedCount;

    if (justPocketed > 0) {
      _currentTargetIndex = 0;
      stateNotifier.value = GameState.scored;

      final nextTarget = currentTarget;
      if (nextTarget != null) {
        final eval = ShotEvaluator.evaluate(
          cueBallPos: cueBall.body.position,
          nextTarget: nextTarget.body.position,
          pockets: _pocketPositions,
          tableW: tableW,
          tableH: tableH,
        );
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
