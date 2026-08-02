# Lite model handoff

Updated: 2026-08-02

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
- Configuration: embedded Gemma chat template, 2,048-token context, 128-token
  maximum output, grammar-constrained greedy decoding, one generation at a time

The signed development package is
`.trailguard/development/model-lite-gemma3-1b-q4km-dev@1.0.0`. Development
trust is Debug-only. The release trust store remains empty until production
keys and hosting are approved.

## iPhone 13 evidence

The exact signed artifact is installed and active on the Kaiyi Guo Personal
Team iPhone 13. The model selects reviewed evidence; TrailGuard expands the
reviewed steps and renders the signed citation. Deterministic safety rules run
before the model and remain authoritative.

| Gate | Result | Evidence |
| --- | --- | --- |
| Grounded water answer | Pass: 4.376 s completion, 2.67 s cold TTFT, 14.0 tok/s, 9 tokens, thermal nominal, one source | `/tmp/TrailGuardGemmaDeterministicSafetyPhysical.xcresult` |
| Fuel-hazard model bypass | Pass: deterministic safety card, no native run | `/tmp/TrailGuardGemmaSafetyBypassPhysical.xcresult` |
| Apple Vision OCR to safety override | Pass | `/tmp/TrailGuardOCRSafetyPhysical.xcresult` |
| Lite + guide + both offline maps | Pass | `/tmp/TrailGuardGemmaSafetyCoexistencePhysical.xcresult` |
| Five consecutive answers | Pass: 4.431/3.396/2.424/2.470/2.462 s; fifth TTFT 1.35 s, 15.4 tok/s, thermal fair; one source on every answer | `/tmp/TrailGuardGemmaSustainedWarmPolicyPhysical.xcresult` |
| Optimized validation build | Pass: 4.493 s completion, 2.46 s cold TTFT, 14.4 tok/s, thermal fair | `/tmp/TrailGuardGemmaOptimizedPhysical.xcresult` |

The optimized validation build uses `-O` for Swift and size optimization for
C/C++ while retaining `DEBUG` solely for the development trust key. It is not a
shipping configuration and does not weaken production trust.

## Runtime details

The app keeps the verified model and Metal weights loaded but creates a fresh
llama context for each completion. This prevents conversation-to-conversation
KV state from leaking while avoiding repeated model loads. The bounded chat
transcript uses eager SwiftUI layout so every incident answer remains present
in the accessibility tree.

The model never authors final procedures. It emits a bounded evidence decision;
`GroundedResponseCodec` validates the identifiers and deterministically expands
only reviewed steps, warnings, risk, action, and citations. Any runtime,
package, evidence, power, or thermal rejection returns to Essential.

## Reproduce the package

```bash
hf download ggml-org/gemma-3-1b-it-GGUF \
  --revision f9c28bcd85737ffc5aef028638d3341d49869c27 \
  --include gemma-3-1b-it-Q4_K_M.gguf \
  --local-dir .trailguard/model-eval/models/gemma-3-1b-q4_k_m

shasum -a 256 \
  .trailguard/model-eval/models/gemma-3-1b-q4_k_m/gemma-3-1b-it-Q4_K_M.gguf

/tmp/trailguard-dev-venv/bin/python tools/prepare_lite_model_package.py \
  --model .trailguard/model-eval/models/gemma-3-1b-q4_k_m/gemma-3-1b-it-Q4_K_M.gguf \
  --terms .trailguard/model-eval/models/gemma-3-1b-q4_k_m/GEMMA_TERMS.md \
  --output .trailguard/development/model-lite-gemma3-1b-q4km-dev@1.0.0 \
  --private-key .trailguard/development/package-signing-key.pem \
  --key-id development-2026-07 \
  --created-at 2026-07-30T00:00:00Z

swift run trailguard-pack-check model \
  Resources/Packages/development_trusted_package_keys.json \
  .trailguard/development/model-lite-gemma3-1b-q4km-dev@1.0.0
```

## Remaining release gates

- True Airplane Mode termination/relaunch with Wi-Fi off
- Low Power Mode rejection to Essential
- Twenty- to thirty-minute battery, memory-pressure, and interruption run
- VoiceOver and largest Dynamic Type physical walkthrough
- Production signing/hosting, App Store configuration, and independent legal,
  safety, privacy, and human-factors sign-off

Do not describe a stopped catalog server as an Airplane Mode pass, and do not
describe Personal Team evidence as TestFlight or App Store approval.
