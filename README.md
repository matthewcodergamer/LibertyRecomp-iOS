# LibertyRecomp iOS

Native iPhone/iPad platform project for the LibertyRecomp GTA IV Xbox 360 static recompilation work.

The shipping architecture is **native ARM64 + Metal**. This is not an Xenia frontend, Wine wrapper, x86/x64 translation layer, or runtime PowerPC JIT.

## Foundation status — Stages 0–5

The repository now contains the first real implementation layer:

- exact LibertyRecomp upstream pin in `UPSTREAM.lock`
- reproducible upstream fetch/verification tooling
- public CI that rejects accidentally committed game payloads and signing secrets
- portable game-content layout/validation code with tests
- GTA IV executable fingerprint manifest and verifier
- macOS reference-source gate
- CMake/Xcode ARM64 iOS toolchain
- unsigned iOS shell build for GitHub Actions
- native UIKit + Metal shell with diagnostics
- AVAudioSession/controller/thermal/lifecycle hooks
- iOS Files folder picker
- storage preflight
- staging-directory import and atomic promotion
- iCloud-backup exclusion for rebuildable/imported game content
- strict default rejection of unknown `default.xex` revisions

The compatibility manifest intentionally has **no invented GTA IV hash**. Until the exact legally owned Xbox 360 executable used by the static recompilation configuration is fingerprinted and added, imports report the SHA-256 and remain unsupported by default.

## Targets

- Baseline device: iPhone 11 / Apple A13
- Architecture: ARM64
- Minimum iOS: 16+
- Graphics: Metal
- Initial gameplay target: stable 30 FPS where practical
- Input target: touch + Apple-supported physical controllers
- Final artifact: signed `.ipa`
- Game data: imported separately from a legally owned Xbox 360 copy

## What is never committed

This repository contains code, tooling, tests, documentation, and build infrastructure only. Do not commit `default.xex`, RPF archives, Xbox disc/ISO/STFS payloads, Rockstar assets, locally generated proprietary game payloads, signing certificates/private keys, or provisioning profiles. CI enforces the obvious cases.

## Portable tests

```bash
python3 scripts/check-prohibited-assets.py
python3 -m unittest discover -s tests -p "test_*.py" -v
cmake --preset host-debug
cmake --build --preset host-debug
ctest --preset host-debug
```

These tests require no GTA IV data.

## Fetch the pinned LibertyRecomp reference

```bash
./scripts/fetch-upstream.sh
```

See [`docs/UPSTREAM.md`](docs/UPSTREAM.md) for the pin/update policy.

## Validate a private extracted game folder

```bash
python3 scripts/verify-game.py /path/to/your/extracted/GTAIV --dry-run
```

For machine-readable diagnostics:

```bash
python3 scripts/verify-game.py /path/to/your/extracted/GTAIV --json
```

An unknown executable is rejected. `--allow-unpinned` exists only for developer investigation and does not make a revision officially supported.

## Build the iOS Foundation shell

A Mac with Xcode is required locally. Public GitHub Actions also cross-compiles this target without signing credentials.

```bash
cmake --preset ios-device-debug \
  -DLIBERTY_IOS_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  -DLIBERTY_IOS_BUNDLE_IDENTIFIER=com.yourname.libertyrecomp
cmake --build --preset ios-device-debug
```

Without a development team, the project configures an unsigned compile-only app suitable for CI.

### Important build options

- `LIBERTY_IOS_SHELL_ONLY=ON`
- `LIBERTY_IOS_CONTENT_MODE=imported|embedded`
- `LIBERTY_IOS_GAMECENTER=OFF` by default
- `LIBERTY_IOS_DIAGNOSTICS=ON`
- `LIBERTY_IOS_ALLOW_UNPINNED_CONTENT=OFF` by default

## Content layout

```text
Application Support/LibertyRecomp/
  Game/
  DLC/
  Cache/
  Config/

Documents/LibertyRecomp/
  saves/
```

The native importer copies a user-selected extracted game folder into `Game.staging/`, validates the supported executable revision, checks free storage, then promotes the completed staging directory to `Game/`. Interrupted imports do not become valid installations.

## Current validation boundary

GitHub CI can test Python/C++ logic and cross-compile the unsigned ARM64 iOS shell. It cannot prove physical iPhone launch, actual GTA IV runtime execution, real Metal frame timing, iPhone 11 memory/thermal performance, or signed IPA installation. Those become physical-device gates as the runtime is integrated.

See [`ROADMAP.md`](ROADMAP.md) for the complete zero-to-IPA plan and [`PROMPTS.md`](PROMPTS.md) for staged implementation prompts.
