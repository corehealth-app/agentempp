# CI-3 Mac executor compatibility authority

```text
PURPOSE=MAC_EXECUTOR_AUTHORITY_V1
DATE_UTC=2026-09-01
MODE=AUTHORING_ONLY
AUTHORITY_PARENT=65a06d3e7426117ea80679933f6a7bb611be5988
AUTHORITY_SUBJECT=build(ops): authorize mac-compatible CI-3 bridge executor
AUTHORITY_SHA=UNKNOWN_UNTIL_COMMIT
REMOTE_BUNDLE_PREDECESSOR=7a929b0cebb28c339010dd5bf115e67b79523156
REMOTE_BUNDLE_COMPATIBILITY=REUSE_READ_ONLY
```

The Mac executor and the preserved remote bundle are two distinct authorities.
The executor commit is intentionally absent from its own blobs: publication must
prove the commit parent, subject, tree and ordered manifest after the commit is
created. The remote bundle remains bound to its predecessor and is not regenerated,
read or mutated by this authoring task.

## Preserved STOP and complete failure accounting

The fresh Mac compatibility baseline stopped with 1,409 tests: 1,323 passed,
86 failed, zero skipped and zero todo. The owner-only failure manifest records
86 unique identifiers, 86 classified and zero unresolved. No expected failure
or warning conversion was used.

| Group | Count | Platform class | Proven cause |
| --- | ---: | --- | --- |
| `RC1_DARWIN_DESCRIPTOR_HELPER_UNMATERIALIZED` | 3 | `MAC_OPERATIONAL` | Darwin correctly requires a hash-bound descriptor helper, while the test harness supplied `null`. |
| `RC2_WRITER_FIXTURE_AUTHORITY_MANIFEST_PATH_OMISSION` | 75 | `CROSS_PLATFORM_PROTOCOL` | The writer fixture omitted the deployment-receipt evidence path; once reached, it also lacked the already-required `synthetic_marker_sha256` receipt field. |
| `RC3_PHYSICAL_MODE_ASSERTION_CONFLATES_GIT_AND_OWNER_ONLY_MODES` | 1 | `MAC_OPERATIONAL` | A physical `0700/0600` fixture was compared with Git executable-bit semantics; physical owner-only and exact Git modes are now separate assertions. |
| `RC4_GIT_READER_ROOT_ONLY_REPOSITORY_IDENTITY_WITHOUT_MAC_UID_BINDING` | 7 | `VPS_OPERATIONAL_AND_MAC_OPERATIONAL` | The default reader was root-only. The complete Mac cause also included the strict version grammar not accepting the attested Apple Git suffix. |

The focused REDs reproduced `3/3`, `1/1`, `1/1` and `8/8` failures for
RC1, RC2, RC3 and RC4 respectively. The corresponding GREENs require a real
synthetic Swift descriptor helper, the complete writer fixture, exact owner-only
physical modes plus exact Git modes, and an explicit current-UID Mac repository
policy whose root hash and policy hash are attested. Final full-suite totals are
recorded only after fresh verification.

## Frozen 17-path executor manifest

The executor authority contains exactly these ordered paths:

1. `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`
2. `docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md`
3. `docs/superpowers/evidence/2026-08-31-ci3-bridge-git-blob-reader-stop-and-authority.md`
4. `docs/superpowers/evidence/2026-08-31-ci3-deployment-receipt-reconciliation-authority.md`
5. `docs/superpowers/evidence/2026-08-31-ci3-env-receipt-reconciliation-authority.md`
6. `docs/superpowers/evidence/2026-09-01-ci3-mac-executor-compatibility-authority.md`
7. `docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md`
8. `docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md`
9. `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`
10. `scripts/ci3/create-ios-staging-bridge-config.mjs`
11. `scripts/ci3/create-ios-staging-bridge-config.test.mjs`
12. `scripts/ci3/ci3-bridge-controller.mjs`
13. `scripts/ci3/ci3-bridge-controller.test.mjs`
14. `scripts/ci3/ci3-bridge-launcher.zsh`
15. `scripts/ci3/ci3-bridge-launcher.test.mjs`
16. `scripts/ci3/ci3-terminal-anchor-writer.swift`
17. `scripts/ci3/ci3-terminal-anchor-writer.test.mjs`

Package and lockfiles are outside the authority and remain unchanged.

## Dual attestation and compatibility ruling

The launch attestation binds the successor executor directly and binds the
remaining dual-authority roots transitively through the exact 17-path manifest.
That manifest includes this evidence contract and the controller/writer sources
that freeze the predecessor, object-bootstrap lineage and CI-3 base. The
bootstrap claim records the launch-attestation hash plus one canonical
`CI3_MAC_DUAL_AUTHORITY_ROOTS_V1` digest over executor, launch attestation,
remote predecessor, remote generation, remote receipt/config hashes,
object-bootstrap authority and CI-3 authority/base. Read claims bind the
bootstrap hash; the local receipt repeats the launch and dual-root hashes; the
terminal evidence chain binds both receipts. No raw path, credential or secret
value is part of this root set.

The writer independently reconstructs the same digest from the actual evidence
objects before accepting the local receipt. Eight isolated mutation-negative
tests cover every root. Controller and writer still reject a remote receipt that
tries to substitute the new executor as the remote bundle authority.

```text
REMOTE_GENERATOR_CREATION_SEMANTICS_CHANGED=NO
REMOTE_CONFIG_SCHEMA_CHANGED=NO
REMOTE_RECEIPT_SCHEMA_CHANGED=NO
REMOTE_GENERATION_OR_PATH_DERIVATION_CHANGED=NO
FIVE_INPUT_CONTRACTS_CHANGED=NO
REMOTE_CLAIM_OR_PUBLICATION_SEMANTICS_CHANGED=NO
REMOTE_BUNDLE_COMPATIBILITY=REUSE_READ_ONLY
```

The Linux/root create dispatcher and `parseMode()` contract remain unchanged.
The Mac repository policy is explicit, Darwin-only, current-UID-bound,
root-path-hash-bound and self-attested; absence still selects the root-only
policy. A separate Darwin-only runtime dispatcher consumes one private
object-bootstrap request. The request binds the executor commit, exact single
parent/lineage digest, tree, subject hash, ordered 17-path manifest root and the
target mode/path/OID/content. Commit/tree and every `ls-tree` entry are proved
before body reads; every manifest body is then content-verified by the bounded
reader and only the requested target is materialized no-clobber as `0600`.
Success is deliberately silent on stdout/stderr and creates no standalone Mac
receipt. The versioned `/bin/zsh -n` Gate 0 launch attestation is the first
receipt and its hash is consumed by bootstrap, local receipt and writer.

## Preserved protocol invariants

- exactly three remote reads, each claimed before its single body read;
- zero retry, refetch, fourth read, retroactive claim, service-role emission or raw values;
- writer no-follow/no-clobber, receipt-last, exact-existing and immutable anchor;
- six independent scans and the full controller transition coverage;
- the remote generator/config/receipt/input/path and publication semantics remain read-only.

## New Gate 0 rule and external boundary

The historical Gate 0 receipt cannot authorize this executor. After publication,
the exact new executor blobs and 17-path manifest must be materialized and a new
`/bin/zsh -n` Gate 0 receipt produced before simulator, `/usr/bin/ssh -G`, SSH,
claims or the three reads. Failure stops without retry.

```text
OLD_GATE_0_REUSE=FORBIDDEN
OPERATIONAL_NETWORK=0
SIMULATOR_EXECUTIONS=0
SSH_CONNECTIONS=0
FORBIDDEN_LOCAL_SSH_G_TEST_BEFORE_REMEDIATION=OBSERVED
FORBIDDEN_LOCAL_SSH_G_TEST_IN_FINAL_SUITE=NO
REMOTE_READS=0
PRIVILEGE_PROMPTS=0
CI3_WORKTREE_MUTATIONS=0
PRODUCTION_MUTATIONS=0
CLEANUP_DEADLINE=2026-09-11T11:44:11.182Z
```

## Pre-review verification evidence

Before Review B round 1, the combined Mac authority suite passed 1,412/1,412 tests with zero
failures, cancellations, skipped tests or todo tests in 390,713.02375 ms. This
exceeded the 1,409-test owner baseline because three fail-closed contract tests
cover invalid policy rejection, operational Mac policy derivation and the
dual-authority boundary.

```text
NODE_SYNTAX=PASS (6 files)
GENERATOR_SELF_TEST=PASS (8 checks, network_calls=0)
LAUNCHER_ZSH_SYNTAX=PASS
SWIFT_WRITER_EXACT_COMPILE=PASS
FOCUSED_RC1=PASS (3/3)
FOCUSED_RC2=PASS (1/1)
FOCUSED_RC3=PASS (2/2 physical and Git-mode assertions)
FOCUSED_RC4=PASS (8/8 including invalid-policy rejection)
FOCUSED_OPERATIONAL_READER=PASS (1/1, all 71 roles)
FULL_FOUR_FILE_SUITE=PASS (1412/1412 under umask 077)
DIFF_CHECK=PASS
CHANGED_PATHS=17
```

The aggregate suite exposed two additional authority-fixture mismatches after
the subject changed: Publisher 0 expected the new subject hash while the shared
fixture still emitted a placeholder, and Publisher 1 still expected that
placeholder after the fixture was corrected. Each was reproduced focused, the
shared executor subject hash became the single fixture source, and both
Publisher tests passed together before the final full run. Production validators
were not weakened.

Added-line scans found no credential/private-key/JWT payload, real IP/origin,
blanket platform bypass, skip/todo/expected-failure mechanism, swallowed
assertion, unbounded body, retry/fourth read/retroactive claim, mutable marker,
arbitrary privileged output or old Gate 0 reuse. Mentions of CI-4, production,
skip/todo and operational-risk terms in this authority are explicit prohibitions
or baseline counts. Diff review found no package/lockfile, schema, input,
claim/publication or unrelated change.

This authority remains unstaged and uncommitted. Independent reviews are still
required before staging. No publication, push, fetch, external read or operation
was performed.

## Post-review deterministic stabilization

An independent owner-safe controller run exposed one failure in the writable
runtime negative test. Its wrapper inherited `umask 077`, so
`mkdir(mode: 0777)` physically produced `0700`, a mode intentionally allowed by
production. The test now applies explicit `chmod(0777)`, asserts the exact low
bits and then requires `DESCRIPTOR_CHAIN`. Before the fix, three bounded runs
passed under `022` and three failed under `077`; the deterministic fixture RED
observed physical `0700` instead of `0777`. After the fix, three runs under each
umask passed. Production validation did not change.

Review also proved that the attested Mac repository policy was previously used
only by direct low-level tests. The operational authority reader now derives one
explicit current-UID/root-hash attestation on Darwin and propagates the same
policy through every bounded generator, manifest and predecessor read. Non-Mac
callers still pass no policy and retain the byte-compatible root-owned default.
The complete focused Git-reader corpus passed `50/50`.

The earlier full suites also contained a test that invoked local
`/usr/bin/ssh -G`. It did not connect to a host or perform network, but the
invocation itself violated this authoring task's pre-Gate0 boundary. The test is
now adapter-only: it validates the exact executable, argv, closed environment,
buffer bound, parser, duplicate ordering and policy with a deterministic native
fixture. The final full suite selected only that adapter path and made no real
ssh-G subprocess call. The operational default remains available only to the
post-Gate0 controller path.

Finally, the strengthened physical-mode test recovered its original owner
identifier literally. A sanitized exact-name gate selected all `86/86` owner
manifest identifiers and passed all 86 under `umask 077`, with zero skip/todo.
The fresh pre-review four-file gate then passed `1412/1412`, zero
fail/cancel/skip/todo, in `390713.02375 ms` under the same owner-safe umask.

## Review B round-1 technical remediation

The review traced one special-case line in `launcherStructuralSkeleton()` into
the Linux/root create path. A focused RED proved that a new remote-authority
declaration outside the three frozen literal regions was incorrectly erased.
The exception and the unused launcher constant were removed. The entire
normalizer is now byte-identical to its predecessor implementation, the current
launcher still matches the preserved skeleton, and the old remote bundle can be
consumed without rerunning its generator.

The launch/bootstrap/local chain now uses the dual-root digest described above.
Focused RED was `10/10` failures before the builder/validator existed; GREEN was
`10/10`, including one mutation-negative case for every root. The writer fixture
then failed `TERMINAL_SEMANTICS_BOOTSTRAP` until the Swift validator independently
reconstructed the digest and required the local receipt to repeat it.

The prior operational Mac policy had no reachable Mac caller. The new local E2E
first failed with the dispatcher rejecting the Mac mode, then passed after the
Darwin-only object-bootstrap route was wired. The E2E invokes a fresh Node
process against a current-UID local repository with a real two-commit lineage
and 17-path tree, materializes exactly one launcher, requires empty
stdout/stderr and applies `/bin/zsh -n` to those exact bytes. Independent
mutations cover commit, parent/lineage, tree, subject hash, manifest root, path,
OID, mode, content binding and existing destination. Linux still rejects the
mode and retains the prior root-only create modes. No SSH, fetch, simulator or
remote read is used by this route.

## Superseded round-1 local verification

After all three remediations and documentation changes, the focused cumulative
gate passed `28/28` and the complete generator file passed `431/431`. The full
four-file Mac authority suite then passed under `umask 077`:

```text
tests=1426
pass=1426
fail=0
cancelled=0
skipped=0
todo=0
duration_ms=354492.223292
```

The exact owner manifest is rechecked separately as `86/86`. Static syntax,
Swift compilation, diff/allowlist and added-line safety scans remain mandatory
after this evidence text is finalized. No tracked production code changes occur
after the full-suite result above.

## Review-B round-2 remediation

The Apple Git suffix is no longer part of the default grammar. The exact
predecessor grammar is selected whenever repository policy is absent; the
Apple form is reachable only after the Darwin policy has passed its platform,
UID, repository-root and attestation checks. Focused negative/positive tests
freeze that split while `parseMode()`, the Linux/root create dispatcher and all
remote generator schemas remain unchanged.

The orphan-blob E2E and isolated object-bootstrap receipt were removed. The V2
private request now proves the published executor Git provenance and complete
17-path content set before writing one target. The CLI emits no success output;
the materialized launcher is immediately syntax-checked in the local E2E, and
the existing Gate 0 launch attestation remains the only versioned receipt that
the downstream dual-root chain consumes. The controller mutation matrix derives
its indices from `AUTHORITY_PATHS.length`, including both final paths.

Fresh round-2 verification passed `50/50` focused, `434/434` generator,
`751/751` controller, exact owner identifiers `86/86` and the full four-file
suite `1460/1460` under `umask 077`, with zero fail/cancel/skip/todo. Static and
added-line scans are recorded in the task report.

## Published execution and terminal STOP

The successor authority was committed with the required parent and subject,
its exact 17-path manifest was pushed fast-forward, and remote readback matched
the local commit. Two final independent reviews reported zero Critical and zero
Important findings. The remote compatibility verdict remains
`REUSE_READ_ONLY`; no remote bundle byte or contract was changed.

The exact published blobs were materialized from the local object database with
exclusive owner-only writes, no symlinks, fsync and readback. The published
four-file suite passed `1460/1460`, with zero fail/cancel/skip/todo, and the
published Swift writer compiled. No second Git fetch occurred. A new Gate 0 ran
`/bin/zsh -n` against the exact published launcher, returned exit 0 with empty
stdout/stderr and produced a new versioned owner-only receipt while preserving
the historical receipt.

The post-Gate-0 external-authority preflight found no installed immutable
root-owned Publisher 1 bootstrap and no installed controller authority at the
fixed external root. The launcher is designed to reject every operational mode
outside that separately authenticated chain. Its issuer/materializer/runtime
inputs are not present on this Mac, so manufacturing a substitute from the Git
worktree would violate the reviewed contract. The terminal result is therefore
`STOP_PRE_AUTHORITY`.

Simulator, real `ssh -G`, SSH, claims, all three remote reads, local bundle,
simulator credential installation, six scans, privileged writer, terminal
anchor and CI-3 Tasks 2–12 were not executed. The remote bundle, fixture, five
CI-3 paths and all predecessor evidence remain preserved. There were no writes
to VPS, Supabase, Vercel, database or production and no cleanup or next gate.
Pre-publication tooling accidentally displayed local commit metadata and
non-secret identifiers; this evidence records the output-discipline deviation
without repeating any value. No config, credential or token value was fetched
or transferred.

The next gate is external provisioning of the authenticated immutable
Publisher 1 bootstrap for this same Mac executor authority. Only then may the
existing successor Gate 0 evidence authorize the ordered operational sequence.

## Semantic-safe successor compatibility addendum

The published Mac executor remains read-only predecessor evidence and its
`STOP_PRE_AUTHORITY` result remains valid. This local successor does not treat
the historical Gate 0 as transferable. Compatibility requires a fresh Gate 0
after the exact successor blobs and their suites are verified, and before any
Publisher 0, simulator, SSH or administrative capability.

The successor changes only the allowed local executor/controller/launcher/
writer chain. It does not regenerate or modify the remote generator, bundle
schema, remote path derivation, Node capsule or input contract. The generator
continues as a separately authenticated predecessor dependency; the controller
manifest remains exactly sixteen targets.

Mac-local compatibility is established by compiling separate validation and
operational binaries from the same exact Swift writer source. The validation
binary has only semantic-preflight capability and emits sanitized stdout; the
controller persists and reads back those exact bytes. The operational binary
cannot run preflight. Phase A then installs only the exact installer as
root-owned immutable self, and only that self may enter Phase B and touch the
Publisher 1 target after claim.

The installer is selected by an independent compile authority that binds the
reviewed source, fixed driver, selected compiler, compile arguments/toolchain
provenance and expected binary digest. Human authorization and Swift preflight
carry the authority and expected digest into Phase A, which rejects any
self-consistent alternate source/sidecar pair. The successor canonicalizer
uses explicit UTF-8 key order and is byte-equality tested between JS and Swift
with digit/underscore adversarial keys. Compatibility is limited to the exact
successor schema; additional keys are rejected.

The corrected order produces Publisher 0 artifacts before transport/consumption,
then creates the owner-only receiver and independent request, records human
authorization and final identities, runs semantic preflight, completes the
two installer phases and readback, publishes operation authority, reads back
all sixteen controller targets, settles, and only then permits later simulator
gates. Privileged-writer authority is reachable after six scans; terminal
authority remains unreachable before all six.

The 1.7.16 focused checkpoint passed 56 state-order, 54 semantic-seam, 10
immutable-installer, 3 no-preseed/real-wiring, 7 preserved-negative and 5
controller/downstream tests, plus one independent installer-selection negative.
Its complete pre-review runs were 282/282 external, 153/153 installer, 215/215
writer and 1501/1501 four-file Mac authority tests, all with zero failure,
cancellation, skip or todo. Those are historical review inputs, not the
1.7.17 remediation result. Unit concurrency made both long runs reliable
without weakening timeouts or assertions. Published counts
223, 143, 161 and 1460 remain historical labels. No remote read, network, SSH,
simulator,
administrative prompt, root write, production action, CI-3 continuation,
retry or cleanup occurred. The recorded cleanup deadline remains unchanged.

## Successor review compatibility addendum — 1.7.17

Compatibility now requires exact successor parent/subject lineage at launcher
and controller; predecessor authority is rejected. Publisher 0 has a causal
zero-preseed start, with authenticated producer output captured before receiver
consumption. The independent human V2 authorization is issued only after the
request and binds authority, request, receiver, sixteen leaves, Git-bound
installer provenance and one non-administrative prompt budget.

The sole first privileged boundary is the fixed macOS system driver, invoked
after semantic preflight and boundary reobservation of request, receiver and all
leaves. It runs the exact Git path/blob-OID-bound supervisor Swift bytes. The
protocol has no mutable candidate selection, verify/execute path split or
`argv[0]` trust. Phase A installs the immutable fixed self for Phase B;
deterministic recovery before/after freeze neither cleans, refetches nor retries.

The shared Swift validator enforces the complete versioned V2 exact schema and
all relations. JS/Swift mutation parity rejects 97 missing-field and 6
extra-field variants. A real production consumer proof authenticates the input
chain, human receipt and operation authority, readbacks exactly sixteen
targets, persists settlement and reaches the later writer authority. Its seam
is limited to privileged/root I/O and does not manufacture semantic receipts.

The current focused 1.7.17 proof is 150/150: 1 launcher-lineage, 10 controller,
70 external, 13 installer and 56 writer tests, with zero failure, cancellation,
skip or todo. Final serial suites passed external 293/293, installer 156/156,
controller 740/740, launcher 115/115, writer 217/217 and generator 434/434.
An initial aggregate 1505/1506 exposed a launcher skeleton divergence; the
predecessor structure and assertions were preserved, and the final aggregate
passed 1506/1506 with zero fail/cancel/skip/todo. Remote
generator, bundle schema, path derivation and input contract remain read-only;
no network, SSH, simulator, administrative prompt, real privilege, root write,
production, CI-3, stage, commit, push, retry or cleanup occurred. Compatibility
remains local `STOP_PRE_AUTHORITY` evidence only.

## Successor round-2 compatibility addendum — 1.7.18

This addendum supersedes incompatible 1.7.17 compatibility claims. The macOS
boundary now goes through the bounded subprocess implementation with the exact
`swift - --privileged-supervisor` delimiter, LF/NUL-free arguments, one prompt
and atomic fixed-image selection. Local tests replace only spawn/privilege;
they never request administrator access.

The P0 bootstrap derives its helper from exact Git-bound blobs, while receive
is builtin and production verify targets the launcher installed by the
nine-entry immutable bootstrap. An absent executable consumes no attempt. The
authority projection is authenticated from the signed pass and current-user
published records, so fixed root paths may be absent before preflight. The
operation request is created only after Phase B PASS/readback.

Recovery is causal and operation-specific. The Phase A promotion/freeze gap is
recoverable only for the exact authenticated generation. Verify recovery must
observe its own controller claim, result, sixteen-target tree and settlement;
Phase B state alone is rejected, and partial/divergent state never respawns,
retries, refetches, prompts or cleans. The exact shared V2 validator rejects a
literal 103 mutations (97 missing, 6 extra) with JS/Swift parity.

Current complete results are external 304/304, installer 158/158, controller
743/743, launcher 115/115, writer 227/227 and read-only generator 434/434;
the current aggregate is 1981/1981, all with zero fail/cancel/skip/todo.
Generator, bundle schema, path derivation and input contract remain read-only.
No network, SSH, simulator, administrator prompt, real privilege, root write,
production, CI-3, stage, commit, push, retry or cleanup occurred. Compatibility
remains local `STOP_PRE_AUTHORITY` evidence.

## Successor round-3 compatibility addendum — 1.7.19

This addendum supersedes incompatible 1.7.18 compatibility claims. Publisher
0's one production-shaped transport begins with every remote successor root
absent and invokes only the fixed system shell. Its stdin contains the exact
Git bytes, manifest, provenance and eleven authority inputs needed to
materialize, reopen and freeze the controller/tool inside that same session
before the controller executes. The controller then creates the versioned
claim first, generates the owner-restricted Ed25519 key, and produces issuer,
unsigned request and payloads before publishing the signed pass, manifest and
transport receipt last. The test remote begins empty and no real SSH occurs.

The bounded transport journals authenticated stdout exclusively with owner-only
mode and synchronization before settlement is returned. Exact journal evidence
allows local capture recovery after an outer crash without a second transport.
The privileged handoff similarly retains one supervisor across Phase A and
Phase B under one prompt. Exact Phase A plus absent Phase B resumes through the
already-running supervisor; a partial/divergent Phase B stops without another
prompt, Phase A or supervisor.

The installed-launcher proof executes the actual zsh launcher and installed
Node controller. Its request is derived from the fixed installed version root,
not an ambient descriptor. The real no-effect consumer readbacks sixteen
targets, settles the controller transaction, calls all six scan functions and
reaches later-writer authority while terminal mode remains denied. Restoring
the launcher's predecessor skeleton keeps the read-only generator contract
intact.

Current complete results are external 311/311, installer 158/158, controller
743/743, launcher 115/115, writer 227/227 and read-only generator 434/434. The
serial aggregate passes 1988/1988 in 711.07 seconds, with zero
fail/cancel/skip/todo and no timeout. Generator, bundle schema, path derivation
and input contract remain read-only. No network, SSH, simulator, administrator
prompt, real privilege, root write, production, CI-3, stage, commit, push,
retry or cleanup occurred. Compatibility remains local
`STOP_PRE_AUTHORITY` evidence.

## Successor round-4 compatibility addendum — 1.7.20

This addendum supersedes incompatible 1.7.19 compatibility claims. Publisher
0's materializer now uses exclusive/no-follow creation, file and directory
synchronization, freeze-flag and full physical-identity readback, an exact-tree
check and descriptor-pinned controller/runtime execution. Its transaction root
is atomically absent-to-created with the claim first; every preexisting root
must validate the original exact claim before key, issuer, payload or any other
artifact can be read or written.

The single-session distributed boundary uses PREPARED, a synchronized
authenticated local journal, a synchronized local ACK and only then remote
commit. Local causal receipts are staged owner-only, file-synced, atomically
promoted and parent-synced, and the broker publishes QUIESCED last before the
outer entrypoint returns. All three prepared-to-ACK kill windows recover from
the original local decision without another transport or effect.

Inside the one privileged protocol, Publisher 1 establishes a root-owned,
version-addressed persistent continuation bound to immutable self and claim.
Killing the original supervisor in the synthetic test does not create another
prompt or Phase A: the registered continuation completes Phase B. An
authenticated pre-Phase-B barrier makes partial/divergent observation
deterministic. The installed-launcher E2E crosses actual zsh and Node/controller
dispatch, six scanners consume actual serialized produced surfaces, sixteen
targets are read back and the real later-writer dispatch is reached while
terminal mode remains denied.

Current complete results are external 322/322, installer 159/159, controller
743/743, launcher 115/115, writer 227/227 and read-only generator 434/434. The
serial aggregate passes 2000/2000 in 811.70 seconds, with zero
fail/cancel/skip/todo. Literal JS/Swift mutation parity remains 103 = 97 + 6.
Generator, bundle schema, path derivation and input contract remain read-only.
No network, SSH, simulator, administrator prompt, real privilege, root write,
production, CI-3, stage, commit, push, retry or cleanup occurred. Compatibility
remains local `STOP_PRE_AUTHORITY` evidence pending two fresh reviews.

## Successor round-5 compatibility addendum — 1.7.21

This addendum supersedes incompatible 1.7.20 compatibility claims. The fixed
Publisher 0 primitive runs before Node/controller and binds creation,
same-descriptor hashing/fstat/synchronization/freeze/readback and execution to
the exact physical bootstrap objects. Tests reject unclaimed preexisting
roots, open-to-hash and hash-to-exec pathname swaps, directory swaps and extra
leaves without normalizing attacker-provided metadata.

PREPARED is nonterminal. The local journal and ACK must be durable before the
fixture's remote terminal publication, and a version-addressed continuation
owns its sole transport while broker and outer are killed in the three required
windows. Owner-only receipts publish with an exclusive-link no-replace step
and synchronized parent; a concurrent divergent destination stops closed.

Publisher 1 control objects are exact and immutable, the launchd definition is
one-shot without KeepAlive, and the synthetic seam covers supervisor death at
CLAIM, DEFINITION, BOOTSTRAP and REGISTRATION plus one invocation after
failure. The installed-launcher E2E crosses the fixture's actual zsh and
Node/controller path. Its six collectors consume serialized surfaces produced
by that execution, the controller observes sixteen targets, and the real
`publishPrivilegedWriterAuthority` consumer runs with only its lower effect
boundary replaced.

Compatibility evidence remains local and production-shaped, not an execution
of real SSH/remote host restart, launchd/reboot/root prompt, Terminal, Xcode or
simulator. Current complete results are external 337/337, installer 172/172,
controller 743/743, launcher 115/115, writer 227/227 and read-only generator
434/434. The serial aggregate passes 2028/2028 in 953.86 seconds with zero
fail/cancel/skip/todo. Literal JS/Swift mutation parity remains 103 = 97 + 6.
Generator, bundle schema, path derivation and input contract remain read-only.
No network, SSH, simulator, administrator prompt, real privilege, root write,
production, CI-3, stage, commit, push, retry or cleanup occurred.
Compatibility remains `STOP_PRE_AUTHORITY` pending two fresh reviews.

## Successor round-7 compatibility addendum — 1.7.22

This addendum supersedes incompatible 1.7.21 one-shot and durability claims.
The local Publisher 0 PREPARED tree is synchronized, mode-frozen and read back
before ACK. A version-addressed local session supervisor retains the sole
fixture transport while journal workers are killed and restarted in all three
authenticated windows. Terminal COMMIT is the final no-replace hard link;
PREPARED remains on the same inode with `nlink=2`.

The Publisher 1 worker definition contains neither `RunAtLoad` nor
`KeepAlive`. A supervised registrar resumes the same Phase A after actual
registrar death at six pre-registration boundaries, then registration precedes
one explicit kickstart. Exclusive run-claim/effect-entry objects and terminal
`completed`/`failed` settlement stop reload/reinvoke equivalents. The tests
execute the same installed Swift worker twice after each terminal outcome and
observe zero new entry/effect.

Compatibility evidence is local only: the session supervisor stays alive and
there is no real host restart, SSH reattachment, launchd/bootout/reboot/root
prompt, Terminal, Xcode, simulator or privileged effect. Focused results pass
external 12/12 and installer 1/1. Complete serial results pass external
347/347, installer 173/173, controller 743/743, launcher 115/115, writer
227/227 and read-only generator 434/434. The serial aggregate passes 2039/2039
in approximately 594 seconds with zero fail/cancel/skip/todo. Literal JS/Swift
mutation parity remains 103 = 97 + 6. Generator, bundle schema, path derivation
and input contract remain read-only. No external effect occurred and status
remains `STOP_PRE_AUTHORITY` pending two fresh reviews.

## Successor round-8 compatibility addendum — 1.7.23

Publisher 0 compatibility now separates the persistent fixture transport
owner from the killable session supervisor. The sole child/session survives
supervisor death at all three journal/ACK and all three remote terminal
boundaries. After durable local `COMMIT_DECIDED` and ACK, the remote performs
one no-replace hard link, fsyncs its directory and emits the exact authenticated
terminal decision last. There is no second transport or effect.

Publisher 1 persists `KICKSTART_DECIDED`, run-claim, effect-entry and terminal
state. A recovered registrar joins the already kicked worker through an
exclusive immutable-identity lock. Pre-effect worker death resumes the same
continuation; post-effect-entry death is a terminal `STOP_PARTIAL` boundary
with no effect replay. Physical tests count one kickstart and at most one
effect entry.

Compatibility evidence remains local-only and does not establish actual SSH
process restart/reattachment, host reboot, real launchd/root prompt, Terminal,
Xcode, simulator or privileged publication. Focused Round 8 passes 11/11;
predecessor regressions pass external 27/27 and installer 14/14. Complete
serial suites pass external 358/358, installer 173/173, controller 743/743,
launcher 115/115, writer 227/227 and read-only generator 434/434, with zero
fail/cancel/skip/todo. Literal JS/Swift mutation parity remains 103 = 97 + 6.
Generator, schema, paths and input contract remain read-only. No external
effect occurred and status remains `STOP_PRE_AUTHORITY` pending two fresh
reviews.

## Successor round-9 compatibility addendum — 1.7.24

Publisher 1 compatibility now separates the persistent version-addressed
activation owner from the killable registrar. Durable owner identity, claim,
exclusive lock and ready handshake precede the activation signal. The owner
alone issues the physical kickstart and monitors worker recovery. Registrar
restart before the signal or after accepted start but before the worker-launch
receipt rejoins that same owner and cannot infer a missing kickstart from a
missing receipt. The worker plist remains free of `RunAtLoad` and `KeepAlive`.

The focused proof progressed from RED 0/2 to GREEN 2/2 by killing the actual
registrar PID at both new boundaries. It preserves one owner PID and observes
one executable kickstart, one worker launch, at most one effect entry and a
deterministic terminal result. Round 8 predecessor proofs pass 11/11; impacted
regressions pass 4/4, 4/4 and 6/6; installer passes 173/173. Swift typechecks
and Node syntax pass. Complete suites pass external 360/360, installer
173/173, controller 743/743, launcher 115/115, writer 227/227 and read-only
generator 434/434. The serial aggregate passes 2052/2052 in approximately
1156.5 seconds with zero fail/cancel/skip/todo.

This is local synthetic compatibility evidence. Activation-owner death, host
reboot/reattachment, actual launchd/root prompt, Terminal, Xcode, simulator and
privileged publication are not proved. Literal JS/Swift mutation parity
remains 103 = 97 + 6. Generator, schema, paths and input contract remain
read-only; no external effect occurred and status remains
`STOP_PRE_AUTHORITY`.
