import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/lab/lab_game.dart';
import '../widgets/power_slider.dart';
import '../widgets/hit_point_selector.dart';

class LabScreen extends StatefulWidget {
  const LabScreen({super.key});
  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen>
    with SingleTickerProviderStateMixin {
  late LabGame _game;
  double _power     = 0.5;
  Offset _hitPoint  = Offset.zero; // x = side spin, y = top/bottom spin (−1..1)
  double _cutAngle  = 0;
  double _distance        = 6.0;
  double _cushionSoftness = 0.3;
  bool   _drawerOpen = false;

  late final AnimationController _drawerCtrl;
  late final Animation<double>   _drawerAnim; // 0 = closed, 1 = open

  static const double _drawerWidth = 240;

  static const List<double> _angles = [0, 15, 20, 30, 45];
  static const List<({double dist, String label})> _distances = [
    (dist: 3.0, label: 'NEAR'),
    (dist: 6.0, label: 'MID'),
    (dist: 9.0, label: 'FAR'),
  ];

  @override
  void initState() {
    super.initState();
    _game = LabGame();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _drawerAnim = CurvedAnimation(
      parent: _drawerCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    super.dispose();
  }

  void _openDrawer()  { setState(() => _drawerOpen = true);  _drawerCtrl.forward(); }
  void _closeDrawer() { _drawerCtrl.reverse().then((_) => setState(() => _drawerOpen = false)); }

  void _setAngle(double degrees) {
    setState(() => _cutAngle = degrees);
    _game.setCutAngle(degrees);
    _closeDrawer();
  }

  void _setDistance(double dist) {
    setState(() => _distance = dist);
    _game.setDistance(dist);
    _closeDrawer();
  }

  // y axis on the ball: up = top spin (+1), down = back spin (−1) → invert dy
  void _shoot() => _game.shoot(
        power: _power,
        spin: -_hitPoint.dy,       // ball y up = top spin
        sideSpin: _hitPoint.dx,    // ball x right = right spin
      );
  void _reset() => _game.setCutAngle(_cutAngle);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(children: [
          // ── Main content ─────────────────────────────────────────────────
          Column(children: [
            _buildTopBar(),
            Expanded(child: GameWidget(game: _game)),
            _buildControls(),
          ]),

          // ── Scrim + frosted drawer (only mounted while open/animating) ───
          if (_drawerOpen)
            AnimatedBuilder(
              animation: _drawerAnim,
              builder: (_, __) => Stack(children: [
                // Dim scrim — tap to close
                GestureDetector(
                  onTap: _closeDrawer,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.18 * _drawerAnim.value),
                  ),
                ),
                // Frosted glass panel sliding in from the right
                Positioned(
                  top: 0, bottom: 0,
                  right: -_drawerWidth * (1 - _drawerAnim.value),
                  width: _drawerWidth,
                  child: _buildFrostedPanel(),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: _iconCircle(Icons.arrow_back_ios_new_rounded),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Laboratory',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  color: Colors.black87)),
        ),
        GestureDetector(
          onTap: _openDrawer,
          child: _iconCircle(Icons.tune_rounded),
        ),
      ]),
    );
  }

  Widget _iconCircle(IconData icon) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.black.withValues(alpha: 0.06),
    ),
    child: Icon(icon, size: 18, color: Colors.black54),
  );

  // ── Frosted glass settings panel ──────────────────────────────────────────
  Widget _buildFrostedPanel() {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        bottomLeft: Radius.circular(20),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            // Apple-style: light gray tint at ~82% opacity
            color: const Color(0xA8F2F2F7),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              bottomLeft: Radius.circular(20),
            ),
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.6), width: 0.5),
            ),
          ),
          child: SafeArea(
            left: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(children: [
                    const Expanded(
                      child: Text('Settings',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1E),
                              letterSpacing: -0.3)),
                    ),
                    GestureDetector(
                      onTap: _closeDrawer,
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF3C3C43).withValues(alpha: 0.12),
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: Color(0xFF3C3C43)),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),
                  _sectionDivider(),
                  const SizedBox(height: 16),

                  // ── Cut angle ─────────────────────────────────────────────
                  _panelLabel('CUT ANGLE'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _angles.map((a) {
                      final sel = a == _cutAngle;
                      return GestureDetector(
                        onTap: () => _setAngle(a),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 50, height: 36,
                          decoration: BoxDecoration(
                            color: sel
                                ? const Color(0xFF34C759)
                                : const Color(0xFF3C3C43).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: sel
                                ? null
                                : Border.all(
                                    color: const Color(0xFF3C3C43).withValues(alpha: 0.12),
                                    width: 0.5),
                          ),
                          child: Center(
                            child: Text('${a.toInt()}°',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white
                                      : const Color(0xFF3C3C43),
                                )),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),
                  _sectionDivider(),
                  const SizedBox(height: 16),

                  // ── Distance ──────────────────────────────────────────────
                  _panelLabel('DISTANCE'),
                  const SizedBox(height: 10),
                  Row(
                    children: _distances.map((d) {
                      final sel = d.dist == _distance;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _setDistance(d.dist),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              height: 36,
                              decoration: BoxDecoration(
                                color: sel
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFF3C3C43).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: sel
                                    ? null
                                    : Border.all(
                                        color: const Color(0xFF3C3C43).withValues(alpha: 0.12),
                                        width: 0.5),
                              ),
                              child: Center(
                                child: Text(d.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? Colors.white
                                          : const Color(0xFF3C3C43),
                                    )),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),
                  _sectionDivider(),
                  const SizedBox(height: 16),

                  // ── Cushion softness ───────────────────────────────────────
                  Row(children: [
                    _panelLabel('CUSHION'),
                    const Spacer(),
                    Text(
                      _cushionSoftness < 0.15
                          ? 'HARD'
                          : _cushionSoftness < 0.45
                              ? 'MEDIUM'
                              : _cushionSoftness < 0.75
                                  ? 'SOFT'
                                  : 'VERY SOFT',
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8E8E93),
                        fontFamily: 'Courier New',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      activeTrackColor: const Color(0xFF34C759),
                      inactiveTrackColor: const Color(0xFF3C3C43).withValues(alpha: 0.15),
                      thumbColor: const Color(0xFF34C759),
                      overlayColor: const Color(0xFF34C759).withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: _cushionSoftness,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (v) {
                        setState(() => _cushionSoftness = v);
                        _game.cushionSoftness = v;
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(children: [
                      Text('HARD', style: TextStyle(fontSize: 9,
                          letterSpacing: 1.2, color: Colors.black38,
                          fontFamily: 'Courier New')),
                      const Spacer(),
                      Text('SOFT', style: TextStyle(fontSize: 9,
                          letterSpacing: 1.2, color: Colors.black38,
                          fontFamily: 'Courier New')),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionDivider() => Container(
    height: 0.5,
    color: const Color(0xFF3C3C43).withValues(alpha: 0.18),
  );

  Widget _panelLabel(String t) => Text(t,
      style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.8,
          color: Color(0xFF8E8E93),
          fontFamily: 'Courier New'));

  // ── Controls: power + hit point + shoot/reset ────────────────────────────
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

          const SizedBox(width: 24),

          // Hit point selector (2D spin)
          Column(mainAxisSize: MainAxisSize.min, children: [
            _label('HIT POINT'),
            const SizedBox(height: 6),
            HitPointSelector(
              value: _hitPoint,
              onChanged: (v) => setState(() => _hitPoint = v),
            ),
          ]),

          const SizedBox(width: 24),

          // Shoot / reset button
          ListenableBuilder(
            listenable: _game.stateNotifier,
            builder: (_, __) {
              final isAiming = _game.stateNotifier.value == LabState.aiming;
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
                    color: Colors.white, size: 28,
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
