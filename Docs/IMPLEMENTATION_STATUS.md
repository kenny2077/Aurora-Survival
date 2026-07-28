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
- [x] Independent model, knowledge, map, policy, catalog, response, and
  evaluation schemas
- [x] Typed grounded-response validation with evidence and procedure allowlists
- [x] Policy identifiers and visible attribution on deterministic safety cards
- [x] Incident-mode network containment and cached offline entitlements
- [x] Bundled emergency-core first-launch and corruption recovery
- [x] Package recall with automatic non-recalled failover
- [x] Launch-time active-pack registry with signature/hash revalidation,
  entitlement, recall, policy, app-version, review, and device gates
- [x] Resumable artifact assembly and interruption tests
- [x] Deterministic SQLite/FTS/vector pack builder with Ed25519 signing
- [x] SQLite FTS5/vector runtime retriever with applicability filters,
  deterministic reciprocal-rank fusion, and lexical fallback
- [x] Byte-for-byte pack reproducibility test in CI
- [x] 120 synthetic gold incident cases and 30 map/asset cases
- [x] Versioned evaluation-report writer and schema
- [x] Model performance/thermal/battery acceptance contract
- [x] Virtual cross-subsystem release and accessibility contract
- [x] Twelve source-controlled architecture decision records
- [x] Attached-plan source audit preventing unlicensed corpus reuse
- [x] Typed grounded JSON connected to the live llama/assistant path
- [x] Exact evidence, procedure, step, and warning resolution before rendering
- [x] Recoverable emergency core connected to application startup
- [x] Strict HTTP range resume connected to signed package installation
- [x] Incident-mode denial connected before package network access
- [x] StoreKit purchase/restore bridge and persistent verified entitlement ledger
- [x] Refund and revocation removal from offline entitlement snapshots
- [x] File-backed offline map runtime boundary
- [x] Persistent vehicle-bound OBD observation records
- [x] Persistent vehicle profile, readiness checklist, and preferred model tier
- [x] Exact vehicle-document ingestion validation
- [x] All 120 gold incidents executed through `IncidentAssistant`
- [x] All 30 map/asset cases executed through map readiness
- [x] Printable/shareable zero-power trip sheet
- [x] In-app system status and external-gate disclosure
- [x] Workstation-only Ollama smoke harness for structured Gemma/Qwen output
  and Qwen embeddings

## Remaining external production milestones

1. **Apple and physical-device verification:** resolve any CI/SDK findings and
   run VoiceOver, Dynamic Type, interruption, memory, thermal, and battery tests
   on the supported iPhone matrix.
2. **Signed production delivery:** provision production trust keys and
   authenticated hosting, then publish licensed real artifacts. Local signing,
   verification, strict range resume, activation, rollback, and recall controls
   are complete.
3. **Real local runtime:** integrate a pinned llama.cpp XCFramework; first Field,
   then Qwen3-VL-2B plus projector. Keep `IncidentAssistant` as the only entry.
   Workstation Ollama tests are evaluation evidence only and are not an iOS
   runtime substitute.
4. **Expert-reviewed content:** replace fixtures with separately signed Vehicle,
   Wilderness, First Aid, and Navigation packs.
5. **Vehicle ingestion assets:** obtain licensed manuals and build signed
   vehicle-specific manifests. Exact identity, document revision, applicability,
   ingestion validation, and wrong-vehicle exclusion are implemented.
6. **Map renderer:** MapLibre, one Scout regional pack, offline location display,
   route breadcrumb, pack age, and readiness test.
7. **Read-only OBD hardware:** BLE adapter discovery, reconnect, code/freeze-frame
   capture, vehicle binding, and cited explanations.
8. **Release evidence:** execute the locked matrices on real approved assets and
   devices, then complete independent red team, human-factors, privacy/legal,
   and domain-owner sign-off.

## Explicitly not implemented

- Model weights, signed production catalog/keys, or configured App Store products
- Pinned llama.cpp XCFramework and the Objective-C++ bridge implementation
- Generative vision inference
- Offline map rendering
- OBD BLE hardware access
- Vehicle-specific repair packs
- Medical diagnosis or invasive guidance
- Background tracking, analytics, or cloud chat

These omissions are visible and deliberate; none is simulated by a placeholder
that could be mistaken for a completed safety feature.
