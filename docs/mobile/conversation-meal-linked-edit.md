# Editing a clarification-owned meal

The existing generic five Save/Undo SQL functions can operate on a real
clarification child. The original report remains negative and immutable. Its
completed child owns the effect and all subsequent edit operations.

The edit-specific private binding is a closed union of the original report and
actual `conversation.clarification.v1` registry shape. The original child effect
retains its schema, child command/hash/epoch, actual registration ID and parent
references. Its registration ID need not equal the command ID. Its provider is
`conversation.clarification/<owner>/<parent>`; it is never replaced with a report
provider or a provider using the child ID.

The qualified original effect supplies the provider when validating the entire
private C11 state. The service carries that original child effect from its actual
state read to the one-shot store. This value is checked locally, never added to
the RPC arguments or accepted from HTTP input. Full C11 rows still participate in
the existing SQL CAS; neither JSON decoding nor this historical effect grants
authentication or write authority.

A linked current group has `conversation.meal-group.v2`. The original v1 group
keeps its exact body. The operation input and factual acknowledgment remain the
existing identity-neutral edit v1 contracts: their actual child ID/hash and
separate operation ID/hash are validated without inventing a v1 report. The
original feedback, original effect, nutrition context, targets and XP are not
rewritten. Public groups expose current food facts and action availability,
without private snapshots, balances or Auth context.

The same finite five-minute registration Undo window, current revision, full
version and open-day checks apply. Unknown Save results reconcile by one read;
they do not calculate or write again. Historical edit decoding can retain the
actual child binding, but reading history never acknowledges a pending write.

The checked-in SDK effect fixture is the exact binding/effect subset of the
synthetic local export `NativeLINKED-FEEDBACK-GOLDEN.json` (SHA-256
`831b9d10b1c20a60869d0d394df9c5e3a0d71c3648c2fd38245b04fad9cf87bc`).
The C11 context in unit tests is separately constructed synthetic data. This
source increment does not, by itself, qualify the five RPCs on an actual child,
public HTTP, the native editor or a distributed release; those are separate
connected checks.
