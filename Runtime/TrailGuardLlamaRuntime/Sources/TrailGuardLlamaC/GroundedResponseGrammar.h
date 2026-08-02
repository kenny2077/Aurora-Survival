#ifndef TRAILGUARD_GROUNDED_RESPONSE_GRAMMAR_H
#define TRAILGUARD_GROUNDED_RESPONSE_GRAMMAR_H

// Bounded conversational decision grammar for the 128-token Lite budget. The
// Swift codec validates evidence indexes and deterministically appends any
// selected reviewed procedure, warnings, and source metadata.
inline constexpr char kGroundedResponseGrammar[] = R"GBNF(
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
answer-string ::= "\"" char{1,220} "\"" space
follow-up-string ::= "\"" char{1,96} "\"" space
answer-kv ::= "\"a\"" space ":" space answer-string
index ::= ("1" | "2") space
indexes ::= "[" space (index ("," space index)?)? "]" space
evidence-kv ::= "\"e\"" space ":" space indexes
null ::= "null" space
procedure ::= index | null
procedure-kv ::= "\"p\"" space ":" space procedure
follow-up ::= follow-up-string | null
follow-up-kv ::= "\"q\"" space ":" space follow-up
root ::= "{" space answer-kv "," space evidence-kv "," space procedure-kv "," space follow-up-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
)GBNF";

#endif
