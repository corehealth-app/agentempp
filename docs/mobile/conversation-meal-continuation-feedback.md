# Original feedback for a saved clarification child

`createSupabaseConversationMealContinuationFeedback` handles the actual
`conversation.meal-continuation-effect.v1` receipt and its real original-parent
and clarification-child bindings. It does not construct a v1 report for the
child, substitute the parent's effect, rename a provider key or invent a server
observation. The closed binding keeps all actual opaque hashes and clocks.

The constructor is inert. Its required `checkCurrentScope` callback comes from
the authenticated request/session owner, is pinned before asynchronous work and
must return strictly true. A detached Auth/patient/epoch/binding snapshot is
checked around I/O; revocation withholds data and stops further work. A parsed
binding is historical evidence, never Auth or write authority.

The existing SQL functions already locate a child by its real registry ID and
epoch, and the original child commit already captures its immutable feedback
context. This adapter uses those existing functions without changing their SQL,
grants, tables or old v1 callers:

- `readOriginal` performs one receipt-only read.
- `ensureOriginal` first reads the original winner. Only definite absence permits
  reading the frozen source and attempting one optional feedback seal. Context,
  protocol, actual child receipt, provider, logs and microsecond clocks must
  agree. There is no live source recapture. A lost or malformed seal response
  permits one receipt-only reconciliation, without another seal or factual write.
- `readHistorical` reads the original under before/after profile-only current
  clinical observations. Epoch, observation clocks and policy binding must stay
  consistent. The current observation cannot precede the saved consumption.
  This path never creates feedback, calculates nutrition, initializes a day or
  calls a model or domain writer.

V2 enrichment reuses the existing six-section builder and official-day proof.
The original source must prove the actual registration, item IDs, quantities,
totals and official context. Day/block data are withheld if their optional
proof is unavailable; missing targets never become percentages or zero-valued
targets. Exercise does not increase the food budget and a message does not
credit the consolidated block. The existing reviewed educational selection is
used without asserting preferences not present in the captured evidence.

An existing v1 winner remains v1. Historical presentation reuses the current
clinical visibility mask and rendering already used for original v1 commands;
it does not rewrite sealed facts. Under protection, old targets, block and unsafe
guidance are hidden. Original facts remain separate from the current editable
group, later Save/Undo operations and refreshed panels.

Optional feedback failure returns null while preserving the already-saved food.
Reading or rendering the original never admits a command, retries consumption,
creates a reward or removes a pending client operation. Public GET may consume
the read-only historical presentation; it must not call `ensureOriginal`.

Current evidence: synthetic unit and neighboring decoder/service tests cover the
six sections, actual child versus parent identities, first-winner replay, lost
seal response, revoked scope, source mismatch, microsecond differences and
current clinical protection. A separate local round also exercised real GoTrue
authentication, the default shared calculator and writer, and these adapters
through the actual Supabase SDK, PostgREST and SQL functions. It saved one food
and one fulfillment, recovered lost factual-commit and feedback-seal responses
by reading, and returned the six-section presentation without repeating either
write. The original semantic/model result was controlled, with no provider call.
The QA profile was incomplete, so day targets and the consolidated block were
correctly unavailable. This round does not qualify complete-profile targets,
public BFF HTTP, native connected integration, latency or distributed acceptance.
