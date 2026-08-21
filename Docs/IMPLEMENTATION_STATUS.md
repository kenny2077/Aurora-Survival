# Implementation status

Updated: 2026-08-15

## Implemented and verified

- Universal iPhone/iPad shell with independent **Ask · Manual · Maps · Tools** navigation roots.
- Exactly two customer-facing model tiers: Lite and Expert (`vision_expert` wire value), plus Auto/Lite/Expert preference and legacy preference migration.
- No-model Ask setup state, frozen stateless Lite policy, and a development-only Expert path with turn-resolved history, direct retrieval-to-Qwen RAG, adaptive context, and fail-closed vision activation.
- Unified wilderness Manual database with 10 direct chapters, exactly 70 reviewed action cards, 1,050 frozen Lite passages, plus 72 Expert scenarios and 460 production vector records. The separate 100,000-row fixture measures capacity only. Discovery text can boost retrieval but cannot authorize high-risk prose.
- All 828 former corpus IDs have an explicit reviewed redirect or retired-passage disposition; the former single-book database and presentation overlay are no longer shipped.
- Dedicated Maps browser/download manager and focused Tools model center with prominent Lite/Expert cards and signed-catalog controls.
- Signed package/catalog verification, exact hashes and sizes, strict range resume, staging, atomic activation, rollback, recall, cached entitlements, and Incident-mode network denial.
- Pinned llama.cpp `b9637` runtime, supported Gemma 3 1B Lite artifact, and reproducible mtmd-capable Expert XCFramework tooling pinned to commit `aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3`.
- Retired readiness, trip sheet, vehicle profile/applicability, OBD, standalone status, duplicate model settings, in-app SOS, and chat Clear controls removed from product state and navigation.
- Repository validator passes; 200 Swift tests pass, including the frozen 200-query Lite benchmark, generated 700-case Expert regression set, separately authored direct-RAG holdout, shadow-corpus licensing/promotion boundaries, claim-aware validation, and direct 120-case orchestration regression; simulator and connected M2 iPad builds pass.

## Current hardware position

- iPhone 13 is the Lite acceptance target.
- iPad Pro M2 and iPhone 17 Pro Max are Expert target classes, but names do not override live capability checks.
- Expert remains production-locked. Debug activation requires the exact signed Qwen3-VL 2B Q4_K_M/Q8_0 pair, retained peak-memory metadata, exported mtmd symbols, and successful projector initialization. Every Expert answer is Qwen-authored; deterministic logic only constrains retrieval, intent safety, provenance, format, and Manual links.
- Existing physical Gemma Lite performance evidence remains relevant to the artifact/runtime, but each changed product flow is rerun and recorded in `FIELD_MANUAL_PROGRESS_REPORT.md`.

## Remaining before release

1. Let the M2 iPad return from serious to nominal thermal, then resume only the retained 12-case Expert gate. The latest complete run passed 8/12; the follow-up passed 3/4 and physically fixed fire-extinguishing before thermal forced a stop. Do not begin the 700/vision/multi-turn/sustained matrix until all 12 pass.
2. iPhone 17 Pro Max physical inference evidence; that hardware is not currently available.
3. True Airplane Mode and Low Power Mode journeys, plus sustained battery, memory-pressure, thermal, and interruption coverage.
4. Full VoiceOver traversal and production trust/hosting/App Store configuration.
5. Human safety, accessibility, legal, licensing, localization, and publication review.

Cloud inference, accounts, analytics, background tracking, duplicate SOS, vehicle diagnostics, and destructive cleanup of retired local files are outside the product contract.
