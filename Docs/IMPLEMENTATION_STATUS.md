# Implementation status

Updated: 2026-08-09

## Implemented and verified

- Universal iPhone/iPad shell with independent **Ask · Manual · Maps · Tools** navigation roots.
- Exactly two customer-facing model tiers: Lite and Expert (`vision_expert` wire value), plus Auto/Lite/Expert preference and legacy preference migration.
- No-model Ask setup state, Lite-only text/photo policy, Expert validation lock, and Expert-to-Lite degradation under eligibility or runtime failure.
- Unified wilderness Manual database with 10 direct chapters, exactly 70 reviewed action cards, 1,050 weighted FTS5 passages, a generated emergency fallback, and exact stable chat links.
- All 828 former corpus IDs have an explicit reviewed redirect or retired-passage disposition; the former single-book database and presentation overlay are no longer shipped.
- Dedicated Maps browser/download manager and focused Tools model center with prominent Lite/Expert cards and signed-catalog controls.
- Signed package/catalog verification, exact hashes and sizes, strict range resume, staging, atomic activation, rollback, recall, cached entitlements, and Incident-mode network denial.
- Pinned llama.cpp `b9637` runtime and supported Gemma 3 1B Lite artifact.
- Retired readiness, trip sheet, vehicle profile/applicability, OBD, standalone status, duplicate model settings, in-app SOS, and chat Clear controls removed from product state and navigation.
- Repository validator passes; 107 Swift tests pass, including the balanced 200-query recall benchmark; the generic simulator app build passes.

## Current hardware position

- iPhone 13 is the Lite acceptance target.
- iPad Pro M2 and iPhone 17 Pro Max are Expert target classes, but names do not override live capability checks.
- Expert remains validation-locked because the native backend does not yet accept image input through an approved mtmd model/projector integration.
- Existing physical Gemma Lite performance evidence remains relevant to the artifact/runtime, but each changed product flow is rerun and recorded in `FIELD_MANUAL_PROGRESS_REPORT.md`.

## Remaining before release

1. Approved signed Expert model and projector, mtmd runtime binding, and real vision acceptance on target hardware.
2. iPhone 17 Pro Max physical inference evidence; that hardware is not currently available.
3. True Airplane Mode and Low Power Mode journeys, plus sustained battery, memory-pressure, thermal, and interruption coverage.
4. Full VoiceOver traversal and production trust/hosting/App Store configuration.
5. Human safety, accessibility, legal, licensing, localization, and publication review.

Cloud inference, accounts, analytics, background tracking, duplicate SOS, vehicle diagnostics, and destructive cleanup of retired local files are outside the product contract.
