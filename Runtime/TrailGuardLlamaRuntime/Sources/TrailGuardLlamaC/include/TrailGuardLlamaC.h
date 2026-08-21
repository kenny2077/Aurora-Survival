#ifndef TRAILGUARD_LLAMA_C_H
#define TRAILGUARD_LLAMA_C_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void * TGLlamaSessionRef;
typedef void * TGEmbeddingSessionRef;
typedef void (*TGTokenCallback)(
    const uint8_t * bytes,
    int32_t byte_count,
    void * context
);

TGLlamaSessionRef tg_llama_session_create(
    const char * model_path,
    const char * projector_path,
    int32_t context_tokens,
    int32_t thread_count,
    char ** error_out
);

char * tg_llama_session_complete(
    TGLlamaSessionRef session,
    const char * system_prompt,
    const char * user_prompt,
    const uint8_t * image_bytes,
    int64_t image_byte_count,
    int32_t maximum_output_tokens,
    int32_t evidence_count,
    int32_t grammar_mode,
    TGTokenCallback token_callback,
    void * token_context,
    int64_t * first_token_microseconds_out,
    int64_t * total_microseconds_out,
    int32_t * generated_token_count_out,
    char ** error_out
);

int32_t tg_llama_runtime_supports_vision(void);

TGEmbeddingSessionRef tg_embedding_session_create(
    const char * model_path,
    int32_t context_tokens,
    int32_t thread_count,
    int32_t expected_dimensions,
    char ** error_out
);

int32_t tg_embedding_session_embed(
    TGEmbeddingSessionRef session,
    const char * text,
    float * output,
    int32_t output_dimensions,
    char ** error_out
);

void tg_embedding_session_destroy(TGEmbeddingSessionRef session);

void tg_llama_session_destroy(TGLlamaSessionRef session);
void tg_llama_string_free(char * string);

#ifdef __cplusplus
}
#endif

#endif
