# Lite Shared-RAG Streaming — iPhone 13 Assessment

Date: 2026-08-22
Device: iPhone 13 (`iPhone14,5`)
Raw trace SHA-256: `00a6573f8a1382fd48ca01fad652dc1a309a66ebc94183562cd07dff7688b69c`

This was the single requested five-prompt physical run. Every case used one hidden
Gemma intent completion, one progressively streamed Gemma answer completion, and
zero repair completions. The device remained nominal throughout. Peak process
footprint was 249.7–257.4 MB, first-visible text was 1.58–2.93 seconds, total
latency was 5.70–14.78 seconds (8.48-second median), and generation throughput
was 10.0–12.1 tokens/second.

## Observed results

1. Dating: useful best-effort prose and zero sources, but Gemma incorrectly marked
   it as a survival question and the final sentence was truncated.
2. Water boiling: retrieved accepted survival evidence and gave the correct
   one-minute normal-elevation guidance, but copied an evidence label and lost
   its source metadata because the Lite decoder expected Expert's sentence
   envelope.
3. Hypothermia: retrieval/model output leaked internal object fields, so the app
   correctly withheld it and showed a retryable format error.
4. Lost/STOP: retrieved accepted survival evidence and gave the right initial
   action, but copied an evidence label and lost source metadata for the same
   envelope mismatch.
5. Unknown device: correctly retained survival intent with `noRelevantEvidence`,
   showed no sources, and provided conservative best-effort prose.

## Corrections made after the run

- Lite grounded output now uses its compact `{"a":"…","e":[1]}` envelope instead
  of Expert's multi-sentence attribution envelope.
- Lite receives at most four deterministically question-ranked claims from its
  single accepted scenario, with simpler evidence labels that are explicitly
  excluded from prose.
- A valid Lite scenario citation now resolves the scenario ID and its reviewed
  source cards.
- The Gemma intent prompt now contains conservative boundary examples for dating,
  live weather, and stranded-in-snow questions.
- General Lite answers are capped at 75 words to fit the retained 160-token budget.
- Incomplete streamed text must end as a complete sentence before it can be kept.
- The physical harness now records wrong intent, missing grounding metadata,
  format errors, truncation, and unexpected sources as failures.

The post-run corrections compile successfully for the connected iPhone 13. They
were not followed by additional model prompts, preserving the agreed five-case
physical scope. The raw trace above therefore records the pre-correction failures
and must not be interpreted as a passing release gate.
