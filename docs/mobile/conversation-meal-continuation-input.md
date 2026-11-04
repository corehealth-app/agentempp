# Linked meal clarification input boundary

`conversation-meal-continuation-input.ts` qualifies reply intent and the server's
question. It does not admit commands, derive a question key, interpret text,
calculate nutrition, resolve the current parent, authenticate an owner, or write
records. A later service must prove the actual Auth owner, epoch, immutable
parent decision, current question/head and authorized source before any effect.

The exact closed `conversation.meal-clarification.v1` body contains
`expected_revision`, opaque `question_key`, and one answer: quantity with its
original food occurrence index, positive finite amount up to 9,999 and literal
unit, or one of the existing six meal types. Binding retains a separate parent
command/input hash, decision hash, epoch, owner and stable reply UUID. The only
accepted idempotency key is `cmreply1:<reply UUID>`. Parsing freezes a detached
copy; it rejects getters, non-JSON values, undefined, foreign fields and invalid
Unicode without reading a getter or silently stripping data.

The reply's body-only SHA-256 uses `conversationOperationCanonicalJson`, the
existing qualified edit strategy: sorted ASCII DTO keys and decimal expansion
of the exact digits that JSON serializes. It is distinct from original v1 meal
command hashing. Opaque parent/question/decision hashes are preserved and never
recomputed from an invented parent. Retrying after an unknown outcome must keep
the original reply UUID and exact original wire bytes; this module does not
provide persistence, retry permission or a network client.

A `conversation.meal-question.v1` quantity question preserves the full original
food name (at most 160 UTF-16 units), occurrence index, revision and opaque key.
Names are not trimmed, truncated or rewritten. The ordered unit allowlist and
reference must exactly match the current whole-name `mobileQuantityDisplay`
lookup: `g`, `kg`, then `mL`, `L` for approved liquids or `unit`/`scoop` for the
approved portion reference. `caneca` follows only the approved whole-milk
reference. Unknown names, powders, brands and mixtures receive no inferred
reference. A meal-type question requires null target/name/reference and no
units. Reply validation compares revision, key, kind, target and allowed unit;
it performs no amount-to-grams conversion or revision rebasing.

Compact reply JSON has a first wire bound of 16,384 UTF-8 bytes. The later SQL
`jsonb::text` bound and all source/conversion constraints remain authoritative;
an amount such as 9,999 kg can be syntactically valid here and still be refused
by the real preparation boundary. Successful parsing is not registration proof.

The versioned private contract is
`T3-LINKED-CLARIFICATION-PREPARATION/CONTRACT.json` in the task evidence directory,
including its explicit 160 UTF-16 question-name amendment. This additive leaf
provides no routes, feature activation, model calls, migrations or deployment.
