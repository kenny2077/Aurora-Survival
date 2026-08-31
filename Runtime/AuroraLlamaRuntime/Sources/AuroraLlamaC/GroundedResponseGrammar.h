#ifndef AURORA_GROUNDED_RESPONSE_GRAMMAR_H
#define AURORA_GROUNDED_RESPONSE_GRAMMAR_H

// Compact answer envelope for the 256-token Lite budget. Swift displays the
// answer verbatim and uses validated evidence indexes only for manual links.
inline constexpr char kGroundedResponseGrammar[] = R"GBNF(
answer-char ::= [^"\\\[\]*{}\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" answer-char{20,700} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
index ::= ("1" | "2") space
indexes ::= "[" space (index ("," space index)?)? "]" space
evidence-kv ::= "\"e\"" space ":" space indexes
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kSingleEvidenceResponseGrammar[] = R"GBNF(
answer-char ::= [^"\\\[\]*{}\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" answer-char{20,700} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "1" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kUnlinkedResponseGrammar[] = R"GBNF(
answer-char ::= [^"\\\[\]*{}\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" answer-char{20,700} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

// Expert and Lite share the compact answer-plus-scenario citation envelope.
inline constexpr char kExpertGroundedResponseGrammar[] = R"GBNF(
answer-char ::= [^"\\\[\]*{}\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" answer-char{20,700} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
index ::= ("1" | "2" | "3") space
indexes ::= "[" space index ("," space index){0,2} "]" space
evidence-kv ::= "\"e\"" space ":" space indexes
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kExpertSingleEvidenceResponseGrammar[] = R"GBNF(
answer-char ::= [^"\\\[\]*{}\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" answer-char{20,700} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "1" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kExpertUnlinkedResponseGrammar[] = R"GBNF(
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" char{20,600} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kExpertClarificationResponseGrammar[] = R"GBNF(
sentence-char ::= [^"\\.!?。！？\x00-\x1F] | "\\" (["\\/bf] | "u" [0-9a-fA-F]{4})
precaution ::= sentence-char{75,280} ("." | "。")
question ::= sentence-char{55,220} ("?" | "？")
answer-string ::= "\"" precaution " " question "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kExpertIntentDecisionGrammar[] = R"GBNF(
query-char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
root ::= "{" space "\"t\"" space ":" space "\"" ("general" | "survival") "\"" space "," space "\"q\"" space ":" space "\"" query-char{0,160} "\"" space "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

#endif
