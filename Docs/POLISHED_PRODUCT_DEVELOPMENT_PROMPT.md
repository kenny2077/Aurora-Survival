# Aurora product development prompt

Continue Aurora as a fully offline universal iPhone/iPad product with four independent roots: **Ask · Manual · Maps · Tools**.

Preserve these binding rules:

- Ask requires a usable signed Lite or Expert model; with no model, show setup and keep Manual/Maps accessible.
- Lite targets iPhone 13 class. Expert (`vision_expert`) targets capable high-memory hardware but stays validation-locked until signed model/projector, mtmd integration, and physical vision acceptance pass.
- Select by live memory, storage, thermal, Low Power Mode, trust, recall, and runtime state—not marketing names alone. Expert degrades to Lite.
- The immutable SQLite corpus and exact Manual anchors remain shared by Ask and Manual.
- Maps presents only map packages. Tools presents only Lite and Expert model packages.
- Keep signed catalogs, hashes, atomic activation, rollback, recall, cached entitlements, and Incident-mode network denial.
- Do not reintroduce readiness, trip sheets, vehicle profile/applicability, OBD, standalone status, duplicate model settings, in-app SOS, chat Clear, accounts, analytics, or cloud inference.
- Do not erase retired user files; simply stop reading them.

For each increment, write the focused contract, make the smallest implementation, run repository validation and the full Swift suite, then run relevant simulator and named physical-device checks. Never present an unrun device, safety, performance, or release gate as complete.
