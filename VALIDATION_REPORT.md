# Validation report

Date: 2026-08-11
Milestone: Aurora 1.0.0 release freeze

## Current result

Aurora passes repository validation, all 135 Swift tests, the production
Gemma prompt/grammar contract check, a generic simulator test build, and a newly
signed arm64 build for the connected iPhone 13. The user also reports successful
manual physical-iPhone testing across several prompts and scenarios.

| Gate | Result | Evidence |
| --- | --- | --- |
| Deterministic knowledge validation | Pass: 10 chapters, 70 lessons, 1,050 passages, 12 primary sources, 828 legacy dispositions | `python3 tools/validate.py` |
| Swift package suite | Pass, 135/135 | `swift test` |
| 200-query retrieval benchmark | Pass: ≥90% overall and ≥95% critical top-two recall gates | `SurvivalKnowledgeTests` |
| Native Gemma contract | Pass: 2,048-token context, 160-token output, grounded and unlinked grammars | `python3 tools/native_llama_lite_eval.py --contract-only` |
| Generic simulator test build | Pass | `/tmp/AuroraRelease100Simulator` |
| Signed iPhone 13 build | Pass: Apple Development arm64 build | `/tmp/AuroraRelease100Physical` |
| Focused simulator journeys | Pass, 6/6 across corrected final runs | `/tmp/AuroraKnowledgeSimulator-20260809-1827.xcresult`; `/tmp/AuroraKnowledgeSimulatorManual-20260809-1829.xcresult` |
| Physical iPhone 13 shell and Manual | Pass, 2/2 | `/tmp/AuroraKnowledgePhysicalShellManual-20260809-1847.xcresult` |
| Physical iPhone 13 Lite exact citation | Pass, 1/1 | `/tmp/AuroraKnowledgePhysicalFinal-20260809-1846.xcresult` |

The database checksum, schema mismatch, emergency fallback, lesson structure, safety lint, source attribution, legacy redirects/retirements, exact Manual anchors, prompt limits, typo handling, and plain-language water retrieval all have automated coverage.

## Open gates

- The interrupted automated 40-case physical Lite stress matrix is not release
  evidence; no aggregate usefulness, repair-rate, or current-contract thermal
  claim is made from its partial report.
- Independent content, medical, legal, licensing, and accessibility SME approval.
- Physical signpost evidence for Manual under one second and local search p95 below 300 ms; functional and development-Mac latency gates pass.
- True Airplane Mode, Low Power Mode, sustained battery/memory/thermal tests, and full VoiceOver traversal.
- Physical M2 iPad Pro and iPhone 17 Pro Max acceptance; Expert vision remains validation-locked.

See `Docs/FIELD_MANUAL_PROGRESS_REPORT.md` for migration details, UI findings, source-review status, and blockers.
