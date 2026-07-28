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

Validation result:

The structural gate now covers package security, vehicle applicability, maps,
OBD, runtime adapters, locked fixtures, CI presence, and test inventory. Run:

```text
python3 tools/validate.py
```

## Authored tests awaiting an Apple toolchain

Eighty-two XCTest methods now cover:

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

## Environment limitation

This Windows environment has no Swift compiler, Xcode, iOS SDK, simulator, or
physical iPhone. The Python validation, reproducible package build, and local
Ollama model/embedding smoke tests passed, but no iOS compile, UI test, Metal
inference, memory, thermal, battery, or physical-device result is claimed.
Run `make project`, `swift test`, and the `TrailGuard` scheme on a Mac before
treating the source as iOS build-verified.
