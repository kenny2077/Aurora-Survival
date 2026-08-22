#ifndef TRAILGUARD_GROUNDED_RESPONSE_GRAMMAR_H
#define TRAILGUARD_GROUNDED_RESPONSE_GRAMMAR_H

// Compact answer envelope for the 160-token Lite budget. Swift displays the
// answer verbatim and uses validated evidence indexes only for manual links.
inline constexpr char kGroundedResponseGrammar[] = R"GBNF(
sentence-char ::= [^"\\\[\]*{}.!?\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
sentence ::= sentence-char{25,219} [.!?]
answer-string ::= "\"" sentence " " sentence "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
index ::= ("1" | "2") space
indexes ::= "[" space (index ("," space index)?)? "]" space
evidence-kv ::= "\"e\"" space ":" space indexes
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kSingleEvidenceResponseGrammar[] = R"GBNF(
sentence-char ::= [^"\\\[\]*{}.!?\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
sentence ::= sentence-char{25,219} [.!?]
answer-string ::= "\"" sentence " " sentence "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "1" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kUnlinkedResponseGrammar[] = R"GBNF(
sentence-char ::= [^"\\\[\]*{}.!?\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
sentence ::= sentence-char{20,219} [.!?]
answer-string ::= "\"" sentence (" " sentence){0,2} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

// Expert grounded answers must finish naturally instead of reaching the
// generic character ceiling. Encoding the 2–5 sentence contract here also
// prevents a malformed or truncated answer from reaching Swift validation.
inline constexpr char kExpertGroundedResponseGrammar[] = R"GBNF(
sentence-char ::= [^"\\.!?\x00-\x1F] | "\\" (["\\/bf] | "u" [0-9a-fA-F]{4})
sentence ::= [A-Za-z] sentence-char{14,219} [.!?]
index ::= ([1-9] | [1-2] [0-9] | "30") space
indexes ::= "[" space index ("," space index){0,2} "]" space
sentence-object ::= "{" space "\"a\"" space ":" space "\"" sentence "\"" space "," space "\"e\"" space ":" space indexes "}" space
root ::= "{" space "\"s\"" space ":" space "[" space sentence-object "," space sentence-object ("," space sentence-object){0,3} "]" space "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kExpertSingleEvidenceResponseGrammar[] = R"GBNF(
sentence-char ::= [^"\\.!?\x00-\x1F] | "\\" (["\\/bf] | "u" [0-9a-fA-F]{4})
sentence ::= [A-Za-z] sentence-char{14,219} [.!?]
indexes ::= "[" space "1" space "]" space
sentence-object ::= "{" space "\"a\"" space ":" space "\"" sentence "\"" space "," space "\"e\"" space ":" space indexes "}" space
root ::= "{" space "\"s\"" space ":" space "[" space sentence-object "," space sentence-object ("," space sentence-object){0,3} "]" space "}" space
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
sentence-char ::= [^"\\.!?\x00-\x1F] | "\\" (["\\/bf] | "u" [0-9a-fA-F]{4})
precaution ::= [A-Za-z] sentence-char{74,279} "."
question ::= [A-Za-z] sentence-char{54,219} "?"
answer-string ::= "\"" precaution " " question "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kExpertIntentDecisionGrammar[] = R"GBNF(
root ::= "{" space "\"t\"" space ":" space "\"" ("general" | "survival") "\"" space "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

#endif
