# Security policy

Aurora handles safety-sensitive guidance, photos, approximate location,
and downloadable model/map data.

## Report privately

Do not open a public issue for vulnerabilities involving package signatures,
artifact verification, path traversal, unsafe medical or vehicle guidance,
location exposure, or a bypass of offline corpus/package integrity. Use GitHub's
private vulnerability reporting for this repository when enabled.

## Security invariants

- Incident text, photos, and location remain on device.
- Downloads are data packages, never executable scripts.
- Every package requires a trusted Ed25519 signature and verified artifacts.
- Package paths cannot be absolute or traverse outside staging.
- An invalid, expired, incomplete, or tampered package is never activated.
- Critical safety and prohibited-scope rules bypass model generation.
- Uncited model instructions are discarded.

## Supported versions

No production version exists yet. The `main` branch is an engineering prototype
and must not be used as a certified emergency product.
