# Map Menu Redesign

## Intent

- Move Map Type into the top navigation bar so it cannot cover the compass.
- Keep Apple Map north-up during device-heading changes while preserving
  two-finger camera rotation.
- Replace obstructive waypoint placement with long press and haptic feedback.
- Add subtle boundaries between Waypoints, Record, and Offline Maps.
- Keep offline-map management compact and open installed maps from a trailing row action.
- Let one deliberate map tap hide or restore map-specific chrome without
  affecting the map camera or active survival features.

## Assumptions

- The heading indicator is orientation guidance, not turn-by-turn routing.
- A missing heading falls back to each map engine's native location-only state.
- A missing heading shows the current-location dot without a fabricated cone.
- Existing waypoint storage, attachments, signed-map validation, trail recording, and offline guarantees remain unchanged.

## Design

- MapKit and MapLibre use a simultaneous 0.5-second long press to open the
  existing waypoint editor at the pressed coordinate. A non-cancelling native
  single tap on empty map space toggles map chrome; pan, pinch, rotation,
  annotations, native controls, and long press do not. The Waypoints mode
  remains the saved-waypoint manager.
- Apple maps use MapKit's `follow` mode with rotation enabled. The camera never
  consumes device heading, while the system-blue gradient cone displays
  `device heading - camera heading` so it remains geographically correct after
  manual rotation.
- Apple Map uses an adaptive native `MKCompassButton` above Aurora's measured
  bottom chrome and a centered native `MKScaleView` at the highest safe top
  position. The redundant map title is removed. Offline maps retain MapLibre's
  native location and chrome.
- Map Type uses top-bar placement. The three mode buttons retain the glass selection treatment with thin dividers between them.
- Offline Maps mode uses a short description with a compact trailing Manage
  Downloads action. Installed map rows place a compact Open Map action beside
  the map name and retain layer selection when needed.

## Decision Log

- Physical testing showed MapKit couples its public native heading beam to
  `followWithHeading`. Aurora therefore uses native MapKit camera controls with
  one custom camera-relative heading cone.
- Restored manual rotation after confirming that disabling `isRotateEnabled`
  also removed a normal Apple Map gesture users expect.
- Retired center-pin and direct-tap placement. Long press now provides one
  deliberate creation gesture without blocking the map view.
- Moved map opening into Download Center to keep the map overlay uncluttered.
- Limited camera state publication to completed movements for performance.
- Selected native map recognizers over a SwiftUI overlay so clean-map mode does
  not interfere with map gestures. Hiding chrome is transient visual state;
  trail recording, selected mode, camera, and stored data remain active.
- Retained the Offline Maps title in Download Center while removing it from the
  visible map, where the title conveyed no useful context.

## Verification

The chrome polish runs exactly three focused signed physical-iPhone journeys
covering top chrome and the compact Offline Maps panel, clean-map gesture
isolation with recording and long-press preservation, and compact installed-map
routing. It retains screenshots and one `.xcresult`, then installs and launches
the exact tested build.
