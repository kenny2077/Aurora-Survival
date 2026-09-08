# v1.1.0 release review

## Owner decisions

- Use the existing R2 development endpoint initially; variable throttling and
  lack of production support remain accepted availability limitations.
- Run ten physical-device images for this release pass, not a fresh 85-image
  exam. This is a reduced smoke check, not equivalent accuracy evidence.
- Use concise factual legal notices; no new arbitration, governing-law, or
  liability-cap provisions. Preserve third-party terms and statutory rights.
- Keep the approved UI and offline architecture. Prepare TestFlight first;
  public App Store submission follows a final safety and manual review.

## Review findings

| Severity | Evidence and impact | Disposition |
| --- | --- | --- |
| High | Download coordinator used unauthenticated manifest sizes/paths before install verification. | Authenticate before staging/download; regression coverage. |
| High | Lexical artifact containment allowed an existing symlink to escape staging. | Reject symlink components, including when the destination is absent; regression coverage. |
| High | Development private key had appeared in prior tool output. | Replaced local key and re-signed local development envelopes; production trust unchanged. |
| Medium | In-flight scanner tasks could restore results after session release. | Generation guards reject stale completion. |
| Medium | Package replacement compared only encoder digest. | Compare full descriptor so table/version replacement releases the runtime. |
| Medium | Shared preparation waiters could overwrite load timing. | Clear the preparation start time after recording it. |
| Medium | Prior candidate-selection evidence described single loads as if they established cold-load p95. | No cold-load p95 claim; retain fp16 and original reports for audit. |
| Medium | Legal copy still described retired features and omitted download-server metadata. | Factual first-release notices approved by owner; not legal certification. |

## Verification record

- Structural validator passed; all 30 Swift test classes passed after package
  hardening, including 12 package-security tests.
- Clean Release build and device Debug build passed before final legal changes;
  final builds must be repeated after those changes.
- Public R2 artifact SHA-256, byte counts, and HTTP ranges verified.
- Reachable Git history: 1,111 blobs scanned for recognizable private keys,
  GitHub tokens, and AWS keys; zero pattern matches. This is not an exhaustive
  credential audit and does not cover external logs or account compromise.
- Corrected synthetic 12 MP check: ten images passed, maximum 313 ms, peak
  footprint 623,806,488 bytes, nominal thermal state. See retained JSON.
- The 23.5-second model load is a single observation, not a percentile. Synthetic
  images do not replace the owner's real camera/library review.

## Cleanup

Removed two unreferenced obsolete implementation checklists and the superseded
August 22 blocked-launch report. They remain recoverable from Git history.
Retained source audits, ADRs, provenance, and benchmark results needed to explain
current architecture and limitations.

## Outstanding release checks

The ten-photo public download and spaced burst completed on package 1.0.1.
All ten top-one predictions matched the PC and all ten labels were in top-five;
peak footprint was 656,525,168 bytes and thermal state stayed nominal/fair.
The original JSON is retained unchanged: its `passed: false` reflects a harness
bug that included first prediction in warm p95. The raw timings were
1283, 201, 232, 199, 198, 208, 216, 198, 219, 189 ms. Excluding the separately
reported first prediction gives nine warm samples, nearest-rank p95 232 ms.
The harness calculation is corrected; no new measurements are invented.
The compute-plan query reported GPU preference under `.all`; this is not an
observed per-operation execution trace or proof of an ANE failure. Do not claim
that this run verified ANE execution. No CPU+GPU fallback was selected.

Final legal-copy build/tests, final code safety pass after the requested push,
ten-photo public-download report, package removal/reinstall and lifecycle checks,
CI, real camera/library review, and App Store Connect account/metadata review.
No security certification, App Review approval, or production SLA is claimed.

## Post-push safety pass

Reviewed the pushed candidate across package trust and activation, transport and
resume, scanner lifecycle, model routing, photo/location handling, generated
guidance, Release exclusions, and legal disclosures. This is a source/configuration
review with automated regression checks, not a penetration test or independent
medical/content certification.

- Final regression run: all 30 Swift test classes passed; species packaging,
  public-verification, R2 release, Expert packaging, and reproducibility checks passed.
- Signed Release archive succeeded. Its resources contain the production keyring
  and privacy manifest, not the development keyring. Binary string checks found
  no species/physical benchmark environment controls or development key ID.
- One follow-up found: scanner preparation task identity still used only encoder
  digest. It now includes package identity/version, matching runtime invalidation.
- Catalog verification checks current key validity. Installed-package verification
  checks signing-time validity to preserve offline availability; revocation relies
  on removing trust/recall, not wall-clock expiration of an installed model.
- URLSession uses platform HTTPS validation; cross-host redirects remain permitted
  for artifact hosting. Signatures and hashes authenticate the result. No claim
  of a custom redirect allowlist is made.
- Source-only checks cannot prove absence of memory warnings, all SDK collection,
  harmful generated advice, or accessibility defects. Camera/library and actual
  airplane-mode journeys remain owner manual checks.
- Ten-photo sampling does not establish 504-class generalization or replace the
  full 85-image acceptance exam. Its reduced scope is explicitly owner-approved.

The candidate remains suitable for further testing, not a completed public-store
release. Store contact/privacy URL, account access, metadata declarations, and
manual approval remain required before submitting publicly.

## Distribution status — September 8, 2026

The production-key-signed species catalog was promoted after CI and the
owner-approved ten-photo device gate passed. The app now uses:
`https://pub-6ac45181bc644cc3b7827299486a5230.r2.dev/species/catalog.json`.
The catalog resolves package `species.bioclip2.north-america-504@1.0.1` with
609,125,423 verified artifact bytes. This remains an owner-accepted development
endpoint with variable rate limits, not a production availability SLA.

Debug builds use the separately signed `catalog-development.json`, which exposes
the existing beta Lite/shared-knowledge packages alongside the production-signed
species package. Release builds continue to exclude development trust and use the
species-only catalog until Gemma's production legal-review gate is satisfied.
