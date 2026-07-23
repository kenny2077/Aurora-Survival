# Validation report

Date: 2026-07-23  
Milestone: Offline iOS vertical slice

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

Validation result:

The structural gate now covers package security, vehicle applicability, maps,
OBD, runtime adapters, locked fixtures, CI presence, and test inventory. Run:

```text
python3 tools/validate.py
```

## Authored tests awaiting an Apple toolchain

Thirty-nine XCTest cases cover:

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

## Environment limitation

The build environment used for this milestone has no Swift compiler, Xcode,
iOS SDK, simulator, or physical iPhone. Therefore no compile, UI test, memory,
thermal, battery, or real Qwen inference result is claimed. Run `make project`
and the `TrailGuard` scheme on a Mac before treating the source as build-verified.
