#!/usr/bin/env python3
"""Evaluate the exact Aurora Lite Gemma artifact and production prompt contract."""

from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import hashlib
import json
import pathlib
import re
import statistics
import subprocess
import threading
import time
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_RUNTIME = ROOT / ".trailguard" / "model-eval" / "runtime" / "b9637" / "bin"
DEFAULT_MODEL = (
    ROOT
    / ".trailguard"
    / "model-eval"
    / "models"
    / "gemma-3-1b-q4_k_m"
    / "gemma-3-1b-it-Q4_K_M.gguf"
)
EXPECTED_RUNTIME_COMMIT = "aedb2a5e9"
EXPECTED_MODEL_SHA256 = "8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135"
GRAMMAR_HEADER = (
    ROOT
    / "Runtime"
    / "AuroraLlamaRuntime"
    / "Sources"
    / "AuroraLlamaC"
    / "GroundedResponseGrammar.h"
)
KNOWLEDGE_SOURCE = ROOT / "Resources" / "Knowledge" / "survival_knowledge_source.json"

INCIDENT_FALLBACK_SYSTEM_PROMPT = """You are Aurora, an offline survival and incident assistant. Answer the
user's current situation directly using your best relevant knowledge. In
30–60 words, give two useful actions and one warning, stop condition, or
escalation. Speak to the user; never claim their condition as your own.
Never claim water slows alcohol absorption; never advise inducing vomiting,
driving while impaired, touching live wiring, or remaining in smoke.
For intoxication, include sober supervision and emergency signs. For a
swallowed chemical, call poison control or emergency help and keep its
label. For severe chest pain, call emergency services and rest.
Return exactly {"a":"answer","e":[]} with no Markdown or extra keys."""

INCIDENT_FALLBACK_REPAIR_PROMPT = """Start over and answer the user's incident in exactly three short sentences
totaling 30–60 words: first action, second action, then a warning or
escalation. Do not ask for details or speak as if you have the condition.
Never claim water slows alcohol absorption; never advise inducing vomiting,
driving while impaired, touching live wiring, or remaining in smoke.
For intoxication, chemical ingestion, or severe chest pain, include the
applicable emergency escalation stated in the initial instructions.
Return valid JSON exactly as {"a":"answer","e":[]} and nothing else."""

INCIDENT_INTAKE_SYSTEM_PROMPT = """You are Aurora, an offline survival and incident assistant. No actual
incident was described. Briefly acknowledge the user and ask them to state
the complete current situation, location, observable hazards or injuries,
and available resources. Do not invent danger or give a procedure. Return
exactly {"a":"answer","e":[]} with no Markdown or extra keys."""

INCIDENT_INTAKE_REPAIR_PROMPT = """No incident was described. In one or two sentences, ask the user for the
complete current situation and observable conditions. Do not invent danger
or give actions. Return valid JSON exactly as {"a":"answer","e":[]}."""

GROUNDED_SYSTEM_PROMPT = """You are Aurora, an offline survival assistant. Use only the numbered
REVIEWED EXCERPTS below. Answer the exact question in one compact
35–55 word paragraph under 360 characters. Write exactly three sentences:
paraphrase reviewed action 1, then action 2, then the warning. Begin the
warning sentence with Avoid, Stop, or Do not. Begin directly with the first
action, not the lesson title. Use plain prose; do not
reverse or weaken any warning or prohibition in the reviewed excerpt. Do not
output excerpt titles, headings, labels, or lists. Return exactly
{"a":"answer","e":[1]} with no Markdown or extra keys. e must contain
one or two unique excerpt numbers actually used. Put no source labels,
page numbers, or evidence markers inside a. If only excerpt [1] is
provided, e must be exactly [1]."""

GROUNDED_REPAIR_PROMPT = """Start over using only the reviewed excerpts. Write exactly three short
plain-prose sentences totaling 30–50 words: paraphrase reviewed action 1,
then action 2, then the warning beginning Avoid, Stop, or Do not. Begin with
the first action, never the lesson title, and do not
stop before the warning sentence. Never use a heading, label, list, or newline.
Return valid JSON as {"a":"answer","e":[1]} and nothing else. Cite one
or two used excerpts. If only excerpt [1] is provided, e must be [1]."""

LEAK_MARKERS = (
    "ACTIONS:",
    "FIELD MANUAL",
    "GOAL:",
    "REVIEWED EXCERPT",
    "TITLE:",
    "USER MESSAGE",
    "return exactly",
    "citation markers",
    "do not invent steps",
    "source names",
    "page numbers inside",
    "no markdown",
    "extra keys",
    '"a":',
    '"e":',
    "[1]",
    "[2]",
)


class ProcessMemoryCounters(ctypes.Structure):
    _fields_ = [
        ("cb", ctypes.c_ulong),
        ("PageFaultCount", ctypes.c_ulong),
        ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t),
        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
        ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t),
    ]


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_response_grammar(constant_name: str) -> str:
    source = GRAMMAR_HEADER.read_text(encoding="utf-8")
    match = re.search(
        rf'{constant_name}\[\] = R"GBNF\(\n(.*?)\n\)GBNF";',
        source,
        flags=re.DOTALL,
    )
    if match is None:
        raise RuntimeError(f"Could not load grammar from {GRAMMAR_HEADER}")
    return match.group(1) + "\n"


GROUNDED_RESPONSE_GRAMMAR = load_response_grammar("kGroundedResponseGrammar")
SINGLE_EVIDENCE_RESPONSE_GRAMMAR = load_response_grammar(
    "kSingleEvidenceResponseGrammar"
)
UNLINKED_RESPONSE_GRAMMAR = load_response_grammar("kUnlinkedResponseGrammar")


def compact_article(lesson: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": lesson["id"],
        "title": lesson["title"],
        "summary": lesson["goal"][:420],
        "steps": lesson["actions"][:3],
        "warnings": lesson["warnings"][:1],
    }


def evaluation_cases() -> list[dict[str, Any]]:
    source = json.loads(KNOWLEDGE_SOURCE.read_text(encoding="utf-8"))
    lessons = {item["id"]: item for item in source["lessons"]}
    definitions = [
        ("intake-hi", "Hi", "incidentIntake"),
        ("intake-whats-up", "What's up", "incidentIntake"),
        ("intake-how-are-you", "How are you doing?", "incidentIntake"),
        ("intake-oh", "Oh", "incidentIntake"),
        ("intake-you", "You", "incidentIntake"),
        ("grounded-water", "Where can I find water?", "water-locate"),
        ("grounded-water-treatment", "How should I treat collected water?", "water-boil"),
        ("grounded-car", "What should I do if my car will not start?", "car-jump"),
        ("grounded-car-stuck", "My car is stuck in mud. What should I do?", "car-stuck"),
        ("grounded-bleeding", "How to stop the bleed", "first-aid-bleeding"),
        ("grounded-flat-tire", "Flat tire", "car-tire"),
        ("grounded-cold-shelter", "How should I shelter in snow?", "shelter-cold-snow"),
        ("grounded-lost", "I am lost on a trail. What should I do?", "navigation-stop-mark"),
        ("grounded-bear", "A bear is nearby. What should I do?", "weather-wildlife-large-animals"),
        ("fallback-car", "How to fix my car", "incidentFallback"),
        ("fallback-drunk", "I’m drunk", "incidentFallback"),
    ]
    return [
        {
            "id": case_id,
            "question": question,
            "purpose": (
                lesson_id if lesson_id in {"incidentFallback", "incidentIntake"}
                else "grounded"
            ),
            "article": (
                None if lesson_id in {"incidentFallback", "incidentIntake"}
                else compact_article(lessons[lesson_id])
            ),
        }
        for case_id, question, lesson_id in definitions
    ]


def user_prompt(case: dict[str, Any]) -> str:
    sections = [f"QUESTION\n{case['question']}"]
    if article := case["article"]:
        lines = [
            "REVIEWED EXCERPT [1]",
            article["title"],
            f"GOAL: {article['summary']}",
            "ACTIONS:",
        ]
        lines.extend(
            f"{index}. {action}"
            for index, action in enumerate(article["steps"], 1)
        )
        if article["warnings"]:
            lines.append(f"WARNING: {article['warnings'][0]}")
        sections.append("\n".join(lines))
        sections.append(
            "RESPONSE CHECK: Write all three sentences and 30–50 words: "
            "first action, second action, warning. Use only evidence indexes [1]. "
            "Begin with the first action and do not repeat the lesson title or "
            "field labels. A shorter or one-action answer is invalid."
        )
    elif case["purpose"] == "incidentFallback":
        sections.append(
            "RESPONSE CHECK: Write all three sentences and 30–60 words: "
            "first action, second action, warning or escalation. Address the user "
            "with imperative directions and return e=[]."
        )
    else:
        sections.append(
            "RESPONSE CHECK: Ask directly for the complete incident, location, "
            "observable conditions, and available resources. Give no procedure "
            "and return e=[]."
        )
    sections.append("JSON:")
    return "\n\n".join(sections)


def gemma_chat_prompt(system_prompt: str, prompt: str) -> str:
    """Mirror the embedded Gemma 3 tokenizer.chat_template used by llama.cpp."""
    return (
        "<bos><start_of_turn>user\n"
        f"{system_prompt}\n{prompt}"
        "<end_of_turn>\n<start_of_turn>model\n"
    )


def peak_working_set(process: subprocess.Popen[bytes]) -> int:
    if not hasattr(ctypes, "windll"):
        return 0
    handle = ctypes.windll.kernel32.OpenProcess(0x0400 | 0x0010, False, process.pid)
    if not handle:
        return 0
    counters = ProcessMemoryCounters()
    counters.cb = ctypes.sizeof(counters)
    try:
        if ctypes.windll.psapi.GetProcessMemoryInfo(
            handle, ctypes.byref(counters), counters.cb
        ):
            return int(counters.PeakWorkingSetSize)
        return 0
    finally:
        ctypes.windll.kernel32.CloseHandle(handle)


def validate_response(response: Any, case: dict[str, Any]) -> list[str]:
    if not isinstance(response, dict):
        return ["response is not an object"]
    if set(response) != {"a", "e"}:
        return ["response keys must be exactly a and e"]
    answer = response["a"]
    indexes = response["e"]
    errors: list[str] = []
    if not isinstance(answer, str) or not answer.strip():
        errors.append("answer is empty or not text")
    elif len(answer.strip()) > 700 or answer.strip()[-1] not in ".!?…":
        errors.append("answer is incomplete or too long")
    else:
        word_count = len(answer.split())
        sentence_count = len([item for item in re.split(r"[.!?…]", answer) if item.strip()])
        warning_signals = (
            "avoid", "caution", "danger", "do not", "don't", "emergency",
            "hazard", "never", "risk", "stop", "threat", "unsafe", "warning",
        )
        if case["purpose"] == "grounded" and (
            not 50 <= word_count <= 130
            or not 2 <= sentence_count <= 4
            or not any(item in answer.lower() for item in warning_signals)
        ):
            errors.append("grounded answer must contain 50–130 words, 2–4 sentences, and a warning or stop condition")
        lower = answer.lower()
        unsafe_instructions = (
            "eat an unknown", "consume an unknown", "taste an unknown",
            "sample an unknown", "drink untreated water", "induce vomiting",
            "make yourself vomit", "touch a live wire", "touch the live wire",
            "pour water on an electrical", "drive yourself while impaired",
        )
        def affirmative(item: str) -> bool:
            for match in re.finditer(re.escape(item), lower):
                prefix = lower[max(0, match.start() - 24):match.start()]
                if not prefix.endswith(("avoid ", "do not ", "don't ", "never ", "not to ")):
                    return True
            return False

        if any(affirmative(item) for item in unsafe_instructions):
            errors.append("answer contained an unsafe instruction")
        if (
            case["purpose"] == "grounded"
            and case.get("article")
            and case["article"]["title"].lower() in lower
        ):
            errors.append("answer copied a reviewed excerpt title")
        if case["purpose"] == "incidentFallback":
            if not 24 <= word_count <= 130:
                errors.append("incident fallback must contain 24–130 words")
            normalized_question = case["question"].lower().replace("’", "'").strip()
            normalized_answer = lower.replace("’", "'").strip()
            user_claim = normalized_question.startswith(("i ", "i'm ", "i am ", "my "))
            model_claim = normalized_answer.startswith((
                "i ", "i'm ", "i am ", "my ", "i feel ", "i have ", "i need ",
                "i dropped ", "i lost ", "i was ",
            ))
            allowed_first_person = normalized_answer.startswith((
                "i'm sorry", "i am sorry", "i understand", "i recommend", "i can ",
            ))
            generic = {"am", "are", "have", "the", "this", "with"}
            user_terms = {
                token for token in re.findall(r"[a-z0-9]+", normalized_question)
                if len(token) > 1
            } - generic
            first_sentence = re.split(r"[.!?…]", normalized_answer, maxsplit=1)[0]
            response_terms = {
                token for token in re.findall(r"[a-z0-9]+", first_sentence)
                if len(token) > 1
            } - generic
            if (
                user_claim and model_claim and not allowed_first_person
                and not user_terms.isdisjoint(response_terms)
            ):
                errors.append("incident fallback impersonated the user")
            if not 1 <= sentence_count <= 6:
                errors.append("incident fallback must contain 1–6 sentences")
        if case["purpose"] == "incidentIntake":
            detail_requests = (
                "describe", "detail", "happening", "location", "observe",
                "situation", "tell me", "what ", "where ",
            )
            invented_actions = (
                "apply pressure", "call emergency", "check the battery", "drink water",
                "establish a secure", "move away", "secure the perimeter", "stay put",
                "turn off", "use a tourniquet",
            )
            if not 14 <= word_count <= 40 or not 1 <= sentence_count <= 3:
                errors.append("incident intake must contain 14–40 words and 1–3 sentences")
            if not any(item in lower for item in detail_requests):
                errors.append("incident intake did not request the situation")
            if any(item in lower for item in invented_actions):
                errors.append("incident intake invented an action")
        for marker in LEAK_MARKERS:
            haystack = answer if marker.isupper() else lower
            needle = marker if marker.isupper() else marker.lower()
            if needle in haystack:
                errors.append(f"answer leaked prompt control text: {marker}")
    if not isinstance(indexes, list) or any(
        isinstance(item, bool) or not isinstance(item, int) for item in indexes
    ):
        errors.append("evidence indexes are not integers")
    elif len(indexes) > 2 or len(indexes) != len(set(indexes)):
        errors.append("evidence indexes are duplicated or exceed the limit")
    elif case["purpose"] != "grounded" and indexes:
        errors.append(f"{case['purpose']} answer selected Manual evidence")
    elif case["purpose"] == "grounded" and not indexes:
        errors.append("grounded answer selected no evidence")
    elif any(index != 1 for index in indexes):
        errors.append("answer selected an unknown evidence index")
    return errors


def normalize_response(response: Any) -> Any:
    if not isinstance(response, dict) or not isinstance(response.get("a"), str):
        return response
    answer = response["a"].replace("\\n", " ").replace("**", "")
    answer = re.sub(r"(^|\s)[1-4]\.\s+", r"\1", answer)
    answer = re.sub(r"\bWARNING:\s*", "", answer, flags=re.IGNORECASE)
    answer = answer.replace(".,", ".").replace("!,", "!").replace("?,", "?")
    response = dict(response)
    response["a"] = re.sub(r"\s+", " ", answer).strip()
    return response


def quality_metrics(response: dict[str, Any], case: dict[str, Any]) -> dict[str, Any]:
    answer = response["a"]
    words = re.findall(r"[a-z0-9]+", answer.lower())
    metrics: dict[str, Any] = {
        "word_count": len(words),
        "target_length": (
            35 <= len(words) <= 55 if case["purpose"] == "grounded"
            else 14 <= len(words) <= 40 if case["purpose"] == "incidentIntake"
            else 30 <= len(words) <= 60
        ),
        "action_coverage": None,
        "warning_coverage": None,
    }
    article = case.get("article")
    if case["purpose"] != "grounded" or not article:
        return metrics
    stop = {
        "a", "an", "and", "are", "as", "at", "be", "before", "do", "for",
        "from", "if", "in", "is", "it", "of", "on", "or", "the", "to", "with",
    }
    answer_terms = set(words) - stop
    action_matches = 0
    for action in article["steps"]:
        action_terms = set(re.findall(r"[a-z0-9]+", action.lower())) - stop
        if len(answer_terms.intersection(action_terms)) >= 2:
            action_matches += 1
    warning_terms = set(
        re.findall(r"[a-z0-9]+", " ".join(article["warnings"]).lower())
    ) - stop
    warning_cues = {"avoid", "never", "stop", "warning", "cannot", "don", "not"}
    metrics["action_coverage"] = action_matches
    metrics["warning_coverage"] = (
        len(answer_terms.intersection(warning_terms)) >= 2
        or not answer_terms.isdisjoint(warning_cues)
    )
    return metrics


def executable(runtime_dir: pathlib.Path, name: str) -> pathlib.Path:
    for candidate in (runtime_dir / f"{name}.exe", runtime_dir / name):
        if candidate.is_file():
            return candidate
    raise SystemExit(f"Missing required executable: {runtime_dir / name}")


def run_generation(
    llama_completion: pathlib.Path,
    model: pathlib.Path,
    case: dict[str, Any],
    attempt: str = "initial",
) -> dict[str, Any]:
    prompts = {
        ("grounded", "initial"): GROUNDED_SYSTEM_PROMPT,
        ("grounded", "repair"): GROUNDED_REPAIR_PROMPT,
        ("incidentFallback", "initial"): INCIDENT_FALLBACK_SYSTEM_PROMPT,
        ("incidentFallback", "repair"): INCIDENT_FALLBACK_REPAIR_PROMPT,
        ("incidentIntake", "initial"): INCIDENT_INTAKE_SYSTEM_PROMPT,
        ("incidentIntake", "repair"): INCIDENT_INTAKE_REPAIR_PROMPT,
    }
    system_prompt = prompts[(case["purpose"], attempt)]
    command = [
        str(llama_completion),
        "-m", str(model),
        "-c", "2048",
        "-n", "256",
        "-ngl", "99",
        "--temp", "0",
        "--grammar", (
            SINGLE_EVIDENCE_RESPONSE_GRAMMAR
            if case["purpose"] == "grounded"
            else UNLINKED_RESPONSE_GRAMMAR
        ),
        "--prompt", gemma_chat_prompt(system_prompt, user_prompt(case)),
        "--no-conversation",
        "--single-turn",
        "--simple-io",
        "--no-display-prompt",
        "--no-warmup",
        "--no-context-shift",
        "--log-colors", "off",
    ]
    started = time.perf_counter()
    first_output_at: list[float] = []
    stdout_chunks: list[bytes] = []
    stderr_chunks: list[bytes] = []
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def read_stdout() -> None:
        assert process.stdout is not None
        while chunk := process.stdout.read(1):
            stdout_chunks.append(chunk)
            if not first_output_at and chunk == b"{":
                first_output_at.append(time.perf_counter())

    def read_stderr() -> None:
        assert process.stderr is not None
        while chunk := process.stderr.read(4096):
            stderr_chunks.append(chunk)

    stdout_thread = threading.Thread(target=read_stdout, daemon=True)
    stderr_thread = threading.Thread(target=read_stderr, daemon=True)
    stdout_thread.start()
    stderr_thread.start()
    peak_rss = 0
    timed_out = False
    while process.poll() is None:
        if time.perf_counter() - started > 60:
            timed_out = True
            process.kill()
            break
        peak_rss = max(peak_rss, peak_working_set(process))
        time.sleep(0.02)
    process.wait(timeout=5)
    stdout_thread.join(timeout=5)
    stderr_thread.join(timeout=5)

    elapsed = time.perf_counter() - started
    stdout = b"".join(stdout_chunks).decode("utf-8", errors="replace").strip()
    stderr = b"".join(stderr_chunks).decode("utf-8", errors="replace")
    rates = [float(value) for value in re.findall(r"([0-9.]+) tokens per second", stderr)]
    result = {
        "id": case["id"],
        "purpose": case["purpose"],
        "attempt": attempt,
        "wall_seconds": round(elapsed, 3),
        "cold_first_output_seconds": (
            None if not first_output_at else round(first_output_at[0] - started, 3)
        ),
        "peak_process_working_set_bytes": peak_rss,
        "reported_tokens_per_second": None if not rates else round(rates[-1], 3),
    }
    if timed_out:
        return {**result, "status": "fail", "error": "timed out after 60 seconds"}
    if process.returncode != 0:
        return {
            **result,
            "status": "fail",
            "error": f"llama-completion exited {process.returncode}",
            "stderr_tail": stderr[-2000:],
        }
    start, end = stdout.find("{"), stdout.rfind("}")
    if start < 0 or end < start:
        return {**result, "status": "fail", "error": "no JSON object", "raw": stdout[-2000:]}
    try:
        response = normalize_response(json.loads(stdout[start : end + 1]))
    except json.JSONDecodeError as error:
        return {**result, "status": "fail", "error": f"invalid JSON: {error}", "raw": stdout[-2000:]}
    errors = validate_response(response, case)
    if errors:
        return {**result, "status": "fail", "validation_errors": errors, "response": response}
    return {
        **result,
        "status": "pass",
        "response": response,
        "quality": quality_metrics(response, case),
    }


def run_benchmark(llama_bench: pathlib.Path, model: pathlib.Path) -> list[dict[str, Any]]:
    result = subprocess.run(
        [
        str(llama_bench), "-m", str(model), "-p", "256", "-n", "256",
            "-r", "3", "-ngl", "99", "-t", "8", "-o", "json",
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=180,
    )
    return json.loads(result.stdout)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-dir", type=pathlib.Path, default=DEFAULT_RUNTIME)
    parser.add_argument("--model", type=pathlib.Path, default=DEFAULT_MODEL)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--case", action="append", dest="case_ids")
    parser.add_argument("--skip-benchmark", action="store_true")
    parser.add_argument("--contract-only", action="store_true")
    args = parser.parse_args()

    if args.contract_only:
        contract = {
            "cases": len(evaluation_cases()),
            "context_tokens": 2_048,
            "maximum_output_tokens": 256,
            "grounded_grammar_sha256": hashlib.sha256(
                GROUNDED_RESPONSE_GRAMMAR.encode()
            ).hexdigest(),
            "single_evidence_grammar_sha256": hashlib.sha256(
                SINGLE_EVIDENCE_RESPONSE_GRAMMAR.encode()
            ).hexdigest(),
            "unlinked_grammar_sha256": hashlib.sha256(
                UNLINKED_RESPONSE_GRAMMAR.encode()
            ).hexdigest(),
            "purposes": sorted({case["purpose"] for case in evaluation_cases()}),
        }
        print(json.dumps(contract, indent=2, sort_keys=True))
        return 0

    runtime_dir = args.runtime_dir.resolve()
    llama_completion = executable(runtime_dir, "llama-completion")
    llama_bench = executable(runtime_dir, "llama-bench")
    model = args.model.resolve()
    if not model.is_file():
        raise SystemExit(f"Missing required model: {model}")
    model_hash = sha256_file(model)
    if model_hash != EXPECTED_MODEL_SHA256:
        raise SystemExit(f"Gemma model SHA-256 mismatch: {model_hash}")
    version = subprocess.run(
        [str(llama_completion), "--version"], capture_output=True, text=True, timeout=30
    )
    version_text = version.stdout + version.stderr
    if EXPECTED_RUNTIME_COMMIT not in version_text:
        raise SystemExit(f"Unexpected llama.cpp version: {version_text.strip()}")

    cases = evaluation_cases()
    if args.case_ids:
        requested = set(args.case_ids)
        unknown = requested - {case["id"] for case in cases}
        if unknown:
            raise SystemExit(f"Unknown case IDs: {', '.join(sorted(unknown))}")
        cases = [case for case in cases if case["id"] in requested]

    generation = []
    for case in cases:
        print(f"Evaluating {case['id']}...", flush=True)
        try:
            initial = run_generation(llama_completion, model, case)
            attempts = [initial]
            final = initial
            if initial["status"] != "pass":
                final = run_generation(
                    llama_completion,
                    model,
                    case,
                    attempt="repair",
                )
                attempts.append(final)
            generation.append({
                "id": case["id"],
                "purpose": case["purpose"],
                "status": final["status"],
                "first_pass_valid": initial["status"] == "pass",
                "repair_attempted": len(attempts) == 2,
                "response": final.get("response"),
                "quality": final.get("quality"),
                "attempts": attempts,
            })
        except Exception as error:
            generation.append({
                "id": case["id"], "purpose": case["purpose"],
                "status": "fail", "first_pass_valid": False,
                "repair_attempted": False, "error": str(error), "attempts": [],
            })
    benchmark = [] if args.skip_benchmark else run_benchmark(llama_bench, model)
    passed = sum(result["status"] == "pass" for result in generation)
    first_passed = sum(result["first_pass_valid"] for result in generation)
    repaired = sum(result["repair_attempted"] for result in generation)
    attempts = [attempt for result in generation for attempt in result["attempts"]]
    first_output = [
        attempt["cold_first_output_seconds"]
        for attempt in attempts
        if attempt.get("cold_first_output_seconds") is not None
    ]
    rates = [
        attempt["reported_tokens_per_second"]
        for attempt in attempts
        if attempt.get("reported_tokens_per_second") is not None
    ]
    grounded_quality = [
        result["quality"] for result in generation
        if result["purpose"] == "grounded" and result.get("quality")
    ]
    fallback_quality = [
        result["quality"] for result in generation
        if result["purpose"] == "incidentFallback" and result.get("quality")
    ]
    target_length = sum(item["target_length"] for item in grounded_quality)
    two_action = sum((item["action_coverage"] or 0) >= 2 for item in grounded_quality)
    warning = sum(item["warning_coverage"] is True for item in grounded_quality)
    leakage_count = sum(
        any(
            (marker if marker.isupper() else marker.lower())
            in (
                (result.get("response") or {}).get("a", "")
                if marker.isupper()
                else (result.get("response") or {}).get("a", "").lower()
            )
            for marker in LEAK_MARKERS
        )
        for result in generation
    )
    false_link_count = sum(
        result["purpose"] == "incidentFallback"
        and bool((result.get("response") or {}).get("e"))
        for result in generation
    )
    first_pass_rate = first_passed / len(cases) if cases else 0
    final_pass_rate = passed / len(cases) if cases else 0
    acceptance_passed = (
        first_pass_rate >= 0.80
        and final_pass_rate >= 0.95
        and leakage_count == 0
        and false_link_count == 0
    )
    report = {
        "schema_version": 2,
        "created_at": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "scope": "Native Gemma Lite contract evaluation; physical iPhone acceptance remains separate",
        "runtime": {
            "release": "b9637",
            "commit": "aedb2a5e9ca3d4064148bbb919e0ddc0c1b70ab3",
            "context_tokens": 2048,
            "maximum_output_tokens": 256,
        },
        "model": {
            "repository": "ggml-org/gemma-3-1b-it-GGUF",
            "revision": "f9c28bcd85737ffc5aef028638d3341d49869c27",
            "filename": model.name,
            "sha256": model_hash,
            "size_bytes": model.stat().st_size,
            "quantization": "Q4_K_M",
            "chat_template": "Embedded Gemma 3 tokenizer.chat_template",
        },
        "evaluation_contract": {
            "grounded_system_prompt_sha256": hashlib.sha256(GROUNDED_SYSTEM_PROMPT.encode()).hexdigest(),
            "incident_fallback_system_prompt_sha256": hashlib.sha256(INCIDENT_FALLBACK_SYSTEM_PROMPT.encode()).hexdigest(),
            "grammar_sha256": hashlib.sha256(GROUNDED_RESPONSE_GRAMMAR.encode()).hexdigest(),
            "single_evidence_grammar_sha256": hashlib.sha256(SINGLE_EVIDENCE_RESPONSE_GRAMMAR.encode()).hexdigest(),
            "unlinked_grammar_sha256": hashlib.sha256(UNLINKED_RESPONSE_GRAMMAR.encode()).hexdigest(),
            "case_ids": [case["id"] for case in cases],
        },
        "summary": {
            "total_cases": len(cases),
            "passed_cases": passed,
            "first_pass_valid_rate": round(first_pass_rate, 4),
            "valid_after_repair_rate": round(final_pass_rate, 4),
            "repair_rate": round(repaired / len(cases), 4) if cases else 0,
            "target_length_rate": round(target_length / len(grounded_quality), 4) if grounded_quality else None,
            "fallback_target_length_rate": round(
                sum(item["target_length"] for item in fallback_quality) / len(fallback_quality), 4
            ) if fallback_quality else None,
            "two_action_coverage_rate": round(two_action / len(grounded_quality), 4) if grounded_quality else None,
            "warning_coverage_rate": round(warning / len(grounded_quality), 4) if grounded_quality else None,
            "leakage_count": leakage_count,
            "false_link_count": false_link_count,
            "acceptance_passed": acceptance_passed,
            "median_cold_first_output_seconds": None if not first_output else round(statistics.median(first_output), 3),
            "median_generation_tokens_per_second": None if not rates else round(statistics.median(rates), 3),
        },
        "generation": generation,
        "benchmark": benchmark,
    }
    if args.output:
        output = args.output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Wrote {output}")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if acceptance_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
