# Clinical reevaluation public form (prepared, dormant)

`clinical-full-questionnaire.ts` projects the shared core descriptor and evaluates
the bounded choice vocabulary through the existing FULL evaluator. It does not
admit health risks, prepare or confirm writes, change targets, or consume photo
quota. The HTTP factory preserves patient authentication and entitlement, rejects
query parameters, bounds strict JSON to 16 KiB, and validates closed public output.
No `route.ts` or default runtime mounts these handlers yet.

## Public data

Describe accepts `kind`, `cycleId`, and `activityPurpose`. The server validates the
actual scope through the existing context RPC; asking for another kind does not
establish its calendar eligibility. Field presence/order/options come from the
shared descriptor. The presentation adds a closed input kind/unit, Portuguese or
English labels, nullable limits and explicit activity confirmation metadata.
The server also offers the applicable activity-purpose question branches;
unoffered branches are rejected. This menu does not establish clinical eligibility.
Unknown meal-day counts remain null. No private phase origin, generation, epoch,
context hash, health snapshot, photo asset IDs or private source hashes are sent.

The optional preference remains separate from `answers`. Opt-out remains null;
zero and false remain real answers. An activity level can be preselected but is
not confirmed until the patient explicitly confirms it. Selecting health risks in
a draft is not a declaration. Newly selected, unadmitted risks return
`health_declaration_required`, with no offered clinical action. Existing HOLDs
cannot be cleared by a skipped answer or by selecting "none" alone.

REGULAR always reports the requirement for three new photos, including a genuine
health-only assessment. Its display reading is either `photos_required` or an
official percentage with an opaque `candidate_id`. The server obtains that
reading from the actual three-photo proof. It does not accept the mean or raw
proof from a client. EARLY_FULL, ROUTINE_REVIEW and SAFETY use `not_required`.

Assess accepts the public draft: `activityPurpose`, `answers`, `preference`,
`measureConfirmed`, and nullable `bodyFat:{confirmed:true,candidateId}`. It never
advertises every schema choice as eligible: each offered action must pass the
actual clinical evaluator. Only its after-targets are projected, masked by that
candidate's actual safety policy. No before-targets are exposed. The response
contains n21 status/reason/missing feedback without persisting a refused value.

## Public command binding

`preparePublic` and `confirmPublic` accept the same draft plus `choice`. They bind
the current phase, genuine no-plan origin and photo proof on the server. A client
cannot supply `phase`, `noPlanOrigin`, a formula, mean, source hash or targets.
The public reading identity includes the actual owner, cycle, proof and mean;
replacement invalidates the previously accepted reading.

Original preparation and confirmation lookups precede current capture. Replays
bind against the original prepared command; reset, expiry or a later health risk
cannot turn an old acknowledgement into a fresh clinical application. Alias keys
can bind only the original receipt. The confirmation is historical evidence and
must be followed by fresh current-state readers for visible app state.

The service methods return **private prepared/result packets**. The public
`clinical-full-http.ts` factory projects only the original after-target display
and historical confirmation identity/calendar. Fresh public preparations store
an immutable sidecar in the same transaction, binding its server-evaluated policy
to the actual owner/preview/context/command/proposal. It contains display booleans,
not risk codes or numbers. The old private transport remains valid without it.

No before-targets are exposed. A proposed professional-diet clearance cannot
reveal previously hidden protein values. Existing old preparations cannot be
backfilled or inferred from concrete phase, nonnull targets, `clearHold`, a skipped
health answer, or current recapture. They project `historical_display_unavailable`.
A pending old preview without evidence cannot be newly confirmed publicly; an
already completed original/alias ACK still precedes all current capture.

The explicit health-declaration handler delegates to the existing idempotent
authority and returns only a historical receipt. Selecting a risk remains a draft
until that action. The native caller must refresh current policy afterwards.

## Native workflow and server-owned entry

`clinical-full-entry.ts` supplies GET and START factories. START accepts only
`reason:null|not_well_with_plan|gain_review_notice` and a stable operation key.
The backend-only SQL wrapper derives the requested kind and uses the server clock.
Its response projects the actual availability, civil calendar and occurrence,
without exposing signup generation. A new resume key with no early reason can
resume an existing EARLY occurrence; an occurrence due for regular review may be
promoted by SQL. The client consumes that returned scope, never inferring it from
the displayed date or fabricating a gain-review invitation.

Native `ClinicalFullQuestionnaire` and `ClinicalFullDraft` provide closed public
field/option types, explicit null/false/zero encoding, optional preference grammar,
activity reconfirmation, exclusive health answers, hidden-field filtering and
opaque reading acceptance invalidated by replacement. No native clinical formula
or mean is sent.

`MobileClinicalFullRepository` binds once to the shell's original Auth subject and
SessionLease, validates before/after requests and gates visible publication.
`ClinicalFullModel` retains each frozen draft, scope, choice, preview and key until
its result is reconciled. A lost connection or cancellation can have committed;
a subsequent input rejection does not silently discard that uncertain intent.
Session teardown prevents late publication or switching to a replacement session.
The original confirmation remains historical and refreshes current readers.

`ClinicalFullView` renders the descriptor, server-offered purposes/actions, explicit
health admission, official photo reading acceptance, preview and confirmation.
Raw invalid numbers remain visible in the shell-owned input state and prevent
assessment; they are never silently skipped or truncated. Integer zero and Boolean
false remain actual answers. Progresso exposes the optional capability independently
of its gamification snapshot. The shell refreshes Hoje, Plano, Progresso and Objetivo
after a confirmation or explicit health receipt and invalidates on teardown.

`AppDependencies.clinicalFull` defaults to nil. The recurring consent/capture/upload/
processing/disposition UI is not composed yet; missing photo capability must not
allow REGULAR completion. No default runtime or route is activated by this work.

## Qualification

Unit/HTTP tests cover exact public shapes, authentication/entitlement, body bounds,
opaque photo binding, explicit acceptance, unknown answers, activity reconfirmation,
new-risk admission boundaries, n21 refusal, age/HOLD masking and Portuguese/English.
The existing owned local SQL bridges now exercise the public command entry points
and questionnaire handlers with real core/service/RPC functions: REGULAR's three
synthetic processed photos, ROUTINE_REVIEW, health-only FULL, first-phase follow-up,
reset/risk replay, alias idempotency and cross-owner isolation. All data is rolled
back and the shared legal/config/audit catalogue preserved.
Entry/START now traverse the same actual owned SQL bridge. Native tests cover raw
input, returned EARLY scope, frozen retries, explicit risk admission and original
session isolation, alongside the first-phase/objective neighbors.

This proves local handlers/services/SQL, not deployed endpoints, a rendered native
form, real Supabase Storage, provider processing, retention or disposal. Default
consumers remain dormant until the entire clinical composition is qualified.
