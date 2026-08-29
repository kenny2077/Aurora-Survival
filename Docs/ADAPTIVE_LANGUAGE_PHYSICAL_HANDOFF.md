# Adaptive-language physical handoff

Updated: 2026-08-29

## Completed before handoff

- Protected pre-overhaul checkpoint pushed to `origin/main` at
  `2a20245933f4965c477d157dbd2efa5d74406019`.
- Adaptive on-device language detection, strict two-field routing, compact
  Lite/Expert answer envelopes, reviewed source mapping, localized malformed
  grounded-response suppression, same-language Expert history filtering, and
  model-led answer prompts are implemented.
- System, Light, and Dark appearance preferences are persisted at the app root;
  Reset to Defaults restores System. The enabled send control uses inverse
  semantic foreground/background colors.
- Swift package tests, generated Xcode unit tests, app build, runtime/source
  validation, and whitespace checks are the required automated checkpoint.

## Deliberately not run overnight

No physical model conversation was started after the user ended the session.
The connected iPad therefore still requires exactly six acceptance turns. Do
not add exploratory chat turns to this run.

The maintained runner is `tools/run_physical_tier_comparison.py`. Its fixed
fixture contains exactly these three prompts and executes Expert, then Lite:

1. `Where can I find food in the wilderness?`
2. `在哪里可以找到并净化水源？`
3. `¿Cómo puedo construir un refugio temporal para pasar la noche?`

Build a signed Debug app for destination
`00008112-001D484C2678A01E`, confirm the previously installed signed Lite,
Expert, and shared-RAG packages remain active, then run:

```sh
python3 tools/run_physical_tier_comparison.py \
  --device 00008112-001D484C2678A01E \
  --run-id adaptive-language-2026-08-30 \
  --app-bundle /absolute/path/to/Aurora.app
```

The runner rejects any count other than six and retains, per turn, the exact
answer, requested and detected language, reviewed-source state, latency,
memory/thermal state, automatic pass/fail reasons, and a screenshot.

## Manual appearance-only check

Without sending a chat message, switch Settings → Appearance through System,
Light, and Dark. Confirm the choice applies immediately, persists after
relaunch, Reset to Defaults returns System, and the enabled send arrow is light
on a dark circle in Light appearance and dark on a light circle in Dark
appearance. Then hand over for manual Expert photo and broader product testing.
