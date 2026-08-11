# Aurora architecture

Binding decisions are recorded in `Docs/ADR/`. Distribution and runtime data
contracts are independently versioned in `Schemas/`.

## Product invariant

Aurora is a fully offline assistant with four product areas: Ask, Manual,
Maps, and Tools. Ask requires a usable signed local model. A survival question
may use at most two local Manual excerpts, and a successful evidence selection
links directly to the same detailed content. Chat does not expose
publisher/source lists.

## Lite Chat runtime

1. The app accepts a message. Photo input is exposed only for an approved,
   active Expert vision runtime.
2. `SurvivalKnowledgeRetriever` searches bundled `survival_knowledge.sqlite`
   with weighted FTS5 and returns at most two answer-ready candidates.
3. `ModelRouter` selects Lite or Expert from preference, trust, runtime,
   memory, storage, thermal state, and power mode. Expert degrades to Lite.
4. `GroundedPromptBuilder` supplies recent conversation plus any candidates to
   Gemma. Unsupported high-risk procedures produce an insufficient-evidence
   response rather than invented steps.
5. Gemma returns `{"a":"answer","e":[1]}`. `a` is displayed naturally;
   validated `e` indexes become zero, one, or two manual destinations.
6. With no usable model, Ask shows model setup and does not synthesize an
   extractive answer. Manual and Maps remain available.

There is no separate hazard-rule or model-bypass stage in Lite Chat.

## Field Manual

The bundled database is the shared knowledge layer for retrieval and reading:

- 10 direct wilderness chapters and exactly 70 concise action lessons;
- 1,050 weighted FTS5 passage records with answer and reference text;
- 12 official/primary guidance sources with review and locator metadata;
- exact stable passage anchors from chat into the Manual tab;
- reviewed redirects or retirement states for all 828 old chunk IDs;
- a generated 10-card emergency fallback if integrity or checksum fails.

`tools/build_survival_knowledge.py` deterministically compiles committed reviewed
JSON into the read-only database, checksum, and fallback. CI and
`tools/validate.py` verify source structure, safety lint, hash, schema counts,
FTS coverage, source relationships, legacy dispositions, and the balanced
200-query retrieval fixture.

## Boundaries

| Component | Responsibility |
| --- | --- |
| SQLite corpus | Offline survival retrieval and detailed manual content |
| Gemma | Normal conversation and natural RAG answer wording |
| Answer envelope | Select only the excerpts actually used |
| Manual navigation | Resolve selected chunks to chapter, section, page, and anchor |
| Expert vision | Add approved local multimodal observations to the prompt |
| Package system | Verify hashes/signatures before activating downloads |
| Maps | Browse and manage signed offline map packages independently of models |

## Model adapter

`LocalLanguageModel` remains the stable core protocol. The llama.cpp adapter:

- embeds checksum-pinned llama.cpp as an XCFramework;
- loads only signed, hash-verified model packages;
- keeps prompts, OCR, images, and output on device;
- applies the model chat template and compact answer/evidence grammar;
- streams with cancellation and reports latency, throughput, memory, and heat;
- unloads under memory pressure, serious heat, backgrounding, or Low Power Mode.

## Navigation, delivery, commerce, and privacy

Each tab owns an independent `NavigationStack`. Maps presents only map packages;
Tools presents only the Lite and Expert model packages. Signed package delivery
and StoreKit entitlement caching remain independent of chat. Incident questions,
photos, location, and health information stay on device. Network operations are
limited to explicit Preparation-mode downloads and denied in Incident Mode.
