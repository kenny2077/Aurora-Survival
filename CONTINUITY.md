## 1. Project Architecture- Should not change unless explicitly requested.

The project must always stay aligned with this thesis:

> TrailGuard is a fully offline iOS incident assistant in which models interpret and explain reviewed evidence, while deterministic safety rules, signed content, citations, and release gates remain authoritative.

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
- `agent/field-foundations` is pushed through substantive handoff commit `78dc400`; its Mac baseline passes 94 tests on both simulator form factors, and the signed universal app plus nested llama framework install, launch, and remain alive on the physical iPhone 13 and M2 iPad Pro.
- MIT-licensed `Phi-3.5-mini-instruct-Q4_K_M.gguf` at revision `6d70da1` is the unbundled Lite winner: exact SHA-256 `e4165e3a...38eff5`, 12/12 native b9637 cases, 2.002 s median cold first output, 60.445 generated tok/s, 2.721 GB peak Windows working set, and 3,183 MiB peak total GPU memory.
- The production prompt/schema/codec now keep procedure text deterministic, the b9637 bridge applies a checked-in grounded-JSON grammar before greedy sampling, structural validation counts 97 tests, pack reproducibility passes, and a hash-pinned Lite package signer is ready for the Mac.

Critical Bugs / Software or Hardware or Network Issues -- Three logs maximum, compact if needed

- GitHub draft PR #8 Actions cannot start because GitHub reports an account-level billing/spending-limit issue.
- Windows has no Swift/Apple toolchain, so the grammar bridge build and all 97 Swift tests require Mac reruns; physical VoiceOver, Dynamic Type, OCR/photo, interruption, airplane-mode cold launch, energy/battery, and thermal gates remain pending.
- No trusted signed Phi package or iPhone inference acceptance exists yet; the selected candidate remains unbundled and startup deliberately exposes Essential only.

Reflect on current working direction is not worth continuing or have better ideas ?

The architecture remains worth continuing. Grammar-constrained structured
generation made the larger MIT Phi candidate reliable without granting it
authority over reviewed steps or warnings. Mac signing and physical iPhone
acceptance are now the remaining Lite gates.

---

## 3. Next Stage Implementation Plan--Update after every meaningful session

- Focus 1: On the Mac, build the grammar-constrained b9637 package, rerun all 97 tests on both simulators, download/rehash Phi, and sign/install it through the real model-package lifecycle.
- Focus 2: Bind the verified active package to `LlamaXCFrameworkBackend` and run iPhone 13 inference acceptance for latency, unified memory, sustained throughput, thermal state, battery, interruption, Low Power Mode, and Essential fallback.
- Focus 3: Complete physical retrieval/citation, OCR/photo, VoiceOver, Dynamic Type, airplane-mode relaunch, and remaining direct-device evidence without upgrading any unrun gate.

---

## 4. Important Files and Commands

Files:

- `Docs/ARCHITECTURE.md`: binding runtime sequence and product invariant.
- `VALIDATION_REPORT.md`: current local verification evidence and remaining limits.
- `App/AppModel.swift`: startup active-pack resolution and assistant reinjection.
- `Core/IncidentRuntimeBootstrap.swift`: verified compiled/bundled retrieval composition and runtime-tier intersection.
- `Runtime/TrailGuardLlamaRuntime/Package.swift`: official llama.cpp release URL and immutable XCFramework checksum.
- `Runtime/TrailGuardLlamaRuntime/Sources/TrailGuardLlamaC/GroundedResponseGrammar.h`: b9637-generated grammar shared by workstation evaluation and the native bridge.
- `Core/LlamaXCFrameworkBackend.swift`: app-side conformance over the isolated deterministic runtime session.
- `Core/GroundedPromptBuilder.swift`: exact nested JSON and evidence-selection contract.
- `Core/GroundedResponseCodec.swift`: validation plus deterministic expansion of approved procedure steps and warnings.
- `Core/RetrievalEngine.swift`: retrieval protocol, Essential baseline, and deterministic rank fusion.
- `Core/SQLiteHybridRetriever.swift`: compiled SQLite FTS/vector retrieval and fail-closed applicability filters.
- `Core/ActivePackRegistry.swift`: signature, policy, entitlement, recall, and device resolution.
- `Tests/SQLiteHybridRetrieverTests.swift`: direct compiled retrieval and bootstrap regressions.
- `Docs/LITE_MODEL_HANDOFF.md`: exact winner, conversion, results, measurements, and Mac continuation.
- `Reports/native-llama-lite-phi-3.5-mini-q4_k_m.json`: complete winning workstation evidence.
- `tools/native_llama_lite_eval.py`: checksum-pinned native candidate evaluator.
- `tools/prepare_lite_model_package.py`: exact-artifact verification and signed Lite package staging.
- `Docs/PHYSICAL_DEVICE_VALIDATION.md`: form-factor decisions and direct-evidence matrix for the iPhone 13 and M2 iPad Pro.
- `Docs/DEVELOPMENT_PACKS.md`: Debug-only key separation and signed lifecycle commands.
- `project.yml`: XcodeGen app/test targets with explicit resource build phases.
- `Resources/Packages/trusted_package_keys.json`: intentionally empty development trust store.

Commands:

```bash
# inspect branch and local changes
rtk proxy git status --short --branch

# structural and reproducibility verification
python tools/validate.py
python tools/test_pack_reproducibility.py

# rerun the selected workstation candidate
python tools/native_llama_lite_eval.py \
  --model .trailguard/model-eval/models/phi-3.5-mini-q4_k_m/Phi-3.5-mini-instruct-Q4_K_M.gguf \
  --output Reports/native-llama-lite-phi-3.5-mini-q4_k_m.json

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

# sign the exact Lite candidate on the Mac
/tmp/trailguard-dev-venv/bin/python tools/prepare_lite_model_package.py \
  --model .trailguard/model-eval/models/phi-3.5-mini-q4_k_m/Phi-3.5-mini-instruct-Q4_K_M.gguf \
  --license .trailguard/model-eval/models/phi-3.5-mini-q4_k_m/LICENSE \
  --output .trailguard/development/model-lite-phi35@1.0.0 \
  --private-key .trailguard/development/package-signing-key.pem \
  --key-id development-2026-07 \
  --created-at 2026-07-30T00:00:00Z

# inspect PR #8 once GitHub Actions billing is restored
rtk proxy gh pr checks 8 --repo kenny2077/TrailGuard

# build and validate signed development knowledge packages
/tmp/trailguard-dev-venv/bin/python tools/prepare_development_packs.py
rtk proxy swift run trailguard-pack-check \
  Resources/Packages/development_trusted_package_keys.json \
  .trailguard/development/knowledge-lifecycle/v1 \
  .trailguard/development/knowledge-lifecycle/v2
```
