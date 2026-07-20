# BodyFlow Personalities, Messages, and Mascot State Design

**Date:** 2026-07-20

**Status:** Approved for implementation planning

**Workpack:** Prompt 07 - Personalidades Focus/Impulse/Zen, mensagens prontas e mascote BodyFlow

## 1. Objective

Build the app-first backend and admin domain that lets a patient select how the BodyFlow coach communicates, renders recurring messages from a safe bilingual catalog, rotates variants without calling an LLM at runtime, and exposes a non-visual mascot state for future product phases.

The selectable personalities are:

- `focus`: direct, firm, objective, and disciplined, never hostile;
- `impulse`: energetic, positive, and motivating, never infantilizing;
- `zen`: calm, didactic, welcoming, and rational.

`balanced` is an internal deterministic fallback. It is not shown as a fourth patient option.

## 2. Scope

This phase includes:

- patient personality preference;
- a versioned message catalog;
- `pt-BR` and `en-US` content;
- `in_app`, `push`, and `email` renditions;
- three variants for every supported combination;
- safe variable interpolation;
- per-context frequency policies;
- deterministic least-recently-used selection;
- monthly editorial packs with human approval and rollback;
- a master-admin message management module;
- a persisted mascot state and audit history;
- mobile API support for reading and changing personality;
- usage, fallback, suppression, and activation telemetry.

This phase does not include:

- sending email;
- APNs credentials or production push delivery;
- runtime LLM generation for recurring patient messages;
- visual mascot assets, animation, or SwiftUI;
- automatic mascot transitions based on guessed engagement thresholds;
- rewriting historical messages;
- production deployment or production database changes without a separate authorization.

## 3. Catalog Coverage

The supported contexts are:

1. `onboarding`
2. `meal_pending`
3. `registration_confirmed`
4. `error_corrected`
5. `hydration`
6. `supplement`
7. `medication`
8. `workout`
9. `progress`
10. `day_incomplete`
11. `reevaluation`
12. `reengagement`
13. `trial`
14. `paywall`
15. `return_after_abandonment`

The initial baseline pack contains:

```text
4 tones x 15 contexts x 3 channels x 2 locales x 3 variants = 1,080 renditions
```

All 1,080 baseline renditions must pass coverage and content linting before the pack can become active. An active email rendition is catalog-ready but is not deliverable while email delivery remains disabled.

## 4. Data Model

Use constrained text columns rather than PostgreSQL enum types so future additions remain additive and migration-friendly. Every table in the exposed `public` schema has RLS enabled and explicit grants.

### 4.1 `coach_personalities`

Stable personality definitions:

- `code` primary key: `balanced`, `focus`, `impulse`, or `zen`;
- localized display name and short description;
- `selectable` boolean (`false` for `balanced`);
- `active` boolean;
- timestamps.

The personality definitions are product configuration, not user-authored copy.

### 4.2 `user_coach_preferences`

One row per domain user:

- `user_id` primary key and foreign key to `users`;
- `personality_code` foreign key;
- `selected_at`;
- `created_at` and `updated_at`.

No row means `balanced`. A new app-first account is not forced to store a choice before onboarding reaches personality selection.

### 4.3 `coach_message_context_policies`

One policy per context and channel:

- `context`;
- `channel`;
- `cooldown_seconds`;
- nullable `max_per_local_day`;
- `delivery_enabled`;
- `refresh_cadence`: `monthly` or `quarterly`;
- timestamps.

The initial policy is conservative:

| Context | Push policy | In-app policy | Refresh |
|---|---|---|---|
| onboarding | idempotent per onboarding step | idempotent per step | quarterly |
| meal_pending | max 2/day, 4h cooldown | idempotent per pending event | monthly |
| registration_confirmed | idempotent per registration | idempotent per registration | monthly |
| error_corrected | idempotent per correction | idempotent per correction | monthly |
| hydration | max 3/day, 2h cooldown | idempotent per hydration event | monthly |
| supplement | idempotent per scheduled item | idempotent per item event | monthly |
| medication | idempotent per scheduled item | idempotent per item event | monthly |
| workout | max 1/day unless event-confirmation | idempotent per workout | monthly |
| progress | max 1/day | max 1/day | monthly |
| day_incomplete | max 1/day | max 1/day | monthly |
| reevaluation | max 1/day | max 1/day | quarterly |
| reengagement | max 1 per 72h | max 1 per 72h | monthly |
| trial | max 1/day | max 1/day | quarterly |
| paywall | max 1/day | max 1/day | quarterly |
| return_after_abandonment | max 1 per 7 days | idempotent per return event | quarterly |

Email delivery is disabled for every context in this phase even though its renditions are complete. The existing global patient push limit remains an additional upper bound.

### 4.4 `coach_content_packs`

An editorial release unit:

- immutable `slug`;
- localized name or operational label;
- `status`: `draft`, `scheduled`, `active`, or `archived`;
- optional parent pack;
- `effective_at`, `activated_at`, and `archived_at`;
- creator, approver, and activation audit metadata;
- timestamps.

Only one pack may be active. Activation uses a transaction and advisory lock. A scheduled pack that has not passed validation cannot activate.

### 4.5 `coach_message_templates`

Stable logical identities independent of wording:

- stable `template_key`;
- personality;
- context;
- channel;
- locale;
- variant number `1..3`;
- allowed and required variable names;
- timestamps.

The tuple `(personality, context, channel, locale, variant)` is unique.

### 4.6 `coach_message_template_versions`

Immutable copy revisions:

- template identity;
- monotonically increasing version;
- optional push title or email subject;
- plain-text body;
- `status`: `draft`, `active`, or `archived`;
- provenance: `seed`, `human`, or `assisted_draft`;
- author and approval metadata;
- content hash;
- timestamps.

Every inserted version is immutable. Editing creates a new draft version and
archives the superseded draft when appropriate. Active text is never updated
in place.

### 4.7 `coach_content_pack_entries`

Maps every logical template in a pack to one immutable version. Draft packs start as a copy of the active mapping and only changed entries point to new versions. This supports monthly partial refreshes without duplicating unchanged text while preserving a complete 1,080-entry release snapshot.

Activation validates that the resolved pack has exactly one eligible version for every required combination.

### 4.8 `coach_message_usage`

Append-only selection telemetry:

- domain user ID;
- selected template version and pack;
- context, channel, locale, and effective personality;
- requested personality;
- outcome: `selected`, `suppressed`, or `failed`;
- reason, such as `exact`, `balanced_fallback`, `cooldown`, `daily_limit`, `missing_variables`, or `catalog_incomplete`;
- optional event idempotency key hash;
- occurrence timestamp.

It stores no rendered body, email address, device token, or patient message.

### 4.9 Mascot state

`user_mascot_state` stores one current state per user and `user_mascot_state_events` stores append-only transitions.

Supported states:

- `inactive`;
- `reactivating`;
- `active`;
- `evolving`;
- `neglected`.

This phase validates explicit transitions but does not infer them from arbitrary inactivity thresholds. The future gamification phase will attach concrete domain events. Visual appearance is not stored or invented here.

## 5. Template Variables and Rendering

Templates use only `{{snake_case}}` placeholders. There are no conditionals, loops, expressions, executable HTML, or nested property access.

The server owns a context-specific allowlist. It includes only values needed by the workpack, such as:

- `name`;
- `meal`;
- `protein_remaining_g`;
- `kcal_remaining`;
- `water_remaining_ml`;
- `next_reevaluation_date`;
- `block_progress_percent`;
- `supplement_name`;
- `medication_name`;
- `trial_days_remaining`.

Rules:

- template placeholders must be a subset of the context allowlist;
- required variables must be present before selection;
- numeric and date formatting is performed by the backend for the selected locale;
- user-originated strings are normalized, stripped of control characters, length-limited, and rendered as plain text;
- unresolved placeholders fail closed;
- a failed rendition is not sent and produces non-PII telemetry;
- preview uses synthetic values only.

## 6. Selection Algorithm

Selection is a service-role-only transactional operation:

1. Resolve the patient's requested personality, defaulting to `balanced` when no preference exists.
2. Resolve the active content pack.
3. Find eligible variants for exact personality, context, channel, locale, and available variables.
4. Apply event idempotency, context cooldown, context daily limit, and the global push limit.
5. Select a variant not yet used in the current rotation cycle, ordered by oldest patient use and stable deterministic tie-break.
6. After all three variants are exhausted, select the least recently used variant and never immediately repeat the last one when another exists.
7. If the exact personality has no eligible rendition, repeat the same process with `balanced` in the same locale.
8. Never cross locales automatically.
9. If both exact and balanced catalogs fail, return no message and record `catalog_incomplete`; do not call an LLM silently.
10. Record selection or suppression atomically.

Concurrent requests for the same user, context, and channel are serialized with a transaction-level advisory lock. Retries with the same event key return the original decision.

## 7. Monthly Editorial Rotation

Runtime variety and editorial freshness are separate concerns:

- runtime rotates the three active variants by patient usage;
- high-frequency contexts receive a monthly editorial review cadence;
- lower-frequency or commercially sensitive contexts receive a quarterly cadence;
- an editor clones the active pack to create the next draft pack;
- assisted rewriting may propose new drafts from existing text, tone rules, and locale, but receives no patient data;
- assisted output never becomes active automatically;
- automated lint runs before review;
- `content_editor` reviews and edits drafts;
- `master_admin` approves and schedules activation;
- activation is atomic and retains the previous pack for one-step rollback;
- if the next pack is incomplete or unapproved, the existing pack remains active.

Assisted rewriting must preserve placeholders and intent. Blind synonym substitution is prohibited because it can alter health meaning, tone, grammar, and translation quality.

## 8. Mobile API

The reserved endpoint becomes functional.

### `GET /api/mobile/v1/coach/persona`

Returns:

- the selected public personality or `null` when using internal fallback;
- the effective personality;
- localized public options for Focus, Impulse, and Zen;
- current non-visual mascot state;
- contract version.

It never exposes `balanced` as a selectable option or returns catalog copy and internal metrics.

### `PATCH /api/mobile/v1/coach/persona`

Accepts only `focus`, `impulse`, or `zen`, requires the existing mobile idempotency contract, and returns the updated preference. The authenticated domain user is always taken from the verified bearer token, never from request JSON.

A personality change affects future selections only and does not rewrite message history.

## 9. Admin Module

Add `/settings/coach-messages` using the existing admin shell and RBAC patterns.

Capabilities:

- list and filter by pack, status, personality, context, channel, and locale;
- inspect all three variants together;
- create a new immutable draft version;
- revise draft copy by creating a new immutable draft version;
- preview with synthetic variables;
- compare versions;
- clone the active pack;
- request a bounded assisted rewrite for a selected template group;
- run coverage and safety validation;
- schedule activation;
- activate, archive, or roll back;
- display basic selection, suppression, fallback, and failure counts.

Authorization:

- `content_editor` may read the catalog and create or edit drafts;
- `master_admin` may additionally approve, schedule, activate, archive, and roll back;
- other admin roles have no write access to this module;
- every mutating server action revalidates the authenticated admin role;
- service-role access is confined to server-only modules after admin verification.

## 10. Content Safety

Every seeded or assisted rendition must satisfy:

- no guilt, shame, humiliation, hostility, or moral judgment;
- no guaranteed weight-loss or health outcome;
- no diagnosis or individualized clinical claim;
- no infantilizing language;
- Focus is firm but respectful;
- Impulse is energetic but not exaggerated;
- Zen is calm without being vague or patronizing;
- locale-native wording rather than word-for-word translation;
- push title/body size limits;
- email subject/body size limits even though delivery is disabled;
- exact placeholder preservation;
- three normalized variants in one combination must be distinct.

The initial content source is versioned in the repository and seeded through an auditable migration. The migration must be deterministic and rerunnable only through normal migration history, not manual database edits.

## 11. Security

- Enable RLS on every new public table.
- Revoke default `PUBLIC`, `anon`, and broad `authenticated` grants.
- Do not expose catalog, usage, or mascot audit tables directly to the mobile client.
- Patient preference reads and writes flow through the authenticated BFF.
- Internal selection and activation routines are executable only by `service_role` unless a narrowly scoped authenticated admin function is proven necessary.
- Any privileged function pins `search_path`, validates caller identity, and has explicit execute grants.
- Do not use user-editable JWT metadata for authorization.
- Store no rendered message or PII in usage telemetry.
- Keep assisted generation inputs limited to approved template copy and product rules.

## 12. Testing and Verification

### Unit and contract tests

- exact personality selection;
- internal balanced fallback;
- no cross-locale fallback;
- three distinct variants before reuse;
- least-recent selection after exhaustion;
- concurrent selection does not duplicate an avoidable variant;
- missing and unsafe variables fail closed;
- control-character and length sanitization;
- event idempotency;
- cooldown and daily limits;
- mobile GET/PATCH contracts;
- role checks for every admin mutation;
- mascot transition validation.

### Catalog tests

- exactly 1,080 required baseline renditions;
- complete matrix coverage;
- unique variants per combination;
- placeholder allowlists;
- bilingual safety lint;
- channel length constraints;
- prohibited language checks;
- email entries exist but delivery remains disabled.

### SQL tests

- RLS enabled;
- no forbidden grants;
- ownership isolation;
- service-only selector privileges;
- immutable active versions;
- one active pack;
- complete-pack activation;
- atomic rollback;
- usage idempotency and concurrency;
- valid mascot transitions.

### Repository verification

- focused tests while implementing;
- `pnpm --filter @mpp/admin test` where supported by package scripts;
- `pnpm test`;
- `pnpm typecheck`;
- admin production build;
- changed-file formatting/lint;
- SQL tests against an isolated database;
- Supabase lint and advisors in staging after authorized application.

## 13. Rollout

1. Create and test additive migrations locally.
2. Implement services and mobile contracts behind the existing versioned BFF.
3. Seed and lint the full baseline pack.
4. Implement the admin module.
5. Apply only to the authorized Supabase staging branch.
6. Keep staging external delivery disabled.
7. Validate with synthetic users and no PII.
8. Open a layered draft PR on top of Prompt 06.
9. Do not modify production without a separate explicit authorization.

## 14. Success Criteria

The phase is complete when:

- a patient can select Focus, Impulse, or Zen through the mobile API;
- no selection safely resolves to internal Balanced;
- every personality/context/channel/locale tuple has three approved variants;
- repeated eligible selections rotate before reuse;
- frequency and idempotency suppress duplicate messages;
- no recurring runtime path requires an LLM;
- monthly draft packs can be reviewed, scheduled, activated, and rolled back;
- admin permissions are enforced server-side and in the database;
- the mascot state exists without invented visual assets or guessed automation;
- all local and staging verification gates pass;
- existing product behavior outside this domain remains unchanged.
