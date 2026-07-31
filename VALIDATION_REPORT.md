# Validation report

Date: 2026-07-30
Milestone: Production Field foundations and Lite workstation selection

## Passed here

- Dependency-free project validation
- JSON decoding for knowledge and model catalogs
- Unique article and source identifiers
- Required article steps, warnings, approval flag, and source metadata
- Exact Essential / Lite / Field / Vision Expert tier contract
- Vision memory and Low Power Mode gates
- Deterministic safety-before-model call order
- Required critical hazard rule presence
- Swift source delimiter and insecure-URL checks
- Archive integrity check
- Active package registry source and fail-closed fixtures
- Compiled SQLite FTS/vector pack generation and reproducibility
- Workstation Ollama structured-output smoke tests for Qwen3 4B and Gemma3 4B
- Workstation Qwen3 Embedding smoke test (1,024 dimensions)
- Persistent preparation-state source and round-trip fixtures
- Swift 6.3.3 package compilation and all 94 XCTest methods
- Xcode 26.6 unsigned iOS Simulator build with bundled app resources
- Full 94-test suite on both iPhone 17 Pro and iPad Pro 11-inch (M5) iOS 26.5
  Simulators
- Successful simulator installation, launch, initial SwiftUI render, and
  inspected iPad portrait/landscape layout
- Apple Development build, install, foreground launch, and live-process
  confirmation on a physical iPhone 13 and M2 iPad Pro
- Debug-only Ed25519 trust separation and real signed development knowledge-pack
  install, activation, rollback, recall, and tamper rejection
- Release-resource verification excluding the development package key
- Official llama.cpp `b9637` XCFramework resolution with checksum verification,
  deterministic C++/Swift text bridge compilation, app linking/embedding, and
  successful generic iOS Simulator plus arm64 iOS device builds
- Strict signature verification of the runtime-linked app and nested framework,
  followed by install, launch, and live-process confirmation on both physical
  devices
- Native llama.cpp `b9637` CUDA comparison of three immutable Lite artifacts
  under the production 2,048-token context, 256-token output cap, grounded JSON
  grammar, and deterministic greedy sampler
- MIT-licensed Phi-3.5 Mini Q4_K_M selection with exact artifact SHA-256,
  8/8 reviewed retrieval/procedure cases, 4/4 unsupported safety abstentions,
  2.002-second median cold first output, and 60.445 generated tokens/second
- Structural validation of the grammar-constrained bridge and 97-test inventory,
  reproducible pack verification, and an exact-artifact signed model-package
  builder exercised with an ephemeral development package

Validation result:

The structural gate now covers package security, vehicle applicability, maps,
OBD, runtime adapters, locked fixtures, CI presence, and test inventory. Run:

```text
python3 tools/validate.py
```

## Apple toolchain verification

The last completed Mac run contains ninety-four XCTest methods covering:

- fuel/fire and severe-bleeding model bypass;
- retrieval ranking, domain filtering, and unapproved-content exclusion;
- vision enablement and memory/thermal/power fallback;
- missing-tier fallback;
- valid, missing, and out-of-range citations;
- uncited-generation and model-exception fallback;
- knowledge serialization.
- package signature, expiry, path, size, hash, install, and rollback behavior;
- exact vehicle match and wrong-vehicle exclusion;
- offline map coverage, detail, freshness, and file readiness;
- OBD read policy, DTC/scalar parsing, and blocked writes;
- text/vision llama runtime image routing and lifecycle;
- twelve locked safety/refusal cases with zero model calls.
- launch-time package identity, policy, recall, entitlement, and device gates;
- preparation-state persistence and corrupt-state fallback.
- SQLite lexical/vector retrieval, applicability, deterministic rank fusion,
  corrupt vector bounds, and fail-closed runtime bootstrap.
- Lite eligibility, Field-to-Lite fallback, Low Power Mode and thermal fallback,
  package activation on iPhone 13-class memory, and conservative generation
  limits.

## Remaining environment limitations

The source is SwiftPM-, iPhone Simulator-, and iPad Simulator-verified. Signed
Essential builds launch on the physical iPhone 13 and M2 iPad Pro, and short
idle traces recorded nominal thermal state with 68.75–68.91 MiB and
19.27–19.84 MiB physical footprints respectively. These traces are baselines,
not sustained battery or thermal acceptance.

Three additional grounded prompt/validator tests bring the source inventory to
97, but Windows has no Swift/Apple toolchain; the Mac must compile and execute
all 97 after the grammar-bridge change.

No physical-device retrieval/citation, OCR/photo, airplane-mode cold launch,
accessibility, interruption, Bluetooth, map-rendering, or model-inference pass
is claimed. The licensed Lite artifact is selected but remains unbundled and
unsigned for iOS. Production trust, signed-package activation, Metal/unified
memory, latency, sustained thermal, and battery acceptance remain external
gates, so startup deliberately remains Essential-only.
