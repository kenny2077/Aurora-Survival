# ADR 0012: Evaluation evidence is fully versioned

Status: Accepted

Every evaluation report records the app commit, prompt version, policy version,
model artifact hash/runtime, installed pack hashes, device, OS, suite, and
result counts.

Consequence: a result cannot be reused to approve a different binary, policy,
model, pack, device class, or operating system.
