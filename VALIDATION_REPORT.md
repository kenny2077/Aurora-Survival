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

```text
PASS: 8 articles, 8 sources, 3 model tiers, 19 Swift sources
```

## Authored tests awaiting an Apple toolchain

Fifteen XCTest cases cover:

- fuel/fire and severe-bleeding model bypass;
- retrieval ranking, domain filtering, and unapproved-content exclusion;
- vision enablement and memory/thermal/power fallback;
- missing-tier fallback;
- valid, missing, and out-of-range citations;
- uncited-generation and model-exception fallback;
- knowledge serialization.

## Environment limitation

The build environment used for this milestone has no Swift compiler, Xcode,
iOS SDK, simulator, or physical iPhone. Therefore no compile, UI test, memory,
thermal, battery, or real Qwen inference result is claimed. Run `make project`
and the `TrailGuard` scheme on a Mac before treating the source as build-verified.
