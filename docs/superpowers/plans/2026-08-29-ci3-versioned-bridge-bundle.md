# CI-3 Versioned Bridge Bundle — executable two-environment plan

> **Status:** Bridge V2 authority may be published and executed once on the
> VPS. The launcher and all subsequent CI-3 work remain deferred to the Mac.

## 1. Global invariants

- Architecture is `VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING`.
- No raw origin/destination/host/IP/key/credential/token/PII/ID is printed.
- `--create`, SSH, network, simulator, stream, install, Task 2+, cleanup,
  provider, production and CI-4 are zero in this operation.
- Five CI-3 working paths stay on CI2 HEAD with empty staging.
- Every O_EXCL claim is attempt one/no retry. Recovery uses durable local
  evidence only and never refetches.
- Missing concrete controller/VPS PASS values STOPs; no operator-supplied
  fallback or old V1/V2/V3 trust material is allowed.

## 2. Phase A — VPS, remote versioned artifact

### A0. Verify final controller authority and snapshot launcher

The future VPS controller supplies `CONTROLLER_PASS.authority_sha`, plus
parent/tree/subject and all seven Git path hashes. Before real reads:

```text
/usr/bin/git rev-parse HEAD
/usr/bin/git rev-parse HEAD^
/usr/bin/git rev-parse HEAD^{tree}
/usr/bin/git show -s --format=%s HEAD
/usr/bin/git rev-parse "$AUTHORITY_SHA:scripts/ci3/create-ios-staging-bridge-config.mjs"
/usr/bin/git cat-file blob "$AUTHORITY_SHA:scripts/ci3/create-ios-staging-bridge-config.mjs"
```

Require parent `9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52`, subject
`build(ops): authorize executable CI-3 bridge tooling`, exact tree/path hashes
from controller PASS and independently recomputed Git blob/file hashes.

The trusted inline Node-core launcher receives only the controller-verified
authority SHA. It performs `lstat/open(O_NOFOLLOW)/open(wx,0600)/write/fsync/
close/fsync-directory`, writes the `git cat-file` bytes to the exact
`.launchers/AUTHORITY_SHA/create-ios-staging-bridge-config.mjs` path, verifies
full physical identity, then invokes:

```text
"$VPS_NODE_PATH" "/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA/create-ios-staging-bridge-config.mjs" --create
```

The generator has no third mode. Direct worktree `--create`, worktree
`hash-object`, pathname reopening or snapshot replacement STOPs.

### A1. Local-only gates

Run from the committed checkout before launcher creation:

```text
node --check scripts/ci3/create-ios-staging-bridge-config.mjs
node --test scripts/ci3/create-ios-staging-bridge-config.test.mjs
node scripts/ci3/create-ios-staging-bridge-config.mjs --self-test
```

Require `126 pass / 0 fail / 0 skipped / 0 todo`, self-test local/synthetic and
`network_calls=0`. This A1 never opens the five real inputs.

### A2. Claim, capture and semantic validation

The generator validates the five exact fixed paths/hashes from the spec.
Before staging it creates/fyncs deterministic
`AUTHORITY_SHA.claim.json` with `O_EXCL|O_NOFOLLOW`, attempt one, no retry and
authority/source/config/receipt hashes. It validates full file/parent metadata
and every schema/purpose/ref/URL/origin/implementation/count/provisioning
relation. Primary denylist is never opened.

If a claim preexists, no source is reread. Recovery uses captured staging/final
only. Claim without capture STOPs; no budget reset.

### A3. Publish with kernel no-replace

Create deterministic `0700` staging and `0600` config/receipt O_EXCL, fsync
them, then create final `0700` O_EXCL. Promote config by `link(2)` no-replace,
de-link only the staging hardlink and prove final `nlink=1`. Promote the
already-fsynced receipt last in the same way. Receipt is the atomic logical
commit marker. Fsync final and parent. Preserve claim/staging evidence.

Do not overstate physical visibility: a crash after config promotion can leave
`FINAL/mobile-staging-config.json` visible while the receipt is absent. The
mandatory classifier returns `UNPUBLISHED` in that state, and no consumer may
open/use/install/stream config. A present receipt returns only
`COMMIT_MARKER_PRESENT_REQUIRES_VALIDATION`; full contract and physical
validation is still required before PASS. This is logical atomic commit plus
kernel no-clobber, not a claim of an invisible directory rename.

Crash recovery:

| State | Recovery |
|---|---|
| claim only | `CLAIM_CONSUMED_NO_CAPTURE`; STOP |
| complete staging, no final | resume from captured bytes, no source reread |
| exact config-only final | promote captured receipt last |
| complete exact final | read-only `EXISTS_VERIFIED` |
| divergent/raced entry | STOP, no overwrite/cleanup |

### A4. VPS PASS and required trust handoff

VPS PASS reports only hashes/metadata/status. In addition to the two-file
remote artifact, the infrastructure controller must pre-deliver the Mac trust
authority described by the spec. The bundle generator does not invent or emit
destination/fingerprints. VPS PASS is incomplete until it hash-binds the
version-addressed sanitized trust descriptor, raw material/config/known-hosts
files, one-entry ED25519 fingerprint, identity/public-key binding, complete
native `ssh -G` policy and selected Mac `/usr/bin/ssh` attestation requirement.

STOP: `STOP_MAC_FETCH_TRUST_AUTHORITY` if any concrete path/hash is absent.

## 3. Phase B — Mac executor, only after VPS PASS

### B0. Strict local/no-network preservation

Read only already-delivered VPS PASS/trust files, local Git objects, worktree
state and frozen manifest. Do not fetch, query remote refs, resolve DNS, invoke
SSH or read any remote path. Require CI-3 local branch/HEAD/no-upstream/empty
staging and five exact paths; revalidate frozen V1/V2/V3 `21+4+7`, mismatch
zero. Any remote Git/read is after B1 PASS.

Five preserved paths:

```text
apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift
apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift
apps/ios/BodyFlow/BodyFlow/Core/Configuration/MobileStagingConfiguration.swift
apps/ios/BodyFlow/BodyFlowTests/CI3StagingLaunchConfigurationTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileStagingConfigurationTests.swift
```

### B1. Executable simulator early gate

Inputs are exact device/runtime hashes supplied by the selected-Mac controller,
not free variables. Future commands use only those verified values:

```text
/usr/bin/xcrun simctl list devices booted -j
/usr/bin/xcrun simctl get_app_container DEVICE_FROM_SELECTION_RECEIPT com.bodyflow.app data
```

Resolve real container once; validate every component with `lstat`, no symlink,
owner/type/mode/link rules. Destinations are container-relative:

```text
Library/Application Support/Agentempp/mobile-staging-config.json
Library/Application Support/Agentempp/synthetic-patient.credentials.json
```

Execute phases `SELECT_DEVICE`, `RESOLVE_CONTAINER`, `INSTALL_PROBE`,
`LAUNCH_PROBE`, `ACK_PROBE`, `REMOVE_PROBE`, `REOBSERVE`. Each has O_EXCL
intent before the one syscall/effect and fsynced result after; attempts are
exactly one. Probe schema/hash and ACK bind authority/device/runtime/app/
container. Verify owner/type/nlink/mode/size/hash/dev/ino/mtime after every
effect. Recovery reobserves; no ambiguous relaunch. Publish
`simulator-gate.receipt.v1.json` only after probe consumed/removed and exact
physical reobservation. No SSH/trust/read claim may predate it.

### B2. Trust-file validation and real `ssh -G`

Set only from fixed base plus verified receipts:

```text
CI3_AUTHORITY_DIR=$HOME/.config/agentempp/ci3/authorities/$AUTHORITY_SHA
CI3_DESCRIPTOR_ALIAS=alias field from hash-verified mac-fetch-trust.descriptor.v1.json
```

Open once no-follow and verify exact owner/mode/link/hash for VPS PASS,
descriptor, material, `ssh_config`, `known_hosts` and identity. Recompute
destination/material/config/known-hosts/public-key/host-key relations without
printing values. Verify `/usr/bin/ssh` path, regular physical identity,
SHA-256 and code signature against descriptor.

Run exactly after B1:

```text
/usr/bin/ssh -G -F "$CI3_AUTHORITY_DIR/ssh_config" "$CI3_DESCRIPTOR_ALIAS"
```

Capture output owner-only. Parse line-by-line, preserving order, defaults,
empty values and duplicates. Descriptor's complete ordered singleton allowlist
and duplicate policies for identityfile/canonicaldomains/global/user-known-
hosts/sendenv/setenv/localforward/remoteforward/permitremoteopen are exact.
Unknown/missing/reordered/duplicate-disallowed STOPs. Require exact bound
destination/root/port/identity/known-hosts/strict checking and disable agent,
inheritance, proxies, forwarding, password/kbd, control master and local
commands. Persist only hashes/signature class.

### B3–B5. Three one-shot remote reads

Order is receipt, config, credential. For each, create and fsync an O_EXCL
claim before the network call. Claim binds attempt one/no retry, authority,
expected path/hash, source generation, B1 gate and B2 evidence.

The process argv is `/usr/bin/ssh`, `-F`, verified config path, verified alias,
and one fixed remote command `exec /usr/bin/cat -- EXACT_PATH_FROM_RECEIPT`.
No filter, shell pipeline, find, glob or listing. Validate path grammar before
argv construction. Capture stdout to one `O_EXCL|O_NOFOLLOW` fd, fsync, rewind,
read/hash on that fd, then reobserve same pathname/inode. Never print stdout.

Result schema binds claim/capture hash, bytes, exit, sanitized stderr class,
start/finish, source generation and remote receipt hash. Any claim consumes its
read even without result. Recovery uses local claim/result/capture only; it
never invokes SSH again.

### B6. Non-circular local publication

Build from the already-bound capture descriptors:

```text
$HOME/.config/agentempp/ci3/bundles/$AUTHORITY_SHA/
  mobile-staging-config.json
  synthetic-patient.credentials.json
  local-publication.receipt.json
```

The receipt is schema/purpose `CI3_LOCAL_PUBLICATION_RECEIPT_V1`, binds remote/
local/trust/simulator/claim-result-capture hashes and states
`terminal_state=PRE_TERMINAL`. It cannot contain install/scan/PASS fields.
Publish with durable claim and receipt-last link no-replace. Exact-existing is
read-only; partial uses local captured bytes; divergence STOPs. Zero refetch.

### B7. Frozen installation and terminal evidence

Revalidate B1 and B6 physical generations. Execute only:

```text
/usr/bin/install -m 0600 "$LOCAL_BUNDLE/mobile-staging-config.json" "$RESOLVED_CONTAINER/Library/Application Support/Agentempp/mobile-staging-config.json"
/usr/bin/install -m 0600 "$LOCAL_BUNDLE/synthetic-patient.credentials.json" "$RESOLVED_CONTAINER/Library/Application Support/Agentempp/synthetic-patient.credentials.json"
```

Paths are derived from verified receipts, not typed by operator. Verify
`/usr/bin/install` identity/hash, exact destinations, owner/regular/nlink=1/
0600/size/hash/dev/ino and physical fd readback. Publish installation receipt.
Launch/ACK once, remove only simulator credential copy after proven
consumption and reobserve absence.

Scan each authorized argv/history/terminal-log/attachment/xcresult/runtime
surface independently with a counter. Missing observer/surface or any marker
STOPs. Publish separate versioned terminal receipt after install/scans; it
binds B6 receipt, install, all scan/phase roots, claims/results and 11 IDs.

Finally, a distinct privileged controller (not normal bridge executor) creates
the external anchor with root-owned `0555` parent,
`open(O_EXCL|O_NOFOLLOW,0444)`, fsync file/dir and
`/usr/bin/chflags uchg` at the fixed `/Library/Application Support/Agentempp/
ci3-terminal-authority/AUTHORITY_SHA/terminal.anchor.v1.json`. Verify exact
path/hash, root:wheel, regular, 0444, nlink1, immutable flag and full identity.
Self-consistent rewrite without the unchanged external anchor STOPs.

Do not create or prepare that anchor unless a separate controller has supplied
the exact hash-bound `CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1`.
Validate its bridge authority, writer/executable/controller/path hashes, uid/
gid zero, exact O_EXCL/no-follow flags, `0444`, immutable flag and
`normal_executor_authorized=false`. Missing authority is
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`; VPS PASS, Mac access and
normal bridge authority never imply it. No privileged-writer authority is
granted or exercised by this plan.

## 4. CI-3 continuation mapping — original plan remains frozen

B0–B7 supersede only Task 1's old Operational bridge subsection. Then execute
the original names/semantics without renumbering:

1. original Task 2 — Metadata-preserving Mobile API transport contract;
2. original Task 3 — Today adapter and server-authoritative validation;
3. original Task 4 — Dependency wiring and Release boundary;
4. original Task 5 — Explicit Today states and localized presentation;
5. original Task 6 — Real staging integration gate;
6. original Task 7 — Selected real XCUI gate;
7. original Task 8 — Focused and full native gates;
8. original Task 9 — Unsigned builds;
9. original Task 10 — Scans and reviews;
10. original Task 11 — Selective commit and single publication;
11. authority continuation label 12 — final report/preservation only; no new
    implementation task/path.

All RED/GREEN commands, semantics, STOPs and single-push rules remain literally
governed by `2026-08-28-ci3-today-staging-vertical-slice.md`.

Exact 23-path allowlist:

```text
apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift
apps/ios/BodyFlow/BodyFlow/App/AppDependencies.swift
apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift
apps/ios/BodyFlow/BodyFlow/Core/Configuration/MobileStagingConfiguration.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPIEnvelope.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransport.swift
apps/ios/BodyFlow/BodyFlow/Core/Networking/MobileAPITransportError.swift
apps/ios/BodyFlow/BodyFlow/Core/Today/MobileAPITodayProvider.swift
apps/ios/BodyFlow/BodyFlow/Core/Today/TodayModels.swift
apps/ios/BodyFlow/BodyFlow/Features/Today/TodayViewModel.swift
apps/ios/BodyFlow/BodyFlow/Features/Today/TodayRootView.swift
apps/ios/BodyFlow/BodyFlow/Resources/Localizable.xcstrings
apps/ios/BodyFlow/BodyFlowTests/AppDependenciesTests.swift
apps/ios/BodyFlow/BodyFlowTests/CI3StagingLaunchConfigurationTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileStagingConfigurationTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileAPITransportTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileAPITodayProviderTests.swift
apps/ios/BodyFlow/BodyFlowTests/TodayContractTests.swift
apps/ios/BodyFlow/BodyFlowTests/TodayViewModelTests.swift
apps/ios/BodyFlow/BodyFlowTests/TodayPresentationTests.swift
apps/ios/BodyFlow/BodyFlowTests/LocalizationContractTests.swift
apps/ios/BodyFlow/BodyFlowTests/CI3StagingIntegrationTests.swift
apps/ios/BodyFlow/BodyFlowUITests/CI3TodayStagingUITests.swift
```

## 5. Embedded VPS handoff — not executed

```text
OPERATION=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
NEXT_ENVIRONMENT=VPS
AUTHORITY_SHA=CONTROLLER_PASS.authority_sha
AUTHORITY_PARENT=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
AUTHORITY_TREE=CONTROLLER_PASS.authority_tree
AUTHORITY_SUBJECT=build(ops): authorize executable CI-3 bridge tooling
GENERATOR=scripts/ci3/create-ios-staging-bridge-config.mjs
GENERATOR_BLOB=/usr/bin/git rev-parse "$AUTHORITY_SHA:scripts/ci3/create-ios-staging-bridge-config.mjs"
GENERATOR_SHA256=/usr/bin/git cat-file blob "$AUTHORITY_SHA:scripts/ci3/create-ios-staging-bridge-config.mjs" | /usr/bin/shasum -a 256
GENERATOR_EXECUTION=/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA/create-ios-staging-bridge-config.mjs --create
GENERATOR_MODES=SELF_TEST_AND_CREATE_ONLY
INPUT_HASHES=FIVE_EXACT_HASHES_IN_SPEC
OUTPUT_ROOT=/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA
OUTPUT_FILES=mobile-staging-config.json,bridge.receipt.json
CLAIM=DETERMINISTIC_O_EXCL_FSYNC_ATTEMPT_1
PUBLICATION=RECEIPT_LAST_LINK_NOREPLACE
RECOVERY=CAPTURED_BYTES_ONLY_NO_SOURCE_REREAD
HISTORICAL_GENERATOR_ONLY_EXPECTED_TESTS=131_PASS_0_FAIL_0_SKIP_0_TODO
CREDENTIAL_COPY=NO
SERVICE_ROLE_OUTPUT=NO
PRIMARY_OPEN=NO
GIT_VERCEL_SUPABASE_PRODUCTION_WRITE=NO
CI4=NO
```

PASS must also return concrete, hash-bound trust-authority paths/hashes for the
Mac. It returns no raw values.

## 6. Embedded Mac handoff — not executed

```text
OPERATION=FETCH_VERSIONED_CI3_BRIDGE_BUNDLE_AND_RESUME_CI3
NEXT_ENVIRONMENT=MAC_LOCAL
AUTHORITY_SHA=VPS_PASS.authority_sha
REMOTE_RECEIPT_PATH=VPS_PASS.remote.receipt_path
REMOTE_RECEIPT_SHA256=VPS_PASS.remote.receipt_sha256
REMOTE_CONFIG_PATH=REMOTE_RECEIPT.output_config_path
REMOTE_CONFIG_SHA256=REMOTE_RECEIPT.output_config_sha256
REMOTE_CREDENTIAL_PATH=/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json
REMOTE_CREDENTIAL_SHA256=d36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208
TRUST_DESCRIPTOR=VPS_PASS.ssh.trust_descriptor_path+trust_descriptor_sha256
B0=STRICT_LOCAL_NO_NETWORK
SIMULATOR_GATE=BEFORE_ANY_REMOTE_GIT_OR_SSH
SSH_EFFECTIVE_CONFIG=/usr/bin/ssh -G -F VERIFIED_CONFIG VERIFIED_DESCRIPTOR_ALIAS
REMOTE_READS=3_TOTAL_1_EACH
CLAIMS=O_EXCL_FSYNC_ATTEMPT_1_NO_RETRY
NO_REFETCH_AFTER_CLAIM=YES
LOCAL_RECEIPT=PRE_TERMINAL_PUBLICATION_ONLY
INSTALL=/usr/bin/install -m 0600
TERMINAL_RECEIPT=SEPARATE_VERSIONED_AFTER_INSTALL_AND_SCANS
TERMINAL_ANCHOR=EXTERNAL_ROOT_OWNED_O_EXCL_UCHG
V1_V2_V3_EXECUTION=NO
CI3_EXISTING_PATHS=5_PRESERVED
CI3_ALLOWLIST=23_EXACT_PATHS
CI3_ORIGINAL_TASKS=2_THROUGH_11
CONTINUATION_LABEL_12=FINAL_REPORT_ONLY
CI3_PARENT=277873755bf29771a10b5f362b522c2e6a6c21d6
CI3_SUBJECT=feat(ios): connect Today to authenticated staging
CI4=NO
```

## 7. STOP classes

`STOP_AUTHORITY_OR_GENERATOR_BINDING`, `STOP_REMOTE_SOURCE_CONTRACT`,
`STOP_VERSIONED_REMOTE_BUNDLE`, `STOP_MAC_FETCH_TRUST_AUTHORITY`,
`STOP_SIMULATOR_EARLY_GATE`, `STOP_SSH_EFFECTIVE_CONFIG_OR_TRUST`,
`STOP_REMOTE_RECEIPT_READ`, `STOP_REMOTE_CONFIG_READ`,
`STOP_REMOTE_CREDENTIAL_READ`, `STOP_LOCAL_ATOMIC_BUNDLE`,
`STOP_TERMINAL_BRIDGE_EVIDENCE`, `STOP_CI3_OR_ALLOWLIST_DRIFT`.

No STOP may be reinterpreted as PASS from synthetic tests, file presence or a
self-consistent mutable receipt chain.

## 8. Atualização 1.7.1 — plano executável autorizado, não executado

### Fase A — única authority controller

1. Preservar V1/V2/V3 e os cinco paths CI-3; não executar bridge.
2. Capturar RED para generator, controller, launcher e writer antes da produção.
3. Congelar os treze paths e seus Git blob OIDs/SHA-256 em ordem.
4. Fazer o launcher provar commit/parent/tree/manifest, quatro componentes e
   tool identities e executar apenas o controller snapshot.
5. Exercitar somente adapters locais/sintéticos, `ssh -G` isolado e test build
   Swift.
6. Exigir reviews finais independentes `0 Critical / 0 Important`.
7. Somente o controller humano poderá criar um commit com parent
   `9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52` e subject
   `build(ops): authorize executable CI-3 bridge tooling`, seguido
   de push fast-forward. Esta implementação não faz commit/push.

### Fase B — handoff VPS futuro, não executado

```text
OPERATION=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
AUTHORITY_ARCHITECTURE=VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1_WITH_EXECUTABLE_MAC_CONTROLLER
AUTHORITY_SHA=CONTROLLER_PASS.authority_sha
AUTHORITY_PARENT=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
AUTHORITY_SUBJECT=build(ops): authorize executable CI-3 bridge tooling
AUTHORITY_MANIFEST_COMMAND=/usr/bin/git ls-tree -r $AUTHORITY_SHA -- [the thirteen literal paths printed below]
GENERATOR=scripts/ci3/create-ios-staging-bridge-config.mjs
GENERATOR_MODE=--create
GENERATOR_EXECUTION=/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA/create-ios-staging-bridge-config.mjs --create
REMOTE_OUTPUT=/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA/REMOTE_GENERATION_ID
REMOTE_FILES=mobile-staging-config.json,bridge.receipt.json
CLAIM=DETERMINISTIC_O_EXCL_FSYNC_ATTEMPT_1
PUBLICATION=NO_REPLACE_RECEIPT_LAST
OVERWRITE=NO
RETRY=NO
CREDENTIAL_COPY=NO
SERVICE_ROLE_OUTPUT=NO
TRUST_DESCRIPTOR=SANITIZED_VERSION_ADDRESSED_HASH_BOUND_VPS_PASS
TRUST_VALUES=EXACT_DESTINATION_ROOT_PORT_IDENTITY_PUBLIC_FINGERPRINT_HOST_ED25519_FINGERPRINT
TRUST_FALLBACK=NO
RAW_DESTINATION_OUTPUT=NO
NEXT_MAC_HANDOFF=ONLY_AFTER_VPS_PASS
V1_V2_V3_EXECUTION=NO
SIMULATOR=NO
CI3_TASK2=NO
GIT_VERCEL_SUPABASE_PRODUCTION_WRITE=NO
```

VPS PASS entrega hashes de authority/tree/manifest, quatro components, remote
generation, receipt/config/credential paths e contents, trust descriptor,
isolated config/known_hosts/identity e fingerprints. Não imprime raw
destination/origin/credential. Valor ausente STOP; não existe fallback livre.

### Fase C — handoff Mac futuro, não executado

```text
OPERATION=RUN_EXECUTABLE_CI3_MAC_BRIDGE_CONTROLLER
ENTRYPOINT=scripts/ci3/ci3-bridge-launcher.zsh
CONTROLLER=scripts/ci3/ci3-bridge-controller.mjs
WRITER_SOURCE=scripts/ci3/ci3-terminal-anchor-writer.swift
AUTHORITY_SHA=VPS_PASS.authority_sha
LAUNCH_ATTESTATION=CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2
CONTROLLER_MODES=plan,verify-simulator,verify-ssh,fetch,install-simulator,scan,write-terminal-anchor,resume,status
B0=STRICT_LOCAL_NO_NETWORK
SIMULATOR_PHASES=SELECT_DEVICE,RESOLVE_CONTAINER,INSTALL_PROBE,LAUNCH_PROBE,ACK_PROBE,REMOVE_PROBE,REOBSERVE
SIMULATOR_BUNDLE_ID=com.bodyflow.app
SIMULATOR_GATE=BEFORE_BOOTSTRAP_CLAIM_AND_SSH
SSH_EXECUTABLE=/usr/bin/ssh
SSH_EFFECTIVE_CONFIG=/usr/bin/ssh -G -F ISOLATED_CONFIG VERIFIED_ALIAS
SSH_CONNECT=THREE_CLAIMED_ONE_SHOT_READS_ONLY
REMOTE_READS=receipt,config,credential
REMOTE_READ_BUDGET=1_EACH_NO_RETRY
RECOVERY=LOCAL_ONLY_NO_REFETCH_NO_RETROACTIVE_CLAIM
LOCAL_BUNDLE=$HOME/.config/agentempp/ci3/bundles/AUTHORITY_SHA/REMOTE_GENERATION_ID
LOCAL_PUBLICATION=O_EXCL_FSYNC_NO_REPLACE_RECEIPT_LAST
ABSENT_LOCAL_RECEIPT=UNPUBLISHED
INSTALL=/usr/bin/install -m 0600
INSTALL_DESTINATIONS=Library/Application Support/Agentempp/mobile-staging-config.json;Library/Application Support/Agentempp/synthetic-patient.credentials.json
CREDENTIAL_SIMULATOR_COPY=REMOVE_AFTER_ACK_AND_REOBSERVE
TERMINAL_SCAN_IDS=argv,history,terminal-log,attachment,xcresult,runtime
TERMINAL_MANIFEST=SANITIZED_HASH_BOUND_PHYSICALLY_REVALIDATED
NORMAL_OPERATION_WRITER_KEYS=authority_path,manifest_path
SCAN_POSTCONDITION=WRITER_SOURCE_BINARY_SIGNATURE_PREPARATION_RECEIPT_AND_MANIFEST_FROZEN
PRIVILEGED_AUTHORITY_PATH=/Library/Application Support/Agentempp/ci3-terminal-authority/AUTHORITY_SHA/TERMINAL_GENERATION_ID/privileged-authority.receipt.json
PRIVILEGED_AUTHORITY_SCHEMA=CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1
PRIVILEGED_AUTHORITY_WRITER=EXTERNAL_ROOT_0444_UCHG_NOT_NORMAL_EXECUTOR
PRIVILEGED_CLAIM=EXTERNAL_ORIGINAL_O_EXCL_ATTEMPT_1
PRIVILEGE=ONE_STANDARD_MACOS_ADMIN_PROMPT_NO_PASSWORD_TO_CODEX
WRITER_BUILD=/usr/bin/xcrun swiftc -parse-as-library -o ROOT_VERSIONED_WRITER AUTHORITY_WRITER_SOURCE
TERMINAL_ANCHOR=/Library/Application Support/Agentempp/ci3-terminal-authority/AUTHORITY_SHA/TERMINAL_GENERATION_ID/terminal-anchor.json
TERMINAL_ANCHOR_PUBLICATION=ROOT_WHEEL_0444_O_EXCL_FSYNC_UF_IMMUTABLE
MISSING_PRIVILEGED_AUTHORITY=STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY
V1_V2_V3_EXECUTION=NO
CI3_EXISTING_PATHS=5_PRESERVED
CI3_ALLOWLIST_PATHS=23_EXACT
CI3_NEXT_TASKS=ORIGINAL_TASKS_2_THROUGH_11_ONLY_AFTER_TERMINAL_PASS
CONTINUATION_LABEL_12=FINAL_REPORT_ONLY
CI3_PARENT=277873755bf29771a10b5f362b522c2e6a6c21d6
CI3_SUBJECT=feat(ios): connect Today to authenticated staging
CI4=NO
```

As cinco paths preservadas são as paths completas da spec §10 para
`BodyFlowApp.swift`, `AppLaunchConfiguration.swift`,
`MobileStagingConfiguration.swift`, `CI3StagingLaunchConfigurationTests.swift`
e `MobileStagingConfigurationTests.swift`. Após `TERMINAL_PASS`, permanecem
literalmente Task 2 transport; Task 3 Today adapter; Task 4 dependency wiring;
Task 5 Today states; Task 6 staging integration; Task 7 XCUI; Task 8 focused/
full gates; Task 9 unsigned builds; Task 10 scans/reviews; Task 11 selective
commit/publication. Os 23 paths exatos são os da spec §10; nenhum outro.

### Gates desta authoring operation

```text
GENERATOR_TESTS>=150
CONTROLLER_TESTS>=160
LAUNCHER_TESTS>=40
ANCHOR_WRITER_TESTS>=96
PROTOCOL_E2E_TESTS>=48
FAIL_SKIP_TODO=0
NETWORK_CONNECT=0
PRIVILEGE_PROMPTS=0
REAL_SIMULATOR=0
REMOTE_BUNDLE=0
TERMINAL_ANCHOR=0
COMMIT_PUSH=0
```

`scan` é o boundary entre executor normal e authority privilegiada. Até esse
ponto o controller normal usa a mesma máquina de estados real e congela os
artefatos pós-scan, mas não cria authority privilegiada e não solicita
administração. Um controller externo, somente após validar esses bytes, deve
publicar sem clobber o receipt root-owned/imutável e o claim original. O
receipt tem chaves exatas `schema_version`, `purpose`, `authority_sha`,
`terminal_generation_id`, `terminal_manifest_sha256`,
`writer_source_sha256`, `writer_binary_sha256`, `writer_signature_sha256`,
`privileged_claim_sha256`, `authority_path_sha256`,
`normal_executor_authorized`, `attempt`, `retry`, `raw_values`. Nenhum valor é
livre: todos derivam da authority ou dos artefatos congelados. Se o controller
externo privilegiado não tiver autorização explícita para gravá-lo, a entrega
obrigatória é STOP; VPS PASS, acesso Mac e bridge authority não a substituem.

Os testes locais/sintéticos Round 1, preservados como histórico e superseded
pela seção Round 3, observaram `152/152` generator, `383/383` controller,
`46/46` launcher e `122/122` writer, sem fail/skip/todo. O RED
específico do receipt externo foi `0/14`; o GREEN foi `14/14`. O contrato de
surfaces dos scans teve RED `0/7` e GREEN `7/7`. Nenhum modo de
produção, anchor ou privilégio foi exercitado nesta authoring operation.

O único entrypoint oficial e o controller devem entrar no commit futuro como
`100755`; writer source entra como `100644` e é compilado separadamente. O
launcher rejeita mode Git divergente com `COMPONENT_MODE`. Pré-commit,
`zsh scripts/ci3/ci3-bridge-launcher.zsh --self-test` retorna
`COMPONENT_MISSING` por ausência dos novos blobs em HEAD; o teste sintético
confirma PASS do mesmo comando depois do commit completo, sem autorizar o
commit real nesta rodada.

## 9. Plano operacional autocontido pós-Round 1

Este plano substitui os rótulos simbólicos anteriores. Valores ainda
inexistentes não são inputs livres: `AUTHORITY_SHA`, tree, OIDs, hashes,
generations, paths e descriptor só podem vir do receipt PASS write-once da
fase imediatamente anterior. O subject único é
`build(ops): authorize executable CI-3 bridge tooling`; OID/SHA-256 de cada um
dos treze paths literais da seção 1 são resolvidos por
`git rev-parse "$AUTHORITY_SHA:$PATH"` e
`git cat-file blob "$AUTHORITY_SHA:$PATH" | shasum -a 256`. Isso evita a
circularidade impossível de embutir no próprio commit seus hashes finais.

### VPS: materializar, atestar, self-test, create

O controller humano fornece exatamente três argumentos hash-bound:
`AUTHORITY_SHA`, `VPS_NODE_PATH`, `VPS_NODE_SHA256`. O operador VPS executa:

```sh
test "${#AUTHORITY_SHA}" -eq 40 || exit 70
test "$(/usr/bin/git rev-parse "$AUTHORITY_SHA^")" = 9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52 || exit 70
test "$(/usr/bin/git show -s --format=%s "$AUTHORITY_SHA")" = 'build(ops): authorize executable CI-3 bridge tooling' || exit 70
test -f "$VPS_NODE_PATH" -a ! -L "$VPS_NODE_PATH" -a -x "$VPS_NODE_PATH" || exit 70
test "$(/usr/bin/shasum -a 256 "$VPS_NODE_PATH" | /usr/bin/awk '{print $1}')" = "$VPS_NODE_SHA256" || exit 70
REL=scripts/ci3/create-ios-staging-bridge-config.mjs
OID=$(/usr/bin/git rev-parse "$AUTHORITY_SHA:$REL") || exit 70
SHA=$(/usr/bin/git cat-file blob "$AUTHORITY_SHA:$REL" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}') || exit 70
ROOT="/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA"
/usr/bin/install -d -o root -g root -m 0700 "$ROOT" || exit 70
TMP=$(/usr/bin/mktemp "$ROOT/.generator.XXXXXXXX") || exit 70
/usr/bin/git cat-file blob "$AUTHORITY_SHA:$REL" > "$TMP" || exit 70
/bin/chmod 0600 "$TMP" || exit 70
test "$(/usr/bin/git hash-object "$TMP")" = "$OID" || exit 70
test "$(/usr/bin/shasum -a 256 "$TMP" | /usr/bin/awk '{print $1}')" = "$SHA" || exit 70
FINAL="$ROOT/create-ios-staging-bridge-config.mjs"
if ! /bin/ln "$TMP" "$FINAL" 2>/dev/null; then /usr/bin/cmp -s "$TMP" "$FINAL" || exit 70; fi
/bin/rm -f "$TMP" || exit 70
test "$(/usr/bin/stat -c '%u:%g:%a:%h' "$FINAL")" = 0:0:600:1 || exit 70
"$VPS_NODE_PATH" "$FINAL" --self-test || exit 70
"$VPS_NODE_PATH" "$FINAL" --create || exit 70
```

O PASS VPS inclui manifest ordenado dos treze paths; generator/controller/
launcher/writer OID+hash; claim e remote generation; config/receipt/credential
path hashes; e o descriptor SSH completo version-addressed. Nenhum raw host,
origin, identity path ou credential é impresso. Receipt ausente continua
`UNPUBLISHED`, mesmo se config já estiver fisicamente presente durante recovery.

### Mac: publishers autorizados, launcher oficial e fases

O modo separado `publish-operation-authority` valida o PASS VPS e instala:

```text
/Library/Application Support/Agentempp/ci3-controller-authority/<authority>/runtime/node
/Library/Application Support/Agentempp/ci3-controller-authority/<authority>/mac-operation-authority.v1.json
```

Ambos são root:wheel, single-link, no-follow e `uchg`; Node é `0555` e o
receipt `0444`. A state machine normal não cria nenhum deles; o publisher exige
receipt humano separado. Receipt ausente,
mutável, fora do path, semanticamente incompleto ou sem identity/hash STOP.
Então o único entrypoint é:

```sh
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh --self-test
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh publish-operation-authority
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh plan
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh verify-simulator
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh verify-ssh
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh fetch
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh install-simulator
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh scan
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh publish-privileged-writer-authority
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh write-terminal-anchor
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh status
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh resume
```

`verify-simulator` conclui sete claims/results/receipts físicos, inclusive
container/probe/ACK/remove/reobserve, antes de qualquer remote Git/read.
`verify-ssh` usa somente `/usr/bin/ssh -G -F <isolated-config> <alias>` e parser
ordenado duplicate-aware. `fetch` usa três e somente três comandos
`exec /usr/bin/cat -- <exact-path>`, claim antes de spawn e capture/result no
mesmo fd/inode; recovery não refaz reads. Publicação local é staging,
um único directory rename no-replace. Install persiste o receipt físico de
`/usr/bin/install -m 0600`. Scan mantém seis implementações/counters e revalida
inputs finais.

Depois de scan, somente o modo `publish-privileged-writer-authority`, com
receipt humano explicitamente autorizado, pode executar:

```text
/bin/zsh scripts/ci3/ci3-bridge-launcher.zsh publish-privileged-writer-authority
```

Ele instala o writer em
`/Library/Application Support/Agentempp/ci3-terminal-authority/<authority>/<terminal-generation>/writer/ci3-terminal-anchor-writer`
root:wheel `0555`, single-link, `uchg`; publica/fsynca claim original por
`O_EXCL` antes da instalação final; e
publica `privileged-authority.receipt.json` root:wheel `0444`, single-link,
`uchg`, ligando source/binary/signature/manifest/claim/anchor path+hash+physical
identity. A assinatura ad-hoc literal `-` é parte do código Git-bound e seu
hash é ligado ao manifest; não existe argumento de identity livre. Ausência
dessa autoridade é obrigatoriamente
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`, não permissão implícita.

O writer elevado revalida semanticamente components, generations, original
claims/results, três captures, sete simulator receipts, install, seis scans e
inputs finais; usa `O_NOFOLLOW`, publica anchor `0444` por `O_EXCL`, fsync e
`uchg`. O ledger final tem os 24 IDs independentes. Só depois de terminal PASS
as Tasks originais 2–11 e os 23 paths literais da spec §10 podem continuar.

### Critério desta authoring operation

Baseline Round 1 histórico: generator `152/152`, controller `383/383`, launcher
`46/46`, writer `122/122`, total `703/703`; superseded pela seção Round 3. Real
VPS/Mac/SSH/simulator/install/publisher/admin/anchor/Task 2/commit/push seguem
não executados. Portanto o estado desta operação continua
`STOP_PRE_AUTHORITY`, apesar dos bytes locais verdes.

## Round 2 executable plan — supersedes external-publisher placeholders

Os publishers são agora componentes executáveis dos mesmos blobs Git-bound,
sem ampliar os modos públicos além dos onze congelados. A sequência futura,
somente depois do único commit do controller e do PASS VPS, é literal:

1. materializar o request e o receipt humano schema-exact do PASS em
   `~/.config/agentempp/ci3/publisher-input/<authority>/`;
2. executar `zsh scripts/ci3/ci3-bridge-launcher.zsh publish-operation-authority`;
3. executar `plan`, `verify-simulator`, `verify-ssh`, `fetch`,
   `install-simulator` e `scan`, sempre pelo launcher oficial;
4. materializar o segundo receipt humano já ligado ao terminal manifest;
5. executar
   `zsh scripts/ci3/ci3-bridge-launcher.zsh publish-privileged-writer-authority`;
6. executar `write-terminal-anchor`, `status` e `resume`.

O primeiro publisher verifica launch attestation, PASS, Node, operation
authority e seis collectors/surfaces; cria uma geração root nova sem clobber,
instala `0555/0444`, verifica hashes/metadata, aplica `root:wheel` + `uchg` e
fsynca arquivos/diretórios. O segundo publisher exige scan/manifest já
duráveis, recompila o writer dos bytes Git-bound por stdin, publica o original
claim antes do executable, calcula no domínio root a identidade física do
writer instalado e cria o privileged receipt com O_EXCL. Um diretório de
geração existente é evidência de concorrência/retry e STOPa; nenhum publisher
adota estado.

Em todas as oito fases duráveis, claim sem receipt físico nunca reexecuta o
efeito. Recovery reabre receipt e metadata; ausência é
`CLAIM_CONSUMED_NO_RESULT`. Bundle preexistente ou destinos do simulator sem
claim original são `REJECT_UNCLAIMED_EXISTING_STATE`. A publicação local é um
único `renameatx_np(RENAME_EXCL)` descriptor-bound do diretório completo; não
há config/credential/receipt canônicos antes do rename.

O terminal manifest entrega ao Swift o authority manifest literal, todos os
claims/results/captures e 42 artifacts das sete fases simulator + sete fases
controller. O writer recomputa schemas e cross-bindings antes do anchor. Os
seis scans autenticados permanecem, sem renomear/deduplicar: `argv`, `history`,
`terminal-log`, `attachment`, `xcresult`, `runtime`.

Os 48 E2E Round 2, agora superseded, eram oito fases por seis pontos de crash e recuperação,
não clones de happy path. Esta rodada somente criou/testou código; nenhum dos
passos reais acima foi executado, nenhum commit/push foi feito e Task 2 segue
bloqueada até terminal PASS.

## Round 3 execution plan — superseding counts and handoff inputs

1. Controller review resolves one single authority commit; do not commit from
   this implementation task.
2. The trusted VPS controller materializes operation authority, Node,
   `CI3_VPS_PUBLISHER_INPUT_MANIFEST_V1` and
   `CI3_VPS_OPERATION_AUTHORITY_PASS_V1`. The two manifests bind every
   candidate/path/generation/collector-contract/transfer root; a distinct human
   receipt binds both manifests. No terminal surface is transferred.
3. An authorized transfer controller creates the owner-only Publisher-1 request
   tree. If that concrete authority is missing, stop. Then and only then the
   Git-bound launcher may dispatch `publish-operation-authority`; this operation
   was not run while authoring.
4. Run B0 locally before any remote Git/read. Require config, credential and ACK
   absence before original simulator claims. Each simulator recovery invokes
   only its read-only physical observer and stops on drift; it never adopts
   exact-existing probe state.
5. Verify concrete SSH trust with native `/usr/bin/ssh -G`; keep public-key byte
   hash distinct from fingerprint-output hash. Fetch exactly three claimed
   `exec /usr/bin/cat -- <fixed-path>` objects, with no refetch on recovery.
6. Publish the local bundle by exclusive directory promotion and install its two
   exact files with persisted physical readback. No unclaimed existing output is
   accepted.
7. Create six final generation-bound surfaces only now, from fixed current-
   operation sources. Run the six literal collectors, persist independent
   counters/command/schema/tool/output roots and reobserve every input after
   scan.
8. Finalize a 62-role pre-terminal manifest including all eight controller
   phase triples through `RUN_SCANS`. Bind its physical result to the two
   non-circular contracts `INVOKE_WRITER` and `VERIFY_ANCHOR`.
9. Require separately authorized Publisher 2. It installs the Git-bound writer
   root-owned/immutable and publishes the privileged authority; missing
   authority is `STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`.
10. The writer reopens and semantically recomputes every provenance edge before
    O_EXCL anchor publication. Only a verified anchor may settle the final two
    contracts and unblock the original Tasks 2–11/report 12.

Current synthetic gates are generator 152/152, controller 408/408, launcher
108/108 and writer 128/128: 796/796 total. The operational E2E matrix is ten
durable phases by six boundaries = 60 materially distinct scenarios, executing
the official launcher and compiled synthetic writer. No real VPS/Mac transfer,
SSH, simulator, install, publisher, admin prompt, anchor, Task 2, commit or push
was executed. `STOP_PRE_AUTHORITY` remains the only current operational status.

## Round 4 remediation plan — external trust, real surfaces and post-anchor settlement

This section supersedes the Round 3 claim that the 60 labelled self-test pairs
were full protocol E2E. The remediation order is test-first and fixed:

1. Add failing controller tests proving that a fully settled event still calls
   the typed current observer and rejects target drift for all ten durable
   phases. Every observation carries the authority-fixed target path as well as
   its path hash, so the privileged writer can reopen the effect itself.
2. Add failing tests for six semantic sources: `argv`, `history`,
   `terminal-log`, `attachment`, `xcresult`, and `runtime`. A source is either
   a PRESENT authority-fixed final file with physical identity/range, or an
   ABSENT authority-fixed path with a descriptor-first absence receipt. A
   receipt/event with a different semantic role is never a source substitute.
3. Freeze an external VPS issuer receipt schema. It is independently
   root-owned, immutable and version-addressed, carries an Ed25519 public key,
   and signs the canonical VPS PASS payload. Neither source nor tests embed a
   production key. Publisher 1 and the writer both reopen this root; absent real
   issuer material is `STOP_PRE_AUTHORITY`.
4. Make Publisher 1 rehash and physically validate every installed target,
   including `human-authorization.receipt.json`, before and after root
   ownership/mode/immutability. A swapped human source can only STOP; it cannot
   produce publisher PASS.
5. Extend terminal evidence with the root-installed operation authority, VPS
   PASS, issuer authority, human authorization, publisher input manifest, SSH
   trust descriptor and public-key bytes. The writer independently validates
   the Ed25519 signature, Git manifest bindings, local components/generations,
   SSH byte/fingerprint relationships and reopens each authority-fixed phase
   target.
6. Rename the writer output semantically to a pre-anchor. Its state is exactly
   `PENDING_VERIFICATION`; it can never claim PASS. After the controller
   physically reopens that pre-anchor, a separately authorized append-only
   terminal settlement binds the actual `INVOKE_WRITER` and `VERIFY_ANCHOR`
   claim/receipt/result roots. Only that settlement declares `TERMINAL_PASS`.
7. Replace the 60 label-only pairs with one integrated synthetic flow per
   phase/boundary: official Git-bound launcher, the production state machine,
   deterministic crash, resume over the same journal, synthetic remote and
   simulator adapters, actual local bundle/six surfaces, compiled writer test
   build invoked with `--write`, pre-anchor readback and terminal settlement.

No production key, root receipt, privilege, network, SSH connection, simulator,
anchor, commit, push or Task 2 action is authorized by this plan. All real
issuer/authority material remains an external future input; its absence is a
required fail-closed result rather than a placeholder value.

## Round 4 implementation result and future execution order

The seven remediation steps above are implemented in the synthetic/local
authority tooling. The execution order for a future authorized run is fixed:

1. Publisher 0/VPS supplies a signed `CI3_VPS_OPERATION_AUTHORITY_PASS_V1`,
   its publisher input manifest and payload, all bound to an externally
   provisioned immutable Ed25519 issuer receipt. The implementation contains no
   production key. Missing or invalid issuer material is `STOP_PRE_AUTHORITY`.
2. Publisher 1 verifies those inputs plus the separate human authorization,
   then installs and reopens the versioned root-owned Node/controller,
   operation authority, human receipt, VPS PASS, issuer receipt, publisher
   manifest, SSH trust descriptor and SSH public key. Every target is checked
   before and after owner/mode/immutability changes. A swapped source STOPs.
3. B0 remains strictly local/no-network. Only after simulator selection,
   runtime/container and probe/ACK phases settle may the controller execute
   `/usr/bin/ssh -G` and exactly three fixed remote reads.
4. Every controller phase writes claim, physical receipt, result and event.
   Recovery of a settled phase always reobserves the current typed physical
   source; recovery never trusts an event or receipt alone.
5. `RUN_SCANS` collects the actual fixed `argv`, `history`, `terminal-log`,
   `attachment`, `xcresult` and `runtime` sources (or the explicit allowed
   `xcresult` absence), publishes generation-bound surfaces, scans, then
   reopens sources/surfaces/receipts.
6. Publisher 2 installs the root-owned immutable writer binary and its
   separately authorized writer receipt. Its absence remains
   `STOP_PRE_AUTHORITY` and cannot be delegated to the normal controller.
7. The writer reconstructs the 13-line authority manifest and all external,
   phase, simulator, SSH and scanner relations, then writes only
   `pre-anchor.json/PENDING_VERIFICATION`.
8. The controller reads back that pre-anchor and settles the actual
   `INVOKE_WRITER` and `VERIFY_ANCHOR` claim/receipt/result triples. A second
   privileged writer invocation reopens those files and creates
   `terminal-settlement.json/TERMINAL_PASS` with append-only/no-clobber
   semantics.
9. Independent Reviews A and B must both return `0 Critical / 0 Important`.
   Only then may the single controller commit occur. Original Tasks 2–11 and
   report 12 remain frozen until that independently reviewed settlement.

Verification is not a pair of dimension smokes: all 60 phase/boundary cases
enter through the Git-bound launcher, inject and observe a crash, resume or
fail-close without effect replay, and invoke the actual Swift test binary as
the `INVOKE_WRITER` effect of that same causal flow. No real external action
was executed while implementing this plan.

## Round 5 executable authority correction — supersedes every earlier `--settle` description

The terminal lifecycle now has one privileged writer invocation only. The
controller invokes the root-owned, immutable, version-addressed writer once
with `--write`. That same process validates the frozen manifest and external
roots, publishes and reads back the pending pre-anchor, derives and publishes
the complete `INVOKE_WRITER` and `VERIFY_ANCHOR`
claim/physical-receipt/result chains, scans the final terminal bytes with all
six literal scanners, and publishes and reads back
`terminal-settlement.json`. `--settle` is not a public or private mode and
returns `MODE_INVALID`; there is no second elevation or second prompt.

`TERMINAL_PASS` is derived only inside that root transaction. It binds all
four generation IDs, the authority receipt hash, the pre-anchor hash, both
contract hashes, every claim/receipt/result edge, the ordered terminal phase
graph, physical target observations, and the terminal-final six-scan root.
The normal executor may reopen and recompute this graph but cannot supply a
terminal triple or settlement manifest.

Remote read bindings are derived again by the writer from the root-owned
operation authority. Each exact path is paired with exactly
`exec /usr/bin/cat -- <authority-path>`; the bootstrap claim, each read claim,
each read result, and the terminal input manifest must match those independent
derivations. The same operation authority contains the ordered per-phase
target contracts. Role, state, path hash, owner allowlist, mode allowlist and
immutability policy must match exactly; a fully rehashed alternate regular
file is rejected.

The six scans remain distinct and ordered: `argv`, `history`,
`terminal-log`, `attachment`, `xcresult`, `runtime`. The controller
collects complete argv, journal/history bytes, event/log bytes, attachment
bytes and only the closed sanitized runtime allowlist/process identity. The xcresult observation uses the
fixed generation-addressed operational result path, with an authenticated
absence receipt when it does not exist. The privileged transaction performs a
second terminal-final scan over current journal/output, the new pre-anchor,
phase objects, actual settlement and writer output, then publishes the bound
`complete-result.json` last.

Publisher 0 is a controller mode reachable only through the separately
installed root-owned immutable external bootstrap. The user-owned worktree
launcher rejects it. The bootstrap verifies the external issuer, fixed runtime
and full root directory chain before reading the fixed issuer/request/key
inputs, signs Ed25519, creates the PASS no-clobber, fsyncs, freezes and reopens
it. No real key is embedded; missing external provisioning is
`STOP_PRE_AUTHORITY`.

Synthetic crash coverage now invokes the actual Swift test writer as the
`INVOKE_WRITER` phase effect, and `VERIFY_ANCHOR` reopens the artifacts from
that same causal run. A crash after a durable claim but before any physical
effect is not healed by replay: it deterministically returns
`STOP_CLAIM_CONSUMED_NO_RESULT` and publishes no anchor. Other boundaries
recover with at-most-once effects and exact-existing readback.

All real authority inputs remain absent in this implementation operation.
Therefore `STOP_PRE_AUTHORITY` remains the only current operational status;
no VPS publisher, SSH/network, simulator, admin prompt, root publication,
anchor, Task 2, commit or push was executed.

Each matrix case now uses two distinct Git-bound controller processes: the first exits at the selected synthetic crash, and the second reconstructs maps, physical target bindings, effect counts and journal state exclusively from the durable scenario snapshot before recovery or STOP.

## Round 6 plan closure

The normative executable boundary is the “Round 6 executable trust boundary”
in the companion spec and is incorporated here without weakening: Publisher 0
starts only from the separately installed root-owned immutable bootstrap and
empty/minimal environment; the worktree launcher rejects that mode. Publisher
1 must materialize the complete authenticated VPS transfer, SSH snapshot and
operation authority by no-follow dirfd/no-clobber/fsync/readback before the Mac
controller is reachable. Missing external issuer, bootstrap materializer,
transport authority, human authorization, SSH snapshot or privileged writer
authority remains `STOP_PRE_AUTHORITY`.

Execution order is: external Publisher 0 bootstrap; signed VPS PASS and transfer
manifest; authenticated Publisher 1 staging/install/readback; B0 local-only
authority and simulator preflight; immutable SSH snapshot plus `ssh -G`; exactly
three fixed `exec /usr/bin/cat --` reads; descriptor-bound local publication;
simulator install/readback; semantic raw scans; the single privileged writer
transaction; final scan; `complete-result.json`; non-circular complete-result
scan; controller readback. No
`after-claim` recovery may adopt a later effect. None of these real actions was
executed in this documentation/tooling operation.

For the 60-case synthetic matrix, remove every pre-run writer fixture step.
The production state machine under the Git-bound launcher reaches
`INVOKE_WRITER`; only its synthetic adapter then reopens the same durable
snapshot and calls the closed-env materializer. Require the ordered
`controller-durable-state-root` evidence role, descriptor path/hash,
scenario/hash, full durable-map schema, unchanged source bytes and writer-side
hash recomputation. Test a missing descriptor before `INVOKE_WRITER`, successful
lazy creation afterwards, writer readback, a terminal crash/restart, and the
unconditional no-adoption STOP for every `after-claim` case. Never map this
synthetic helper to real publisher authority.

## Round 8 execution plan — authority remains external

1. Publisher 0 provisioning: an external issuer supplies the root-owned
   immutable bootstrap authority and exact component hashes. The future VPS
   operator invokes the fixed absolute Node/controller under `env -i`; the
   Node-core retained-fd transaction signs and publishes the VPS PASS exactly
   once. Missing issuer/bootstrap/runtime is `STOP_PRE_AUTHORITY`.
2. Transport: carry the authenticated V2 manifest containing the eleven
   transported roles (Node, controller, launcher, launch attestation, authority
   manifest, operation authority and five SSH inputs). The transport receiver
   must retain the source descriptors, verify hashes and preserve evidence; it
   may not accept operator-selected substitutions.
3. Publisher 1 provisioning: from the externally installed
   `ci3-publisher1-bootstrap` launcher, run only `publish-operation-authority`.
   It installs sixteen root-owned immutable targets, including the derived
   launcher line authority and exact generation-addressed five-file SSH
   snapshot, then reopens bytes and full metadata before reporting publication.
4. Operational B0: execute only the installed controller-authority launcher.
   Its first Node is fixed/hash-bound and every spawn uses the closed
   environment. Local simulator preflight remains before any SSH/Git remote
   read.
5. Continue the existing phase machine unchanged through exactly three remote
   reads, local publication, simulator install/readback, credential removal,
   six semantic scans, one privileged writer invocation and anchor readback.
6. Treat the controller's durable `COMPLETE` as
   `PRE_TERMINAL_UNPUBLISHED`. The normal executor cannot publish a tail
   receipt. The one privileged writer invocation creates/readbacks the anchor
   and settlement, scans the actual journal/stdout/stderr/complete/final-scan
   bytes, and publishes the fixed privileged terminal marker last. The fixed
   internal terminalizer only validates that marker and emits already retained
   bytes; it never reopens a pathname after the scan. Only that privileged
   marker changes status to `TERMINAL_PASS`.
7. Only after that marker may the original frozen Tasks 2–11 and report Task 12
   be considered for continuation. This plan does not run them now.

Exact future entrypoint grammar (the values are taken from and checked against
the external signed authorities; they are not freely supplied shell values):

```text
/usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin \
  <ROOT_IMMUTABLE_VPS_NODE> <ROOT_IMMUTABLE_VPS_CONTROLLER> \
  publish-vps-operation-authority-pass

/bin/zsh -f "/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/<AUTHORITY_SHA>/<BOOTSTRAP_GENERATION>/runtime/ci3-bridge-launcher.zsh" \
  publish-operation-authority

/bin/zsh -f "/Library/Application Support/Agentempp/ci3-controller-authority/<AUTHORITY_SHA>/runtime/ci3-bridge-launcher.zsh" \
  resume
```

The first command is valid only after Publisher 0's external root has been
installed and hash/readback verified. The latter two launchers validate the
ten-line external authority before their first Node. No Python runtime or
additional package is authorized.

## Round 9 execution plan — receiver, materializer and terminal commit marker

1. Publisher 0, from its already external/root-owned immutable bootstrap,
   publishes the signed PASS and V2 eleven-role transport. It does not invent
   the external issuer or a Mac materializer hash.
2. The external Mac root publisher installs the exact
   `CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V1`, its bound VPS issuer receipt and
   reviewed Swift binary under
   `ci3-publisher1-bootstrap/<authority>/<controller-generation>`. The receipt
   freezes binary path/hash, writer source hash, issuer hash, closed
   environment and denies normal authority. Missing/mismatched input is
   `STOP_PRE_AUTHORITY` before any prompt/effect.
3. The normal Mac controller validates and retains the transported candidates,
   snapshots exactly sixteen deterministic receiver leaves, derives the
   launcher authority, and writes one owner-only hash-bound transaction request.
   It never passes original candidate pathnames to the privileged installer.
4. One administrator invocation executes the fixed immutable Swift
   materializer with only request path plus exact SHA. The materializer reopens
   its root authority/issuer/self, verifies the signed PASS and every source
   relationship independently, and retains request/source/ancestor descriptors.
5. With all sources validated but before staging, the materializer writes and
   fsyncs `publisher1.claim.json` `O_EXCL`. It creates the full authority in one
   sibling staging directory through `openat/O_NOFOLLOW/O_EXCL`, freezes every
   leaf and directory, promotes the directory with `RENAME_EXCL`, fsyncs,
   reobserves and writes `publisher1.result.json`.
6. Recovery never prompts/refetches/reexecutes. Claim plus exact tree is
   reobserved (`EXISTS_RECOVERED` or `EXISTS_VERIFIED`); claim without complete
   effect, partial tree, preexisting unclaimed tree, source/ancestor drift or
   divergent result STOPs with preserved evidence.
7. Run B0 and the existing phase machine only from the installed operation
   launcher. Materialize a reversible actual-journal frame before the writer;
   raw-scan each object and decoded frame. The same single privileged writer
   invocation writes anchor, settlement, final frames and the privileged PASS
   marker last.
8. `resume/status` stays `PRE_TERMINAL_UNPUBLISHED` until the exact root-owned
   marker validates. The terminalizer emits its retained scanned bytes directly.
   Only then may the original Tasks 2–11 and report Task 12 become eligible.

This plan section documents a future executable handoff only. Round 9 executed
no real Publisher 0/1, transport, admin prompt, network, SSH, simulator,
terminal anchor or continuation task.

## Round 10 execution correction

The future handoff must use this exact order; earlier terminal steps are
superseded:

1. Require external `CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2`. Verify its
   fixed request-path hash, expected request bytes hash, complete physical
   metadata/identity and exact receiver-root path/descriptor identity before
   any untrusted byte can execute.
2. The normal controller writes the fixed request and invokes production only
   as `--publisher1-transaction <exact-fixed-request-path> <expected-sha256>`.
   No stdin, suffix-selected root or path-free production input is allowed.
3. Before prompting, observe root-owned `publisher1.claim.json`,
   `publisher1.result.json` and the complete immutable sixteen-leaf tree.
   Reuse exact settled state. A claim without a complete matching tree, a
   partial tree or any mismatch STOPs; controller restart must not launch a
   second `osascript`/admin child.
4. On the first effect, write/fsync the claim, construct/fsync a private
   descriptor-relative staging tree, promote it once with `RENAME_EXCL`, then
   freeze and read back the destination. Never freeze staging before rename.
5. After the eight normal phases, write the normal COMPLETE commit-contract
   event and seal the reversible journal. Run all six scans over actual bytes.
   This is not terminal PASS.
6. Invoke the privileged writer once. It owns both `INVOKE_WRITER` and
   `VERIFY_ANCHOR`, recomputes their roots, settlement/final scans/frames and
   publishes the privileged marker literally last. No normal write follows.
7. On restart, report PASS only for the exact reopened root marker. Earlier
   objects without it remain unpublished; partial/divergent roots STOP.

The synthetic crash matrix interrupts the two privileged phases at all six
boundaries inside that same writer transaction, before marker publication,
and recovery uses exact-existing roots without effect replay. Real external
authorities are still absent, so this plan was not executed against a real
receiver, privilege boundary, network, simulator, anchor or Task 2.

## Round 11 execution correction

1. Require the V2 external materializer authority to enumerate all sixteen
   receiver leaves in fixed role order with path/content hashes and exact
   uid/gid/mode/nlink/size/mtime/dev/inode/identity. Reject missing, duplicate,
   reordered or self-consistently substituted leaves before privilege.
2. Build the request from retained descriptor observations. The Swift
   materializer must `fstat/read/fstat` every leaf and reobserve the retained
   receiver directory and each canonical child immediately before its original
   `O_EXCL` claim. Persist the full source observations in claim and result.
3. On controller restart, first validate the exact privileged terminal marker
   and all fixed transitive roots. Never treat pre-anchor, settlement, scans or
   the five pre-frame artifacts as PASS on their own.
4. If an exact prefix exists without the marker, continue only through the same
   externally authorized writer recovery. Test crashes after COMPLETE final
   scan, after retained frames, after marker readback and after directory
   freeze. Dirty or unclaimed prefixes STOP without adoption.
5. Query `terminalStatus` after recovery. Only its marker-validating PASS may be
   reported by `resume`; otherwise report `PRE_TERMINAL_UNPUBLISHED`.
6. Use the reviewed root writer as the transient supervisor for the one
   authorized invocation. It launches only the same absolute binary worker
   under a closed environment and may retry that worker once after a crash.
   Controller recovery only observes/waits; it must never invoke a second
   `osascript`. A dead supervisor without a marker is `STOP_PRE_AUTHORITY`.

Round 11 performed only local/synthetic verification. No real receiver,
privilege, network, SSH, simulator, terminal root or continuation task was run.

## Round 12 execution correction

1. Carry the already authenticated privileged claim hash into every fixed
   writer publication; never infer it from an existing file.
2. Create each file no-clobber, write and fsync `0444` bytes, fsync the parent,
   set `UF_IMMUTABLE` through the retained descriptor, fsync again and reread.
3. On restart after file fsync but before/after flags, accept only the exact
   descriptor identity and bytes under the original claim. Set/verify the flag
   and finish readback. Preexisting state without the claim STOPs.
4. Build the terminal marker over exactly eighteen paths: the original nine,
   pre-anchor, writer output, terminal final scan and both privileged phase
   claim/receipt/result triples.
5. Before `status`, `resume` or terminal emission can return PASS, require the
   exact terminal and phase directory entry sets, stable root-owned `0555`
   directories, immutable single-link `0444` files, and recompute every
   authority/generation/path/hash/phase/observation/settlement/COMPLETE
   relation. Missing, extra or mutated state STOPs.

The local RED/GREEN tests exercise both flag crash edges and transitive-root
tampering. They do not authorize or perform any real privileged or external
action; the future handoff remains `STOP_PRE_AUTHORITY`.

## Round 13 execution correction

1. Reopen the authority-fixed terminal manifest and immutable root writer,
   retain their bytes/physical identity, and construct independent expected
   values for the privileged writer authority receipt.
2. Call the publication-grade exact authority validator; never accept a
   purpose/generation-only shortcut.
3. Call the one canonical exact pre-anchor validator and recompute components,
   generations, fixed paths, external-authority roots, phase-target roots,
   scan roots, finding IDs, timestamp and writer provenance/claim relations.
4. Validate settlement, privileged phase claims/receipts/results, physical
   observations, scans, COMPLETE roots and the exact marker as one corpus.
5. Route operational `status`, `resume`, exact-existing recovery and terminal
   emission through that corpus validator. Absence remains unpublished;
   mutation or unavailable external expectation STOPs.
6. Rehash each negative fixture through all posterior objects and require STOP;
   validate the complete unmodified corpus twice for deterministic recovery.

This is a local validation plan only. It does not invoke or authorize any real
publisher, network, simulator, privileged writer, anchor or continuation task.

## Round 14 execution correction

1. Reopen and authenticate the fixed immutable writer and terminal manifest.
2. Execute the writer's read-only `--validate-manifest` entrypoint by absolute
   path with the exact authority/four generations and a closed environment.
3. Within that entrypoint call the same Swift semantic validator as publication
   over all 71 evidence roles and six scan receipts; perform no write, prompt,
   network call or privilege transition.
4. Accept only one exact hash-only semantic receipt bound to manifest,
   writer identity, ordered evidence/scan roots and recomputed semantic roots.
5. Derive pre-anchor expectations from that receipt. Reopen `RUN_SCANS` as the
   first terminal predecessor; rebuild the two contracts from the canonical
   transition table and require exact contract hashes and result predecessors.
6. Run the role-class mutation matrix and the disconnected phase-contract
   adversary through the real validation entrypoint. Every invalid case STOPs;
   the unmodified validation remains read-only and creates no anchor.

No step authorizes a real run. Missing external authority or writer binding is
`STOP_PRE_AUTHORITY`, and no continuation phase may start from this plan alone.

## Round 15 execution correction

1. Obtain path and retained-descriptor observations with BigInt stats.
2. Compare dev, ino, uid, gid, mode, nlink, size and exact mtimeNs before and
   after every read/effect boundary.
3. Hash the exact decimal eight-field preimage matching Swift; never reconstruct
   nanoseconds from floating-point `mtimeMs`.
4. Convert only schema-required bounded JSON integers after hashing and STOP on
   unsafe conversion.
5. Compile the synthetic writer, give it a non-millisecond mtime, materialize a
   real 71-role fixture and compare the Node identity to the Swift read-only
   validation receipt. Mutating one nanosecond or any other identity field must
   fail closed.

This remains a local TDD/verification plan. It authorizes no real privileged,
network, SSH, simulator, anchor or continuation action.

## Round 16 execution correction

1. Reproduce the legacy collision for adjacent `dev`/`ino` values above
   `Number.MAX_SAFE_INTEGER` at the promotion and simulator boundaries.
2. Observe all promotion paths with BigInt `lstat`; compare staging/parent and
   staging/final identities without conversion and preserve no-clobber.
3. Observe the resolved simulator container with BigInt `lstat` and derive its
   authority digest from the complete shared eight-field serializer.
4. Run positive production-boundary tests plus mismatched adjacent identities;
   the promoter must STOP and simulator hashes must differ.
5. Audit controller, generator and tests so any intentional Number stat is
   only an existence/bounded check or the explicit legacy-collision fixture.
6. Run focused tests, all four suites, syntax/Swift/diff/allowlist/sensitive
   scans and record exact counts and hashes before review.

No step supplies external authority or authorizes real publication, simulator,
network, privilege, anchor, continuation, commit or push.

## Round 17 execution correction

1. Reproduce the legacy `size` collision with exact `2^53` and `2^53+1`
   values after Number projection.
2. Require exact BigInt/canonical integers in the stable-identity comparator.
3. Preserve all eight BigInt fields in `metadataView()` across entry-before,
   descriptor-before/after and entry-after.
4. Use the common controller/Swift eight-field identity preimage for generator
   physical identity hashes.
5. Exercise the real owner-only reader for original claim, exact-existing,
   staging and recovery and require each adjacent-size mutation to STOP.
6. Audit every generator stat conversion; only explicitly bounded owner/mode/
   link policy checks may convert after safe-range validation.
7. Run focused, generator and four-suite aggregate gates plus syntax, Swift,
   diff, allowlist, mode, sensitive-literal and orphan-process checks.

This is a synthetic/local verification plan and authorizes no real action.

## Round 18 execution plan — immutable VPS Node capsule before bridge create

1. Publish one seven-path runtime authority with parent `ba847...` and subject
   `build(ops): authorize immutable VPS Node runtime capsule`.
2. Materialize its builder only by `git cat-file` into
   `/root/.config/agentempp/runtimes/node/.builders/<runtime-authority>/`.
3. Use literal `/usr/bin/node` only for builder self-test/create/verify. Never
   use NVM, PATH fallback or package installation.
4. Persist the attempt-one claim and fsync it before the single immutable
   capability probe. Preserve all failure evidence without retry or cleanup.
5. Copy through the retained source fd, verify bytes/version/core/syntax and
   closure, promote no-clobber, then freeze Node, receipt and final directory.
6. Reopen the complete capsule, verify three immutable flags, physical
   identities, closure and execution, then revalidate `/usr/bin/node` unchanged.
7. Create a detached clean execution worktree at bridge authority `ba847...`.
   Materialize the bridge generator only from its published blob and run its
   syntax/tests/self-test/create exclusively with the capsule.
8. Consume at most one bridge creation attempt. Do not run the Mac handoff,
   simulator, Task 2, CI-4, Supabase, Vercel, database or production actions.

No runtime or bridge effect is authorized before the runtime authority remote
SHA is confirmed. Exact-existing requires its original claim; partial or
unclaimed state is a terminal STOP.

## Round 19 execution STOP — dynamic closure before runtime claim

The seven-path runtime authority was published at `f039fe38...`. Its Git blob
snapshot passed physical readback and self-test, but the only authorized
`--create` invocation stopped with `ERROR DYNAMIC_CLOSURE`. Read-only evidence
found seven current `ldd` entries, including two symlink entries; the published
regular-file no-follow reader rejected those entries instead of first binding
their canonical target safely.

The stop happened before claim, probe, copy, staging or final publication.
Runtime invocation budget is nevertheless exhausted `1/1`; retry and cleanup
remain prohibited. Bridge generator/output are absent and bridge budget remains
`0/1`. Resume requires a new child authority that specifies safe canonical
closure binding and explicitly grants a fresh runtime attempt. This round does
not implement or execute that next gate.

## Round 20 execution — corrected full-path closure V2

1. Preserve V1 and its consumed attempt byte-identically.
2. Freeze independent 7/7/0, 2/5/5 and 9/max2 dimensions plus the three hashes.
3. Publish the seven-path authority after 200+ tests, baseline and two 0C/0I reviews.
4. Materialize only its Git blob; claim/fsync precedes ldd and durable capture.
5. Walk lstat/readlink components, open final O_NOFOLLOW once and revalidate.
6. On capsule PASS, execute unchanged `ba847...` exclusively with capsule V2.
7. Publish one terminal four-path commit; do not run Mac, Task 2, CI-4 or cleanup.

## Round 21 STOP — verifier V2 após publicação física completa

Runtime authority `b08e6326...` foi publicada e a tentativa V2 única foi
consumida. Claim/capture/probe e o final imutável existem; a revalidação
read-only de schema, bindings, closure e flags passa. O create, porém, terminou
sem PASS porque o verifier chama o retorno de `JSON.stringify` ao projetar o
probe. Runtime fica `PARTIAL_PRESERVED`; bridge continua ausente `0/1`.

Não repetir create/verify publicado, ldd, probe, chattr, bridge ou cleanup. O
próximo plano precisa publicar nova authority, corrigir somente a expressão e
autorizar verificação/adoção read-only do capsule `b08e6326...`. A adoção deve
ligar authority, builder, claim, capture, probe, receipt, identidade e flags
existentes sem mutação e sem conceder novo budget de criação.

## Round 22 execution — verifier-only e adoção read-only do capsule V2

1. Preservar o STOP `030aa2...`, a authority `b08e...`, o builder/teste V2 e a
   tentativa de criação consumida `1/1` byte a byte.
2. Publicar uma authority sucessora de sete paths com verifier/teste novos e
   documentação 1.7.6; o verifier aceita somente `--self-test` e
   `--verify-existing`.
3. Exigir RED da precedência antiga e da implementação ausente, depois pelo
   menos 120 testes sintéticos GREEN, self-test, allowlist, diff check e duas
   revisões 0C/0I.
4. Materializar o verifier somente por seu blob Git publicado, root-owned,
   `0600`, single-link, O_EXCL e fsync.
5. Consumir uma única tentativa de adoção: claim externo primeiro; depois
   reabrir artifacts, revalidar closure pelo capture e confirmar hashes,
   identities, bytes e immutable flags sem nova descoberta/probe/mutação.
6. Executar version/core smoke e as fases receipt-bound bootstrap e self-hosted;
   publicar o receipt de adoção somente após provar artifacts inalterados.
7. Apenas em PASS, criar/reusar worktree detached limpa `ba847...`, materializar
   o generator por blob e consumir sua tentativa `0/1` exclusivamente pelo
   capsule adotado.
8. Publicar um segundo commit terminal de quatro paths. Não executar Mac,
   simulador, Task 2, CI-4, cleanup ou qualquer sistema externo.

Qualquer claim sem receipt, drift físico, failure de smoke/self-host ou estado
ambíguo é STOP sem retry e sem bridge.

## Round 23 STOP — reader Git da bridge excede bound publicado

A authority do verifier `461a2e0...` foi publicada e a adoção read-only passou
na única tentativa. O capsule V2 permanece completo, imutável e byte-idêntico,
com receipt externo de adoção validado. O generator bridge em `ba847...`
passou 154/154 testes e self-test 8/8 usando esse capsule.

A única bridge `--create` parou antes do claim com `ERROR GIT_AUTHORITY`. O
reader publicado usa `spawnSync` com `maxBuffer=64 KiB`, mas sua primeira
leitura `cat-file` recebe o blob do próprio generator, que tem 82.675 bytes.
Assim, nenhum input secreto foi aberto e nenhum authority root, claim, staging,
generation, config ou receipt foi criado. O budget da bridge está consumido
`1/1`; não repetir, ampliar o buffer localmente ou substituir o entrypoint.

Retomada exige nova authority filha com TDD para blobs acima de 64 KiB, novo
snapshot Git-bound e concessão explícita de nova tentativa da bridge, mantendo
o capsule adotado read-only. Este round não executa esse próximo gate, Mac,
simulador, Task 2, CI-4, cleanup ou ação externa.

## Round 24 — authority Bridge V2 e gate zsh environment-correct

1. Preservar a V1 em 1/1 e o capsule Node V2 adotado sem mutação.
2. Publicar exatamente 14 paths, parent `92cccf3...`, com reader bounded de
   1 MiB, 48/48 testes específicos, suíte completa e zero retry.
3. Provar que o skeleton do launcher é igual ao predecessor Mac-validado; se
   grammar/control-flow/call-graph divergir, STOP e encaminhar ao Mac.
4. Classificar a VPS como `VPS_ZSH_SYNTAX_EXECUTION=NOT_APPLICABLE`; não
   instalar zsh nem usar Bash.
5. Persistir no receipt que `/bin/zsh -n` está deferred ao Mac e é obrigatório
   antes de simulador, claim, SSH ou qualquer remote read.
6. Após push/readback da authority, materializar o generator pelo blob Git e
   executar uma única tentativa `--create` pelo capsule Node adotado.
7. Exigir claim-before-effect, publication receipt last, output versionado,
   readback físico, zero credential copy, zero service-role e zero raw values.
8. Em PASS ou STOP, publicar um único commit documental terminal. Não executar
   o handoff Mac, Task 2, CI-4 ou cleanup na VPS.

### Mac Gate 0 — antes de toda rede

O handoff deve materializar o launcher pelo blob exato, validar o runtime
literal `/bin/zsh` (target, owner/mode, hash, versão, assinatura e parent
chain), executar exatamente `/bin/zsh -n <EXACT_MATERIALIZED_LAUNCHER>`, exigir
exit 0/stdout vazio/stderr vazio/hash unchanged e criar
`mac-zsh-syntax.receipt.json` owner-only/no-clobber. Reabrir e validar o
receipt antes do simulator gate. Falha: zero rede, zero claim, zero stream,
STOP sem retry.

## Round 25 STOP — Bridge V2 consumida antes do claim

A authority V2 `c8e1d00...` foi publicada e lida de volta. O snapshot exato
passou self-test, mas a única tentativa `--create` retornou
`ERROR ENV_RECEIPT_STATE`. O receipt de staging existente diverge em sete
campos semânticos do contrato congelado. Nenhum raw value foi reportado.

Não existe claim, staging, generation, config ou receipt V2. O budget é 1/1 e
retry é proibido. Preservar snapshot, capsule e inputs sem cleanup. A retomada
exige nova authority que escolha explicitamente o contrato correto do env
receipt, teste a reconciliação e conceda uma nova tentativa independente.
Mac Gate 0, simulador, SSH, remote reads, Task 2 e CI-4 continuam bloqueados.

## Round 26 — authority canônica do env receipt e tentativa independente

1. Preservar Bridge V1/V2 em `1/1`, seus snapshots e o Node capsule adotado.
2. Provar hash, metadata, provenance e sete valores canônicos do receipt sem
   imprimir nenhum valor sensível.
3. TDD com ao menos 46 casos de reconciliação; preservar reader 48+, generator
   240+, controller 689+, E2E 44+, launcher 22+ e writer 4+.
4. Publicar exatamente 15 paths, parent no STOP V2 e subject de reconciliação.
5. Somente após scans e duas reviews 0C/0I, materializar o generator pelo blob
   Git e consumir uma tentativa nova 1/1 pelo capsule adotado.
6. Exigir output versionado, receipt last, zero credential copy, zero
   service-role/raw values e readback físico integral.
7. Não executar Gate 0 do Mac, Task 2, CI-4, produção ou cleanup nesta VPS.

## Round 27 STOP — deployment receipt diverge antes da tentativa

A authority do Round 26 foi publicada e o env receipt canônico passou. O
preflight seguinte parou em `DEPLOYMENT_RECEIPT_STATE`: exatamente `purpose` e
`node` divergem das expectativas herdadas do generator, enquanto os demais
gates do deployment receipt passam. Nenhum valor bruto foi emitido.

`--create` não foi executado; o novo budget permanece `0/1`. Claim, staging,
generation, config e receipt estão ausentes. Preservar snapshot, capsule,
adoption e cinco inputs sem cleanup. A retomada requer authority específica
para o deployment receipt; não executar Mac Gate 0, Task 2 ou CI-4.
