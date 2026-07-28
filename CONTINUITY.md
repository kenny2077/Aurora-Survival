## 1. Project Architecture- Should not change unless explicitly requested.

The project must always stay aligned with this thesis:

> TrailGuard is a fully offline iOS incident assistant in which models interpret and explain reviewed evidence, while deterministic safety rules, signed content, citations, and release gates remain authoritative.

Do not narrow the project into a toy demo.

- Dataset: Versioned, signed local knowledge/model/map packs; development fixtures include 120 gold incidents, 30 map/asset cases, 12 safety cases, and reviewed starter/emergency-core JSON.
- Baselines: Essential extractive retrieval is the fail-closed baseline; Field text LLM and Vision Expert are optional on-device tiers behind package, entitlement, policy, and device gates.
- Metrics: Safety-rule recall and bypass behavior, evidence/citation validity, retrieval applicability, reproducible package hashes, latency/memory/thermal/battery gates, and locked incident/map matrices.
- Related Work: llama.cpp on-device inference, Qwen3-VL candidates, Apple Vision OCR, SQLite FTS5/vector retrieval, MapLibre-compatible offline maps, and read-only OBD.

Code Architecture:
- `App/`: SwiftUI application shell and Apple-platform adapters.
- `Core/`: deterministic safety, retrieval, routing, package, entitlement, map, OBD, and grounded-response runtime.
- `Resources/`: bundled emergency knowledge, development knowledge, and model catalog.
- `Tests/`: Swift/XCTest contracts and locked fixtures.
- `Schemas/`: independently versioned distribution and runtime JSON contracts.
- `tools/`: validation, reproducible pack building, fixture generation, and workstation model evaluation.
- `Docs/`: architecture, ADRs, safety case, implementation status, and external gates.
- `Reports/`: checked-in virtual and workstation evaluation evidence.

---

## 2. Progress--Update after every meaningful session

Milestones -- Three Facts only, no raw logs : compact if needed
- `agent/field-foundations` is synchronized at `6996cf6`; local changes restore Swift 6.3.3 compilation and add fail-closed active-pack retrieval/runtime composition at app startup.
- Structural validation passes with 48 Swift sources, 88 tests, 120 gold incidents, and 30 map/asset cases; SwiftPM, signed-pack reproducibility, and Python compilation all pass.
- Xcode 26.6 builds the resource-complete app; all 88 tests pass on an iPhone 17 Pro iOS 26.5 Simulator, and the installed app launches and renders its Ask screen.

Critical Bugs / Software or Hardware or Network Issues -- Three logs maximum, compact if needed

- GitHub draft PR #8 Actions cannot start because GitHub reports an account-level billing/spending-limit issue.
- Production package trust keys and the pinned llama.cpp XCFramework/backend are not present; startup deliberately exposes Essential only and rejects unknown packages.
- Physical-iPhone signing and memory, thermal, battery, camera, Bluetooth, map, accessibility, and interruption gates have not yet been executed.

Reflect on current working direction is not worth continuing or have better ideas ?

The architecture remains worth continuing. Verified compiled retrieval is now
app-integrated and fail-closed; the next meaningful risk reduction is a signed
physical-device run before adding the real llama.cpp backend.

---

## 3. Next Stage Implementation Plan--Update after every meaningful session

- Focus 1: Open the generated project, select a development team and attached iPhone, then run signing, launch, VoiceOver/Dynamic Type, interruption, and baseline memory/thermal/battery checks.
- Focus 2: Provision production Ed25519 trust keys and a signed development knowledge package, then exercise install, activation, recall, rollback, and cold offline launch on-device.
- Focus 3: Integrate a pinned llama.cpp XCFramework for Field text inference only after the physical-device Essential path is green; keep optional tiers disabled until their acceptance gates pass.

---

## 4. Important Files and Commands

Files:

- `Docs/ARCHITECTURE.md`: binding runtime sequence and product invariant.
- `VALIDATION_REPORT.md`: current local verification evidence and remaining limits.
- `App/AppModel.swift`: startup active-pack resolution and assistant reinjection.
- `Core/IncidentRuntimeBootstrap.swift`: verified compiled/bundled retrieval composition and runtime-tier intersection.
- `Core/RetrievalEngine.swift`: retrieval protocol, Essential baseline, and deterministic rank fusion.
- `Core/SQLiteHybridRetriever.swift`: compiled SQLite FTS/vector retrieval and fail-closed applicability filters.
- `Core/ActivePackRegistry.swift`: signature, policy, entitlement, recall, and device resolution.
- `Tests/SQLiteHybridRetrieverTests.swift`: direct compiled retrieval and bootstrap regressions.
- `project.yml`: XcodeGen app/test targets with explicit resource build phases.
- `Resources/Packages/trusted_package_keys.json`: intentionally empty development trust store.

Commands:

```bash
# inspect branch and local changes
rtk proxy git status --short --branch

# structural and reproducibility verification
/tmp/trailguard-dev-venv/bin/python tools/validate.py
/tmp/trailguard-dev-venv/bin/python tools/test_pack_reproducibility.py

# Swift package verification
rtk proxy swift test

# generate the Xcode project
rtk xcodegen generate

# unsigned generic iOS Simulator build
rtk proxy xcodebuild -project TrailGuard.xcodeproj -scheme TrailGuard \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TrailGuardDerivedData CODE_SIGNING_ALLOWED=NO build

# full installed-simulator suite
rtk proxy xcodebuild -project TrailGuard.xcodeproj -scheme TrailGuard \
  -destination 'platform=iOS Simulator,id=0E9D8B60-FEA9-4AD5-88C9-58D5FB31636E' \
  -derivedDataPath /tmp/TrailGuardSimulatorTests CODE_SIGNING_ALLOWED=NO test

# inspect PR #8 once GitHub Actions billing is restored
rtk proxy gh pr checks 8 --repo kenny2077/TrailGuard
```
