# New-command clinical daily initialization

`createConversationMealDayInitializer(db).initialize(auth, boundCommand)` is an
inert, private composition of the existing clinical services. It installs no
route, flag or capability. The registration caller must first recover prepared
state, skip initialization if source/resolved/effect already exists, and admit a
new command before calling this helper. Initialization precedes the first meal
source capture; it is never a GET/status/replay effect.

Each invocation validates and detaches authenticated identity and the full bound
command/hash before I/O. It creates a request-local
`createCurrentClinicalAdmission(createSupabaseLegacyClinicalAdmissionSource(db))`
and real `createCurrentClinicalReadModel`, then calls only `preflight` with the
fixed backend `current_clinical_v1` representation. No numeric `today` reader is
called. Neither a caller URL/clock nor a requested operation key is accepted.

The returned private server snapshot is detached and validated again against the
owner. Its clinical civil date, authenticated owner and command UUID form a
UUIDv5 name under the server namespace
`UUIDv5(DNS, "performe.ai/conversation.meal.daily.v1")`. The namespace UUID is
`de8c8ce6-0dd4-5802-8ee3-77fc10fbebe8`; the name is
`<owner>/<command>/<server-clinical-date>`. Concurrent calls for that identity
therefore use the same existing daily receipt key. Different commands or server
dates use distinct names. Observed-at clocks, client dates and random nonces are
not inputs. This adds no schema or persistent nonce.

The helper then calls the real `createClinicalDailyEffect` with that key callback.
The existing daily service owns receipt-first replay, official calculation,
APPLICATION capture from the SQL clock and locked CAS. Current server day/source
checks remain in the existing daily and meal SQL protocols. This helper supplies
no targets, country, body values, clinical source or fallback formula.

Existing behavior stays with the reused effect: confirmed no-plan and unassigned
legacy phases skip target application; assigned HOLD reaches the safety path;
known unavailable/preserved reasons remain preserved. Profile/body/context errors
keep their closed clinical error codes. Unexpected callback failures are
redacted. The helper never calls closeDays, rewards, workout lifecycle, food
registration, meal source capture or an interpreter/provider.

Optional `ConversationMealDayPorts` replace only the read-model and daily-effect
factories for controlled tests or explicit trusted backend composition. Factory
callbacks are captured on construction; each request captures its model method,
auth/command and returned observation before another asynchronous boundary.
These ports and clinical observations are not public HTTP inputs or authorities
that a mobile client may supply.

Tests use real preflight/legacy admission and real daily effect/service/repository
defaults over a controlled RPC transport, including eligible calculation, HOLD,
unknown old formula preservation and receipt replay. Other tests cover the
independently derived UUIDv5 value, concurrent identity stability, source/date
separation, invalid bindings, errors and callback/input mutation. Actual
PostgreSQL/SDK qualification and registration-driver activation remain integration
gates; this helper alone is not the complete meal-report flow.
