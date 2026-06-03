# Pool IQ - Setup

## 安裝 Flutter

```bash
# macOS via Homebrew
brew install --cask flutter

# 或下載 SDK
# https://docs.flutter.dev/get-started/install/macos
```

## 建立並執行

```bash
# 在此目錄執行
cd /Users/leomok/workspace/pool-tutorial

# 建立 Flutter 專案骨架（只需一次）
flutter create . --org com.pooliq

# 安裝依賴
flutter pub get

# 執行 (macOS)
flutter run -d macos

# 執行 (iOS Simulator)
open -a Simulator
flutter run -d iPhone

# 執行 (Android)
flutter run -d android
```

> 注意：`flutter create .` 會在現有目錄建立 Flutter 骨架，
> 已存在的 lib/ 檔案會被保留。
