# TrailGuard llama.cpp runtime

This package isolates TrailGuard's optional native inference dependency from
the dependency-free core package.

- Upstream: `ggml-org/llama.cpp`
- Release: `b9637`
- Commit: `aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3`
- Published: 2026-06-14
- Artifact: `llama-b9637-xcframework.zip`
- SHA-256: `46c7dad871f804d82399ddcfeb54d23b6469888801fc35124d7e33e543a9bef7`
- License: MIT; see `LICENSE.llama.cpp`

Swift Package Manager verifies the archive checksum before exposing the
official `llama` XCFramework. The wrapper supports text-only, single-turn,
deterministic greedy generation. Model selection, model licensing, signed
model packaging, and physical-device acceptance remain separate gates.
