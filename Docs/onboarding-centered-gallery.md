# Aurora Centered-Gallery Onboarding

## Intent

- Keep the existing three-page onboarding, legal acceptance, and model routing.
- Replace the generic icon fallback with Aurora's real app artwork.
- Give each page one clear idea, concise human copy, and intentional whitespace.
- Keep legal text complete and offline while presenting one agreement action.
- Limit connected-iPad verification to three onboarding cases.

## Decisions

- Use a centered gallery rather than a dense field-guide layout.
- Use a shared top-anchored editorial grid so titles and primary content begin at
  the same vertical level on every page.
- Reduce page-one typography and collapse its consent disclosure to one quiet
  sentence plus the existing legal hub link.
- Align feature rows with a fixed symbol column and a shared leading text edge.
- Describe Aurora plainly as "Offline AI help for the outdoors."
- Use "Source-backed" and "Private by design" to communicate grounding and
  local processing without implying that every generated answer is verified.
- Start Lite or Expert directly from its page-three Download button, then open
  Tools as the authoritative download-progress surface.
- Use one `Legal & Privacy` hub with agreement, privacy, and model-document destinations.
- Keep `legalSchemaVersion` unchanged because legal substance is reorganized, not changed.
- Use directional slide-and-fade transitions; Reduce Motion uses a crossfade.
- Preserve the 752-point app boundary and use a narrower 620-point gallery.

## Non-goals

This polish does not change onboarding persistence, package catalogs, downloads,
model activation, inference, or Cloudflare distribution.

## Assumptions

- The visible consent sentence may be shortened without changing what the
  existing versioned acceptance records.
- Complete legal and model-license text remains available from the legal hub.
- The model page retains dynamic sizes, eligibility, routing, and Wi-Fi guidance.
- Wi-Fi-default behavior remains enforced even though its onboarding note is
  removed.

## Polish decision log

- Chosen: shared editorial grid with a consistent top anchor and narrower content.
- Considered: vertically centering each page independently; rejected because
  different content heights cause visible jumping between pages.
- Considered: placing all content in larger cards; rejected because it adds
  visual weight when the requested direction is quieter and less wordy.
- Chosen: always label the two onboarding model controls "Download" and leave
  restored-state details to Tools.
- Considered: state-aware onboarding labels; rejected to keep first-run model
  selection simple and consistent.
