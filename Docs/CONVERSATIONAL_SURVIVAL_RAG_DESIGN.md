# Lite Chat and Unified Wilderness Knowledge Design

Status: implemented 2026-08-09

## Contract

TrailGuard remains fully offline. Ordinary messages use the installed local
model normally. Survival questions search the same read-only knowledge database
used by Manual, inject at most two concise reviewed passages, and convert only
validated evidence indexes into exact Manual links.

`survival_knowledge.sqlite` replaces the former single-book corpus and Manual
overlay. It contains 10 chapters, exactly 70 action lessons, 1,050 indexed
passage records, source relationships, aliases, and dispositions for all 828
former chunk IDs. The source of truth is committed reviewed JSON; the SQLite
file, checksum, and emergency fallback are deterministic build outputs.

## Retrieval

1. Build a bounded query from the message and recent user context.
2. Normalize common survival terms and known misspellings.
3. Search weighted FTS5 fields for chapter, lesson, goal, aliases, answer text,
   reference text, and keywords.
4. Apply domain filtering, review gating, deterministic ranking, prefix fallback,
   and lesson-level duplicate suppression.
5. Return at most two answer-ready passages, each no longer than 120 words.
6. If a survival query has no reviewed result, return an explicit
   insufficient-evidence response and a relevant Manual chapter; do not ask the
   model to invent a high-risk procedure.
7. Convert evidence indexes into stable passage IDs. Legacy IDs resolve through
   reviewed redirects; unrelated material opens a retired-passage state.

The 2,048-token Lite context and 128-token output ceiling are unchanged. No
embedding model, cloud request, or runtime database migration is required.

## Manual

Manual home begins with search and ten compact chapter cards. There is no
“Start here” shelf. Each lesson presents one goal, 3–6 numbered actions, 1–3
critical warnings, and optional deep reference/source details. Search groups
Core Lessons before Deep References. If database checksum or integrity fails,
the generated fallback exposes one reviewed action card per chapter and disables
deep search.

## Acceptance

- Exactly 10 chapters, 70 lessons, at least 1,000 indexed passages, and complete
  source and legacy relationships.
- Balanced 200-query benchmark with at least 90% overall and 95% critical
  top-two lesson recall.
- Exact Ask-to-Manual passage navigation and explicit retired legacy behavior.
- Local search below 300 ms on the iPhone 13 acceptance target.
- No text-only plant/mushroom identification or hybrid/EV high-voltage repair.
- Dark mode, largest Dynamic Type, accessibility labels, offline cold launch,
  and generated fallback coverage.
