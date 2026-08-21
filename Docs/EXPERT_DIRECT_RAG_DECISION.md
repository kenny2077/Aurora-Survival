# Expert Direct-RAG Decision

## Status

Accepted for the development-only Expert tier on 2026-08-15. This decision
supersedes the separate Qwen evidence-planner stage. It does not unlock Expert
for release.

## Problem

Physical runs showed control-prompt leakage, unrelated-history contamination,
false verified badges, and weak procedural coverage. The production index had
446 records; the 100,000-row figure described measured search capacity, not
production knowledge. More source material alone could not repair orchestration,
ranking, output validation, or verification-label defects.

## Decision

1. Resolve each turn deterministically as standalone conversation, new incident,
   topic follow-up, answer-focused follow-up, or visual request. Greetings and
   topic switches receive no unrelated history.
2. Produce one bounded retrieval query. Collapse dense and lexical records to
   each scenario's best rank, fuse once with RRF `k=60`, then apply exact-cue and
   linked-discovery boosts once. Stable scenario IDs break ties.
3. Send at most three eligible promoted scenarios directly to Qwen. No qualifying
   scenario means Qwen answers without evidence and the result is unverified.
4. Require internal sentence-attribution JSON for grounded answers. Render only
   natural prose, sentence citations, and resolved source cards.
5. Make at most one evidence-focused repair. Display every structurally valid
   draft even when support is weak. Withhold only malformed output or internal
   prompt/schema leakage.
6. Keep support and request coverage independent. Ordinary conversation has no
   verification badge; a clarification can show coverage but cannot be marked
   verified.

## Corpus Decision

The canonical database retains 70 Manual lessons and adds two Expert-only
promoted scenarios: `car-no-start-triage` and `food-fishing-basics`. Their claims
have primary-source IDs and exact locators. Internal source review is recorded;
independent wilderness/medical/product/legal approval remains pending and blocks
release.

## Verification Gates

- Exact regressions cover “My car will not start” → “Hi” → “Wassup” and “How can
  I find food?” → “How to fish.”
- Retrieval tests cover best-rank scenario deduplication, stable ties, lexical
  fallback, dense/lexical ablation, source resolution, and leakage rejection.
- A separately authored frozen holdout must calibrate the fused threshold for
  100% critical precision before maximizing recall. Generated 700-case coverage
  remains regression data and is not described as independent.
- Three clean physical iPad repetitions must show zero leakage, malformed endings,
  terminal validation refusals after valid generation, false verified badges,
  history contamination, and unresolved citation IDs.

## Compatibility

Lite behavior, explicit PhotoKit authorization, signed offline packages, and the
Ask/Manual/Maps/Tools architecture are unchanged.

## Two-Intent Amendment — 2026-08-20

Physical use showed that treating every non-greeting as an incident allowed
ordinary words such as “get” and “weather” to select unrelated survival records.
Expert now uses one hidden, grammar-constrained Qwen classification with exactly
two values: `general_question` and `survival_question`. General questions never
query Survival RAG. Current-information questions are general and receive an
offline limitation because no live-data provider is installed.

Survival retrieval now keeps natural text for BGE while removing generic words
from FTS. RRF orders candidates but cannot authorize evidence. A scenario must
pass an absolute multiword or cosine-similarity gate before discovery links may
boost it. Failed grounding remains a survival turn with
`no_relevant_evidence`; Qwen answers once without sources. The hidden intent
completion and deterministic retrieval are not answer-repair generations.

The initial M2 iPad spot check found that `0.62` admitted an unrelated EV record
for a solar-still repair request (`cosine 0.6371`). Three expected survival
matches scored `0.6893`, `0.7379`, and `0.7865`. The committed development
thresholds are therefore `0.68` for dense-only eligibility and `0.58` when at
least two meaningful lexical concepts also align. This is a conservative spot
calibration, not a release calibration; the frozen 160-case production-BGE run
and independent review remain required.
