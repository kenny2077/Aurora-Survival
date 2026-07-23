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

## Next production milestones

1. **Apple build verification:** generate the Xcode project, resolve any SDK
   warnings, run the unit suite, add UI tests, and test VoiceOver and Dynamic
   Type.
2. **Signed package system:** implement download resume, SHA-256 validation,
   signature verification, atomic install, free-space reservation, rollback,
   license display, and deletion.
3. **Real local runtime:** integrate a pinned llama.cpp XCFramework; first Field,
   then Qwen3-VL-2B plus projector. Keep `IncidentAssistant` as the only entry.
4. **Expert-reviewed content:** replace fixtures with separately signed Vehicle,
   Wilderness, First Aid, and Navigation packs.
5. **Vehicle identity:** VIN/manual import, exact vehicle manifest, and strict
   wrong-vehicle exclusion.
6. **Map slice:** MapLibre, one Scout regional pack, offline location display,
   route breadcrumb, pack age, and readiness test.
7. **Read-only OBD slice:** BLE adapter discovery, code/freeze-frame capture,
   vehicle binding, and cited explanations.
8. **Release evidence:** locked evaluation sets, physical-device matrix,
   independent red team, human-factors testing, privacy/legal review, and
   domain-owner sign-off.

## Explicitly not implemented

- Model weights or commercial downloads
- Generative vision inference
- Offline map rendering
- OBD hardware access
- Vehicle-specific repair packs
- Medical diagnosis or invasive guidance
- Background tracking, analytics, or cloud chat

These omissions are visible and deliberate; none is simulated by a placeholder
that could be mistaken for a completed safety feature.
