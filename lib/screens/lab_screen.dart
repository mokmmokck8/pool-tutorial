import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/lab/lab_game.dart';
import '../widgets/power_slider.dart';

class LabScreen extends StatefulWidget {
  const LabScreen({super.key});
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  late LabGame _game;
  double _power    = 0.5;
  double _cutAngle = 0;

  static const List<double> _angles = [0, 15, 20, 30, 45];

  @override
  void initState() {
    super.initState();
    _game = LabGame();
  }

  void _setAngle(double degrees) {
    setState(() => _cutAngle = degrees);
    _game.setCutAngle(degrees);
  }

  void _shoot() {
    _game.shoot(power: _power);
  }

  void _reset() {
    _game.setCutAngle(_cutAngle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          _buildAngleSelector(),
          Expanded(child: GameWidget(game: _game)),
          _buildControls(),
        ]),
      ),
    );
  }

  // ── Top bar (no reset button — it moved to the shoot/reset circle) ─────────
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.06),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: Colors.black54),
          ),
        ),
        const SizedBox(width: 12),
        const Text('Laboratory',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                color: Colors.black87)),
      ]),
    );
  }

  // ── Cut angle chips ────────────────────────────────────────────────────────
  Widget _buildAngleSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text('CUT ANGLE',
              style: TextStyle(fontSize: 10, letterSpacing: 2,
                  color: Colors.black38, fontFamily: 'Courier New')),
        ),
        Row(
          children: _angles.map((a) {
            final selected = a == _cutAngle;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => _setAngle(a),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF2ECC71)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF27AE60)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${a.toInt()}°',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  // ── Controls: power + shoot/reset button ──────────────────────────────────
  Widget _buildControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Power slider
          Column(mainAxisSize: MainAxisSize.min, children: [
            _label('POWER'),
            const SizedBox(height: 6),
            PowerSlider(
                value: _power,
                onChanged: (v) => setState(() => _power = v)),
          ]),

          const SizedBox(width: 32),

          // Shoot / Reset toggle
          ListenableBuilder(
            listenable: _game.stateNotifier,
            builder: (_, __) {
              final labState = _game.stateNotifier.value;
              final isAiming = labState == LabState.aiming;

              return GestureDetector(
                onTap: isAiming ? _shoot : _reset,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 66, height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isAiming
                        ? const LinearGradient(
                            colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight)
                        : null,
                    color: isAiming ? null : const Color(0xFF607D8B),
                    boxShadow: isAiming
                        ? [BoxShadow(
                            color: const Color(0xFF2ECC71).withValues(alpha: 0.35),
                            blurRadius: 16, spreadRadius: 2)]
                        : null,
                  ),
                  child: Icon(
                    isAiming
                        ? Icons.sports_cricket_rounded
                        : Icons.refresh_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontSize: 10, letterSpacing: 2,
          color: Colors.black38, fontFamily: 'Courier New'));
}
