# 🛠️ Flutter Commands Cheat Sheet

## 🚀 Running the App

### Android
```bash
# Run on connected device or emulator
flutter run -d android

# If multiple devices are connected, list them first:
flutter devices
flutter run -d <DEVICE_ID>
```

### iOS (Mac Only)
```bash
# Open Simulator
open -a Simulator

# Run on Simulator
flutter run -d ios

# Run on physical iPhone (requires signing)
flutter run -d <DEVICE_ID>
```

## 🏗️ Building

### Android
```bash
# Build Debug APK
flutter build apk --debug

# Build Release Bundle (for Play Store)
flutter build appbundle
```

### iOS
```bash
# Build for Simulator (No signing needed)
flutter build ios --no-codesign --simulator

# Build for Device (Requires Signing in Xcode)
flutter build ios
```

## 🧹 Maintenance

### Clean Project
```bash
# Removes build artifacts (fix weird cache issues)
flutter clean
flutter pub get
```

### iOS Dependencies
```bash
# If iOS build fails, try this:
cd ios
rm -rf Pods
rm Podfile.lock
pod install
cd ..
```
