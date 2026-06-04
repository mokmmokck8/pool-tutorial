import 'package:flutter/material.dart';
import 'game_screen.dart';
import 'lab_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1A14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              // Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2ECC71).withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(20),
                  color: const Color(0xFF2ECC71).withOpacity(0.08),
                ),
                child: const Text(
                  'BILLIARDS TRAINING',
                  style: TextStyle(
                    fontSize: 11, letterSpacing: 2,
                    color: Color(0xFF2ECC71), fontFamily: 'Courier New',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Title
              const Text('Upgrade your',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300,
                      color: Colors.white70, height: 1.15)),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF2ECC71), Color(0xFF1ABC9C)],
                ).createShader(bounds),
                child: const Text('Pool IQ',
                    style: TextStyle(fontSize: 60, fontWeight: FontWeight.w800,
                        color: Colors.white, height: 1.0, letterSpacing: -2)),
              ),
              const Text('to start.',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300,
                      color: Colors.white70, height: 1.15)),
              const SizedBox(height: 16),
              // Subtitle
              const Text(
                'Master cue ball control, spin & positioning.\nLearn to think two shots ahead.',
                style: TextStyle(fontSize: 14, color: Colors.white38, height: 1.6),
              ),
              const SizedBox(height: 28),
              // Feature pills
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(Icons.my_location_rounded, 'Auto-aim'),
                  _pill(Icons.rotate_right_rounded, 'Spin control'),
                  _pill(Icons.star_rounded, 'Shot rating'),
                ],
              ),
              const Spacer(flex: 3),
              // Game Start button
              _primaryButton(
                context,
                label: 'Game Start',
                icon: Icons.arrow_forward_rounded,
                onTap: () => Navigator.of(context).push(PageRouteBuilder(
                  pageBuilder: (_, a, b) => const GameScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: const Duration(milliseconds: 400),
                )),
              ),
              const SizedBox(height: 12),
              // Laboratory button
              _secondaryButton(
                context,
                label: 'Laboratory',
                icon: Icons.science_outlined,
                onTap: () => Navigator.of(context).push(PageRouteBuilder(
                  pageBuilder: (_, a, b) => const LabScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: const Duration(milliseconds: 400),
                )),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: const Color(0xFF2ECC71)),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.6))),
      ]),
    );
  }

  Widget _primaryButton(BuildContext context,
      {required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2ECC71), Color(0xFF27AE60)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2ECC71).withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: Colors.white, letterSpacing: 0.3)),
          const SizedBox(width: 8),
          Icon(icon, color: Colors.white, size: 20),
        ]),
      ),
    );
  }

  Widget _secondaryButton(BuildContext context,
      {required String label, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white60, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: Colors.white60)),
        ]),
      ),
    );
  }
}
