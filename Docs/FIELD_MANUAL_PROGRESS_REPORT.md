# TrailGuard Wilderness Knowledge Overhaul Report

Review date: 2026-08-09
Target: iOS 17+, fully offline; Lite floor is iPhone 13 class

## Outcome

TrailGuard now uses one immutable, versioned `survival_knowledge.sqlite` for both Manual and Ask retrieval. The previous single-book corpus and presentation overlay are removed. Manual opens with offline search and ten direct chapter cards; there is no “Start here” shelf.

The release contains exactly 10 chapters, 70 concise action lessons, 1,050 indexed passage records, 12 primary sources, and a reviewed disposition for all 828 legacy chunk IDs. Ask · Manual · Maps · Tools and the Lite/Expert model contract are unchanged.

## Before and after

| Area | Previous | Current |
| --- | --- | --- |
| Manual home | Promotional header, “Start here,” 8 broad chapter cards | Search, then 10 direct wilderness problem cards; “Start here” absent |
| Curriculum | 32 overlay lessons | Exactly 70 action-focused lessons |
| Reference data | 828 chunks / 270 topics from one book plus JSON overlay | 1,050 FTS5 passages generated from reviewed source records |
| Runtime | `ManualCatalog` plus `SurvivalCorpusStore` | One read-only `SurvivalKnowledgeStore` for Manual and Ask |
| Links | Raw chunk/page anchors | Stable passage IDs plus reviewed redirects/retirement for every old chunk ID |
| Failure mode | Overlay and corpus fallbacks were separate | Ten generated emergency cards; deep search disabled; unsupported Ask answers fail closed |

## Curriculum and presentation

The ten chapters are Survival Basics, Find and Treat Water, Start a Fire, Build a Shelter, Find Food Safely, Navigate When Lost, Signal for Rescue, Wilderness First Aid, Weather and Wildlife, and Car Breakdown.

Each lesson has one goal, 3–6 numbered actions, 1–3 critical warnings, source links, and a review date. Cards use short titles and 4–8 word purpose lines. Readers use semantic forest/water/fire colors, SF Symbols, system typography, adaptive cards, dark mode, Dynamic Type, and non-color accessibility labels.

Food content refuses text-only plant or mushroom identification. Vehicle content prohibits work on orange high-voltage components, traction batteries, airbags, brakes, fuel systems, and model-specific repairs. US-specific organizations and emergency practices are labeled rather than presented as global rules.

## Data, sources, and migration

Committed reviewed records in `Resources/Knowledge/survival_knowledge_source.json` are the canonical input. `tools/build_survival_knowledge.py` deterministically creates:

- `survival_knowledge.sqlite`
- `survival_knowledge.sha256`
- `survival_fallback.json`

The database normalizes metadata, sources, chapters, lessons, actions, warnings, passages, passage-source relationships, aliases, legacy anchors, and weighted FTS5 content. Runtime opens it read-only and verifies checksum, schema, counts, FTS coverage, source coverage, and legacy coverage.

The 1,050 passage records are deterministic atomic retrieval views of the 70 reviewed lessons; they are not 1,050 independently authored articles. Primary-source review is recorded as of 2026-08-09 against CDC, Army ATP 3-50.21, NPS, Red Cross, National Weather Service/NOAA, FEMA/Ready.gov, and NHTSA material. This does not imply independent wilderness, medical, legal, or accessibility SME certification.

All 828 old chunk IDs are explicitly redirected or retired. Equivalent advice opens the stable replacement passage. Unsafe or unrelated material displays “Passage retired” and points to a replacement chapter instead of silently opening unrelated guidance.

## Retrieval

Search indexes chapter and lesson titles, goals, aliases, common misspellings, actions, warnings, keywords, short answers, and full reference text with weighted BM25 ranking. It applies deterministic normalization, typo/intent expansion, prefix fallback, review gating, chapter/domain filtering, and lesson duplicate suppression.

Ask receives no more than two reviewed lessons. Lite queries the database for every current message and accepts a match only when normalized lesson aliases, keywords, or meaningful reviewed terms identify a specific lesson. Accepted matches produce grounded answers and exact Manual links. Unmatched messages use Gemma's model-only incident fallback with no Manual link; this fallback is not reviewed Manual content.

During physical testing, “How do I make water safer?” initially selected unrelated “Backtrack Safely” evidence because common words dominated an OR query. Stop-word normalization and a direct regression test corrected this; the final iPhone run selected and opened “Collect and Prefilter Water.”

## Verification evidence

- Repository validator: **PASS** — 10 chapters, 70 lessons, 1,050 passages, 12 primary sources, 828 legacy dispositions, 45 Swift sources, and 126 tests.
- Swift package suite: **126/126 PASS**.
- Knowledge tests cover exact counts, lesson shape, checksum failure, schema mismatch, deterministic checksum, fallback, legacy redirect/retirement, exact anchors, 120-word answer limits, plain-language water intent, and latency.
- Balanced retrieval benchmark: **200 queries; required ≥90% overall and ≥95% for critical intents; both gates pass**.
- Generic simulator app/unit/UI build: **PASS**.
- Focused simulator journeys: **6/6 pass across the corrected final runs**. Evidence: `/tmp/TrailGuardKnowledgeSimulator-20260809-1827.xcresult` (five passing journeys; one superseded test-data failure) and `/tmp/TrailGuardKnowledgeSimulatorManual-20260809-1829.xcresult` (corrected Manual journey pass).
- Physical iPhone 13 shell and Manual: **2/2 PASS**, `/tmp/TrailGuardKnowledgePhysicalShellManual-20260809-1847.xcresult`.
- Physical iPhone 13 installed-Lite answer and exact cited passage: **1/1 PASS**, `/tmp/TrailGuardKnowledgePhysicalFinal-20260809-1846.xcresult`.

The physical Manual journey verifies the missing “Start here” shelf, chapter browsing, 60-second action/warning presentation, offline search, and deep-reference opening. The installed Lite journey verifies no SOS/Clear/photo controls, a real local answer, Manual tab selection, and exact navigation to the visible cited title.

## Performance and accessibility

The 200-query benchmark completes in under half a second on the M2 development Mac. The final repeated-search test completed 20 local searches in about 0.202 seconds, roughly 10 ms per search and below the 300 ms budget. Physical functional navigation is green, but strict app-only Manual-under-one-second and iPhone search p95 must still be measured with signposts/Instruments rather than XCTest polling.

Simulator coverage includes dark appearance, accessibility XXXL Dynamic Type, all ten chapter cards, empty/no-result search, and accessibility identifiers. Full VoiceOver traversal remains a release gate.

## Removed material

`source_corpus.sqlite`, its checksum/importer, `manual_catalog.json`, `ManualCatalog`, `SurvivalCorpusStore`, and their fixed 828-chunk/270-topic runtime contracts are removed. The original files remain recoverable from version control. Legacy IDs survive only in the reviewed migration manifest and compatibility tests.

## Remaining blockers

- Independent safety/medical/legal/accessibility SME approval has not occurred and must not be inferred from primary-source review.
- Strict physical p95 search, Manual cold-display signposts, Airplane Mode, Low Power Mode, sustained battery/memory/thermal runs, and full VoiceOver traversal remain open release gates.
- The paired M2 iPad Pro and iPhone 17 Pro Max were not available for current physical acceptance. Expert vision remains validation-locked until approved signed model/projector, mtmd binding, and eligible-hardware testing exist.
- Annual source recheck and authority-change monitoring are operational requirements for future content releases.
