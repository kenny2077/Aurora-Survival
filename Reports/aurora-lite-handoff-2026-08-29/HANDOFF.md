# Aurora Lite physical handoff — 2026-08-29

Device: Kenny's iPad (iPad Pro 11-inch, 4th generation)

Exactly three Lite conversations were executed:

1. `Hi` passed: natural greeting, no weather/update disclaimer, no sources.
2. `How to start a fire` produced useful guidance but the model router labeled it `general`, so the reviewed source card was missing.
3. `如何在野外找到并净化水源？` produced an English, ungrounded answer because the model router returned `general/en`.

The two observed routing failures were repaired after the run with deterministic handling for explicit fire requests and Chinese survival requests, response-language correction, and an English retrieval fallback for explicit Chinese water questions. The focused regression test and final signed device build passed. They were not physically rerun because the approved physical limit was exactly three conversations.

Artifacts:

- `report.json`: raw response, source state, routing envelope, timing, thermal state, and pass flags.
- `greeting.png`, `fire.png`, `water-zh.png`: screenshots captured immediately after each response.

The final installed app is `com.example.AuroraSurvivalAgent`, with Lite model `1.2.0` and shared RAG `3.2.0-dev` active in Aurora's fresh sandbox.
