# Validation report

Date: 2026-08-02
Milestone: signed offline product system and Gemma Lite physical verification

## Current result

TrailGuard passes its structural validator and all 112 Swift tests. The exact
signed Gemma 3 1B IT Q4_K_M artifact is installed and active on a physical base
iPhone 13 together with reviewed guides and both Minnesota map sizes.

The model is an explanation/evidence-selection layer. Deterministic safety,
package verification, evidence allowlists, citations, and Essential fallback
remain authoritative.

## Automated gates

- Eight reviewed starter articles and eight signed source records validate.
- All 120 locked incident cases execute through `IncidentAssistant`.
- All 30 map/asset cases execute through map readiness.
- Twelve safety/refusal cases preserve safety-before-model behavior.
- Package envelopes reject invalid signatures, hashes, sizes, paths,
  compatibility, recalls, entitlements, and unsupported runtime configuration.
- SQLite FTS/vector packs build reproducibly and fail closed on corrupt or
  inapplicable evidence.
- The signed six-product catalog supports strict resumable downloads and atomic
  installation for Gemma, three reviewed guides, and two offline maps.
- The app and isolated llama.cpp bridge build for generic iOS Simulator and
  signed arm64 iOS device targets.
- Release resources exclude the development trust key.

Run:

```bash
python3 tools/validate.py
/tmp/trailguard-dev-venv/bin/python tools/test_pack_reproducibility.py
swift test
```

## Physical iPhone 13 gates

| Gate | Result | Evidence |
| --- | --- | --- |
| Grounded signed Gemma answer | Pass: 2.67 s cold TTFT, 14.0 tok/s, 9 tokens, nominal | `/tmp/TrailGuardGemmaDeterministicSafetyPhysical.xcresult` |
| Deterministic fuel-hazard bypass | Pass; no native run | `/tmp/TrailGuardGemmaSafetyBypassPhysical.xcresult` |
| Apple Vision OCR safety path | Pass | `/tmp/TrailGuardOCRSafetyPhysical.xcresult` |
| Twin Cities Scout rendering | Pass | `/tmp/TrailGuardTwinCitiesPhysicalUnlocked8.xcresult` |
| Minnesota guide/map rendering | Pass | `/tmp/TrailGuardMinnesotaGuidePhysical.xcresult` |
| Model/guide/map coexistence | Pass | `/tmp/TrailGuardGemmaSafetyCoexistencePhysical.xcresult` |
| Five consecutive grounded answers | Pass: final warm TTFT 1.35 s, 15.4 tok/s, thermal fair; no fallback/termination | `/tmp/TrailGuardGemmaSustainedWarmPolicyPhysical.xcresult` |
| Optimized validation build | Pass: 2.46 s cold TTFT, 14.4 tok/s, thermal fair | `/tmp/TrailGuardGemmaOptimizedPhysical.xcresult` |

Every generative answer in these gates uses the exact
`8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135`
artifact and renders exactly one reviewed offline source. The optimized build
retains Debug only for non-shipping development trust; production trust is not
weakened.

## Remaining limitations

No true Airplane Mode or Low Power Mode physical pass is claimed yet. A stopped
or unavailable catalog host is useful offline evidence but is not equivalent to
turning the device radios off. The 20–30 minute battery/memory/interruption run,
VoiceOver/largest Dynamic Type walkthrough, external OBD hardware, production
keys/hosting, App Store configuration, and independent legal/safety/privacy
sign-offs also remain open.

GitHub Actions cannot currently start because GitHub reports an account-level
billing/spending-limit issue; local validation is green but does not replace
the missing hosted CI record.
