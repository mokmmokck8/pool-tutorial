import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:pool_tutorial/game/lab/lab_simulation.dart';

void main() {
  // Cue at (5.5, 5), target straight ahead at (5.5, 12); shot is +y.
  // Contact happens when the centres are 2r apart, i.e. cue centre ≈ y 11.4.
  const double contactY = 12.0 - SimBall.radius * 2;

  LabSimulation freshShot({double spin = 0.0, double power = 0.6}) {
    final sim = LabSimulation(
      cuePos: Vector2(5.5, 5.0),
      targetPos: Vector2(5.5, 12.0),
    );
    sim.fire(power: power, spin: spin, dir: Vector2(0, 1));
    return sim;
  }

  /// Step until the first ball-ball contact, then [settle] seconds further, and
  /// return the cue ball.  Measuring just after contact isolates follow / draw
  /// from later rail interactions of the struck ball.
  SimBall cueAfterContact(LabSimulation sim, {double settle = 0.3}) {
    var hit = false;
    double after = 0;
    sim.onBallCollision = () => hit = true;
    for (int i = 0; i < 4000; i++) {
      sim.step(1 / 120.0);
      if (hit) {
        after += 1 / 120.0;
        if (after >= settle) break;
      }
    }
    expect(hit, isTrue, reason: 'the balls should have collided');
    return sim.balls[0];
  }

  test('ball settles to rest (constant-deceleration friction, not asymptotic)',
      () {
    final sim = freshShot();
    var stepped = 0;
    while (sim.anyMoving && stepped < 12000) {
      sim.step(1 / 120.0);
      stepped++;
    }
    expect(sim.anyMoving, isFalse, reason: 'the ball should actually stop');
  });

  test('draw: backspin pulls the cue ball back behind the contact point', () {
    final cue = cueAfterContact(freshShot(spin: -1.0));
    expect(cue.vel.y, lessThan(0), reason: 'cue should be travelling backwards');
    expect(cue.pos.y, lessThan(contactY), reason: 'cue should be behind contact');
  });

  test('follow: topspin drives the cue ball forward through contact', () {
    final cue = cueAfterContact(freshShot(spin: 1.0));
    expect(cue.vel.y, greaterThan(0), reason: 'cue should be travelling forward');
    expect(cue.pos.y, greaterThan(contactY), reason: 'cue should be past contact');
  });

  test('ordering: draw < stun < follow just after contact', () {
    final draw = cueAfterContact(freshShot(spin: -1.0)).pos.y;
    final stun = cueAfterContact(freshShot(spin: 0.0)).pos.y;
    final follow = cueAfterContact(freshShot(spin: 1.0)).pos.y;
    expect(draw, lessThan(stun));
    expect(stun, lessThan(follow));
  });

  test('cushion restitution (Han Eq.26) absorbs energy on a head-on rail hit',
      () {
    final sim = LabSimulation(
      cuePos: Vector2(5.5, 11.0),
      targetPos: Vector2(1.0, 1.0), // out of the way
    );
    sim.fire(power: 0.5, dir: Vector2(0, 1)); // straight into the bottom rail
    final before = sim.balls[0].vel.length;

    var bounced = false;
    sim.onCueBallRailBounce = (_, __) => bounced = true;
    for (int i = 0; i < 2000 && !bounced; i++) {
      sim.step(1 / 120.0);
    }
    expect(bounced, isTrue);
    expect(sim.balls[0].vel.length, lessThan(before),
        reason: 'the rail should remove energy (e < 1)');
  });
}
