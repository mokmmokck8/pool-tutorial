import 'dart:math';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'components/ball_component.dart';

class ShotEvaluation {
  final int score;
  final String label;
  const ShotEvaluation({required this.score, required this.label});
}

class ShotEvaluator {
  /// Evaluate how well the cue ball is positioned for the next shot.
  /// Returns a score 0–100 and a descriptive label.
  static ShotEvaluation evaluate({
    required Vector2 cueBallPos,
    required Vector2 nextTarget,
    required List<Vector2> pockets,
    required double tableW,
    required double tableH,
  }) {
    Vector2 nearestPocket = pockets[0];
    double nearestDist = (pockets[0] - nextTarget).length;
    for (int i = 1; i < pockets.length; i++) {
      final d = (pockets[i] - nextTarget).length;
      if (d < nearestDist) { nearestDist = d; nearestPocket = pockets[i]; }
    }

    final ghostBall = _ghostBall(nextTarget, nearestPocket);
    final distToGhost = (cueBallPos - ghostBall).length;

    // Score based on:
    // 1. Distance from ideal ghost ball position (closer = better)
    final maxDist = sqrt(tableW * tableW + tableH * tableH);
    final distScore = ((1.0 - (distToGhost / maxDist).clamp(0.0, 1.0)) * 60).round();

    // 2. Angle feasibility: is cue ball on a reachable side?
    final anglePenalty = _anglePenalty(cueBallPos, nextTarget, nearestPocket);
    final angleScore = ((1.0 - anglePenalty) * 30).round();

    // 3. Is cue ball close to a rail? (harder shot)
    final railPenalty = _railPenalty(cueBallPos, tableW, tableH);
    final railScore = ((1.0 - railPenalty) * 10).round();

    final total = (distScore + angleScore + railScore).clamp(0, 100);

    return ShotEvaluation(
      score: total,
      label: _scoreLabel(total),
    );
  }

  static Vector2 _ghostBall(Vector2 obj, Vector2 pocket) {
    final dir = (pocket - obj).normalized();
    return obj - dir * (BallComponent.radius * 2);
  }

  static double _anglePenalty(Vector2 cue, Vector2 target, Vector2 pocket) {
    // The shot becomes harder when angle is very shallow (near straight-in or very cut)
    final dir1 = (target - cue).normalized();
    final dir2 = (pocket - target).normalized();
    final dot = dir1.dot(dir2).clamp(-1.0, 1.0);
    final angle = acos(dot); // 0 = straight in, pi = full cut
    // Penalize extreme cuts (angle > 60°)
    if (angle < pi / 3) return 0.0;
    return ((angle - pi / 3) / (pi * 2 / 3)).clamp(0.0, 1.0);
  }

  static double _railPenalty(Vector2 cue, double tableW, double tableH) {
    const minDist = 0.8;
    final distFromRail = [
      cue.x,
      tableW - cue.x,
      cue.y,
      tableH - cue.y,
    ].reduce(min);
    if (distFromRail > minDist) return 0.0;
    return (1.0 - distFromRail / minDist).clamp(0.0, 1.0);
  }

  static String _scoreLabel(int score) {
    if (score >= 85) return 'Perfect position!';
    if (score >= 70) return 'Good shape';
    if (score >= 50) return 'Workable';
    if (score >= 30) return 'Tough leave';
    return 'Bad position';
  }
}
