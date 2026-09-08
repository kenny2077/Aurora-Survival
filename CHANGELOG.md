# Changelog

## 1.1.0 — release candidate

- Add optional production-key-signed BioCLIP species package 1.0.1 on R2.
- Authenticate package manifests before downloading artifacts and reject symlink
  path escapes, with regression tests.
- Prevent stale Species ID tasks from restoring released session state.
- Rotate exposed development signing material; production keys are unchanged.
- Refresh first-release legal notices, contribution guidance, MIT licensing,
  third-party notices, and privacy API declarations.
- Preserve the approved scanner UI and existing app data during updates.

Validation: 30 Swift test classes passed before final copy changes; final CI
results are the authority for the pushed commit. Public download/install and
ten-photo burst completed; nine warm predictions ranged from 189 to 232 ms.
First prediction was 1,283 ms; model load was a separate single measurement.

Limitations: R2 development endpoint, no fresh 85-image release exam by owner
decision, no cold-load p95 claim, and no guaranteed ANE execution. TestFlight,
manual camera/library review, and public App Store review remain separate gates.

## 1.0.0

Existing release tag preserved. Earlier development evidence remains in Git
history and the retained architecture and benchmark records.
