# Initial conversation scope for an existing account

A completed legacy profile can have no row in the existing private authority
epoch table. A read of the conversation session must not manufacture that row.
`GET /api/mobile/v1/conversation/session` returns the specific 409 code
`conversation_session_initialization_required` for that case.

The authenticated, entitlement-gated `POST` at the same path accepts only
`{"schema":"conversation.session-initialization.v1"}` and the fixed
`Idempotency-Key: conversation-session-initialize-v1`. It accepts no owner,
epoch, clinical values or query parameters. Its patient comes from current
verified Auth and the existing account mapping; admin identities are excluded.

The operation checks the completed profile and current identity before using
the existing locked `observe_mobile_signup_strength_epoch` RPC. That RPC creates
only a missing epoch. An existing epoch, including a reset epoch, is preserved;
the operation admits no signup, intake, workout or meal command. An already
initialized session requires no epoch write. Fresh clinical, Auth, admin and
mapping checks gate the returned snapshot. A reset or backwards observation
during initialization prevents publication of the original scope.

The iOS client keeps the original Auth lease. It invokes initialization only
after that exact 409 code, never after a general conflict, timeout or server
error. The POST cannot automatically refresh or replay after 401. If its response
is lost, a later explicit open reads the current session first. No profile,
clinical target, historical receipt or XP is rewritten by initialization.

The BFF method guard requires the exact GET/POST/dynamic/runtime export set at
this one path before projecting the old GET-only route inventory. All historical
route counts and hashes remain pinned; unknown methods and paths still fail.
Local tests, a build and a Preview are separate from connected/native release
qualification and installed tester acceptance.
