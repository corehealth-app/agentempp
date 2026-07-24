# BodyFlow Central Entitlements Design

**Status:** implemented and staging-validated in the isolated worktree on
2026-07-24. Production charging, paywall activation, real-user migration and
provider configuration remain excluded.

## Objective

Create one deterministic, auditable access decision for the native BodyFlow
app and trusted admin/backend surfaces. RevenueCat will simplify App Store
purchase lifecycle handling, while the BodyFlow database remains the final
authority for product access.

This flow is app-first. Frozen legacy messaging and agent billing code is not a
consumer of the new entitlement service.

## Evidence And Current State

The repository already contains:

- `subscriptions`, with Stripe provider IDs, plan, period and legacy statuses;
- idempotent `subscription_events` claim/finalization RPCs;
- a signature-verified Stripe Edge Function;
- `GET /api/mobile/v1/entitlements`, currently deriving access directly from
  `subscriptions.status IN ('active', 'trial')`;
- content-delivery SQL that independently repeats part of the same legacy
  subscription rule.

The staging branch contained zero users, subscriptions and subscription events
when inspected with aggregate-only queries. Production legacy-user counts were
not queried and cannot be validated from the available evidence.

## Provider Decision

Use RevenueCat for the iOS purchase integration and subscription lifecycle.
Use the BodyFlow domain UUID as the RevenueCat App User ID only after app
authentication has resolved a confirmed patient account.

RevenueCat is not the source of authorization inside BodyFlow. Signed provider
events are normalized into BodyFlow records, and all app access is resolved by
one database function. This prevents a provider outage or SDK cache from
silently becoming the backend authorization rule.

No RevenueCat account, product, entitlement, API key, webhook secret or live
integration is created in this phase. The future provider configuration must
use separate sandbox and production webhook configurations.

## Access Model

The canonical entitlement key for the initial product is `bodyflow_full`.
Supported states are:

- `active`: paid access currently valid;
- `trialing`: trial access currently valid;
- `grace_period`: billing recovery window with access;
- `expired`: period ended and access denied;
- `canceled`: renewal canceled; access continues only until a future explicit
  `access_expires_at`;
- `grandfathered`: explicitly approved legacy access;
- `manual_comp`: explicitly granted complimentary access;
- `blocked`: explicit denial that overrides every other source.

Supported sources are `stripe`, `apple_storekit`, `revenuecat`, `manual` and
`legacy`. New iOS purchases use `revenuecat`; `apple_storekit` remains available
for a future controlled migration away from RevenueCat without schema changes.

Every provider or manual grant is stored independently. A canceled or expired
record from one source must never erase a valid record from another source.
The resolver uses the following deterministic policy:

1. any currently effective `blocked` record denies access;
2. otherwise, any currently valid access record grants access;
3. access-capable states are `active`, `trialing`, `grace_period`,
   `grandfathered`, `manual_comp`, plus `canceled` before its explicit expiry;
4. expired time bounds deny access even if the stored state is otherwise
   access-capable;
5. among valid records, choose status priority, latest expiry and stable ID as
   deterministic tie-breakers;
6. if no record grants access, return the most recent denied state; if no
   record exists, return `expired` with reason `no_entitlement`.

The resolver returns only patient-safe fields: key, access boolean, state,
source, plan, expiry, grace expiry, cancel-at-period-end, reason and decision
time. Provider IDs, raw payloads and internal metadata are never returned.

## Persistence

Create `user_entitlements` as the normalized provider/manual projection:

- immutable ownership: `user_id`, `entitlement_key`, `source`,
  `source_reference`;
- mutable provider state: status, plan, start/expiry/grace timestamps,
  cancellation flag and environment;
- ordering: `last_provider_event_at`, `last_provider_event_id`;
- observability: created/updated timestamps and non-sensitive metadata.

The unique source reference prevents one provider subscription from being
attached to two patients. Provider updates are accepted only when their
`(event_at, event_id)` ordering key is newer than the stored key. Exact retries
return the current record without mutating it.

Create `entitlement_events` as a sanitized idempotency/audit ledger. It stores
provider event ID, event type, source, environment, processing result and
technical timestamps. It does not store raw webhook payloads, emails, receipt
data, transaction tokens or customer attributes.

Existing `subscription_events.payload` remains private legacy storage; this
phase does not expose or backfill it.

## Trusted Database Interfaces

`resolve_user_entitlement` is the only read decision used by the mobile BFF.
It is callable only by `service_role`; the authenticated mobile route resolves
the patient identity before invoking it. It is not callable by `anon`, direct
`authenticated` clients or unrestricted `PUBLIC`.

The shared mobile route wrapper enforces that decision after patient
authentication and before invoking the product handler. Account recovery and
configuration surfaces remain reachable without a paid grant: `/me`,
`/profile`, `/onboarding`, `/entitlements`, `/coach/persona`, `/devices` and
`/notification-preferences`, including their true child paths. Every other
`/api/mobile/v1` route fails closed with `subscription_required`. Exact
path-boundary matching prevents a similarly prefixed route from inheriting an
exemption.

`apply_entitlement_event` validates and atomically applies one normalized event.
It is service-role only, uses a fixed search path, verifies the trusted backend
role and rejects unknown states, sources, environments, invalid time ranges and
empty identifiers.

`sync_stripe_subscription_entitlement` translates an already persisted Stripe
`subscriptions` row into a central entitlement event in the same trusted
transaction. The Stripe webhook calls it after each successful subscription
mutation. Legacy `trial` maps to `trialing`; `past_due` maps to
`grace_period` only while a future period end exists, otherwise `expired`.

## RevenueCat Boundary

The webhook route is disabled when its signing secret is absent. It must:

- read the exact raw request body;
- verify RevenueCat HMAC with a constant-time comparison and a bounded replay
  window;
- accept only the configured environment;
- require a UUID App User ID and the configured entitlement key;
- normalize only known event types;
- use provider event ID and timestamp for idempotency/order;
- never log request bodies, product receipts, aliases or customer attributes.

The future sandbox configuration names are
`REVENUECAT_WEBHOOK_SIGNING_SECRET`, `REVENUECAT_WEBHOOK_ENVIRONMENT` and
`REVENUECAT_PRODUCT_PLAN_MAP`. They remain unset in this phase. Product-change,
pause and test events are acknowledged without mutating access. Billing issues
mutate access only when the provider includes an explicit grace-period expiry;
a related `BILLING_ERROR` cancellation is ignored so it cannot overwrite that
explicit grace state.

Voluntary, developer-initiated and price-increase cancellations retain access
only until the explicit provider expiry. A customer-support refund denies
access immediately. `REFUND_REVERSED` restores active state. A cancellation
without one of those understood reasons remains retryable for reconciliation
instead of guessing whether access should continue.

Events that cannot be safely reduced from their own payload, including transfer
reconciliation, must fail closed for backend mutation and remain retryable.
They must not guess ownership or revoke another patient's access.

## Stripe Compatibility

The existing Stripe subscription table and checkout remain operational. New
Stripe webhook mutations also update `user_entitlements` through the trusted
sync RPC. The central resolver additionally has a temporary read-through for
legacy Stripe rows that have not yet been projected. This avoids requiring a
real-user backfill in this phase.

The read-through is intentionally narrow: only a future active/trial period can
grant access. It does not grandfather users without subscriptions. Production
legacy migration requires a separate aggregate audit and explicit approval.

## Fail-Closed And Migration Policy

- New app-first patients without a valid entitlement receive access denied.
- No production user is migrated or revoked in this phase.
- No implicit entitlement is inferred from account age, legacy messaging identity,
  email, role or historical messages.
- Grandfathered and manual-comp access require explicit service-side records
  with an audit reason and actor reference in non-sensitive metadata.
- Admin/support roles do not automatically receive patient product access.
- Provider outages do not revoke an already valid record before its known
  expiry; missing or unverifiable new claims do not grant access.

## API Contract

`GET /api/mobile/v1/entitlements` returns:

```json
{
  "data": {
    "entitlement": "bodyflow_full",
    "has_active_access": true,
    "status": "active",
    "source": "revenuecat",
    "plan": "mensal",
    "access_expires_at": "2026-08-24T00:00:00.000Z",
    "grace_expires_at": null,
    "cancel_at_period_end": false,
    "reason": "valid_entitlement",
    "decision_at": "2026-07-24T00:00:00.000Z",
    "mobile_billing": {
      "provider": "revenuecat",
      "available": false,
      "reason": "provider_not_configured"
    }
  },
  "request_id": "..."
}
```

The route never returns raw subscription rows or provider references. Billing
availability remains false until sandbox configuration is separately approved
and verified.

The same decision is also a server-side gate for protected mobile routes. A
client cannot bypass it by omitting the entitlement endpoint or by relying on a
cached SDK purchase state.

## Security And Privacy

- RLS is enabled on both new tables.
- No direct writes are granted to authenticated users.
- Provider/manual identifiers are not directly selectable by patients.
- Trusted mutation functions are revoked from `PUBLIC`, `anon` and
  `authenticated`, and granted only to `service_role`.
- The patient-safe resolver is service-role only and returns a bounded JSON
  projection through the authenticated BFF.
- No secret or raw provider payload is stored in the central entitlement
  tables, test fixtures or logs.

## Known Bounded Follow-Up

The content-delivery database functions still derive the optional editorial
`plan` targeting dimension from legacy `subscriptions`. They do not decide
product access: the authenticated BFF gate now denies protected content routes
unless the central resolver grants access. However, a RevenueCat-only or manual
entitlement may not receive content whose eligibility is additionally narrowed
by a legacy plan value.

Before enabling a plan-specific content catalog, those functions must consume
a patient-safe plan resolved from the central entitlement service. Creating
mirror `subscriptions` rows is intentionally rejected because it would restore
two mutable sources of truth. This follow-up does not block the initial catalog
while content is not segmented by plan.

## Out Of Scope

- Production migrations, deploys, charging and paywall activation.
- App Store Connect or RevenueCat dashboard configuration.
- Real-user backfill, grandfathering or subscription repair.
- Product identifiers, prices, offers and trial commercial policy.
- SwiftUI purchase UI or SDK installation; that starts in the iOS prompts.
- Any legacy messaging integration or compatibility work.

## Acceptance

- The same database resolver decides access for the app and trusted admin/BFF
  consumers.
- Every protected mobile route enforces the resolver after authentication and
  before product data is read or mutated.
- Multiple sources cannot destructively overwrite each other.
- Old or duplicate provider events cannot regress a newer decision.
- Ordinary cancellation retains access only through an explicit future expiry;
  a confirmed customer-support refund denies access immediately.
- Explicit block overrides every valid grant.
- New users with no record fail closed.
- Stripe remains compatible without a production backfill.
- RevenueCat ingestion is safe-by-default and disabled without sandbox config.
- No real user, price, charge, provider secret or production environment is
  changed.
