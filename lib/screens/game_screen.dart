import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/pool_game.dart';
import '../widgets/hit_point_selector.dart';
import '../widgets/power_slider.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late PoolGame _game;
  double _power = 0.5;
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

  void _shoot() => _game.shoot(hitPoint: _hitPoint, power: _power);

  void _showShotResult(int score, String label) {
    ScaffoldMessenger.of(context).clearSnackBars();
    final color = score >= 80
        ? const Color(0xFF2ECC71)
        : score >= 50
            ? const Color(0xFFF39C12)
            : const Color(0xFFE74C3C);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: color.withOpacity(0.92),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text('$label  •  $score / 100',
          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top HUD ──────────────────────────────────────────
            _buildTopHUD(),
            // ── Game canvas — fills remaining space above controls
            Expanded(
              child: GameWidget(
                game: _game,
                backgroundBuilder: (ctx) => Container(color: Colors.white),
              ),
            ),
            // ── Controls ─────────────────────────────────────────
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHUD() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _HUDChip(icon: Icons.sports_bar_rounded, label: 'Pool IQ',
              textColor: Colors.black87, borderColor: Colors.black12),
          const SizedBox(width: 10),
          ListenableBuilder(
            listenable: _game.stateNotifier,
            builder: (_, __) {
              final state = _game.stateNotifier.value;
              return _HUDChip(
                icon: Icons.info_outline_rounded,
                label: _stateLabel(state),
                textColor: _stateColor(state),
                borderColor: _stateColor(state).withOpacity(0.3),
              );
            },
          ),
        ],
      ),
    );
  }

  String _stateLabel(GameState state) => switch (state) {
    GameState.aiming => 'Set spin & power',
    GameState.rolling => 'Ball in motion…',
    GameState.scored => 'Scored!',
    GameState.scratch => 'Scratch!',
    GameState.idle => 'Ready',
  };

  Color _stateColor(GameState state) => switch (state) {
    GameState.scored => const Color(0xFF27AE60),
    GameState.scratch => const Color(0xFFE74C3C),
    GameState.rolling => const Color(0xFFF39C12),
    _ => Colors.black54,
  };

  Widget _buildControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Spin selector
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('SPIN',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Colors.black38,
                    fontFamily: 'Courier New')),
            const SizedBox(height: 8),
            HitPointSelector(
              value: _hitPoint,
              onChanged: (p) => setState(() => _hitPoint = p),
            ),
          ]),

          const SizedBox(width: 28),

          // Strike button
          ListenableBuilder(
            listenable: _game.stateNotifier,
            builder: (_, __) {
              final canShoot = _game.stateNotifier.value == GameState.aiming ||
                  _game.stateNotifier.value == GameState.idle;
              return GestureDetector(
                onTap: canShoot ? _shoot : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: canShoot
                        ? const LinearGradient(
                            colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: canShoot ? null : Colors.black12,
                    boxShadow: canShoot
                        ? [
                            BoxShadow(
                              color: const Color(0xFF2ECC71).withOpacity(0.4),
                              blurRadius: 18,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.sports_cricket_rounded,
                    color: canShoot ? Colors.white : Colors.black26,
                    size: 26,
                  ),
                ),
              );
            },
          ),

          const SizedBox(width: 28),

          // Power slider
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('POWER',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Colors.black38,
                    fontFamily: 'Courier New')),
            const SizedBox(height: 8),
            PowerSlider(
              value: _power,
              onChanged: (v) => setState(() => _power = v),
            ),
          ]),
        ],
      ),
    );
  }
}

class _HUDChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color textColor;
  final Color borderColor;

  const _HUDChip({
    required this.icon,
    required this.label,
    required this.textColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: textColor),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13, color: textColor, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
