# Reliable Package Downloads

## Understanding

- Large signed packages must survive pauses, network failures, relaunches, and
  ordinary app updates without silently restarting completed work.
- Download, verification, installation, and runtime validation are separate
  phases and must be visible to the user.
- Package signatures, SHA-256 checks, path safety, and atomic activation remain
  mandatory; corrupt or unauthenticated bytes are never retained as trusted.
- Downloads remain sequential to limit heat. Serious thermal state warns but
  does not automatically pause, by owner decision.
- Idle AI runtimes are released during large transfers. Maps keeps location
  active only while visible or explicitly recording a trail.
- This work does not tune Lite inference or change the R2 host.

## Assumptions

- iPhone 13 remains the minimum validation device.
- Checkpoints are 16 MiB, so an interruption loses at most the active chunk.
- The existing R2 endpoint remains acceptable; direct range probing measured
  about 23 MB/s on September 8, 2026.
- Local transfer diagnostics contain phase, byte, error, and thermal data only;
  they never contain prompts, photos, or location.

## Design

Background URLSession downloads one signed artifact as sequential HTTP ranges.
Each completed range is appended and synchronized to a durable `.partial` file.
Its actual file length is the authoritative checkpoint. Content-Range, total
length, and the remote validator are checked before appending. The finished file
is SHA-256 verified before the staging directory is atomically activated.

Recovery first reconciles pending identifiers with the activation index.
Installed packages clear stale markers, and installed dependencies are never
downloaded again. Recoverable transport, storage, and file-operation failures
retain checkpoints; signature, path, size, and checksum failures remove unsafe
staging bytes. Concurrent active-pack refreshes request a follow-up pass instead
of dropping the newer state.

The UI reports Downloading, Verifying, Installing, Paused, Ready, and Failed.
Failure text and resumable progress are visible. A thermal warning may accompany
an active transfer without changing its state.

## Decision log

- Chosen: checkpointed background ranges. Whole-file resume data was rejected
  because it is opaque and may become unusable; foreground-only ranges were
  rejected because they cannot continue when iOS permits background work.
- Chosen: sequential 16 MiB ranges. Parallel ranges were rejected because the
  measured host bandwidth did not justify extra heat and ordering complexity.
- Chosen: retain safe checkpoints on recoverable failures and delete only data
  that cannot still satisfy the signed manifest.
- Chosen: warn and continue at serious thermal state, as requested. Automatic
  pause remains a possible future policy if physical testing shows instability.
- Chosen: keep Lite inference tuning and hosting migration out of this repair.
