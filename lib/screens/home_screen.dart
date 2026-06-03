import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'game_screen.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          _buildBackground(),
          _buildContent(context),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return CustomPaint(
      painter: _BackgroundPainter(_orbitController),
      child: AnimatedBuilder(
        animation: _orbitController,
        builder: (_, __) => const SizedBox.expand(),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SafeArea(
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTag(),
                  const SizedBox(height: 20),
                  _buildTitle(),
                  const SizedBox(height: 16),
                  _buildSubtitle(),
                  const SizedBox(height: 48),
                  _buildStartButton(context),
                  const SizedBox(height: 24),
                  _buildFeaturePills(),
                ],
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
        style: GoogleFonts.spaceMono(
          fontSize: 11,
          color: const Color(0xFF2ECC71),
          letterSpacing: 2,
        ),
      ),
    ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.2, end: 0);
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upgrade your',
          style: GoogleFonts.inter(
            fontSize: 44,
            fontWeight: FontWeight.w300,
            color: Colors.white.withOpacity(0.9),
            height: 1.1,
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF2ECC71), Color(0xFF27AE60), Color(0xFF1ABC9C)],
          ).createShader(bounds),
          child: Text(
            'Pool IQ',
            style: GoogleFonts.inter(
              fontSize: 72,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.0,
              letterSpacing: -2,
            ),
          ),
        ),
        Text(
          'to start.',
          style: GoogleFonts.inter(
            fontSize: 44,
            fontWeight: FontWeight.w300,
            color: Colors.white.withOpacity(0.9),
            height: 1.1,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildSubtitle() {
    return Text(
      'Master cue ball control, spin & positioning.\nLearn to think two shots ahead.',
      style: GoogleFonts.inter(
        fontSize: 15,
        color: Colors.white.withOpacity(0.45),
        height: 1.6,
      ),
    ).animate().fadeIn(delay: 600.ms);
  }

  Widget _buildStartButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, a, b) => const GameScreen(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      ),
      child: Container(
        height: 56,
        width: 220,
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
            Text(
              'Start Training',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
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
    return Row(
      children: features.map((f) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Container(
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
              Text(
                f.$1,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      )).toList(),
    ).animate().fadeIn(delay: 1000.ms);
  }

  Widget _buildBallShowcase() {
    return AnimatedBuilder(
      animation: _orbitController,
      builder: (context, _) {
        return CustomPaint(
          painter: _BallShowcasePainter(_orbitController.value),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final Animation<double> animation;
  _BackgroundPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    // subtle radial gradient
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

    // grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..strokeWidth = 1;
    const spacing = 60.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => false;
}

class _BallShowcasePainter extends CustomPainter {
  final double t;
  static const _ballColors = [
    Color(0xFFF1C40F), // 1 yellow
    Color(0xFF3498DB), // 2 blue
    Color(0xFFE74C3C), // 3 red
    Color(0xFF9B59B6), // 4 purple
    Color(0xFFE67E22), // 5 orange
    Color(0xFF1ABC9C), // 6 teal
    Color(0xFF8B0000), // 7 maroon
    Color(0xFF2C3E50), // 8 black-ish
  ];

  _BallShowcasePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.45;
    final cy = size.height * 0.5;
    final radius = min(size.width, size.height) * 0.38;

    // glow circle
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF2ECC71).withOpacity(0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius * 1.5));
    canvas.drawCircle(Offset(cx, cy), radius * 1.5, glowPaint);

    // orbit ring
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), radius, ringPaint);

    // orbiting balls
    for (int i = 0; i < _ballColors.length; i++) {
      final angle = (i / _ballColors.length) * 2 * pi + t * 2 * pi;
      final bx = cx + radius * cos(angle);
      final by = cy + radius * sin(angle);
      _drawBall(canvas, Offset(bx, by), 18, _ballColors[i]);
    }

    // center cue ball
    _drawCueBall(canvas, Offset(cx, cy), 26);
  }

  void _drawBall(Canvas canvas, Offset center, double r, Color color) {
    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center + const Offset(3, 4), r, shadow);

    final base = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.4),
        radius: 1.0,
        colors: [
          Color.lerp(Colors.white, color, 0.3)!,
          color,
          Color.lerp(color, Colors.black, 0.5)!,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, base);

    // specular
    final spec = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center + Offset(-r * 0.3, -r * 0.3), r * 0.25, spec);
  }

  void _drawCueBall(Canvas canvas, Offset center, double r) {
    final shadow = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center + const Offset(3, 5), r, shadow);

    final base = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.4),
        radius: 1.0,
        colors: [
          Colors.white,
          const Color(0xFFE8E8E8),
          const Color(0xFFB0B0B0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, base);

    final spec = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center + Offset(-r * 0.3, -r * 0.3), r * 0.2, spec);
  }

  @override
  bool shouldRepaint(_BallShowcasePainter old) => old.t != t;
}
