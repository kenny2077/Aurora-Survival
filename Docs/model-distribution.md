# Aurora model distribution

Aurora uses one signed package-catalog schema (`schemaVersion: 1`) for local,
beta, and production delivery. Model binaries, credentials, and signing keys
must not be committed.

## R2 layout

The `aurora-survival-models` bucket uses immutable versioned objects:

```
catalog-development.json
species/catalog.json
beta/catalog.json
beta/packages/<package-id>/<version>/...
production/catalog.json
production/packages/<package-id>/<version>/...
```

Versioned objects receive `public,max-age=31536000,immutable`. Catalog objects
receive `no-cache,max-age=0,must-revalidate` and are uploaded last. Keep at
least the active and immediately previous versions in R2; rollback is a signed
catalog promotion, never an overwrite of a versioned object.

## Prepare an audited beta release

```sh
.trailguard/tooling-venv/bin/python tools/publish_r2_models.py prepare
```

The command verifies package signatures, artifact hashes and sizes, shared-RAG
dependencies, runtime metadata, and required legal files. It hard-links local
binary assets into the ignored staging directory when possible and writes only
release metadata to `Releases/Models/beta-release.json` for source control.

Production preparation and publication are deliberately blocked until a
professional legal review approves the global terms and Gemma redistribution
package. The bundled package includes the April 1, 2026 Gemma Terms, NOTICE,
prohibited-use reference, and modification record, but those files do not by
themselves satisfy the release gate.

## Publish to R2

Authenticate Wrangler and configure an `rclone` S3 remote named `r2` with a
bucket-scoped token stored outside the repository. Wrangler is used only for
bucket setup; `rclone` is required for resumable multipart uploads because the
model files exceed Wrangler's 315 MB limit. Create the bucket once, then attach
`downloads.auroraforgelab.com` under the bucket's **Settings → Custom Domains**:

```sh
npx wrangler r2 bucket create aurora-survival-models
```

Then publish and verify every public artifact supports byte ranges:

```sh
.trailguard/tooling-venv/bin/python tools/publish_r2_models.py publish \
  --public-base-url https://downloads.auroraforgelab.com
```

The publisher refuses to replace any publicly visible versioned object, uploads
large files with multipart transfer, uploads the catalog only after all package
files, and requires public HTTPS plus `206` responses. Debug and beta builds use
the current development-signed catalog:

```sh
xcodebuild ... AURORA_PACKAGE_CATALOG_URL=https://downloads.auroraforgelab.com/catalog-development.json
```

The August 27 `beta/catalog.json` snapshot predates the September 7
development-key rotation and is rejected by the current trust store; re-sign and
republish it before pointing any build at it.

Release builds use `https://downloads.auroraforgelab.com/species/catalog.json`.
Future production model releases use
`https://downloads.auroraforgelab.com/production/catalog.json` after the legal
review gate passes.

The previous public development URL was disabled on September 14, 2026 after
the owner approved an early cutover and the custom-domain catalogs and range
requests passed verification. Older builds that still reference `r2.dev` can no
longer fetch packages.
