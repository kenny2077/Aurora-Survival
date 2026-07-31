#ifndef TRAILGUARD_GROUNDED_RESPONSE_GRAMMAR_H
#define TRAILGUARD_GROUNDED_RESPONSE_GRAMMAR_H

// Generated from Schemas/grounded-response.schema.json by llama.cpp b9637
// examples/json_schema_to_grammar.py with the response field order.
inline constexpr char kGroundedResponseGrammar[] = R"GBNF(
answer-confidence ::= ("\"insufficient\"" | "\"limited\"" | "\"supported\"") space
answer-confidence-kv ::= "\"answer_confidence\"" space ":" space answer-confidence
char ::= [^"\\\x7F\x00-\x1F] | [\\] (["\\bfnrt] | "u" [0-9a-fA-F]{4})
decimal-part ::= [0-9]{1,16}
do-not-do ::= "[" space  "]" space
do-not-do-kv ::= "\"do_not_do\"" space ":" space do-not-do
domain ::= ("\"vehicle\"" | "\"wilderness\"" | "\"first_aid\"" | "\"navigation\"") space
domain-kv ::= "\"domain\"" space ":" space domain
driveability ::= ("\"do_not_drive\"" | "\"unknown\"" | "\"conditional\"" | "\"not_applicable\"") space
driveability-kv ::= "\"driveability\"" space ":" space driveability
escalation ::= "{" space escalation-reason-kv "," space escalation-action-kv "}" space
escalation-action-kv ::= "\"action\"" space ":" space string
escalation-kv ::= "\"escalation\"" space ":" space escalation
escalation-reason-kv ::= "\"reason\"" space ":" space string
immediate-action ::= "{" space immediate-action-kind-kv "," space immediate-action-evidence-ids-kv "}" space
immediate-action-evidence-ids ::= "[" space (string ("," space string)*)? "]" space
immediate-action-evidence-ids-kv ::= "\"evidence_ids\"" space ":" space immediate-action-evidence-ids
immediate-action-kind ::= ("\"stop\"" | "\"move\"" | "\"sos\"" | "\"assess\"" | "\"continue\"") space
immediate-action-kind-kv ::= "\"kind\"" space ":" space immediate-action-kind
immediate-action-kv ::= "\"immediate_action\"" space ":" space immediate-action
integral-part ::= [0] | [1-9] [0-9]{0,15}
null ::= "null" space
number ::= ("-"? integral-part) ("." decimal-part)? ([eE] [-+]? integral-part)? space
observations ::= "[" space  "]" space
observations-item ::= "{" space observations-item-fact-kv "," space observations-item-source-kv "," space observations-item-confidence-kv "}" space
observations-item-confidence-kv ::= "\"confidence\"" space ":" space number
observations-item-fact-kv ::= "\"fact\"" space ":" space string
observations-item-source ::= ("\"user\"" | "\"photo\"" | "\"obd\"" | "\"sensor\"") space
observations-item-source-kv ::= "\"source\"" space ":" space observations-item-source
observations-kv ::= "\"observations\"" space ":" space observations
procedure-id ::= string | null
procedure-id-kv ::= "\"procedure_id\"" space ":" space procedure-id
questions ::= "[" space  "]" space
questions-item ::= "{" space questions-item-id-kv "," space questions-item-text-kv "," space questions-item-why-kv "}" space
questions-item-id-kv ::= "\"id\"" space ":" space string
questions-item-text-kv ::= "\"text\"" space ":" space string
questions-item-why-kv ::= "\"why\"" space ":" space string
questions-kv ::= "\"questions\"" space ":" space questions
risk-level ::= ("\"critical\"" | "\"high\"" | "\"moderate\"" | "\"low\"") space
risk-level-kv ::= "\"risk_level\"" space ":" space risk-level
root ::= "{" space domain-kv "," space risk-level-kv "," space immediate-action-kv "," space questions-kv "," space observations-kv "," space procedure-id-kv "," space steps-kv "," space do-not-do-kv "," space driveability-kv "," space escalation-kv "," space answer-confidence-kv "}" space
space ::= | " " | "\n"{1,2} [ \t]{0,20}
steps ::= "[" space  "]" space
steps-item ::= "{" space steps-item-step-id-kv "," space steps-item-evidence-ids-kv "}" space
steps-item-evidence-ids ::= "[" space string ("," space string)* "]" space
steps-item-evidence-ids-kv ::= "\"evidence_ids\"" space ":" space steps-item-evidence-ids
steps-item-step-id-kv ::= "\"step_id\"" space ":" space string
steps-kv ::= "\"steps\"" space ":" space steps
string ::= "\"" char* "\"" space
)GBNF";

#endif
