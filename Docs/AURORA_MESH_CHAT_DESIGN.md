# Aurora Mesh Chat Debug Beta

Status: approved implementation design, Debug builds only.

Aurora Mesh Chat is a foreground-only Bluetooth Low Energy field tool for
encrypted private group text. It is Aurora-only: there is no public chat,
direct messaging, media, internet fallback, background relay, or emergency
service integration. Range is environment-dependent and is not guaranteed.

## Reference boundary

The transport review used `permissionlesstech/bitchat` commit
`9b84b361225facd8e623f25d76f889d3dc54a879` (2026-08-10), released under the
Unlicense. Aurora borrows the general lessons—central and peripheral BLE
roles, bounded queues, TTL routing, duplicate suppression, backpressure, and
deterministic simulation—but does not copy its UUIDs, wire protocol, UI,
Nostr integration, or feature modules.

## Architecture

- `AuroraMeshEngine` is the radio-independent, single-writer protocol core.
- `MeshBLELink` is the only layer that imports CoreBluetooth.
- `MeshChatCoordinator` owns foreground lifecycle and publishes UI snapshots.
- `AuroraMeshStore` persists encrypted envelopes and bounded sync metadata.
- `MeshKeychainVault` stores installation and group keys as device-only data.

Debug builds define `AURORA_MESH_BETA`. Release builds keep the existing
five-tool Field Tools surface and cannot navigate to or start Mesh Chat.

## Protocol contract

- Version 1; 20 members; six direct links; seven relay hops.
- Text payloads are at most 2,048 UTF-8 bytes.
- Ed25519 authenticates installation identities and message bodies.
- X25519, HKDF-SHA256, and ChaCha20-Poly1305 protect QR enrollment.
- ChaCha20-Poly1305 group epoch keys protect group messages.
- Any current member may invite; only the creator may revoke and rekey.
- Only current group members relay a group's opaque packets.
- Catch-up is limited to messages first seen during the previous seven days
  and at most 500 messages per peer session.
- Local deletion creates tombstones so catch-up cannot resurrect messages.

## User contract

The radio runs only while Mesh Chat is visible and the app is active. Aurora
does not disable auto-lock. The UI distinguishes Sending, Relayed, and
Delivered N of M; acknowledgements are delivery receipts, not read receipts.
The first-use notice states that every hop must be a current group member with
Mesh Chat open and that this tool does not contact emergency services.

## Promotion gate

The Debug beta is simulation-led because only one iPhone is available. It may
not be exposed in Release until two iPhones pass direct delivery, three pass
multi-hop and partition recovery, a one-hour energy trial passes, and the
cryptographic and wire design receives focused security review.

## Editable display names

Status: approved 2026-09-01.

### Understanding

- Mesh Home begins with one compact row showing `Name` on the left and the current display name on the right; tapping the row opens editing.
- Mesh Home does not show `This installation` or the identity fingerprint.
- Renaming preserves the installation's Ed25519/X25519 keys and fingerprint.
- A signed, encrypted name update propagates to existing active groups and uses seven-day catch-up for offline members.
- Names are trimmed, nonempty, and limited to 64 UTF-8 bytes.
- Fingerprints remain visible in Group Details for deliberate identity verification.
- Name editing does not change membership, epochs, message history, radio policy, permissions, or the Debug-only gate.

### Design

Keychain rewrites only the stored display name alongside the existing private keys. The engine replaces its in-memory private identity with the same keys and emits one signed `identityUpdate` envelope per active group. Peers verify the ordinary group membership, signing key, signature, and sender sequence before accepting the name.

SQLite stores the newest accepted display name and sequence per group/member. Resolved display names are exposed in snapshots and used by member lists and message sender labels without modifying signed membership grants. Older, replayed, malformed, or over-limit updates are rejected. If a peer is offline, the encrypted update remains eligible for normal seven-day catch-up.

### Decision log

- Use signed encrypted group events rather than rewriting membership grants; grants remain immutable evidence of admission.
- Propagate changes to existing groups rather than limiting them to the local installation or future invitations.
- Preserve keys and fingerprint so a cosmetic rename never creates a new person cryptographically.
- Keep security fingerprints in Group Details while simplifying Mesh Home to the user-facing name.
- Reuse current routing, replay protection, persistence, and catch-up instead of adding a separate name service.

## Full-screen invite scanning and group deletion

Status: approved 2026-09-01.

### Understanding

- Invite scanning uses an edge-to-edge camera on iPhone and iPad with adaptive safe-area controls, rotation support, and accessible denied/unavailable states.
- A valid Aurora invite is delivered once and continues through the existing verification flow; unrelated QR codes are ignored.
- Only the creator may delete a group. Deletion is irreversible, immediately removes the group from normal UI, and propagates through the existing signed, encrypted `endGroup` body.
- Visible history is erased immediately. Minimal protected termination state remains hidden for seven days so temporarily offline members can learn the group ended.
- Mesh remains foreground-only, BLE-only, Debug-only, seven hops, and twenty members. No dependency, background mode, network path, wire version, or database schema is added.

### Design

The scanner is presented with `fullScreenCover`. Its AVFoundation preview fills the viewport while SwiftUI supplies a safe-area Close control, instructions, an adaptive guide, and explicit requesting/running/denied/unavailable states. Capture setup and session start/stop run on a dedicated serial queue.

Creator deletion first durably records the termination envelope and ended group in one SQLite transaction, then removes visible messages, acknowledgements, and resolved names. Ended groups are excluded from snapshots and accept no new group activity. The current epoch key and termination packet remain only for relay. Pending termination packets retry when Mesh starts and when BLE links transition from zero to available, with mutable TTL reset to seven. After seven days, Core purges group-scoped state and returns its recorded epochs so the app removes the Keychain keys. Receiving a valid creator termination follows the same idempotent hide, scrub, relay, and purge path.

### Decision log

- Use a native full-screen cover rather than device-specific sheet sizing.
- Keep the wire body named `endGroup` for compatibility while presenting the action as Delete Group.
- End the group for all members rather than deleting only the creator's copy.
- Retain hidden termination state for seven days rather than losing offline members or waiting indefinitely for receipts.
- Retry on Mesh start and new-link availability rather than on every presence heartbeat, limiting radio and queue cost.
- Reuse `endedAt` and existing envelope/key tables; no schema migration or deletion-receipt protocol is warranted.

## Modern group conversation UI

Status: approved 2026-09-02.

### Understanding

- Mesh group chat should feel like a familiar modern messenger while retaining Aurora colors and offline delivery language.
- Adjacent messages from the same sender group only on the same calendar day with a forward gap of zero through five minutes.
- Sender names, timestamps, and delivery metadata stay concise; the header shows the group name and live nearby-member count.
- Initial entry opens at the newest message. Incoming messages follow only when the reader is already near the bottom; otherwise a New Messages control preserves reading position.
- The adaptive multi-line composer clears only after the engine accepts and persists a message, and it warns near the 2,048-byte UTF-8 limit.
- Encryption, protocol, history order, persistence, BLE lifecycle, and Debug-only availability do not change. Reactions, replies, editing, attachments, avatars, typing indicators, notifications, and read receipts remain out of scope.

### Design

The app derives date separators and sender-group boundary context from the engine-provided message order without persisting presentation state. A lazy, readable-width conversation renders neutral incoming bubbles and Aurora-accent outgoing bubbles with compact sender, time, and final-outgoing delivery metadata. Empty state, selectable text, combined VoiceOver labels, Dynamic Type, light/dark contrast, and Reduce Motion are first-class.

`ScrollViewReader` and viewport geometry provide smart follow: the view follows while within roughly 80 points of the bottom, always follows a successful local send, and otherwise displays a floating New Messages control. Delivery-only mutations never create unread counts or move the viewport. The header derives nearby count from current group membership and reachable identities.

The composer lives in a bottom safe-area inset, supports one through five lines, disables whitespace-only or oversized drafts, and reveals byte feedback after 75% capacity. `MeshChatCoordinator.send(_:to:)` returns an awaited success result so a failed local send preserves the exact draft and focus.

### Decision log

- Use a familiar messenger layout rather than Aurora's assistant transcript or a rugged utility list.
- Build with native SwiftUI and existing tokens rather than adding a chat framework.
- Group metadata concisely rather than repeating it on every bubble or hiding it behind taps.
- Preserve engine order and derive grouping in linear time; do not reorder delayed Mesh traffic.
- Use smart follow plus a New Messages control instead of unconditional auto-scroll.
- Clear the composer only after durable local acceptance so critical text is not lost on failure.
- Keep the redesign presentation-only; do not expand the text-chat feature set.
