# Saved Waypoint Focus and Map Panel Simplicity

## Understanding

- Tapping a saved waypoint must animate the current map back to that point.
- The behavior must work with both Apple and downloaded map surfaces.
- Current zoom and bearing should remain stable where the map engine permits.
- Offline Maps and idle Trail Recording do not need explanatory copy.
- The download-management action is labeled “Downloads.”
- Changing among the three map modes provides one subtle selection haptic.
- Storage, recording, map packages, networking, and privacy behavior remain unchanged.

## Design

`MapPackView` publishes a transient waypoint-focus request when a saved waypoint
button is selected. Each native map bridge consumes a new request once and
animates its camera to the requested coordinate without recreating the map.
Saved-waypoint accessibility identifiers remain stable.

Mode buttons use native selection feedback only when the selected mode actually
changes. The two idle descriptions are removed without affecting status or
recording information.

## Assumptions

- A selected waypoint is already valid persisted data.
- Camera movement is local and requires no network request.
- Light selection feedback is appropriate and respects system haptic behavior.
- Repeated selection of the same map mode does not emit feedback.

## Decision Log

- Chose a one-shot focus request instead of rebuilding the map, preserving
  camera state and avoiding visual jumps.
- Chose single-waypoint focus instead of fitting every waypoint because the
  selected saved point is the user’s explicit destination.
- Chose native light selection feedback over custom haptic patterns for a calm,
  consistent interaction.
- Limited copy removal to the requested idle descriptions; safety and failure
  messages remain available.
