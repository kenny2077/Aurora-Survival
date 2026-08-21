# Expert Native Vision Decision

Date: 2026-08-21

## Decision

An Expert turn with a newly attached image bypasses intent classification and
Survival RAG. Aurora sends the user's exact question, the bounded ephemeral
image, and only bounded relevant text context directly to the installed
Qwen3-VL model. The model produces exactly one progressively streamed answer.

The native vision prompt asks Qwen3-VL to answer the actual visual question,
describe relevant objects, people, actions, layout, diagrams, and legible text,
and give its most likely object identification while separating visible evidence
from uncertain inference. It must not invent obscured details, measurements,
diagnoses, safety guarantees, or live facts, and it gives advice only when asked.

Photo answers are always unsourced model-best-effort responses. They never query
Survival RAG, create Manual links, display offline source cards, or carry Expert
intent, retrieval, verification, support, or coverage metadata. If a clean answer
was streamed before an incomplete envelope ended, that prose remains visible. A
decoding or inference failure produces one retryable vision error and no fallback
inference.

Full image bytes are released after the request. Only the existing bounded
transcript thumbnail persists. A text-only follow-up follows normal Expert text
routing and cannot reason about the old image unless the user attaches it again.

## Rejected alternatives

- The fixed visual-hazard taxonomy was rejected because it discarded object,
  scene, diagram, and layout understanding and could substitute unrelated hazard
  retrieval for the user's question.
- Image-driven Survival RAG was rejected because weak visual labels could create
  false grounding and unrelated citations.
- OCR-only, Lite, text-model, or second-completion fallbacks were rejected because
  they hide native vision failures and violate the one-completion contract.

## Compatibility

Text-only Expert retains its hidden two-intent decision, survival-only retrieval,
absolute evidence gate, and one streamed answer completion. Lite, model/package
identities, the paired projector, adaptive image bounds, PhotoKit authorization,
and thumbnail-only transcript storage are unchanged.

