#include "AuroraLlamaC.h"
#include "GroundedResponseGrammar.h"
#include "PinnedMtmdABI.h"

#include <TargetConditionals.h>
#include <llama/llama.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <mutex>
#include <cmath>
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
    mtmd_context * vision_context;
    bool context_has_run;
};

struct EmbeddingSession {
    llama_model * model;
    llama_context * context;
    const llama_vocab * vocab;
    int32_t dimensions;
    int32_t context_tokens;
};

struct MtmdAPI {
    decltype(mtmd_context_params{}) (*context_params_default)(void);
    mtmd_context * (*init_from_file)(
        const char *, const llama_model *, mtmd_context_params
    );
    void (*free_context)(mtmd_context *);
    bool (*support_vision)(const mtmd_context *);
    const char * (*get_marker)(const mtmd_context *);
    mtmd_helper_bitmap_wrapper (*bitmap_from_buffer)(
        mtmd_context *, const unsigned char *, size_t, bool
    );
    void (*bitmap_free)(mtmd_bitmap *);
    mtmd_input_chunks * (*chunks_init)(void);
    void (*chunks_free)(mtmd_input_chunks *);
    int32_t (*tokenize)(
        mtmd_context *, mtmd_input_chunks *, const mtmd_input_text *,
        const mtmd_bitmap **, size_t
    );
    size_t (*token_count)(const mtmd_input_chunks *);
    int32_t (*eval_chunks)(
        mtmd_context *, llama_context *, const mtmd_input_chunks *, llama_pos,
        llama_seq_id, int32_t, bool, llama_pos *
    );

    bool available() const {
        return context_params_default && init_from_file && free_context
            && support_vision && get_marker && bitmap_from_buffer && bitmap_free
            && chunks_init && chunks_free && tokenize && token_count
            && eval_chunks;
    }
};

template <typename Function>
Function load_mtmd_symbol(const char * name) {
    return reinterpret_cast<Function>(dlsym(RTLD_DEFAULT, name));
}

const MtmdAPI & mtmd_api() {
#if defined(TRAILGUARD_LINKED_MTMD)
    static const MtmdAPI api{
        mtmd_context_params_default,
        mtmd_init_from_file,
        mtmd_free,
        mtmd_support_vision,
        mtmd_get_marker,
        mtmd_helper_bitmap_init_from_buf,
        mtmd_bitmap_free,
        mtmd_input_chunks_init,
        mtmd_input_chunks_free,
        mtmd_tokenize,
        mtmd_helper_get_n_tokens,
        mtmd_helper_eval_chunks,
    };
#else
    static const MtmdAPI api{
        load_mtmd_symbol<decltype(MtmdAPI::context_params_default)>("mtmd_context_params_default"),
        load_mtmd_symbol<decltype(MtmdAPI::init_from_file)>("mtmd_init_from_file"),
        load_mtmd_symbol<decltype(MtmdAPI::free_context)>("mtmd_free"),
        load_mtmd_symbol<decltype(MtmdAPI::support_vision)>("mtmd_support_vision"),
        load_mtmd_symbol<decltype(MtmdAPI::get_marker)>("mtmd_get_marker"),
        load_mtmd_symbol<decltype(MtmdAPI::bitmap_from_buffer)>("mtmd_helper_bitmap_init_from_buf"),
        load_mtmd_symbol<decltype(MtmdAPI::bitmap_free)>("mtmd_bitmap_free"),
        load_mtmd_symbol<decltype(MtmdAPI::chunks_init)>("mtmd_input_chunks_init"),
        load_mtmd_symbol<decltype(MtmdAPI::chunks_free)>("mtmd_input_chunks_free"),
        load_mtmd_symbol<decltype(MtmdAPI::tokenize)>("mtmd_tokenize"),
        load_mtmd_symbol<decltype(MtmdAPI::token_count)>("mtmd_helper_get_n_tokens"),
        load_mtmd_symbol<decltype(MtmdAPI::eval_chunks)>("mtmd_helper_eval_chunks"),
    };
#endif
    return api;
}

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
    const char * media_marker,
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

    const std::string user_content = media_marker == nullptr
        ? std::string(user_prompt)
        : std::string(media_marker) + "\n" + user_prompt;
    const llama_chat_message messages[] = {
        {"system", system_prompt},
        {"user", user_content.c_str()},
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
    const char * projector_path,
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

    mtmd_context * vision_context = nullptr;
    if (projector_path != nullptr) {
        const MtmdAPI & api = mtmd_api();
        if (!api.available()) {
            llama_free(context);
            llama_model_free(model);
            release_backend();
            set_error(error_out, "The pinned runtime does not export mtmd vision support.");
            return nullptr;
        }
        mtmd_context_params vision_params = api.context_params_default();
        vision_params.use_gpu = use_gpu;
        vision_params.print_timings = false;
        vision_params.n_threads = thread_count;
        vision_params.warmup = false;
        vision_context = api.init_from_file(
            projector_path,
            model,
            vision_params
        );
        if (vision_context == nullptr || !api.support_vision(vision_context)) {
            if (vision_context != nullptr) api.free_context(vision_context);
            llama_free(context);
            llama_model_free(model);
            release_backend();
            set_error(error_out, "The verified projector could not initialize vision.");
            return nullptr;
        }
    }

    Session * session = new Session{
        model,
        context,
        llama_model_get_vocab(model),
        context_params,
        vision_context,
        false,
    };
    return static_cast<TGLlamaSessionRef>(session);
}

char * tg_llama_session_complete(
    TGLlamaSessionRef opaque_session,
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
        || image_byte_count < 0
        || maximum_output_tokens <= 0
        || grammar_mode < 0
        || grammar_mode > 3) {
        set_error(error_out, "Invalid llama completion request.");
        return nullptr;
    }

    const auto completion_started = std::chrono::steady_clock::now();
    Session & session = *static_cast<Session *>(opaque_session);
    const bool has_image = image_bytes != nullptr && image_byte_count > 0;
    if (grammar_mode == 1 && !has_image) {
        set_error(error_out, "Visual observation requires image input.");
        return nullptr;
    }
    if (has_image && session.vision_context == nullptr) {
        set_error(error_out, "Image input requires an initialized verified projector.");
        return nullptr;
    }
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
        has_image ? mtmd_api().get_marker(session.vision_context) : nullptr,
        error
    );
    if (!error.empty()) {
        set_error(error_out, error);
        return nullptr;
    }

    int32_t token_count = has_image ? 0 : -llama_tokenize(
        session.vocab,
        prompt.c_str(),
        static_cast<int32_t>(prompt.size()),
        nullptr,
        0,
        true,
        true
    );
    if (!has_image && token_count <= 0) {
        set_error(error_out, "The grounded prompt could not be tokenized.");
        return nullptr;
    }
    if (!has_image && token_count + maximum_output_tokens
        > static_cast<int32_t>(llama_n_ctx(session.context))) {
        set_error(error_out, "The grounded prompt exceeds the configured context.");
        return nullptr;
    }

    std::vector<llama_token> prompt_tokens(
        has_image ? 0 : static_cast<size_t>(token_count)
    );
    int32_t written = has_image ? 0 : llama_tokenize(
        session.vocab,
        prompt.c_str(),
        static_cast<int32_t>(prompt.size()),
        prompt_tokens.data(),
        token_count,
        true,
        true
    );
    if (!has_image && written != token_count) {
        set_error(error_out, "The grounded prompt token count was inconsistent.");
        return nullptr;
    }

    llama_sampler * sampler = llama_sampler_chain_init(
        llama_sampler_chain_default_params()
    );
    const bool expert_request = maximum_output_tokens > 160;
    const bool expert_grounded = expert_request
        && evidence_count > 0;
    const bool expert_intent = grammar_mode == 2;
    const bool expert_clarification = grammar_mode == 3;
    llama_sampler * grammar = llama_sampler_init_grammar(
        session.vocab,
        expert_intent
            ? kExpertIntentDecisionGrammar
            : expert_clarification
            ? kExpertClarificationResponseGrammar
            : expert_grounded && evidence_count == 1
            ? kExpertSingleEvidenceResponseGrammar
            : expert_grounded
                ? kExpertGroundedResponseGrammar
        : evidence_count <= 0
            ? expert_request
                ? kExpertUnlinkedResponseGrammar
                : kUnlinkedResponseGrammar
            : evidence_count == 1
                ? kSingleEvidenceResponseGrammar
                : kGroundedResponseGrammar,
        "root"
    );
    llama_sampler * penalties = expert_request
        ? llama_sampler_init_penalties(64, 1.15f, 0.0f, 0.0f)
        : nullptr;
    llama_sampler * greedy = llama_sampler_init_greedy();
    if (sampler == nullptr || grammar == nullptr || greedy == nullptr
        || (expert_request && penalties == nullptr)) {
        if (sampler != nullptr) {
            llama_sampler_free(sampler);
        }
        if (grammar != nullptr) {
            llama_sampler_free(grammar);
        }
        if (penalties != nullptr) {
            llama_sampler_free(penalties);
        }
        if (greedy != nullptr) {
            llama_sampler_free(greedy);
        }
        set_error(error_out, "The answer sampler could not be created.");
        return nullptr;
    }
    llama_sampler_chain_add(sampler, grammar);
    if (penalties != nullptr) {
        llama_sampler_chain_add(sampler, penalties);
    }
    llama_sampler_chain_add(sampler, greedy);

    std::string output;
    int32_t generated_token_count = 0;
    int32_t prompt_offset = 0;
    bool prompt_already_evaluated = false;
    if (has_image) {
        const MtmdAPI & api = mtmd_api();
        mtmd_helper_bitmap_wrapper bitmap = api.bitmap_from_buffer(
            session.vision_context,
            image_bytes,
            static_cast<size_t>(image_byte_count),
            false
        );
        if (bitmap.bitmap == nullptr || bitmap.video_ctx != nullptr) {
            if (bitmap.bitmap != nullptr) api.bitmap_free(bitmap.bitmap);
            llama_sampler_free(sampler);
            set_error(error_out, "The attached image is corrupt or unsupported.");
            return nullptr;
        }
        mtmd_input_chunks * chunks = api.chunks_init();
        const mtmd_bitmap * bitmaps[] = {bitmap.bitmap};
        mtmd_input_text input{prompt.c_str(), true, true};
        const int32_t tokenize_result = chunks == nullptr
            ? -1
            : api.tokenize(
                session.vision_context,
                chunks,
                &input,
                bitmaps,
                1
            );
        const size_t multimodal_tokens = tokenize_result == 0
            ? api.token_count(chunks)
            : 0;
        llama_pos new_n_past = 0;
        const bool exceeds_context = multimodal_tokens
            + static_cast<size_t>(maximum_output_tokens)
            > llama_n_ctx(session.context);
        const int32_t eval_result = tokenize_result == 0 && !exceeds_context
            ? api.eval_chunks(
                session.vision_context,
                session.context,
                chunks,
                0,
                0,
                kPromptBatchTokens,
                true,
                &new_n_past
            )
            : -1;
        if (chunks != nullptr) api.chunks_free(chunks);
        api.bitmap_free(bitmap.bitmap);
        if (tokenize_result != 0 || exceeds_context || eval_result != 0) {
            llama_sampler_free(sampler);
            set_error(
                error_out,
                exceeds_context
                    ? "The multimodal prompt exceeds the configured context."
                    : "The image could not be evaluated by the pinned projector."
            );
            return nullptr;
        }
        prompt_already_evaluated = true;
    }
    while (!has_image && token_count - prompt_offset > kPromptBatchTokens) {
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
    llama_batch batch{};
    if (!has_image) {
        batch = llama_batch_get_one(
            prompt_tokens.data() + prompt_offset,
            token_count - prompt_offset
        );
    }
    for (int32_t index = 0; index < maximum_output_tokens; ++index) {
        int32_t decode_result = prompt_already_evaluated
            ? 0
            : llama_decode(session.context, batch);
        prompt_already_evaluated = false;
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
        const size_t piece_offset = output.size();
        if (!append_token_piece(session, token, output, error)) {
            llama_sampler_free(sampler);
            set_error(error_out, error);
            return nullptr;
        }
        if (token_callback != nullptr && output.size() > piece_offset) {
            token_callback(
                reinterpret_cast<const uint8_t *>(output.data() + piece_offset),
                static_cast<int32_t>(output.size() - piece_offset),
                token_context
            );
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
    if (session->vision_context != nullptr) {
        mtmd_api().free_context(session->vision_context);
    }
    llama_free(session->context);
    llama_model_free(session->model);
    delete session;
    release_backend();
}

int32_t tg_llama_runtime_supports_vision(void) {
    return mtmd_api().available() ? 1 : 0;
}

TGEmbeddingSessionRef tg_embedding_session_create(
    const char * model_path,
    int32_t context_tokens,
    int32_t thread_count,
    int32_t expected_dimensions,
    char ** error_out
) {
    if (error_out != nullptr) *error_out = nullptr;
    if (model_path == nullptr || context_tokens <= 0 || thread_count <= 0
        || expected_dimensions <= 0) {
        set_error(error_out, "Invalid embedding runtime configuration.");
        return nullptr;
    }
    retain_backend();
    llama_model_params model_params = llama_model_default_params();
    const int32_t gpu_layers = gpu_offload_layers();
    const bool use_gpu = gpu_layers > 0;
    model_params.n_gpu_layers = gpu_layers;
    llama_model * model = llama_model_load_from_file(model_path, model_params);
    if (model == nullptr) {
        release_backend();
        set_error(error_out, "The embedding GGUF model could not be loaded.");
        return nullptr;
    }
    const int32_t dimensions = llama_model_n_embd_out(model);
    if (dimensions != expected_dimensions) {
        llama_model_free(model);
        release_backend();
        set_error(error_out, "The embedding model dimensions do not match the signed package.");
        return nullptr;
    }
    llama_context_params params = llama_context_default_params();
    params.n_ctx = static_cast<uint32_t>(context_tokens);
    params.n_batch = static_cast<uint32_t>(context_tokens);
    params.n_ubatch = static_cast<uint32_t>(std::min(context_tokens, kPhysicalBatchTokens));
    params.n_threads = thread_count;
    params.n_threads_batch = thread_count;
    params.embeddings = true;
    params.attention_type = LLAMA_ATTENTION_TYPE_NON_CAUSAL;
    params.pooling_type = LLAMA_POOLING_TYPE_CLS;
    params.offload_kqv = use_gpu;
    params.op_offload = use_gpu;
    llama_context * context = llama_init_from_model(model, params);
    if (context == nullptr) {
        llama_model_free(model);
        release_backend();
        set_error(error_out, "The embedding context could not be created.");
        return nullptr;
    }
    return static_cast<TGEmbeddingSessionRef>(new EmbeddingSession{
        model,
        context,
        llama_model_get_vocab(model),
        dimensions,
        context_tokens,
    });
}

int32_t tg_embedding_session_embed(
    TGEmbeddingSessionRef opaque_session,
    const char * text,
    float * output,
    int32_t output_dimensions,
    char ** error_out
) {
    if (error_out != nullptr) *error_out = nullptr;
    if (opaque_session == nullptr || text == nullptr || output == nullptr) {
        set_error(error_out, "Invalid embedding request.");
        return 0;
    }
    EmbeddingSession & session = *static_cast<EmbeddingSession *>(opaque_session);
    if (output_dimensions != session.dimensions) {
        set_error(error_out, "The embedding output buffer has the wrong size.");
        return 0;
    }
    const int32_t text_length = static_cast<int32_t>(std::strlen(text));
    int32_t token_count = -llama_tokenize(
        session.vocab, text, text_length, nullptr, 0, true, false
    );
    if (token_count <= 0 || token_count > session.context_tokens) {
        set_error(error_out, "The embedding query exceeds the configured context.");
        return 0;
    }
    std::vector<llama_token> tokens(static_cast<size_t>(token_count));
    if (llama_tokenize(
        session.vocab, text, text_length, tokens.data(), token_count, true, false
    ) != token_count) {
        set_error(error_out, "The embedding query could not be tokenized.");
        return 0;
    }
    llama_batch batch = llama_batch_init(token_count, 0, 1);
    batch.n_tokens = token_count;
    for (int32_t index = 0; index < token_count; ++index) {
        batch.token[index] = tokens[static_cast<size_t>(index)];
        batch.pos[index] = index;
        batch.n_seq_id[index] = 1;
        batch.seq_id[index][0] = 0;
        batch.logits[index] = true;
    }
    const int32_t result = llama_model_has_encoder(session.model)
        ? llama_encode(session.context, batch)
        : llama_decode(session.context, batch);
    llama_batch_free(batch);
    if (result != 0) {
        set_error(error_out, "The embedding model could not evaluate the query.");
        return 0;
    }
    float * values = llama_get_embeddings_seq(session.context, 0);
    if (values == nullptr) values = llama_get_embeddings_ith(session.context, -1);
    if (values == nullptr) {
        set_error(error_out, "The embedding model returned no pooled vector.");
        return 0;
    }
    double squared_norm = 0;
    for (int32_t index = 0; index < session.dimensions; ++index) {
        squared_norm += static_cast<double>(values[index]) * values[index];
    }
    const double norm = std::sqrt(squared_norm);
    if (!std::isfinite(norm) || norm <= 0) {
        set_error(error_out, "The embedding model returned an invalid vector.");
        return 0;
    }
    for (int32_t index = 0; index < session.dimensions; ++index) {
        output[index] = static_cast<float>(values[index] / norm);
    }
    return 1;
}

void tg_embedding_session_destroy(TGEmbeddingSessionRef opaque_session) {
    if (opaque_session == nullptr) return;
    EmbeddingSession * session = static_cast<EmbeddingSession *>(opaque_session);
    llama_free(session->context);
    llama_model_free(session->model);
    delete session;
    release_backend();
}

void tg_llama_string_free(char * string) {
    std::free(string);
}
