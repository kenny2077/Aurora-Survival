# Implementation status

Updated: 2026-07-23

## Complete in this milestone

- [x] SwiftUI iPhone application shell
- [x] Offline starter guide and source UI
- [x] Incident chat orchestration
- [x] Critical-hazard deterministic override
- [x] Offline retrieval and domain filtering
- [x] Citation-range validation
- [x] Extractive no-model fallback
- [x] Essential / Field / Vision Expert contract
- [x] Dynamic vision capability routing
- [x] Offline OCR for all tiers
- [x] Grounded runtime prompt builder
- [x] Model-runtime adapter seam
- [x] Readiness and zero-power UX
- [x] Unit-test suite and structural validation
- [x] Ed25519 package-envelope verification
- [x] SHA-256, file-size, duplicate-path, and path-traversal checks
- [x] Atomic package activation, rollback, and inactive cleanup
- [x] Download transport boundary and staging cleanup
- [x] Exact vehicle identity and wrong-vehicle exclusion
- [x] Map coverage, detail, age, file, and routing readiness
- [x] Whitelist-only OBD commands and response parsing
- [x] llama.cpp text/vision backend contract
- [x] Locked safety and forbidden-OBD fixtures
- [x] GitHub Actions structural, Swift, and iOS build jobs

## Next production milestones

1. **Apple build verification:** resolve any CI/SDK warnings, add UI tests, and
   test VoiceOver and Dynamic Type.
2. **Signed package delivery:** add production trust keys, authenticated hosting,
   download resume, license purchase/receipt binding, and real signed artifacts.
3. **Real local runtime:** integrate a pinned llama.cpp XCFramework; first Field,
   then Qwen3-VL-2B plus projector. Keep `IncidentAssistant` as the only entry.
4. **Expert-reviewed content:** replace fixtures with separately signed Vehicle,
   Wilderness, First Aid, and Navigation packs.
5. **Vehicle ingestion:** VIN/manual import and signed vehicle-specific manifests.
   Exact runtime identity and wrong-vehicle exclusion are implemented.
6. **Map renderer:** MapLibre, one Scout regional pack, offline location display,
   route breadcrumb, pack age, and readiness test.
7. **Read-only OBD hardware:** BLE adapter discovery, reconnect, code/freeze-frame
   capture, vehicle binding, and cited explanations.
8. **Release evidence:** locked evaluation sets, physical-device matrix,
   independent red team, human-factors testing, privacy/legal review, and
   domain-owner sign-off.

## Explicitly not implemented

- Model weights, signed production catalog, or commercial purchases
- Generative vision inference
- Offline map rendering
- OBD BLE hardware access
- Vehicle-specific repair packs
- Medical diagnosis or invasive guidance
- Background tracking, analytics, or cloud chat

These omissions are visible and deliberate; none is simulated by a placeholder
that could be mistaken for a completed safety feature.
