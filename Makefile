# Makefile for Collectio Flutter App

.PHONY: run-android run-ios build-android build-ios clean lint format help

# Default target
help:
	@echo "Flutter Helper Commands"
	@echo "-----------------------"
	@echo "make run-android   - Run app on Android Emulator/Device"
	@echo "make run-ios       - Run app on iOS Simulator/Device"
	@echo "make build-apk     - Build Android APK (debug)"
	@echo "make build-ios     - Build iOS App (no codesign)"
	@echo "make clean         - Clean project and dependencies"
	@echo "make deps          - Get dependencies (pub get)"
	@echo "make pod-install   - Install iOS pods (Mac only)"

# --- Running ---

run-android:
	flutter run -d android

run-ios:
	open -a Simulator
	flutter run -d ios

# --- Building ---

build-apk:
	flutter build apk --debug

build-ios:
	flutter build ios --no-codesign --simulator

# --- Maintenance ---

clean:
	flutter clean
	flutter pub get

deps:
	flutter pub get

pod-install:
	cd ios && pod install && cd ..
