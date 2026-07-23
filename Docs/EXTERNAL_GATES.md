# External completion gates

The following goals cannot be honestly marked complete by source code alone.
They require assets, people, credentials, or physical equipment outside this
workspace. The app keeps their features visibly unavailable until evidence is
recorded.

| Gate | Required input | Completion evidence |
| --- | --- | --- |
| iOS compile | GitHub macOS runner or Xcode Mac | Green core tests and iOS build |
| Field model | Licensed, converted, signed GGUF | Hash, license, quality, latency, memory, heat, battery results |
| Vision Expert | Qwen3-VL GGUF + projector and capable iPhones | Locked vision dataset results on each approved device |
| Expert first aid | Qualified medical reviewers | Named review attestations, date, jurisdiction, red-team results |
| Vehicle procedures | Licensed manufacturer manuals and mechanics | Exact vehicle manifests and wrong-vehicle tests |
| Wilderness content | Qualified field instructors | Scenario review, environmental coverage, revision schedule |
| Offline maps | Licensed PMTiles/style/routing artifacts | Coverage audit, Airplane Mode route test, attribution review |
| OBD hardware | Supported BLE adapters and vehicles | Connection, reconnect, parser, isolation, and no-write capture |
| Commerce | App Store products and receipt service | Purchase, restore, refund, family-sharing, and offline entitlement tests |
| Release | Legal/privacy/accessibility/human-factors owners | Signed release checklist and rollback drill |

## Non-negotiable rule

A missing external gate is not resolved by changing a checkbox, loosening a test,
or substituting model confidence. The corresponding feature remains unavailable
or clearly labeled as an engineering prototype.
