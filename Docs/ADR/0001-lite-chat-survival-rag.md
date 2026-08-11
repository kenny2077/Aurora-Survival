# ADR 0001: Lite Chat uses Gemma plus shared survival RAG

Status: Accepted (supersedes the former rule-based routing decision)

Ordinary messages use pretrained Gemma conversation. The app may retrieve the
best one or two chunks from the bundled SQLite survival corpus and include them
in the prompt. Gemma returns a natural answer plus the evidence indexes it used;
those indexes create exact Field Manual links.

There is no separate hazard-rule or model-bypass stage. The corpus, chat
retriever, and detailed manual are one shared offline knowledge layer.

Consequence: release checks focus on corpus integrity, retrieval relevance,
answer-to-manual-link validity, on-device behavior, and accessibility.
