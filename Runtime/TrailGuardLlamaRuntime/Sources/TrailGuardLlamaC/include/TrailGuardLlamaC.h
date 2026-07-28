#ifndef TRAILGUARD_LLAMA_C_H
#define TRAILGUARD_LLAMA_C_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void * TGLlamaSessionRef;

TGLlamaSessionRef tg_llama_session_create(
    const char * model_path,
    int32_t context_tokens,
    int32_t thread_count,
    char ** error_out
);

char * tg_llama_session_complete(
    TGLlamaSessionRef session,
    const char * system_prompt,
    const char * user_prompt,
    int32_t maximum_output_tokens,
    char ** error_out
);

void tg_llama_session_destroy(TGLlamaSessionRef session);
void tg_llama_string_free(char * string);

#ifdef __cplusplus
}
#endif

#endif
