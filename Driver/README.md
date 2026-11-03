# VSLight Audio Driver

A minimal AudioServerPlugIn that exposes a virtual output device and applies per-client gain.

## Architecture

- Based on [libASPL](https://github.com/gavv/libASPL) (MIT). The source is fetched at build time and pinned by commit in `Scripts/build-driver.sh`.
- Exposes a stereo device with an output stream and a loopback input stream.
- `OnProcessClientOutput` applies per-app gain based on the client bundle ID or PID.
- The app writes gains through the custom property `'apvl'` (array of dictionaries with `bundleID`, `pid`, `volume`, `muted`).
- The mixed signal is written into a ring buffer and served from the input stream to the loopback helper in the app.
- The output stream has volume and mute controls, so the menu bar volume works as the master gain.

## Build

```bash
./Scripts/build-driver.sh
```

The script clones libASPL, compiles it with the macOS 27 SDK, creates `Driver/build/VSLightAudioDriver.driver`, and signs it (ad-hoc by default, Developer ID when `CODESIGN_ID` is set).

## Install

```bash
sudo ./Scripts/install-driver.sh
```

The driver is copied to `/Library/Audio/Plug-Ins/HAL` and `coreaudiod` is restarted. Uninstall:

```bash
sudo ./Scripts/install-driver.sh --uninstall
```

## Limitations

- Requires administrator approval.
- Adds one IO buffer of routing latency.
- Not suitable for the Mac App Store.
- The app must be running for the loopback path; it restores the previous output device on quit.
- The driver is built for the current architecture (arm64 by default). Set `ARCH=x86_64` to build an Intel slice.

## License

libASPL is MIT licensed. See the upstream repository for its license and Apple sample notices.
