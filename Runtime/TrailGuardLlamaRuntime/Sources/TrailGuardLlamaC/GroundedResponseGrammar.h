#ifndef TRAILGUARD_GROUNDED_RESPONSE_GRAMMAR_H
#define TRAILGUARD_GROUNDED_RESPONSE_GRAMMAR_H

// Compact answer envelope for the 160-token Lite budget. Swift displays the
// answer verbatim and uses validated evidence indexes only for manual links.
inline constexpr char kGroundedResponseGrammar[] = R"GBNF(
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" char{135,440} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
index ::= ("1" | "2") space
indexes ::= "[" space (index ("," space index)?)? "]" space
evidence-kv ::= "\"e\"" space ":" space indexes
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kSingleEvidenceResponseGrammar[] = R"GBNF(
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" char{135,440} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "1" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

inline constexpr char kUnlinkedResponseGrammar[] = R"GBNF(
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" char{120,440} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
evidence-kv ::= "\"e\"" space ":" space "[" space "]" space
root ::= "{" space answer-kv "," space evidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

#endif
