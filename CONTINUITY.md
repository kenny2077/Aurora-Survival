## 1. Project Architecture- Should not change unless explicitly requested.

The project must always stay aligned with this thesis:

> Aurora is a fully offline universal iPhone/iPad survival assistant with four independent roots—Ask, Manual, Maps, and Tools—and concise, reviewed, source-linked wilderness actions grounded in one knowledge database.

Do not narrow the project into a toy demo.

- Dataset: Versioned corpus-v3 `survival_knowledge.sqlite`, deterministically built from committed reviewed manifests and JSON. Lite remains exactly 10 chapters, 70 lessons, and 1,050 frozen passages. Expert contains 61 scenarios, 545 promoted claim records, and 79 canonical Survival Manual 2026 chunks. Its signed vector shard contains 922 real records; 100,000 rows remains a separate measured capacity fixture.
- Baselines: Manual and Ask share `SurvivalKnowledgeStore`; every stateless Lite message queries the database using only the current question/domain/OCR. Specific normalized lesson matches receive at most two reviewed lessons; unmatched messages use model-only incident fallback with no Manual link. Ten generated Manual fallback cards survive database validation failure.
- Metrics: Deterministic build/checksum/schema, frozen 200-query Lite recall, 700 generated Expert regression cases plus a separately authored frozen holdout, exact/legacy anchors, real-model prose/leakage sequences, local latency, offline behavior, accessibility, battery/memory/thermal, and physical-device acceptance.
- Related Work: SQLite FTS5/BM25, llama.cpp on-device inference, CDC, Army ATP 3-50.21, NPS, Red Cross, NWS/NOAA, FEMA/Ready.gov, NHTSA, and MapLibre-compatible offline maps.

Code Architecture:
- `App/`: Ask · Manual · Maps · Tools; Manual home is search plus ten direct chapter cards with no “Start here.”
- `Core/SurvivalKnowledge.swift`: read-only validated knowledge store, Manual models/routes, weighted search, fallback loading, and Ask retrieval.
- `Resources/Knowledge/`: canonical reviewed JSON, legacy manifest, generated database/checksum/fallback, and no old book corpus/overlay.
- `tools/build_survival_knowledge.py`: deterministic database/fallback builder; `tools/validate.py` enforces content and database contracts.
- `Tests/` and `UITests/`: 218 Swift tests, frozen 200-query Lite, generated 700-case Expert regression coverage, a separately authored Direct-RAG holdout, corpus-v3/compiler integrity, vector-shard boundaries, simulator agreement/photo authorization journeys, and retained physical-device reports.
- `Docs/`: architecture, validation, implementation status, and `FIELD_MANUAL_PROGRESS_REPORT.md` evidence.

Model contract:
- Lite targets iPhone 13-class devices. Expert targets eligible high-memory hardware only after signed artifact/projector, runtime, thermal/power/storage/memory, and physical vision gates pass.
- Lite is fully stateless and text-only. Gemma performs one hidden two-intent call and one progressively streamed answer call with zero repair calls; a narrow high-precision survival guard corrects known small-model false-general decisions. Survival turns use the shared BGE/vector/FTS fusion, absolute gate, and cited source resolution, rerank ten candidates, and select at most two independently eligible scenarios with ten claims.
- Expert is development-only: pinned Qwen3-VL 2B Q4_K_M plus Q8_0 projector and pinned BGE-small-en-v1.5 Q8_0 run through llama.cpp b9637. Deterministic signed 384-dimensional float16 shards support exact Metal search to 100,000 rows. Text-only turns use one hidden two-intent call, survival-only gated RAG, and one streamed answer. Newly attached photos bypass intent and RAG and receive one native streamed Qwen3-VL answer with no sources, Manual links, badges, repair, or fallback inference.
- Exactly Lite and Expert remain customer-facing. Ask is unavailable without a usable model; Manual and Maps remain available. Chat has no SOS or Clear control.

---

## 2. Progress--Update after every meaningful session

Milestones -- Three Facts only, no raw logs : compact if needed
- Lite and Expert now resolve one signed `knowledge.shared-survival-rag-v3` pack containing corpus-v3, pinned BGE-small-en-v1.5 Q8, and the rebuilt 922-record float16 index. Model packages carry only their inference artifacts plus the shared-pack dependency contract.
- Lite now preserves task-bearing operations, reranks ten gated scenarios, selects up to two independently eligible scenarios, and sends at most ten coherent claims. The manifest-discovered reviewed-claim sidecar consolidates water-location, water-selection, and outdoor-cooking evidence; the compiler reports zero unresolved promoted fragments.
- Focused iPhone 13 A/B diagnostics held peak footprint near 230–244 MB with at least 1.85 GB available and no jetsam or model-load failure. Repeated unpaced development reruns eventually reached serious thermal, so the Debug harness now paces cases. The user's manual menu test passed the current Lite answer quality; 23 focused Swift regressions and the iOS build pass.

Critical Bugs / Software or Hardware or Network Issues -- Three logs maximum, compact if needed

- M2 iPad 100k capacity gate remains 127.09 ms p95 embedding+search with 35,700,856 additional peak bytes and nominal thermal; the real production index is 956 records, not 100,000.
- The first physical no-evidence case exposed an EV false match at cosine 0.6371. Strong/moderate gates were recalibrated to 0.68/0.58; three correct physical matches measured 0.6893–0.7865, and the final rerun rejected the false source. A conservative no-evidence prompt then removed its invented solvent repair and directed the user to identify the model/manufacturer.
- The immutable iPhone 13 trace records the pre-correction quality failures: dating was routed as survival, water/STOP lost source metadata, and hypothermia was withheld for control leakage. `Reports/lite-shared-rag-streaming/ASSESSMENT.md` records the corrections; a post-correction model rerun was intentionally not added beyond the agreed five prompts.

Reflect on current working direction is not worth continuing or have better ideas ?

Direct RAG is materially better than the planner flow and should continue. The next quality constraint is model-call latency and attribution compliance, not adding indiscriminate corpus volume; future depth should still arrive only as independently reviewed source records.

---

## 3. Next Stage Implementation Plan--Update after every meaningful session

- Focus 1: If a formal release gate is needed later, run the paced Lite A/B comparison from nominal thermal state; it is not required for this completed manual-quality iteration.
- Focus 2: Preserve the current reviewed evidence limits, including the absence of unsupported cooking temperatures.
- Focus 3: Keep corpus/model expansion and broader regression work out of this completed Lite iteration.

---

## 4. Important Files and Commands

Files:

- `Resources/Knowledge/survival_knowledge_source.json`: canonical reviewed curriculum/source records.
- `Resources/Knowledge/expert_shadow_corpus.json`: Expert-only sources, licensed chunks, scenario links, conflicts, corroboration, and unpromoted proposals.
- `Resources/Knowledge/legacy_anchor_manifest.json`: every former chunk ID redirected or retired.
- `Resources/Knowledge/survival_knowledge.sqlite`: immutable runtime database.
- `Resources/Knowledge/survival_fallback.json`: one emergency action card per chapter.
- `Core/SurvivalKnowledge.swift`: unified Manual/Ask store and retrieval.
- `Core/IncidentAssistant.swift`: tier-neutral two-intent routing and Direct-RAG, stateless top-two Lite selection, bounded Expert history/three-scenario selection, and one streamed answer generation with cited-source resolution.
- `Core/ExpertContext.swift`: Expert adaptive profiles, `ExpertTurnResolver`, bounded relevant history, scenario-level dense/lexical RRF, one-time boosts, and deterministic selection.
- `Core/ExpertEvidence.swift`: Expert-only scenario, reviewed claim, numeric fact, evidence bundle, risk, and failure-taxonomy types.
- `Core/ExpertSafety.swift`: sentence-attribution envelope, structural completeness and control-leakage checks, claim-aware support validation, and actionable repair errors.
- `Core/ExpertVectorIndex.swift`: signed memory-mapped float16 shards, quarantine/filtering, deterministic bounded top-K, Metal exact scan, and Accelerate fallback.
- `Core/ActiveModelRuntimeResolver.swift`: exact Lite/Expert runtime allowlists, shared-RAG dependency validation, and the signed shared corpus/BGE/vector descriptor.
- `Core/GroundedPromptBuilder.swift`: compact purpose/attempt contracts with defensive Lite history removal.
- `Core/GroundedResponseCodec.swift`: compact JSON, leakage, completion, and evidence validation.
- `Runtime/AuroraLlamaRuntime/`: pinned llama.cpp bridge and ignored, verified two-slice mtmd XCFramework; explicit linker references prevent app dead-stripping.
- `App/ExpertPhysicalHarness.swift`: Debug-only process memory and physical report support.
- `App/PhotoLibraryAccess.swift`: injectable explicit PhotoKit authorization and canonical attachment state.
- `App/CameraCaptureView.swift`: standard still-camera wrapper used by the composer source chooser.
- `App/RiskAcknowledgementView.swift`: non-dismissible schema-v2 startup acknowledgment, including AI-assisted/developer-reviewed offline-reference fallibility disclosure.
- `Resources/Knowledge/CorpusSources/survival-manual-2026/`: byte-preserved source and signed build-time manifest for the canonical RAG-only manual.
- `tools/build_expert_corpus_v3.py`: manifest discovery, normalization, semantic chunking, deduplication, metadata/claim compilation, conflict checks, and immutable import reporting.
- `Reports/survival-manual-2026/corpus-import-report.json`: canonical import inventory, provenance, locators, conflicts, and actual vector counts.
- `Reports/survival-manual-2026/physical-final-20-r2.json`: immutable final connected-M2-iPad 20-prompt trace for corpus-v3.
- `Reports/expert-native-vision/expert-native-vision-r1.json`: immutable three-case native Qwen3-VL physical trace with streaming, routing, latency, throughput, memory, and thermal metrics.
- `tools/run_physical_expert.py`: resumable signed-install, calibration, vision, multi-turn, interruption, and sustained M2 runner.
- `Docs/EXPERT_DIRECT_RAG_DECISION.md`: finalized Direct-RAG architecture and decision record.
- `Docs/EXPERT_NATIVE_VISION_DECISION.md`: native photo routing, one-call generation, ephemeral-image, and source-suppression decision.
- `Docs/CAMERA_CAPTURE_ATTACHMENT_DECISION.md`: source-choice permissions, save-before-attach, failure preservation, and capture privacy decision.
- `Tests/Fixtures/expert_direct_rag_holdout.json`: separately authored frozen Direct-RAG relevance, negative, and prose holdout.
- `Reports/expert-m2-ipad/expert-direct-rag-sequence-r4.json`: complete five-turn physical routing and real-Qwen trace.
- `Reports/expert-m2-ipad/expert-direct-rag-fishing-r5.json`: focused post-fix fishing completeness trace.
- `tools/build_expert_vector_shards.py`: deterministic real-corpus export, embedding, SQLite metadata, and signed shard builder.
- `tools/build_expert_vector_benchmark.py`: deterministic ten-shard/100,000-row physical capacity fixture.
- `App/GuideLibraryView.swift`: ten-chapter Manual UI and readers.
- `App/AppModel.swift`: UI-only Lite transcript, database loading, search, and exact Manual navigation.
- `App/ChatView.swift`: banner-free chat, Lite badge, actionable notices, and exact Manual links.
- `tools/build_survival_knowledge.py`: deterministic build and validation.
- `tools/native_llama_lite_eval.py`: exact pinned Gemma artifact and production prompt/grammar evaluator.
- `Tests/SurvivalKnowledgeTests.swift`: structure, retrieval, safety, migration, fallback, and latency tests.
- `Tests/ConversationalRAGTests.swift`: stateless sequences, prompt isolation, validation, retry, and failure regressions.
- `Tests/ExpertSequenceBenchmarkTests.swift`: generated 40/30/30/20 Expert sequence matrix and p95/recall gates.
- `Tests/ExpertRAGBenchmarkTests.swift`: generated 700-case regression plus frozen holdout gates for retrieval, negatives, coverage, traceability, and taxonomy.
- `Tests/Fixtures/expert_rag_benchmark.json`: retained generated Expert regression set; it is not described as independent.
- `Reports/expert-two-intent-calibration-v2.json`: 80 survival positives, 80 hard negatives, and the M2-iPad cosine spot calibration for the absolute gate. Full production-BGE holdout calibration remains a release blocker.
- `Docs/EXPERT_MODE_DEVELOPMENT.md`: artifact, build, activation, behavior, and physical acceptance briefing.
- `Docs/FIELD_MANUAL_PROGRESS_REPORT.md`: current before/after evidence and blockers.
- `Docs/LITE_SUBSTANTIVE_ANSWERS.md`: approved substantive-answer design, implementation contract, and measured limitations.
- `Docs/LITE_CHAT_CASE.md`: current database-first grounded/fallback contract and measured evidence.

Commands:

```bash
# rebuild database/checksum/fallback from committed source records
rtk proxy python3 tools/build_survival_knowledge.py

# repository and content contracts
rtk proxy python3 tools/validate.py

# deterministic 100k exact-search fixture and connected-M2 gate
python3 tools/build_expert_vector_benchmark.py \
  --output .trailguard/expert-vector-benchmark-100k
python3 tools/run_physical_expert.py --mode expert-vector-benchmark \
  --run-id expert-vector-100k-m2-v5-metal-heap \
  --cooldown-every 0 --cooldown-seconds 0 --nominal-settle-seconds 0

# full Swift suite
rtk proxy swift test

# exact pinned Gemma production contract
rtk proxy python3 tools/native_llama_lite_eval.py --contract-only

# build the pinned local mtmd-capable XCFramework (large network/build step)
rtk proxy tools/build_mtmd_xcframework.sh

# signed package install/calibration on the connected M2 iPad
python3 tools/run_physical_expert.py --mode expert-install \
  --catalog-url http://192.168.3.62:8765/catalog.json
python3 tools/run_physical_expert.py --mode expert-calibration \
  --profile constrained --repetition 1

# paced Expert physical batch: unload and cool for 60 seconds every five cases
python3 tools/run_physical_expert.py --mode expert-multiturn --batch 1 \
  --cooldown-every 5 --cooldown-seconds 60

# retained new-architecture Qwen diagnostic (run only from nominal thermal)
python3 tools/run_physical_expert.py --mode expert-rag-diagnostic \
  --cooldown-every 4 --cooldown-seconds 30 \
  --run-id expert-rag-v2-diagnostic-validator-repair

# thermal probe and exact two-case resume
python3 tools/run_physical_expert.py --mode expert-thermal-probe \
  --nominal-settle-seconds 60 --run-id thermal-probe
python3 tools/run_physical_expert.py --mode expert-rag-diagnostic \
  --case-start 10 --case-count 2 --cooldown-every 0 \
  --run-id thermal-managed-validator-tail

# regenerate Xcode project
rtk proxy xcodegen generate

# generic simulator build
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AuroraKnowledgeBuild CODE_SIGNING_ALLOWED=NO build-for-testing

# physical iPhone focused acceptance
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS,id=00008110-001645080EA8201E' \
  -derivedDataPath /tmp/AuroraKnowledgePhysical -allowProvisioningUpdates \
  -only-testing:AuroraUITests/PhysicalProductFlowTests test-without-building

# inspect obsolete runtime references
rtk proxy rg -n 'source_corpus|manual_catalog|ManualCatalog|SurvivalCorpusStore|startHereLessonIDs' App Core Tests tools
```
