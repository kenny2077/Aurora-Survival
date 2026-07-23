# Virtual integration milestone

Date: 2026-07-23

## Outcome

Every implementation phase that can be completed without licensed third-party
assets, expert authority, App Store Connect configuration, or physical hardware
is connected to an executable code path.

## End-to-end paths

1. App startup loads and validates the bundled emergency core, installs it on
   first launch, and repairs a corrupt active copy.
2. A question/photo observation passes deterministic safety before retrieval.
3. Essential mode remains extractive. Llama/Qwen mode must return grounded JSON.
4. Grounded output resolves only retrieved evidence, approved procedure IDs,
   exact step IDs, and verbatim warnings. Failure falls back to Essential.
5. Package delivery is denied in incident mode. Preparation-mode transfer uses
   strict byte ranges, persistent partial files, hashes, signatures, atomic
   activation, rollback, and recall.
6. Verified StoreKit events persist locally. Refund or revocation removes
   offline access; no entitlement is invented without verification.
7. Vehicle manuals require exact document revision and vehicle applicability.
8. Offline map packs open only after file, coverage, detail, freshness, and
   routing checks.
9. OBD commands remain allowlisted and observations persist with adapter,
   vehicle, raw response, parsed codes, and sources.
10. The user can prepare and share/print a trip sheet for zero-power failure.

## Executable evidence

- 76 Swift tests;
- 120 incident cases executed through `IncidentAssistant`;
- 30 map/asset cases executed through `MapReadinessEvaluator`;
- 12 locked safety cases with zero model calls;
- 9 locked OBD write/clear rejections;
- deterministic emergency-core and evaluation fixture regeneration;
- byte-for-byte reproducible SQLite/FTS/vector signed pack builds;
- structural contract validation in Linux CI;
- Swift package and unsigned iOS simulator jobs on GitHub macOS runners.

## Hosted verification

GitHub Actions run
[`29996996730`](https://github.com/kenny2077/TrailGuard/actions/runs/29996996730)
passed all three jobs against commit
`79a1631625a4ab75b37a25b47596216171ee54bf`:

- `structural`: deterministic regeneration, repository validation, and
  reproducible signed-pack build;
- `swift-core`: all 11 bounded XCTest classes and 76 tests;
- `ios-build`: XcodeGen project generation and unsigned generic iOS Simulator
  build.

The machine-readable provenance record is
`Reports/virtual-integration-2026-07-23.json`.

## Deliberately external

No virtual test is represented as evidence for real Qwen performance, licensed
maps, expert first-aid or repair approval, BLE adapter isolation, App Store
transactions, or physical iPhone accessibility/thermal/battery behavior. Those
remain the open GitHub production gates.
