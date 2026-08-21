# Survival Manual 2026 — Canonical Expert RAG Decision

Date: 2026-08-20

## Scope

Survival Manual 2026 is a build-time, RAG-only source for development Expert. It does not alter Lite or the visible Manual. The preserved original is discovered through its adjacent corpus-v3 manifest; future reviewed Markdown sources use the same folder contract without changes to compiler code.

## Pipeline

The compiler verifies the original SHA-256, removes document-production noise, builds a heading tree, forms atomic procedural units, and emits 200–500-token chunks targeting 350 tokens with contextual overlap. Exact normalized duplicates collapse by SHA-256. Five-gram MinHash/Jaccard clusters at 0.90 retain one canonical vector and preserve alternate locators as aliases. Incompatible actions or measurements are conflicts and fail construction until a disposition is committed.

Claims, rather than raw chunks, authorize Qwen answers. Each scenario has applicability, action, contraindication, numeric, and escalation claims as available. Overlapping scenarios retain their existing stable IDs while the 2026 manual becomes canonical and compatible existing authorities remain corroboration. Newly covered skills receive stable `sm26-*` IDs.

## Runtime boundary

The existing two-intent route remains unchanged. General questions skip Survival RAG. Survival questions use hybrid retrieval, scenario-level fusion, and the absolute relevance gate. Accepted claims enter the single streamed Qwen answer call; rejected or absent evidence produces an unsourced best-effort answer. No repair completion or deterministic answer replacement is introduced.

## Promotion and release

All six chapters are `humanApproved` for development using private audit ID `developer-review-2026-08-20`. This does not satisfy the external corroboration and independent subject-matter gates required for release. AI-assisted/developer-reviewed provenance appears in acknowledgment schema v2, not citation cards.

## Decisions

- Corpus/package contract v3 replaces hard-coded Expert source lists.
- The 2026 manual is canonical on compatible overlap; corroborating sources are retained.
- Duplicate aliases cannot contribute an additional ranking vote or vector.
- Source cards may be title-only and require a document/section/chunk locator.
- Download UI, runtime crawling, arbitrary imports, and on-device document embedding remain deferred.
