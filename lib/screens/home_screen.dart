import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'game_screen.dart';

// ── Typography helpers (no google_fonts — uses platform system font) ──────────
TextStyle _inter(double size, FontWeight w, Color c, {double? letterSpacing, double? height}) =>
    TextStyle(
      fontSize: size,
      fontWeight: w,
      color: c,
      letterSpacing: letterSpacing,
      height: height,
      fontFamily: null, // SF Pro on iOS/macOS, Roboto on Android
    );

TextStyle _mono(double size, Color c, {double? letterSpacing}) =>
    TextStyle(
      fontSize: size,
      color: c,
      letterSpacing: letterSpacing,
      fontFamily: 'Courier New',
    );

// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _orbitController;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          _buildBackground(),
          isLandscape ? _buildLandscapeContent(context) : _buildPortraitContent(context),
        ],
      ),
    );
  }

  // ── Landscape: side-by-side text + ball showcase ───────────────────────────
  Widget _buildLandscapeContent(BuildContext context) {
    return SafeArea(
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: _contentWidgets(context),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: _buildBallShowcase(),
          ),
        ],
      ),
    );
  }

  // ── Portrait: stacked layout ───────────────────────────────────────────────
  Widget _buildPortraitContent(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.38,
            child: _buildBallShowcase(),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _contentWidgets(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _contentWidgets(BuildContext context) => [
    _buildTag(),
    const SizedBox(height: 16),
    _buildTitle(),
    const SizedBox(height: 12),
    _buildSubtitle(),
    const SizedBox(height: 36),
    _buildStartButton(context),
    const SizedBox(height: 20),
    _buildFeaturePills(),
  ];

  Widget _buildBackground() {
    return CustomPaint(
      painter: _BackgroundPainter(),
      child: AnimatedBuilder(
        animation: _orbitController,
        builder: (_, __) => const SizedBox.expand(),
      ),
    );
  }

  Widget _buildTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF2ECC71).withOpacity(0.5)),
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF2ECC71).withOpacity(0.08),
      ),
      child: Text(
        'BILLIARDS TRAINING',
        style: _mono(11, const Color(0xFF2ECC71), letterSpacing: 2),
      ),
    ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.2, end: 0);
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Upgrade your',
            style: _inter(40, FontWeight.w300, Colors.white.withOpacity(0.9), height: 1.1)),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF2ECC71), Color(0xFF27AE60), Color(0xFF1ABC9C)],
          ).createShader(bounds),
          child: Text('Pool IQ',
              style: _inter(68, FontWeight.w800, Colors.white,
                  height: 1.0, letterSpacing: -2)),
        ),
        Text('to start.',
            style: _inter(40, FontWeight.w300, Colors.white.withOpacity(0.9), height: 1.1)),
      ],
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildSubtitle() {
    return Text(
      'Master cue ball control, spin & positioning.\nLearn to think two shots ahead.',
      style: _inter(14, FontWeight.w400, Colors.white.withOpacity(0.45), height: 1.6),
    ).animate().fadeIn(delay: 600.ms);
  }

  Widget _buildStartButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (_, a, b) => const GameScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      )),
      child: Container(
        height: 54,
        width: 210,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2ECC71).withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Start Training',
                style: _inter(16, FontWeight.w700, Colors.white, letterSpacing: 0.5)),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 800.ms).scale(begin: const Offset(0.9, 0.9));
  }

  Widget _buildFeaturePills() {
    final features = [
      ('Auto-aim', Icons.my_location_rounded),
      ('Spin control', Icons.rotate_right_rounded),
      ('Shot rating', Icons.star_rounded),
    ];
    // Use Wrap so pills never overflow on narrow screens
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: features
          .map((f) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(f.$2, size: 14, color: const Color(0xFF2ECC71)),
                    const SizedBox(width: 6),
                    Text(f.$1,
                        style: _inter(12, FontWeight.w500,
                            Colors.white.withOpacity(0.6))),
                  ],
                ),
              ))
          .toList(),
    ).animate().fadeIn(delay: 1000.ms);
  }

  Widget _buildBallShowcase() {
    return AnimatedBuilder(
      animation: _orbitController,
      builder: (_, __) => CustomPaint(
        painter: _BallShowcasePainter(_orbitController.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ── Painters ────────────────────────────────────────────────────────────────

class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.6, 0),
        radius: 1.2,
        colors: [
          const Color(0xFF1A6B3C).withOpacity(0.15),
          const Color(0xFF0A0A0F),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => false;
}

class _BallShowcasePainter extends CustomPainter {
  final double t;
  static const _ballColors = [
    Color(0xFFF1C40F),
    Color(0xFF3498DB),
    Color(0xFFE74C3C),
    Color(0xFF9B59B6),
    Color(0xFFE67E22),
    Color(0xFF1ABC9C),
    Color(0xFF8B0000),
    Color(0xFF2C3E50),
  ];

  const _BallShowcasePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final radius = min(size.width, size.height) * 0.36;

    // Glow
    canvas.drawCircle(
      Offset(cx, cy),
      radius * 1.5,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF2ECC71).withOpacity(0.06),
          Colors.transparent,
        ]).createShader(
            Rect.fromCircle(center: Offset(cx, cy), radius: radius * 1.5)),
    );

    // Orbit ring
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = Colors.white.withOpacity(0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Orbiting balls
    for (int i = 0; i < _ballColors.length; i++) {
      final angle = (i / _ballColors.length) * 2 * pi + t * 2 * pi;
      _drawBall(canvas,
          Offset(cx + radius * cos(angle), cy + radius * sin(angle)),
          18, _ballColors[i]);
    }

    // Center cue ball
    _drawCueBall(canvas, Offset(cx, cy), 26);
  }

  void _drawBall(Canvas canvas, Offset center, double r, Color color) {
    canvas.drawCircle(
      center + const Offset(3, 4), r,
      Paint()
        ..color = Colors.black.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      center, r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          radius: 1.0,
          colors: [
            Color.lerp(Colors.white, color, 0.3)!,
            color,
            Color.lerp(color, Colors.black, 0.5)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.drawCircle(
      center + Offset(-r * 0.3, -r * 0.3), r * 0.25,
      Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  void _drawCueBall(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center + const Offset(3, 5), r,
      Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      center, r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.4),
          radius: 1.0,
          colors: const [Colors.white, Color(0xFFE0E0E0), Color(0xFFAAAAAA)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.drawCircle(
      center + Offset(-r * 0.3, -r * 0.3), r * 0.2,
      Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  @override
  bool shouldRepaint(_BallShowcasePainter old) => old.t != t;
}
