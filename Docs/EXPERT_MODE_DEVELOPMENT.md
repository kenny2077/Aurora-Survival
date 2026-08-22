# Expert Mode Development

Expert is implemented as a development-only tier. Production remains locked
until the retained M2 iPad feasibility matrix, iPhone 17 Pro Max acceptance,
and human safety/legal review all pass.

## Pinned artifacts

- Runtime: llama.cpp `b9637`, commit
  `aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3`.
- Language model: `Qwen/Qwen3-VL-2B-Instruct-GGUF` revision
  `52d6c8ffea26cc873ac5ad116f8631268d7eb503`,
  `Qwen3VL-2B-Instruct-Q4_K_M.gguf`.
- Projector: the matching
  `mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf` from that revision.
- License identifier: `Apache-2.0`; release distribution still requires the
  repository's legal review gate.
- Embedder: `BAAI/bge-small-en-v1.5` revision
  `5c38ec7c405ec4b44b94cc5a9bb96e735b38267a`, 384 dimensions, Q8_0.

`Resources/Models/catalog.json` records exact byte counts and SHA-256 values.
`tools/prepare_expert_model_package.py` refuses any other files and requires
retained peak-memory values for all three context profiles before signing.

## Runtime activation

Run `tools/build_mtmd_xcframework.sh` to reproduce an mtmd-capable Apple
XCFramework from the pinned commit. The script verifies exported mtmd symbols
and places the ignored binary under
`Runtime/AuroraLlamaRuntime/Artifacts/llama.xcframework`. Swift Package
Manager uses that local binary when present; otherwise it uses the official
text-only b9637 binary and Expert fails closed.

The physical harness may bind Expert in Debug only when all of the following
hold:

1. the signed manifest and both artifacts verify;
2. model, projector, quantizations, revision, runtime, context, and output
   metadata exactly match the allowlist;
3. retained peak-memory values are present;
4. the runtime exports the pinned mtmd ABI; and
5. the projector initializes and reports vision support.

Release builds reject Expert packages regardless of those checks.
Ordinary Debug chat additionally requires
`TRAILGUARD_ENABLE_EXPERT_NORMAL_CHAT=1`; do not set it while retained physical
acceptance is failing.

## Behavior

- Adaptive profiles are 8,192/6,144/4,096 tokens with 1,024/768/512-pixel
  image bounds, 256 output tokens, 512 template tokens, and 768 MiB required
  memory headroom above the retained peak.
- Expert keeps only newest whole raw messages for the visible in-memory
  session. Lite receives no history and remains at 2,048 context tokens.
- Expert queries the corpus-v3 scenario FTS and signed BGE index containing 61
  scenarios, 545 promoted claims, and 79 canonical Survival Manual 2026 chunks.
  The manifest-discovered reviewed-claim sidecar consolidates overlapping water
  and food procedures while retaining source locators and corroboration edges.
- One bounded query is searched lexically and densely. Each channel contributes
  only its best rank per scenario, RRF `k=60` orders candidates, and an absolute
  multiword/cosine gate determines eligibility before any discovery boost. At most
  three scenarios and eight query-focused claims per scenario enter the prompt.
- Expert also queries a versioned shadow corpus containing 10 source-document
  records and 21 redistributable source chunks. External-content FTS matches can
  boost linked scenario candidates, but raw chunks never enter a high-risk evidence
  bundle or support a displayed sentence. Four extracted proposals remain isolated
  as unpromoted candidates pending independent critic and human approval.
- One hidden grammar-constrained Qwen inference selects `generalQuestion` or
  `survivalQuestion`. General turns skip Survival RAG. Survival turns use the
  absolute evidence gate and preserve `noRelevantEvidence` when no scenario passes.
- A newly attached photo bypasses intent classification and Survival RAG. Its
  bounded bytes and the exact visual question go directly to Qwen3-VL for one
  streamed native multimodal answer. Photo answers have no evidence, sources,
  Manual links, or verification metadata; full image bytes remain ephemeral.
- Text-only history can resolve intent but is never reviewed evidence. Only evidence
  records attributed by displayed text-only survival answers create Manual links.
- Every visible substantive Expert answer is authored by exactly one streamed Qwen
  answer completion. There is no answer repair, rewrite, semantic-verification, or
  deterministic procedural fallback. Structural decoding hides envelope/control
  text and resolves only citation indexes actually used by the model.
- Grounded survival answers show only cited accepted sources. Survival turns without
  eligible evidence remain survival turns but receive an unsourced conservative
  best-effort answer. General turns receive no survival evidence or source panel.
- Survival Manual 2026 citations use title plus required chapter/skill/paragraph
  locator; organization and URL are optional. Its AI-assisted/developer-reviewed
  provenance is disclosed in startup acknowledgment schema v2, not on source cards.
- Expert runtime errors and cancellation unload the runtime and suspend Expert
  for the lifetime of that assistant instance. No same-request Lite inference
  follows a failed Expert inference.

## Verification and remaining physical gates

The focused native-vision overhaul run completed all three approved cases on the
connected M2 iPad at nominal thermal state. Each photo used one answer call, zero
intent/RAG/repair calls, forwarded the image, streamed progressively, and returned
no sources, Manual links, or verification metadata. Total latencies were 6.182,
6.962, and 6.285 seconds at roughly 32 tokens/second. Qwen3-VL correctly recognized
the bow-drill instructional diagram and leaf-mimicking insect. Its muddy-water
advice was directionally safe but stated contamination more confidently than the
image alone establishes; this remains a quality caveat for broader vision review.
The immutable trace is
`Reports/expert-native-vision/expert-native-vision-r1.json`.

The Survival Manual 2026 corpus-v3 integration passed its final connected-M2-
iPad 20-prompt run: 20/20 route and safety checks, one hidden intent call plus
one streamed answer call per turn, zero repairs, zero leakage, zero false source
cards, and nominal thermal. Median total latency was 6.143 seconds. One bleeding
case measured 10.811 seconds, so the strict 10.2-second release maximum remains
open even though its generation quality was accepted for development.

```bash
rtk proxy swift test
rtk proxy swift build --package-path Runtime/AuroraLlamaRuntime
rtk proxy python3 tools/validate.py
rtk proxy xcodegen generate
rtk proxy xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AuroraExpertBuild CODE_SIGNING_ALLOWED=NO build-for-testing
```

The automated matrix retains the existing 200 Lite retrieval cases and adds an
generated 700-case Expert text regression set spanning all 70 base scenarios: direct language,
typos, observable cues, follow-ups, corrections, adversarial history, noisy OCR,
70 multi-topic incidents, 70 insufficient-evidence cases, and 70 low-risk cases.
Each record carries acceptable evidence, required claim kinds, forbidden claims,
risk, expected disposition, and internal reference guidance. Candidate recall must
be at least 98% overall, 100% for critical cases, with p95 below 150 ms. The prior
120-case sequence set remains as an orchestration regression, not proof of Qwen
grounding correctness.

The M2 iPad runtime feasibility gate passed nine fresh-process calibration
runs. Retained maxima are 1,650,658,088 bytes at 8K, 1,374,653,128 bytes at 6K,
and 1,125,927,408 bytes at 4K; every calibration run retained the required
headroom at nominal thermal state.

The retired fixed-hazard 120-case vision matrix completed without a crash, jetsam event,
or serious thermal state and stayed at or below 1,684,704,256 bytes peak.
Physical acceptance nevertheless failed: visual-result p95 was 19.34 seconds,
only 27 of 60 grounded responses met the full structural contract, five cases
exhausted the repair path, and the model produced repeatable critical safety
errors involving snake handling/venom certainty, food safety, tick infection
certainty, and invented navigation values. That classifier and its image-driven
RAG route are no longer production code. The retained historical summary is in
`Reports/expert-m2-ipad/summary-primary-partial.json`; Expert remains locked.

The physical runner now accepts `--cooldown-every` and `--cooldown-seconds`.
Its default policy unloads Expert and pauses for 60 seconds after every five
cases, then waits longer while the device reports fair thermal state; a
serious or critical state still aborts before the next inference. Each pause
is recorded in the retained report.

The accuracy-first model-authored recovery retained every rejected report. A
focused 20-case physical text gate ultimately passed 20/20 with Qwen-authored
answers, ten exact-match boundary overrides, four repairs, 5.7-second median
latency, 10.2-second maximum latency, and nominal thermal state. The corrected
first 30-case sequence batch then passed 30/30 including 10/10 critical cases.

The second 30-case batch still rejects the candidate. Its best retained run was
28/30, and the latest run was 26/30, with repeatable Qwen invention of unreviewed
fire-site distances and malformed repair prose despite explicit allowed-number
instructions. All 30 cases in that batch are critical. Batches three/four and
interruption, power, sustained-use, and battery scenarios therefore remain
deferred. Expert stays locked; do not weaken the numeric/provenance gate or
continue physical stress work until these repeatable final-answer failures are
resolved.

The shadow-corpus physical gate is retained under
`Reports/expert-m2-ipad/shadow-corpus-validator-repair-gate*.json`. The first run
passed 4/12 routes. Multi-topic boundary enforcement and non-anchoring repair
feedback raised the second run to 9/12 as originally reported; review found the
insufficient-evidence miss was report reconstruction rather than production routing,
so the effective result was 10/12. The remaining two critical cases safely hid
unsupported generation after repair. A tighter sentence-count experiment regressed
to 2/8 and was reverted; that run stopped correctly when thermal reached serious.
The 700-case, vision, multi-turn, interruption, and sustained matrices were not
started because the 12-case safety gate did not pass. Expert remains locked until a
cooled rerun achieves every gate criterion.

The subsequent cooled v4 gate completed nominal and passed 8/12; assessment,
combined bleeding/shock, EV damage, and fire extinguishing failed closed. A
placeholder-free compact response contract then fixed the repeatable
fire-extinguishing case in v5. That run passed 3/4 but stopped at the required
serious-thermal boundary. Its cloudy-water draft added a new unsupported conclusion;
the validator correctly rejected it, and the exact mutation is retained in Swift
tests. No later physical stage was started.
