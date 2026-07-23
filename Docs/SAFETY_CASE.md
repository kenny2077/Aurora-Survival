# MVP safety case

## Claim

Aurora can provide a safer offline information path than an unrestricted
chat model because critical hazards bypass generation and normal answers are
limited to retrieved, source-attributed material.

This claim is architectural. It is not yet a clinical or product certification.

## Evidence implemented

- `SafetyEngine` executes before retrieval and generation.
- Critical cards do not call a language model.
- Retrieval excludes articles where `reviewed` is false.
- A model sees numbered evidence and explicit prohibited scopes.
- Missing or invalid citations trigger an extractive fallback.
- Missing models, model exceptions, and vision ineligibility degrade to text.
- Model tier does not alter the knowledge pack or safety engine.
- Vision is paused for insufficient memory/storage, heat, or Low Power Mode.
- The UI identifies the prototype and directs immediate danger to SOS.

## Known gaps

- Phrase matching is not a certified clinical triage classifier.
- The starter corpus has source metadata but no signed review attestations.
- No jurisdiction, language, accessibility, child, pregnancy, disability, or
  vehicle-specific validation has been completed.
- OCR can be wrong and is not yet confidence-scored in the UI.
- No physical-device performance or thermal result exists.
- No signed package installer, update rollback, or tamper test exists.
- No independent red team, human-factors study, or regulatory analysis exists.

## Release blockers

Do not distribute as an emergency product until all known gaps have owners,
tests, evidence, and independent domain approval. Do not market it as replacing
emergency services, a clinician, a mechanic, an owner manual, or trained rescue.
