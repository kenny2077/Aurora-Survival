# ADR 0001: Deterministic safety precedes models

Status: Accepted

Hazard detection runs before retrieval or inference. Critical matches return a
fixed, policy-attributed card. Model output cannot override or soften it.

Consequence: policy rules require independent versioning and locked regression
tests; false-negative review is a release gate.
