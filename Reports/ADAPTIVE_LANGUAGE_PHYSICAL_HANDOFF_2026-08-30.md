# Aurora Adaptive-Language Physical Handoff — 2026-08-30

## Outcome

The fixed six-turn physical run completed on the connected iPad without a crash, thermal warning, unsupported-channel text, or wrong-language reply. The release gate did **not** pass: Expert produced reviewed sources in all three languages, but Lite failed reviewed retrieval in every case and its Spanish grounded answer was suppressed after malformed model output.

No additional model conversations were run after the required six.

## Checkpoints

- Pre-overhaul checkpoint: `2a20245933f4965c477d157dbd2efa5d74406019`
- Adaptive-language and appearance implementation: `2987264b35e41d87e4fc7340aacddf4218bb3b55`
- Remote: `origin/main` at `kenny2077/Aurora`

## Device and memory

- Device: iPad Pro (11-inch) (4th generation), `iPad14,3`, Apple M2
- OS: iPadOS 26.6
- Storage class: 128 GB; free before the run: 47,766,559,693 bytes
- Physical memory: 7,902,838,784 bytes
- Available memory before model testing: 5,340,970,192 bytes
- Highest measured Aurora footprint: 1,671,727,936 bytes (about 1.56 GiB)
- Thermal state: nominal before and after the six turns
- Installed packages: Lite and Expert both reported ready offline

The measured peak is substantially below the proposed 5.5 GB Expert ceiling. It is an observed process footprint for these prompts, not a guarantee for every context or image workload.

## Exact six-turn result

| Mode | Prompt | Language | Sources | Latency | Result |
| --- | --- | --- | --- | ---: | --- |
| Expert | `Where can I find food in the wilderness?` | English | Survival Manual 2026 | 7,499 ms | Language and citation passed. Answer was indirect; the harness also rejected a valid alternate reviewed food record. |
| Expert | `在哪里可以找到并净化水源？` | Simplified Chinese | Survival Manual 2026 | 7,033 ms | Chinese passed. Finding guidance was grounded, but purification guidance was incomplete. The recorded `truncated_ending` flag is a harness bug caused by `。`. |
| Expert | `¿Cómo puedo construir un refugio temporal para pasar la noche?` | Spanish | Survival Manual 2026 | 9,943 ms | Spanish and citation passed. The harness rejected a valid tarp-shelter record; wording still needs polish. |
| Lite | `Where can I find food in the wilderness?` | English | None | 3,671 ms | Failed. Lite misrouted the survival question as general and returned a generic location request. |
| Lite | `在哪里可以找到并净化水源？` | Simplified Chinese | None | 4,243 ms | Failed. Lite emitted a placeholder retrieval query, so no reviewed evidence was found; answer was incomplete. |
| Lite | `¿Cómo puedo construir un refugio temporal para pasar la noche?` | Spanish | None | 5,495 ms | Failed safely. Routing worked, but malformed answer-envelope syntax was withheld and replaced by a localized retry. |

All six replies matched the requested language. Expert selected reviewed source cards in 3/3 cases; Lite selected them in 0/3.

## Root-cause classification

1. **Lite routing quality — product blocker.** The Lite router returned literal placeholder content (`English retrieval query`) for English and Chinese cases. The English food question was also classified as `general`. This prevents reviewed RAG retrieval and source cards.
2. **Lite structured generation — product blocker.** The Spanish Lite answer used malformed quote and evidence syntax. Aurora correctly withheld it, but the retry is not a useful field answer.
3. **Expert coverage — quality issue.** Language and provenance are working, but the Chinese response retrieved only water-location evidence and omitted purification steps.
4. **Harness expectations — corrected for future runs.** Chinese terminal punctuation is now accepted, and the fixed comparison fixture accepts the reviewed food-principles and tarp-shelter records used by Expert. Today’s immutable JSON remains unchanged.

## Appearance verification

- The automated appearance, persistence, reset, and semantic send-button tests passed before physical handoff.
- After Xcode UI automation was enabled on the iPad, the physical settings-only test passed in 40.460 seconds without submitting a chat turn.
- The test verified that System, Light, and Dark are present; Dark applies and persists across relaunch; and Reset to Defaults restores System.
- Enabled-arrow contrast is covered by the semantic-color implementation and automated suite; it remains a recommended visual check during manual handoff.

## Evidence

- [Combined immutable JSON](physical-tier-comparison/adaptive-language-2026-08-30-morning-combined.json)
- [Expert JSON](physical-tier-comparison/adaptive-language-2026-08-30-morning-expert.json)
- [Lite JSON](physical-tier-comparison/adaptive-language-2026-08-30-morning-lite.json)
- [Expert English screenshot](physical-tier-comparison/adaptive-language-vision_expert-adaptive-food-en.png)
- [Expert Chinese screenshot](physical-tier-comparison/adaptive-language-vision_expert-adaptive-water-zh.png)
- [Expert Spanish screenshot](physical-tier-comparison/adaptive-language-vision_expert-adaptive-shelter-es.png)
- [Lite English screenshot](physical-tier-comparison/adaptive-language-lite-adaptive-food-en.png)
- [Lite Chinese screenshot](physical-tier-comparison/adaptive-language-lite-adaptive-water-zh.png)
- [Lite Spanish screenshot](physical-tier-comparison/adaptive-language-lite-adaptive-shelter-es.png)
- [Physical appearance reset screenshot](physical-tier-comparison/adaptive-language-appearance-system-reset.png)

## Next implementation target

Repair the Lite routing prompt/grammar so it cannot copy placeholder schema text, then improve retrieval coverage for multi-part questions. Do not tune away the compact envelope or the malformed-grounded-answer suppression: both behaved correctly when Lite produced invalid protocol output.
