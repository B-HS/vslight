<p align="center">
  <img src="Resources/icon.png" width="96" height="96" alt="VSLight" />
</p>

<h1 align="center">VSLight</h1>

<p align="center">A native macOS 27 volume controller with precise control, presets, and output switching.</p>

<p align="center">
  <a href="https://github.com/B-HS/vslight/releases/latest"><b>Download the latest release</b></a>
</p>

## Features

- Precise system volume with a slider and click-to-edit percentage.
- Presets with global Carbon shortcuts. No default presets.
- Output device switching from the menu bar window.
- Liquid Glass UI, macOS 27 `reorderable()`, and Swift 6 strict concurrency.
- Sleep/wake, session, CoreAudio restart, and device-change recovery.
- Launch at login with approval state and restart controls.
- Per-app volume through a bundled HAL audio driver.

## Requirements

- macOS 27.0 or later
- Xcode 27.2 or later (source builds)
- XcodeGen (`brew install xcodegen`)

## Install

Download the release ZIP and move `VSLight.app` to `/Applications`.

If the app is ad-hoc signed, right-click it and choose Open on first launch.

Per-app volume requires the bundled driver in `/Library/Audio/Plug-Ins/HAL`. The app provides an install button. Installation needs an administrator password and restarts `coreaudiod`.

## Usage

1. Click the speaker icon in the menu bar.
2. Choose an output device at the top.
3. Drag the slider or click the percentage to edit it.
4. Create presets and shortcuts in Settings > Presets.
5. Manage Login Items in Settings > General.
6. Enable per-app volume in Settings > Per-App Volume.

## Build

```bash
xcodegen generate
xcodebuild -project VSLight.xcodeproj -scheme VSLight -configuration Debug \
  -derivedDataPath build build
open build/Build/Products/Debug/VSLight.app
```

Tests:

```bash
xcodebuild -project VSLight.xcodeproj -scheme VSLight \
  -destination 'platform=macOS' test
```

## Per-App Audio Driver

```bash
./Scripts/build-driver.sh
sudo ./Scripts/install-driver.sh
```

Uninstall with `sudo ./Scripts/install-driver.sh --uninstall`.

The driver is built on [libASPL](https://github.com/gavv/libASPL) (MIT). It adds one IO buffer of routing latency and is not App Store compatible.

## Release

Signing and notarization keys are documented in [docs/RELEASE.md](docs/RELEASE.md). Both GitHub workflows use the `MACOS_RUNNER` variable when set; otherwise they use `macos-27`.

## Limitations

- Per-app volume requires driver installation and the app must stay running for the loopback path.
- The app is not sandboxed; distribution uses Developer ID.
- Automatic updates are not included.
