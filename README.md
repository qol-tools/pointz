<div align="center">

# PointZ

[![tests](https://github.com/qol-tools/pointz/actions/workflows/tests.yml/badge.svg)](https://github.com/qol-tools/pointz/actions/workflows/tests.yml)
[![lint](https://github.com/qol-tools/pointz/actions/workflows/lint.yml/badge.svg)](https://github.com/qol-tools/pointz/actions/workflows/lint.yml)
[![Build and Release](https://github.com/qol-tools/pointz/actions/workflows/release.yml/badge.svg)](https://github.com/qol-tools/pointz/actions/workflows/release.yml)

A mobile client for remote PC control, paired with the [PointZerver](https://github.com/qol-tools/qol/tree/main/plugins/pointz) plugin for [qol](https://github.com/qol-tools/qol).

</div>

## Quick start

Download from [Releases](https://github.com/qol-tools/pointz/releases), or build from source:

```bash
git clone https://github.com/qol-tools/pointz
cd pointz
make build
```

Clone to a path without spaces; Flutter and Gradle reject paths containing whitespace.

## Pairing

The desktop shows a 6-digit code while pairing is open. Pick the desktop in the app, type the code, and tap Pair. The phone and desktop prove they know the same code without sending it, and every command afterwards is encrypted with a key only that pair holds.

A phone pairs with one desktop at a time per pairing; each desktop you use needs its own. If the desktop forgets the phone, open pairing on the desktop again, long-press the desktop in the app, and pair once more.

## About

The mobile half of qol's PointZ remote-control plugin.

## License

PolyForm Noncommercial 1.0.0
