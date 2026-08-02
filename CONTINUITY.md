## 1. Project Architecture- Should not change unless explicitly requested.

The project must always stay aligned with this thesis:

> Aurora is a fully offline iOS incident assistant

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
- The signed six-product catalog and range-resumable Download Center cover the exact 806,058,240-byte Gemma 3 1B Q4_K_M Lite candidate, three reviewed guides, Twin Cities Scout, and Minnesota Statewide Field products; Qwen3 1.7B remains a hidden challenger.
- Conversational RAG now passes multi-turn history through a compact constrained model decision, validates evidence selection, and deterministically expands reviewed procedures, citations, and warnings; the shared manual contains 15 survival topics across 8 polished chapters.
- On the Kaiyi Guo Personal Team iPhone 13, the signed Gemma model passed a two-turn offline water conversation in 55.6 seconds end to end with no fallback, one source per turn, complete prose, exact CDC 1/3-minute boil guidance, and the cloth-prefilter safety warning (`/tmp/AuroraConversationalPhysical/Logs/Test/Test-Aurora-2026.08.02_12-43-42-+0800.xcresult`).

Critical Bugs / Software or Hardware or Network Issues -- Three logs maximum, compact if needed

- GitHub draft PR #8 Actions cannot start because GitHub reports an account-level billing/spending-limit issue.
- True Airplane Mode and Low Power Mode remain unproven; server-unavailable incident mode is not being mislabeled as a radio-off test.
- Publication still requires final human legal/clinical/mechanical review plus broader survival-intent, accessibility, terrain-map, and physical-device gates; historical Phi evidence remains rejected and must not be restored as Lite.

Reflect on current working direction is not worth continuing or have better ideas ?

The architecture remains worth continuing. The model now provides natural language and conversational continuity while reviewed evidence, deterministic safety, citations, and signed packages retain authority.

---

## 3. Next Stage Implementation Plan--Update after every meaningful session

- Focus 1: Expand deterministic safety and conversational evaluation across heat illness, bleeding, fire, shelter, lost-person, food, and general follow-up intents while measuring iPhone 13 latency.
- Focus 2: Complete physical Dynamic Type, VoiceOver, Airplane Mode, Low Power Mode, download-resume, manual, and signed map gates.
- Focus 3: Integrate and verify detailed Twin Cities/Minnesota terrain rendering, then complete the publication, attribution, and human-review audit.

## 4. Important Files and Commands

Files:

- `Docs/ARCHITECTURE.md`: binding runtime sequence and product invariant.
- `VALIDATION_REPORT.md`: current local verification evidence and remaining limits.
- `App/AppModel.swift`: startup active-pack resolution and assistant reinjection.
- `App/DownloadCenterView.swift`: preparation-only signed catalog, progress, pause/resume, and installed/active UI.
- `App/OfflineMapDetailView.swift`: MapLibre SwiftUI bridge, offline style preparation, region selection, and attribution.
- `Core/PackageCatalog.swift`: signed catalog schema, verification, and same-origin safe URL resolution.
- `Core/PackageDownloadCoordinator.swift`: range-resumable verified download and atomic installation.
- `Core/OfflineMapRuntimeResolver.swift`: active-package identity, readiness, and safe local artifact resolution.
- `Core/OfflineMapStyleAssembler.swift`: local PMTiles/glyph injection and no-network style enforcement.
- `Core/ActiveModelRuntimeResolver.swift`: signed-manifest and accepted-configuration gate before native model binding.
- `Core/IncidentRuntimeBootstrap.swift`: verified compiled/bundled retrieval composition and runtime-tier intersection.
- `Runtime/AuroraLlamaRuntime/Package.swift`: official llama.cpp release URL and immutable XCFramework checksum.
- `Runtime/AuroraLlamaRuntime/Sources/AuroraLlamaC/GroundedResponseGrammar.h`: compact bounded evidence-selection grammar used by the native bridge.
- `Core/LlamaXCFrameworkBackend.swift`: app-side conformance over the isolated deterministic runtime session.
- `Runtime/AuroraLlamaRuntime/Sources/AuroraLlamaC/AuroraLlamaC.cpp`: persistent model/Metal weights with a fresh llama context for each completion.
- `App/ChatView.swift`: bounded incident transcript rendered eagerly so repeated answers remain visible to VoiceOver and UI automation.
- `App/GuideLibraryView.swift`: chaptered shared survival manual driven by the same reviewed knowledge corpus as chat retrieval.
- `Core/GroundedPromptBuilder.swift`: compact domain/evidence-index decision contract sized for the fixed 128-token iPhone budget.
- `Core/GroundedResponseCodec.swift`: validates the bounded decision and deterministically expands only signed procedure steps, citations, warnings, risk, and action.
- `Core/IncidentAssistant.swift`: multi-turn conversational history, retrieval, deterministic safety, and grounded-response orchestration.
- `UITests/PhysicalProductFlowTests.swift`: iPhone 13 Gemma, safety-bypass, OCR, guide/map, and sustained physical product gates.
- `Core/RetrievalEngine.swift`: retrieval protocol, Essential baseline, and deterministic rank fusion.
- `Core/SQLiteHybridRetriever.swift`: compiled SQLite FTS/vector retrieval and fail-closed applicability filters.
- `Core/ActivePackRegistry.swift`: signature, policy, entitlement, recall, and device resolution.
- `Tests/SQLiteHybridRetrieverTests.swift`: direct compiled retrieval and bootstrap regressions.
- `Docs/LITE_MODEL_HANDOFF.md`: exact winner, conversion, results, measurements, and Mac continuation.
- `Docs/POLISHED_PRODUCT_DEVELOPMENT_PROMPT.md`: reusable product-quality continuation brief synthesized from both uploaded plans.
- `Docs/CONVERSATIONAL_SURVIVAL_RAG_DESIGN.md`: iteration-one conversational RAG, source-authority, and verification design.
- `Reports/native-llama-lite-phi-3.5-mini-q4_k_m.json`: complete winning workstation evidence.
- `tools/native_llama_lite_eval.py`: checksum-pinned native candidate evaluator.
- `tools/prepare_lite_model_package.py`: exact-artifact verification and signed Lite package staging.
- `tools/prepare_product_catalog.py`: deterministic guide/map packaging and signed six-product catalog generation.
- `tools/serve_product_catalog.py`: safe range-aware local product host for physical testing.
- `Docs/PHYSICAL_DEVICE_VALIDATION.md`: form-factor decisions and direct-evidence matrix for the iPhone 13 and M2 iPad Pro.
- `Docs/DEVELOPMENT_PACKS.md`: Debug-only key separation and signed lifecycle commands.
- `project.yml`: XcodeGen app/test targets with explicit resource build phases.
- `Resources/Packages/trusted_package_keys.json`: intentionally empty development trust store.

Commands:

```bash
# inspect branch and local changes
rtk proxy git status --short --branch

# structural and reproducibility verification
python3 tools/validate.py
/tmp/trailguard-dev-venv/bin/python tools/test_pack_reproducibility.py

# rerun the selected Gemma workstation candidate
python tools/native_llama_lite_eval.py \
  --model .trailguard/model-eval/models/gemma-3-1b-q4_k_m/gemma-3-1b-it-Q4_K_M.gguf \
  --output Reports/native-llama-lite-gemma-3-1b-q4_k_m.json

# Swift package verification
rtk proxy swift test

# rebuild and verify the complete local product catalog
/tmp/trailguard-dev-venv/bin/python tools/prepare_product_catalog.py --rebuild-maps
rtk proxy swift run trailguard-pack-check catalog \
  Resources/Packages/development_trusted_package_keys.json \
  .trailguard/development/catalog.json

# serve signed packages to devices on the local network
/tmp/trailguard-dev-venv/bin/python tools/serve_product_catalog.py \
  --directory .trailguard/development/product-host --bind 0.0.0.0 --port 8765

# generate the Xcode project
rtk xcodegen generate

# unsigned generic iOS Simulator build
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AuroraMapLibreBuild CODE_SIGNING_ALLOWED=NO build

# signed connected iPhone 13 build
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS,id=00008110-001645080EA8201E' \
  -derivedDataPath /tmp/AuroraPhysicalBuild \
  -allowProvisioningUpdates build

# full installed-simulator suite
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS Simulator,id=0E9D8B60-FEA9-4AD5-88C9-58D5FB31636E' \
  -derivedDataPath /tmp/AuroraSimulatorTests CODE_SIGNING_ALLOWED=NO test

# physical two-turn conversational RAG gate on the connected iPhone 13
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS,id=00008110-001645080EA8201E' \
  -derivedDataPath /tmp/AuroraConversationalPhysical \
  -allowProvisioningUpdates \
  -only-testing:AuroraUITests/PhysicalProductFlowTests/testLiteConversationalFollowUp test

# sign the exact Gemma Lite release candidate on the Mac
/tmp/trailguard-dev-venv/bin/python tools/prepare_lite_model_package.py \
  --model .trailguard/model-eval/models/gemma-3-1b-q4_k_m/gemma-3-1b-it-Q4_K_M.gguf \
  --terms .trailguard/model-eval/models/gemma-3-1b-q4_k_m/GEMMA_TERMS.md \
  --output .trailguard/development/model-lite-gemma3-1b-q4km-dev@1.0.0 \
  --private-key .trailguard/development/package-signing-key.pem \
  --key-id development-2026-07 \
  --created-at 2026-07-30T00:00:00Z

# install and resolve the signed Lite package through the real lifecycle
rtk proxy swift run trailguard-pack-check model \
  Resources/Packages/development_trusted_package_keys.json \
  .trailguard/development/model-lite-gemma3-1b-q4km-dev@1.0.0

# inspect PR #8 once GitHub Actions billing is restored
rtk proxy gh pr checks 8 --repo kenny2077/Aurora

# build and validate signed development knowledge packages
/tmp/trailguard-dev-venv/bin/python tools/prepare_development_packs.py
rtk proxy swift run trailguard-pack-check \
  Resources/Packages/development_trusted_package_keys.json \
  .trailguard/development/knowledge-lifecycle/v1 \
  .trailguard/development/knowledge-lifecycle/v2
```
