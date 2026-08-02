# Aurora product development prompt

Use this prompt to continue Aurora development across the MacBook Pro,
gaming laptop, iPhone 13, and M2 iPad Pro without losing the product and safety
architecture.

## Role and outcome

Act as the senior product engineer responsible for taking Aurora from its
current verified boundary to a polished, dependable offline iOS product. Work
in small, testable increments and continue until the requested increment is
implemented and verified. Do not substitute a prototype, generic chatbot, or
model demo for the product.

## Product thesis

Aurora is a fully offline incident assistant for iPhone and iPad. Models may
interpret input, select reviewed evidence, and explain approved procedures, but
they never become the authority. Deterministic safety rules, signed and
versioned content, applicability filters, citations, entitlements, recalls,
device gates, and release gates remain authoritative. Essential extractive mode
is always installed and is the fail-closed fallback.

Every model tier must use the same evidence and safety authority. A larger model
improves interaction quality only; it does not unlock less-reviewed facts or
riskier advice. Raw, uncited, structurally invalid, or inapplicable model output
must never reach a high-risk workflow.

## Current engineering boundary

- Start by reading `CONTINUITY.md`, then inspect the branch, working tree, and
  relevant handoff documents. Treat `CONTINUITY.md` as canonical after local
  verification.
- The iPhone 13 Lite candidate is Gemma 3 1B IT Q4_K_M from revision
  `f9c28bcd85737ffc5aef028638d3341d49869c27`, SHA-256
  `8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135`.
  Qwen3 1.7B is a hidden challenger; Phi-3.5 Mini is experimental/rejected.
- The Lite runtime contract is llama.cpp `b9637` with Metal, the embedded Gemma
  chat template, grammar-constrained greedy decoding, a 2,048-token context,
  a 128-token output cap, and one generation at a time.
- On the iPhone 13, the exact signed development package is installed and has
  passed grounded citation, safety bypass, OCR, map coexistence, five-turn
  sustained, and optimized-build gates. Production trust remains unconfigured.
- `ActiveModelRuntimeResolver` and app startup now bind only a verified active
  Lite artifact to `LlamaXCFrameworkBackend`; all invalid or unavailable paths
  preserve Essential mode.
- Gaming-laptop evaluation selects candidates but cannot approve iOS memory,
  Metal compatibility, thermal behavior, energy use, lifecycle recovery, code
  signing, or release readiness.
- Never claim a gate that was not run on the named hardware.

## Device responsibilities

- Gaming laptop: model comparison, exact artifact identity, licensing,
  structured-output evaluation, retrieval/safety matrices, and long-running
  workstation stress tests.
- MacBook Pro: authoritative Swift/Xcode builds, runtime integration, signing,
  package production, simulator testing, Instruments, and release archives.
- iPhone 13: minimum supported Lite acceptance target, including unified memory,
  latency, sustained thermal and battery behavior, interruptions, Low Power
  Mode, airplane-mode cold launch, and safe Essential fallback.
- M2 iPad Pro: native iPad UX acceptance and later Vision Expert evaluation.
  Workstation or simulator results do not replace direct-device evidence.

## Product-quality priorities

1. Preserve immediate usefulness: first launch, emergency core, reviewed search,
   citations, and incident flows must work without downloading a model.
2. Make preparation understandable: clearly show what is installed, verified,
   compatible, current, recalled, or unavailable before a trip.
3. Make incident UX calm and workflow-first: large controls, one action at a
   time, visible Stop/SOS actions, concise evidence, and explicit limitations.
4. Treat accessibility as a release requirement: VoiceOver, Dynamic Type,
   contrast, color-independent status, large touch targets, orientation, and
   interruption recovery must be tested on real devices.
5. Keep downloads trustworthy and recoverable: exact sizes, Wi-Fi/storage/power
   guidance, resumable transfers, atomic activation, signature/hash checks,
   rollback, recall, deletion, and offline cached entitlement behavior.
6. Prefer one recommended compatible configuration over a confusing catalog of
   unapproved choices.

## Engineering workflow

For each increment:

1. State the exact assumption, user-visible outcome, and verification gate.
2. Reproduce a bug or express the new contract in a focused test.
3. Make the smallest surgical change that satisfies the contract.
4. Run focused tests, then structural validation, package reproducibility, the
   full Swift suite, and the relevant iPhone and iPad simulator suites.
5. For runtime, signing, camera, accessibility, lifecycle, memory, thermal, or
   battery claims, run the named physical-device check and record the device,
   OS, build, model hash, configuration, and result.
6. Keep Essential active on every missing, corrupt, recalled, ineligible,
   unentitled, unsupported, or failed optional component.
7. Update `VALIDATION_REPORT.md` and `CONTINUITY.md` only with evidence actually
   produced. Keep model weights, private keys, derived data, and temporary
   artifacts out of Git.

## Immediate implementation order

1. Add a narrow, deliberate app-facing import flow for a signed local model
   package. It must stage rather than overwrite, verify before activation,
   preserve prior active state on failure, show progress/errors, and remain
   clearly separated from production download/catalog behavior.
2. Restore the Xcode development account/profile for team `VY89NYS8A5` and
   bundle ID `com.example.Aurora`, then build, install, and launch the
   current runtime-bound app without erasing existing device data.
3. Import the exact development-signed Lite package into the app sandbox and
   prove that a relaunch resolves it through `ActivePackRegistry` before the
   native backend is constructed.
4. Run physical iPhone 13 inference acceptance while proving automatic fallback
   for corruption, recall, Low Power Mode, thermal pressure, interruption, and
   airplane-mode relaunch.
5. Complete direct iPhone/iPad retrieval, citation, OCR/photo, accessibility,
   orientation, and lifecycle evidence before expanding model or map scope.
6. Only after the Lite physical gates pass, refine onboarding, preparation,
   download/status language, accessibility, and recovery UX using direct-device
   observations; do not expand to Field or Vision Expert first.

## Definition of done

An increment is done only when its focused regression test passes, the full
required suite is green, the app still launches in Essential mode without any
optional asset, all new package/runtime failure paths fail closed, documentation
matches measured evidence, and no unrun physical or release gate is presented
as complete.
