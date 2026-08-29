# Model Download Progress and Tier Isolation

## Understanding

- Starting Lite downloads Lite and its required shared RAG package.
- Expert remains idle and independently selectable unless Expert itself was started.
- The active tier shows a linear byte-weighted progress bar and percentage.
- Pause and resume preserve the visible percentage.
- Shared RAG remains one reusable package and is not duplicated per tier.
- One connected-iPad UI test covers the core behavior before handoff.
- The handoff build is clean-installed without being launched.

## Assumptions

- A rounded percentage is required; estimated remaining time is not.
- Existing background transfer, verification, and atomic activation behavior is unchanged.
- Shared-RAG failures and progress belong visually to the tier setup that initiated them.

## Final Design

`AppModel.modelSetupState(for:)` aggregates shared-RAG progress only while the
requested tier's own model setup is active or paused. A dependency transfer
started for Lite therefore cannot make Expert appear active.

The selected tier's percentage remains weighted by the declared byte counts of
the shared RAG and model packages. `ToolsView` adds a full-width linear progress
row beneath the active tier card with a visible percentage and pause/resume
action. Accessibility identifiers expose both progress and state.

The focused connected-iPad test starts Lite, verifies Lite progress is visible,
and verifies Expert remains available without Expert progress. The app is then
clean-installed for manual testing without launching it.

## Decision Log

- Chosen: the selected model task owns presentation of shared-dependency
  progress. This is the smallest change consistent with the existing download
  architecture.
- Rejected: separate per-tier download-session objects. They add persistence and
  synchronization complexity without improving the required two-tier behavior.
- Preserved: a single shared RAG package, signed catalogs, background transfers,
  resumability, hash verification, and atomic activation.
