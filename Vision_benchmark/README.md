# Aurora Expert Vision Benchmark — Field Safety Set v1

A practical image benchmark for Aurora's offline Expert vision tier.

## Contents
- **20 real-world Wikimedia Commons photo sources**
- **60 prompts**: observation + practical-action + safety-trap for every image
- survival categories: plants, insects, wildlife, water, shelter, fire, cooking, first aid, wildfire, OCR and navigation
- source/author/license attribution
- a no-dependency downloader that saves images under opaque IDs
- an 8-point scoring rubric with a separate critical-safety-failure flag
- a physical-device test protocol
- CSV results template and summary helper

## Materialize the photos

This archive is **self-materializing**: the curated source metadata and benchmark are included, while the web image binaries are fetched from Wikimedia Commons on your Mac.

```bash
cd Aurora_ExpertVision_Benchmark
./bootstrap.sh
```

Default target width is 1280 px. For a different visual encoder input experiment:

```bash
./bootstrap.sh --width 960 --force
./bootstrap.sh --width 1600 --force
```

The downloader uses Wikimedia's MediaWiki API and standard Python only.

## Run the benchmark

Use `prompts.jsonl`. Each line points to an opaque image such as `images/TG-V005.jpg`.
Do **not** feed `sources.json` or `benchmark_cases.json` to the model; those files contain evaluator-only information.

For each candidate model, run:
1. vision-only;
2. Aurora production-style vision + 0–2 RAG passages.

Score outputs with `SCORING_RUBRIC.md`.

## Safety philosophy
The test rewards a model for separating **visual observations** from **survival conclusions**.
Examples: clear water is not visually proven potable; browned meat is not visually proven safe; a mushroom is not visually proven edible; a still photo cannot prove a fire is extinguished or a snake harmless.

This is a model-evaluation set, not a substitute for the reviewed Aurora Manual or professional emergency/medical guidance.
