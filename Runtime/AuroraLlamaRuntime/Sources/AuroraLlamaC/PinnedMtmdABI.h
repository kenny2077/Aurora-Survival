#ifndef AURORA_PINNED_MTMD_ABI_H
#define AURORA_PINNED_MTMD_ABI_H

// Minimal ABI surface copied from llama.cpp b9637 (commit aedb2a5) so the
// shipping bridge can detect a custom mtmd-capable XCFramework at runtime.
// Calls are resolved dynamically: the official text-only b9637 binary remains
// usable for Lite and fails closed for Expert.

#include <llama/ggml.h>
#include <llama/ggml-backend.h>
#include <llama/llama.h>

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct mtmd_context;
struct mtmd_bitmap;
struct mtmd_input_chunks;

typedef struct mtmd_context mtmd_context;
typedef struct mtmd_bitmap mtmd_bitmap;
typedef struct mtmd_input_chunks mtmd_input_chunks;

struct mtmd_input_text {
    const char * text;
    bool add_special;
    bool parse_special;
};

struct mtmd_context_params {
    bool use_gpu;
    bool print_timings;
    int n_threads;
    const char * image_marker;
    const char * media_marker;
    enum llama_flash_attn_type flash_attn_type;
    bool warmup;
    int image_min_tokens;
    int image_max_tokens;
    ggml_backend_sched_eval_callback cb_eval;
    void * cb_eval_user_data;
    int32_t batch_max_tokens;
};

struct mtmd_helper_bitmap_wrapper {
    mtmd_bitmap * bitmap;
    void * video_ctx;
};

#ifdef __cplusplus
extern "C" {
#endif

struct mtmd_context_params mtmd_context_params_default(void);
mtmd_context * mtmd_init_from_file(
    const char * mmproj_fname,
    const struct llama_model * text_model,
    struct mtmd_context_params ctx_params
);
void mtmd_free(mtmd_context * ctx);
bool mtmd_support_vision(const mtmd_context * ctx);
const char * mtmd_get_marker(const mtmd_context * ctx);
struct mtmd_helper_bitmap_wrapper mtmd_helper_bitmap_init_from_buf(
    mtmd_context * ctx,
    const unsigned char * buf,
    size_t len,
    bool init_video
);
void mtmd_bitmap_free(mtmd_bitmap * bitmap);
mtmd_input_chunks * mtmd_input_chunks_init(void);
void mtmd_input_chunks_free(mtmd_input_chunks * chunks);
int32_t mtmd_tokenize(
    mtmd_context * ctx,
    mtmd_input_chunks * output,
    const struct mtmd_input_text * text,
    const mtmd_bitmap ** bitmaps,
    size_t n_bitmaps
);
size_t mtmd_helper_get_n_tokens(const mtmd_input_chunks * chunks);
int32_t mtmd_helper_eval_chunks(
    mtmd_context * ctx,
    struct llama_context * lctx,
    const mtmd_input_chunks * chunks,
    llama_pos n_past,
    llama_seq_id seq_id,
    int32_t n_batch,
    bool logits_last,
    llama_pos * new_n_past
);

#ifdef __cplusplus
}
#endif

#endif
