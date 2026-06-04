import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/pool_game.dart';
import '../game/components/ball_component.dart';
import '../widgets/hit_point_selector.dart';
import '../widgets/power_slider.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late PoolGame _game;
  double _power   = 0.5;
  Offset _hitPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _game = PoolGame(
      onShotEvaluated: (score, label) {
        if (mounted) _showShotResult(score, label);
      },
    );
  }

  void _shoot() {
    if (!_game.isCurrentShotPossible) return;
    _game.hitPointNotifier.value = _hitPoint;
    _game.shoot(hitPoint: _hitPoint, power: _power);
  }

  void _showShotResult(int score, String label) {
    ScaffoldMessenger.of(context).clearSnackBars();
    final color = score >= 80
        ? const Color(0xFF27AE60)
        : score >= 50
            ? const Color(0xFFF39C12)
            : const Color(0xFFE74C3C);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text('$label  •  $score / 100',
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          Expanded(child: _buildGameArea()),
          _buildControls(),
        ]),
      ),
    );
  }

  // ── Top bar: back + sequence chips ────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.06),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.black54),
          ),
        ),
        const SizedBox(width: 12),
        // Ball sequence
        Expanded(child: _buildSequenceBar()),
        const SizedBox(width: 12),
      ]),
    );
  }

  Widget _buildSequenceBar() {
    final balls = _game.objectBalls;
    if (balls.isEmpty) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: _game.stateNotifier,
      builder: (_, __) {
        final currentTarget = _game.currentTarget;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < balls.length; i++) ...[
              if (i > 0) _ArrowChip(done: !balls[i - 1].inPlay),
              _BallChip(
                ball: balls[i],
                isCurrent: balls[i] == currentTarget,
                isDone: !balls[i].inPlay,
              ),
            ],
          ],
        );
      },
    );
  }

  // ── Game canvas ─────────────────────────────────────────────────────────────
  Widget _buildGameArea() {
    return ListenableBuilder(
      listenable: _game.stateNotifier,
      builder: (_, __) {
        final cleared = _game.stateNotifier.value == GameState.cleared;
        return Stack(children: [
          GestureDetector(
            onTapUp: (d) => _onTableTap(d.localPosition),
            child: GameWidget(game: _game),
          ),
          if (cleared) _buildClearedOverlay(),
        ]);
      },
    );
  }

  void _onTableTap(Offset localPos) {
    if (_game.stateNotifier.value != GameState.aiming) return;
    final worldPos = _game.tapToWorld(localPos.dx, localPos.dy);
    final pockets = _game.pocketPositions;
    int? bestIdx;
    double bestDist = 2.5; // world units tap radius
    for (int i = 0; i < pockets.length; i++) {
      final d = (pockets[i] - worldPos).length;
      if (d < bestDist) { bestDist = d; bestIdx = i; }
    }
    if (bestIdx != null) {
      _game.selectPocket(bestIdx);
      setState(() {});
    }
  }

  Widget _buildClearedOverlay() {
    return Container(
      color: Colors.black45,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎱', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          const Text('Cleared!',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const GameScreen()),
            ),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
            child: const Text('Play Again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  // ── Controls ────────────────────────────────────────────────────────────────
  Widget _buildControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Spin selector
          Column(mainAxisSize: MainAxisSize.min, children: [
            _label('SPIN'),
            const SizedBox(height: 6),
            HitPointSelector(
              value: _hitPoint,
              onChanged: (p) {
                setState(() => _hitPoint = p);
                _game.hitPointNotifier.value = p; // real-time overlay update
              },
            ),
          ]),

          const SizedBox(width: 20),

          // Undo + Strike buttons
          Column(mainAxisSize: MainAxisSize.min, children: [
            // Undo button
            ListenableBuilder(
              listenable: _game.canUndoNotifier,
              builder: (_, __) {
                final canUndo = _game.canUndoNotifier.value;
                return GestureDetector(
                  onTap: canUndo ? () { _game.undo(); setState(() {}); } : null,
                  child: AnimatedOpacity(
                    opacity: canUndo ? 1.0 : 0.3,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.black.withOpacity(0.06),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.undo_rounded, size: 16, color: Colors.black54),
                        SizedBox(width: 4),
                        Text('Undo', style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // Strike button
            ListenableBuilder(
              listenable: _game.stateNotifier,
              builder: (_, __) {
                final state = _game.stateNotifier.value;
                final isAiming = state == GameState.aiming || state == GameState.idle;
                final shotOk = isAiming && _game.isCurrentShotPossible;
                // Impossible shot: show undo prompt instead of shoot button
                if (isAiming && !_game.isCurrentShotPossible) {
                  return Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('切角太大', style: TextStyle(
                        fontSize: 11, color: Color(0xFFE74C3C), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () { _game.undo(); setState(() {}); },
                      child: Container(
                        width: 66, height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE74C3C).withValues(alpha: 0.12),
                          border: Border.all(color: const Color(0xFFE74C3C), width: 2),
                        ),
                        child: const Icon(Icons.undo_rounded, color: Color(0xFFE74C3C), size: 26),
                      ),
                    ),
                  ]);
                }
                return GestureDetector(
                  onTap: shotOk ? _shoot : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 66, height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: shotOk
                          ? const LinearGradient(
                              colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight)
                          : null,
                      color: shotOk ? null : Colors.black12,
                      boxShadow: shotOk
                          ? [BoxShadow(color: const Color(0xFF2ECC71).withValues(alpha: 0.35),
                                blurRadius: 16, spreadRadius: 2)]
                          : null,
                    ),
                    child: Icon(Icons.sports_cricket_rounded,
                        color: shotOk ? Colors.white : Colors.black26, size: 26),
                  ),
                );
              },
            ),
          ]),

          const SizedBox(width: 20),

          // Power slider
          Column(mainAxisSize: MainAxisSize.min, children: [
            _label('POWER'),
            const SizedBox(height: 6),
            PowerSlider(value: _power, onChanged: (v) => setState(() => _power = v)),
          ]),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 10, letterSpacing: 2, color: Colors.black38, fontFamily: 'Courier New'));
}

// ── Sequence chips ─────────────────────────────────────────────────────────────

class _BallChip extends StatelessWidget {
  final BallComponent ball;
  final bool isCurrent;
  final bool isDone;
  const _BallChip({required this.ball, required this.isCurrent, required this.isDone});

  @override
  Widget build(BuildContext context) {
    final clr = isDone ? Colors.black12 : ball.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isCurrent ? 34 : 28,
      height: isCurrent ? 34 : 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone ? Colors.black12 : clr,
        border: isCurrent
            ? Border.all(color: const Color(0xFF2ECC71), width: 2.5)
            : Border.all(color: Colors.black.withOpacity(0.1), width: 1),
        boxShadow: isCurrent
            ? [BoxShadow(color: const Color(0xFF2ECC71).withOpacity(0.4), blurRadius: 8)]
            : null,
      ),
      child: Center(
        child: Text(
          '${ball.number}',
          style: TextStyle(
            color: isDone ? Colors.black38 : Colors.white,
            fontSize: isCurrent ? 13 : 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ArrowChip extends StatelessWidget {
  final bool done;
  const _ArrowChip({required this.done});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Icon(Icons.chevron_right_rounded,
        size: 18, color: done ? const Color(0xFF2ECC71) : Colors.black26),
  );
}

