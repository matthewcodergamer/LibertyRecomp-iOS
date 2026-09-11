# LibertyRecomp iOS — Implementation Prompts

Use these prompts **one stage at a time** with a capable coding agent. Do not paste all stages into one task. Every stage assumes the previous stage's exit criteria are satisfied.

## Master operating prompt — prepend to every stage

```text
You are working in https://github.com/matthewcodergamer/LibertyRecomp-iOS.
The upstream/reference project is https://github.com/matthewcodergamer/LibertyRecomp.

Goal: build a native ARM64 iOS port of the Xbox 360 version of GTA IV using LibertyRecomp static recompilation, with Metal graphics and an iPhone 11/A13 baseline. This is not an emulator frontend. Do not introduce Xenia, Wine, x86/x64 translation, or a runtime PPC JIT as the shipping architecture.

Before changing code:
1. Inspect the current repository and relevant upstream files. Do not assume paths or APIs exist.
2. Read ROADMAP.md and preserve completed work.
3. Reuse upstream LibertyRecomp/ReXGlue/RAGE/VFS/audio/save/input/shader infrastructure where possible. Do not reinvent existing systems.
4. Never commit Rockstar assets, default.xex, RPF archives, extracted game files, keys, proprietary generated game payloads, signing certificates, provisioning profiles, or secrets.
5. Fix root causes instead of adding fake gameplay workarounds. If behavior diverges from Xbox 360, identify the first semantic/runtime divergence.
6. Add regression tests for low-level fixes whenever practical.
7. Keep the iPhone 11/A13 target in mind: 30 FPS target, bounded memory, Metal, asynchronous I/O, thermal adaptation.
8. Preserve a desktop/macOS reference path so iOS-specific bugs can be distinguished from core/runtime bugs.
9. Do not claim code works unless you actually ran the available tests/builds or CI proves it. If physical-device validation is required, say so explicitly.
10. Keep changes scoped to the requested stage. Do not jump ahead and create speculative systems that cannot yet be tested.

For every task:
- inspect first
- make the smallest coherent implementation
- run formatting/tests/builds available in the environment
- fix failures
- update documentation
- summarize files changed, commands/tests run, remaining blockers, and exact next step
- commit with a clear message
```

---

## Prompt 0 — repository foundation

```text
[Use the Master operating prompt above.]

Implement Stage 0 of ROADMAP.md.

Tasks:
- inspect this new repository and the upstream LibertyRecomp repository
- create a documented upstream integration strategy; prefer a pinned submodule or clearly pinned fork/reference rather than manually copying source
- add .gitignore rules for build output, DerivedData, local GTA game data, default.xex, *.rpf, local payload directories, signing material, caches, and Xcode user state
- add docs/UPSTREAM.md containing the exact expected upstream repository and a place for the pinned commit SHA
- add config/game_versions/gta4_x360_supported.json as a schema/example with placeholder values only; do not invent hashes
- add scripts/verify-game.py that validates a supplied private extracted game folder without copying or redistributing assets; support a dry-run mode and clear errors
- add unit tests for verify-game.py using temporary dummy files
- add a prohibited-assets CI check that fails if obvious proprietary payload filenames or signing secrets are committed
- add a basic GitHub Actions workflow for script/unit tests
- update README with development flow

Exit criteria:
- clean checkout runs the unit tests without GTA data
- .gitignore protects private payloads
- no proprietary asset is committed
- CI configuration is valid
- document exactly what still requires a Mac/device
```

## Prompt 1 — pin and integrate LibertyRecomp

```text
[Master operating prompt]

Implement Stage 1 of ROADMAP.md.

Inspect the upstream LibertyRecomp structure and determine the cleanest maintainable integration method for this repository. Pin an exact upstream revision and make the project able to reference/build it reproducibly.

Requirements:
- preserve upstream history or pinning; do not paste a giant unmanaged source snapshot
- document how to update the upstream pin safely
- expose build metadata containing this repo commit + upstream commit
- preserve upstream tests
- add a CI job that validates the upstream checkout/pin
- do not require game assets for CI configuration-only tests

If a full macOS build cannot complete without private inputs, split the target so framework/platform code can still be compiled/tested independently and clearly document the limitation.
```

## Prompt 2 — establish the macOS reference build

```text
[Master operating prompt]

Implement the desktop/macOS oracle from Stages 1-2.

Tasks:
- inspect upstream macOS build presets and dependencies
- make the pinned source configure and compile on a GitHub macOS runner as far as legally possible without private game assets
- keep a separate optional developer path for a complete local build using legally owned private game files
- add build metadata logging
- preserve or enable ReXGlue CPU tests on ARM64/macOS when feasible
- make CI artifacts contain only project binaries/logs, never game data

Exit criteria:
- macOS CI has a deterministic pass/fail result
- build failures identify missing private data separately from code/toolchain failures
```

## Prompt 3 — make iOS a first-class CMake/Xcode target

```text
[Master operating prompt]

Implement Stage 2: iOS ARM64 toolchain reliability.

Inspect existing upstream iOS support before writing anything.

Requirements:
- minimum deployment target iOS 16+
- ARM64 device target
- Xcode generator / Apple Clang
- Metal forced on; Vulkan/D3D paths off on iOS
- compile options: LIBERTY_IOS_SHELL_ONLY, LIBERTY_IOS_CONTENT_MODE, LIBERTY_IOS_GAMECENTER, LIBERTY_IOS_DIAGNOSTICS
- no signing requirement for configuration/compile-only CI where possible
- isolate or replace desktop-only dependencies cleanly
- do not start GTA runtime in shell-only builds
- add a macOS GitHub Actions job that configures and compiles the shell target

Fix every compile/link error you encounter rather than suppressing it blindly.
```

## Prompt 4 — native iOS shell

```text
[Master operating prompt]

Implement Stage 3: a real native iOS shell that can run independently of GTA data.

Required subsystems:
- application lifecycle
- SDL bootstrap only if upstream actually uses it
- Metal device + command queue + drawable + clear/present
- os_log logging
- AVAudioSession setup
- controller discovery
- Documents/Application Support/Caches paths
- memory warning handling
- thermal-state handling
- foreground/background handling
- landscape orientation policy

Add a simple diagnostic screen showing build commit, upstream commit, iOS version, device model, Metal device name, thermal state, and game-content status.

Add unit-testable platform-independent pieces. CI must compile the iOS shell. Physical device execution remains a separate test gate.
```

## Prompt 5 — content provider and importer architecture

```text
[Master operating prompt]

Implement Stages 4-5.

Create a GameContentProvider abstraction that fits the existing LibertyRecomp VFS instead of bypassing it.

Implement:
- EmbeddedContentProvider for developer bring-up
- IOSImportedContentProvider for normal use
- Application Support/LibertyRecomp/Game, DLC, Cache, Config layout
- Documents/LibertyRecomp/saves layout
- iCloud-backup exclusion for rebuildable/imported game data
- staging-directory import with atomic promotion
- storage-space preflight
- validation before install becomes active
- interrupted-import recovery
- supported executable fingerprint metadata

The UI should explain that the user must import files from a legally owned Xbox 360 copy. Do not bundle or download copyrighted content.

Build importer logic so core validation/copy-state code is unit testable with dummy files on CI.
```

## Prompt 6 — PowerPC/ReXGlue correctness gate

```text
[Master operating prompt]

Implement Stage 6 using the existing ReXGlue tests first.

Audit the currently covered PPC integer, floating-point, endian, CR/XER, VMX/Altivec, saturation, permutation, aliasing, atomic, and ordering behavior relevant to GTA IV.

Add missing regression coverage, especially instructions whose destination may alias a source. Add property/differential tests where a trustworthy reference implementation already exists.

Do not change generated GTA game logic to hide instruction bugs. Fix the instruction generator/runtime semantics and regenerate as required.

Make these tests part of CI on an ARM64-capable/macOS path where feasible.
```

## Prompt 7 — guest memory and endian diagnostics

```text
[Master operating prompt]

Implement Stage 7.

Inspect the current LibertyRecomp/ReXGlue guest-memory abstractions before adding new ones. Centralize or strengthen:
- guest/host address translation
- alignment checks
- region/page tracking
- virtual/physical allocation accounting
- big-endian reads/writes
- allocation lifetime diagnostics

Add an optional debug guard mode. On an invalid access, log guest PC/LR/thread, address, size, read/write type, region metadata, and recent guest-call history.

Keep release overhead low by compiling expensive diagnostics out or gating them.
```

## Prompt 8 — Xbox host services on iOS

```text
[Master operating prompt]

Implement Stage 8 by auditing what upstream already provides.

Validate iOS behavior for threads, mutexes, semaphores, events, timers, sleep/yield, time base, files, directories, async I/O, VFS mounts, locale, user profile, saves, controllers, and network stubs.

Map guest thread roles to sensible Darwin/pthread QoS instead of blindly copying Xbox priority numbers. Never place expensive I/O on real-time audio or rendering threads.

Add tests/mocks for host services that can run without GTA data.
```

## Prompt 9 — enter the recompiled GTA runtime

```text
[Master operating prompt]

Implement Stage 9.

Goal: transition from the iOS shell into the recompiled GTA IV runtime using the supported private game revision.

Add:
- boot-step markers
- guest PC/LR logging
- guest thread names/IDs where known
- recent-call ring buffer
- deterministic crash/blocker reporting

Do not try to fix every failure in one change. Identify the first reproducible blocker, fix it at the correct layer, add a regression test, then repeat.

When private game data is unavailable in CI, maintain a synthetic/bootstrap test that validates the host runtime entry plumbing.
```

## Prompt 10 — Metal renderer first frame

```text
[Master operating prompt]

Implement Stage 10 only after runtime entry is stable.

Bring up rendering incrementally:
1. Metal clear/present
2. known debug triangle
3. host buffer upload
4. one GTA vertex/index buffer
5. one translated shader
6. first GTA draw
7. depth/stencil
8. texture/sampler
9. blending

Add Metal debug labels for command buffers, encoders, pipelines, textures, buffers, and major passes.

Keep a renderer test mode that can run without GTA data using synthetic resources.

Exit only when a GTA-generated draw command reaches Metal correctly on a physical device, or when CI has completed all non-device prerequisites and the remaining gate is explicitly documented.
```

## Prompt 11 — Xenos resource conversion

```text
[Master operating prompt]

Implement Stage 11 by reusing existing upstream Xenos/native-renderer conversion code wherever possible.

Validate:
- texture untile
- endianness
- mip layout
- Xbox texture formats to Metal-compatible formats
- vertex/index formats
- render targets
- depth/stencil
- resolves/MSAA as needed
- sRGB/gamma
- samplers
- blend/alpha behavior
- viewport/scissor

Create deterministic resource-conversion tests using synthetic known patterns. Avoid requiring copyrighted textures for CI.
```

## Prompt 12 — shader translation and pipeline-state cache

```text
[Master operating prompt]

Implement Stage 12.

Inspect the existing RAGE FXC/XenosRecomp pipeline and macOS Metal path. Reuse it rather than inventing a second shader compiler.

Requirements:
- produce Metal-consumable shader artifacts
- preserve Xbox shader constants/register semantics
- stable cache keys that include source hash, translator version, feature flags, and relevant formats
- MTLRenderPipelineState cache keyed by shaders + render/depth formats + blend + vertex layout + sample count
- cache invalidation on translator/build changes
- prewarm known common pipelines where possible
- background compilation only when safe; never introduce a new frame-time hitch path

Add cache hit/miss/build-time instrumentation.
```

## Prompt 13 — streaming and iOS storage I/O

```text
[Master operating prompt]

Implement Stage 13 while preserving GTA IV's existing streaming state machine and VFS/device architecture.

Optimize the host path, not the game's semantics:
- asynchronous file I/O
- no main-thread blocking reads
- instrumentation for request latency, bytes/frame, outstanding requests, cache hit rate
- release temporary untile/conversion buffers after GPU upload when safe
- bounded caches
- only add read-ahead based on profiling

Add stress tests with synthetic archives/files where possible.
```

## Prompt 14 — physics/collision correctness

```text
[Master operating prompt]

Implement Stage 14.

Use the repository's existing collision diagnostics and prior CPU-semantics lessons. Trace the complete path from streamed collision asset to contact generation.

Test standing, jumping, slopes, stairs, roads, streamed boundaries, vehicles, ragdolls, projectiles, bridges, and interiors.

Never fix fall-through by teleporting the player, enlarging all bounds, disabling collision, or forcing Z positions. Find the first corrupted state and fix its source.
```

## Prompt 15 — iOS audio and media

```text
[Master operating prompt]

Implement Stage 15.

Reuse existing XMA/audio decoding. Add robust iOS host integration:
- AVAudioSession categories/options
- route change
- interruption
- Bluetooth/headphones
- background/foreground
- decoded ring buffers
- no blocking file access in realtime callback

Audit logos/video/media paths. Prefer executing the existing guest path where it already works; add a host decoder only for an actual missing host capability.

Add underrun counters and long-session audio diagnostics.
```

## Prompt 16 — touch + physical controller input

```text
[Master operating prompt]

Implement Stage 16.

Feed both physical controller and touch into the same Xbox input abstraction.

Touch design:
- left virtual stick
- right-side drag camera area by default
- ABXY
- L1/L2/R1/R2
- D-pad
- Start/Back
- L3/R3
- context-aware on-foot/vehicle visibility
- multi-touch without button stealing
- safe-area/notch handling
- editor for position, size, opacity, sensitivity, deadzone, hide/reset
- separate on-foot and vehicle profiles

Physical controllers:
- SDL/GameController integration
- DualShock 4
- DualSense
- Xbox Wireless
- MFi when available
- hot-plug
- optionally hide/fade touch controls when controller is active

Add a synthetic input-test screen independent of GTA.
```

## Prompt 17 — saves, settings, suspend/resume

```text
[Master operating prompt]

Implement Stage 17.

Requirements:
- atomic save writes
- previous-save backup
- export/import saves
- keep mobile host settings separate from original GTA settings
- on background: pause simulation/input/audio and safely finish or suspend GPU work
- on foreground: recreate/reacquire drawable/resources as needed, restore audio/controller, then resume
- handle lock, notification center, calls, headphones, controller disconnect, memory warning

Add lifecycle state-machine tests where possible.
```

## Prompt 18 — opening-sequence certification

```text
[Master operating prompt]

Do not add new architecture in this task. Use the current build to certify and fix the exact opening sequence path from app launch through save/reload.

Maintain a checklist for:
logos → title → menu → New Game → loading → opening sequence → first cutscenes → player control → first vehicle → city drive → mission transition → save → quit → relaunch → load → continue.

For each failure:
- capture diagnostics
- find first divergent subsystem
- fix root cause
- add regression coverage where practical
- update compatibility status

Do not declare the milestone complete without a physical-device pass.
```

## Prompt 19 — open-world compatibility sweep

```text
[Master operating prompt]

Implement Stage 19 compatibility tracking and fixes.

Create a machine-readable compatibility matrix and human-readable report for all islands and major systems: traffic, pedestrians, police, wanted level, weapons, explosions, weather, day/night, interiors, shops, phone, vehicles, boats, helicopters, motorcycles, missions, streaming, saves.

Each entry records PASS/PARTIAL/BLOCKED, tested commit, device, and concise evidence.

Fix progression blockers before cosmetic bugs.
```

## Prompt 20 — performance instrumentation

```text
[Master operating prompt]

Implement Stage 20 before doing broad optimization.

Add low-overhead metrics for:
- FPS/frame time
- game CPU
- render CPU
- GPU duration
- physics
- streaming
- process memory
- guest memory
- texture/buffer/staging/cache memory
- audio cache
- shader/pipeline cache
- dynamic resolution
- thermal state

Provide an optional in-game diagnostic overlay and exportable trace/report. Make metrics easy to disable in release builds.
```

## Prompt 21 — A13 CPU optimization

```text
[Master operating prompt]

Profile on iPhone 11/A13 using the Stage 20 instrumentation. Optimize only measured CPU bottlenecks.

Investigate:
- scalar PPC vector translations that can safely use SIMD
- unnecessary endian conversions
- guest/host translation hot paths
- locks/contention
- allocator churn
- streaming decompression
- render state translation
- duplicate per-frame/per-draw work

Every SIMD/semantic optimization needs correctness tests. Report before/after timings for each meaningful optimization.
```

## Prompt 22 — Metal GPU optimization

```text
[Master operating prompt]

Profile GPU-limited scenes on iPhone 11 and implement Stage 22.

Focus on measured issues:
- duplicate resources/uploads
- avoidable framebuffer copies/resolves
- staging-buffer reuse
- command encoder fragmentation
- pipeline switches/cache misses
- bandwidth-heavy passes
- overdraw
- shadows/reflections
- render-target size

Do not reduce visual quality blindly. Record GPU-time and visual-regression results before/after.
```

## Prompt 23 — dynamic resolution and presets

```text
[Master operating prompt]

Implement Stage 23.

Add Performance, Balanced, Quality, and Custom presets. Target 30 FPS / 33.3 ms on iPhone 11.

Implement a stable dynamic-resolution controller using smoothed GPU/frame-time history, hysteresis, gradual changes, and min/max scale. Prevent frame-to-frame oscillation.

Start from Xbox-equivalent visuals. Treat approximately 540p–720p-class internal resolution as an initial tuning range, then tune from real A13 measurements.

Log resolution decisions and expose them in diagnostics.
```

## Prompt 24 — memory pressure and thermal adaptation

```text
[Master operating prompt]

Implement Stage 24.

Build IOSMemoryBudgetController around actual existing allocators/caches. Track process, guest, textures, buffers, staging, audio, shaders/pipelines, and other large caches.

On memory pressure, trim only resources that can be safely recreated. Never violate guest-visible residency semantics.

Add thermal adaptation for nominal/fair/serious/critical states, reducing optional GPU cost progressively while preserving game correctness.

Test long sessions and repeated pressure callbacks. Record jetsam-risk indicators where available.
```

## Prompt 25 — mobile launcher/UI polish

```text
[Master operating prompt]

Implement Stage 25 as a premium, restrained mobile launcher rather than an emulator dashboard.

Screens:
- first-run import
- Home/Play
- Controls
- Graphics/Performance
- Saves
- Diagnostics
- optional Mods later

Style:
- dark neutral graphite
- restrained blur
- clean white typography
- no excessive neon
- respect safe areas and landscape iPhone layouts
- do not redistribute copyrighted GTA artwork; use project-owned UI assets or locally imported user-owned content only where legally appropriate

Keep Play prominent and advanced settings secondary.
```

## Prompt 26 — crash reports and safe mode

```text
[Master operating prompt]

Implement Stage 26.

Capture enough state to diagnose crashes/blockers without collecting unnecessary personal data:
- project/upstream commit
- supported game revision ID
- device/iOS
- guest PC/LR/thread
- recent guest calls
- host stack when available
- last shader/pipeline/draw
- last streamed resource identifier where safe
- memory/thermal state

On next launch offer Normal, Safe Mode, and View/Export Report. Safe Mode disables mods, uses conservative graphics, and can invalidate optional caches.
```

## Prompt 27 — CI maturity and remote-development workflow

```text
[Master operating prompt]

Implement Stage 27 so development can continue from GitHub even when no local Mac is available.

Create/repair workflows for:
- script/unit tests
- PPC/ReXGlue regression tests
- macOS reference configure/build
- iOS shell/device compile validation
- formatting/static analysis
- prohibited-assets scan
- packaging smoke test

Make workflow logs concise and actionable. Upload only legal build/test artifacts. Do not upload GTA data or signing secrets.

Document how to inspect failed jobs, reproduce locally later, and what CI cannot validate without a physical iPhone.
```

## Prompt 28 — release-candidate stabilization

```text
[Master operating prompt]

Implement Stage 28. Freeze new features and drive the base GTA IV experience to release-candidate quality.

Priorities:
1. progression blockers
2. crashes/data corruption
3. save reliability
4. input
5. streaming/memory
6. audio
7. sustained performance/thermal behavior
8. visual correctness
9. UI polish

Maintain a release-blocker issue list and do not close an issue without test evidence.
```

## Prompt 29 — DLC/mods/achievements/multiplayer

```text
[Master operating prompt]

Only run this after the base game RC is stable.

Implement optional systems independently and make each disable-able:
1. TLAD
2. TBoGT
3. FusionFix-style mod overlay/import UX
4. local achievements, then optional Game Center bridge
5. existing multiplayer/P2P path validation

Do not let any optional subsystem become required for base-game startup.
```

## Prompt 30 — signed IPA build pipeline

```text
[Master operating prompt]

Implement Stage 30: a reproducible release/IPA pipeline.

Create scripts and documentation that:
- verify repo/upstream revisions
- validate the supported private game revision when a developer build needs it
- regenerate recompiled code only when required
- prepare legal shader/build metadata without committing game-derived proprietary payloads
- configure ios-release
- compile ARM64 Release
- create an Xcode archive
- support user-provided Apple signing/provisioning without ever committing certificates, passwords, profiles, or API keys
- export a .ipa
- emit build-info.json
- archive symbols privately for crash debugging

CI should perform an unsigned or ad-hoc packaging smoke test when possible. A truly installable signed IPA requires valid Apple signing/provisioning supplied by the developer.

Expected output structure:
dist/LibertyRecompiled.ipa
dist/build-info.json
dist/symbols/

Document exact commands from clean checkout to IPA. Run every non-signing test available and clearly state the final physical-device installation test.
```

## Prompt 31 — 1.0 final acceptance

```text
[Master operating prompt]

Perform the Stage 31 acceptance audit. Do not add features unless required to fix a release blocker.

Verify with evidence:
- native ARM64 path
- Metal renderer
- no runtime Xenia/Wine/x86 translation dependency
- exact supported GTA IV Xbox 360 revision documented
- legal first-run data import
- base-story compatibility target
- touch and physical controller support
- reliable saves
- audio/media
- iOS suspend/resume
- memory-pressure and thermal behavior
- safe mode/crash diagnostics
- reproducible release build
- signed IPA installed and launched on physical iPhone
- iPhone 11 performance report with typical/heavy/worst tested scenes

Produce RELEASE_CHECKLIST.md, KNOWN_ISSUES.md, PERFORMANCE.md, and final installation/build documentation. Mark 1.0 ready only if all blocking items have evidence or are explicitly accepted as non-blocking known issues.
```

---

# How to use these prompts

Run exactly one numbered prompt at a time. After each stage:
1. review the commit/diff
2. wait for CI
3. inspect failures
4. fix until green
5. update ROADMAP completion status
6. only then move to the next prompt

When a physical-device gate is reached, keep progressing only on work that can be validated without pretending the device test passed. The roadmap intentionally separates CI-verifiable work from real iPhone gameplay/performance validation.