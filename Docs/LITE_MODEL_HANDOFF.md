# Lite model workstation handoff

Updated: 2026-07-30

## Selection

The Windows workstation winner is:

- Repository: `bartowski/Phi-3.5-mini-instruct-GGUF`
- Repository revision: `6d70da17e749a471ccb62ade694486011a75cda3`
- Base model: `microsoft/Phi-3.5-mini-instruct`
- Base revision: `2fe192450127e6a83f7441aef6e3ca586c338b77`
- License: MIT
- Artifact: `Phi-3.5-mini-instruct-Q4_K_M.gguf`
- Quantization: `Q4_K_M`
- Bytes: `2,393,232,672`
- SHA-256: `e4165e3a71af97f1b4820da61079826d8752a2088e313af0c7d346796c38eff5`
- Base-model `LICENSE` bytes/SHA-256: `1,084` /
  `fa8235e5b48faca34e3ca98cf4f694ef08bd216d28b58071a1f85b1d50cb814d`
- Chat template: Phi-3 ChatML from the embedded
  `tokenizer.chat_template`
- Runtime: official llama.cpp `b9637`,
  commit `aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3`
- Configuration: 2,048 context tokens, 256 maximum output tokens,
  grammar-constrained greedy sampling

The candidate is selected in `Resources/Models/catalog.json`, but it is not
bundled, installed, signed, or active. Essential remains the startup tier.

The exact prompt framing is:

```text
<|system|>
{system_prompt}<|end|>
<|user|>
{user_prompt}<|end|>
<|assistant|>
```

## Reproduction and conversion

Download the evaluated bytes:

```bash
hf download bartowski/Phi-3.5-mini-instruct-GGUF \
  --revision 6d70da17e749a471ccb62ade694486011a75cda3 \
  --include Phi-3.5-mini-instruct-Q4_K_M.gguf \
  --local-dir .trailguard/model-eval/models/phi-3.5-mini-q4_k_m

hf download microsoft/Phi-3.5-mini-instruct \
  --revision 2fe192450127e6a83f7441aef6e3ca586c338b77 \
  --include LICENSE \
  --local-dir .trailguard/model-eval/models/phi-3.5-mini-q4_k_m

shasum -a 256 \
  .trailguard/model-eval/models/phi-3.5-mini-q4_k_m/Phi-3.5-mini-instruct-Q4_K_M.gguf

shasum -a 256 \
  .trailguard/model-eval/models/phi-3.5-mini-q4_k_m/LICENSE
```

Bartowski reports that the evaluated publisher artifact was produced with
llama.cpp `b3751` and an importance matrix. Its calibration text is
`https://gist.githubusercontent.com/bartowski1182/eb213dccb3571f863da82e99418f81e8/raw`,
SHA-256
`200e109bcd2b599fabcceaaada7f52bbd1e7c8f9ae030b8dc59c011de039a8026`.
The reconstruction recipe is:

```bash
hf download microsoft/Phi-3.5-mini-instruct \
  --revision 2fe192450127e6a83f7441aef6e3ca586c338b77 \
  --local-dir phi-3.5-mini-base

python convert_hf_to_gguf.py phi-3.5-mini-base \
  --outfile Phi-3.5-mini-instruct-F16.gguf --outtype f16

curl -L \
  https://gist.githubusercontent.com/bartowski1182/eb213dccb3571f863da82e99418f81e8/raw \
  -o bartowski-imatrix-calibration.txt

llama-imatrix -m Phi-3.5-mini-instruct-F16.gguf \
  -f bartowski-imatrix-calibration.txt \
  -o Phi-3.5-mini-instruct.imatrix

llama-quantize --imatrix Phi-3.5-mini-instruct.imatrix \
  Phi-3.5-mini-instruct-F16.gguf \
  Phi-3.5-mini-instruct-Q4_K_M.gguf Q4_K_M
```

A reconstruction does not claim byte identity with the evaluated publisher
artifact. Rehash it and rerun all gates before selection.

## Evaluation result

All candidates used the same final grounded-response prompt, checked-in GBNF
grammar, native b9637 CUDA runtime, 2,048-token context, 256-token output cap,
and greedy sampling.

| Candidate | Structured/retrieval | Unsupported safety | Eligible |
| --- | ---: | ---: | --- |
| Phi-3.5 Mini Q4_K_M | 8/8 | 4/4 | Yes |
| Qwen2.5-1.5B Instruct Q4_K_M | 2/8 | 0/4 | No |
| Qwen3-0.6B Q8_0 | 0/8 | 0/4 | No |

The reviewed cases cover all eight starter procedures. Each passing response
selected the supplied procedure, cited only supplied evidence, emitted no
model-authored steps or warnings, and left deterministic procedure expansion
to `GroundedResponseCodec`. The unsupported cases cover surgery, prescription
dosing, ECU writing, and airbag bypass. Each winning response used
`answer_confidence = insufficient`, selected no procedure, cited no evidence,
and emitted no prohibited procedure.

Qwen2.5-1.5B was rejected for confidence/procedure inconsistency, invented
evidence, and one prohibited-text echo. Qwen3-0.6B was rejected for failing to
select reviewed procedures and for invented evidence. Qwen2.5-3B was excluded
before weight download because revisions
`7dabda4d13d513e3e842b20f0d435c732f172cbe` (GGUF) and
`aa8e72537993ba99e69dfaafa59ed015b17504d1` (base) carry the
non-commercial Qwen Research License.

Detailed machine-readable evidence:

- `Reports/native-llama-lite-phi-3.5-mini-q4_k_m.json`
- `Reports/native-llama-lite-qwen2.5-1.5b-q4_k_m.json`
- `Reports/native-llama-lite-qwen3-0.6b-q8.json`

## Windows measurements

The winner recorded:

- Median cold first output: 2.002 seconds
- Median observed generation: 60.445 tokens/second
- `llama-bench` generation: 68.343 tokens/second
- `llama-bench` prompt processing: 3,182.564 tokens/second
- Peak process working set: 2,721,488,896 bytes
- Peak total RTX 4050 device memory: 3,183 MiB

GPU memory is total device memory reported by `nvidia-smi` during isolated
generation and must not be added to process working set. These Windows CUDA
measurements do not approve unified-memory use, latency, thermal state, or
battery behavior on an iPhone.

## Mac continuation

1. Build and test the grammar-constrained b9637 bridge on macOS. The simulator
   suite now contains 97 tests; rerun both iPhone and iPad destinations.
2. Download the exact artifact and base-model MIT license, then verify both
   hashes.
3. Sign a development package without committing the private key:

```bash
/tmp/trailguard-dev-venv/bin/python tools/prepare_lite_model_package.py \
  --model .trailguard/model-eval/models/phi-3.5-mini-q4_k_m/Phi-3.5-mini-instruct-Q4_K_M.gguf \
  --license .trailguard/model-eval/models/phi-3.5-mini-q4_k_m/LICENSE \
  --output .trailguard/development/model-lite-phi35@1.0.0 \
  --private-key .trailguard/development/package-signing-key.pem \
  --key-id development-2026-07 \
  --created-at 2026-07-30T00:00:00Z
```

4. Install and activate that directory through `PackageInstaller` and
   `ActivePackRegistry`; verify signature/hash rejection, rollback, recall,
   entitlement, memory, thermal, Low Power Mode, and automatic Essential
   fallback.
5. On the physical iPhone 13, record first-token latency, tokens/second, peak
   unified memory, sustained thermal state, battery impact, interruptions, and
   airplane-mode cold launch before approving the artifact for production.

No iPhone inference, Metal memory, battery, or thermal pass is claimed by this
workstation handoff.
