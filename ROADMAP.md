# LibertyRecomp iOS — Zero-to-IPA Roadmap

This roadmap turns the existing LibertyRecomp static recompilation work into a native iPhone/iPad build. It is intentionally milestone-driven: do not skip ahead when a lower-level subsystem is still incorrect.

## Non-negotiable rules

1. Do not commit Rockstar game assets, `default.xex`, RPF archives, extracted game content, keys, or other proprietary payloads.
2. Use a legally owned Xbox 360 copy for private development/testing data.
3. Prefer fixing the first semantic/runtime divergence over adding title-specific hacks.
4. Every low-level bug fix must gain a regression test when practical.
5. Keep a macOS/desktop reference build as the behavior oracle for iOS-specific bugs.
6. iPhone 11 / A13 is the baseline performance target.
7. Initial gameplay target is 30 FPS, not 60 FPS.
8. Preserve GTA IV's original streaming/lifecycle model before attempting remaster-style enhancements.
9. All expensive work must be measurable: CPU time, GPU time, memory, I/O, thermal state, shader compilation, cache misses.
10. A milestone is complete only when its exit criteria pass in CI and, where required, on a physical device.

---

# Stage 0 — Project foundation and source freeze

### Goal
Create a controlled project with known source inputs, supported game revision metadata, CI, build documentation, and a reproducible branch strategy.

### Implement
- Link/reference `matthewcodergamer/LibertyRecomp` as the upstream source project.
- Decide whether this repository vendors a pinned LibertyRecomp snapshot, uses a git submodule, or carries an iOS-focused fork. Prefer a pinned submodule/fork over copying files manually.
- Add `docs/UPSTREAM.md` documenting the exact upstream commit used.
- Add `config/game_versions/gta4_x360_supported.json` with placeholders for supported revision metadata and hashes. Never include proprietary bytes.
- Add `scripts/verify-game.py` to validate expected filenames, directory structure, hashes, and free disk space when private game files are supplied.
- Add `.gitignore` entries for all local game payloads, build outputs, Xcode user state, signing material, derived data, and private caches.
- Add issue templates for CPU/runtime, renderer, iOS platform, performance, and compatibility bugs.

### CI
- Markdown/link lint where practical.
- Python/script unit tests.
- Verify no forbidden filenames/content patterns are accidentally committed.

### Exit criteria
- Repository initializes cleanly from a fresh clone.
- Private game-data directories are ignored.
- One exact LibertyRecomp upstream commit is pinned and documented.
- Supported game revision metadata format exists.

---

# Stage 1 — Import/pin LibertyRecomp and establish the desktop oracle

### Goal
Reuse the existing static recompilation runtime instead of rebuilding it.

### Implement
- Pull in the LibertyRecomp source at a known commit.
- Preserve ReXGlue integration, PowerPC-generated code flow, RAGE patches, VFS, audio, saves, input, shader tooling, and existing diagnostics.
- Build the unmodified reference target on macOS first.
- Add a script that prints the exact upstream commit, game-revision ID, compiler version, build type, and enabled backends.

### Tests
- Existing LibertyRecomp unit tests.
- ReXGlue instruction tests.
- Desktop/macOS build on CI.

### Exit criteria
- macOS reference build compiles from a clean checkout.
- Core test suites pass.
- Build metadata is embedded/logged.

---

# Stage 2 — iOS toolchain must compile before GTA starts

### Goal
Make iOS ARM64 a first-class build configuration.

### Implement
- Minimum iOS 16+.
- Architecture `arm64` only for device builds.
- Xcode generator and Apple Clang.
- `LIBERTY_RECOMP_TARGET_PLATFORM=ios`.
- Force Metal on, Vulkan/D3D off for iOS.
- Add compile-time options:
  - `LIBERTY_IOS_SHELL_ONLY`
  - `LIBERTY_IOS_CONTENT_MODE`
  - `LIBERTY_IOS_GAMECENTER`
  - `LIBERTY_IOS_DIAGNOSTICS`
- Eliminate/port desktop-only dependencies.
- Keep simulator support only for platform-shell testing; do not pretend it validates recompiled game execution/performance.

### CI
- Configure `ios-debug`.
- Compile unsigned simulator shell where possible.
- Compile unsigned device archive where CI allows.
- Fail on warnings promoted for iOS platform code.

### Exit criteria
- iOS target configures and links without requiring GTA data.
- No desktop-only symbol leakage.

---

# Stage 3 — Native iOS application shell

### Goal
Prove the Apple platform layer independently of GTA IV.

### Implement
- App lifecycle.
- SDL bootstrap if retained by upstream.
- Metal device, command queue, CAMetalLayer/SDL Metal surface, drawable acquisition, clear, present.
- `os_log` logging.
- AVAudioSession setup.
- GameController/SDL controller discovery.
- Documents/Application Support/Cache paths.
- Memory warning callbacks.
- Thermal-state callbacks.
- Foreground/background/inactive handling.
- Safe orientation policy (landscape-first).

### Diagnostic shell screen
Display:
- app version
- git commit
- device model
- iOS version
- Metal GPU name
- available logical CPU count
- thermal state
- content status

### Exit criteria
- Physical iPhone launches shell repeatedly without crash.
- Metal clear/present works.
- Background/foreground cycle works.
- Audio session survives route change.

---

# Stage 4 — Game content architecture

### Goal
Keep the IPA relatively small and keep proprietary game data outside the public repository.

### Implement
Create a `GameContentProvider` abstraction with at least:
- `EmbeddedContentProvider` for developer bring-up.
- `IOSImportedContentProvider` for normal device use.

Normal storage layout:

```text
Application Support/LibertyRecomp/
  Game/
  DLC/
  Cache/
    shaders/
    pipelines/
    converted_resources/
  Config/
Documents/LibertyRecomp/
  saves/
```

Requirements:
- Imported game data and rebuildable cache excluded from iCloud backup.
- Saves remain user-exportable.
- Atomic installation using a staging directory then rename.
- Validate required files before marking install complete.
- Storage-space preflight.
- Crash-safe resume/retry.

### Exit criteria
- App can select/import a legal extracted game folder.
- Invalid/incomplete folder is rejected with a useful reason.
- Interrupted import never produces a false valid install.

---

# Stage 5 — Supported-game fingerprinting and build linkage

### Goal
Prevent address-dependent patches from running against the wrong executable revision.

### Implement
- SHA-256 validation for the supported `default.xex` revision.
- Region/title-update/media metadata where useful.
- Human-readable compatibility errors.
- Build the static recompiled CPU code on the Mac/CI side, not on the phone.
- Separate recompiled executable code from large game-data import.

### Exit criteria
- Unsupported XEX is rejected.
- Supported revision maps to the correct recomp configuration.
- Build metadata identifies the game revision used.

---

# Stage 6 — PowerPC/static-recomp correctness gate

### Goal
Guarantee CPU semantics before debugging impossible gameplay behavior.

### Implement/test
- Integer arithmetic and carry/overflow.
- Rotate/mask operations.
- CR/XER semantics.
- Big-endian loads/stores.
- Floating-point rounding/conversion/NaN edge cases.
- VMX/Altivec permutations and saturation.
- Register aliasing cases where destination overlaps source.
- Atomics/memory ordering.
- Time-base behavior.

Add differential tests that compare generated instruction behavior with a trusted reference implementation over randomized inputs.

### Rule
When a gameplay system appears logically impossible, first determine whether a CPU semantic mismatch caused the data corruption.

### Exit criteria
- ReXGlue test suite passes on ARM64 host builds.
- Known aliasing/vector regressions remain covered.

---

# Stage 7 — Guest memory and endian correctness

### Goal
Provide predictable Xbox 360-style guest memory semantics on iOS ARM64.

### Implement
- Central `guest_to_host`, `host_to_guest`, `guest_read`, `guest_write` helpers or equivalent existing abstractions.
- Alignment validation.
- Page/region tracking.
- Physical/virtual allocation bookkeeping.
- Big-endian field helpers.
- Debug guard mode.
- Allocation lifetime diagnostics.

Debug fault report should include:
- guest PC/LR
- guest thread
- access address/size/type
- region metadata
- last guest call history

### Exit criteria
- Memory tests pass.
- Common invalid access classes produce useful diagnostics rather than opaque host crashes.

---

# Stage 8 — Xbox kernel/RAGE host services on iOS

### Goal
Validate the host services the recompiled game expects.

### Validate/implement
- threads
- mutexes/semaphores/events
- timers/sleep/yield
- time base
- async I/O
- file/directory operations
- VFS mounts
- locale/user profile
- save container
- controller enumeration
- networking stubs

Map guest thread roles to host priorities/QoS categories instead of blindly copying Xbox numeric priorities.

### Exit criteria
- Runtime survives initialization through host-service bring-up.
- No unimplemented kernel import blocks normal boot path.

---

# Stage 9 — Start recompiled GTA IV on iOS

### Goal
Reach the guest entry path and survive startup.

### Implement
- Guest entry bootstrap.
- Symbol/guest-PC logging.
- Recent-call ring buffer.
- Crash recovery metadata.
- Boot-step markers.

### Exit criteria
- App transitions from native shell into GTA runtime.
- First major runtime failure is reproducible and diagnosable.
- Each fixed blocker gains a regression test/diagnostic where practical.

---

# Stage 10 — Metal renderer: clear to first GTA draw

### Goal
Produce the first recognizable GTA IV GPU output through Metal.

### Bring-up order
1. Metal device/queue.
2. Drawable and render target.
3. Clear/present.
4. Static debug triangle.
5. GTA vertex/index buffer upload.
6. First translated shader.
7. First GTA draw call.
8. Depth/stencil.
9. Textures/samplers.
10. Blending.

### Add Metal debug labels
Name passes, resources, shaders, pipelines, and encoders for Xcode GPU capture.

### Exit criteria
- A GTA-generated draw command produces visible geometry on iPhone.

---

# Stage 11 — Xenos resource conversion

### Goal
Correctly map Xbox 360 GPU resources to Metal.

### Implement/validate
- texture tiling/untile
- endian conversion
- texture formats
- mip layouts
- vertex formats
- index buffers
- render targets
- depth/stencil formats
- resolves
- MSAA semantics as needed
- sRGB/gamma
- viewport/scissor
- samplers
- blending/alpha behavior
- resource lifetimes

Create small deterministic renderer/resource tests that do not require the full game whenever possible.

### Exit criteria
- Test patterns and representative GTA resources match expected output.
- Menus/logos no longer fail due to basic resource-format errors.

---

# Stage 12 — Shader pipeline and pipeline-state cache

### Goal
Avoid runtime shader stalls and achieve correct Xenos→Metal shader behavior.

### Implement
- Reuse RAGE FXC extraction/XenosRecomp pipeline.
- Convert to a Metal-consumable representation (MSL/AIR/metallib pipeline as appropriate to the upstream renderer).
- Preserve constant/register semantics.
- Cache shader artifacts by stable content hash + build version.
- Cache `MTLRenderPipelineState` using shader IDs plus render/depth formats, blend state, vertex layout, and sample count.
- Prewarm common pipelines during install/startup where data is known.

### Exit criteria
- Main menu shaders render correctly.
- Repeated boot does not recompile everything.
- No pathological frame-time shader compilation spikes in known scenes.

---

# Stage 13 — GTA IV streaming and VFS on iPhone storage

### Goal
Preserve Rockstar's residency system while adapting the host I/O path.

### Implement/validate
- RPF reads through existing VFS/device abstractions.
- Async host I/O.
- Read-ahead only where measurements show benefit.
- Avoid main-thread synchronous storage.
- Preserve request/loading/loaded lifecycle and dependencies.
- Release temporary untile/conversion buffers after Metal upload where safe.
- Instrument per-frame streaming bytes, outstanding requests, cache hit rate, residency, and stalls.

### Exit criteria
- Rapid movement through loaded sectors does not deadlock.
- Assets load/unload correctly.
- Memory does not grow without bound.

---

# Stage 14 — Physics/collision correctness

### Goal
Make world collision, vehicles, ragdolls, and contacts match expected behavior.

### Diagnostic sequence
Trace:
- sector request
- XBN/WBN load
- resource fixup
- static body creation
- insertion queue
- broadphase
- pair cache
- filtering
- narrowphase
- contact

Never mask a CPU/runtime bug with a gameplay-position hack.

### Test matrix
- standing/jumping
- stairs/slopes
- roads/sidewalks
- streamed sectors
- cars/walls/rollovers
- ragdolls
- bullets/explosions
- bridges/interiors

### Exit criteria
- Niko and vehicles reliably remain on world geometry across streaming boundaries.

---

# Stage 15 — Audio and media

### Goal
Deliver stable mobile audio and all required media paths.

### Implement
- Existing XMA decoding path.
- PCM buffering.
- SDL/CoreAudio bridge as appropriate.
- AVAudioSession interruptions and route changes.
- Bluetooth/headphone handling.
- Never perform blocking disk I/O inside realtime audio callback.
- Inspect video/media formats and use guest decoder when possible; provide host integration only where needed.

### Tests
- dialogue
- radio/music
- ambient audio
- engines
- weapons/explosions
- cutscenes
- phone audio
- background/foreground

### Exit criteria
- Long drive has no persistent crackle/starvation.
- Audio resumes after interruption.

---

# Stage 16 — Input abstraction and mobile touch controls

### Goal
Make touch and physical controllers feed the same Xbox input abstraction.

### Implement
- Physical: DualShock 4, DualSense, Xbox Wireless, MFi via SDL/GameController where available.
- Touch overlay with context-aware on-foot/vehicle layouts.
- Left virtual stick.
- Right-side drag camera region.
- ABXY, shoulders/triggers, D-pad, Start/Back, L3/R3.
- Touch editor: move, resize, hide, opacity, sensitivity, deadzone, reset.
- Separate on-foot/vehicle layouts.
- Auto-fade touch overlay when a physical controller is active.
- Haptics optional.

### Exit criteria
- Opening gameplay is fully controllable without a physical controller.
- Controller hot-plug does not duplicate or lock input.

---

# Stage 17 — Save/configuration and lifecycle safety

### Goal
Make GTA IV behave like a real iPhone game.

### Implement
- Atomic save writes with previous-save backup.
- Save import/export.
- Mobile-host settings separate from GTA's original settings.
- Background: pause guest simulation, input, audio, and unsafe GPU work.
- Foreground: reacquire drawable, audio session, controller, then resume.
- Handle lock screen, notifications, calls, route changes, controller disconnect.

### Exit criteria
- Save/load survives forced app termination scenarios.
- Repeated suspend/resume cycles do not crash or advance simulation incorrectly.

---

# Stage 18 — Complete opening sequence certification

### Goal
Cross from technology demo to playable port.

Certification path:
1. app launch
2. logos
3. GTA IV title
4. main menu
5. New Game
6. loading screen
7. opening sequence
8. first cutscenes
9. player control
10. first vehicle
11. city drive
12. destination/mission transition
13. save
14. quit
15. relaunch
16. load save
17. continue gameplay

### Exit criteria
All 17 steps pass on a physical iPhone 11.

---

# Stage 19 — Open-world compatibility sweep

### Goal
Exercise every major gameplay subsystem and every island.

### Test
- Broker/Dukes/Bohan/Algonquin/Alderney
- high-speed driving
- heavy traffic
- pedestrians
- police/wanted system
- weapons/explosions
- weather/day-night
- shops/safehouses
- phone
- interiors
- boats/helicopters/motorcycles
- mission scripting
- long play sessions

Maintain a compatibility database with PASS/PARTIAL/BLOCKED and build commit.

### Exit criteria
- No known progression blocker for the base story target.
- Major open-world systems are stable.

---

# Stage 20 — Instrumentation before optimization

### Goal
Make performance measurable.

### Overlay/capture metrics
- FPS/frame time
- game CPU
- render CPU
- GPU time
- physics
- streaming
- process resident memory
- guest memory
- texture/buffer memory
- conversion staging memory
- audio cache
- shader/pipeline cache
- dynamic resolution scale
- thermal state

### Exit criteria
- Any slow scene can be classified as CPU, GPU, I/O, memory, shader compilation, or thermal limited.

---

# Stage 21 — iPhone 11 / A13 CPU optimization

### Goal
Reduce host CPU overhead without changing game behavior.

### Profile/fix
- scalarized vector code that should use SIMD
- excessive byte swapping
- guest/host address translation hot paths
- lock contention
- allocation churn
- streaming decompression
- render-state translation overhead
- redundant work per draw/request

Use NEON/SIMD only behind correctness tests.

### Exit criteria
- CPU-limited benchmark scenes meet the 30 FPS frame budget where practical.

---

# Stage 22 — Metal/GPU optimization

### Goal
Reduce A13 GPU time and memory bandwidth.

### Optimize after correctness
- remove duplicate uploads/resources
- avoid unnecessary framebuffer copies/resolves
- use private GPU resources appropriately
- reuse staging buffers
- batch command work where safe
- pipeline-state cache
- reduce expensive overdraw/post-processing when necessary
- profile shadows/reflections
- test Metal heaps/argument buffers only if profiling proves value

### Exit criteria
- GPU-limited benchmark scenes improve without new rendering regressions.

---

# Stage 23 — Dynamic resolution and graphics presets

### Goal
Hold stable frame pacing instead of chasing peak resolution.

### Presets
- Performance
- Balanced
- Quality
- Custom

### Dynamic resolution
- Default target: 33.3 ms frame budget for 30 FPS.
- Adjust gradually using GPU/frame-time history.
- Set minimum/maximum render-scale bounds.
- Do not oscillate every frame.

Initial iPhone 11 range should prioritize Xbox-equivalent visuals and ~540p–720p-class internal rendering before adding enhancements.

### Exit criteria
- Heavy scenes reduce resolution gracefully rather than developing sustained stutter.

---

# Stage 24 — Memory-pressure and thermal control

### Goal
Prevent jetsam kills and long-session thermal collapse.

### Implement
`IOSMemoryBudgetController` tracking host/guest/GPU/cache/staging memory.

On memory pressure, progressively:
1. release unused Metal resources
2. trim streaming caches
3. trim decoded audio
4. trim optional caches
5. reduce optional/distant residency where compatible with game semantics

Thermal states:
- Nominal: normal preset
- Fair: lower dynamic-resolution ceiling slightly
- Serious: stronger GPU reductions
- Critical: minimum safe quality, protect stability

### Exit criteria
- Long sessions remain alive under realistic memory pressure.
- Performance degrades gracefully with thermal state instead of crashing.

---

# Stage 25 — Mobile launcher and diagnostics UX

### Goal
Make it feel like a purpose-built iOS port rather than an emulator frontend.

### Screens
- first-launch game import
- Library/Home with prominent Play button
- Controls/touch editor
- Graphics/performance
- Saves
- Diagnostics
- Mods (later)

### Style
- dark neutral graphite
- restrained blur
- clear white typography
- no excessive neon
- simple GTA IV-inspired monochrome feel without redistributing copyrighted art

### Diagnostics
- build commit
- game revision
- device/iOS
- renderer
- current preset
- last crash summary
- export diagnostic report

### Exit criteria
- A non-developer can install data, configure controls, start the game, and recover from a bad setting without Xcode.

---

# Stage 26 — Crash recovery and safe mode

### Goal
Turn crashes into actionable reports.

### Capture
- app/build commit
- game revision
- device/iOS
- guest PC/LR/thread
- host stack where available
- recent guest call history
- last shader/pipeline/draw
- last streamed asset
- memory/thermal state

Next launch offers:
- Start normally
- Start Safe Mode
- View/Export Diagnostic Report

Safe mode disables mods, uses conservative graphics, and can invalidate optional caches.

### Exit criteria
- Common crash classes generate a useful report and safe restart path.

---

# Stage 27 — Automated testing and GitHub Actions maturity

### Goal
Let development continue even when a local Mac is unavailable.

### Workflows
- Linux/unit tests
- macOS reference build
- iOS shell/build validation
- PowerPC instruction regression tests
- formatting/static analysis
- prohibited-assets guard
- packaging smoke test

CI may prove compilation and tests, but physical-device gameplay/performance still requires real iPhone testing.

### Exit criteria
- Every PR gets objective pass/fail gates.
- Failed Actions logs are sufficient to diagnose most build regressions remotely.

---

# Stage 28 — Base-game compatibility release candidate

### Goal
Ship a stable GTA IV base-game candidate before extras.

### Required
- story progression without known blocker
- stable save/load
- usable touch controls
- physical controller support
- audio/media complete enough for playthrough
- open-world streaming stable
- no known repeatable memory kill in normal play
- sustained performance profile characterized on iPhone 11

### Exit criteria
- RC checklist passes on at least one real iPhone 11 plus a newer reference device if available.

---

# Stage 29 — Optional DLC, mods, achievements, multiplayer

Do only after base-game stability.

Order:
1. TLAD
2. TBoGT
3. FusionFix-style mod overlay/import UX
4. local achievement tracking / optional Game Center bridge
5. existing multiplayer/P2P path validation

Each optional subsystem must be disable-able so it cannot block base-game boot.

---

# Stage 30 — IPA packaging and signing

### Goal
Produce a repeatable installable artifact.

### Build script responsibilities
1. verify source/upstream commit
2. verify supported private game revision for developer build
3. generate/update recompiled code when needed
4. prepare shader metadata/cache seed
5. configure `ios-release`
6. compile ARM64 Release
7. archive app
8. sign/export according to the developer's provisioning setup
9. create `.ipa`
10. emit build metadata and symbol archive

Suggested outputs:

```text
dist/
  LibertyRecompiled.ipa
  build-info.json
  symbols/
```

`build-info.json` should include commit, upstream commit, supported game revision ID, iOS minimum, architecture, build configuration, and feature flags.

### Exit criteria
- Fresh checkout + documented prerequisites can reproduce the same release build process.
- IPA installs on the intended test device after valid signing/provisioning.
- Game data is imported separately unless developer embedded-content mode is explicitly used.

---

# Stage 31 — 1.0 acceptance gate

`1.0` means all of the following are true:
- native ARM64 execution; no Xenia/Wine/x86 translation requirement
- Metal renderer
- supported GTA IV Xbox 360 revision clearly documented
- first-run content validation/import
- base story compatibility target achieved
- touch + physical controllers
- reliable saves
- audio and critical media paths
- suspend/resume
- memory/thermal handling
- crash diagnostics/safe mode
- reproducible release build
- signed IPA install tested
- iPhone 11 performance documented with realistic minimum/typical/worst-case observations

## Definition of done
The project is complete when a cleanly built, correctly signed IPA can be installed on an iPhone, the user can import files from their legally owned supported Xbox 360 copy, start GTA IV, complete the base-game compatibility target with stable controls/audio/saves/streaming, and the application remains usable across normal iOS lifecycle, memory, and thermal conditions.