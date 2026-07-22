# BodyFlow Educational Content CMS Design

**Status:** approved in product and architecture review on 2026-07-21

## Objective

Build the educational publication domain for the BodyFlow admin and the
versioned mobile BFF. Editors must be able to prepare content without a deploy,
nutrition reviewers must approve its technical accuracy, and master admins must
control when it becomes visible. The mobile app must receive only content that
is published, localized, eligible for the patient, and safe to render natively.

## Product Decisions

- The canonical article body is sanitized Markdown. Arbitrary HTML and inline
  images are not supported.
- Publications support independent `pt-BR` and `en-US` versions. A patient does
  not receive another locale as a fallback when their locale has no published
  version.
- Editorial responsibilities are separated:
  - `content_editor` creates, edits, uploads covers, and submits drafts;
  - `nutrition_admin` approves or rejects technical content;
  - `master_admin` publishes immediately, schedules, or archives.
- Targeting is optional. An untargeted publication is universal. When targeting
  is present, every configured dimension must match the patient.
- Scheduling is evaluated from database time. It does not require a cron or a
  background status transition.
- The module is app-first and has no dependency on WhatsApp or any legacy
  messaging transport.

## Scope

The delivery includes:

- publication, localization, revision, targeting, cover, user-state, event, and
  audit persistence;
- a role-gated admin publication workflow;
- secure cover upload and temporary cover download capabilities;
- mobile list, detail, read-event, and save-state routes under `/api/mobile/v1`;
- deterministic eligibility, pagination, Markdown validation, and reading-time
  calculation;
- SQL, unit, route, admin, type, and build verification;
- staging migration and staging canary validation after the branch is reviewed.

The delivery excludes:

- native iOS screens, Xcode work, final visual styling, and animations;
- APNs delivery or automatic content campaigns;
- rich-text HTML, inline media, video, audio, attachments, or embedded scripts;
- AI-authored or automatically published health content;
- comments, reactions, social feeds, recommendations learned by a model, and
  full-text search;
- production deployment or production data changes.

## Architecture

The admin remains a Next.js server-rendered backoffice. Browser clients use
authenticated server actions; they never receive a service credential. Each
server action authenticates the admin with the regular Supabase client, loads
the canonical role from `admin_users`, then delegates to a service built on the
server-only service client.

The mobile surface remains a versioned BFF. It authenticates the patient through
`createMobileRoute`, derives locale and eligibility from canonical domain data,
and returns DTOs rather than database rows. Patient clients receive no direct
table grants for CMS data and never see bucket names or object paths.

Lifecycle changes use database functions so state validation, role validation,
actor attribution, and audit insertion commit atomically. Functions are not
executable by `PUBLIC`, `anon`, or `authenticated`; only the trusted backend role
may call them. Each function also validates the supplied actor against
`admin_users` instead of trusting the application alone.

## Domain Model

### Publications

`content_publications` stores only stable identity and lifecycle metadata:

- `id` and immutable `slug`;
- creator and creation/update timestamps;
- optional global `archived_at` and `archived_by`;
- a monotonically increasing revision counter used to allocate version numbers.

A publication slug is 3 to 120 lowercase ASCII characters using letters,
numbers, and hyphens. Editorial metadata is deliberately absent from this table:
changing a draft must not alter the currently visible version.

### Localized Versions

`content_versions` stores one numbered revision for one publication and locale:

- locale is exactly `pt-BR` or `en-US`;
- category, normalized tags, `featured_today`, and targeting are immutable
  snapshots of what the reviewers approved;
- title is 3 to 120 characters;
- excerpt is 20 to 280 characters;
- normalized `body_markdown` is 100 to 50,000 characters;
- `body_hash` identifies the validated source;
- `reading_time_minutes` is derived from the canonical normalized Markdown,
  using the same alphanumeric-token rule as the database, at 200 words per
  minute rounded up with a minimum of one minute;
- an optional uploaded cover asset may be attached;
- author, technical reviewer, publisher, timestamps, and rejection reason are
  stored explicitly.

Tags are lowercase slugs, unique within a version, with at most 20 tags and 40
characters per tag. The initial category set is shared across locales, but each
published version carries its own approved category snapshot.

The initial category set is:

- `weight_loss`;
- `hypertrophy`;
- `nutrition`;
- `training`;
- `neuroscience`;
- `habit_formation`;
- `cardiovascular_health`;
- `hydration`;
- `supplementation`;
- `sleep`;
- `using_bodyflow`.

The persisted editorial state is `draft`, `in_review`, `approved`, or
`rejected`. A draft may be edited in place. Submission freezes it; later changes
create the next numbered draft. Rejected versions remain immutable and the
author creates a new draft from them. Removing a publication from the app is a
global archive action, so archiving a current version can never accidentally
reveal an older one.

`scheduled` and `published` are effective states, not mutable clock-driven
states:

- an approved version with no `publish_at` is not visible;
- an approved version with `publish_at > database_now` is scheduled;
- an approved version with `publish_at <= database_now` is publishable;
- the visible version is the highest numbered publishable version for the
  requested publication and locale; once eligible, a newer immediate version
  cannot be displaced by an older scheduled version;
- a globally archived publication is never visible.

This model lets the current version remain live while its replacement is being
edited, reviewed, or waiting for a schedule. No cron is required to swap it.

### Targeting

Target rows are normalized and keyed by `content_version_id` so values retain
database integrity and targeting changes pass through the same review workflow:

- `content_version_target_protocols` uses the existing `protocol_enum` values
  `recomposicao`, `ganho_massa`, and `manutencao` as product objectives;
- `content_version_target_plans` uses the existing `plan_enum`;
- `content_version_target_personalities` references `coach_personalities(code)` and is
  limited to selectable personalities.

For each dimension independently, no rows means wildcard. When rows exist, the
patient must match one row in that dimension. Dimensions combine with AND.

- Protocol comes from `user_profiles.current_protocol`.
- Plan comes from the most recent non-expired subscription whose status is
  `trial` or `active`. A patient without one matches only universal plan content.
- Personality comes from `user_coach_preferences.personality_code`. A patient
  without a selection matches only universal personality content.

Only a content editor may change targets on a draft. Changing targeting for a
publication with a live version creates a new draft and the current approved
target snapshot remains effective until the replacement is published.

### Cover Assets

`content_assets` is a CMS-owned catalog for `content-covers`. It does not reuse
`media_assets`, because patient media requires a patient owner and follows a
different retention lifecycle.

An asset records its server-generated path, MIME, declared and actual size,
ETag, status, creator, and timestamps. Allowed MIME types remain JPEG, PNG, and
WebP with the bucket's existing 10 MiB maximum. SVG is rejected. States are
`pending_upload`, `uploaded`, and `deleted` with validated transitions.

The admin requests a signed upload, uploads directly to the private bucket, and
calls completion. Completion verifies the object exists and that MIME and size
match the declaration before the asset can be attached. A cover in use cannot
be deleted. Mobile cover URLs are signed on demand and expire after 300 seconds.

### Patient State And Metrics

`content_user_state` has one row per patient and publication and stores:

- first and last opened timestamps;
- the localized version last opened;
- completion timestamp and completed version;
- saved timestamp;
- last origin.

Saved state survives a new publication version. Completion is true only when
the completed version is the currently visible localized version, so a material
revision can be read and completed independently.

The consolidated state is monotonic under delayed mobile delivery. An older
event may backfill an earlier `first_opened_at`, but it cannot regress the last
open, completion, saved state, corresponding version, or origin already
established by a newer state-changing event. Impressions stay in the ledger but
do not become the consolidated origin.

`content_events` is append-only and supports:

- `impression` for a card actually displayed;
- `opened` for a card selected, which is the click metric;
- `completed` for explicit completion;
- `saved` and `unsaved` for state changes;
- origin `today`, `library`, or `push`.

Each event mutation carries the mobile `Idempotency-Key`. A unique database key
on patient and idempotency key prevents a duplicate event even if the operation
commits but completion of the generic API idempotency claim fails. Saving the
same final state is a successful no-op and does not create another state-change
event.

Administrative lifecycle actions are written to the existing `audit_log` with
actor, action, entity IDs, version, status, schedule, and content hash. Full
article bodies are not copied into audit rows.

## Markdown Policy

The shared validator accepts paragraphs, H2/H3 headings, emphasis, strong text,
ordered and unordered lists, block quotes, and HTTPS links. It rejects:

- raw HTML;
- H1 headings, which would duplicate the article title;
- Markdown images and other inline embeds;
- non-HTTPS links, data URLs, JavaScript URLs, and protocol-relative URLs;
- malformed or excessively nested constructs.

Validation rejects unsafe input instead of silently rewriting approved health
content. The normalized Markdown and its SHA-256 hash are stored together. The
iOS client will later render the same supported subset natively.

## Editorial Workflow

1. A `content_editor` creates the publication and one or both locale drafts.
2. Any active `content_editor` may continue an open draft. `authored_by` remains
   the original attribution, while the audit actor records who saved or
   submitted each change. An editor may upload and attach one cover to each
   localized draft.
3. Preview uses the same Markdown parser and policy as persistence.
4. Submission validates content, cover status, metadata, and targeting, then
   transitions the draft to `in_review` and freezes it.
5. A `nutrition_admin` who is not the author approves or rejects the version.
   Rejection requires a reason between 10 and 1,000 characters.
6. A `master_admin` schedules or immediately publishes an approved version.
   Immediate publication sets `publish_at` from database time; scheduling must
   be at least five minutes in the future.
7. A master admin may archive the whole publication. Archive hides every locale
   immediately but does not delete history, metrics, versions, or assets.

Every transition uses optimistic preconditions for version and current status.
Stale browser tabs receive a conflict instead of overwriting newer work.

## Mobile API Contract

All routes require a confirmed patient account and return the established v1
response envelope. Locale comes from the canonical patient profile.

### `GET /api/mobile/v1/content`

Accepted query parameters:

- `surface=today|library|saved`, default `library`;
- optional category;
- `limit` from 1 through 50, default 20;
- an opaque cursor issued by the server.

`today` includes only `featured_today` content. `saved` includes only currently
eligible saved content. Ordering is effective publication time descending, then
publication ID descending. The cursor encodes both values and is validated
before use.

Each list item contains publication ID, slug, localized title and excerpt,
category, tags, reading time, effective publication time, feature flag,
localized version number, patient saved/completed state, and an optional
short-lived cover capability with explicit expiry.

### `GET /api/mobile/v1/content/:id`

The route accepts a UUID publication ID and returns the same metadata plus the
validated Markdown body. It returns `404 content_not_found` when the publication
does not exist or is not visible for the patient's locale, segment, schedule, or
archive state. This prevents eligibility disclosure.

### `POST /api/mobile/v1/content/:id/read`

The JSON body contains:

```json
{
  "event": "impression | opened | completed",
  "origin": "today | library | push",
  "version": 3
}
```

`version` must equal the currently visible localized version. A stale version
returns `409 content_version_changed`. The route requires `Idempotency-Key`,
updates consolidated state, appends at most one event, and returns that state.

### `POST /api/mobile/v1/content/:id/save`

The JSON body contains `saved: boolean` and the currently visible localized
`version`. It has the same visibility, stale-version, and idempotency rules as
the read route.

## Admin Experience

The admin adds a `Publicacoes` destination at `/content`. It is a dense editorial
workspace rather than a marketing page.

- The list supports status, locale, category, author, reviewer, schedule, and
  featured filters while loading only the newest snapshot for each locale.
- A publication editor exposes the stable slug and separate `pt-BR` and `en-US`
  draft tabs, each containing the complete metadata snapshot to be reviewed.
- Draft editing includes title, excerpt, Markdown, preview, cover upload,
  category, tags, feature flag, and version-scoped targeting controls.
- Review mode is read-only and shows author, content hash, previous published
  version, and approve/reject commands.
- Publication commands show explicit confirmation dialogs and effective time.
- Unsupported roles see an access-denied state and server actions independently
  reject the command.
- Publication detail loads at most 50 immutable versions, reserving the newest
  version of each locale before filling the remaining slots with the newest
  global history. It reports when older history was omitted, keeping the
  operational view bounded without hiding an active locale workflow.

No AI generation is added in this phase. Content remains human-authored and
human-reviewed.

## Error Handling And Observability

- Validation failures use structured field errors and never store partial
  lifecycle transitions.
- Concurrent editorial changes return conflict errors with no overwrite.
- Missing or mismatched cover objects fail completion and remove an invalid
  object when safe.
- Mobile database failures return the standard opaque `internal_error`; logs
  contain request ID, operation, and technical IDs but no article body, access
  token, signed URL, email, or patient-identifying data.
- Audit logs provide actor and lifecycle evidence. Product metrics contain
  technical publication/version IDs and event type only.

## Security Model

- All new public-schema tables have RLS enabled.
- `PUBLIC`, `anon`, and `authenticated` receive no direct CMS table privileges.
- The private bucket remains non-public and has no end-user object policies.
- Admin actions authenticate with the user's session and authorize against the
  database role before using the server-only service client.
- Lifecycle RPCs validate actor role and legal transition inside the same
  transaction, use fixed search paths, and revoke default function execution.
- Mobile reads are scoped by BFF authentication and recompute eligibility on
  every request. Client-provided locale, plan, protocol, and personality are
  ignored.
- Signed URLs are capabilities with short expiry and are omitted from generic
  idempotency response storage.

## Verification Strategy

### Database

Transactional SQL tests cover schema constraints, grants, RLS, role separation,
legal and illegal transitions, immutable submitted revisions, technical review,
immediate and scheduled visibility, replacement without downtime, archive,
each targeting dimension, combined targeting, locale isolation, and event
idempotency.

### Shared And Backend Code

Unit tests cover Markdown policy, limits, normalization, hashing, reading time,
query parsing, cursor validation, DTO mapping, eligibility repository failures,
asset state, and lifecycle services. Tests are written first and observed
failing before implementation.

### Mobile Routes

Route tests cover authentication, list/detail success, locale separation,
segmentation, schedule, archive, `404` non-disclosure, stale-version conflict,
idempotent read/save mutations, generic idempotency replay, and temporary cover
refresh.

### Admin

Service and action tests cover every role, stale revision conflicts, cover
verification, submission, review, publication, scheduling, and archive. The
admin package test suite, full monorepo tests, full typecheck, and admin build
must pass.

## Rollout

Implementation is layered on `codex/bodyflow-personalities-mascot-v1` in its own
worktree and branch. Migrations are additive and first applied only to the
Supabase staging branch `xitugspwfxkcluxvrdeg`. Staging crons remain inactive.

The canary uses synthetic admins and patients only. It verifies the complete
editorial workflow, both locales, universal and segmented visibility, scheduled
visibility using database time, cover capability expiry, metrics idempotency,
and archive behavior. The result is published as a draft pull request. Production
remains unchanged until a separate explicit authorization.
