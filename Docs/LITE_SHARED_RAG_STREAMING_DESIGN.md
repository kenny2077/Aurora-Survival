# Lite Shared-RAG Streaming Design

## Understanding

- Lite keeps the pinned Gemma 3 1B Q4_K_M model, 2,048-token context, and
  160-token output limit for iPhone 13-class hardware.
- Lite and Expert consume one validated corpus-v3 database, BGE-small-en-v1.5
  Q8 embedding artifact, and deterministic 384-dimensional vector index.
- Both text tiers use the same two-intent router, hybrid scenario retrieval,
  absolute evidence gate, stable ranking, and cited-source resolution.
- Lite remains stateless, reranks a stable ten-scenario pool by requested
  operation and subject alignment, and sends the best two independently
  eligible scenarios to Gemma. Expert retains bounded history and up to three
  eligible scenarios.
- Lite performs one hidden intent completion and one progressively streamed
  answer completion. It performs no answer repair completion.
- Lite is text-only. Its composer exposes no camera or photo attachment path.
- A missing or quarantined shared RAG runtime disables grounding for both tiers;
  answers remain available as unsourced best effort.

## Assumptions and constraints

- The embedding identity and Gemma/Qwen weights remain unchanged. Corpus claims
  and their deterministic vectors are rebuilt when reviewed sidecars change.
- Manual keeps its independent validated database and emergency fallback path.
- Lite receives up to two accepted scenarios and at most ten coherent,
  query-relevant promoted claims that fit its compact 1,400-token input budget.
- Only model-cited accepted claims resolve Offline Sources cards.
- The focused physical experiment is limited to five prompts on an iPhone 13.

## Decision log

1. Selected one shared signed RAG pack instead of duplicating BGE weights in
   Lite and Expert model packages.
2. Selected Gemma's constrained hidden intent completion instead of preserving
   deterministic Lite routing or querying RAG for every turn.
3. Selected one streamed answer completion with zero repairs.
4. Replaced Lite's top-one evidence policy after physical testing showed that
   discarding the operation `find` let water-contamination guidance outrank
   water-location guidance. Lite now preserves task-bearing verbs as canonical
   operations and selects at most two independently eligible scenarios.
5. Added manifest-discovered reviewed-claim sidecars and a promoted-claim
   structural quality gate. The first sidecar consolidates source-backed water
   location, water selection, and raw-food cooking claims without inventing
   missing cooking temperatures.
6. Selected best-effort unsourced degradation for both tiers when the shared
   RAG runtime is unavailable; partial lexical grounding is not allowed.
7. Selected a text-only Lite composer with model-capability explanation instead
   of OCR-only image handling or automatic tier switching.

## Final data flow

User text is classified by the selected tier's model. General turns go directly
to that model. Survival turns query the shared lexical and dense indexes, fuse
and gate scenarios identically, then select up to three scenarios for Expert.
Lite operation/subject-reranks a ten-candidate pool and sends the best two
eligible scenarios, capped at ten claims. The selected model performs one
streamed response-envelope completion. Clean prose is displayed progressively;
only valid cited accepted evidence becomes an Offline Sources card.
