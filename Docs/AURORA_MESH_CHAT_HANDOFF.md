# Aurora Mesh Chat Debug Beta — Engineering Handoff

Last updated: 2026-08-31 (Asia/Shanghai)

## Goal and safety boundary

Implement Aurora Mesh Chat as the sixth Field Tool in Debug builds only. It is Aurora-only, encrypted private group text over foreground Bluetooth LE. There is no public room, direct messaging, media, internet fallback, background relay, emergency integration, or change to iOS auto-lock.

The approved design and the Bitchat reference commit are recorded in `Docs/AURORA_MESH_CHAT_DESIGN.md`. Bitchat commit `9b84b361225facd8e623f25d76f889d3dc54a879` is reference material only; no protocol, UUID, UI, or unrelated feature was copied.

## Current implementation

### Build and product gate

- `AURORA_MESH_BETA` is defined for SwiftPM Debug Core/tests and Xcode Debug app/unit/UI test targets.
- Every mesh source is wrapped in `#if AURORA_MESH_BETA`.
- `ToolsView` adds the sixth `Mesh Chat` card and destination only under that flag.
- Release compiles the mesh files as empty files and has no route/card/reachable mesh types.
- `project.yml` is the project source of truth. Run `xcodegen generate` after changing it.
- Bluetooth permission text explicitly describes the visible Debug beta. The camera text adds QR scanning in Debug through `AURORA_CAMERA_USAGE_DESCRIPTION`.
- No Bluetooth background mode was added. The app's pre-existing location background mode and package-download networking are unrelated to Mesh Chat.

### Core protocol

Files:

- `Core/AuroraMeshModels.swift`
- `Core/AuroraMeshCrypto.swift`
- `Core/AuroraMeshStore.swift`
- `Core/AuroraMeshEngine.swift`

Implemented:

- Actor-owned groups, messages, sender sequences, current/historical epoch keys, recent-ID deduplication, persisted sliding sequence replay protection, per-sender rate limiting, TTL relay, batched acknowledgements, delivery counts, signed presence, catch-up selection, and deterministic injected clock.
- Protocol limits: 20 members, 6 links, 7 hops, 2,048 UTF-8 bytes, 256 queued frames/link, 32 reassemblies/peer, 4,096 dedup IDs, 500 catch-up packets/session, and 7-day relay age.
- Compact versioned wire header with immutable packet ID and mutable TTL outside the signed/encrypted body.
- Ed25519 signatures, X25519 agreement, HKDF-SHA256, ChaCha20-Poly1305 group encryption, and 8-byte keyed group/epoch tags.
- Five-minute QR invitations contain no group key. Joiner and inviter derive the same six-digit code. Approval is encrypted with an ephemeral X25519 session key.
- Any current member can invite. Membership grants propagate inside the current group channel.
- Creator-only removal advances the epoch, signs a fresh retained roster, and sends the new key in separately encrypted X25519 packages. Removed members reject the rekey and cannot open new-epoch traffic.
- Self-leave and creator end-group packets.
- Old-epoch traffic is not accepted for live relay, while historical keys remain available to decrypt local history.
- One-hop signed/encrypted sync summaries are emitted on link establishment and every 20 seconds. They refresh 45-second reachability and request up to 500 eligible current-epoch ciphertexts; the join grant timestamp prevents pre-join history disclosure.

### Persistence and secrets

- SQLite WAL store persists versioned groups/rosters, encrypted wire envelopes, acknowledgements, sender sequences, sync indexes, tombstones, and known key epochs.
- History pages are capped at 100. Catch-up is capped at 500.
- Local deletion inserts tombstones before deleting envelopes, preventing catch-up restoration.
- Ed25519/X25519 private keys and group epoch keys use Keychain generic-password items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Deleting a group's local history removes historical epoch keys from both the engine and Keychain, retaining only the current epoch key.

### BLE and SwiftUI

Files:

- `App/MeshKeychainVault.swift`
- `App/MeshBLELink.swift`
- `App/MeshChatCoordinator.swift`
- `App/MeshChatView.swift`

Implemented:

- CoreBluetooth central + peripheral roles using Aurora-specific service/characteristic UUIDs.
- Deterministic advertisement-token tie-break to reduce duplicate symmetric connections.
- Six-link cap, MTU-aware fragmentation, 30-second reassembly expiry, 32 reassemblies/peer, 256-frame per-link queues, and CoreBluetooth backpressure callbacks.
- Main-actor coordinator converts actor snapshots to immutable SwiftUI state and bridges encrypted wire packets only.
- BLE starts when Mesh Chat is visible and stops on navigation away or any non-active scene phase. No code changes `isIdleTimerDisabled`.
- First-use limitations, saved groups, create group, QR scanning/invite display, verification approval, chat composer, byte-limit UI, delivery labels, fingerprints, creator removal/end, self-leave, and local history deletion.
- Denied/unavailable Bluetooth states have accessible text.

## Verification completed

`rtk swift test --filter AuroraMeshTests` passed 13 Debug tests with one Release-only benchmark skipped, in 0.254 seconds on the M2. Coverage includes:

- wire round-trip and malformed headers/lengths;
- encryption/signature verification, tampering, and wrong-epoch rejection;
- QR omission of the group key, matching verification codes, encrypted approval, and expiry;
- batched acknowledgements/delivery counts, packet-ID and persisted sender-sequence replay rejection, and tombstones;
- signed presence expiry, catch-up recovery, and pre-join history exclusion;
- forged membership grants, duplicate approval use, and wire/name limit rejection;
- creator rekey/removal exclusion;
- history paging/catch-up caps;
- deterministic 20-node line, ring, star, degree-six dense, and partitioned graphs;
- at-most-once display, seven-hop cutoff, and the 120-link-delivery bound.

The final Debug iOS app built successfully for generic iOS Simulator using:

```sh
rtk xcodebuild -project Aurora.xcodeproj -scheme Aurora -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AuroraMeshDebug2 CODE_SIGNING_ALLOWED=NO build
```

A clean Release app built successfully at `/tmp/AuroraMeshRelease2/Build/Products/Release-iphonesimulator/Aurora.app`. Its binary has no `Mesh Chat`, `AuroraMesh`, or `tools.meshChat` strings. Release camera wording excludes QR scanning. The shared Bluetooth usage key remains in the plist, but no Release code references CoreBluetooth Mesh functionality and no Mesh route exists.

The Release-optimized 20-node/1,000-message production-engine simulation passed in **4.082 seconds**, under the five-second M2 gate. Exact command:

```sh
rtk swift test -c release \
  -Xswiftc -DAURORA_MESH_BETA \
  -Xswiftc -DDEBUG \
  -Xswiftc -DAURORA_MESH_PERFORMANCE \
  --filter AuroraMeshTests/testReleaseOptimizedThousandMessageSimulationPerformance
```

`-DDEBUG` is needed only because unrelated existing Release test sources call Debug-only assistant helpers; compilation remains `-c release` optimized.

Static search across `App/Mesh*.swift` and `Core/AuroraMesh*.swift` found no `URLSession`, `NWConnection`, `Network.framework`, `isIdleTimerDisabled`, or background-mode use.

The first whole-repository `swift test` run compiled successfully but showed two unrelated existing failures in `ConversationalRAGTests` over overlong-answer assertions. The targeted Mesh test suite is green.

### Single-iPhone physical smoke test (2026-08-31)

A signed Debug build was built, installed, and launched successfully on Kenny's iPhone 13 running iOS 26.6 (23G71). Aurora remained alive as PID 28951 after the requested navigation and lock/unlock exercise.

An Instruments Activity Monitor recording ran for 61.74 seconds without a crash. Aurora's physical footprint was approximately 47.13–53.28 MiB. CPU was near zero while idle, with brief interaction peaks up to 22.4%. This short trace found no runaway growth, but it is not a substitute for the planned one-hour energy gate.

A separate 62.33-second Power Profiler recording completed successfully while Aurora remained attached. Aurora's per-process samples reported zero Wi-Fi and cellular bytes and no modeled networking or GPU impact during the sample. The display remained the main unavoidable cost while Mesh Chat was visible. The Instruments CLI crashed when exporting only the thermal-state table, so no numeric thermal conclusion is recorded from that table.

The phone-holder subsequently confirmed that every requested manual observation was normal: Bluetooth permission and the zero-peer Mesh Home state behaved as expected, repeated navigation and lock/unlock recovered without errors, and the iPhone was not hot. This closes the short single-iPhone smoke check; it does not replace the one-hour energy or multi-device gates. The trace bundles are temporary local artifacts at `/private/tmp/AuroraMeshPhysicalActivity.trace` and `/private/tmp/AuroraMeshPhysicalPower.trace`.

On 2026-09-01, the same signed Debug beta was built, installed, and launched successfully on Kenny's 11-inch iPad Pro (4th generation), running iPadOS 26.6. Aurora was confirmed alive as PID 54619. Bluetooth permission, invitation exchange, bidirectional text, acknowledgements, and reconnect/catch-up remain manual two-device checks; installation alone does not mark the direct-exchange gate passed.

The first two-device invitation attempts exposed two separate issues. The inviter approval alert was hidden below the active QR sheet, so `MeshChatView` now renders approval inline on that sheet with a Mesh Home fallback. More importantly, the joiner's verification code is derived locally before transmission, so seeing it did not prove BLE delivery. The actual lifecycle bug was that pushing Mesh Home into a group triggered `onDisappear` and stopped Bluetooth; the iPad then displayed its QR code from a group screen while its mesh radio was off.

The coordinator now keeps a balanced visibility lease across Mesh Home, group chat, group details, QR invitation, and QR scanning. Internal navigation no longer stops BLE, while leaving Mesh Chat or making the scene inactive still does. Invite hello packets retry every second until approval/expiry, encrypted approvals retry for nine seconds, failed/disconnected central links restart scanning, and Debug UI shows link state plus sent/received/no-link counters. The corrected signed build compiled, the targeted suite again passed 13 tests with one Release-only skip and zero failures, and the same build was installed on both devices. Kenny then confirmed that direct invitation worked. In clear conditions with limited obstruction, his manual tests reached roughly 20–30 meters; this is an observation from the current two-device setup, not a guaranteed product range.

### Editable Mesh display names (2026-09-01)

Mesh Home now starts with one compact row showing `Name` on the left and the current display name on the right; tapping the row opens editing. The old home-screen “This installation” section and fingerprint are removed; fingerprints remain available in Group Details. Editing a name preserves the installation's Ed25519 and X25519 keys and therefore preserves its fingerprint.

Each active group receives a signed, encrypted `identityUpdate` event. The event uses normal relay and seven-day catch-up, so an offline current member can learn the newer name later. SQLite stores the newest name per group/member by sender sequence and rejects an older update received out of order. Ordinary signed group traffic also refreshes the resolved name. The targeted Mesh suite now passes 15 tests with one Release-only skip and zero failures, including key preservation, signed propagation, catch-up, and newest-name-wins behavior. A signed Debug device build also completed successfully.

### Full-screen scanner and creator deletion (2026-09-01)

Invite scanning now uses an edge-to-edge `fullScreenCover` on both compact and regular layouts. The AVFoundation preview aspect-fills the viewport; safe-area overlays provide Close, an adaptive QR guide, instructions, and requesting/denied/unavailable states. Session configuration and start/stop run on a private serial queue. QR validation and the existing verification flow are unchanged.

The creator action is now Delete Group with irreversible confirmation and awaited success. The existing signed encrypted `endGroup` wire body is unchanged. A successful deletion atomically retains only hidden ended-group metadata, the termination envelope, and recorded keys; normal messages, acknowledgements, sender indexes, and resolved names are scrubbed, and ended groups disappear from snapshots. Members perform the same operation after validating the creator event. The packet retries only when Mesh starts or a link changes from zero to available. After seven days, two-phase cleanup removes Keychain epochs before Core purges the remaining SQLite group state, allowing interruption-safe retries.

The targeted Mesh suite passes 17 tests with one Release-only benchmark skipped and zero failures. New coverage includes creator/non-creator behavior, history and acknowledgement scrubbing, restart relay, TTL reset, tampering, wrong epoch, historical key cleanup, and seven-day purge. The app and UI-test targets compile successfully. The identical signed Debug build was installed and launched on Kenny's iPhone and iPad for manual verification. UI-test execution remains blocked before test launch by the existing host `DebuggerLLDB.DebuggerVersionStore.StoreError` / `no debugger version` failure; no UI runtime pass is claimed.

### Modern group conversation UI (2026-09-02)

Group chat now uses a familiar messenger presentation: Aurora-accent outgoing bubbles, neutral incoming bubbles, five-minute sender grouping, date separators, concise sender/time/final-delivery metadata, selectable text, and an accessible empty state. The principal header shows the group name and live nearby-member count. Conversation width is bounded on iPad and bubbles cap at 78% of the row.

Scrolling opens at the newest message and follows incoming traffic only while the viewport is near the bottom. When the reader is reviewing history, the position stays fixed and a New Messages control appears. Delivery-only changes do not move the view or create unread counts. The safe-area composer supports one through five lines, warns after 75% of the 2,048-byte UTF-8 limit, disables blank/oversized sends, and clears only after awaited local acceptance; failure preserves the draft.

The targeted Swift Package Mesh suite still passes 17 tests with one Release-only skip and no failures. Two Xcode-hosted deterministic tests for grouping boundaries, engine-order preservation, localized day labels, whitespace, thresholds, and multibyte limits pass. App, unit-test, and UI-test targets compile. UI-test execution still stops before test code because the host reports `DebuggerLLDB.DebuggerVersionStore.StoreError` / `no debugger version`; no UI runtime pass is claimed. A clean Release simulator build contains no `Mesh Chat`, `MeshConversation`, `mesh.message`, or `tools.meshChat` strings.

A signed Debug device build completed, was installed on Kenny's iPhone, and launched successfully for manual review. CoreDevice listed the iPad as `unavailable`, so this build was not installed there and no iPad runtime result is claimed. The ready bundle is `/private/tmp/AuroraMeshModernChatDevices/Build/Products/Debug-iphoneos/Aurora.app`; install it when the iPad is connected, unlocked, and available.

## Important remaining work, in order

1. **Repair the host UI-test runner, then execute the Mesh UI tests.** The expanded scanner-geometry and creator-deletion tests compile, but `test-without-building` again stalled before execution with `DebuggerLLDB.DebuggerVersionStore.StoreError` / `no debugger version` and was stopped manually. This is an Xcode host/toolchain problem, not a passing UI result.
2. **Run the multi-device physical gates.** The short single-iPhone smoke check passed. Next verify direct exchange between the iPhone and iPad, then three-device multi-hop/partition recovery. Do not claim reliability/range from the single-device result. Keep Debug-only until direct exchange, three-device recovery, one-hour energy, and focused crypto/wire review pass.
3. **Focused security review and remaining adversarial cases.** Add malicious rekey-roster variants, replay across an engine process restart, fragmented-frame corruption/order tests, and queue-overflow recovery tests.
4. **Invite reliability.** Add retry/expiry UI for one-hop invite hello/approval packets while both screens remain visible.
5. **Live detail refresh.** The editable display-name path is implemented, but an already-open details view should still be checked against live roster changes.

## Known engineering concerns

- Invite hello/approval control packets are one-hop broadcast and currently have no retry/timeout UI. The approval ciphertext protects the group key, but a retry state machine is needed for real radio loss.
- CoreBluetooth restoration is intentionally absent because the beta is foreground-only.
- Backpressure queues drop excess frames at 256. This is bounded and safe, but an incomplete transfer waits for the 30-second reassembly expiry; add explicit transfer cancellation metrics if needed.
- The advertisement tie-break uses a short identity token. Verify iOS consistently exposes the local name in foreground advertisements; otherwise add an encrypted post-connect identity handshake while preserving the six-link cap.
- Display-name edits propagate through signed encrypted group events and preserve identity keys. Confirm the new name on both physical devices, including after one device is briefly offline and reconnects.
- A persisted 4,096-sequence replay window now rejects repeated sender sequences while allowing bounded out-of-order delivery. A process-restart integration test is still desirable.
- The UI passes an `AuroraMeshGroup` value into chat/details; live roster updates appear on the home snapshot but an already-open details sheet may remain stale until reopened.

## Working tree and ownership

All mesh changes are uncommitted. Do not discard unrelated user work. At handoff, the changed/new paths are:

- `Package.swift`
- `project.yml`
- `App/ToolsView.swift`
- `App/MeshBLELink.swift`
- `App/MeshChatCoordinator.swift`
- `App/MeshChatView.swift`
- `App/MeshKeychainVault.swift`
- `Core/AuroraMeshModels.swift`
- `Core/AuroraMeshCrypto.swift`
- `Core/AuroraMeshStore.swift`
- `Core/AuroraMeshEngine.swift`
- `Tests/AuroraMeshTests.swift`
- `UITests/MeshChatUITests.swift`
- `Docs/AURORA_MESH_CHAT_DESIGN.md`
- this handoff file

Start the next session by reading the design and this handoff, running `git status --short`, then executing the targeted Mesh tests before changing behavior.
