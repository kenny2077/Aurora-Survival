## 1. Project Architecture- Should not change unless explicitly requested.

The project must always stay aligned with this thesis:

> Aurora is a fully offline iOS incident assistant in which models interpret and explain reviewed evidence, while deterministic safety rules, signed content, citations, and release gates remain authoritative.

Do not narrow the project into a toy demo.

- Dataset: Versioned, signed local knowledge/model/map packs; development fixtures include 120 gold incidents, 30 map/asset cases, 12 safety cases, and reviewed starter/emergency-core JSON.
- Baselines: Essential extractive retrieval is the fail-closed baseline; Lite and Field text LLMs plus Vision Expert are optional on-device tiers behind package, entitlement, policy, and device gates.
- Metrics: Safety-rule recall and bypass behavior, evidence/citation validity, retrieval applicability, reproducible package hashes, latency/memory/thermal/battery gates, and locked incident/map matrices.
- Related Work: llama.cpp on-device inference, Qwen3-VL candidates, Apple Vision OCR, SQLite FTS5/vector retrieval, MapLibre-compatible offline maps, and read-only OBD.

Code Architecture:
- `App/`: SwiftUI application shell and Apple-platform adapters.
- `Core/`: deterministic safety, retrieval, routing, package, entitlement, map, OBD, and grounded-response runtime.
- `Resources/`: bundled emergency knowledge, development knowledge, and model catalog.
- `Tests/`: Swift/XCTest contracts and locked fixtures.
- `Schemas/`: independently versioned distribution and runtime JSON contracts.
- `tools/`: validation, reproducible pack building, fixture generation, and workstation model evaluation.
- `Runtime/`: checksum-pinned optional native inference packages and bridges.
- `Docs/`: architecture, ADRs, safety case, implementation status, and external gates.
- `Reports/`: checked-in virtual and workstation evaluation evidence.

---

## 2. Progress--Update after every meaningful session

Milestones -- Three Facts only, no raw logs : compact if needed
- `agent/field-foundations` is pushed at `9e1975a`; the universal target passes all 94 tests on both iPhone and iPad simulators and has inspected portrait/landscape iPad rendering.
- Apple Development signing is provisioned, and the universal runtime-linked app plus nested framework verify, install, launch, and remain alive on the physical iPhone 13 (`iPhone14,5`) and M2 iPad Pro (`iPad14,3`).
- Debug-only signed-pack lifecycle and Release trust exclusion are green; Lite is explicit, and official llama.cpp `b9637` is checksum-pinned with a deterministic text bridge that builds for simulator and arm64 iOS while the candidate GGUF remains unset.

Critical Bugs / Software or Hardware or Network Issues -- Three logs maximum, compact if needed

- GitHub draft PR #8 Actions cannot start because GitHub reports an account-level billing/spending-limit issue.
- Physical VoiceOver, Dynamic Type, OCR/photo, interruption, airplane-mode cold launch, sustained energy/battery, and extended thermal gates remain pending; injected physical XCTest signing also hits `errSecInternalComponent`.
- Production package trust keys and an evaluated signed Lite GGUF are not present; startup deliberately exposes Essential only, so the compiled llama.cpp backend is not activated.

Reflect on current working direction is not worth continuing or have better ideas ?

The architecture remains worth continuing. The Mac-side llama.cpp boundary is
green; selection and performance approval of a real Lite GGUF now require the
gaming laptop evaluation followed by physical-device evidence.

---

## 3. Next Stage Implementation Plan--Update after every meaningful session

- Focus 1: Complete direct screen, retrieval/citation, OCR/photo, accessibility, interruption, airplane-mode relaunch, and sustained energy/battery evidence on both physical devices.
- Focus 2: Prepare the exact gaming-laptop Lite candidate evaluation and signed-artifact handoff, without choosing a model from workstation smoke results alone.
- Focus 3: Commit and push the verified universal-device, development-trust, Lite contract, and pinned-runtime milestone while preserving Essential as the fail-closed default.

---

## 4. Important Files and Commands

Files:

- `Docs/ARCHITECTURE.md`: binding runtime sequence and product invariant.
- `VALIDATION_REPORT.md`: current local verification evidence and remaining limits.
- `App/AppModel.swift`: startup active-pack resolution and assistant reinjection.
- `Core/IncidentRuntimeBootstrap.swift`: verified compiled/bundled retrieval composition and runtime-tier intersection.
- `Runtime/AuroraLlamaRuntime/Package.swift`: official llama.cpp release URL and immutable XCFramework checksum.
- `Core/LlamaXCFrameworkBackend.swift`: app-side conformance over the isolated deterministic runtime session.
- `Core/RetrievalEngine.swift`: retrieval protocol, Essential baseline, and deterministic rank fusion.
- `Core/SQLiteHybridRetriever.swift`: compiled SQLite FTS/vector retrieval and fail-closed applicability filters.
- `Core/ActivePackRegistry.swift`: signature, policy, entitlement, recall, and device resolution.
- `Tests/SQLiteHybridRetrieverTests.swift`: direct compiled retrieval and bootstrap regressions.
- `Docs/PHYSICAL_DEVICE_VALIDATION.md`: form-factor decisions and direct-evidence matrix for the iPhone 13 and M2 iPad Pro.
- `Docs/DEVELOPMENT_PACKS.md`: Debug-only key separation and signed lifecycle commands.
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
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AuroraDerivedData CODE_SIGNING_ALLOWED=NO build

# full installed-simulator suite
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS Simulator,id=0E9D8B60-FEA9-4AD5-88C9-58D5FB31636E' \
  -derivedDataPath /tmp/AuroraSimulatorTests CODE_SIGNING_ALLOWED=NO test

# inspect PR #8 once GitHub Actions billing is restored
rtk proxy gh pr checks 8 --repo kenny2077/Aurora

# build and validate signed development knowledge packages
/tmp/trailguard-dev-venv/bin/python tools/prepare_development_packs.py
rtk proxy swift run trailguard-pack-check \
  Resources/Packages/development_trusted_package_keys.json \
  .trailguard/development/knowledge-lifecycle/v1 \
  .trailguard/development/knowledge-lifecycle/v2
```
