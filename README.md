# LibertyRecomp iOS

Native iPhone/iPad target for the LibertyRecomp GTA IV Xbox 360 static recompilation project.

## Goal

Build a native ARM64 iOS port based on static recompilation, using Metal for graphics and a mobile-first platform layer. The repository contains only code, tooling, tests, documentation, and build infrastructure. It must not contain Rockstar game assets, `default.xex`, RPF archives, or other copyrighted game data.

## Source project

This project is designed to build on the existing LibertyRecomp work in `matthewcodergamer/LibertyRecomp` rather than reinventing the CPU runtime, RAGE compatibility layer, shader tooling, VFS, saves, audio, input, and game-specific fixes.

## Initial target

- Device baseline: iPhone 11 / Apple A13
- Architecture: ARM64
- Minimum iOS target: iOS 16+
- Graphics: Metal
- Performance target: stable 30 FPS where practical, using dynamic resolution and adaptive quality
- Input: touch controls plus Apple-supported physical controllers
- Distribution artifact: signed `.ipa`
- Game data: imported separately from a legally owned Xbox 360 copy

## Development rule

No fake fixes. When behavior diverges from the Xbox 360 version, instrument the first point of divergence, fix the underlying CPU/runtime/renderer/platform semantics, and add a regression test.

See `ROADMAP.md` for the full zero-to-IPA development plan and `PROMPTS.md` for staged implementation prompts.