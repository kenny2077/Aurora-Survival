# Model experiment and release gates

Updated: 2026-08-09

## Two-tier contract

| Tier | Current candidate | Intended target | State |
| --- | --- | --- | --- |
| Lite | Gemma 3 1B IT Q4_K_M | iPhone 13-class and comparable devices | Supported when signed, installed, eligible, and runtime-bound |
| Expert (`vision_expert`) | Qwen3-VL 2B-class model plus projector | High-memory devices such as iPhone 17 Pro Max and iPad Pro M2+ | Validation-locked |

The iOS runtime is pinned to llama.cpp `b9637` at commit `aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3`. The exact signed Gemma Lite artifact has prior short and five-turn iPhone 13 evidence. Expert is not approved: its signed artifacts, mtmd image path, and physical vision inference must all pass before the app can expose photo attachment.

## Routing matrix

- Auto selects Expert only when its signed model/projector is approved, installed, runtime-bound, and currently eligible; otherwise it selects Lite.
- Manual Expert selection reports validation locked while those gates remain incomplete and may use Lite if available.
- Expert degrades to Lite under thermal pressure, Low Power Mode, memory/storage failure, recall, trust failure, or runtime failure.
- If no usable tier exists, Ask is unavailable. Manual and Maps continue to work.
- Hardware names describe validation targets but never bypass live memory, storage, thermal, power, trust, recall, or runtime checks.

## Acceptance gates

### Grounding and safety

- Valid evidence indexes create exact Manual links; invalid, duplicate, or out-of-range indexes create none.
- Citation-to-passage entailment target is at least 0.98 after expert review.
- Expired, unsigned, recalled, or unreviewed records and packages never activate.
- Model failure never silently produces an extractive answer presented as model output.

### Device performance

- Lite warm first token at most 3 seconds and at least 8 tokens/second on iPhone 13.
- Expert first useful visual result at most 8 seconds on the minimum approved device.
- Manual visible within one second and merged local search within 300 ms.
- No OS termination in a 30-minute incident script and no serious thermal transition in the standard ten-turn script.
- Expert vision energy use at most 5% battery for the standard photo scenario.

The current Lite candidate has prior short and five-turn latency/throughput evidence. Long-duration battery and interruption gates remain pending. Expert performance and real image inference remain blocked until an approved signed model/projector and capable physical target are available.

## Required hardware matrix

Test iPhone 13 as the Lite floor, then representative recent iPhones, iPhone 17 Pro Max, and iPad Pro M2 or newer across fresh/warm launch, storage pressure, Low Power Mode, thermal pressure, Airplane Mode, backgrounding, and memory pressure. Do not infer compatibility solely from a product name.
