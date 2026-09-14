# GTA V iOS — Source Port vs Xbox 360 Static Recomp Decision

## Decision

There are two technically serious native-iOS routes. Which one is primary depends on whether the GTA V source tree is lawfully obtained and licensed for use.

### Route A — lawful complete source tree: preferred technical route

If we have a complete, lawfully obtained GTA V source tree and the right to modify/use it, the fastest native-iOS architecture is a direct ARM64 source port:

```text
GTA V source
  -> remove/replace Windows/console platform layer
  -> Apple Clang ARM64
  -> native iOS runtime
  -> direct Metal renderer
  -> iPhone 11/A13
```

Why this is technically best:

- no runtime CPU translation
- no PowerPC semantic emulation layer
- no big-endian guest-memory model unless the source itself requires one
- whole-program optimization by Apple Clang/LLVM
- direct access to RAGE systems for profiling and mobile-specific fixes
- easier symbolication and crash diagnosis
- highest ceiling for A13 optimization

The main cost is the platform port: Windows/Direct3D dependencies, middleware, file systems, threading, input, audio, launcher/DRM assumptions, and renderer backends must be replaced or isolated.

### Route B — public/legal clean-room route: Xbox 360 static recomp

If the source tree cannot legally be used, use `OZORDI/SanRecomp` + XenonRecomp as the primary public route:

```text
owned Xbox 360 default.xex
  -> XenonRecomp PowerPC -> C++ on build machine
  -> Apple Clang ARM64
  -> SanRecomp RAGE/runtime host
  -> Xenos resource/shader translation
  -> Metal
  -> iPhone 11/A13
```

This route is slower at the CPU/runtime-correctness level but has two major iPhone advantages:

- Xbox 360-era data/settings were designed for a 512 MB console memory system
- the public project already has PowerPC->C++, RAGE/runtime structures, installer/VFS work, and a Metal-capable renderer abstraction in progress

No shipping JIT is planned for either route.

## Do not use the PC binary + translation stack as the final architecture

A Windows x86-64 binary route such as x86-64 emulation/translation + Win32 compatibility + D3D translation may be useful only as a temporary experiment. It is not the target IPA architecture because it adds:

- CPU translation overhead
- JIT/executable-memory complications on iOS
- Win32 API compatibility work
- D3D -> intermediate API -> Metal translation overhead
- extra memory pressure
- harder frame pacing and thermal control
- harder debugging and App Store-style signing/distribution constraints

For a real native IPA, compile source or statically recompiled C++ to ARM64 ahead of time.

## PC-source vs Xbox-360-static-recomp comparison

| Category | Lawful PC/console source port | Xbox 360 static recomp |
|---|---|---|
| CPU efficiency ceiling | Best | Very good once correct |
| Time to ARM64 code | Fast if source builds cleanly | Recompiler already exists, but semantic fixes remain |
| Renderer work | D3D/console backend -> Metal | Xenos abstraction/shaders -> Metal |
| Memory pressure | PC content/config can be heavy | Much better baseline because 360 was memory constrained |
| Asset size | Heavier unless mobile profile is created | Better mobile starting point |
| Debuggability | Best | Good with guest-PC/runtime diagnostics |
| Legal/public collaboration | Only if rights permit | Best public clean-room route |
| iPhone 11 optimization access | Best | Good, but guest/runtime semantics constrain changes |
| Risk | middleware/platform dependencies | recompiler/runtime/render correctness |

## Recommended program

### If lawful source is available

1. Create a private `GTA5-iOS-source-port` workspace. Do not put proprietary Rockstar source into the public repo.
2. Build the source unchanged on its supported desktop target first.
3. Inventory platform boundaries: renderer, OS, threads, VFS, input, audio, networking, launcher/DRM, media, middleware.
4. Add an ARM64 Apple target that compiles engine/runtime code without rendering.
5. Bring up a minimal native iOS shell and enter RAGE initialization.
6. Replace graphics with a direct Metal backend. Avoid Vulkan/DXVK in the final build.
7. Create an A13 mobile configuration using Xbox-360-class visual targets: 30 FPS, dynamic 480p-720p internal resolution, low/medium shadows, conservative reflections/post FX, bounded streaming pools.
8. Reduce content residency and optional PC-era features before reducing simulation correctness.
9. Add touch/controller input, AVAudioSession, lifecycle, saves, importer/asset deployment.
10. Profile on iPhone 11 and tune CPU/GPU/memory/thermal independently.
11. Package/sign IPA only after physical-device certification.

### If source cannot legally be used

Continue with SanRecomp/XenonRecomp as the clean route and reuse the Apple-platform lessons from LibertyRecomp-iOS.

## A13 baseline rules

- iPhone 11 is the minimum certification target.
- 30 FPS target: 33.33 ms frame budget.
- Direct Metal only in the shipping build.
- Dynamic internal resolution, initially 480p-720p class for GTA V.
- Do not target native display resolution on A13.
- Xbox-360-class texture/LOD quality first.
- No MSAA by default unless required for correctness.
- Cache Metal pipeline states; do not create pipelines in gameplay hot paths.
- Async file I/O; no main-thread streaming reads.
- Bound texture, audio, shader, pipeline, and conversion caches by bytes.
- Release transient upload/decompression/untile buffers immediately when safe.
- Treat ~2 GB resident memory as an initial soft engineering target only; actual thresholds must come from physical-device measurements.
- Thermal degradation order: render scale -> shadows -> reflections -> post effects -> cache/worker trim.
- Never alter mission logic, physics tick rate, or script semantics to manage temperature.

## Why a 2017 MacBook Air can run GTA V while an iPhone still needs a port

Raw CPU/GPU capability is not the only variable. The Mac can run an existing x86-64 Windows build with a mature PC renderer, has more sustained cooling/power and typically more system memory. The iPhone must run an ARM64/Metal build, has 4 GB-class total memory on the iPhone 11, uses passive cooling, and iOS can terminate memory-heavy processes. A native port removes much of the architectural overhead, but it still has to be engineered for the phone's memory, graphics API, lifecycle, and thermal envelope.

## Current public evidence

- SanRecomp publicly targets GTA V Xbox 360 static recompilation with XenonRecomp and has Apple/Metal paths in its build/runtime.
- Current public reporting on the unofficial native Switch GTA V port shows ARM-native execution is feasible on 4 GB-class hardware, but that project is reported to rely on leaked Rockstar source and therefore is not a code source for this project.
- The useful lesson from that work is architectural: native ARM compilation plus aggressive memory/content/graphics tuning can outperform compatibility-layer approaches.

## Immediate next engineering step

Do not build two full implementations at once. First determine the legal/technical status of the available source tree:

- exact branch/version
- complete or partial
- desktop buildability
- renderer APIs present
- platform abstraction layout
- middleware dependencies
- whether its license/rights permit modification and use

If it is lawfully usable and complete, source-port architecture becomes GTA V Track A. SanRecomp remains Track B and a valuable behavioral/reference implementation. If not, Track B becomes primary.