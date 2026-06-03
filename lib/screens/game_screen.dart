import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:google_fonts/google_fonts.dart';
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
  Offset _hitPoint = Offset.zero; // normalized -1..1

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
    _game.shoot(hitPoint: _hitPoint, power: _power);
  }

  void _showShotResult(int score, String label) {
    ScaffoldMessenger.of(context).clearSnackBars();
    final color = score >= 80
        ? const Color(0xFF2ECC71)
        : score >= 50
            ? const Color(0xFFF39C12)
            : const Color(0xFFE74C3C);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color.withOpacity(0.9),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          '$label  •  $score / 100',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Game canvas
          GameWidget(game: _game),

          // Top HUD
          _buildTopHUD(),

          // Bottom controls
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildTopHUD() {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _HUDChip(icon: Icons.sports_bar_rounded, label: 'Pool IQ'),
          const SizedBox(width: 12),
          ListenableBuilder(
            listenable: _game.stateNotifier,
            builder: (_, __) {
              final state = _game.stateNotifier.value;
              return _HUDChip(
                icon: Icons.info_outline_rounded,
                label: _stateLabel(state),
                color: _stateColor(state),
              );
            },
          ),
        ],
      ),
    );
  }

  String _stateLabel(GameState state) => switch (state) {
    GameState.aiming => 'Set spin & power',
    GameState.rolling => 'Ball in motion...',
    GameState.scored => 'Scored!',
    GameState.scratch => 'Scratch!',
    GameState.idle => 'Ready',
  };

  Color _stateColor(GameState state) => switch (state) {
    GameState.scored => const Color(0xFF2ECC71),
    GameState.scratch => const Color(0xFFE74C3C),
    GameState.rolling => const Color(0xFFF39C12),
    _ => Colors.white54,
  };

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.85),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Spin selector
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SPIN',
                  style: GoogleFonts.spaceMono(fontSize: 10, color: Colors.white38, letterSpacing: 2),
                ),
                const SizedBox(height: 8),
                HitPointSelector(
                  value: _hitPoint,
                  onChanged: (p) => setState(() => _hitPoint = p),
                ),
              ],
            ),

            const SizedBox(width: 32),

            // Shoot button
            ListenableBuilder(
              listenable: _game.stateNotifier,
              builder: (_, __) {
                final canShoot = _game.stateNotifier.value == GameState.aiming ||
                    _game.stateNotifier.value == GameState.idle;
                return GestureDetector(
                  onTap: canShoot ? _shoot : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: canShoot
                          ? const LinearGradient(
                              colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: canShoot ? null : Colors.white12,
                      boxShadow: canShoot
                          ? [
                              BoxShadow(
                                color: const Color(0xFF2ECC71).withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: Icon(
                      Icons.sports_cricket_rounded,
                      color: canShoot ? Colors.white : Colors.white24,
                      size: 28,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(width: 32),

            // Power slider
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'POWER',
                  style: GoogleFonts.spaceMono(fontSize: 10, color: Colors.white38, letterSpacing: 2),
                ),
                const SizedBox(height: 8),
                PowerSlider(
                  value: _power,
                  onChanged: (v) => setState(() => _power = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HUDChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HUDChip({
    required this.icon,
    required this.label,
    this.color = Colors.white54,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
