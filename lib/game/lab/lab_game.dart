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

  // ══════════════════════════════════════════════════════════════════════════
  // 可調整參數（Tunable parameters）
  // ══════════════════════════════════════════════════════════════════════════

  // ── 出桿力道 ───────────────────────────────────────────────────────────────
  /// 母球每次擊打的最大衝力（N·s）。
  /// 增大 → 球速更快；減小 → 球速更慢。
  static const double kMaxForce = 80.0;

  // ── 循跡取樣 ────────────────────1──────────────────────────────────────────
  /// 母球軌跡相鄰取樣點的最小距離（物理單位）。
  /// 增大 → 軌跡點較稀疏；減小 → 軌跡點較密集。
  static const double kTrailSampleDist = 0.18;

  // ── 碰前旋轉衰減 ──────────────────────────────────────────────────────────
  /// 旋轉衰減基礎速率（spin units / 秒，力道 = 1 時的值）。
  ///   decayRate = kPreSpinDecayRate / (power² + 0.1)
  /// 增大 → 低力道時旋轉消失更快（球更早進入自然滾動）。
  static const double kPreSpinDecayRate = 0.2;

  /// 碰前旋轉對母球施加的額外摩擦力（N / spin unit）。
  /// 增大 → 上旋加速 / 下旋減速效果更明顯；減小 → 效果更微弱。
  static const double kPreSpinForce = 18.0;

  // ── 碰後旋轉效果 ──────────────────────────────────────────────────────────
  /// 碰後旋轉力持續的最長時間（秒，對應 spin = ±1 時）。
  /// 增大 → 上旋 / 下旋延伸效果持續更久。
  static const double kSpinMaxDuration = 0.5;

  /// 碰後旋轉對母球施加的力大小（N）。
  /// 增大 → 上旋追球 / 下旋煞車效果更強。
  static const double kSpinForce = 80.0;

  // ── 跟進（Follow）效果 ────────────────────────────────────────────────────
  /// 力道超過此閾值時，母球不再跟進（純定桿）。
  /// 減小 → 更難觸發跟進；增大 → 高力道也有跟進效果。
  static const double kFollowThreshold = 0.65;

  /// 跟進效果最大前進速度比例（0 = 完全不跟進，1 = 全速跟進）。
  /// 增大 → 跟進路徑更長；減小 → 跟進路徑更短。
  static const double kFollowScale = 0.45;

  // ── 旋轉碰撞衰減 ──────────────────────────────────────────────────────────
  /// 母球碰庫（反彈）時，剩餘旋轉量減少的比例（0 = 不衰減，1 = 完全消失）。
  /// 增大 → 碰庫後旋轉效果更快消失。
  static const double kRailSpinDecay = 0.25;

  /// 母球碰到目標球時，旋轉量減少的比例（0 = 不衰減，1 = 完全消失）。
  /// 增大 → 碰球後旋轉效果更快消失。
  static const double kBallSpinDecay = 0.20;

  // ── 碰庫動能損耗 ──────────────────────────────────────────────────────────
  /// 母球每次碰庫後速度保留的比例（1.0 = 完全彈性，無損耗）。
  /// Box2D 的 restitution 合成用 max()，牆的設定對高 restitution 的球無效，
  /// 因此在偵測到碰庫後直接縮減速度來模擬能量損失。
  /// 減小 → 碰庫後球速更快衰減；建議範圍 0.90 ~ 0.98。
  static const double kRailVelocityKeep = 0.94;

  // ── 庫邊軟硬度（Cushion softness）────────────────────────────────────────
  /// 大力撞庫時切向速度（沿庫邊方向）最多被吸收的比例。
  /// softness = 0 時不吸收（完全硬庫）；softness = 1 時以最大比例吸收。
  /// 吸收量隨法向衝擊速度線性增加，模擬「越大力打庫，反射角越小」的真實感。
  static const double kCushionMaxAngleReduction = 0.10;

  /// 達到最大吸收效果的參考撞庫法向速度（物理單位 / 秒）。
  /// 法向速度超過此值後吸收量不再增加（clamp 至 1.0）。
  static const double kCushionRefSpeed = 18.0;

  // ══════════════════════════════════════════════════════════════════════════

  // ── Public notifiers ─────────────────────────────────────────────────────
  final stateNotifier = ValueNotifier<LabState>(LabState.aiming);

  /// 庫邊軟硬度（0.0 = 全硬，1.0 = 全軟）。可由 UI 動態調整。
  double cushionSoftness = 0.3;

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
  double _cueDist = 6.0;

  final List<Vector2> _pocketPositions = [];
  final Map<BallComponent, Vector2> _prevPositions = {};

  // ── Shot state ────────────────────────────────────────────────────────────
  bool _gameLoaded        = false;
  bool _ballsMoving       = false;
  bool _ballsContacting   = false;
  bool _firstCollisionDone = false;
  double _lastPower       = 0.5;
  double _lastSpin        = 0.0;
  double _lastCutAngle    = 0.0;
  Vector2 _prevCueVel     = Vector2.zero();
  Vector2 _prevTargetVel  = Vector2.zero();
  Vector2 _shotDir        = Vector2(1, 0);

  // ── Cue ball trail ────────────────────────────────────────────────────────
  final List<Vector2> cueTrail = [];

  // ── Pre-collision spin state ──────────────────────────────────────────────
  double _preCollisionSpin = 0.0;

  // ── Post-collision spin state ─────────────────────────────────────────────
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
    _lastCutAngle = degrees;
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

  void setDistance(double dist) {
    _cueDist = dist;
    if (_gameLoaded) setCutAngle(_lastCutAngle);
  }

  void shoot({required double power, double spin = 0.0}) {
    if (stateNotifier.value != LabState.aiming) return;
    _lastPower     = power;
    _lastSpin      = spin.clamp(-1.0, 1.0);
    _ballsContacting    = false;
    _firstCollisionDone = false;
    _spinRemaining      = 0.0;
    _preCollisionSpin   = _lastSpin;
    cueTrail.clear();

    final angle = _autoAimAngle;
    _shotDir = Vector2(cos(angle), sin(angle));

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
    _detectRailBounce();
    _applyPreCollisionSpin(dt);
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
        (pos - cueTrail.last).length >= kTrailSampleDist) {
      cueTrail.add(pos);
    }
  }

  // ── Manual ball-ball collision ────────────────────────────────────────────
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

      // Arm post-collision spin using whatever spin survived the pre-collision decay.
      // Duration also scales with power: at low power the ball is slow, so
      // spin-to-roll transition completes faster → shorter effect.
      if (_preCollisionSpin.abs() > 0.01) {
        _spinRemaining = _preCollisionSpin.abs() * kSpinMaxDuration * _lastPower;
      }
    }

    cueBall.body.linearVelocity    = newCueVel;
    targetBall.body.linearVelocity = newTargetVel;

    // Spin loses energy on contact with another ball
    _decaySpin(kBallSpinDecay);
  }

  // ── Spin decay helpers ────────────────────────────────────────────────────

  /// Reduce both spin states by [fraction] (0 = no change, 1 = zeroed out).
  void _decaySpin(double fraction) {
    final keep = 1.0 - fraction;
    _preCollisionSpin *= keep;
    _spinRemaining    *= keep;
  }

  /// Detect a rail bounce by comparing the cue ball's velocity sign before and
  /// after the physics step.  A reversal in either axis with enough speed means
  /// the ball just reflected off a cushion.
  void _detectRailBounce() {
    if (stateNotifier.value != LabState.rolling) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) return;

    const minSpeed = 0.5; // ignore tiny velocities (avoid false positives at rest)
    final prev = _prevCueVel;
    final curr = cueBall.body.linearVelocity;

    final xBounce = prev.x.abs() > minSpeed && curr.x * prev.x < 0;
    final yBounce = prev.y.abs() > minSpeed && curr.y * prev.y < 0;

    if (xBounce || yBounce) {
      _decaySpin(kRailSpinDecay);

      // ── Cushion angle reduction ───────────────────────────────────────────
      // 軟庫吸收切向（沿庫邊）速度，使反射角隨撞庫力道增大而縮小。
      // xBounce → 法向為 X；切向為 Y（沿水平庫邊）。
      // yBounce → 法向為 Y；切向為 X（沿垂直庫邊）。
      if (cushionSoftness > 0) {
        var vel = cueBall.body.linearVelocity;
        if (xBounce) {
          final impactFraction = (prev.x.abs() / kCushionRefSpeed).clamp(0.0, 1.0);
          final reduction = cushionSoftness * impactFraction * kCushionMaxAngleReduction;
          vel = Vector2(vel.x, vel.y * (1.0 - reduction));
        }
        if (yBounce) {
          final impactFraction = (prev.y.abs() / kCushionRefSpeed).clamp(0.0, 1.0);
          final reduction = cushionSoftness * impactFraction * kCushionMaxAngleReduction;
          vel = Vector2(vel.x * (1.0 - reduction), vel.y);
        }
        cueBall.body.linearVelocity = vel;
      }

      // Manually bleed off kinetic energy — Box2D max(restitution) mixing
      // means the wall's lower restitution has no effect when the ball's is higher.
      cueBall.body.linearVelocity =
          cueBall.body.linearVelocity * kRailVelocityKeep;
    }
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

  // ── Pre-collision spin-to-roll transition ─────────────────────────────────
  //
  // Models felt friction converting the ball's initial spin into natural forward
  // roll.  _preCollisionSpin decays linearly toward 0 at a rate that is faster
  // the lower the power (less forward momentum to resist friction).
  //
  //   backspin (_preCollisionSpin < 0): backward force → extra deceleration
  //   topspin  (_preCollisionSpin > 0): forward force  → slight acceleration
  //
  // Once _preCollisionSpin reaches 0 the ball rolls naturally (no extra force).
  // At collision time whatever spin remains becomes the post-collision spin budget.
  //
  void _applyPreCollisionSpin(double dt) {
    if (_firstCollisionDone) return;
    if (stateNotifier.value != LabState.rolling) return;
    if (!cueBall.isLoaded || !cueBall.inPlay) return;
    if (_preCollisionSpin.abs() < 0.001) return;

    // Decay rate: inversely proportional to power² so low-power shots lose
    // their spin quickly and arrive as a naturally rolling ball.
    final decayRate = kPreSpinDecayRate / (_lastPower * _lastPower + 0.1);
    final step = decayRate * dt;

    if (_preCollisionSpin > 0) {
      _preCollisionSpin = (_preCollisionSpin - step).clamp(0.0, 1.0);
    } else {
      _preCollisionSpin = (_preCollisionSpin + step).clamp(-1.0, 0.0);
    }

    // Apply friction force proportional to remaining spin
    final vel = cueBall.body.linearVelocity;
    if (vel.length < 0.01) return;
    final forceDir = _preCollisionSpin < 0 ? -(vel.normalized()) : vel.normalized();
    cueBall.body.applyForce(forceDir * (_preCollisionSpin.abs() * kPreSpinForce));
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

    final totalDuration = _preCollisionSpin.abs() * kSpinMaxDuration;
    // Linear fade: full force at start, zero at end
    final fade      = totalDuration > 0 ? (_spinRemaining / totalDuration).clamp(0.0, 1.0) : 0.0;
    final spinDir   = _lastSpin > 0 ? _shotDir : -_shotDir;
    final forceMag  = _preCollisionSpin.abs() * kSpinForce * fade;

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
