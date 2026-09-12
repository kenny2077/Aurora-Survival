# Contributing to Aurora Survival

Aurora Survival is open source under the MIT license. Contributions are welcome;
please open an issue to discuss substantial changes before sending a pull request.

## Priorities

Prioritize reproducible bugs, package security, privacy, device compatibility,
and measured performance. Discuss new features before implementation. Keep
changes focused; do not mix fixes with unrelated refactoring or formatting.

## Development

Use Xcode with the iOS 26 SDK, XcodeGen, and Python 3.11 or newer. Generate the
Xcode project from `project.yml`; do not edit the generated project directly.

```sh
xcodegen generate
python3 tools/validate.py
python3 tools/run_swift_tests.py
python3 tools/test_species_packaging.py
```

Open `Aurora.xcodeproj` for signed device builds. Provisioning credentials,
downloaded weights, signing keys, and local build outputs must not be committed.
Model conversion belongs on the higher-memory experiment machine; use small
local smoke tests before running full physical-device exams.

## Review and commits

Search existing issues and changes before starting. Explain the bug, the smallest
fix, the regression test, and any remaining risk. Include device/OS details for
UI, memory, thermal, or performance changes. Never describe a single measurement
as a percentile. Do not tune on sealed evaluation images.

Use concise conventional commits, for example `fix(packages): reject symlink
artifact paths`, `docs: clarify offline downloads`, or `chore(release): prepare
v1.1.0`. Comments should explain an invariant or a non-obvious decision, not
repeat the code. Preserve approved UI and existing app data.

Security reports follow [SECURITY.md](SECURITY.md). Contributions to Aurora-owned
code use [MIT](LICENSE); preserve all third-party notices and license exceptions.
