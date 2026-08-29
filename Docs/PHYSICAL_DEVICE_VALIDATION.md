# Physical device validation

Updated: 2026-08-29

## Confirmed intent

- Ship one adaptive, universal iOS/iPadOS application rather than separate
  products.
- Require a usable Lite or Expert model before Ask is available.
- Treat the iPhone 13 as the lower-memory text/OCR acceptance target.
- Treat the M2 iPad Pro as the first Vision Expert research target, without
  approving it until exact artifacts pass measured gates.
- Keep incident input, OCR, retrieval, and generation offline.
- Require signed packages and validated zero-to-two Field Manual links without
  a pre-model hazard gate or fixed response card.
- Defer model performance claims to physical-device measurements; workstation
  results are candidate evidence only.

## Assumptions and non-functional requirements

- The connected `iPhone14,5` is the intended iPhone 13.
- The connected `iPad14,3` is the intended 11-inch M2 iPad Pro.
- A single Xcode target with `TARGETED_DEVICE_FAMILY = 1,2` is the minimum
  maintainable architecture.
- SwiftUI views must adapt without device-name checks or duplicated feature
  code.
- Manual, Maps, package resolution, retrieval, and exact citations must remain
  available after termination and without network access; Ask requires a model.
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
   or artifact checks. Expert admits the 6 GB device class at
   `5,500,000,000` reported physical bytes, then still requires measured
   package memory plus 768 MiB live headroom.
4. **Expert remains locked.** The M2 iPad may display Expert target messaging,
   but cannot expose vision input until signed artifacts and mtmd integration pass.
5. **Chat polish uses native glass.** The chat shell uses iOS 26 glass controls,
   keeps the existing model lifecycle and routing policy, and exposes an
   icon-only native model menu. Missing packages route to Tools; installed
   packages load and unload in Ask. Lite attachment choices use a compact
   two-row popover. The idle greeting is fixed slightly above center, the
   focused composer expands into one compact glass surface, thinking status
   precedes the answer, and populated conversations are top-aligned. Tools
   exposes an adjacent load or unload control for each model tier.
6. **Appearance is explicit but minimal.** Settings exposes only System, Light,
   and Dark. The persisted choice applies at the app root, Reset to Defaults
   restores System, and the enabled send control uses inverse semantic colors
   so its arrow remains dark in Dark appearance and light in Light appearance.
7. **Adaptive-language acceptance is paired across tiers.** The maintained
   physical runner performs exactly three Lite and three Expert conversations:
   English wilderness food, Simplified Chinese water location/purification,
   and Spanish overnight shelter. Each record retains the exact answer,
   requested and detected language, reviewed-source state, latency, failure
   reason, memory/thermal data, and one screenshot.

## Evidence matrix

| Gate | iPhone 13 | M2 iPad Pro |
| --- | --- | --- |
| Xcode paired | Pass: paired | Pass: paired with `devicectl` |
| Signed build/install | Pass: Apple Development build installed | Pass: Apple Development build installed |
| Four-tab/no-model launch | Rerun in current report | Rerun in current report |
| Unified survival retrieval and manual links | Earlier corpus flow passed; current 10-chapter database rerun is recorded in the Field Manual report | Pending |
| Signed Gemma Lite inference | Partial: stateless grounded-to-ordinary sequence and exact Manual navigation passed under the prior compact contract; substantive `1.1.0` installed, but final five-domain acceptance remains open | Not evaluated |
| Liquid-glass chat journeys | Pass: empty capability UI, keyboard dismissal with preserved draft, and Lite water conversation | Pending |
| Manual and dedicated offline Maps tab | Rerun in current report | Rerun in current report |
| Expert vision | Not eligible; photo actions visible but disabled in Lite | Validation-locked pending signed model/projector and mtmd |
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
  Aurora processes confirmed (iPhone PID 85350; iPad PID 680).
- Physical XCUITests now install and run successfully on the iPhone 13, including
  repeated native inference, survival RAG, Apple Vision OCR, guides,
  and local MapLibre products.
- The final 2026-08-25 chat-controls gate ran only the three scoped journeys on
  the connected iPhone 13 (`D93DEDAA-E38F-5BDE-B05F-5FCC01D7E190`) with signed
  device builds. `/tmp/AuroraChatControls-20260825-final2.xcresult` records
  the empty-state/capability and keyboard-dismissal journeys passing. It retains
  screenshots of the fixed, raised greeting, icon-only model dropdown, compact
  two-row Lite attachment popover, and focused glass composer with its draft.
  `/tmp/AuroraChatControls-20260825-lite-final2.xcresult` records the third
  journey passing with no skip: direct Lite loading, thinking status above the
  answer, a completed Lite-labeled water response in the top half of the chat,
  and the adjacent Lite unload control in Tools. Its three retained screenshots
  cover the thinking, completed conversation, and Tools runtime-control states.
- The 2026-08-26 Maps simplicity gate ran only the three scoped map journeys on
  the connected iPhone 13 (`D93DEDAA-E38F-5BDE-B05F-5FCC01D7E190`, Xcode
  destination `00008110-001645080EA8201E`) running iOS 26.6. The signed physical
  result at `TestResults/MapMenu-2026-08-26.xcresult` records three passes, zero
  failures, and zero skips: separated top Map Type and bottom mode controls;
  movable center-pin plus direct-tap waypoint placement; and the simplified
  Manage Downloads handoff opening an installed offline map. Retained
  screenshots are exported under
  `TestResults/MapMenu-2026-08-26-Attachments`. The accessibility hierarchy also
  recorded the custom blue current-location indicator with a live heading.
- The 2026-08-26 native-location revision ran one focused signed journey on the
  same connected iPhone 13. `TestResults/NativeLocation-2026-08-26.xcresult`
  records one pass, zero failures, and zero skips. Its screenshot under
  `TestResults/NativeLocation-2026-08-26-Attachments` verifies MapKit's native
  system-blue location dot and heading beam in Record mode, unobstructed by the
  waypoint placement pin. Aurora's custom location cone, dot, and shadow were
  removed; MapLibre uses its corresponding native location and heading UI.
- The 2026-08-26 north-up correction ran the same single focused signed journey
  on the connected iPhone 13 after physical visual iteration. The accepted run
  at `TestResults/NorthUpHeading-2026-08-26-v15.xcresult` records one pass, zero
  failures, and zero skips. Its retained screenshot under
  `TestResults/NorthUpHeading-2026-08-26-v15-Attachments` confirms a fixed
  north-up Apple map and centered current-location marker. The map uses
  nonrotating follow behavior; only the compact system-blue heading layer
  responds when a valid compass heading is available. Heading updates run while
  the Maps tab is visible and stop on exit unless trail recording is active.
- The 2026-08-26 native map interaction correction ran exactly three focused
  signed journeys on the same connected iPhone 13. The accepted result at
  `TestResults/NativeMapInteraction-2026-08-26-final.xcresult` records three
  passes, zero failures, and zero skips: a manually rotatable MapKit camera with
  an adaptive native compass and centered native scale; long-press waypoint
  editor presentation without center-pin or single-tap placement; and preserved
  Waypoints management, Record, and Manage Downloads flows. Screenshots under
  `TestResults/NativeMapInteraction-2026-08-26-final-Attachments` confirm the
  stronger camera-relative system-blue heading cone and unobstructed native map
  controls.
- The 2026-08-26 map-chrome and offline-download polish ran exactly three
  focused signed journeys on the connected iPhone 13. The accepted result at
  `TestResults/MapChromePolish-2026-08-26-final.xcresult` records three passes,
  zero failures, and zero skips. It verifies the title-free map with its native
  top-centered scale, the compact Offline Maps and installed-map actions, and
  reversible single-tap clean-map mode while pan, rotation, active recording,
  and long-press waypoint editing remain intact. The three retained screenshots
  are under `TestResults/MapChromePolish-2026-08-26-final-Attachments`.
- The 2026-08-27 saved-waypoint and map-panel polish ran two focused signed
  journeys on the connected iPhone 13. The accepted result at
  `TestResults/WaypointFocusPolish-2026-08-27.xcresult` records two passes, zero
  failures, and zero skips. It verifies title-only Offline Maps and idle Trail
  Recording panels, the compact “Downloads” action, preserved clean-map and
  long-press behavior, and native camera recentering after the map is panned
  away and a persisted waypoint is selected. Screenshots are retained under
  `TestResults/WaypointFocusPolish-2026-08-27-Attachments`.
- The 2026-08-27 Tools liquid-glass redesign ran exactly three focused signed
  journeys on the connected iPhone 13. The accepted result at
  `TestResults/ToolsLiquidGlass-2026-08-27-v5.xcresult` records three passes,
  zero failures, and zero skips. It verifies the compact Offline Models-first
  dashboard and Field tools layout, icon-only Lite load/unload controls with
  the Expert device gate, and the simplified Settings About section. Retained
  dashboard and Settings screenshots are under
  `TestResults/ToolsLiquidGlass-2026-08-27-v5-Attachments`. The tested Lite
  package remained installed; this gate did not download or remove model
  packages.
- The 2026-08-25 compact Tools gate ran one focused journey on the connected
  iPhone 13. `/tmp/AuroraToolsCompact-20260825-fixed.xcresult` records the
  signed Lite model loading and unloading directly beside its compact model
  row, with the load control returning after unload and no “Check Availability”
  action. The installed Lite and shared-RAG packages were restored over the
  wired device connection; no LAN catalog was exposed. The retained screenshot
  records the compact Lite row and the Expert 6 GB-class ineligibility state.
- The 2026-08-25 adaptive chat-sizing gate ran one focused signed journey on
  the connected iPhone 13. `/tmp/AuroraChatSizing-20260825.xcresult`
  records one pass with no skips: the user query bubble fits its content, the
  compact attachment and send controls retain their native glass treatment,
  and Lite completes the conversation. Three physical-device screenshots are
  retained in the result bundle.
- Current stateless Lite acceptance is recorded in
  `/tmp/AuroraStatelessLitePhysical-exact-link.xcresult` and
  `/tmp/AuroraStatelessLitePhysical-retry.xcresult`: exact “Locate Likely
  Water” navigation passed, the banner was absent, and a casual turn after a
  grounded water turn contained no stale advice or Manual link.
- `/tmp/AuroraStatelessLitePhysical-link-retry.xcresult` records the
  accepted small-model deficit: “How do I make water safer?” exhausted its one
  repair and displayed the incomplete-answer terminal response without a false
  link. Current-contract TTFT, throughput, retry latency, and thermal impact
  were not measured in this run.
- `/tmp/AuroraSubstantivePackageInstall.xcresult` records installation and
  activation of the signed `model-lite-gemma3-1b-q4km-dev@1.1.0` package with
  the 160-token manifest on the iPhone 13.
- Exploratory substantive generation accepted bleeding, water, lost, and bear
  responses before the stuck-vehicle case failed closed. The run was not
  retained and is not release acceptance evidence. The retained generic-car
  result at
  `/tmp/AuroraSubstantivePhysical/Logs/Test/Test-Aurora-2026.08.09_23-26-20-+0800.xcresult`
  failed closed without a procedure or false Manual link, but did not produce
  an accepted clarification.
- Two final reruns on the unlocked iPhone ended before test launch with Xcode
  `DebuggerVersionStore.StoreError`. No five-domain, TTFT, throughput, warm
  completion, repair-latency, or thermal pass is claimed for the substantive
  contract.
- The final Lite Chat survival acceptance result is
  `/tmp/AuroraLiteChatPhysicalAcceptance/Logs/Test/Test-Aurora-2026.08.02_14-43-28-+0800.xcresult`.
  Both generated answers direct the user to boil water for at least one minute,
  respect the follow-up constraint that no filter is available, and link to
  the former page-addressable water passage. This is retained as historical
  baseline evidence; the current database uses stable semantic passage IDs.
- The final ordinary-chat and enriched-manual result is
  `/tmp/AuroraLiteChatPhysicalAcceptance/Logs/Test/Test-Aurora-2026.08.02_14-34-25-+0800.xcresult`.
  The greeting uses Gemma with no manual link; Guide reports 17 chapters and
  the former detailed water passage. Current Manual evidence is recorded in
  `FIELD_MANUAL_PROGRESS_REPORT.md`.
- The app-hosted corpus/unit acceptance result is
  `/tmp/AuroraLiteChatPhysicalAcceptance/Logs/Test/Test-Aurora-2026.08.02_14-16-42-+0800.xcresult`.
  It verifies the retired bundled-book baseline. Current validation verifies
  10 chapters, 70 lessons, 1,050 FTS passages, and 828 legacy dispositions.
- The baseline Activity Monitor trace is
  `/tmp/Aurora-iPhone13-activity.trace`. It is short-run engineering
  evidence, not a performance or battery acceptance pass.
- The matched iPad trace is
  `/tmp/Aurora-M2-iPadPro-activity.trace` and carries the same limitation.
