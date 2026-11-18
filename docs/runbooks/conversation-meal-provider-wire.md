# Meal source labels: provider wire and canonical result

The meal interpreter still uses the configured Haiku model, source-owned tokens,
one durable interpretation permission and the existing canonical semantic
validator. Provider output never supplies a patient, quantity conversion,
nutritional authority, clinical policy or permission to save a meal.

The private provider response format represents an absent `food_index` or
`visual_index` as the integer `-1`. The prompt uses that same representation.
The decoder accepts only integer indices from -1 through 29, restores -1 to
canonical `null`, and leaves all other fields intact. The original closed Zod
schema and source validator then check the entire result. Unknown fields,
missing tokens, unsupported references and inconsistent quantities still fail.
Persisted interpretations and existing receipt readers retain canonical nulls.

Each source's private `labels` field is an ordered array of the same closed
label records, matching the server-provided token order exactly. The decoder
requires an existing source unit and exactly one label per original token,
then reconstructs the original token-keyed object before canonical parsing.
Missing/extra labels, invented units, invalid indices and unknown label fields
remain errors. An empty visual source must have an empty label array.

The provider schema shares one array-item grammar per source instead of
expanding one object grammar per token. Local references are resolved before
unused definitions are removed; the resulting grammar is independent of text
length for the same set of source units. Canonical source schemas, source
hashes, semantic validation, persisted interpretations and write permissions
remain unchanged. A previously unknown attempt is never retried under this
codec; connected qualification uses fresh synthetic command identities.

This representation avoids a nullable union for every token. Local JSON Schema
references are resolved from the server-generated schema before projection, so
lowering a nullable index cannot leave a dangling reference to its old `anyOf`.
External or cyclic references are refused. Existing unsupported numeric and
cardinality wire constraints remain enforced by the backend instead.

Anthropic documents a limit of 16 union-typed parameters and additional grammar
complexity limits. The source that failed connected qualification had 28 union
positions after reference expansion. Its private wire projection now has none.
That offline observation alone does not establish the subtype of a provider
error or prove connected success. See the official
[structured output limits](https://platform.claude.com/docs/en/build-with-claude/structured-outputs#schema-complexity-limits).

An existing unknown interpretation attempt remains immutable. A new deployment,
codec change or HTTP retry does not authorize another provider call for that
attempt. Qualification uses new synthetic commands and verifies the actual
provider, official saved receipt, technical repeat and readback before release.
No migration, key rotation or new provider service is required for this wire
change.

## Provider rejection observations

For HTTP 400 at the provider boundary, the interpreter can emit a closed
`provider_rejection` category: schema complexity, unsupported schema keyword,
invalid schema, unsupported structured output, or output token limit. It reads
only own data descriptors at the known SDK error locations, ignores strings
longer than 65,536 characters, and never emits the message, metadata, response
body, source text, headers, or credentials. Unknown errors retain the previous
stage/name/status observation. This observation neither retries a call nor
changes its durable result.

The R181 hosted meal attempt still received HTTP 400 after the wire projection.
The projection's offline grammar checks do not establish the cause of that
rejection or prove a successful registration. Qualify a new synthetic attempt;
never replay an interpretation whose provider outcome is already unknown.

When that category is unavailable, an SDK-shaped HTTP 400 can also emit a
closed `provider_error` projection: the upstream raw value's type, selected
published OpenRouter `error_type` values, a known provider enum, and a fixed
technical vocabulary. The projection reads only known data descriptors;
object-valued upstream errors are supported. Words retain no source ordering,
positions or frequencies, and arbitrary values, keys and provider names never
escape. Tests use actual OpenAI `BadRequestError` instances and reject getters,
prototype lookup names and secret-bearing messages. Unknown outcomes still
remain immutable; these observations do not retry or authorize a writer.
See [OpenRouter error formats](https://openrouter.ai/docs/api_reference/errors-and-debugging).
