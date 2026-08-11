# Lite model handoff

Updated: 2026-08-10

## Release decision

The iPhone 13 Lite candidate is **Gemma 3 1B IT Q4_K_M**. Phi-3.5 Mini is
retained only as rejected historical workstation evidence; it must not be
restored as the recommended iPhone 13 download. Qwen3 1.7B Q4_K_M remains a
hidden challenger and is not customer-facing.

Exact selected artifact:

- Repository: `ggml-org/gemma-3-1b-it-GGUF`
- Revision: `f9c28bcd85737ffc5aef028638d3341d49869c27`
- File: `gemma-3-1b-it-Q4_K_M.gguf`
- Bytes: `806,058,240`
- SHA-256: `8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135`
- Terms: Gemma Terms of Use plus the package Notice; final publication still
  requires human legal review
- Runtime: official llama.cpp `b9637` XCFramework with Metal
- Configuration: embedded Gemma chat template, 2,048-token context, 160-token
  maximum output, grammar-constrained greedy decoding, one generation at a time

The signed development package is
`.trailguard/development/model-lite-gemma3-1b-q4km-dev@1.1.0`. Development
trust is Debug-only. The release trust store remains empty until production
keys and hosting are approved.

## iPhone 13 evidence

The exact signed artifact is installed and active on the Kaiyi Guo Personal
Team iPhone 13. Historical performance evidence predates the current stateless
Lite prompt contract. Current functional acceptance is listed separately and
does not claim new performance measurements.

| Gate | Result | Evidence |
| --- | --- | --- |
| Grounded water answer | Pass: 4.376 s completion, 2.67 s cold TTFT, 14.0 tok/s, 9 tokens, thermal nominal, one source | `/tmp/AuroraGemmaDeterministicSafetyPhysical.xcresult` |
| Historical fuel-hazard control path | Superseded by Lite Chat architecture | `/tmp/AuroraGemmaSafetyBypassPhysical.xcresult` |
| Historical Apple Vision OCR path | Superseded; rerun with Lite Chat | `/tmp/AuroraOCRSafetyPhysical.xcresult` |
| Lite + guide + both offline maps | Pass | `/tmp/AuroraGemmaSafetyCoexistencePhysical.xcresult` |
| Five consecutive answers | Pass: 4.431/3.396/2.424/2.470/2.462 s; fifth TTFT 1.35 s, 15.4 tok/s, thermal fair; one source on every answer | `/tmp/AuroraGemmaSustainedWarmPolicyPhysical.xcresult` |
| Optimized validation build | Pass: 4.493 s completion, 2.46 s cold TTFT, 14.4 tok/s, thermal fair | `/tmp/AuroraGemmaOptimizedPhysical.xcresult` |

Current stateless Lite functional evidence:

| Gate | Result | Evidence |
| --- | --- | --- |
| Exact grounded Manual navigation | Pass: “Where can I find water?” generated a grounded answer and opened “Locate Likely Water” | `/tmp/AuroraStatelessLitePhysical-exact-link.xcresult` |
| Stale-topic sequence | Pass: water answer followed by “How are you doing?” produced an ordinary greeting with no Manual link or water advice | `/tmp/AuroraStatelessLitePhysical-retry.xcresult` |
| Conditional repair failure | Pass: “How do I make water safer?” remained invalid after the single repair and showed the incomplete-answer terminal response with no link | `/tmp/AuroraStatelessLitePhysical-link-retry.xcresult` |
| Signed substantive package install | Pass: `model-lite-gemma3-1b-q4km-dev@1.1.0` installed and activated with the 160-token manifest | `/tmp/AuroraSubstantivePackageInstall.xcresult` |
| Generic car clarification | Safe failure: both generations were rejected and no procedure or Manual link appeared; the expected clarification copy was not produced | `/tmp/AuroraSubstantivePhysical/Logs/Test/Test-Aurora-2026.08.09_23-26-20-+0800.xcresult` |
| Substantive five-domain acceptance | Not passed: an exploratory run accepted bleeding, water, lost, and bear before stuck-vehicle failure, but retained final reruns did not launch because of Xcode `DebuggerVersionStore.StoreError` | — |
| Current TTFT/throughput/thermal | Not measured in this run; historical figures above are not transferred to the new contract | — |

Database-first incident contract:

| Gate | Result | Evidence |
| --- | --- | --- |
| Database-first routing and fallback validation | Pass: 126 Swift tests cover tire/tyre/puncture, bleed/bleeding/blood loss/hemorrhage, generic car fallback, intoxication fallback, statelessness, role reversal, length limits, repair, and false-link prevention | `swift test` on 2026-08-10 |
| Simulator build and focused shell flows | Pass | `/tmp/AuroraDatabaseFirstBuild`, `/tmp/AuroraDatabaseFirstSimulator` |
| Native 16-case generation | Blocked: pinned b9637 `llama-completion` is absent | — |
| Physical five-grounded/five-fallback matrix | Blocked before inference: UI test runner killed during launch; retry hit `DebuggerVersionStore.StoreError` | `/tmp/AuroraDatabaseFirstPhysicalRetry.xcresult` |

The optimized validation build uses `-O` for Swift and size optimization for
C/C++ while retaining `DEBUG` solely for the development trust key. It is not a
shipping configuration and does not weaken production trust.

## Runtime details

The app keeps the verified model and Metal weights loaded but creates a fresh
llama context for each completion. Lite also excludes prior turns at the app,
retrieval, and prompt boundaries. Every Lite message queries the Manual: a
specific normalized lesson match uses the grounded contract, while no match
uses the model-only incident fallback with `e=[]` and no Manual link. Expert
retains a bounded-history interface
for later work but is not enabled or changed by this repair. The visible chat
transcript remains UI-only for Lite.

The model emits compact JSON containing a natural answer plus at most two
evidence indexes. `GroundedResponseCodec` validates completion, control-text
leakage, prompt purpose, uniqueness, and index range before resolving exact
Field Manual destinations. A decoding or quality failure receives one repair
inference with no failed output in its prompt. Backend/load failures do not
retry, and no canned or extractive answer is presented as Gemma output.

## Reproduce the package

```bash
hf download ggml-org/gemma-3-1b-it-GGUF \
  --revision f9c28bcd85737ffc5aef028638d3341d49869c27 \
  --include gemma-3-1b-it-Q4_K_M.gguf \
  --local-dir .trailguard/model-eval/models/gemma-3-1b-q4_k_m

shasum -a 256 \
  .trailguard/model-eval/models/gemma-3-1b-q4_k_m/gemma-3-1b-it-Q4_K_M.gguf

python3 tools/prepare_lite_model_package.py \
  --model .trailguard/model-eval/models/gemma-3-1b-q4_k_m/gemma-3-1b-it-Q4_K_M.gguf \
  --terms .trailguard/model-eval/models/gemma-3-1b-q4_k_m/GEMMA_TERMS.md \
  --output .trailguard/development/model-lite-gemma3-1b-q4km-dev@1.1.0 \
  --private-key .trailguard/development/package-signing-key.pem \
  --key-id development-2026-07 \
  --version 1.1.0 \
  --created-at 2026-08-09T14:40:00Z

swift run trailguard-pack-check model \
  Resources/Packages/development_trusted_package_keys.json \
  .trailguard/development/model-lite-gemma3-1b-q4km-dev@1.1.0
```

## Remaining release gates

- True Airplane Mode termination/relaunch with Wi-Fi off
- Low Power Mode Expert-to-Lite degradation and no-model unavailability
- Twenty- to thirty-minute battery, memory-pressure, and interruption run
- VoiceOver and largest Dynamic Type physical walkthrough
- Production signing/hosting, App Store configuration, and independent legal,
  safety, privacy, and human-factors sign-off

Do not describe a stopped catalog server as an Airplane Mode pass, and do not
describe Personal Team evidence as TestFlight or App Store approval.
