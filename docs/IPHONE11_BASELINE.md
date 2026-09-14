# iPhone 11 / A13 Baseline

The iPhone 11 is the minimum performance target for both native static-recomp projects.

This document defines initial engineering budgets. They are targets for measurement and tuning, not claims that a finished port already reaches them.

## Core target

- Device baseline: iPhone 11 / A13
- Architecture: ARM64
- Graphics API: Metal
- Minimum iOS target: iOS 16+
- Primary frame-rate target: 30 FPS
- Frame budget: 33.33 ms
- Long-session target: at least 30 minutes without memory termination or unrecoverable thermal degradation

## Render-scale strategy

Do not render the game at the iPhone panel's full native resolution by default.

### GTA IV initial range

- nominal internal target: roughly 960x540 to 1280x720
- dynamic-resolution controller tracks GPU frame time
- lower temporary floor is allowed during heavy scenes if needed to preserve frame pacing

### GTA V initial range

- nominal internal target: roughly 854x480 to 1280x720
- expected typical range should be established by profiling, not guessed in advance
- prioritize stable frame pacing over short benchmark peaks

Upscaling to the display is a presentation step. A later project stage may evaluate higher-quality spatial/temporal upscaling if it is cheaper than rendering more native pixels.

## Frame-budget policy

At 30 FPS:

```text
Total budget                 33.33 ms
CPU and GPU may overlap.
```

The profiler must separately report:

- game thread
- render submission
- physics
- scripts/AI
- streaming
- audio
- GPU frame time
- drawable wait
- shader/pipeline creation

No optimization decision should be based on FPS alone.

## CPU policy

The A13 has heterogeneous cores. Do not attempt unsupported hard affinity assumptions.

Use host scheduling/QoS intentionally:

- critical game/render work: latency-sensitive
- streaming/decompression/resource conversion: bounded worker pool
- audio: realtime-safe path, no blocking I/O
- diagnostics/cache maintenance: background/utility

Rules:

- avoid spin-wait loops
- avoid per-frame heap churn
- batch repetitive host calls
- remove redundant endian/conversion work from hot paths
- cache immutable translations
- do not create more workers than measured workloads justify

## GPU policy

Metal is the only shipping graphics API.

Priorities:

1. stable frame pacing
2. correct rendering
3. bandwidth reduction
4. pipeline reuse
5. resolution/quality scaling

Use:

- cached `MTLRenderPipelineState` objects
- bounded texture/buffer pools
- private GPU resources where appropriate
- short-lived staging buffers
- render-pass reuse where correctness permits
- Metal debug labels and GPU captures during development

Avoid:

- runtime shader compilation inside normal gameplay when artifacts can be prepared or cached
- keeping CPU and GPU copies of large resources after the CPU copy is no longer needed
- recreating pipelines every frame
- full-resolution transient effects without evidence they fit the budget

## Quality ladder

### Performance baseline

- 30 FPS cap
- aggressive dynamic resolution
- Xbox 360 textures/assets/LOD first
- conservative shadows
- conservative reflections
- reduced expensive post-processing
- no MSAA unless a specific pass requires it for correctness

### Balanced

For later devices or scenes with headroom:

- higher dynamic-resolution target
- improved shadow resolution/distance
- improved reflection frequency
- selected post effects restored

### Quality

Not an iPhone 11 certification requirement.

## Memory policy

The exact safe process limit varies with iOS/device state, so do not code against a guessed jetsam number.

Instead maintain explicit categories:

```text
recompiled code/runtime
RAGE guest memory
textures
GPU buffers
render targets
audio
streaming residency
resource-conversion scratch
shader cache
pipeline cache
UI/host platform
```

Initial engineering policy:

- aim for a normal-play working set comfortably below the point where iOS memory pressure begins
- start with a conservative soft target near 2 GB resident memory and adjust only from physical-device measurements
- trim rebuildable caches immediately on memory warning
- bound every cache by bytes, not only entry count
- release conversion/upload scratch memory as soon as the GPU no longer needs it
- never keep duplicate extracted game installations
- do not load the whole world into RAM

The Xbox 360 versions are chosen partly because their original content/streaming systems were designed around far smaller console memory budgets. Preserve that streaming discipline.

## Streaming policy

- async I/O
- no main-thread file reads
- limited request concurrency
- predictable staging-ring budget
- prioritize imminent gameplay assets
- release temporary untile/decompression buffers promptly
- instrument bytes read, queue depth, request latency, cache hit rate, and residency

If streaming causes hitching, determine whether the cause is storage latency, decompression, fixups, upload bandwidth, or missing residency—not simply "make the cache bigger."

## Thermal controller

Thermal adaptation order:

1. reduce dynamic render scale
2. reduce shadow cost
3. reduce reflection/update cost
4. reduce optional post-processing
5. trim nonessential caches/workers

Do not change simulation speed, mission logic, physics tick semantics, or script timing to manage temperature.

Track:

- nominal
- fair
- serious
- critical

A serious/critical event must be logged with frame time and memory state so the threshold can be tuned from real device data.

## GTA IV baseline acceptance

A candidate iPhone 11 build is acceptable only when it can:

- launch reliably
- reach gameplay
- drive through streamed city sectors
- maintain usable 30 FPS-class frame pacing in representative scenes
- survive 30 minutes without memory termination
- survive background/foreground transitions
- save, quit, relaunch, and load

## GTA V baseline acceptance

GTA V has a stricter content-pressure problem. Initial certification is:

- complete prologue
- enter open world
- drive continuously through multiple streamed areas
- stable controls/audio
- no unbounded memory growth
- no persistent shader-compilation stalls after warm-up
- no memory termination in a 30-minute run
- 30 FPS target with dynamic resolution and Xbox 360-class assets/settings

If iPhone 11 cannot meet a gate, profile the first limiting subsystem. Do not immediately abandon the device target or switch to a translation/emulation stack.

## Newer iPhones

Newer devices inherit the same native ARM64/Metal path. They can scale upward through data-driven presets:

- higher render scale
- larger caches
- better shadows
- more reflections
- more post-processing
- optional higher frame-rate targets

The codebase should not require separate game ports for each iPhone generation.
