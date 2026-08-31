# Aurora Lite 256-Token iPhone 13 Handoff

## Objective

Finish the Lite-only experiment on the connected standard iPhone 13
(`D93DEDAA-E38F-5BDE-B05F-5FCC01D7E190`). Raise Lite generation from 160 to
256 tokens without changing its 2,048-token context, model weights, 4 GB device
gate, public interfaces, or Expert behavior. Do not use the connected iPad.

## Current State

Work stopped immediately when the user reached their usage limit. The changes
below are partial and **have not been built, tested, packaged, installed, or
physically exercised**. No model conversations were submitted in this
iteration, and nothing was committed.

The worktree was already dirty before this iteration. Preserve all existing
changes in `App/ChatView.swift`, the adaptive-language/precision-RAG pipeline,
and their tests. Do not reset, discard, or broadly reformat them.

Implemented so far:

- `LlamaRuntimeConfiguration.liteMaximumOutputTokens` and the maintained model
  catalog now use 256.
- The native bridge identifies Expert from the loaded context (`> 2048`) rather
  than treating every request above 160 output tokens as Expert.
- Lite grounded, single-evidence, and unlinked grammars allow up to 700 answer
  characters without punctuation or sentence-count enforcement.
- Lite prompts ask substantive answers to aim for 70–120 useful words, keep
  greetings brief, answer stable habitat/animal-behavior questions directly,
  and reserve live-data disclaimers for genuinely current/local requests.
- Lite package preparation defaults to version `1.3.0` and writes
  `maximum_output_tokens=256`; product-catalog and publisher inputs reference
  the new package/version.
- Runtime/catalog tests and repository validation expectations were updated to
  256. The native Lite evaluator was partially updated to the new ceiling and
  longer evaluation ranges.

## Required Review and Remaining Implementation

1. Review the current diff before editing. Separate the pre-existing dirty
   changes from the Lite-256 additions; preserve both.
2. Confirm the Swift multiline prompt interpolations compile and that the
   70–120-word guidance is present only for Lite substantive answers.
3. Finish auditing `tools/native_llama_lite_eval.py` for stale 160-token or old
   440-character/75-word assumptions.
4. Add a focused maximum-size Lite prompt test proving estimated prompt tokens
   plus the 256-token output reserve remain within the 2,048-token context.
5. Add/confirm regression coverage that equal Lite/Expert output ceilings still
   select their respective grammar and repetition-penalty behavior. The
   repository validator currently checks the native source contract, but the
   signed iPhone run must provide the integration proof.
6. Update the maintained Lite design documentation after behavior is verified.
7. Run `git diff --check`, focused Swift tests, the full Swift suite,
   `python3 tools/validate.py`, and
   `python3 tools/native_llama_lite_eval.py --contract-only`.
8. Regenerate the ignored Xcode project, run generated Xcode tests, and produce
   a signed build for the iPhone 13 only.

## Package Work

Create `.trailguard/development/model-lite-gemma3-1b-q4km-dev@1.3.0` from the
verified `1.2.0` package with `tools/prepare_lite_model_package.py`, the existing
development signing key, a new creation timestamp, and version `1.3.0`.

Before installation, verify:

- The GGUF remains exactly 806,058,240 bytes with SHA-256
  `8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135`.
- Only signed manifest metadata/version changed; package/model payload size did
  not increase.
- Metadata contains `context_tokens=2048`, `maximum_output_tokens=256`, and the
  existing shared-RAG package/contract identifiers.

Install and activate `1.3.0` on the iPhone without clearing Aurora's sandbox,
shared-RAG package, preferences, or conversations. Do not install or test it on
the iPad.

## Exact Physical Acceptance

Run exactly these two Lite conversations on the iPhone 13, once each and with
no retries:

1. `What is typical rabbit behavior in a forest?`
2. `How to build a shelter`

Capture exact answer text, source state, generated tokens, TTFT, total time,
throughput, thermal state, screenshot, and pre/peak/post memory for each turn.

Pass conditions:

- Rabbit behavior is direct and substantive, with no weather/location/live-data
  disclaimer and no source unless complete reviewed coverage genuinely passes.
- Shelter is approximately 70–120 useful words and displays
  `Survival Manual 2026`.
- Neither turn shows internal-format, retrieval, grounding, or retry notices.
- No jetsam, memory warning, runtime unload, or inference failure occurs.
- Peak Aurora footprint is below 1.6 GB, minimum process-available memory is at
  least 300 MB, and post-turn memory returns within 15% of the loaded baseline.

Leave the verified app open for manual review. Keep all changes uncommitted
unless the user explicitly requests a checkpoint.
