# Workout report SQL parity

New workout preparations use an independent SQL grammar matching the existing TypeScript resolver: natural performed verbs, minute/hour durations, duration before/after the activity and explicit intensity. Catalogue matching remains unique and captured. Missing values stay questions; negations, future, habits, third parties, mixed activities and conflicting source units remain non-ready. No intensity, weight or calorie default is introduced.

T44 caption, context and transcript are separate original evidence. The new private units helper preserves that reconstruction; equipment pixels alone do not prove performed exercise. Public command, preparation, receipt, source and read shapes are unchanged.

Normalization retains the TypeScript diacritic/whitespace policy without `unaccent` transliteration aliases. Native PostgreSQL case/NFD behavior is not claimed to cover every Unicode version: exploratory differences outside the observed PT/EN catalogue are retained separately and actual captured pairs must remain non-ready. No nonportable ICU collation or global Unicode compatibility engine is installed.

`private.conversation_workout_preparations.report_version` is private immutable storage metadata. Existing rows and the constant default are version1; trusted SQL prepare explicitly stores version2 for a new preparation. Callers do not select a version. Replay first selects the persisted version, and commit proves the stored preparation using its matching independent guard under the existing locks. The old `conversation_workout_report` function remains literal. Old pending statements are not reinterpreted as ready, and saved receipt replay does not recalculate from a changed body/day.

The migration pins predecessor bodies and modifies only the prepare version/insert hooks and commit proof call. Existing source/day/epoch/catalogue checks, quota, strength facts, formulas, feedback context, XP, energy block and food budget remain unchanged. Private helpers are inaccessible to public/authenticated/service roles; the existing public RPC signatures and grants remain unchanged.

Local qualification uses actual admitted/captured sources and SQL prepare/commit/read/replay in rollback-only PostgreSQL, including before-upgrade legacy rows. Recorded real-PG goldens verify TypeScript agreement. These checks do not establish deployment, connected HTTP/native QA, durable workout clarification replies or completion of the full conversational scope.
