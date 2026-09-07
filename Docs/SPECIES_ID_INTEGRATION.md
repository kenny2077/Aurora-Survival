# Species ID integration

## Device validation status (2026-09-07)

The released fp16 encoder is integrated and hash-verified. Mac Core ML parity
passed 20/20 at a minimum cosine of 0.999479, and AuroraSpeciesKit 0.1.3's
Pillow-compatible bicubic preprocessing matched the PC reference 85/85 on Mac.
The iPhone 13 `.all` compute run passed every performance, memory, thermal, and
top-five requirement, but one close moose/Dall-sheep case changed top-one on the
A15 Neural Engine (84/85). Release remains gated on the complete CPU+GPU fallback
run. See `Reports/species-id/iphone13-2026-09-07.json`.

Aurora's Species ID is an optional signed package. The app does not bundle the
BioCLIP encoder, species table, or embeddings.

## Locked inputs

- Runtime package: `kenny2077/aurora-species-BioCLIP` tag `0.1.3`
- Runtime commit: `01f6d97284807ae5282df6b7010baae5cbe955c9`
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
Convert the checkpoint on the higher-memory build PC with the environment
pinned by the BioCLIP repository, then transfer the resulting `.mlpackage` to
this Mac.

## Build the signed development package

```sh
python3 tools/prepare_species_package.py \
  --encoder /path/to/BioCLIP2-ImageEncoder.mlpackage \
  --species-table /path/to/species_table.json \
  --embeddings /path/to/species_embeddings.f16.bin \
  --output .trailguard/development/species-bioclip2-north-america-504@1.0.0 \
  --private-key .trailguard/development/package-signing-key.pem \
  --created-at 2026-09-07T00:00:00Z
```

`prepare_product_catalog.py` automatically includes that package when its
signed envelope is present. It remains absent otherwise.

## Release gates

Do not publish to R2 until Core ML parity passes on the Mac and the full 85-image
exam passes on the paired iPhone 13. Retain the device JSON report with cold and
warm latency, peak memory, available memory, compute device, and thermal state.
