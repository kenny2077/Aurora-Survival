# Lite Substantive Survival Answers

> The clarification/ordinary routing described below is retained as historical
> evidence. It was superseded on 2026-08-10 by the database-first incident
> pipeline.

## Database-first superseding contract — 2026-08-10

- Lite queries the reviewed database for every current message; the previous
  hard-coded survival-term prefilter no longer controls Lite routing.
- Normalized lesson aliases, keywords, titles, goals, actions, and warnings
  accept specific matches and reject generic-only terms such as `car`, `fix`,
  `help`, `problem`, and `survive`.
- Specific matches keep the 35–55-word grounded contract and exact Manual links.
  Unmatched messages use `incidentFallback`: 30–60-word best-effort Gemma
  guidance, runtime acceptance at 24–75 words, `e=[]`, and no Manual link.
- Fallback validation rejects prompt leakage, incomplete output, evidence
  indexes, and role reversal, including smart-apostrophe forms such as `I’m`.
- Repository validation, all 126 Swift tests, generic simulator build, and two
  focused simulator UI flows pass. Native generation is blocked by the missing
  pinned b9637 executable. Physical inference was not reached: the matrix test
  runner was killed during launch and a retry hit Xcode's debugger-store error.

## Understanding

- Grounded Lite answers are currently too brief because the prompt asks for one
  8–28-word action, the grammar caps answers at 220 characters, and retrieval
  exposes only a lesson goal plus its first action.
- Grounded answers should normally be one 35–55-word paragraph with two useful
  actions and an important warning or stop condition.
- Casual chat remains brief and Lite remains fully stateless.
- Generic requests such as “How to fix my car” must ask for observable symptoms
  instead of selecting an unrelated procedure or Manual link.
- Lite may use 160 output tokens while retaining the 2,048-token context, pinned
  Gemma artifact, grammar-constrained greedy decoding, loaded weights, and
  serialized inference.

## Assumptions

- Gemma remains the displayed answer generator; the app does not append canned
  or extractive Manual text.
- Existing reviewed lesson goals, actions, warnings, aliases, and keywords are
  sufficient; no knowledge schema migration or new survival content is needed.
- Runtime validation accepts a broad 28–70-word grounded range so useful
  paraphrases are not rejected for superficial formatting differences.
- Package trust, offline privacy, Expert locking, and unrelated product areas
  remain unchanged.

## Decision Log

1. Chose a compact paragraph over ordered UI steps or 70–110-word guidance.
2. Chose 160 output tokens over retaining 128 or increasing to 192.
3. Apply added depth only to grounded survival guidance.
4. Route vague survival requests to a Gemma-generated clarification with no
   Manual link.
5. Chose evidence-rich prompting with the existing compact `a/e` envelope over
   prompt-only expansion or a more fragile structured step schema.
6. Keep strict JSON, leakage, completion, and evidence validation while making
   warning/action coverage an evaluation metric rather than a runtime reject.

## Final Design

Retrieval enriches each selected passage from its reviewed lesson: goal,
three actions, first warning, aliases, and keywords. A specificity check uses
those intent terms plus explicit high-signal survival terms to distinguish a
grounded request from a generic clarification request. Lite continues to use
only the current question, explicit domain, and current OCR.

`ModelPromptPurpose` adds `clarification`. Grounded prompts receive up to two
compact reviewed briefings and target a 35–55-word paragraph. Clarification
prompts target 18–45 words, ask for concrete observations, remind the user to
restate the complete situation, and require `e=[]`. Ordinary prompts stay
short. The shared JSON grammar allows up to 440 answer characters, and Lite’s
output cap becomes 160 tokens.

Grounded output is accepted at 28–70 words and one to four complete sentences.
Clarification output requires a direct request for observations, no named
procedure, and no evidence. Existing
leakage, index, completion, one-repair, runtime-failure, and no-extractive-
fallback behavior remains. Evaluation reports target-length, action, warning,
first-pass, repair, leakage, and false-link metrics separately.

## Measured implementation evidence — 2026-08-09

- Repository validation passes with 10 chapters, 70 lessons, 1,050 passages,
  and 121 Swift tests; all 121 Swift tests pass.
- The generic iOS simulator build-for-testing passes, as do the focused
  four-tab/model-required UI flows on the iPhone 17 simulator.
- Signed Gemma package `model-lite-gemma3-1b-q4km-dev@1.1.0` contains the exact
  pinned 806,058,240-byte Q4_K_M artifact and `maximum_output_tokens=160`; the
  Swift package checker passes its full verification/install/activation gate.
- The 16-case native evaluator compiles and uses the production prompt,
  grammar, 160-token limit, one-repair policy, and requested usefulness metrics.
  Generation results are not claimed because pinned b9637 CLI executables are
  not installed on this Mac.
- The signed `1.1.0` package installed and activated on the physical iPhone 13;
  `/tmp/AuroraSubstantivePackageInstall.xcresult` records that pass.
- Exploratory physical generation produced validator-accepted grounded answers
  for bleeding, water, lost, and bear prompts before the stuck-vehicle prompt
  failed closed. That exploratory run has no retained result bundle and is not
  promoted to release acceptance evidence.
- The retained generic-car clarification test exhausted its single repair and
  displayed the incomplete-answer terminal response. It exposed no procedure
  or Manual link, but did not satisfy the clarification-copy acceptance check;
  see `/tmp/AuroraSubstantivePhysical/Logs/Test/Test-Aurora-2026.08.09_23-26-20-+0800.xcresult`.
- Two attempts to rerun the final five-domain test on the unlocked phone ended
  before launch with Xcode `DebuggerVersionStore.StoreError`; no final model
  result is claimed. Current-contract TTFT, throughput, completion time, repair
  latency, and thermal state were not instrumented, so the 80%/95% generation
  and physical performance targets remain unproven.
