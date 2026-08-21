# Scalable Expert Vector RAG and Reliability

## Understanding

- Expert remains a fully offline, development-locked text and vision tier.
- BGE-small-en-v1.5 supplies 384-dimensional query and corpus embeddings.
- The device may search up to 100,000 signed records in immutable 10,000-row shards.
- Discovery records improve retrieval but never authorize answer attribution.
- Only promoted, reviewed claims can mark generated guidance as verified.
- Complete model drafts remain visible after one evidence-focused regeneration.
- Photo access uses explicit limited/full PhotoKit authorization and a one-time startup acknowledgment.

## Assumptions

- English is the first indexed language.
- Exact float16 scanning is preferred to an approximate index at the accepted scale.
- Corpus vectors are created by trusted build tooling; the app embeds queries only.
- Lite, Manual, Maps, and the four-root product architecture remain unchanged.
- Release still requires physical, product/legal, and independent subject-matter review.

## Decision Log

1. Use pinned `BAAI/bge-small-en-v1.5` through the existing llama.cpp runtime instead of adding Core ML.
2. Use memory-mapped exact float16 shards instead of HNSW or lexical prefiltering.
3. Keep discovery and promoted evidence as separate authority tiers.
4. Show complete flagged Expert drafts with sentence-level verification warnings.
5. Request explicit PhotoKit read/write authorization; denied or restricted access disables images.
6. Require acknowledgment schema version 1 before the main application UI.
7. Replace the two-stage Qwen evidence planner with direct retrieval-to-Qwen RAG.
8. Separate sentence support from request coverage; ordinary replies have no badge.

## Implementation Contract

The canonical implementation contract is the accepted plan in the task that introduced this document and `EXPERT_DIRECT_RAG_DECISION.md`. Package activation requires pinned model and vector-index identities. Query retrieval collapses each channel to the best rank per scenario, merges global dense and lexical rankings through reciprocal-rank fusion (`k=60`), and sends no more than three eligible reviewed scenarios directly to Qwen. Signed shard corruption is quarantined, embedding failure degrades to lexical retrieval, and neither condition changes Lite behavior.

## Retained Implementation Evidence

- The pinned Q8_0 BGE artifact is 36,688,064 bytes with SHA-256 `cb33d693ed112580cd18269561b356d3348a790ef8c13b0f08c17a2373acc232`.
- Two clean production-shard builds produced identical vector, record-map, metadata, and manifest checksums. The current signed bundle contains 446 real reviewed/discovery records; 100,000 is the supported and separately benchmarked capacity, not fabricated production evidence.
- The M2 iPad `expert-vector-100k-m2-v5-metal-heap` run searched ten 10,000-row float16 shards across 12 paced BGE queries at 127.09 ms p95 for embedding plus exact search, 35,700,856 bytes additional peak memory, 128 returned results per query, and nominal thermal state throughout.
- The first post-upgrade three-case Expert smoke completed without validation-terminal responses and without unsafe visible output, but two vision/evidence routes failed. Expert therefore remains development-only.
