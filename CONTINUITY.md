## 1. Project Architecture- Should not change unless explicitly requested.

The project must always stay aligned with this thesis:

> TrailGuard is a fully offline universal iPhone/iPad survival assistant with four independent roots—Ask, Manual, Maps, and Tools—and concise, reviewed, source-linked wilderness actions grounded in one immutable knowledge database.

Do not narrow the project into a toy demo.

- Dataset: Versioned `survival_knowledge.sqlite`, deterministically built from committed reviewed JSON; exactly 10 chapters, 70 lessons, 1,050 FTS5 passages, 12 primary sources, and reviewed dispositions for all 828 former chunk IDs.
- Baselines: Manual and Ask share `SurvivalKnowledgeStore`; every stateless Lite message queries the database using only the current question/domain/OCR. Specific normalized lesson matches receive at most two reviewed lessons; unmatched messages use model-only incident fallback with no Manual link. Ten generated Manual fallback cards survive database validation failure.
- Metrics: Deterministic build/checksum/schema, content safety lint, 200-query top-two recall, exact/legacy anchors, local latency, offline behavior, dark mode, Dynamic Type, VoiceOver, battery/memory/thermal, and physical device acceptance.
- Related Work: SQLite FTS5/BM25, llama.cpp on-device inference, CDC, Army ATP 3-50.21, NPS, Red Cross, NWS/NOAA, FEMA/Ready.gov, NHTSA, and MapLibre-compatible offline maps.

Code Architecture:
- `App/`: Ask · Manual · Maps · Tools; Manual home is search plus ten direct chapter cards with no “Start here.”
- `Core/SurvivalKnowledge.swift`: read-only validated knowledge store, Manual models/routes, weighted search, fallback loading, and Ask retrieval.
- `Resources/Knowledge/`: canonical reviewed JSON, legacy manifest, generated database/checksum/fallback, and no old book corpus/overlay.
- `tools/build_survival_knowledge.py`: deterministic database/fallback builder; `tools/validate.py` enforces content and database contracts.
- `Tests/` and `UITests/`: 135 Swift tests, 200-query retrieval benchmark, simulator journeys, and physical iPhone acceptance.
- `Docs/`: architecture, validation, implementation status, and `FIELD_MANUAL_PROGRESS_REPORT.md` evidence.

Model contract:
- Lite targets iPhone 13-class devices. Expert targets eligible high-memory hardware only after signed artifact/projector, runtime, thermal/power/storage/memory, and physical vision gates pass.
- Lite is fully stateless at app, retrieval, and prompt boundaries; specific Manual matches use a 35–55-word grounded prompt, unmatched incidents use a 30–60-word incident fallback, greetings/no-incident messages use incident intake, malformed output receives one repair inference, runtime failures do not retry, and only grounded validated evidence indexes create Manual links.
- Exactly Lite and Expert remain customer-facing. Ask is unavailable without a usable model; Manual and Maps remain available. Chat has no SOS or Clear control.

---

## 2. Progress--Update after every meaningful session

Milestones -- Three Facts only, no raw logs : compact if needed
- TrailGuard is frozen for app/source release `1.0.0` build 1; the signed Gemma 3 1B Q4_K_M package remains independently versioned at `1.1.0`.
- Database-first Lite routing, stateless prompting, grounded-only Manual links, incident fallback/intake, one quality repair, and banner-free chat are the accepted release behavior.
- Release validation passes: deterministic knowledge rebuild, repository contracts, 135/135 Swift tests, native production-contract check, generic simulator test build, and signed iPhone 13 build. The user reports satisfactory manual physical prompt/scenario testing.

Critical Bugs / Software or Hardware or Network Issues -- Three logs maximum, compact if needed

- The interrupted automated 40-case physical Lite matrix remains unretained and is excluded from release evidence; no aggregate usefulness, repair-rate, or current-contract thermal pass is claimed.
- Independent wilderness/medical/legal/licensing/accessibility SME approval is absent; current content is primary-source reviewed, not certified.
- Current-contract TTFT/throughput/repair thermal measurements, Airplane/Low Power Mode, sustained battery/memory, full VoiceOver, M2 iPad, iPhone 17 Pro Max, native pinned-evaluator generation, and Expert vision gates remain open.

Reflect on current working direction is not worth continuing or have better ideas ?

The unified reviewed source-record pipeline is worth continuing. Future depth should be added as independently reviewed source records, not by restoring the broad single-book corpus or runtime web scraping.

---

## 3. Next Stage Implementation Plan--Update after every meaningful session

- Focus 1: Commit the approved product snapshot, merge PR #8 to `main`, tag `v1.0.0`, and publish the GitHub Release without committing interrupted stress artifacts.
- Focus 2: In post-1.0 work, retain a complete physical Lite stress matrix and measure first-pass validity, repair rate, TTFT, throughput, completion, and thermal behavior.
- Focus 3: Obtain independent safety/medical/legal/licensing review and keep Expert locked until signed artifacts, mtmd binding, and eligible-device evidence exist.

---

## 4. Important Files and Commands

Files:

- `Resources/Knowledge/survival_knowledge_source.json`: canonical reviewed curriculum/source records.
- `Resources/Knowledge/legacy_anchor_manifest.json`: every former chunk ID redirected or retired.
- `Resources/Knowledge/survival_knowledge.sqlite`: immutable runtime database.
- `Resources/Knowledge/survival_fallback.json`: one emergency action card per chapter.
- `Core/SurvivalKnowledge.swift`: unified Manual/Ask store and retrieval.
- `Core/IncidentAssistant.swift`: stateless Lite routing, retrieval, one repair, and terminal response policy.
- `Core/GroundedPromptBuilder.swift`: compact purpose/attempt contracts with defensive Lite history removal.
- `Core/GroundedResponseCodec.swift`: compact JSON, leakage, completion, and evidence validation.
- `App/GuideLibraryView.swift`: ten-chapter Manual UI and readers.
- `App/AppModel.swift`: UI-only Lite transcript, database loading, search, and exact Manual navigation.
- `App/ChatView.swift`: banner-free chat, Lite badge, actionable notices, and exact Manual links.
- `tools/build_survival_knowledge.py`: deterministic build and validation.
- `tools/native_llama_lite_eval.py`: exact pinned Gemma artifact and production prompt/grammar evaluator.
- `Tests/SurvivalKnowledgeTests.swift`: structure, retrieval, safety, migration, fallback, and latency tests.
- `Tests/ConversationalRAGTests.swift`: stateless sequences, prompt isolation, validation, retry, and failure regressions.
- `Docs/FIELD_MANUAL_PROGRESS_REPORT.md`: current before/after evidence and blockers.
- `Docs/LITE_SUBSTANTIVE_ANSWERS.md`: approved substantive-answer design, implementation contract, and measured limitations.
- `Docs/LITE_CHAT_CASE.md`: current database-first grounded/fallback contract and measured evidence.

Commands:

```bash
# rebuild database/checksum/fallback from committed source records
rtk proxy python3 tools/build_survival_knowledge.py

# repository and content contracts
rtk proxy python3 tools/validate.py

# full Swift suite
rtk proxy swift test

# exact pinned Gemma production contract
rtk proxy python3 tools/native_llama_lite_eval.py --contract-only

# regenerate Xcode project
rtk proxy xcodegen generate

# generic simulator build
rtk proxy xcodebuild -project TrailGuard.xcodeproj -scheme TrailGuard \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TrailGuardKnowledgeBuild CODE_SIGNING_ALLOWED=NO build-for-testing

# physical iPhone focused acceptance
rtk proxy xcodebuild -project TrailGuard.xcodeproj -scheme TrailGuard \
  -destination 'platform=iOS,id=00008110-001645080EA8201E' \
  -derivedDataPath /tmp/TrailGuardKnowledgePhysical -allowProvisioningUpdates \
  -only-testing:TrailGuardUITests/PhysicalProductFlowTests test-without-building

# inspect obsolete runtime references
rtk proxy rg -n 'source_corpus|manual_catalog|ManualCatalog|SurvivalCorpusStore|startHereLessonIDs' App Core Tests tools
```
