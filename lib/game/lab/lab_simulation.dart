import 'dart:math' show sqrt;
import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;

/// A ball in the simulation — position, velocity, and play state.
class SimBall {
  Vector2 pos;
  Vector2 vel;
  bool inPlay;

  static const double radius = 0.30;

  SimBall(Vector2 pos, Vector2 vel, {this.inPlay = true})
      : pos = pos.clone(),
        vel = vel.clone();
}

enum _EventKind { ballBall, wall }

/// Pure-Dart, event-driven billiards simulation based on python-billiards.
///
/// Algorithm:
///   1. Find the minimum TOI (time of impact) among all possible events.
///   2. Advance every ball to that TOI (with damping and spin forces).
///   3. Resolve the event (elastic collision or wall reflection).
///   4. Repeat until the frame dt is consumed.
///
/// Collision formulas are taken directly from python-billiards/physics.py.
class LabSimulation {
  // ── Table geometry ──────────────────────────────────────────────────────────
  static const double tableW = 11.0;
  static const double tableH = 22.0;
  static const double _r = SimBall.radius;

  // Ball-centre boundary (ball centre must stay within these limits)
  static const double _minX = _r;
  static const double _maxX = tableW - _r;
  static const double _minY = _r;
  static const double _maxY = tableH - _r;

  // ── Physics constants ───────────────────────────────────────────────────────
  static const double kMaxForce = 120.0; // max cue-ball speed (units/s at power=1)
  static const double kDamping = 1.2; // felt rolling damping (s⁻¹)
  // Cushion: normal direction loses energy, tangential direction nearly free
  static const double kCushionRestitution    = 0.78; // normal-component keep after cushion
  static const double kCushionTangentialKeep = 0.97; // tangential-component keep after cushion
  static const double kRailSpinDecay = 0.50; // spin fraction lost on cushion
  static const double kBallSpinDecay = 0.20; // spin fraction lost on ball-ball hit
  static const double kBallSpinCollisionDeduction = 0.03;
  static const double kPreSpinDecayRate = 0.08; // spin-to-roll rate (/ power²)
  static const double kPreSpinForce = 20.0; // pre-collision spin push force (N)
  static const double kSpinMaxDuration = 0.25; // max post-collision topspin time (s)
  static const double kSpinForce = 70.0; // post-collision topspin force (N)
  static const double kFollowThreshold = 1.0; // power above which stun is enforced
  static const double kFollowScale = 0.45; // fraction of forward speed kept (no-spin follow)
  // Spin influence on post-collision cue-ball direction:
  //   topspin → adds forward component; backspin → subtracts (creates draw)
  static const double kSpinCollisionInfluence = 0.50;
  static const double kSideSpinThrowFraction = 0.5;
  static const double kSideSpinSurfaceSpeed = 3.5; // reduced to prevent extreme reversal
  static const double kSideSpinRailFriction = 0.55;

  // ── Balls (index 0 = cue, index 1 = target) ────────────────────────────────
  final List<SimBall> balls;

  // ── Spin / shot state ───────────────────────────────────────────────────────
  double preCollisionSpin = 0.0;
  double spinRemaining = 0.0;
  double _spinAtCollision = 0.0; // |preCollisionSpin| captured at first ball-ball hit
  double _spinTotalDuration = 0.0;
  double currentSideSpin = 0.0;
  bool firstCollisionDone = false;
  Vector2 shotDir = Vector2(1, 0);
  double lastPower = 0.5;
  double lastSpin = 0.0;

  // ── Event callbacks ─────────────────────────────────────────────────────────
  /// Called when the cue ball reflects off a cushion.
  /// [isX] true → x-component was reflected (vertical cushion).
  /// [prevVel] is the cue-ball velocity just before the reflection.
  void Function(bool isX, Vector2 prevVel)? onCueBallRailBounce;

  /// Called when the two balls collide.
  void Function()? onBallCollision;

  LabSimulation({required Vector2 cuePos, required Vector2 targetPos})
      : balls = [
          SimBall(cuePos, Vector2.zero()),
          SimBall(targetPos, Vector2.zero()),
        ];

  bool get anyMoving => balls.any((b) => b.inPlay && b.vel.length2 > 0.01);

  // ── Main step ───────────────────────────────────────────────────────────────

  /// Advance the simulation by [dt] seconds using an event-driven loop.
  void step(double dt) {
    double tLeft = dt;
    const int maxIter = 40; // safety cap — should never be reached in practice
    int iter = 0;

    while (tLeft > 1e-9 && iter++ < maxIter) {
      // ── Find the next event within [tLeft] ─────────────────────────────────
      double tMin = tLeft;
      _EventKind? eventKind;
      int wallBallIdx = -1;
      bool wallIsX = false;

      // Ball-ball TOI (python-billiards: toi_ball_ball)
      if (balls[0].inPlay && balls[1].inPlay) {
        final t = _toiBallBall();
        if (t >= 0 && t < tMin) {
          tMin = t;
          eventKind = _EventKind.ballBall;
        }
      }

      // Wall TOIs for each ball (derived from python-billiards: toi_args_ball_line_onesided)
      for (int i = 0; i < balls.length; i++) {
        final b = balls[i];
        if (!b.inPlay) continue;

        double t;

        // Left wall  (x = _minX), outward normal (+1, 0) — hit when vel.x < 0
        if (b.vel.x < 0) {
          t = (_minX - b.pos.x) / b.vel.x;
          if (t >= 0 && t < tMin) {
            tMin = t;
            eventKind = _EventKind.wall;
            wallBallIdx = i;
            wallIsX = true;
          }
        }
        // Right wall (x = _maxX), outward normal (-1, 0) — hit when vel.x > 0
        if (b.vel.x > 0) {
          t = (_maxX - b.pos.x) / b.vel.x;
          if (t >= 0 && t < tMin) {
            tMin = t;
            eventKind = _EventKind.wall;
            wallBallIdx = i;
            wallIsX = true;
          }
        }
        // Top wall   (y = _minY), outward normal (0, +1) — hit when vel.y < 0
        if (b.vel.y < 0) {
          t = (_minY - b.pos.y) / b.vel.y;
          if (t >= 0 && t < tMin) {
            tMin = t;
            eventKind = _EventKind.wall;
            wallBallIdx = i;
            wallIsX = false;
          }
        }
        // Bottom wall (y = _maxY), outward normal (0, -1) — hit when vel.y > 0
        if (b.vel.y > 0) {
          t = (_maxY - b.pos.y) / b.vel.y;
          if (t >= 0 && t < tMin) {
            tMin = t;
            eventKind = _EventKind.wall;
            wallBallIdx = i;
            wallIsX = false;
          }
        }
      }

      // ── Advance all balls to tMin ───────────────────────────────────────────
      _advanceAll(tMin);

      // ── Resolve the event ───────────────────────────────────────────────────
      if (eventKind == _EventKind.ballBall) {
        _resolveElasticCollision();
        onBallCollision?.call();
      } else if (eventKind == _EventKind.wall) {
        final prevVel = balls[wallBallIdx].vel.clone();
        _resolveWall(wallBallIdx, wallIsX);
        if (wallBallIdx == 0) {
          onCueBallRailBounce?.call(wallIsX, prevVel);
        }
      }

      tLeft -= tMin;
    }

    // Safety clamp — should be a no-op under normal conditions
    for (final b in balls) {
      if (!b.inPlay) continue;
      b.pos.x = b.pos.x.clamp(_minX, _maxX);
      b.pos.y = b.pos.y.clamp(_minY, _maxY);
    }
  }

  // ── Advance + damping + spin ─────────────────────────────────────────────────

  void _advanceAll(double dt) {
    // Exponential velocity damping (felt friction): v *= e^(-kDamping*dt)
    // Numerically stable form: divide by (1 + kDamping*dt)
    final dampFactor = 1.0 / (1.0 + kDamping * dt);
    for (final b in balls) {
      if (!b.inPlay) continue;
      b.pos += b.vel * dt;
      b.vel *= dampFactor;
    }
    _applySpinStep(dt);
  }

  // ── TOI: ball-ball (python-billiards toi_ball_ball) ─────────────────────────
  //
  // Two balls collide when |pos1 + t·vel1 - (pos2 + t·vel2)| = 2r.
  // Let dpos = pos1 - pos2, dvel = vel1 - vel2.
  // Expand: |dpos + t·dvel|² = (2r)²
  //   ⟹ <v,v>t² + 2<p,v>t + (<p,p> - (2r)²) = 0
  // The smaller root is the time of impact.
  // Numerically stable form: t = c / (-b + √Δ) where b = <p,v>, c = <p,p>-(2r)².

  double _toiBallBall() {
    final b1 = balls[0];
    final b2 = balls[1];

    final dpos = b1.pos - b2.pos;
    final dvel = b1.vel - b2.vel;

    final posDotVel = dpos.dot(dvel);
    if (posDotVel >= 0) return double.infinity; // balls not approaching

    final speedSqrd = dvel.dot(dvel);
    if (speedSqrd < 1e-14) return double.infinity;

    final rsum = SimBall.radius * 2.0;
    final rsumSqrd = rsum * rsum;
    final distSqrd = dpos.dot(dpos);

    // Numerically stable discriminant: Δ/4 = |v|²·(2r)² - |p×v|²
    final cross = dpos.x * dvel.y - dpos.y * dvel.x;
    final deltaOver4 = speedSqrd * rsumSqrd - cross * cross;
    if (deltaOver4 <= 0) return double.infinity; // balls miss

    final cMinusR2 = distSqrd - rsumSqrd;
    if (cMinusR2 < 0) return double.infinity; // already overlapping — skip

    // t₁ = c / (-b + √(Δ/4))  (python-billiards numerically stable form)
    return cMinusR2 / (-posDotVel + sqrt(deltaOver4));
  }

  // ── Elastic collision (python-billiards elastic_collision) ───────────────────
  //
  // For balls of equal mass m:
  //   impulse = 2·<dpos, dvel> / (2m · |dpos|²) · dpos
  //           = <dpos, dvel> / |dpos|² · dpos      (m = 1)
  //   new_vel1 = vel1 - impulse
  //   new_vel2 = vel2 + impulse

  void _resolveElasticCollision() {
    final b1 = balls[0]; // cue
    final b2 = balls[1]; // target

    final dpos = b1.pos - b2.pos; // vector from target to cue
    final dvel = b1.vel - b2.vel;

    final distSqrd = dpos.dot(dpos);
    if (distSqrd < 1e-12) return;

    final posDotVel = dpos.dot(dvel);
    if (posDotVel > 1e-6) return; // already moving apart

    // Save pre-collision cue velocity before it is modified
    final preCueVel = b1.vel.clone();

    // Apply elastic impulse
    final impulse = dpos * (posDotVel / distSqrd);
    b1.vel -= impulse; // = cueTangential + targetNormal
    b2.vel += impulse; // = targetTangential + cueNormal

    if (!firstCollisionDone) {
      firstCollisionDone = true;

      // Collision normal pointing from cue centre toward target centre
      final dist = sqrt(distSqrd);
      final normal = -dpos / dist; // = (b2.pos - b1.pos) / dist

      final cueNorm = preCueVel.dot(normal); // speed of cue along normal (positive = toward target)
      final cueTang = preCueVel - normal * cueNorm;

      // Follow/draw: power controls base stun→follow; spin adds or subtracts forward component.
      //   high power + no spin  → stun  (normalFactor ≈ 0)
      //   low  power + no spin  → slight follow
      //   any  power + topspin  → more forward (follow)
      //   any  power + backspin → backward component (draw)
      final followFraction = (1.0 - lastPower / kFollowThreshold).clamp(0.0, 1.0);
      final normalFactor = (followFraction * kFollowScale + lastSpin * kSpinCollisionInfluence)
          .clamp(-0.55, kFollowScale + kSpinCollisionInfluence);

      b1.vel = cueTang + normal * (cueNorm * normalFactor);

      // Side spin: deflects cue ball laterally proportional to cut-angle tangential speed
      if (currentSideSpin.abs() > 0.01) {
        final tang = Vector2(-normal.y, normal.x);
        final deflV = currentSideSpin * kSideSpinThrowFraction * cueTang.length;
        b1.vel += tang * deflV;
      }

      // Arm post-collision topspin budget only — backspin effect is already
      // encoded in the backward normal component above.
      _spinAtCollision = preCollisionSpin.abs();
      _spinTotalDuration = _spinAtCollision * kSpinMaxDuration * lastPower;
      if (lastSpin > 0 && _spinAtCollision > 0.01) {
        spinRemaining = (_spinTotalDuration - kBallSpinCollisionDeduction).clamp(0.0, double.infinity);
      }
    }

    _decaySpin(kBallSpinDecay);
  }

  // ── Wall reflection ──────────────────────────────────────────────────────────

  void _resolveWall(int ballIdx, bool isX) {
    final b = balls[ballIdx];

    // Cushion physics: normal direction loses energy (restitution < 1),
    // tangential direction has negligible friction — realistic reflection model.
    if (isX) {
      b.vel.x = -b.vel.x * kCushionRestitution;
      b.vel.y *= kCushionTangentialKeep;
    } else {
      b.vel.y = -b.vel.y * kCushionRestitution;
      b.vel.x *= kCushionTangentialKeep;
    }

    // Spin effects apply only to the cue ball
    if (ballIdx != 0) return;

    _decaySpin(kRailSpinDecay);

    if (currentSideSpin.abs() > 0.01) {
      final s = currentSideSpin;
      final f = kSideSpinRailFriction;

      if (isX) {
        // Vertical cushion: spin creates friction in the Y direction.
        // After reflection b.vel.x = -prevVel.x, so prevVel.x = -b.vel.x.
        final prevVelX = -b.vel.x;
        final spinSurf = (prevVelX > 0 ? -1.0 : 1.0) * s * kSideSpinSurfaceSpeed;
        b.vel.y = b.vel.y * (1.0 - f) + f * spinSurf;
      } else {
        // Horizontal cushion: spin creates friction in the X direction.
        final prevVelY = -b.vel.y;
        final spinSurf = (prevVelY > 0 ? 1.0 : -1.0) * s * kSideSpinSurfaceSpeed;
        b.vel.x = b.vel.x * (1.0 - f) + f * spinSurf;
      }
    }
  }

  // ── Spin forces (applied continuously between events) ────────────────────────

  void _applySpinStep(double dt) {
    final cue = balls[0];
    if (!cue.inPlay) return;

    // Pre-collision: slip-to-roll transition — spin decays and pushes/brakes cue ball
    if (!firstCollisionDone && preCollisionSpin.abs() > 0.001) {
      final decayRate = kPreSpinDecayRate / (lastPower * lastPower + 0.1);
      final step = decayRate * dt;

      if (preCollisionSpin > 0) {
        preCollisionSpin = (preCollisionSpin - step).clamp(0.0, 1.0);
      } else {
        preCollisionSpin = (preCollisionSpin + step).clamp(-1.0, 0.0);
      }

      if (cue.vel.length2 > 0.0001) {
        final dir = preCollisionSpin < 0 ? -(cue.vel.normalized()) : cue.vel.normalized();
        cue.vel += dir * (preCollisionSpin.abs() * kPreSpinForce * lastPower * lastPower * dt);
      }
    }

    // Post-collision topspin: accelerates cue ball along its current travel direction.
    // Using current velocity direction (not fixed shotDir) means the force adapts after
    // rail bounces — no spurious reversals.
    if (firstCollisionDone && spinRemaining > 0 && cue.vel.length2 > 0.001) {
      final fade = _spinTotalDuration > 0 ? (spinRemaining / _spinTotalDuration).clamp(0.0, 1.0) : 0.0;
      final forceMag = _spinAtCollision * kSpinForce * fade * lastPower;
      cue.vel += cue.vel.normalized() * (forceMag * dt);
      spinRemaining = (spinRemaining - dt).clamp(0.0, double.infinity);
    }
  }

  // ── Spin decay ───────────────────────────────────────────────────────────────

  void _decaySpin(double fraction) {
    final keep = 1.0 - fraction;
    preCollisionSpin *= keep;
    spinRemaining *= keep;
    currentSideSpin *= keep;
  }
}
