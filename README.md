<div align="center">
  <a href="https://github.com/qol-tools/pointz">
    <img
      src="assets/pz-banner.svg"
      alt="PointZ"
      width="442"
      height="159"
    />
  </a>
</div>

<br>

<p align="center">Mobile client for remote PC control</p>

## Platform Support

- [x] Android
- [ ] iOS

## Overview

PointZ is a Flutter mobile app that lets you control your PC from your phone. Works with [PointZerver](https://github.com/qol-tools/pointzerver) running on your computer.

## Features

- Touch-based mouse control with acceleration
- Multi-finger gestures (2-finger right-click, 3-finger middle-click)
- Hardware keyboard passthrough
- Tap-and-hold drag mode
- Automatic server discovery

## Installation

Download from [Releases](https://github.com/qol-tools/pointz/releases) or build from source.

## Usage

1. Start [PointZerver](https://github.com/qol-tools/pointzerver) on your PC
2. Ensure phone and PC are on the same network
3. Launch the PointZ app
4. Tap your computer's name from the discovery list

## Building

**⚠️ IMPORTANT:** Clone to a path **without spaces**. Flutter/Gradle cannot build from paths containing spaces.

```bash
make build    # Build debug release
make release  # Build production release
make run      # Run on device
make pair     # Pair phone via wireless ADB
```
