# Validation report

Date: 2026-07-28
Milestone: Production Field foundations on the local workstation

## Passed here

- Dependency-free project validation
- JSON decoding for knowledge and model catalogs
- Unique article and source identifiers
- Required article steps, warnings, approval flag, and source metadata
- Exact Essential / Field / Vision Expert tier contract
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
- Swift 6.3.3 package compilation and all 88 XCTest methods
- Xcode 26.6 unsigned iOS Simulator build with bundled app resources
- Full 88-test suite on an iPhone 17 Pro iOS 26.5 Simulator
- Successful simulator installation, launch, and initial SwiftUI render

Validation result:

The structural gate now covers package security, vehicle applicability, maps,
OBD, runtime adapters, locked fixtures, CI presence, and test inventory. Run:

```text
python3 tools/validate.py
```

## Apple toolchain verification

Eighty-eight XCTest methods now cover:

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

## Remaining environment limitations

The source is SwiftPM- and iOS Simulator-build verified, but no physical-iPhone
Metal inference, memory, thermal, battery, camera, Bluetooth, map-rendering,
VoiceOver, or interruption result is claimed. Production package trust keys,
licensed assets, and a pinned llama.cpp XCFramework also remain external gates.
