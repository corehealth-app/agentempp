# CI-3 Mac pre-Gate0 Git object bootstrap authority

## Operation

```text
OPERATION=RECONCILE_CURRENT_AUTHORITY_OBJECT_AVAILABILITY_WITH_PRE_NETWORK_MAC_GATE_0_ORDER
MODE=AUTHORING_ONLY
ARCHITECTURE=PRE_GATE0_GIT_OBJECT_BOOTSTRAP_V1
DATE_UTC=2026-09-01
```

This authority reconciles one circularity only. The Mac Gate 0 requires the
exact launcher bytes, but the user-supplied Mac STOP reports that the required
Git objects were not present locally and the predecessor prohibited every
network operation before Gate 0. The STOP is preserved; it was not rerun on
the VPS.

## Published lineage and preserved bundle

```text
TERMINAL_DOCUMENTATION_SHA=cc9e8c681d53689314f553c82624ec452b7d2542
TERMINAL_DOCUMENTATION_PARENT=7a929b0cebb28c339010dd5bf115e67b79523156
TERMINAL_DOCUMENTATION_TREE=4c6a77df2a9bbcefe47648b92cdecaf772494fa9
TERMINAL_DOCUMENTATION_SUBJECT=docs(ops): record canonical inputs and CI-3 bridge bundle
BRIDGE_CURRENT_AUTHORITY_SHA=7a929b0cebb28c339010dd5bf115e67b79523156
BRIDGE_CURRENT_AUTHORITY_PARENT=70a7d60dd9c4224e3be9072ce5fbd966bd534560
BRIDGE_CURRENT_AUTHORITY_TREE=902a89cab73ebe5ea78b246a9961aa20a6eaaf96
CI3_IOS_AUTHORITY_SHA=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
CI2_BASE=277873755bf29771a10b5f362b522c2e6a6c21d6
BRIDGE_AUTHORITY_PATH_COUNT=16
LAUNCHER_PATH=scripts/ci3/ci3-bridge-launcher.zsh
LAUNCHER_MODE=100755
LAUNCHER_BLOB=918de148626fbfa642a4ac97a1e2057092ecffb8
LAUNCHER_SHA256=7d4fd15564a90be5d6892ca04f03d85b7c2391a0eb9d3fffa1c2ea03adde5d1d
BRIDGE_REMOTE_GENERATION_ID=rb-b1ec265eb71070f50932a4d7af8af5fed4ba4937c8858319d3550b76a04880ad
BRIDGE_REMOTE_RECEIPT_SHA256=349842c03aaaa039ddaf0da9e14ccb6b7793618cb346ab301de7f45fa146c10d
BRIDGE_REMOTE_CONFIG_SHA256=5132de192dba24912d65aa61228606864e3e86a56c04593cf63126c66554ee2a
SYNTHETIC_CREDENTIAL_SHA256=d36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208
BRIDGE_REMOTE_BUNDLE_STATUS=PRESERVED_PASS
```

The VPS revalidated commit type, parent, tree, subject, all 16 ordered
authority paths with their Git modes/OIDs/SHA-256 values, and the physical
receipt/config hashes. It did not open the root-only inputs or credential and
did not execute generator, controller, launcher or writer.

## VPS manager preservation

The canonical manager baseline remained exact before authoring:

```text
MANAGER=/root/agentempp
MANAGER_BRANCH=codex/better-ahead-rebranding-design
MANAGER_HEAD=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
CANONICAL_STATUS_COMMAND=LC_ALL=C git status --porcelain=v1 -uall
CANONICAL_TOTAL_TRACKED_UNTRACKED=25/5/20
CANONICAL_PORCELAIN_SHA256=455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0
CANONICAL_TRACKED_DIFF_SHA256=7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb
CANONICAL_STAGED_DIFF_SHA256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

## Ruling: provenance network is not operational network

The Mac first performs a no-network availability decision against its local
object database for the object-bootstrap authority SHA supplied by this
handoff, its terminal-documentation parent, the current bridge authority and
the launcher blob. If all four exist and validate, the fetch count is zero. If
any is absent, one logical fetch is authorized:

```bash
GIT_TERMINAL_PROMPT=0 \
git -C /Users/eduardohenrique/Developer/bodyflow \
  -c maintenance.auto=false \
  -c gc.auto=0 \
  fetch \
  --no-tags \
  --no-recurse-submodules \
  origin \
  refs/heads/codex/better-ahead-rebranding-design:refs/remotes/origin/codex/better-ahead-rebranding-design
```

The origin must be exactly
`https://github.com/corehealth-app/agentempp.git`, with HTTPS scheme, exact
host/path, no userinfo, query, fragment or embedded credential in fetch/push
URLs. The refspec has no `+` and updates only the remote-tracking ref. Prune,
tags, submodules, shallow mutation, checkout, local-branch update, pull, merge,
rebase, network tracing and retry are prohibited. Output is sanitized and no
credential-helper data is reported.

This single fetch is `code-provenance network`: it may obtain only commits and
blobs through Git. It cannot connect operationally to the VPS, execute SSH,
read the bridge bundle/config/credential, open secrets, start the simulator,
create remote-read claims or mutate the CI-3 worktree. It does not count as the
operational network guarded by Gate 0.

## Readback and Gate 0 ordering

After zero or one fetch, require:

- the remote-tracking ref equals the new object-bootstrap authority;
- that authority has parent `cc9e8c681d53689314f553c82624ec452b7d2542`;
- bridge authority `7a929b0cebb28c339010dd5bf115e67b79523156` exists;
- launcher mode, OID and SHA-256 equal the frozen values above;
- the ordered 16-path bridge manifest is exact and every object has valid type
  and size;
- manager and CI-3 HEAD, worktree status and staging are byte-identical to
  their pre-fetch snapshots.

Any fetch failure/ambiguity, remote-tip mismatch, object/hash/type/size drift or
worktree/index mutation is `STOP_DOCUMENTED` before Gate 0, with no second
fetch, simulator, SSH or remote read.

Only after readback may the Mac materialize the exact launcher from the object
database and execute exactly:

```text
/bin/zsh -n <EXACT_MATERIALIZED_LAUNCHER>
```

The receipt binds this authority, the bridge authority, launcher blob/hash,
fetch count 0 or 1, remote-tracking ref, `/bin/zsh` identity, exit,
stdout/stderr counts, launcher identity before/after and
`network-after-bootstrap-before-gate0=false`. Exit must be zero, stdout and
stderr empty, and launcher identity unchanged. Failure has no retry and leaves
operational network, claims and reads at zero.

Gate 0 remains mandatory before simulator, bootstrap claim,
`/usr/bin/ssh -G`, SSH, the three remote reads, config/credential access and
any operational network. On PASS, the existing bundle/authority handoff
continues unchanged.

## Closed scenario matrix

| # | Scenario | Required result |
|---:|---|---|
| 1 | all objects local | fetch `0/1`; continue to readback |
| 2 | authority absent | exactly one bounded fetch |
| 3 | launcher absent | exactly one bounded fetch |
| 4 | fetch fails or is ambiguous | STOP before Gate 0 |
| 5 | remote tip differs | STOP |
| 6 | launcher hash differs | STOP |
| 7 | manager changes during fetch | STOP |
| 8 | CI-3 worktree changes during fetch | STOP |
| 9 | second fetch requested | reject |
| 10 | SSH before Gate 0 | reject |
| 11 | simulator before Gate 0 | reject |
| 12 | remote read before Gate 0 | reject |
| 13 | bootstrap and Gate 0 PASS | continue existing handoff |
| 14 | secret/config proposed as bootstrap input | reject |
| 15 | predecessor bridge execution proposed | reject |

## Review gates

Review A covered Git origin/refspec, one-fetch bound, object readback,
worktree invariance, no retry, no secret/runtime data and authority lineage.
Review B covered circularity resolution, unchanged Gate 0, operational
network ordering, simulator/SSH/read boundaries, receipts, STOP behavior and
continuation of the existing Mac handoff. Two ambiguities found during review
were corrected before publication: the local availability set now includes
this object-bootstrap authority, and all frozen object identities are written
in full. Final results:

```text
REVIEW_A_CRITICAL=0
REVIEW_A_IMPORTANT=0
REVIEW_B_CRITICAL=0
REVIEW_B_IMPORTANT=0
```

## External effects and next gate

```text
BRIDGE_REMOTE_BUNDLE_MUTATED=NO
SECRET_READ=NO
GENERATOR_CONTROLLER_LAUNCHER_WRITER_EXECUTED=NO
VERCEL_WRITE=NO
SUPABASE_WRITE=NO
DATABASE_WRITE=NO
PRIMARY_LIVE_WRITE=NO
PRODUCTION_WRITE=NO
MAC_EXECUTION=NO
CI3_TASK2_STARTED=NO
CI4_STARTED=NO
NEXT_ENVIRONMENT=MAC_LOCAL
NEXT_GATE=FETCH_VERSIONED_CI3_BRIDGE_BUNDLE_AND_RESUME_CI3
```
