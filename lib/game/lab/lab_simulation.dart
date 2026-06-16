import 'dart:math' show sqrt, atan2;
import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;

/// A ball in the simulation.
///
/// [spinSurf] is the in-plane "spin surface velocity" R·ω of the ball about a
/// horizontal axis — i.e. the velocity the contact point would have purely from
/// top/back spin.  Pure rolling means `spinSurf == vel` (contact point still).
/// [sideSpin] is a normalized proxy for ωz (English about the vertical axis).
class SimBall {
  Vector2 pos;
  Vector2 vel;
  Vector2 spinSurf;
  double sideSpin;
  bool inPlay;

  static const double radius = 0.30;

  SimBall(
    Vector2 pos,
    Vector2 vel, {
    Vector2? spinSurf,
    this.sideSpin = 0.0,
    this.inPlay = true,
  })  : pos = pos.clone(),
        vel = vel.clone(),
        spinSurf = (spinSurf ?? Vector2.zero()).clone();
}

enum _EventKind { ballBall, wall }

/// Pure-Dart, event-driven billiards simulation.
///
/// Architecture (event-driven, straight segments):
///   1. Find the minimum TOI (time of impact) among all possible events,
///      capped to [kMaxSubStep] so friction/spin integrate accurately.
///   2. Advance every ball over that step (cloth friction + slip→roll).
///   3. If the step actually reached an event, resolve it.
///   4. Repeat until the frame dt is consumed.
///
/// Physics model:
///   • Ball motion uses the rigid-body slip→roll friction of Han, "Dynamics in
///     Carom and Three Cushion Billiards" (J. Mech. Sci. Tech., 2005),
///     Eqs. (1)–(8).  A struck ball slides (kinetic friction drives the contact
///     slip toward zero) then rolls (small rolling resistance), so follow / draw
///     / stun emerge naturally from the cue ball's retained spin — no per-shot
///     heuristics.  Friction is projected onto the line of travel, so the path
///     stays straight (no masse / swerve, by design).
///   • Ball-ball impact is frictionless, equal-mass, e = 0.98 (Han Eq. 11).
///   • Cushion restitution varies with normal speed (Han Eq. 26) and cushion
///     friction varies with incidence angle (Han Eq. 27).
///   • TOI / elastic-impulse formulas follow python-billiards/physics.py.
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

  // ── Scale ───────────────────────────────────────────────────────────────────
  // Sim units → metres.  Short rail 11 u ≈ 1.27 m  →  ~0.1155 m/u.
  // Only used where Han's empirical formulas genuinely need SI (cushion e vs V).
  static const double kMetersPerUnit = 0.1155;

  // ── Shot power ──────────────────────────────────────────────────────────────
  static const double kMaxForce = 120.0; // cue-ball speed at power = 1 (units/s)

  // ── Cloth friction (constant decelerations, units/s²) — tunable for feel ────
  static const double kSlideDecel = 34.0; // sliding-phase deceleration (slip ≠ 0)
  static const double kRollDecel = 9.0; //  pure-rolling resistance (Han Eq. 8, lumped)
  static const double kRollEps = 0.05; //   |slip| below this ⇒ treat as pure rolling
  static const double kStopEps = 0.15; //   speed below this (and rolling) ⇒ stopped

  // Cue tip vertical offset → initial top/back spin: spinSurf0 = gain·spin·v0.
  // spin ∈ [-1, 1]:  +1 strong follow, 0 natural roll-up, −1 strong draw.
  static const double kTipSpinGain = 2.0;

  // Integration sub-step cap (s).  Keeps the slip→roll transition and the
  // straight-line TOI approximation accurate within a segment.
  static const double kMaxSubStep = 0.004;

  // ── Ball-ball impact (frictionless, Han Eq. 11) ─────────────────────────────
  static const double kBallRestitution = 0.98; // measured e between balls
  static const double kBallSideThrow = 0.10; //   English → tangential throw at contact
  static const double kBallSpinDecay = 0.20; //   side-spin lost on a ball-ball hit

  // ── Cushion impact ──────────────────────────────────────────────────────────
  // Restitution vs normal approach speed V [m/s]:  e = 0.39 + 0.257 V − 0.044 V²
  static const double kCushE0 = 0.39, kCushE1 = 0.257, kCushE2 = 0.044; // Han Eq. 26
  static const double kCushEMin = 0.50, kCushEMax = 0.95; // clamp outside fitted range
  // Friction vs incidence angle θ [rad] (0 = head-on):  μ = 0.471 − 0.241 θ
  static const double kCushMu0 = 0.471, kCushMu1 = 0.241; // Han Eq. 27
  static const double kCushMuMin = 0.05, kCushMuMax = 0.50;
  static const double kCushTangScrub = 0.60; // how strongly μ scrubs tangential speed
  static const double kCushSideThrow = 3.0; //  side-spin → tangential squirt off rail
  static const double kRailSpinDecay = 0.50; //  side-spin lost on a cushion

  // Side-spin (ωz) natural decay from the friction moment Mz (Han Eq. 5), per s.
  static const double kSideSpinDecel = 0.60; // normalized units/s

  // ── Balls (index 0 = cue, index 1 = target) ────────────────────────────────
  final List<SimBall> balls;

  // ── Shot reference state ─────────────────────────────────────────────────────
  Vector2 shotDir = Vector2(1, 0);
  double lastPower = 0.5;

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

  /// A ball counts as moving if it has speed, or residual spin that will still
  /// set it in motion (e.g. a draw shot that has momentarily stopped).
  bool get anyMoving => balls.any((b) =>
      b.inPlay &&
      (b.vel.length2 > kStopEps * kStopEps ||
          (b.vel - b.spinSurf).length2 > kRollEps * kRollEps));

  // ── Launch a shot ─────────────────────────────────────────────────────────────

  /// Initialise the cue ball for a new shot.
  /// [spin]: top/back spin from the tip's vertical offset, +follow / −draw.
  /// [sideSpin]: English from the tip's horizontal offset.
  void fire({
    required double power,
    double spin = 0.0,
    double sideSpin = 0.0,
    required Vector2 dir,
  }) {
    lastPower = power;
    shotDir = dir.clone();

    final d = dir.normalized();
    final v0 = power * power * kMaxForce;

    final cue = balls[0];
    cue.vel = d * v0;
    cue.spinSurf = d * (kTipSpinGain * spin.clamp(-1.0, 1.0) * v0);
    cue.sideSpin = sideSpin.clamp(-1.0, 1.0);

    final tgt = balls[1];
    tgt.vel.setZero();
    tgt.spinSurf.setZero();
    tgt.sideSpin = 0.0;
  }

  // ── Main step ───────────────────────────────────────────────────────────────

  /// Advance the simulation by [dt] seconds using an event-driven loop.
  void step(double dt) {
    double tLeft = dt;
    const int maxIter = 400; // safety cap — bounded by frame dt / kMaxSubStep
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

      // Wall TOIs for each ball (python-billiards: toi_args_ball_line_onesided)
      for (int i = 0; i < balls.length; i++) {
        final b = balls[i];
        if (!b.inPlay) continue;

        double t;
        if (b.vel.x < 0) {
          t = (_minX - b.pos.x) / b.vel.x; // left wall
          if (t >= 0 && t < tMin) {
            tMin = t;
            eventKind = _EventKind.wall;
            wallBallIdx = i;
            wallIsX = true;
          }
        }
        if (b.vel.x > 0) {
          t = (_maxX - b.pos.x) / b.vel.x; // right wall
          if (t >= 0 && t < tMin) {
            tMin = t;
            eventKind = _EventKind.wall;
            wallBallIdx = i;
            wallIsX = true;
          }
        }
        if (b.vel.y < 0) {
          t = (_minY - b.pos.y) / b.vel.y; // top wall
          if (t >= 0 && t < tMin) {
            tMin = t;
            eventKind = _EventKind.wall;
            wallBallIdx = i;
            wallIsX = false;
          }
        }
        if (b.vel.y > 0) {
          t = (_maxY - b.pos.y) / b.vel.y; // bottom wall
          if (t >= 0 && t < tMin) {
            tMin = t;
            eventKind = _EventKind.wall;
            wallBallIdx = i;
            wallIsX = false;
          }
        }
      }

      // ── Advance, capped to a sub-step ───────────────────────────────────────
      // If the event lies within one sub-step we reach (and resolve) it now;
      // otherwise we take a bounded step and re-evaluate events next iteration
      // (this is what keeps a decelerating / reversing ball physically correct
      // without re-deriving the analytic TOI under friction).
      final bool reachEvent = eventKind != null && tMin <= kMaxSubStep + 1e-9;
      final double adv = reachEvent ? tMin : (tMin < kMaxSubStep ? tMin : kMaxSubStep);

      _advanceAll(adv);

      if (reachEvent) {
        if (eventKind == _EventKind.ballBall) {
          _resolveElasticCollision();
          onBallCollision?.call();
        } else {
          final prevVel = balls[wallBallIdx].vel.clone();
          _resolveWall(wallBallIdx, wallIsX);
          if (wallBallIdx == 0) onCueBallRailBounce?.call(wallIsX, prevVel);
        }
      }

      tLeft -= adv;
    }

    // Safety clamp — should be a no-op under normal conditions
    for (final b in balls) {
      if (!b.inPlay) continue;
      b.pos.x = b.pos.x.clamp(_minX, _maxX);
      b.pos.y = b.pos.y.clamp(_minY, _maxY);
    }
  }

  // ── Advance + cloth friction (slip→roll) ─────────────────────────────────────

  void _advanceAll(double dt) {
    for (final b in balls) {
      if (!b.inPlay) continue;
      b.pos += b.vel * dt;
      _applyCloth(b, dt);
    }
  }

  /// Rigid-body cloth friction for one ball over [dt] (Han Eqs. 1–8).
  ///
  /// Works in 1-D along the line of travel (so the path never curves):
  ///   slip u = v∥ − s∥  (centre speed minus spin surface speed)
  ///     u ≠ 0 → sliding: kinetic friction decelerates v∥ and spins s∥ up/down
  ///             until u → 0; for a solid sphere the slip shrinks 7/2× faster
  ///             than v∥ alone (I = 2/5 mR²), and rolling is reached at
  ///             v_roll = (5 v∥ + 2 s∥)/7.
  ///     u ≈ 0 → pure rolling: small constant rolling resistance until it stops.
  void _applyCloth(SimBall b, double dt) {
    final slip = b.vel - b.spinSurf;
    final slipMag = slip.length;
    final speed = b.vel.length;

    // Direction of motion.  At (near) rest, the spin itself sets the ball going
    // — that is where follow / draw comes from after a stun-like ball-ball hit.
    Vector2 moveDir;
    if (speed > kStopEps) {
      moveDir = b.vel / speed;
    } else if (slipMag > kRollEps) {
      moveDir = -slip / slipMag; // ball will accelerate the way the spin pushes
    } else {
      b.vel.setZero();
      b.spinSurf.setZero();
      _decaySide(b, dt);
      return;
    }

    double vLong = b.vel.dot(moveDir);
    double sLong = b.spinSurf.dot(moveDir);
    final double u = vLong - sLong;

    if (u.abs() > kRollEps) {
      // Sliding phase (Han Eq. 6).
      final double s = u.sign;
      if (3.5 * kSlideDecel * dt >= u.abs()) {
        // Reaches pure rolling within this step.
        final double vRoll = (5 * vLong + 2 * sLong) / 7.0;
        vLong = vRoll;
        sLong = vRoll;
      } else {
        vLong -= s * kSlideDecel * dt; //        m·v̇ = f
        sLong += s * 2.5 * kSlideDecel * dt; //  I·ω̇ = R·f  (×5/2 for a sphere)
      }
    } else {
      // Pure rolling (Han Eq. 7/8): lumped rolling resistance brings it to rest.
      if (kRollDecel * dt >= vLong.abs()) {
        vLong = 0.0;
      } else {
        vLong -= vLong.sign * kRollDecel * dt;
      }
      sLong = vLong;
    }

    // Reconstruct collinear motion (drops any lateral spin ⇒ no swerve/masse).
    b.vel = moveDir * vLong;
    b.spinSurf = moveDir * sLong;
    if (vLong.abs() < kStopEps && (vLong - sLong).abs() < kRollEps) {
      b.vel.setZero();
      b.spinSurf.setZero();
    }

    _decaySide(b, dt);
  }

  /// Natural decay of side spin from the friction moment Mz (Han Eq. 5).
  void _decaySide(SimBall b, double dt) {
    if (b.sideSpin == 0.0) return;
    final double d = kSideSpinDecel * dt;
    b.sideSpin =
        b.sideSpin.abs() <= d ? 0.0 : b.sideSpin - b.sideSpin.sign * d;
  }

  // ── TOI: ball-ball (python-billiards toi_ball_ball) ─────────────────────────

  double _toiBallBall() {
    final b1 = balls[0];
    final b2 = balls[1];

    final dpos = b1.pos - b2.pos;
    final dvel = b1.vel - b2.vel;

    final posDotVel = dpos.dot(dvel);
    if (posDotVel >= 0) return double.infinity; // not approaching

    final speedSqrd = dvel.dot(dvel);
    if (speedSqrd < 1e-14) return double.infinity;

    final rsum = SimBall.radius * 2.0;
    final rsumSqrd = rsum * rsum;
    final distSqrd = dpos.dot(dpos);

    final cross = dpos.x * dvel.y - dpos.y * dvel.x;
    final deltaOver4 = speedSqrd * rsumSqrd - cross * cross;
    if (deltaOver4 <= 0) return double.infinity; // miss

    final cMinusR2 = distSqrd - rsumSqrd;
    if (cMinusR2 < 0) return double.infinity; // already overlapping

    return cMinusR2 / (-posDotVel + sqrt(deltaOver4));
  }

  // ── Ball-ball collision (Han Eq. 9–11: frictionless, equal mass, e = 0.98) ──
  //
  // Only the line-of-centres (normal) component changes; tangential velocity
  // and all spin are preserved (no friction between balls).  Follow / draw then
  // arise afterwards as the cue's retained spinSurf converts to roll on the cloth.

  void _resolveElasticCollision() {
    final cue = balls[0];
    final obj = balls[1];

    final dpos = cue.pos - obj.pos;
    final distSqrd = dpos.dot(dpos);
    if (distSqrd < 1e-12) return;

    final dvel = cue.vel - obj.vel;
    if (dpos.dot(dvel) > 1e-6) return; // already separating

    final dist = sqrt(distSqrd);
    final n = -dpos / dist; // unit normal: cue → target (line of centres)
    final t = Vector2(-n.y, n.x); // tangent

    final cueN = cue.vel.dot(n), cueT = cue.vel.dot(t);
    final objN = obj.vel.dot(n), objT = obj.vel.dot(t);

    const e = kBallRestitution;
    final cueN2 = 0.5 * ((1 - e) * cueN + (1 + e) * objN); // Han Eq. 11
    final objN2 = 0.5 * ((1 + e) * cueN + (1 - e) * objN);

    cue.vel = n * cueN2 + t * cueT;
    obj.vel = n * objN2 + t * objT;
    obj.spinSurf.setZero(); // struck ball has no spin → slides then rolls
    // cue.spinSurf is retained (frictionless) and drives follow/draw afterwards.

    // English deflects the cue (and slightly nudges the object) along the tangent.
    if (cue.sideSpin.abs() > 0.01) {
      final throwV = cue.sideSpin * kBallSideThrow * (cueN2.abs() + objN2.abs());
      cue.vel += t * throwV;
      obj.vel -= t * (throwV * 0.5);
      cue.sideSpin *= (1 - kBallSpinDecay);
    }
  }

  // ── Cushion reflection (Han Eq. 26 restitution, Eq. 27 friction) ─────────────

  void _resolveWall(int ballIdx, bool isX) {
    final b = balls[ballIdx];

    // Split into wall-normal (vN) and tangential (vT) speeds.
    final double vN = isX ? b.vel.x : b.vel.y;
    final double vT = isX ? b.vel.y : b.vel.x;

    // Restitution from the normal approach speed (Han Eq. 26, V in m/s).
    final double vMs = vN.abs() * kMetersPerUnit;
    final double e =
        (kCushE0 + kCushE1 * vMs - kCushE2 * vMs * vMs).clamp(kCushEMin, kCushEMax);

    // Friction from the incidence angle (Han Eq. 27, θ = 0 is head-on).
    final double theta = atan2(vT.abs(), vN.abs());
    final double mu = (kCushMu0 - kCushMu1 * theta).clamp(kCushMuMin, kCushMuMax);

    final double vNr = -vN * e; //                  reflected normal component
    double vTr = vT * (1 - kCushTangScrub * mu); //  cushion friction scrubs tangential

    // English squirts the ball along the rail (cue ball only).
    if (ballIdx == 0 && b.sideSpin.abs() > 0.01) {
      final double sgn = isX ? (vN > 0 ? -1.0 : 1.0) : (vN > 0 ? 1.0 : -1.0);
      vTr += mu * sgn * b.sideSpin * kCushSideThrow;
    }

    if (isX) {
      b.vel.x = vNr;
      b.vel.y = vTr;
    } else {
      b.vel.y = vNr;
      b.vel.x = vTr;
    }

    // spinSurf is left in the world frame on purpose: after a near-head-on
    // bounce it now opposes travel, so a rolling ball "dies" at the cushion —
    // this falls out of the cloth friction on the following steps.
    if (ballIdx == 0) b.sideSpin *= (1 - kRailSpinDecay);
  }
}
