# Remote implementation completion checklist

Updated: 2026-07-23

This checklist maps the architecture plan to work that can be completed and
verified in a source-only virtual workspace. “Complete” means implemented with
an executable local or CI contract; it does not claim external certification.

| Repository gate | Status | Evidence |
| --- | --- | --- |
| Architecture decisions in source control | Complete | `Docs/ADR/0001`–`0012` |
| Independently versioned schemas | Complete | `Schemas/*.schema.json` |
| Model provenance/device/thermal manifest | Complete | `model-pack.schema.json` |
| Map geometry/license/artifact manifest | Complete | `map-pack.schema.json` |
| Reproducible knowledge-pack build | Complete | `build_pack.py` and reproducibility CI |
| SQLite FTS + precomputed vectors | Complete | deterministic pack compiler |
| Signed install/activation/rollback | Complete | verifier and installer tests |
| Recall and failover | Complete | activation index and recall tests |
| Launch-time active-pack resolution | Complete | revalidation, entitlement, policy, review, version, recall, and device gates |
| Compiled-pack runtime retrieval | Complete | SQLite FTS5/vector reader with RRF and applicability filtering |
| Typed model response | Complete | grounded response schema and Swift validator |
| Evidence/procedure validation | Complete | unknown IDs fail closed |
| Policy attribution on safety cards | Complete | deterministic source and policy ID |
| Model-independent emergency core | Complete | first-launch/corruption recovery tests |
| Incident mode requires no network | Complete | network policy and entitlement tests |
| Download interruption/resume | Complete | artifact assembler restart tests |
| Read-only OBD policy | Complete | allowlist and nine locked rejection commands |
| Map readiness failure paths | Complete | map evaluator plus 30 asset cases |
| Model performance acceptance | Complete | latency/memory/thermal/battery evaluator |
| Evaluation provenance report | Complete | schema, writer, and `Reports/virtual-integration-2026-07-23.json` |
| Gold incident matrix | Complete | 120 synthetic control-path cases |
| Virtual release failure matrix | Complete | model/map/OBD/commerce/accessibility tests |
| Attached document source audit | Complete | architecture-only classification |
| CI structural/core/iOS jobs | Complete | `.github/workflows/ci.yml` |
| Typed response used by llama runtime | Complete | output-mode contract and live codec |
| Emergency recovery used at startup | Complete | `AppModel` bootstrap |
| Resume used by package delivery | Complete | strict byte-range coordinator |
| Store verification persistence | Complete | StoreKit bridge and entitlement ledger |
| Vehicle document ingestion | Complete | exact identity/revision/applicability gate |
| OBD observation persistence | Complete | vehicle-bound local record store |
| Offline map open boundary | Complete | file-backed runtime |
| Gold matrices executed | Complete | 120 incident and 30 asset execution tests |
| Zero-power preparation export | Complete | printable/shareable trip sheet |

## External acceptance gates still open

These require authority or equipment not available to a virtual workspace:

- expert-approved first-aid, vehicle, wilderness, and navigation content;
- source-owner redistribution licenses and production signing keys;
- a pinned, licensed llama.cpp/Qwen model build and real model weights;
- licensed MapLibre-compatible regional assets and attribution approval;
- supported BLE OBD adapters and representative vehicles;
- App Store Connect products, restore/refund/family-sharing evidence;
- physical iPhone performance, thermal, battery, camera, VoiceOver, Dynamic
  Type, interruption, and Airplane Mode testing;
- independent safety red team, human-factors, privacy, legal, and domain-owner
  release sign-off.

The corresponding feature stays unavailable or prototype-labeled until its
evidence is attached to a versioned evaluation report.
