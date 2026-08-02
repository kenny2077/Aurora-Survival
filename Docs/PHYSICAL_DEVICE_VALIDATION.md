# Physical device validation

Updated: 2026-08-02

## Confirmed intent

- Ship one adaptive, universal iOS/iPadOS application rather than separate
  products.
- Keep Essential available on every supported device without an optional model.
- Treat the iPhone 13 as the lower-memory text/OCR acceptance target.
- Treat the M2 iPad Pro as the first Vision Expert research target, without
  approving it until exact artifacts pass measured gates.
- Keep incident input, OCR, retrieval, and generation offline.
- Require signed packages, reviewed evidence, citations, and deterministic
  safety rules on both form factors.
- Defer model performance claims to physical-device measurements; workstation
  results are candidate evidence only.

## Assumptions and non-functional requirements

- The connected `iPhone14,5` is the intended iPhone 13.
- The connected `iPad14,3` is the intended 11-inch M2 iPad Pro.
- A single Xcode target with `TARGETED_DEVICE_FAMILY = 1,2` is the minimum
  maintainable architecture.
- SwiftUI views must adapt without device-name checks or duplicated feature
  code.
- Essential launch, emergency-core recovery, retrieval, citations, and OCR must
  remain available after termination and without network access.
- Optional runtime activation must fail closed under missing assets, low power,
  thermal pressure, insufficient memory/storage, recall, or trust failure.

## Decision log

1. **Universal target selected.** A single iPhone/iPad target keeps the safety
   path and package store identical. Separate targets would duplicate release
   configuration and increase drift risk.
2. **Adaptive SwiftUI retained.** Existing `TabView`, `NavigationStack`, lists,
   and flexible-width content are the starting point. Device-specific branches
   will be added only for a measured layout defect.
3. **Physical approval remains capability-based.** Marketing names document the
   test matrix but do not bypass runtime memory, storage, thermal, power, trust,
   or artifact checks.
4. **Essential precedes model work.** Both devices must pass install, launch,
   retrieval, OCR, offline relaunch, accessibility, and interruption checks
   before Lite or Vision integration.

## Evidence matrix

| Gate | iPhone 13 | M2 iPad Pro |
| --- | --- | --- |
| Xcode paired | Pass: paired | Pass: paired with `devicectl` |
| Signed build/install | Pass: Apple Development build installed | Pass: Apple Development build installed |
| Essential first launch | Pass | Partial: foreground launch and live process confirmed; screen flow pending |
| Emergency core and retrieval | Pass: reviewed answer and deterministic safety path | Pending |
| Signed Gemma Lite inference | Pass: grounded, sustained, and optimized-build evidence | Not evaluated |
| Reviewed guide and offline maps | Pass: Twin Cities Scout and Minnesota Statewide Field | Pending |
| OCR | Pass: Apple Vision text flowed into deterministic safety override | Pending |
| Airplane-mode cold relaunch | Pending | Pending |
| Dynamic Type and VoiceOver | Pending | Pending |
| Background/foreground and termination | Pending | Pending |
| Model performance/thermal | Pass for five-turn and optimized short runs: 1.35 s warm TTFT, 15.4 tok/s, thermal fair, no termination; long battery run pending | Not evaluated |

Do not convert a pending cell to pass without direct device evidence.

## Physical-test infrastructure notes

- Xcode automatic signing created the Apple Development identity and an
  Xcode-managed profile for team `AL8BCFV85N`.
- The iPhone 13 accepted and launched the signed application after the user
  explicitly trusted the Personal Team profile.
- The M2 iPad Pro was paired, switched to Developer Mode, accepted the same
  Personal Team profile, and launched the signed universal application.
- After the llama.cpp runtime pin was added, the universal Debug product and
  nested `llama.framework` passed strict code-signature verification. That exact
  runtime-linked build installed and launched on both devices, with live
  TrailGuard processes confirmed (iPhone PID 85350; iPad PID 680).
- Physical XCUITests now install and run successfully on the iPhone 13, including
  repeated native inference, deterministic safety, Apple Vision OCR, guides,
  and local MapLibre products.
- The baseline Activity Monitor trace is
  `/tmp/TrailGuard-iPhone13-activity.trace`. It is short-run engineering
  evidence, not a performance or battery acceptance pass.
- The matched iPad trace is
  `/tmp/TrailGuard-M2-iPadPro-activity.trace` and carries the same limitation.
