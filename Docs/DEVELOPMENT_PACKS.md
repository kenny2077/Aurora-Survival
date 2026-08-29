# Development package trust and lifecycle

Updated: 2026-07-28

Aurora keeps production and development trust separate:

- `trusted_package_keys.json` is the production keyring and remains empty until
  production keys are provisioned.
- `development_trusted_package_keys.json` contains only the current development
  public key. The app reads it only in `DEBUG`.
- Xcode Release builds exclude the development keyring from copied resources.
- The matching private key lives at
  `.trailguard/development/package-signing-key.pem`, which is ignored by Git.
- Development-fixture knowledge is accepted only in `DEBUG`; Release continues
  to require `review_status = approved`.

The checked-in public key is not production authority. Rotating it requires a
new key ID, a new local private key, updated signed fixtures, and rerunning the
Release-resource exclusion check.

## Prepare and validate

```bash
# one-time local key creation; never commit this file
mkdir -p .trailguard/development
openssl genpkey -algorithm ED25519 \
  -out .trailguard/development/package-signing-key.pem
chmod 600 .trailguard/development/package-signing-key.pem

# build compiled and signed v1/v2 development packs
/tmp/aurora-dev-venv/bin/python tools/prepare_development_packs.py

# verify real Swift install, activation, rollback, recall, and tamper rejection
swift run aurora-pack-check \
  Resources/Packages/development_trusted_package_keys.json \
  .trailguard/development/knowledge-lifecycle/v1 \
  .trailguard/development/knowledge-lifecycle/v2
```

`prepare_development_packs.py` refuses to overwrite an existing output
directory and refuses a private key that does not match the committed
development public key.

## Release check

After regenerating the Xcode project, build both configurations and inspect the
products:

```bash
xcodegen generate

xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AuroraDebugTrust \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Aurora.xcodeproj -scheme Aurora \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/AuroraReleaseTrust \
  CODE_SIGNING_ALLOWED=NO build
```

The Debug product must contain `development_trusted_package_keys.json`; the
Release product must not.
