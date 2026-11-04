# Durable command meal edit service

`conversation-meal-edit-service.ts` is private orchestration over the five
service-only edit RPCs. It is not a public presentation or an enabled route.
The authenticated patient and original command/hash/epoch bind every operation.
The caller preserves its operation UUID and closed input across reconciliation.

The service reads the original operation winner first. A fresh Save requires the
client's exact current revision and opaque full C11 version, then reuses the
existing consumed-meal preparation. The complete private state, including raw
timestamps and unknown database columns, reaches the SQL comparison unchanged.
Undo delegates restoration to SQL's recorded beforeimage. It does not calculate
inverse nutrient ratios. Original registration feedback and receipts stay intact.

There is one write attempt. A lost write response permits one read of that same
operation. Without a proven winner the result requires reconciliation; the
service does not resend, generate another UUID or claim that saving failed.
A successful private receipt is revalidated against the original binding and
operation hash. Its full snapshot, including historical daily balance, must
never be forwarded as a public chat response or current clinical guidance.

New Flow media clients also send `X-Conversation-Owner` on asset operations.
The common route checks this optional precondition after authentication and
entitlement and before the media handler. The patient comes from authentication;
the header cannot authorize ownership. Existing clients without it are unchanged.

## Qualification

The local synthetic stack exercised actual GoTrue authentication, PostgREST,
the SDK edit store, C11 preparation and all five edit RPCs: quantity Save,
replay, Save Undo, one-to-many replacement and exact restoration, original
registration Undo, stale versions, isolation between accounts and a committed
write whose response was deliberately lost. No second write was performed in
that recovery. The surrounding command HTTP run passed 25 requests. Its
interpreter response was controlled; this is not external-provider or native
end-to-end qualification.

The first integration run stopped at an invalid foreign-account test fixture:
it changed only the top-level patient fields and correctly received an identity
error. The corrected run authenticated the second account through the real Auth
dependencies and passed. Both runs restored the exact seed/global fingerprint.
The final handover verified 94 user-owner foreign-key columns empty, plus no
Auth users, identities, sessions, refresh tokens, audit entries or Storage objects.

Focused service/media neighbors: 164 tests in eight files. Full Admin: 5,850
tests in 250 files. BFF: 84 tests in 11 files. Nonincremental Admin typecheck
passed. Independent static reviews found no material issue. Public projection,
native integration, staging activation, distribution and client acceptance are
separate gates; none is implied by these checks.
