# ADR 0006: Signed and recallable packs

Status: Accepted

Model, knowledge, and map artifacts require an Ed25519 envelope, per-file hash
and size verification, safe paths, atomic activation, rollback, and recall.

Consequence: a recalled active version immediately fails over to a non-recalled
installed version or becomes unavailable.
