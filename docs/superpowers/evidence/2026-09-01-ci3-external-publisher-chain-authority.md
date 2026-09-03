# CI-3 External Publisher chain authority — local evidence

## Scope

This evidence records authoring-only verification for the external Publisher
chain. It contains no raw authority values, host data, credentials, keys,
configuration or customer data.

## Authority model

1. The published Mac executor authority remains the frozen local lineage and
   preserved Gate 0 binding.
2. External Publisher 0 is the sole root-only issuer/pass producer and has one
   fixed non-interactive provision attempt, with no retry.
3. External Publisher 1 is the sole fixed-bootstrap materializer of the
   controller-consumed V2 authority and exact terminal-anchor writer.

The public transport has a closed allowlist and excludes issuer-private key
material. Publisher 1 binds exactly sixteen receiver leaves, their physical
metadata, the request/receiver identity, its closed environment and the writer
source. Every evidence projection is `raw_values=false`.

## Verification record

- RED recorded before implementation: chain module absent; installer source
  absent. These failures established the intended production boundaries.
- External Publisher chain suite: 223 passed, zero failed, zero skipped, zero
  todo.
- Publisher 1 bootstrap installer suite: 143 passed, zero failed, zero
  skipped, zero todo.
- The unchanged frozen terminal-writer suite: 161 passed, zero failed, zero
  skipped, zero todo. It is compiled directly with its published synthetic
  entrypoint; no copied source, replacement entrypoint or extracted validator
  is used.
- Actual-main Publisher 1 compiles the authority-bound installer candidate to
  an owner-only hash-verified binary, then invokes that binary with the single
  canonical request. The synthetic integration verifies its installed tree,
  claim/result receipts and exact-existing recovery; a mismatched request stops
  before compiler invocation, claim or tree creation.
- The actual-main producer serializes the frozen writer's 13-field transaction
  directly with CI-only fixed roots. The installed unchanged writer then proves
  created, exact-existing and crash recovery; request identity, receiver leaf
  and destination-parent race negatives leave no accepted final tree. Swapped
  issuer, writer identity and authority-subject lineage are rejected by the
  producer before bootstrap claim or writer-tree creation.
- Node syntax and Swift compilation are exercised by the focused suites.
- The pre-existing published executor record of 1460/1460 and its preserved
  Gate 0 are referenced only as frozen predecessors, not re-executed evidence.

## Operational status

Publisher 0, issuer/pass, transport, human authorization, Publisher 1 and
controller external roots are not provisioned by this task. The current
operational result is `STOP_PRE_AUTHORITY`. No network, VPS, administrative
prompt, simulator, root-path write, remote bundle mutation, production action
or CI-3 continuation occurred.

## Implementation status

**PARTIAL — local authoring only.** The executable main path now derives the
same request root, receiver root and transaction pathname used by the frozen
controller; preparation creates the parent-pinned local tree, and Publisher 0
pre-materializes the exact-existing sixteen leaves and request before deriving
one V2 materializer and one canonical installer request. Publisher 1 reopens
and revalidates that single projection before its fixed child. The installer
independently pins a fixed frozen-authority projection, compares all pass
lineage, rejects non-canonical or Node-unsafe physical metadata, and retains
the descriptor/no-follow, no-clobber and receipt-last guarantees. These local
guarantees are not a provisioned authority or an authorization to continue
CI-3.

The synthetic root is a closed CI-only projection selected solely from the
fixed test root before serialization; it is not a caller parameter and it does
not weaken production's fixed roots. Operational publication still remains
separately stopped until external authorities are present.

Continuation order is fixed: obtain explicit human authorization, provision
Publisher 0 once, transport only allowlisted public artifacts, provision and
read back Publisher 1/controller, then resume the separately authorized
simulator/SSH/CI-3 sequence. Prompt budgets stay closed, the remote bundle stays
unchanged, and the previously established cleanup deadline remains in force.

## Semantic-safe successor remediation evidence

The predecessor evidence remains a valid `STOP_PRE_AUTHORITY`; it is not an
operational successor authority. The review findings were traced to five
causes: production integration omitted the writer semantic capability, a
mutable user-owned installer was still a privileged boundary, Publisher 0
fixtures pre-created outputs later treated as produced/transported, the
request negative changed a receiver leaf instead of independent request bytes,
and documentary totals had become stale.

The successor compiles two binaries from the exact same reviewed Swift source.
The validation binary exposes only semantic preflight and calls the shared
production validators; the operational binary cannot expose preflight. The
controller executes that validation binary against the real owner-only
receiver and request, persists only its sanitized stdout receipt, and reads it
back before Phase A. JavaScript neither fabricates that receipt nor asserts
semantic parity. Source, request and receiver replacement after preflight all
fail before claim or effect.

Phase A authenticates the fixed request and receipt and installs only the exact
installer into its version-addressed immutable system location. Phase B is
reachable only through that root-owned immutable self; it revalidates the
bindings, creates the claim before the first target effect, and publishes the
result last. Crash, partial, divergent, unclaimed and exact-existing cases fail
closed without refetch, retry or cleanup.

Installer selection is independently bound rather than self-authorized. A
compile authority fixes the reviewed source, fixed driver, selected compiler,
compile arguments/toolchain provenance and expected binary digest. The human
receipt binds the compile authority and expected digest, Swift preflight
repeats both, and Phase A accepts only an actual installer matching the
independent expected digest. The successor canonicalizer uses explicit UTF-8
key ordering; a JS/Swift byte-equality test covers digit/underscore adversarial
keys. Authority consumption remains exact-schema only: unknown keys are
rejected rather than treated as a forward-compatible extension.

The fixture now begins with zero downstream Publisher outputs. A fixed producer
creates issuer/pass/manifest during Publisher 0, a fixed receiver creates the
receiver artifacts during transport, and only then are request, human receipt,
final identities and semantic preflight consumed. The manifest remains exactly
sixteen controller targets. The generator is a separately validated
predecessor link and is not a seventeenth manifest target.

The 1.7.16 focused checkpoint was 56/56 state-order, 54/54 shared-seam, 10/10
two-phase installer, 3/3 real wiring/no-preseed, 7/7 preserved negatives and
5/5 controller/downstream, plus 1/1 independent installer-selection negative.
Its complete pre-review runs were 282/282 external-chain, 153/153 installer,
215/215 writer and 1501/1501 four-file Mac authority tests. Those numbers are
historical inputs to the successor review, not the 1.7.17 remediation result.
Each reported historical group had zero failure, cancellation, skip and todo. The earlier
223/223, 143/143, 161/161 and 1460/1460 totals are historical only. The three
writer timeouts and interrupted broad run observed under prior pressure were
not hidden: the same current suites completed reliably with test concurrency
set to one and without timeout enlargement, bypass or assertion reduction.

The downstream path now reaches operation authority after Publisher 1,
controller authority across exactly sixteen targets, and privileged-writer
authority only after all six scans; terminal anchoring remains denied earlier.
The remote generator, bundle schema, remote path derivation and input contract
remain unchanged and read-only. A fresh successor Gate 0 is mandatory; no
historical receipt is transferable. No network, SSH, simulator, privilege,
root write, production, CI-3, retry or cleanup occurred, and the previously
recorded cleanup deadline remains applicable.

## Successor review remediation evidence — 1.7.17

The reviewed successor now enforces exact parent and subject lineage in both
launcher and controller and rejects the predecessor authority. Publisher 0
starts with no future output candidates: its fixed producer creates the public
outputs, authenticated transport captures them, and the receiver consumes only
that capture. The human V2 receipt is independently created only after the
request and binds the authority, request, receiver, sixteen leaves, installer
Git provenance and the single non-administrative prompt budget.

The first privileged boundary is one fixed macOS system driver after semantic
preflight and after the request, receiver and every leaf are reobserved. It
interprets the exact supervisor Swift bytes bound by Git path, blob OID and the
independent authority manifest. There is no candidate verify-path/execute-path
split and no `argv[0]` trust. Phase A then installs/readbacks its immutable self;
Phase B accepts only that fixed self. Deterministic crash recovery accepts only
the uniquely authenticated state before or after the freeze and never cleans,
refetches, retries or starts another attempt.

The canonical V2 receipt is versioned and exact-schema throughout the real
consumer path. The shared Swift validator checks the complete key set and all
cross-field relations. Cross-language mutation parity rejects 103 mutations:
97 missing-field variants and 6 extra-field variants. The real operation
publisher consumes the authenticated request, issuer/pass, human receipt and
operation authority, readbacks exactly sixteen targets, persists settlement,
and constructs the later-writer authority only after the required state. Its
test seam replaces only the privilege/root I/O boundary; it does not fabricate
receipts or operation authority.

The consolidated focused 1.7.17 proof is 150/150: 1 launcher-lineage, 10
controller, 70 external chain, 13 installer and 56 writer tests, with zero
failure, cancellation, skip and todo. Final serial suites passed external
293/293, installer 156/156, controller 740/740, launcher 115/115, writer
217/217 and generator 434/434. The first aggregate run exposed one launcher
structural-skeleton regression (1505/1506); after restoring predecessor
structure without changing the generator or weakening assertions, the final
aggregate passed 1506/1506 with zero fail/cancel/skip/todo. The remote
generator, schema, path derivation
and input contract remain read-only. No network, SSH, simulator, real
privilege, administrative prompt, root write, production, CI-3, stage, commit,
push, retry or cleanup occurred. Operational state remains
`STOP_PRE_AUTHORITY`.

## Successor round-2 remediation evidence — 1.7.18

This section supersedes incompatible architectural claims in the historical
1.7.17 checkpoint. The fixed macOS invocation crosses the real bounded
subprocess path with LF/NUL-free arguments, exact `swift -
--privileged-supervisor` dispatch, one prompt budget and atomic loaded-image
selection. The local proof substitutes a fake spawn at that boundary and does
not exercise administrator authority.

Publisher 0's sole SSH contract bootstraps its remote helper from the exact
Git-bound controller and launcher blobs. Receive is an authority builtin and
production verify resolves the nine-entry immutable bootstrap's installed
launcher. Missing executables consume zero attempts. The authenticated
authority projection is derived from the signed pass and available published
Git/current-user records; no frozen root projection is a preflight
prerequisite.

Phase B readbacks all nine canonical bootstrap entries before the causal
operation-publisher request is written. The no-effect local path invokes the
compiled Swift materializer and independently observes the authenticated
claim, canonical result, all sixteen target bytes/modes/hashes and controller
settlement. Outer-ledger recovery is operation-specific: Phase B settlement
cannot recover verify. Partial, absent or divergent controller state stops
without respawn, retry, refetch, prompt or cleanup. Phase A also
deterministically recovers the exact post-promotion/pre-freeze state.

The shared closed V2 schema has a literal 103-mutation matrix: 97 missing-key
and 6 extra-key variants, with JS/Swift acceptance parity. Current complete
serial results are external 304/304, installer 158/158, controller 743/743,
launcher 115/115, writer 227/227 and read-only generator 434/434. The current
aggregate is 1981/1981; every run has zero fail/cancel/skip/todo. The remote
generator, schema, path derivation and input contract remain read-only. No
network, SSH, simulator, real privilege, root write, production, CI-3, stage,
commit, push, retry or cleanup occurred. Status remains
`STOP_PRE_AUTHORITY`.

## Successor round-3 remediation evidence — 1.7.19

This section supersedes incompatible architectural claims in the historical
1.7.18 checkpoint. The sole Publisher 0 transport now starts, in the local
production-shaped proof, with its remote object root, issuer, request, pass,
payload and helper absent. A fixed system shell receives the exact Git bytes,
manifest, provenance and eleven authority inputs through stdin. In that same
session it materializes, readbacks and freezes the controller and tool before
executing the controller, then creates a versioned claim-first transaction,
owner-restricted Ed25519 key, public issuer, unsigned request and payloads. The
signed pass, manifest and authenticated transport receipt are published last.
The proof uses an initially empty fake remote; it does not perform real SSH.

Authenticated stdout is persisted to an exclusive owner-only, synchronized
local journal before the remote operation can be reported settled. A crash
after remote settlement and before local capture promotion therefore recovers
from that same journal without a second session. Publisher 1 keeps one
supervisor alive across Phase A and Phase B under the original prompt. Reentry
after exact Phase A joins the original continuation, with no second prompt or
Phase A invocation; partial or divergent Phase B state stops closed.

The no-effect integration executes the installed zsh launcher and crosses into
the installed Node controller. That controller derives the causal request from
its fixed installed version root, without an ambient descriptor, readbacks all
sixteen targets, persists settlement, invokes the six actual scan functions
and establishes later-writer reachability. Terminal mode remains denied. The
launcher retains the predecessor structural skeleton and the generator remains
read-only.

Current complete serial results are external 311/311, installer 158/158,
controller 743/743, launcher 115/115, writer 227/227 and read-only generator
434/434. The six-file serial aggregate is 1988/1988 in 711.07 seconds, with
zero fail/cancel/skip/todo and no timeout. The remote generator, schema, path
derivation and input contract remain read-only. No network, SSH, simulator,
real privilege, root write, production, CI-3, stage, commit, push, retry or
cleanup occurred. Status remains `STOP_PRE_AUTHORITY`.

## Successor round-4 remediation evidence — 1.7.20

This section supersedes incompatible 1.7.19 claims. Publisher 0 now creates
each bootstrap object exclusively with no-follow semantics, synchronizes files
and directories, freezes and readbacks flags plus the complete physical
identity tuple, verifies the exact tree, and executes the controller/runtime
through pinned descriptors. File, directory, mode and extra-leaf swaps stop
before controller execution. A new transaction requires an absent root and
publishes its claim first. Any existing root must carry the original exact
claim before another object is read or written; unclaimed, extra, key, issuer
and payload preseed cases stop without mutation.

The one Publisher 0 session now exposes only PREPARED until authenticated local
journal bytes and the local ACK have been synchronized. Causal local receipts
use owner-only staging, file synchronization, atomic promotion and parent
directory synchronization. The local ACK precedes remote commit, and a final
broker-owned QUIESCED receipt prevents return while a filesystem write remains.
Kill windows before the first journal chunk, before its last chunk and after
the local ACK all recover the original durable decision with no second session
or effect.

Publisher 1 registers, within the original administrative protocol, a
root-owned version-addressed continuation bound to immutable self, claim and
persistent service definition. The synthetic seam kills the supervisor itself
and the durable continuation resumes Phase B without another prompt or Phase A.
An authenticated barrier immediately before Phase B makes partial/divergent
state deterministic and stops both reentry and the original supervisor. The
no-effect E2E executes the installed launcher itself, crosses zsh into the
installed Node controller, feeds six scanners with actual serialized produced
surfaces, readbacks sixteen targets, settles and traverses the real later-writer
dispatch while terminal publication remains denied.

Current complete serial results are external 322/322, installer 159/159,
controller 743/743, launcher 115/115, writer 227/227 and read-only generator
434/434. The six-file serial aggregate passes 2000/2000 in 811.70 seconds with
zero fail/cancel/skip/todo. The shared literal mutation matrix remains 103 = 97
missing fields plus 6 extra fields. The remote generator, schema, path
derivation and input contract remain read-only. No network, SSH, simulator,
real prompt/privilege, root write, production, CI-3, stage, commit, push, retry
or cleanup occurred. Status remains `STOP_PRE_AUTHORITY`, pending two fresh
independent reviews.

## Successor round-5 remediation evidence — 1.7.21

This section supersedes incompatible 1.7.20 claims. Before any Node/controller
process, Publisher 0 invokes the fixed materializer to create roots and leaves
with exclusive/no-follow primitives, retain pinned descriptors, authenticate
bytes and physical identity through those same descriptors, synchronize,
freeze/readback and verify the exact tree. Local tests cover an unclaimed
preexisting root, pathname replacement between open/hash and hash/exec,
directory replacement and an extra leaf. No unclaimed tree is normalized with
chmod/chflags.

The local production-shaped protocol now separates PREPARED from COMMIT:
remote terminal output remains absent until the local journal and ACK are
durable. A version-addressed continuation owns the fixture's sole session, and
tests kill both broker and outer process in all three prepared windows and
recover the local decision without a second session or effect. Local receipts
use owner-only staging, file and parent synchronization, and exclusive-link
no-clobber publication; a divergent destination race is rejected instead of
being replaced.

Publisher 1 requires exact immutable claim, definition, invocation,
registration and marker objects. Its launchd definition is one-shot without
KeepAlive. The synthetic registration matrix kills the supervisor at CLAIM,
DEFINITION, BOOTSTRAP and REGISTRATION and proves exactly one worker invocation
after terminal failure. The no-effect E2E executes the fixture-installed
launcher through zsh and Node/controller, collects and serializes the six
surfaces produced by that execution, reads sixteen targets, and calls the real
`publishPrivilegedWriterAuthority` implementation; only its effect boundary is
substituted below the consumer.

These are local proofs, not external operational evidence: the remote is a
fixture with no real SSH or host restart, the service seam does not exercise
real launchd/reboot/root prompt, and the installed launcher fixture does not
drive Terminal, Xcode or a simulator. Complete serial results are external
337/337, installer 172/172, controller 743/743, launcher 115/115, writer
227/227 and read-only generator 434/434. The six-file serial aggregate passes
2028/2028 in 953.86 seconds with zero fail/cancel/skip/todo. The remote
generator, schema, path derivation and input contract remain read-only. No
network, SSH, simulator, real prompt/privilege, root write, production, CI-3,
stage, commit, push, retry or cleanup occurred. Status remains
`STOP_PRE_AUTHORITY`, pending two fresh independent reviews.

## Successor round-9 remediation evidence — 1.7.24

This section supersedes the incompatible Publisher 1 activation inference in
1.7.23. Before activation may be signalled, the registrar now creates and
verifies a version-addressed activation owner's durable identity, claim, lock
and ready handshake. The activation owner, rather than the registrar, owns the
single physical kickstart and worker recovery. A registrar restarted before
the signal or after accepted start but before worker-launch receipt rejoins
that same owner; absence of the launch receipt is not interpreted as proof
that no kickstart occurred. The worker still has neither `RunAtLoad` nor
`KeepAlive`.

The new tests were RED 0/2 while those boundaries were absent and are GREEN
2/2. They kill the actual registrar PID at `PRE_SIGNAL` and
`POST_ACCEPT_PRE_RECEIPT`, retain the original owner PID, and observe exactly
one executable kickstart, one worker launch and at most one effect entry with
deterministic terminal settlement. Round 8 predecessor proofs pass 11/11;
impacted regressions pass 4/4, 4/4 and 6/6; the complete installer passes
173/173. Swift typechecks and Node syntax checks pass. Complete suites pass
external 360/360, installer 173/173, controller 743/743, launcher 115/115,
writer 227/227 and read-only generator 434/434. The serial aggregate passes
2052/2052 in approximately 1156.5 seconds with zero fail/cancel/skip/todo.

The local failure model does not prove activation-owner death, host
reboot/reattachment, real launchd/root prompt, Terminal, Xcode, simulator or
privileged publication. Remote generator, schema, paths and input contract
remain read-only. No network, real SSH, admin/root, production, CI-3, stage,
commit, push or external effect occurred. Status remains
`STOP_PRE_AUTHORITY`.

## Successor round-7 remediation evidence — 1.7.22

This section supersedes the incompatible 1.7.21 one-shot and ownership claims.
For Publisher 0, the fixture PREPARED tree is synchronized, mode-frozen,
read back and validated before local ACK. A version-addressed local session
supervisor retains the sole fake-SSH child while journal workers are killed
and restarted at the three authenticated boundaries. After ACK, terminal
remote COMMIT is only the final no-replace hard link; PREPARED remains as
evidence on the same inode with `nlink=2`.

Publisher 1 uses a supervised synthetic registrar state machine. Tests kill
the actual registrar process at CLAIM, DEFINITION, INVOCATION, PRE_BOOTSTRAP,
POST_BOOTSTRAP and PRE_REGISTRATION and join the original Phase A. The worker
job has neither `RunAtLoad` nor `KeepAlive`; registration precedes one explicit
kickstart. Exclusive run-claim and effect-entry objects guard effect entry,
and authenticated `completed` or `failed` state settles the service. The same
installed Swift worker is really invoked twice after success and twice after
failure, with no new claim, entry or effect.

The failure model is local and process-scoped. The session supervisor remains
alive; host restart, SSH reattachment, real launchd/bootout/reboot/root prompt,
Terminal, Xcode, simulator and privileged writer effects are not proved or
claimed. Focused results pass external 12/12 and installer 1/1. Complete
serial results pass external 347/347, installer 173/173, controller 743/743,
launcher 115/115, writer 227/227 and read-only generator 434/434. The six-file
serial aggregate passes 2039/2039 in approximately 594 seconds with zero
fail/cancel/skip/todo. Remote generator, schema, path derivation and input
contract remain read-only. No network, SSH, simulator, privilege/root write,
production, CI-3, stage, commit, push, external retry or cleanup occurred.
Status remains `STOP_PRE_AUTHORITY`, pending two fresh independent reviews.

## Successor round-8 remediation evidence — 1.7.23

This section supersedes the incompatible 1.7.22 process-ownership limits. A
separate Publisher 0 transport owner retains the fixture's sole child/session
while the session supervisor is killed and restarted at the three journal/ACK
windows and the three remote COMMIT boundaries. Local `COMMIT_DECIDED` is
durable before ACK. The remote then performs one no-replace hard link,
synchronizes the containing directory and emits an authenticated terminal
decision bound to the output and request hashes. No second transport, refetch
or effect is available.

Publisher 1 persists version-addressed `KICKSTART_DECIDED`, run-claim,
effect-entry and terminal state. A registrar restarted after kickstart joins
the original worker through an exclusive lock on immutable identity and does
not kickstart again. Worker death at run-claim or before effect-entry relaunches
the same continuation. Death after effect-entry or before terminal produces
`STOP_PARTIAL`; the effect is never replayed. Tests count physical kickstarts,
worker launches and effect entries.

The failure model remains local. It does not prove death/restart of the actual
SSH process, host reboot, external reattachment, real launchd/root prompt,
Terminal, Xcode, simulator or privileged publication. Round 8 focused results
pass 11/11 and predecessor regressions pass external 27/27 plus installer
14/14. Complete serial suites pass external 358/358, installer 173/173,
controller 743/743, launcher 115/115, writer 227/227 and read-only generator
434/434, with zero fail/cancel/skip/todo. Remote generator, schema, paths and
input contract remain read-only. No network, real SSH, admin/root, production,
CI-3, stage, commit, push, external retry or cleanup occurred. Status remains
`STOP_PRE_AUTHORITY`, pending two fresh independent reviews.

## Published successor and terminal stop evidence — 1.7.25

The semantic-safe successor authority was committed, pushed by fast-forward,
and read back from the remote. Both final independent reviews reported
`0 Critical / 0 Important`. Owner-only exact-blob materialization covered the
16 changed paths plus the inherited generator/test pair. The final published
aggregate passed `2052/2052` with zero fail/cancel/skip/todo. The operational
and semantic-preflight writers are distinct capability-separated binaries, the
installer was compiled from its exact published source, and the new Gate 0
passed with exit zero, empty stdout/stderr and an unchanged launcher.

The exact published executable was then invoked once in `--prepare`. It failed
closed before an attempt marker, claim, child process or production owner root
could be created because the required production frozen corpus is absent and
no published or authorized constructor exists for it. The missing corpus
includes real context, launch attestation, operation authority, Publisher0
Node/SSH payloads and operation authorities. Synthesizing those security and
future simulator/SSH bindings is not authorized. Publisher0 and Publisher1
remain `0/1`; operational network/SSH, admin prompt, simulator, root write,
remote read, CI-3 Task 2 and cleanup remain zero. Terminal status is
`STOP_DOCUMENTED`; the
unexecuted material next gate is
`AUTHORIZE_PRODUCTION_FROZEN_INPUT_CONSTRUCTOR_V1`.
