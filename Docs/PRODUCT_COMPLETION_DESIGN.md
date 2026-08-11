# Aurora product completion design

Updated: 2026-07-31

## Understanding summary

- Aurora will be a polished universal iPhone/iPad incident assistant, with
  the iPhone 13 as the minimum Lite-model acceptance device.
- The exact signed Gemma 3 1B IT Q4_K_M package must be downloadable, installed
  into the app sandbox, selected by the verified registry, and exercised by the
  real on-device chatbot.
- Reviewed knowledge/manual content and two Minnesota map products must use the
  same resumable, signed, hash-verified package lifecycle.
- The small map covers the Twin Cities metro. The large map covers Minnesota.
- Downloaded maps must render without networking and retain OpenStreetMap and
  Protomaps attribution; a readiness-only placeholder is not sufficient.
- Existing user-facing workflows must be implemented honestly and verified on
  the iPhone 13, including safety, citations, OCR/photo, preparation, package
  management, accessibility, interruptions, and offline relaunch.
- A Personal Team development build can prove product behavior, but production
  App Store signing, hosting, commerce, legal review, and expert content approval
  remain separate release gates.

## Assumptions and non-functional requirements

- “Menu” means downloadable manual/knowledge content; the navigation menu will
  also be included in the physical usability pass.
- Preparation Mode may access the network for explicit downloads. Incident Mode
  denies catalog, artifact, purchase, refresh, analytics, and telemetry traffic.
- The development catalog is served from the Mac on the local network. It is an
  untrusted transport: Ed25519 signatures, exact sizes, SHA-256 checks, safe
  paths, policy, entitlement, recall, and device checks remain authoritative.
- Downloads expose size, storage requirements, progress, retry/resume, verified
  installation, activation, deletion, and understandable failures.
- The iPhone 13 Lite gate remains first token at or below three seconds and at
  least eight generated tokens per second, with no OS termination or serious
  thermal transition during the standard sustained script.
- Model-required Ask, the SQLite Field Manual, survival retrieval, and
  citations remain available when any optional download is absent or fails.
- Private keys and model/map artifacts remain outside Git. Public licenses,
  attribution, manifests, schemas, and verification evidence are retained.

## Approaches considered

### Selected: signed development catalog and local range server

Use the existing package coordinator with a small signed catalog and a
range-capable development server on the Mac. The same app flow handles model,
knowledge, and map packages. The delivery base URL can later point at production
HTTPS object storage without changing the trust boundary.

### Rejected: file import only

File import is useful as a recovery tool but does not prove download progress,
range resume, preparation-mode policy, or catalog behavior.

### Deferred: production cloud hosting now

Cloud hosting is required before publication, but choosing credentials, vendor,
cost controls, authentication, and retention before the device workflow passes
would create an external dependency without reducing product risk.

## Final design

1. A catalog service presents verified downloadable products and their installed
   state. Debug builds accept a user-editable local catalog URL; release builds
   require production HTTPS configuration.
2. `PackageDownloadCoordinator` reports progress and supports cancellation and
   retry without weakening its strict HTTP range checks. Installation remains
   staged and atomic.
3. The model package activates through `PackageInstaller`,
   `ActivePackRegistry`, and `ActiveModelRuntimeResolver`; only then can
   `LlamaXCFrameworkBackend` load the GGUF.
4. Knowledge packages supply reviewed, attributed SQLite retrieval content and
   never replace the bundled emergency core.
5. Twin Cities and Minnesota packages contain PMTiles, an offline style,
   glyph/sprite assets, attribution, bounds, freshness, and optional routing
   artifacts. A checksum-pinned MapLibre Native Swift package renders only the
   verified active local files.
6. A calm preparation-focused Download Center separates model, guides, and maps;
   Incident Mode disables all download actions. Status language distinguishes
   downloaded, verified, active, incompatible, recalled, and failed states.
7. Debug diagnostics write structured physical-device evidence for inference
   latency/rate, memory, thermal and battery snapshots, package lifecycle,
   fallback, OCR, offline rendering, relaunch, and interruption checks.
8. Figma uses an iOS design-system library as visual reference, SF Pro/Dynamic
   Type typography, reusable components, accessible contrast, large controls,
   and layouts for the iPhone 13 first. SwiftUI remains the implementation source
   of truth and every visual state must remain functional at accessibility sizes.

## Decision log

1. **Two map products:** Twin Cities is the fast small download; Minnesota is
   the larger statewide download.
2. **Local server before cloud:** proves the real network/package workflow while
   keeping hosting credentials and cost outside the first physical acceptance.
3. **MapLibre Native plus PMTiles:** provides an open, GPU-accelerated iOS map
   renderer and compact single-file regional vector maps.
4. **One package trust boundary:** model, knowledge, and map downloads share
   signature, integrity, activation, rollback, and recall controls.
5. **Physical evidence is authoritative:** simulator and Mac results may catch
   regressions but cannot approve iPhone memory, thermal, energy, camera,
   accessibility, or offline behavior.
6. **No placeholder success:** unavailable production services remain visibly
   unavailable rather than receiving a green status or simulated result.
7. **Sustained inference uses the product session:** five sequential grounded
   prompts in one Incident Mode launch prove warm-session reuse, citations,
   fallback avoidance, throughput, and thermal state. Repeated cold launches or
   a separate benchmark executable do not satisfy this product gate.

## Completion evidence

- Automated: focused package/catalog/map/runtime tests, all Swift tests,
  structural validation, reproducibility, simulator suites, arm64 build, and
  strict signature verification.
- Physical iPhone 13: signed install/launch, exact model identity, real generated
  answer, safety/citation/fallback matrices, measured Lite performance, both map
  downloads and offline rendering, guide download, camera/OCR, accessibility,
  background/foreground, termination/relaunch, Airplane Mode, Low Power Mode,
  storage failure, cancellation/resume, and package tamper rejection.
- Publication audit: app icon and screenshots, privacy manifest and disclosures,
  licenses/attribution, production keys and hosting, App Store identifiers and
  products, archive validation, legal/expert review, and no unresolved release
  blocker represented as complete.
