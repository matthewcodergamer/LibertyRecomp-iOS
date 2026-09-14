# Native iOS Program Plan — GTA IV + GTA V

This document defines the shipping architecture and zero-to-playable plan for native iOS builds based on the Xbox 360 versions of Grand Theft Auto IV and Grand Theft Auto V.

The baseline device is **iPhone 11 / Apple A13**. Later iPhones should benefit from the same architecture with higher render scale, larger caches, and more thermal headroom.

## 1. Architecture decision

### Shipping architecture

**Do not ship a runtime PowerPC JIT.**

The final IPA architecture is:

```text
owned Xbox 360 executable
        |
        | developer/build machine only
        v
static PowerPC -> C++ recompilation
        |
        v
Apple Clang ARM64
        |
        v
native ARM64 game/runtime code
        |
        +---- RAGE/platform host services
        +---- VFS / audio / saves / input
        +---- Xenos resource + shader translation
        v
Metal
        |
        v
iPhone 11 / A13
```

For GTA IV, the source/reference project is LibertyRecomp and the static recompilation path is ReXGlue-based.

For GTA V, the clean public reference is SanRecomp, which targets the Xbox 360 release and uses XenonRecomp for PowerPC -> C++ recompilation. GTA V should become a separate `SanRecomp-iOS` project rather than mixing both games into one runtime repository.

### Why no shipping JIT

A JIT adds runtime translation overhead, executable-memory complexity, platform restrictions, larger failure surface, more RAM pressure, and unpredictable frame-time spikes. Static recompilation gives the compiler the whole program ahead of time and produces normal ARM64 code that can be optimized, linked, profiled, symbolicated, and packaged like a native iOS application.

A JIT or emulator may still be useful **only as a development reference** on a Mac when comparing behavior, but it is not part of the IPA architecture.

### What Git is for

Git/GitHub is the source-control and CI layer, not the game execution layer. The development model is:

```text
main
  stable integration state

feature/stage-N-name
  one coherent milestone

GitHub Actions
  portable tests
  macOS compile/tests
  unsigned iOS ARM64 compile
  artifact validation

physical device gate
  signed install
  launch
  Metal correctness
  performance / memory / thermal
```

Never put proprietary game data in Git history.

## 2. Two-project strategy

### Project A — LibertyRecomp-iOS / GTA IV

Repository: `matthewcodergamer/LibertyRecomp-iOS`

Reference source: `matthewcodergamer/LibertyRecomp`

Goals:

- native ARM64 executable
- Metal renderer
- user-imported legally owned Xbox 360 game data
- touch + physical controllers
- saves, audio, lifecycle, diagnostics
- iPhone 11 / A13 30 FPS target
- final signed IPA

This is the first production target because LibertyRecomp is already further along than the GTA V static-recomp project.

### Project B — SanRecomp-iOS / GTA V

Future repository: `matthewcodergamer/SanRecomp-iOS`

Reference source: `OZORDI/SanRecomp`

Goals:

- Xbox 360 GTA V static recompilation
- native ARM64 application
- shared Apple platform concepts from the GTA IV project
- Metal renderer and Xenos resource translation
- iPhone 11 / A13 baseline
- touch/controller support
- final signed IPA

Do **not** base this project on leaked GTA V source code, leaked mobile ports, redistributed Android game payloads, or unofficial binaries. Public reports of unofficial Android/Switch work may be useful as broad feasibility evidence only; no code, assets, or proprietary source from those projects should enter this repository.

## 3. Shared Apple platform layer

Do not prematurely create a third repository. First stabilize these interfaces inside LibertyRecomp-iOS, then extract only code that is actually reusable.

Candidate shared modules:

```text
ApplePlatform/
  Lifecycle
  AppPaths
  Logging
  Diagnostics
  MemoryPressure
  ThermalState
  AudioSession
  ControllerDiscovery
  TouchOverlay
  FilesImporter
  SaveExport

MetalHost/
  Device
  Queue
  FrameContext
  ResourceUpload
  PipelineCache
  ShaderCache
  TexturePool
  BufferPool
  DynamicResolution
  GPUCounters
```

Game-specific RAGE, patches, guest addresses, executable fingerprints, shader semantics, and resource rules remain in their own project.

## 4. GTA IV zero-to-complete path

### Phase IV-0 — Foundation

Already underway.

- pin exact LibertyRecomp revision
- CI
- prohibited-asset guard
- game version schema
- private-content verifier
- macOS reference path
- unsigned iOS shell compile

Gate: all public CI green without GTA data.

### Phase IV-1 — Reference build and reproducibility

- fetch exact pinned LibertyRecomp commit
- preserve upstream ReXGlue/RAGE/VFS/audio/save/input/shader code
- build the macOS reference configuration
- record compiler, commit, executable revision, and renderer backend
- establish a deterministic supported Xbox 360 executable fingerprint

Gate: a known private game revision boots in the reference project and the exact SHA-256 is recorded locally and then added to the public compatibility manifest as metadata only.

### Phase IV-2 — iOS ARM64 platform target

- make iOS ARM64 a first-class target
- iOS 16+ device deployment target
- Apple Clang
- no x86 translation
- Metal only for graphics
- no Vulkan or D3D backend in the shipping iOS target
- shell-only mode independent of GTA data
- compile-time feature toggles

Gate: clean CI produces a linked unsigned ARM64 `.app` without proprietary payloads.

### Phase IV-3 — Native application shell

- UIKit/scene lifecycle
- Metal device/queue/drawable
- clear/present
- AVAudioSession
- GameController discovery
- file paths
- memory warnings
- thermal-state notifications
- foreground/background transitions
- diagnostics screen

Gate on physical iPhone: 50 repeated cold launches and suspend/resume cycles without crash.

### Phase IV-4 — Content import

- use iOS Files picker
- validate selected extracted Xbox 360 game folder
- require known executable revision
- storage preflight
- `Game.staging` import
- validate completed staging tree
- atomic promote to `Game`
- mark game/cache data as excluded from iCloud backup
- keep saves exportable
- resumable/retryable failure flow

Gate: interrupted import can never be mistaken for a valid installation.

### Phase IV-5 — Static game linkage

- run ReXGlue on the supported private executable on a build machine
- compile generated C++ as ARM64
- link the recompiled executable code into the iOS app
- keep large game data external to the IPA
- embed build metadata linking app commit to supported game revision

Gate: the native app enters the recompiled guest entry path.

### Phase IV-6 — CPU semantic correctness

Before gameplay debugging, prove:

- integer carry/overflow
- rotates/masks
- CR/XER behavior
- endian loads/stores
- floating-point conversions/rounding/NaNs
- VMX permutations and saturation
- destination/source register aliasing
- atomics
- memory ordering
- timebase

Gate: ReXGlue regression tests pass on ARM64 and known vector aliasing bugs remain covered.

### Phase IV-7 — Guest memory + kernel/RAGE host services

- guest address translation
- alignment checks
- allocation bookkeeping
- endian helpers
- crash diagnostics
- threads/events/mutexes/timers
- VFS
- async file I/O
- user/save containers
- input enumeration
- network stubs where required

Gate: runtime initializes without unknown kernel/platform blockers.

### Phase IV-8 — Metal renderer

Bring-up order:

1. clear/present
2. debug geometry
3. GTA vertex/index upload
4. first translated shader
5. first GTA draw
6. depth/stencil
7. textures/samplers
8. blending
9. render targets/resolves
10. post-processing

Do not port an entire emulator GPU. Translate the game/runtime's Xenos-facing abstractions into Metal using the existing static-recomp renderer architecture.

Gate: a GTA-generated draw produces recognizable geometry.

### Phase IV-9 — Shader + resource correctness

- Xenos texture formats
- tiling/untile
- endian conversion
- mips
- vertex formats
- index formats
- depth/stencil
- resolve semantics
- blend/alpha
- gamma/sRGB
- viewport/scissor
- sampler behavior
- Xenos shader -> Metal-consumable representation
- stable shader cache
- Metal pipeline-state cache

Gate: logos/menu render without basic shader/resource corruption.

### Phase IV-10 — Streaming/VFS

Preserve GTA IV's original residency system instead of replacing it.

- asynchronous RPF reads
- bounded staging buffers
- no main-thread storage I/O
- resource dependency order
- timely release of conversion/upload scratch memory
- per-frame streaming diagnostics

Gate: long fast drives through the city do not deadlock and resident memory stops growing after warm-up.

### Phase IV-11 — Physics/collision

Debug from first divergence:

```text
sector request
 -> collision archive load
 -> fixups
 -> body creation
 -> broadphase insertion
 -> pair generation
 -> narrowphase
 -> contact
```

Never hide a CPU/runtime bug by moving the player upward or disabling collision.

Gate: character and vehicles remain on streamed world geometry.

### Phase IV-12 — Audio/media

- reuse existing XMA path
- bounded audio buffers
- no blocking I/O in real-time callback
- interruption/route handling through AVAudioSession
- dialogue/radio/engines/weapons/cutscene validation

Gate: 30-minute drive with stable audio and successful interruption recovery.

### Phase IV-13 — Input and mobile controls

One Xbox input abstraction, two input sources:

- physical controller
- touch overlay

Touch requirements:

- left stick
- right camera region
- ABXY
- triggers/bumpers
- D-pad
- Start/Back
- L3/R3
- on-foot and vehicle layouts
- size/position/opacity/deadzone/sensitivity editor
- auto-fade when controller is active

Gate: opening gameplay is completable without a physical controller.

### Phase IV-14 — Save/lifecycle safety

- atomic save writes
- previous-save backup
- save import/export
- background pause
- safe Metal quiesce
- audio interruption
- drawable reacquisition
- controller rebind

Gate: repeated suspend/resume and forced-exit tests do not corrupt saves.

### Phase IV-15 — Gameplay certification

Minimum path:

launch -> logos -> title -> menu -> New Game -> opening -> player control -> first vehicle -> city drive -> mission transition -> save -> relaunch -> load -> continue.

Gate: full sequence passes on iPhone 11.

### Phase IV-16 — Open-world compatibility

- every island
- fast driving
- traffic/peds
- wanted system
- weapons/explosions
- weather/day-night
- interiors
- boats/helicopters/motorcycles
- mission scripting
- long sessions

Gate: no known base-story progression blocker.

### Phase IV-17 — iPhone 11 optimization

Only optimize measured bottlenecks.

CPU:

- reduce host abstraction overhead
- eliminate avoidable copies and allocations
- replace spin waits with appropriate synchronization
- batch high-frequency API calls
- use QoS rather than attempting hard core pinning
- keep game/render critical work latency-focused
- keep streaming/background work off the critical path

GPU:

- Metal-native render passes
- pipeline caching
- texture/buffer pools
- reduce redundant state transitions
- merge compatible passes
- reduce transient render-target bandwidth
- use original Xbox 360 assets first
- dynamic resolution
- reduced shadows/reflection cost under pressure

Memory:

- per-category accounting
- bounded shader/pipeline/resource caches
- aggressively release upload/untile scratch buffers
- memory-pressure trims
- no duplicate full game trees

Thermal:

- 30 FPS cap
- dynamic resolution first
- then shadow/reflection/post-effect reductions
- emergency cache trim
- never allow thermal adaptation to change mission logic

Gate: sustained 30-minute session on iPhone 11 without jetsam and with acceptable thermal behavior.

### Phase IV-18 — IPA release pipeline

CI can produce unsigned compile artifacts. A final installable IPA requires Apple signing.

Release flow:

```text
clean checkout
 -> fetch exact upstream pin
 -> verify supported game revision metadata
 -> generate/reuse static recompiled code
 -> build shader artifacts
 -> Xcode Release archive
 -> sign/provision
 -> export IPA
 -> install on physical device
 -> run certification suite
```

Never store signing certificates or provisioning profiles in the public repository.

## 5. GTA V zero-to-complete path

GTA V starts only after the GTA IV Apple platform and Metal lessons are stable enough to reuse.

### Phase V-0 — Separate project bootstrap

Create `SanRecomp-iOS` and pin `OZORDI/SanRecomp` to an exact commit.

- no copied source snapshot
- no leaked GTA V source
- no Android-port binaries
- no game assets
- same prohibited-asset CI policy
- same private executable fingerprint model

Gate: clean public repository with reproducible upstream pin.

### Phase V-1 — Desktop oracle

- build SanRecomp reference target first
- run XenonRecomp-generated code on desktop/macOS
- preserve all existing RAGE/recompiler work
- record first failing subsystem

Gate: known reference build and diagnostics.

### Phase V-2 — Reuse Apple platform shell

Port only proven reusable pieces from LibertyRecomp-iOS:

- lifecycle
- file importer
- paths
- audio session
- controller/touch layer
- diagnostics
- memory pressure
- thermal controller
- Metal frame host

Do not copy GTA IV-specific patches or guest addresses.

Gate: GTA V iOS shell builds unsigned on CI.

### Phase V-3 — Static ARM64 linkage

- XenonRecomp PPC -> C++ on build machine
- compile generated code with Apple Clang
- link native ARM64
- no runtime JIT

Gate: enter GTA V guest/runtime bootstrap.

### Phase V-4 — RAGE host services

- threads/synchronization
- VFS
- file I/O
- save/profile
- timers
- controller
- audio
- memory

Gate: initialization proceeds to renderer startup.

### Phase V-5 — Xenos -> Metal

GTA V will need its own renderer correctness work even if the Metal host is shared.

- resource formats
- shader translation
- render targets
- depth/stencil
- blending
- post-processing
- shadow maps
- resolves
- pipeline caching

Gate: first GTA V-generated geometry.

### Phase V-6 — Streaming

GTA V has more content pressure than GTA IV, so the iPhone 11 plan must be strict:

- original Xbox 360 assets only
- asynchronous reads
- bounded residency
- bounded conversion buffers
- no duplicate texture copies after upload
- aggressive cache eviction under memory pressure
- persistent pipeline/shader cache on disk

Gate: prologue and first open-world transition without unbounded memory growth.

### Phase V-7 — Gameplay systems

- physics
- animation
- AI
- script VM
- cutscenes
- vehicles
- weapons
- audio
- saves

First-divergence debugging remains mandatory.

Gate: complete prologue and enter open world.

### Phase V-8 — iPhone 11 performance mode

The iPhone 11 target is **playable 30 FPS**, not visual parity with modern console/PC editions.

Initial assumptions:

- Xbox 360 content set
- 30 FPS cap
- dynamic internal resolution
- conservative shadows/reflections
- bounded population only if profiling proves necessary and only through safe, game-supported controls
- no high-resolution texture packs
- no PC-only effects
- precompiled/cached pipelines where practical

Gate: sustained playable open-world drive on iPhone 11 without memory termination.

### Phase V-9 — Full-story certification + IPA

- mission compatibility database
- long-session soak tests
- save/reload
- background/foreground
- controller/touch
- thermal tests
- signed Release archive
- IPA install

Gate: base story has no known progression blocker and the IPA is reproducibly buildable.

## 6. iPhone 11 is the baseline, not the ceiling

Do not design the project around the newest iPhone and then attempt to scale down later.

Every major subsystem must have an A13 baseline mode first:

- render scale
- shadow quality
- reflection frequency
- post-processing quality
- cache sizes
- staging-buffer limits
- streaming concurrency
- thermal response

Newer iPhones can raise those limits after the baseline works.

## 7. Definition of playable

A build is not called playable because it reaches a menu.

For this program, playable means:

- native ARM64 executable
- no shipping JIT or x86 translation
- Metal rendering
- stable input
- stable audio
- safe saves
- game-data import
- repeatable launch
- open-world traversal
- mission progression
- bounded memory
- background/foreground safety
- acceptable sustained thermal behavior
- physical iPhone 11 validation

## 8. Hard rules

1. Never commit or redistribute Rockstar game assets or executable payloads.
2. Never use leaked GTA V source code as an implementation base.
3. Never make the shipping architecture depend on Xenia, Wine, Box64, Winlator, or runtime x86/PPC translation.
4. Never call a system fixed until the actual test/CI/device gate passes.
5. Never optimize before measuring.
6. Never hide a guest/runtime semantic failure with gameplay hacks.
7. Keep GTA IV and GTA V game-specific code separated.
8. Reuse the Apple platform layer only where the interface is proven common.
9. iPhone 11 remains the release baseline until explicitly changed.
10. 30 FPS is the initial performance contract; 60 FPS is a later-device enhancement, not a baseline requirement.
