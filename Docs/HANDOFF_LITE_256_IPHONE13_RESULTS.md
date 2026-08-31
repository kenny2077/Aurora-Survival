# Aurora Lite 256-token iPhone 13 handoff

Date: 2026-08-31

## Installed state

- Device: standard iPhone 13 (`D93DEDAA-E38F-5BDE-B05F-5FCC01D7E190`)
- Reported physical memory: 3,840,311,296 bytes
- Aurora Lite package: `model.lite.gemma3-1b-q4km@1.3.0`
- Shared RAG package: `knowledge.shared-survival-rag-v3@3.2.0-dev`
- Package state: `Lite ready offline`
- Lite runtime: 2,048 context tokens, 256 maximum output tokens
- GGUF: 806,058,240 bytes; SHA-256 `8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135`

The focused Swift contract group passed 35 tests. The signed package lifecycle
check and signed iPhone build passed. No full suite, iPad run, Expert prompt,
retry, or commit was performed.

## Physical results

### 1. Rabbit behavior — pass

Prompt: `What is typical rabbit behavior in a forest?`

Answer:

> Rabbits are generally solitary animals, but they often form small groups, especially during breeding season. They exhibit a wide range of behaviors, including foraging, burrowing, and socializing. They are known for their quick reflexes and can be quite wary of humans. Their behavior is heavily influenced by food availability and the presence of predators.

- Words: 54
- Sources: none
- Generated tokens: 73
- First-token latency: 678 ms
- Answer generation: 8,690 ms
- Total turn: 24,781 ms
- Throughput: 8.99 tokens/s
- Thermal: nominal
- Peak physical footprint: 241,092,320 bytes
- Minimum available memory: 1,958,820,128 bytes
- No live-data disclaimer, internal text, runtime failure, or source card
- Screenshot: `Docs/AuroraLite256-iPhone13-rabbit.png`

### 2. Shelter — fail, not retried

Prompt: `How to build a shelter`

Answer:

> Use a strong frame and deep dry insulation when no carried shelter is available.

- Words: 14
- Source card: `Survival Manual 2026`
- Generated tokens: 31
- First-token latency: 767 ms
- Answer generation: 3,363 ms
- Total turn: 7,215 ms
- Throughput: 11.56 tokens/s
- Thermal: nominal
- Peak physical footprint: 249,415,440 bytes
- Minimum available memory: 1,950,480,624 bytes
- Loaded pre/post footprint: 131,417,728 / 138,856,112 bytes (5.7% increase)
- No internal-format, retrieval, grounding, retry, or runtime-failure notice
- Failure reason: the grounded response remained far below the requested
  approximately 70–120 useful words, despite the larger output ceiling
- Screenshot: `Docs/AuroraLite256-iPhone13-shelter.png`

## Conclusion

The 256-token configuration is stable and has ample iPhone 13 memory headroom,
but token capacity alone does not fix terse grounded answers. The next change
should focus on the grounded prompt/evidence content or sampling behavior, not
another output-ceiling increase.

Aurora remains installed with Lite 1.3.0 active. The two conversations are
left visible for manual review. All worktree changes remain uncommitted.
