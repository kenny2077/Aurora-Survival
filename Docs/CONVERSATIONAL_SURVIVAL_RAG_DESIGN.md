# Conversational Survival RAG Design

Status: accepted direction for iteration one (2026-08-02)

## Product intent

TrailGuard should feel like a normal multi-turn chatbot while remaining useful
without a network connection on the base iPhone 13. The assistant may explain,
compare options, ask a relevant follow-up, and understand short references such
as “what if I do not have a filter?” It is scoped to survival, preparedness,
navigation, layperson first aid, and roadside incidents.

The model is an explanation layer, not an authority. Reviewed signed content,
deterministic emergency rules, package verification, and citation validation
remain authoritative. The app must never imply that it replaces emergency
services, a clinician, a vehicle manual, or local instructions.

## Assumptions and release boundaries

- The installed Gemma 3 1B Lite model remains the iPhone 13 release candidate.
- Chat is fully offline. No prompt, transcript, image, or location is uploaded.
- Recent dialogue is supplied as a small rolling window; a fresh native context
  per answer remains acceptable and avoids stale inference state.
- Procedural or factual survival guidance must identify reviewed evidence.
  Brief social conversation and clarification may be uncited when it contains no
  survival claim or instruction.
- The model may naturally summarize reviewed evidence. Exact emergency actions,
  prohibitions, medical boundaries, and high-risk procedures remain app-rendered
  from reviewed records.
- Wild-food identification, medication dosing, invasive treatment, weapon
  construction, safety-system bypass, and instructions unsupported by the local
  corpus are outside the release contract.
- Government and nonprofit sources are references, not blanket permission to
  republish an entire book. TrailGuard stores original reviewed summaries and
  short procedures with source metadata; logos and third-party material are not
  copied. Human editorial, clinical, mechanical, and legal review remain release
  gates.

## Considered approaches

### A. Hybrid conversational response plus reviewed procedure selection

The model returns a natural reply together with evidence indexes and an optional
reviewed procedure index. The app validates all indexes, displays the model's
short explanation, and appends exact reviewed steps only when a procedure was
selected. High-risk deterministic rules still bypass the model.

This is the selected approach. It provides ordinary conversation without asking
a 1B model to invent or semantically certify safety-critical instructions.

### B. Unconstrained prose followed by citation scanning

This feels flexible but a syntactically valid citation does not prove that every
claim is supported. It is not strong enough for an offline incident product.

### C. Evidence selector with deterministic rendering

This is the former implementation. It is safest syntactically but behaves like a
fixed FAQ and does not meet the conversational product requirement.

## Runtime contract

1. Evaluate the current question, trusted OCR observations, and relevant recent
   user context with deterministic safety rules. A match returns immediately and
   performs no model generation.
2. Build a retrieval query from the current question plus a bounded amount of
   recent dialogue. Retrieve up to four reviewed local records.
3. Prompt Gemma with a compact rolling transcript and concise evidence blocks.
4. Generate one grammar-constrained JSON object containing:
   - `a`: a short natural answer;
   - `e`: zero or more valid evidence indexes;
   - `p`: one reviewed procedure index or `null`;
   - `q`: an optional short follow-up question.
5. Reject malformed output, unknown indexes, unsupported procedural selection,
   empty grounded answers, or text that attempts to smuggle citations/markup.
6. Render the conversational answer, source markers, optional reviewed procedure,
   reviewed warnings, and the follow-up. On failure, use the extractive baseline.
7. Preserve only a bounded in-memory dialogue window. Clearing the chat removes
   that context.

The codec validates provenance and structural policy; it does not pretend to be
an offline entailment model. For that reason, actionable procedure steps stay
verbatim from the reviewed corpus rather than being generated in free text.

## Manual and retrieval model

The book and the chatbot use the same reviewed corpus so a chapter can open from
a cited chat answer and a chapter update immediately improves retrieval. The
planned first-edition chapter order is:

1. Assess, stabilize, and call for help
2. Water
3. Fire, warmth, and burn prevention
4. Shelter and severe weather
5. Food storage and emergency rations
6. Navigation and being lost
7. Signaling and rescue
8. Layperson first aid boundaries
9. Wildlife and environmental hazards
10. Vehicle survival and roadside incidents

Food content will focus on carried food, storage, ration planning, contamination,
and avoiding unsafe identification. It will not claim that a photograph or short
description can establish that a wild plant or mushroom is edible.

## Visual direction

The implementation follows Apple's current Figma design resources as a reference
and maps them semantically to SwiftUI: system colors, SF Pro through Dynamic Type,
SF Symbols, native navigation, prominent but calm emergency affordances, readable
source cards, and large tap targets. Figma dimensions are guidance for hierarchy
and composition, not literal fixed SwiftUI frames.

## Acceptance criteria for iteration one

- A follow-up such as “What if I do not have a filter?” receives an answer that
  uses the preceding water context.
- The model can greet, clarify, explain, and ask a relevant follow-up without
  printing the same full checklist on every turn.
- Every factual/procedural answer displays valid local sources; invalid output
  fails closed to reviewed extractive guidance.
- Deterministic emergency cases bypass the model with zero generation calls.
- Clear conversation removes the rolling history.
- Automated tests, a signed device build, and a physical iPhone 13 multi-turn test
  pass before the feature is considered verified.
