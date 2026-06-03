# Pool IQ 🎱

> Upgrade your Pool IQ — a billiards training app built with Flutter + Forge2D.

Master cue ball control, spin, and positioning. The app auto-aims the angle for you — your job is to choose the right **spin** and **power** to pocket the ball *and* leave the cue ball in the perfect spot for the next shot.

---

## Features

| Feature | Description |
|---|---|
| **Auto-aim** | Shot angle is calculated automatically via ghost-ball method |
| **Spin control** | Tap the cue ball diagram to set English (left/right/top/back) |
| **Power slider** | Vertical slider, green → red |
| **Aim overlay** | Dashed aim line, ghost ball, green pocket line, blue deflection line |
| **Position zone** | Orange circle shows ideal landing zone for next shot |
| **Shot evaluator** | Rates your cue ball position 0–100 after each pot |

---

## Prerequisites

Install Flutter (one time):

```bash
# macOS (Homebrew)
brew install --cask flutter

# Verify installation
flutter doctor
```

> Requires Flutter ≥ 3.0 and Dart ≥ 3.0

---

## Getting Started

```bash
# 1. Clone the repo
git clone <repo-url>
cd pool-tutorial

# 2. Install dependencies
flutter pub get
```

---

## Running the App

### 📱 iOS (Simulator)

```bash
# Open Simulator first
open -a Simulator

# List available simulators
flutter devices

# Run on iPhone simulator
flutter run -d iPhone

# Or target a specific simulator
flutter run -d "iPhone 16"
```

> Requires Xcode installed (`xcode-select --install`)

---

### 🤖 Android (Emulator or Device)

```bash
# Start Android emulator via Android Studio, then:
flutter devices                     # verify device is listed
flutter run -d android

# Or target a specific emulator/device
flutter run -d emulator-5554

# On a physical Android device (enable USB debugging first)
flutter run -d <device-id>
```

> Requires Android Studio with an emulator, or a physical device with USB debugging enabled.

---

### 🖥 Desktop

#### macOS
```bash
flutter run -d macos
```

#### Windows
```bash
flutter run -d windows
```

#### Linux
```bash
flutter run -d linux
```

---

## Build Release

```bash
# macOS app bundle
flutter build macos

# iOS .ipa (requires Apple Developer account)
flutter build ios --release

# Android .apk
flutter build apk --release

# Android .aab (for Play Store)
flutter build appbundle
```

---

## Project Structure

```
lib/
├── main.dart                     # App entry, force landscape, immersive mode
├── screens/
│   ├── home_screen.dart          # Animated home page with orbiting balls
│   └── game_screen.dart          # Game UI shell (HUD + controls overlay)
├── game/
│   ├── pool_game.dart            # Forge2DGame: physics, auto-aim, ball logic
│   ├── shot_evaluator.dart       # Score 0–100 based on cue ball position
│   └── components/
│       ├── ball_component.dart   # Physics ball + gradient rendering
│       ├── table_component.dart  # Felt surface, rails, pockets
│       └── aim_overlay.dart      # All aiming guides drawn in world coords
└── widgets/
    ├── hit_point_selector.dart   # Circle cue ball spin selector
    └── power_slider.dart         # Vertical power bar
```

---

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `flame` | ^1.19.0 | Game engine |
| `flame_forge2d` | ^0.19.0 | Box2D physics bridge |
| `google_fonts` | ^6.2.1 | Inter + Space Mono fonts |
| `flutter_animate` | ^4.5.0 | Home screen animations |

---

## Controls

| Control | Action |
|---|---|
| **Spin selector** (left) | Tap/drag to set cue ball hit point |
| **Power slider** (right) | Drag up/down to set shot power |
| **Strike button** (center green) | Fires the shot |

The aim lines update in real-time as you adjust spin — the **blue dashed line** shows where the cue ball will deflect after contact (90° rule).
