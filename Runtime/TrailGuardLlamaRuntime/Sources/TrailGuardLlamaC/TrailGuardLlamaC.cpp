#include "AuroraLlamaC.h"
#include "GroundedResponseGrammar.h"

#include <TargetConditionals.h>
#include <llama/llama.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <sys/sysctl.h>
#include <vector>

namespace {

// Match the compact Lite-tier eligibility floor enforced by ModelRouter. The
// accepted Gemma 3 1B artifact is small enough for full Metal offload on the
// iPhone 13; lower-memory devices retain the Essential fallback.
constexpr uint64_t kMinimumMemoryForGPUOffload = 3'500'000'000ULL;
constexpr int32_t kPromptBatchTokens = 256;
constexpr int32_t kPhysicalBatchTokens = 128;

int32_t gpu_offload_layers() {
#if TARGET_OS_SIMULATOR
    return 0;
#else
    uint64_t physical_memory = 0;
    size_t size = sizeof(physical_memory);
    if (sysctlbyname(
        "hw.memsize",
        &physical_memory,
        &size,
        nullptr,
        0
    ) != 0 || physical_memory < kMinimumMemoryForGPUOffload) {
        return 0;
    }
    return 99;
#endif
}

struct Session {
    llama_model * model;
    llama_context * context;
    const llama_vocab * vocab;
    llama_context_params context_params;
    bool context_has_run;
};

std::mutex backend_mutex;
int backend_references = 0;

void retain_backend() {
    std::lock_guard<std::mutex> lock(backend_mutex);
    if (backend_references == 0) {
        llama_backend_init();
    }
    ++backend_references;
}

void release_backend() {
    std::lock_guard<std::mutex> lock(backend_mutex);
    --backend_references;
    if (backend_references == 0) {
        llama_backend_free();
    }
}

void set_error(char ** error_out, const std::string & message) {
    if (error_out != nullptr) {
        *error_out = strdup(message.c_str());
    }
}

std::string format_prompt(
    const Session & session,
    const char * system_prompt,
    const char * user_prompt,
    std::string & error
) {
    const char * chat_template = llama_model_chat_template(
        session.model,
        nullptr
    );
    if (chat_template == nullptr) {
        error = "The model does not provide a supported chat template.";
        return {};
    }

    const llama_chat_message messages[] = {
        {"system", system_prompt},
        {"user", user_prompt},
    };
    int32_t size = llama_chat_apply_template(
        chat_template,
        messages,
        2,
        true,
        nullptr,
        0
    );
    if (size < 0) {
        error = "The model chat template could not be applied.";
        return {};
    }

    std::vector<char> buffer(static_cast<size_t>(size) + 1);
    int32_t written = llama_chat_apply_template(
        chat_template,
        messages,
        2,
        true,
        buffer.data(),
        static_cast<int32_t>(buffer.size())
    );
    if (written < 0 || written > static_cast<int32_t>(buffer.size())) {
        error = "The model chat template produced an invalid prompt.";
        return {};
    }
    return std::string(buffer.data(), static_cast<size_t>(written));
}

bool append_token_piece(
    const Session & session,
    llama_token token,
    std::string & output,
    std::string & error
) {
    char stack_buffer[256];
    int32_t size = llama_token_to_piece(
        session.vocab,
        token,
        stack_buffer,
        sizeof(stack_buffer),
        0,
        true
    );
    if (size >= 0) {
        output.append(stack_buffer, static_cast<size_t>(size));
        return true;
    }

    std::vector<char> buffer(static_cast<size_t>(-size));
    size = llama_token_to_piece(
        session.vocab,
        token,
        buffer.data(),
        static_cast<int32_t>(buffer.size()),
        0,
        true
    );
    if (size < 0) {
        error = "A generated token could not be decoded.";
        return false;
    }
    output.append(buffer.data(), static_cast<size_t>(size));
    return true;
}

}  // namespace

TGLlamaSessionRef tg_llama_session_create(
    const char * model_path,
    int32_t context_tokens,
    int32_t thread_count,
    char ** error_out
) {
    if (error_out != nullptr) {
        *error_out = nullptr;
    }
    if (model_path == nullptr || context_tokens <= 0 || thread_count <= 0) {
        set_error(error_out, "Invalid llama runtime configuration.");
        return nullptr;
    }

    retain_backend();
    llama_model_params model_params = llama_model_default_params();
    const int32_t gpu_layers = gpu_offload_layers();
    const bool use_gpu = gpu_layers > 0;
    model_params.n_gpu_layers = gpu_layers;

    llama_model * model = llama_model_load_from_file(
        model_path,
        model_params
    );
    if (model == nullptr) {
        release_backend();
        set_error(error_out, "The GGUF model could not be loaded.");
        return nullptr;
    }

    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = static_cast<uint32_t>(context_tokens);
    // A full-context prompt batch creates a large transient Metal allocation
    // that can exceed the iPhone 13's 4 GB process budget. Keep the logical
    // context intact while evaluating prompts in bounded physical batches.
    context_params.n_batch = static_cast<uint32_t>(
        std::min(context_tokens, kPromptBatchTokens)
    );
    context_params.n_ubatch = static_cast<uint32_t>(
        std::min(context_tokens, kPhysicalBatchTokens)
    );
    context_params.n_threads = thread_count;
    context_params.n_threads_batch = thread_count;
    context_params.offload_kqv = use_gpu;
    context_params.op_offload = use_gpu;

    llama_context * context = llama_init_from_model(model, context_params);
    if (context == nullptr) {
        llama_model_free(model);
        release_backend();
        set_error(error_out, "The llama context could not be created.");
        return nullptr;
    }

    Session * session = new Session{
        model,
        context,
        llama_model_get_vocab(model),
        context_params,
        false,
    };
    return static_cast<TGLlamaSessionRef>(session);
}

char * tg_llama_session_complete(
    TGLlamaSessionRef opaque_session,
    const char * system_prompt,
    const char * user_prompt,
    int32_t maximum_output_tokens,
    int32_t evidence_count,
    int64_t * first_token_microseconds_out,
    int64_t * total_microseconds_out,
    int32_t * generated_token_count_out,
    char ** error_out
) {
    if (error_out != nullptr) {
        *error_out = nullptr;
    }
    if (first_token_microseconds_out != nullptr) {
        *first_token_microseconds_out = 0;
    }
    if (total_microseconds_out != nullptr) {
        *total_microseconds_out = 0;
    }
    if (generated_token_count_out != nullptr) {
        *generated_token_count_out = 0;
    }
    if (opaque_session == nullptr
        || system_prompt == nullptr
        || user_prompt == nullptr
        || maximum_output_tokens <= 0) {
        set_error(error_out, "Invalid llama completion request.");
        return nullptr;
    }

    const auto completion_started = std::chrono::steady_clock::now();
    Session & session = *static_cast<Session *>(opaque_session);
    // Each request owns fresh KV state. Recreate only the small context while
    // retaining the loaded model and its Metal weights across completions. This
    // avoids relying on architecture-specific recurrent-cache reset semantics.
    if (session.context_has_run) {
        llama_free(session.context);
        session.context = llama_init_from_model(
            session.model,
            session.context_params
        );
        if (session.context == nullptr) {
            set_error(error_out, "The llama context could not be refreshed.");
            return nullptr;
        }
    }
    session.context_has_run = true;

    std::string error;
    std::string prompt = format_prompt(
        session,
        system_prompt,
        user_prompt,
        error
    );
    if (!error.empty()) {
        set_error(error_out, error);
        return nullptr;
    }

    int32_t token_count = -llama_tokenize(
        session.vocab,
        prompt.c_str(),
        static_cast<int32_t>(prompt.size()),
        nullptr,
        0,
        true,
        true
    );
    if (token_count <= 0) {
        set_error(error_out, "The grounded prompt could not be tokenized.");
        return nullptr;
    }
    if (token_count + maximum_output_tokens
        > static_cast<int32_t>(llama_n_ctx(session.context))) {
        set_error(error_out, "The grounded prompt exceeds the configured context.");
        return nullptr;
    }

    std::vector<llama_token> prompt_tokens(static_cast<size_t>(token_count));
    int32_t written = llama_tokenize(
        session.vocab,
        prompt.c_str(),
        static_cast<int32_t>(prompt.size()),
        prompt_tokens.data(),
        token_count,
        true,
        true
    );
    if (written != token_count) {
        set_error(error_out, "The grounded prompt token count was inconsistent.");
        return nullptr;
    }

    llama_sampler * sampler = llama_sampler_chain_init(
        llama_sampler_chain_default_params()
    );
    llama_sampler * grammar = llama_sampler_init_grammar(
        session.vocab,
        evidence_count <= 0
            ? kUnlinkedResponseGrammar
            : evidence_count == 1
                ? kSingleEvidenceResponseGrammar
                : kGroundedResponseGrammar,
        "root"
    );
    llama_sampler * greedy = llama_sampler_init_greedy();
    if (sampler == nullptr || grammar == nullptr || greedy == nullptr) {
        if (sampler != nullptr) {
            llama_sampler_free(sampler);
        }
        if (grammar != nullptr) {
            llama_sampler_free(grammar);
        }
        if (greedy != nullptr) {
            llama_sampler_free(greedy);
        }
        set_error(error_out, "The answer sampler could not be created.");
        return nullptr;
    }
    llama_sampler_chain_add(sampler, grammar);
    llama_sampler_chain_add(sampler, greedy);

    std::string output;
    int32_t generated_token_count = 0;
    int32_t prompt_offset = 0;
    while (token_count - prompt_offset > kPromptBatchTokens) {
        llama_batch prompt_batch = llama_batch_get_one(
            prompt_tokens.data() + prompt_offset,
            kPromptBatchTokens
        );
        if (llama_decode(session.context, prompt_batch) != 0) {
            llama_sampler_free(sampler);
            set_error(error_out, "llama_decode failed while evaluating the prompt.");
            return nullptr;
        }
        prompt_offset += kPromptBatchTokens;
    }
    llama_batch batch = llama_batch_get_one(
        prompt_tokens.data() + prompt_offset,
        token_count - prompt_offset
    );
    for (int32_t index = 0; index < maximum_output_tokens; ++index) {
        int32_t decode_result = llama_decode(session.context, batch);
        if (decode_result != 0) {
            llama_sampler_free(sampler);
            set_error(error_out, "llama_decode failed.");
            return nullptr;
        }

        llama_token token = llama_sampler_sample(
            sampler,
            session.context,
            -1
        );
        if (llama_vocab_is_eog(session.vocab, token)) {
            break;
        }
        ++generated_token_count;
        if (generated_token_count == 1
            && first_token_microseconds_out != nullptr) {
            *first_token_microseconds_out = std::chrono::duration_cast<
                std::chrono::microseconds
            >(std::chrono::steady_clock::now() - completion_started).count();
        }
        if (!append_token_piece(session, token, output, error)) {
            llama_sampler_free(sampler);
            set_error(error_out, error);
            return nullptr;
        }
        batch = llama_batch_get_one(&token, 1);
    }

    llama_sampler_free(sampler);
    if (total_microseconds_out != nullptr) {
        *total_microseconds_out = std::chrono::duration_cast<
            std::chrono::microseconds
        >(std::chrono::steady_clock::now() - completion_started).count();
    }
    if (generated_token_count_out != nullptr) {
        *generated_token_count_out = generated_token_count;
    }
    return strdup(output.c_str());
}

void tg_llama_session_destroy(TGLlamaSessionRef opaque_session) {
    if (opaque_session == nullptr) {
        return;
    }
    Session * session = static_cast<Session *>(opaque_session);
    llama_free(session->context);
    llama_model_free(session->model);
    delete session;
    release_backend();
}

void tg_llama_string_free(char * string) {
    std::free(string);
}
