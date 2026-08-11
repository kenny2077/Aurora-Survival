# Lite Stateless Chat Repair

> Historical baseline: the 128-token and short grounded-answer limits in this
> decision were superseded on 2026-08-09 by
> `LITE_SUBSTANTIVE_ANSWERS.md`. Statelessness, retry, and failure behavior
> remain current.

## Understanding

- Lite must maximize Gemma 3 1B answer quality inside the existing iPhone 13 memory envelope.
- Every Lite question is independent: prior visible chat remains UI history but is excluded from retrieval and inference.
- Gemma remains the answer generator; the app must not disguise canned or extractive text as model output.
- Reviewed Field Manual passages remain the only grounding source for survival procedures and exact Manual links.
- Invalid generated output may receive one shorter repair attempt; runtime failures must not be retried as output failures.
- The persistent “Fully offline · Gemma + Field Manual” chat banner is removed.
- Expert may use bounded history later, but Expert enablement or redesign is out of scope.

## Assumptions and constraints

- Keep the signed Gemma 3 1B Q4_K_M artifact, 2,048-token context, 128-token output, grammar-constrained greedy decoding, and one generation at a time.
- Keep questions, OCR, retrieval, prompts, and inference fully offline.
- Ordinary Lite turns cite no Manual evidence; grounded Lite turns require one or two validated evidence indexes.
- A second generation is exceptional and occurs only after syntactically or semantically invalid model output.
- Existing unrelated worktree changes must be preserved.

## Decision log

1. **Fully stateless Lite** was chosen over selective or four-turn history to prevent stale topic contamination and reserve context for the current question.
2. **Tier-aware compact prompts with one repair attempt** were chosen over a minimal history deletion because the observed failures also include instruction leakage and malformed output.
3. **The existing answer/evidence JSON envelope remains** instead of redesigning the native protocol, preserving the current citation and safety boundary.
4. **No extractive fallback** was chosen so every displayed answer carrying a model badge is genuinely model-generated.
5. **Expert history is deferred** so this repair does not broaden the unvalidated Expert scope.

## Final design

Lite requests carry no conversation history. Retrieval eligibility and queries use only the current question, explicit domain, and current OCR. Prompt construction selects a compact ordinary or grounded contract, plus an initial or repair attempt. Swift validates the compact JSON, answer completeness, prompt-control leakage, and evidence policy. Decoder or quality failures receive one fresh-context repair call using the same current input and evidence but not the failed output. Runtime failures return immediately with separate copy. Routine ready-state notices are suppressed because the model badge already conveys the active tier.

Regression coverage reproduces casual turns after car/water guidance, independent injury routing, malformed and leaked generations, retry limits, runtime failure handling, prompt size/content, banner removal, and exact Manual links. Final acceptance uses the exact signed Gemma package on the physical iPhone 13 and records first-pass and retry performance separately.

## Verification — 2026-08-09

- Repository validation passed; all 117 Swift tests passed; generic simulator
  build-for-testing and two focused simulator UI flows passed.
- Physical iPhone 13 exact navigation passed for “Where can I find water?” and
  opened “Locate Likely Water.”
- Physical water → “How are you doing?” passed with an ordinary Gemma greeting,
  no stale water advice, no Manual link, no prompt leakage, and no banner.
- Physical “How do I make water safer?” exhausted the one repair attempt and
  correctly returned the incomplete-answer terminal response without a link.
- The exact Gemma artifact checksum and nine-case evaluator contract smoke
  passed. Native evaluator generation remains pending because the pinned b9637
  command-line executable is not installed on this Mac.
- Current-contract TTFT, throughput, retry latency, and thermal impact were not
  instrumented and remain open; no historical number was reused.
