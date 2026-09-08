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
- Generated guidance may be incorrect even when accompanied by references;
  citation validation is not a guarantee that every generated statement is safe.

## Supported versions

Version 1.1.0 is under release verification. No security certification is claimed.
Aurora is an educational aid, not a certified emergency or medical product.
Report issues against the latest release or `main`, with reproduction details
and no private user data. If private vulnerability reporting is unavailable,
contact the repository owner through an existing private channel before sharing
exploit details. Never post credentials in issues, logs, or chat transcripts.

Development signing keys must never be used for production. Treat a key exposed
in tool output as compromised, remove its trust, and regenerate development
packages. Release builds exclude the development keyring and benchmark controls.

The initial R2 development endpoint is an accepted availability limitation, not
a reason to weaken HTTPS, signatures, hashes, or package-path validation.
