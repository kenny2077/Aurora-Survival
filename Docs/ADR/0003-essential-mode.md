# ADR 0003: Essential mode has no model dependency

Status: Accepted

Bundled safety rules, emergency cards, local retrieval, citations, and an
extractive formatter remain usable when every generative model fails to load.

Consequence: every release tests a model-unavailable path and emergency-core
corruption recovery.
