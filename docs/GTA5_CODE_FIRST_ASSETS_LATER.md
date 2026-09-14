# GTA V iOS — Code First, Assets Later

This document defines a staged workflow for preparing a GTA V iOS port before the full game-data set is available on the development machine.

## Legal/source boundary

Owning GTA V on Epic Games gives access to the installed game data for that copy, but it does not by itself grant rights to proprietary Rockstar source code. Do not place Rockstar source, leaked source, game assets, private keys, or redistributed mobile/Switch game packs in this public repository.

If a complete GTA V source tree is lawfully available and may be modified, keep it in a separate private workspace. If not, use the public SanRecomp/XenonRecomp clean-room route.

## Goal

Do as much iOS-specific engineering as possible before importing the real GTA V assets. The codebase should be able to build, launch, initialize platform services, exercise the renderer, and validate the asset pipeline with synthetic fixtures.

## Phase 0 — Public iOS scaffold

Build without GTA V data:

- Apple Clang ARM64 target
- iOS 16+ deployment target
- UIKit application/scene lifecycle
- CAMetalLayer / Metal device / command queue
- frame loop and clear/present test
- AVAudioSession setup
- GameController discovery
- touch-input abstraction
- Application Support / Documents / Cache paths
- logging and crash diagnostics
- memory-pressure notifications
- thermal-state notifications
- foreground/background handling
- CI cross-compilation of an unsigned ARM64 app

Gate: clean public checkout builds without any Rockstar data.

## Phase 1 — Engine/platform abstraction

If lawful source is available privately, isolate platform dependencies behind small interfaces rather than scattering iOS conditionals throughout the engine.

Suggested boundaries:

```text
Platform/
  Threads
  Time
  Files
  VirtualMemory
  Logging
  User
  Saves
  Input
  Audio
  Networking
  Video

Render/
  Device
  Buffers
  Textures
  Samplers
  PipelineState
  RenderPass
  ShaderLibrary
  UploadQueue
  Present
```

Gate: as much engine/runtime code as possible compiles for `arm64-apple-ios` with renderer/game-data consumers stubbed where necessary.

## Phase 2 — Asset contract before assets

Define the mobile asset pipeline before the laptop has the complete GTA V installation.

Public code may include:

- manifest schemas
- file-type classifiers
- expected logical paths
- hashing/validation code
- dependency graphs
- texture-conversion interfaces
- mesh/LOD conversion interfaces
- audio/video policy interfaces
- cache-key generation
- storage preflight
- staging + atomic promotion logic
- synthetic test fixtures

Do not hard-code proprietary file contents into tests.

Example output layout:

```text
Application Support/GTA5-iOS/
  Game/
  Cooked/
    Textures/
    Geometry/
    Audio/
    Video/
    Shaders/
  Cache/
  Config/

Documents/GTA5-iOS/
  Saves/
```

## Phase 3 — Synthetic renderer validation

Before GTA data exists, prove the Metal path with generated content:

1. clear/present
2. colored triangle
3. indexed geometry
4. textured quad
5. depth test
6. alpha blending
7. offscreen render target
8. mipmapped texture
9. instancing
10. compute/upload test if required
11. pipeline-cache reuse
12. dynamic-resolution resize

Gate: stable 30 FPS shell on the iPhone 11 with no unbounded memory growth.

## Phase 4 — A13 baseline from day one

Use the iPhone 11 profile immediately:

- 30 FPS target / 33.33 ms frame budget
- ARM64 AOT only
- direct Metal
- dynamic internal resolution approximately 854x480 to 1280x720
- no MSAA by default
- conservative shadow/reflection targets
- bounded texture/buffer/shader/pipeline caches
- async storage
- no main-thread asset reads
- conservative worker count
- initial ~2 GB resident-memory soft engineering target, adjusted only from real device measurements
- thermal degradation order: resolution -> shadows -> reflections -> post FX -> cache/work trim

## Phase 5 — Laptop asset ingestion later

When the development laptop is available:

1. Install the user's legitimate GTA V copy through Epic Games.
2. Record the exact game build/version.
3. Point the local/private asset tool at the installed game directory.
4. Inventory every archive/resource class before modifying anything.
5. Produce hashes and a machine-readable manifest.
6. Run conversion into a separate staging directory; never modify the original installation in place.
7. Validate converted outputs before promotion.
8. Measure size per category before and after conversion.
9. Import the cooked output to the iPhone through the app's file importer or a development deployment path.
10. Keep all Rockstar-derived outputs private/local.

## Compression/optimization order

Do not blindly recompress every file. Optimize in this order:

1. remove content not required by the selected single-player build/profile
2. reduce duplicate/redundant build outputs
3. tune texture resolution and GPU format where quality permits
4. tune LOD and distance settings
5. reduce expensive render-target sizes
6. tune audio/video bitrate only after measuring their storage and runtime cost
7. bound streaming residency and temporary conversion buffers
8. preserve files that are already efficiently compressed unless conversion has a measured benefit

Every transformation should be deterministic and recorded in a manifest so the mobile data pack can be reproduced from the owned desktop installation.

## First real-data milestones

Once real game data is available, bring it in incrementally:

```text
engine boot
 -> one known texture
 -> one known mesh
 -> one translated shader/material
 -> first GTA-authored draw
 -> frontend/logo resources
 -> menu
 -> map sector streaming
 -> player
 -> vehicle
 -> prologue
 -> open world
```

Do not begin by copying the complete PC installation to the phone and debugging everything at once.

## Source-first limitation

The full GTA game cannot be proven playable with no matching assets. What can be completed early is the Apple platform layer, ARM64 build path, Metal renderer host, asset contracts/converters, diagnostics, controls, memory/thermal policy, CI, and synthetic rendering tests.

Real integration starts when a matching, legitimately obtained game-data set is available.
