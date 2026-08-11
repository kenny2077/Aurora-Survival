# Lite Chat and Field Manual case

## Claim

TrailGuard provides a database-first offline incident path. Every Lite message
queries the bundled SQLite Manual. A specific reviewed match grounds Gemma with
up to two lessons and creates exact Manual links; an unmatched message uses a
model-only Gemma incident fallback with no Manual link.

## Implemented evidence

- The versioned knowledge database checksum and schema are verified before use.
- SQLite contains 10 chapters, 70 lessons, and 1,050 indexed passage records.
- Chat retrieval is capped at two reviewed passages of at most 120 words each.
- Lite retrieval and inference use only the current message, explicit domain,
  and current OCR observations; the visible transcript is UI-only.
- The compact model envelope contains only a natural answer and selected
  evidence indexes.
- Invalid, duplicate, missing, or incident-fallback indexes cannot create manual
  links. Invalid generated output receives one repair inference; runtime
  failures do not retry.
- The Manual tab reads the same SQLite rows and supports stable passage anchors
  plus reviewed redirects or retirement states for all 828 former chunk IDs.
- Incident-fallback answers require `e=[]` and show no Manual link.
- Questions, OCR observations, retrieval, inference, and reading stay offline.
- The persistent offline/Manual banner and routine ready notices are absent;
  the Lite badge remains on generated answers.

## Measured acceptance — 2026-08-10

- Repository validation and all 126 Swift tests pass. New regressions verify
  database-first routing for `flat tire`, `tyre`, `puncture`, `bleed`, blood
  loss, and hemorrhage; generic car and intoxication requests use fallback;
  smart-apostrophe role reversal and fallback evidence are rejected.
- The generic simulator build-for-testing and two focused iPhone 17 simulator
  UI flows pass. The 16-case evaluator compiles with only the production
  grounded/incident-fallback Lite purposes.
- Native generation remains blocked because the pinned b9637
  `llama-completion` executable is absent.
- `/tmp/TrailGuardDatabaseFirstPhysicalRetry.xcresult` records a physical test
  runner kill while waiting for the composer, before inference. A smaller
  retry then hit Xcode `DebuggerVersionStore.StoreError`. No database-first
  device-generation or performance pass is claimed.

## Superseded physical evidence — 2026-08-09

- Repository validation passed and all 121 Swift tests passed. The substantive
  contract adds regressions for full lesson actions/warnings, 28–70-word
  validation, clarification routing, stateless sequences, repair behavior, and
  false Manual-link prevention.
- Two focused simulator UI flows passed on an iPhone 17 simulator.
- The signed Gemma 3 1B Q4_K_M development package `1.1.0` was rebuilt with the
  160-token metadata contract and passed signature, install, activation,
  registry, and runtime-gate verification. The signed package also installed
  and activated on the physical iPhone 13; the retained result is
  `/tmp/TrailGuardSubstantivePackageInstall.xcresult`.
- On the signed Gemma package on the physical iPhone 13, “Where can I find
  water?” generated a grounded answer and opened the exact “Locate Likely
  Water” Manual destination.
- The former ordinary greeting behavior is superseded; Lite now uses the
  incident-assistant fallback for every unmatched message.
- “How do I make water safer?” produced invalid output on both allowed attempts;
  the app displayed the distinct incomplete-answer terminal response and did
  not fabricate a Manual link. This is an accepted measured Gemma 3 1B deficit.
- TTFT, throughput, retry latency, and thermal impact were not instrumented in
  this run; earlier performance figures do not prove the new prompt contract.
- Exploratory substantive generation yielded accepted bleeding, water, lost,
  and bear answers before the stuck-vehicle case failed closed, but that run
  has no retained result bundle and is not release evidence. A retained generic
  car test also failed closed without a procedure or false link, rather than
  producing an accepted clarification.
- A final unlocked-phone rerun did not launch because Xcode twice reported
  `DebuggerVersionStore.StoreError`. Native 16-case generation also remains
  pending because this Mac lacks the pinned b9637 `llama-cli`/`llama-bench`.
  The substantive physical acceptance and 80%/95% generation targets therefore
  remain open.

## Remaining release evidence

- Rerun physical iPhone 13 OCR, Airplane Mode, Low Power Mode, sustained
  battery/memory, VoiceOver, and Dynamic Type; instrument current-contract
  TTFT, throughput, retry latency, and thermal impact.
- Complete production trust, hosting, licensing, privacy, accessibility, and
  independent content review.
- Do not market the prototype as replacing emergency services, a clinician, a
  mechanic, an owner manual, or trained rescue.
