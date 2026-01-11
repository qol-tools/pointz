.PHONY: help build run check test clean release pair

help:
	@echo "PointZ - Flutter mobile client for remote PC control"
	@echo ""
	@echo "Commands:"
	@echo "  make run      - Run Flutter app on connected device"
	@echo "  make build    - Build debug release"
	@echo "  make release  - Build production release"
	@echo "  make test     - Run Flutter tests"
	@echo "  make check    - Check Flutter/ADB setup"
	@echo "  make pair     - Pair phone for wireless ADB"
	@echo "  make clean    - Clean build artifacts"

run:
	@bash scripts/adb-autoconnect.sh || true
	flutter run

build:
	flutter build apk --debug

release:
	flutter build apk --release

test:
	flutter test

check:
	@echo "Checking Flutter..."
	@flutter --version
	@echo ""
	@echo "Checking ADB..."
	@adb version || echo "ADB not found. Install Android SDK Platform Tools."
	@echo ""
	@echo "Checking connected devices..."
	@adb devices

pair:
	@bash scripts/adb-pair-wireless.sh

clean:
	flutter clean
