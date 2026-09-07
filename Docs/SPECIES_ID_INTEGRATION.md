# Species ID integration

## Device validation status (2026-09-07)

The released fp16 encoder is integrated and hash-verified. AuroraSpeciesKit
0.2.0 restores the torchvision-sized vImage path for production and retains the
Pillow-exact path only for validation. On the paired iPhone 13, the production
fp16 encoder scored 79/85 true-label top-one and 85/85 top-five with 195 ms warm
p95, a 268 ms maximum, 635 MB peak footprint, and no serious thermal state. All
827 planned operations preferred the Neural Engine.

The signed int8 and 6-bit challengers also retained 85/85 top-five, but neither
earned release selection. Int8 reached 78/85 top-one and 201 ms warm p95; its
first compile/load improved 29.87% over fp16, below the locked 30% minimum. The
6-bit candidate reached 77/85 and 227 ms with an 869 MB peak footprint. The
production choice therefore remains fp16 with `.all`; CPU+GPU fallback remains
rejected because the earlier sustained run reached serious thermal state. See
the retained `iphone13-performance-*.json` reports under `Reports/species-id`.

Aurora's Species ID is an optional signed package. The app does not bundle the
BioCLIP encoder, species table, or embeddings.

## Locked inputs

- Runtime package: `kenny2077/aurora-species-BioCLIP` tag `0.2.0`
- Runtime commit: `782b310a41db713c2e00f0dfb668d65b2151b170`
- BioCLIP-2 model: `imageomics/bioclip-2`
- Model revision: `2957b322090f9cb17ae72c71981c7218a28d81e0`
- Safetensors SHA-256: `b7b2bf6fbc95799e42630e394cf95803892ab447c1a8ab629dbc82fbeaf7dfef`
- Input: `224 x 224`
- Image/text embedding dimensions: `768`
- Species rows: `504`, float16, in JSON table order
- Ranking: softmax over `100 * cosine_similarity`

The pinned safetensors checkpoint is downloaded to the ignored local path
`.trailguard/species-source/bioclip-2`. The species table and embedding binary
are staged under `.trailguard/species-source/aurora-species` (SHA-256
`2584c1e5aa50a7c48d8d63bb9dcbc35633991551f8b737dbaf7bd01892202833` and
`685dffd104c63107f20c6644a2ca0ea2d1d25ab9caeed3dd92f39720d4d0ad0a`).
The immutable fp16 encoder is available from the upstream
`encoder-fp16.2026-09-05` GitHub release. Compression experiments can be
reproduced with `tools/optimize_species_encoder.py`; they do not replace the
fp16 release unless every accuracy, speed, memory, and thermal gate passes.

## Build the signed development package

```sh
python3 tools/prepare_species_package.py \
  --encoder /path/to/BioCLIP2-ImageEncoder.mlpackage \
  --species-table /path/to/species_table.json \
  --embeddings /path/to/species_embeddings.f16.bin \
  --output .trailguard/development/species-bioclip2-north-america-504@1.0.0 \
  --private-key .trailguard/development/package-signing-key.pem \
  --created-at 2026-09-07T00:00:00Z \
  --encoder-variant fp16
```

`prepare_product_catalog.py` automatically includes that package when its
signed envelope is present. It remains absent otherwise.

## Release gates

Do not publish to R2 until Core ML parity passes on the Mac, the full 85-image
exam passes on the paired iPhone 13, and the user's manual camera/library review
passes. Keep the signed package in the local development catalog until then.
Retain device JSON with model-load and warm latency, stage timings, peak and
available memory, compute device, battery, prediction changes, and thermal state.
