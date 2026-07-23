# TrailGuard architecture

## Product invariant

The model interprets and explains; it does not define truth or authorize a
hazardous action. Safety rules, reviewed procedures, source metadata, and
release gates are independent of model tier.

## Runtime sequence

1. The app accepts a text question and, optionally, a photo.
2. Apple Vision performs local OCR. OCR text is marked as fallible observation.
3. `SafetyEngine` examines the question and OCR for critical patterns.
4. A critical match returns a fixed card and ends the pipeline.
5. `RetrievalEngine` searches only articles with `reviewed == true`.
6. `ModelRouter` selects the best installed tier permitted by current device
   memory, free storage, thermal state, and power mode.
7. The selected model receives numbered evidence through
   `GroundedPromptBuilder`.
8. `CitationPolicy` rejects missing or out-of-range citations.
9. Failure at steps 6–8 returns a deterministic extractive answer.

## Boundaries

| Component | May do | Must not do |
| --- | --- | --- |
| Safety engine | Stop generation; issue fixed immediate actions | Diagnose a condition |
| Retrieval | Rank approved local evidence | Retrieve draft or unapproved content |
| Text model | Rephrase and organize evidence | Add unsupported facts |
| Vision model | Describe visible features and uncertainty | Declare a part safe or prescribe a repair by sight alone |
| Medical pack | Layperson first aid and escalation | Surgery, invasive treatment, diagnosis, prescriptions |
| Vehicle pack | Read-only inspection and owner-manual procedures | ECU writes, safety-system bypass, unsupported lift points |

## Model adapters

`LocalLanguageModel` is the stable core protocol. `ClosureBackedLanguageModel`
adapts a runtime by accepting two prompts and returning text. A production
llama.cpp adapter should:

- embed a pinned llama.cpp build as an XCFramework;
- load only signed, hash-verified model packages;
- keep all prompts, images, and output on device;
- bind Qwen's language GGUF and multimodal projector as one atomic package;
- constrain image resolution before the vision encoder;
- stream tokens with cancellation;
- unload on memory warning, serious heat, backgrounding, or Low Power Mode;
- expose measured memory, first-token latency, generation rate, and temperature;
- return plain text to the existing citation validator.

The adapter must not bypass `IncidentAssistant`.

## Data packs

The starter JSON is a development fixture, not a production corpus. Production
packs need:

- a signed manifest, semantic version, locale, jurisdiction, and expiration;
- one source record per procedure;
- author, reviewer, review date, and change rationale;
- explicit contraindications and escalation thresholds;
- automated schema, broken-link, duplicate, and citation tests;
- domain-owner approval independent of app release;
- rollback to the prior signed version.

Vehicle procedures must be keyed by make, model, year, powertrain, market, and
document revision. Generic guidance cannot supply torque values, jack points,
fluid types, fuse assignments, high-voltage isolation, or towing modes.

## Maps and OBD

They are deliberately outside this first vertical slice.

- Offline maps should use MapLibre Native and legally distributable signed
  regional packs. The app must show pack age, coverage, contour/road detail,
  and a no-network route preview.
- OBD-II should start read-only. Store raw code, timestamp, freeze-frame data,
  adapter identity, vehicle profile, and the evidence used to explain the code.
  No clearing codes, actuator tests, coding, or ECU writes in v1.

## Privacy

The MVP has no analytics or network client. Production download services must
separate model/map/package transfer from incident content. Questions, photos,
location, health information, and vehicle identifiers stay on device unless the
user explicitly performs an SOS or export action.
