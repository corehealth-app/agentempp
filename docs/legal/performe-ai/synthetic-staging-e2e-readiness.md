# Performe AI — Synthetic Staging E2E Readiness

STATUS: TECHNICAL QA READINESS DRAFT
LEGAL APPROVAL: NOT OBTAINED
PUBLISHED: NO
STAGING ACTIVE: NO
PRODUCTION ACTIVE: NO
E2E EXECUTED: NO

## Objective and boundary

Prepare a future, separately authorized staging E2E that proves the technical server-owned onboarding and Flow journey using synthetic data only. This readiness document does not create or activate documents, users, credentials, migrations, deployments, requirement sets, provider keys, or remote resources.

`REAL USER LEGAL ACTIVATION: BLOCKED`

The future QA run is not legal review, legal publication, consent by a real person, UAT, production clearance, or evidence that the product may process real personal data.

## Synthetic document contract

The current runtime accepts keys matching `^[a-z][a-z0-9_]{0,99}$`, rejects `dev_*`, accepts locales `pt-BR` and `en-US`, and accepts only `acceptance`, `acknowledgement`, or `consent`. The future isolated staging dataset should use:

| Synthetic key | Version | Locale pair | Action | Purpose |
| --- | --- | --- | --- | --- |
| `qa_terms_notice` | `qa-e2e-v1` | `pt-BR` / `en-US` | `acceptance` | `qa_onboarding_terms_notice` |
| `qa_privacy_notice` | `qa-e2e-v1` | `pt-BR` / `en-US` | `acknowledgement` | `qa_onboarding_privacy_notice` |
| `qa_health_ai_notice` | `qa-e2e-v1` | `pt-BR` / `en-US` | `acknowledgement` | `qa_onboarding_health_ai_notice` |
| `qa_sensitive_data_consent` | `qa-e2e-v1` | `pt-BR` / `en-US` | `consent` | `qa_onboarding_sensitive_data_consent` |

These identifiers are technically compatible proposals for the future QA execution, not current rows or legal keys. Do not use `legal_*`, a real Privacy/Terms identity, version `1.0.0`, the legal draft bodies, or `dev_*` fixtures.

Every pt-BR body must begin with:

> DOCUMENTO SINTÉTICO DE QA — NÃO É TERMO DE USO OU POLÍTICA JURÍDICA.

Every en-US body must begin with:

> SYNTHETIC QA DOCUMENT — THIS IS NOT A TERM OF USE OR LEGAL POLICY.

Any additional text must remain synthetic, non-normative, and limited to identifying the action under test. Each body must stay under 12,000 UTF-8 bytes; the verified-document collection must stay under 48,000 serialized UTF-8 bytes; and the complete public onboarding state must stay under 60,000 serialized UTF-8 bytes.

The schema requires `publication_status = 'published'` for a selectable row. In this QA context, that value would mean only **technically available inside the exact authorized staging environment**. It must never be represented as legal publication, approval, effectiveness, or production eligibility.

## Mandatory fail-closed environment gate

Before any future write, the execution mandate must identify and independently verify:

- the exact authorized Supabase staging project reference;
- the exact Vercel BFF Preview deployment and project identity;
- explicit proof that neither target is production;
- the exact migration state required by the server-owned onboarding;
- an insertion method scoped only to that verified staging target;
- a production exclusion that prevents `qa_*` documents and QA requirement sets from being seeded, copied, promoted, or selected in production.

If target identity, environment classification, production exclusion, migration state, or rollback/closeout evidence is missing, stop before the first write. Repository names, branch names, aliases, browser visibility, or a successful HTTP response are not sufficient proof.

Because onboarding documents and requirement sets are immutable in the current schema, the future plan must decide before insertion whether staging QA rows remain as explicitly owned synthetic evidence or require a separately reviewed cleanup mechanism. Do not claim deletion where the current immutable triggers prevent it, and do not alter those triggers merely to simplify QA.

## Synthetic users and test data

- Create exactly two new task-owned synthetic accounts, referenced as `QA_USER_A` and `QA_USER_B`.
- Use only approved QA mailbox aliases created for that run; never personal emails, real names, existing patients, or existing accounts.
- Start with no pre-existing messages or patient records.
- Use fabricated, non-identifying onboarding and health-like values that cannot be mistaken for a real person.
- Do not import, copy, sample, or infer production data.
- Keep all generated Flow conversation content synthetic and exclude it from ordinary logs and reports.

## Future authorized journey

The future E2E must prove, in order:

1. `QA_USER_A` login and confirmed isolated session.
2. Server-owned onboarding requirements with exact QA keys, versions, locales, hashes, purposes, and action types.
3. Explicit unchecked actions and atomic server acknowledgement of completion.
4. Transition to Hoje.
5. Flow request and provider response within the authorized completion budget.
6. Persisted message and history after reload/revisit.
7. Logout and synchronous removal of user-scoped client state.
8. `QA_USER_B` login, onboarding, Flow journey, and history.
9. Proof that A cannot read or affect B and B cannot read or affect A.
10. Clean logout, evidence capture, provider-key revocation, and environment/data closeout classification.

No step may use a production service, real patient, pre-existing conversation, outbound campaign, push, billing, media upload, or medication action.

## OpenRouter budget gate for the future run

Do not create a key during this task. A later explicit authorization must create a new exclusive key with:

- total limit: US$5;
- renewal: disabled;
- expiry: no more than 24 hours;
- maximum: 8 completions;
- soft stop: US$3;
- hard stop: US$5;
- model: only the model named by the then-current mandate;
- reuse of any prior key: prohibited;
- closeout: revocation required and verified.

Stop before a provider call if any cap, expiry, model restriction, counter, observability control, or revocation path is not enforceable.

## Apple and distribution boundary

The intended future entity is only a candidate to become the owner/seller after incorporation and formal decisions. Do not create an App Store listing or contract under PIPER/PiperHub or CoreHealth for convenience. Do not change bundle ID, signing, or entitlements. Signing and TestFlight remain separate gates, and no future transfer of an app or account may be treated as trivial.

## Readiness and authorization gates

- Documentary synthetic dataset: PREPARED.
- Contract compatibility: PREPARED against the current local schema and API contract.
- Exact staging identities: MUST BE REVERIFIED in the future execution mandate.
- Synthetic account/mailbox provisioning: NOT EXECUTED.
- Staging migration/document/requirement-set activation: NOT EXECUTED.
- BFF Preview deployment: NOT EXECUTED by this task.
- OpenRouter key and calls: NOT CREATED / NOT EXECUTED.
- E2E: NOT EXECUTED.
- Production: BLOCKED and OUT OF SCOPE.

The next operation must authorize the exact staging targets, synthetic setup, bounded provider key, E2E execution, evidence collection, and closeout. It must stop after the synthetic run and must not infer legal or production readiness from technical success.
