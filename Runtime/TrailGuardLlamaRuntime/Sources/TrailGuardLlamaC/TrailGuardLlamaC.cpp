#include "TrailGuardLlamaC.h"
#include "GroundedResponseGrammar.h"

#include <TargetConditionals.h>
#include <llama/llama.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

struct Session {
    llama_model * model;
    llama_context * context;
    const llama_vocab * vocab;
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
#if TARGET_OS_SIMULATOR
    model_params.n_gpu_layers = 0;
#else
    model_params.n_gpu_layers = 99;
#endif

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
    context_params.n_batch = static_cast<uint32_t>(context_tokens);
    context_params.n_threads = thread_count;
    context_params.n_threads_batch = thread_count;

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
    };
    return static_cast<TGLlamaSessionRef>(session);
}

char * tg_llama_session_complete(
    TGLlamaSessionRef opaque_session,
    const char * system_prompt,
    const char * user_prompt,
    int32_t maximum_output_tokens,
    char ** error_out
) {
    if (error_out != nullptr) {
        *error_out = nullptr;
    }
    if (opaque_session == nullptr
        || system_prompt == nullptr
        || user_prompt == nullptr
        || maximum_output_tokens <= 0) {
        set_error(error_out, "Invalid llama completion request.");
        return nullptr;
    }

    Session & session = *static_cast<Session *>(opaque_session);
    llama_memory_clear(llama_get_memory(session.context), true);

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
        kGroundedResponseGrammar,
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
        set_error(error_out, "The deterministic sampler could not be created.");
        return nullptr;
    }
    llama_sampler_chain_add(sampler, grammar);
    llama_sampler_chain_add(sampler, greedy);

    std::string output;
    llama_batch batch = llama_batch_get_one(
        prompt_tokens.data(),
        token_count
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
        if (!append_token_piece(session, token, output, error)) {
            llama_sampler_free(sampler);
            set_error(error_out, error);
            return nullptr;
        }
        batch = llama_batch_get_one(&token, 1);
    }

    llama_sampler_free(sampler);
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
