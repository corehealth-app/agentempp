# CI-3 Versioned Remote Bridge Artifact V2 — bounded-reader specification

**Date:** 2026-08-29
**Status:** successor authority/tooling contract; one VPS creation attempt authorized after publication
**Architecture:** `VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING`

## 1. Decision and scope

V1 and V2 are `FROZEN_SUPERSEDED`. V3 is
`FROZEN_REJECTED_AFTER_ROUND5`; it must never be executed or edited and there
is no sixth V3 round. Review A ended `0C/5I/1M`, Review B `0C/6I/1M`.
`174/174` synthetic tests did not close the 11 independent Important findings.

This authority authors seven Git paths only. It does not execute `--create`,
SSH, network, V1/V2/V3, simulator, streams, installation, CI-3 Task 2 onward,
cleanup, Supabase, Vercel, production or CI-4. No secret, raw origin,
destination, host/IP, credential, token, PII or raw identifier belongs in Git
or terminal output.

## 2. Closed CLI and trusted-generator launch

The tracked files are:

```text
scripts/ci3/create-ios-staging-bridge-config.mjs
scripts/ci3/create-ios-staging-bridge-config.test.mjs
```

Only Node core modules are used. The only generator modes remain exactly
`--self-test` and `--create`. `--self-test` is synthetic, local, temp-only and
`network_calls=0`. `--create` is VPS/root-only. Direct execution of the
mutable checkout source is rejected with `GENERATOR_LAUNCHER_REQUIRED`.

### 2.1 Git-bound launcher/snapshot contract

Self-validation cannot make already-executing mutable source trusted. The
trusted launcher therefore runs before the generator and is part of the VPS
handoff, not a third generator mode or an eighth file. It must:

1. run from the exact repository root and verify final authority
   commit/parent/tree/subject;
2. obtain bytes with `/usr/bin/git cat-file blob
   AUTHORITY_SHA:scripts/ci3/create-ios-staging-bridge-config.mjs`;
3. obtain the expected object ID with `/usr/bin/git rev-parse` and independently
   compute Git's `sha1("blob " + bytes + NUL + bytes)` object ID;
4. create with `open(O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600)` the exact
   `/root/.config/agentempp/bridges/ci3/.launchers/AUTHORITY_SHA/create-ios-staging-bridge-config.mjs`;
5. write once, fsync the fd, close it and fsync both launcher directories;
6. on exact-existing, open once no-follow and verify root:root, regular,
   `0600`, `nlink=1`, full identity and exact blob/file hashes, never rewrite;
7. execute only `/usr/bin/node SNAPSHOT_PATH --create`, cwd at repository root
   and minimal fixed environment.

The snapshot process opens itself once and binds that fd's bytes plus
`uid/gid/mode/nlink/size/mtime/dev/ino` before/after to `git cat-file` bytes.
It never calls `git hash-object` on a worktree pathname. Swap or drift STOPs
before any real source read. The handoff's inline Node-core launcher is the
executable implementation of these syscalls; no untracked launcher file is
accepted.

## 3. Fixed VPS sources and complete semantic validation

Only these five paths may be opened:

| Input | Exact path | SHA-256 |
|---|---|---|
| env | `/root/.config/agentempp/secrets/ci3-staging-mobile-bff.env` | `6aa784b9e5777a8924c4f37c1a9081cd040e399e30abfe5255978e1c1e571b9d` |
| env receipt | `/root/.config/agentempp/secrets/ci3-staging-mobile-bff.receipt.json` | `44d0da30244f2340827698caa1aae85410b6a34d5c50a312a8b9e5e9bbe08978` |
| deployment receipt | `/root/.config/agentempp/secrets/ci3-dedicated-mobile-bff-deployment.receipt.json` | `f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6` |
| credential | `/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json` | `d36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208` |
| provisioning receipt | `/root/.config/agentempp/secrets/ci3-synthetic-patient.provisioning.receipt.json` | `5ed29995fa906d3774384d5a1aa9157516fa9f3e3dd0d320beff138b6aeedfcb` |

The primary path is denylisted and never opened. Each path and parent is
opened/observed no-follow and remains root:root, parent `0700`, file `0600`,
regular and `nlink=1`. Descriptor, pathname and parent are revalidated with
the full identity tuple before and after.

Semantic validation supplements the frozen whole-file hashes:

- env names are exactly URL, anon key and service role; receipt is schema `1`,
  purpose `ci3_staging_mobile_bff`, source
  `existing_authorized_credential`, staging, and binds each classification,
  name and value hash;
- URL is HTTPS and its host-derived project ref equals env receipt,
  credential and provisioning refs;
- deployment is schema `1`, purpose
  `ci3-dedicated-mobile-bff-deployment`, staging/Preview/READY, framework,
  runtime/root exact, implementation SHA
  `e3e1e252b48e42554e75899b950692c05186f60d` and tree bound, route counts
  equal, origin hash relationally exact, Preview probes satisfy
  `attempted=passed=mobile+forbidden_base+prior_findings`, Production zero,
  env `3/0/0`, SSO null, no link/alias/domain/API target/token/mutation;
- credential is exact nine-key schema `1`, staging, cleanup/marker bound, with
  token/service-role/user/patient extras absent;
- provisioning is exact schema `1`, purpose `ci3_authenticated_today`, authority
  `5cecaa7af3f2c61f387e4e2d77a2b5e61f2d9a1c`, `TODAY_VERIFIED`, staging,
  implementation SHA/tree bound, exact attempts/fixture/request counts,
  deadline bound, and no primary/production/token/service-role/Vercel/CI start.

Preview deployment count is derived from validated target/state; it is not a
hard-coded receipt claim.

## 4. Remote artifact and deterministic receipt

Final path `/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA/` contains exactly
`mobile-staging-config.json` and `bridge.receipt.json`. Credential is not
copied; no mutable alias exists.

The config has exactly schema, staging, Supabase URL/anon, BFF origin, staging
ref, authority and deadline. The sanitized 30-field receipt binds authority,
generator, all five sources, config, fixed filenames/credential path,
relations/counts and false emission/open controls. `created_at_utc` is the
authority commit timestamp, making repeated rendering deterministic. Receipt
contains no raw origin/key/credential/ID.

There is no synthetic or recovery exception to this schema. Wrong, missing or
extra `purpose` — including a receipt whose hash was also rewritten into a
self-consistent claim — is `PUBLISHED_CONTRACT` and STOP. `--self-test` builds
the same complete schema with synthetic `.invalid` values; it never uses a
permissive alternate receipt.

## 5. Durable budget, no-clobber publication and recovery

Node lacks `renameat2(RENAME_NOREPLACE)`. The implemented equivalent combines
a root-only threat domain, deterministic durable claim and kernel `link(2)`
no-replace with receipt-last commit:

```text
CLAIM=/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA.claim.json
STAGING=/root/.config/agentempp/bridges/ci3/.staging-AUTHORITY_SHA
FINAL=/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA
COMMIT_MARKER=FINAL/bridge.receipt.json
```

Claim is created `O_EXCL|O_NOFOLLOW`, attempt `1`, `no_retry=true`, with
authority/source/config/receipt hashes, then fsynced with parent before
staging. Staging and both `0600` files are deterministic/O_EXCL/fsynced. Final
`0700` is O_EXCL. Config is promoted by no-replace hardlink; its staging link
is removed as transaction completion and final must be `nlink=1`. The
already-fsynced receipt is promoted the same way, last. Until receipt exists
single-link, no bundle is published. Final and parent are fsynced. Claim and
staging directory remain evidence; no cleanup runs.

The receipt-last boundary is explicit: after a crash, `FINAL/` and even
`FINAL/mobile-staging-config.json` can be physically visible before the
receipt. That state is `UNPUBLISHED`, not a partial PASS. Every consumer and
every recovery entrypoint must classify visibility first; absent receipt means
it must not read, install, stream or otherwise consume config. Receipt presence
is only `COMMIT_MARKER_PRESENT_REQUIRES_VALIDATION`; `PUBLISHED`/`EXISTS_VERIFIED`
requires the full no-follow metadata, claim, config and receipt validation.
Thus atomicity is the logical authorization boundary supplied by the
receipt-last marker, while kernel `link(2)` supplies physical no-clobber. Node
core does not claim that the config pathname itself is invisible during this
root-only pre-commit window.

Only the compliant root generator can write this `0700` domain; compromised
root is outside the threat claim. Inside the domain, O_EXCL+link closes the
check/rename race.

Recovery never rereads five sources after a claim. It uses captured
staging/final bytes only: claim without capture STOPs; complete staging resumes;
partial final with exact config completes receipt-last; complete final is
read-only `EXISTS_VERIFIED`. A second rerender is ignored after claim. Any
divergence is preserved and STOPs.

Exact-existing verifies output root/final/files and every directory component:
no symlink, owner/group, `0700/0600`, regular/single-link files, exact entries,
stable no-follow fds and full physical identity before/after, plus complete
authority/source/config/receipt relations.

## 6. Mac B0 and simulator gate — strictly before network

B0 is strictly local/no-network: no fetch, remote Git query, DNS, SSH or remote
read. It reads only already-delivered VPS PASS, local Git objects/worktrees and
frozen manifest. Remote Git/read is after simulator PASS.

Before an SSH claim, publish owner-only
`$HOME/.config/agentempp/ci3/authorities/AUTHORITY_SHA/simulator-gate.receipt.v1.json`.
Schema binds device selection/runtime, exact bundle `com.bodyflow.app`, resolved
container identity, these container-relative destinations, probe schema/hash,
ACK, attempts and typed physical root:

```text
Library/Application Support/Agentempp/mobile-staging-config.json
Library/Application Support/Agentempp/synthetic-patient.credentials.json
```

Phases are `SELECT_DEVICE`, `RESOLVE_CONTAINER`, `INSTALL_PROBE`,
`LAUNCH_PROBE`, `ACK_PROBE`, `REMOVE_PROBE`, `REOBSERVE`; attempts for
resolve/install/launch/consume/remove are one. Every intent/result is
O_EXCL+fsynced. Metadata covers owner/group/type/mode/link/size/hash/dev/inode/
mtime. Symlink, hardlink, mode/inode drift or ambiguous ACK consumes the phase
and STOPs; recovery only reobserves, never relaunches. No trust/read claim may
predate this receipt.

## 7. Version-addressed SSH trust and real effective config

No concrete destination/fingerprint is present in this authority. Operator
variables are forbidden. VPS PASS must pre-deliver by approved controller
channel these exact owner-only Mac paths:

```text
$HOME/.config/agentempp/ci3/authorities/AUTHORITY_SHA/vps-pass.receipt.v1.json
$HOME/.config/agentempp/ci3/authorities/AUTHORITY_SHA/mac-fetch-trust.material
$HOME/.config/agentempp/ci3/authorities/AUTHORITY_SHA/mac-fetch-trust.descriptor.v1.json
$HOME/.config/agentempp/ci3/authorities/AUTHORITY_SHA/ssh_config
$HOME/.config/agentempp/ci3/authorities/AUTHORITY_SHA/known_hosts
```

Missing concrete hashes/files is `STOP_MAC_FETCH_TRUST_AUTHORITY`, never a
fallback. Raw material/config is never printed. The sanitized descriptor is
version-addressed and hash-bound by VPS PASS; it fixes authority/remote
receipt, alias, destination hash, root user, port, all trust-file hashes,
identity path/public-key fingerprint, ED25519 host-key fingerprint,
`/usr/bin/ssh` path/hash/code-signature, OS/OpenSSH version and complete ordered
native-output policy.

The policy has an ordered singleton allowlist and explicit duplicate-capable
keys: `identityfile`, `canonicaldomains`, `globalknownhostsfile`,
`userknownhostsfile`, `sendenv`, `setenv`, `localforward`, `remoteforward`,
`permitremoteopen`. Parser preserves every native line, duplicate, empty/
default value and order. Unknown, absent, reordered or unapproved duplicate
STOPs; no last-write-wins map. Destination/user/port/identity/known-hosts and
strict checking are exact. Agent, inheritance, proxy/jump/command, forwarding,
password, keyboard-interactive, ControlMaster, local command and alternate
destination are disabled.

After simulator PASS execute exactly:

```text
/usr/bin/ssh -G -F "$CI3_AUTHORITY_DIR/ssh_config" "$CI3_DESCRIPTOR_ALIAS"
```

Both variables are derived only from fixed base+verified authority/descriptor,
never operator input. First verify physical/hash/code-signature of SSH and all
trust paths. Persist only executable/signature/effective-config hashes.

## 8. Three reads and non-circular local publication

Only three network reads follow, in order: remote receipt, config, existing
credential. Paths/hashes come solely from VPS PASS/receipt. Each claim is
O_EXCL+fsynced before SSH and binds attempt one/no retry, authority, source
generation, expected hash, SSH/trust and simulator. Remote argv is fixed
`exec /usr/bin/cat -- EXACT_PATH`; stdout is captured, never printed.

Capture stays on one no-follow fd for write/fsync/read/hash and physical
reobservation. Result binds claim/capture hashes, bytes, exit, sanitized stderr
class and times. Claim without result is consumed; recovery never refetches.

Local bundle contains exactly config, credential and
`local-publication.receipt.json`. That receipt is **pre-terminal**: it binds
authority, remote/local hashes, trust/simulator and claim/result/capture roots,
states `PRE_TERMINAL`, and contains no install/scan/PASS claim. Local
publication uses the same claim+receipt-last link no-replace and recovery
contract. This removes B6↔B7 circularity.

## 9. Install, terminal receipt and external anchor

After local revalidation, install only with `/usr/bin/install -m 0600` from
bound local files to the two container-relative destinations. Verify exact
install executable/hash; source/destination owner, regular type, `nlink=1`,
`0600`, size/hash/dev/inode; and physical no-follow readback. Installation
receipt freezes executable, mode, container, destinations, hashes and metadata.

After ACK and removal of only simulator credential copy, scan every authorized
surface independently. Publish separate versioned
`terminal-bridge.receipt.v1.json` under
`$HOME/.config/agentempp/ci3/terminal/AUTHORITY_SHA/TERMINAL_GENERATION_SHA/`.
It binds pre-terminal publication, installation, simulator phases, every scan
hash/counter, claims/results, all 11 Important IDs and `TERMINAL_PASS`. It is
never inside/rewrite of local bundle.

A distinct privileged writer then creates once:

```text
/Library/Application Support/Agentempp/ci3-terminal-authority/AUTHORITY_SHA/TERMINAL_GENERATION_ID/terminal-anchor.json
```

Directory is root-owned `0555`; file uses
`open(O_EXCL|O_NOFOLLOW,0444)`, fsync file/dir and `/usr/bin/chflags uchg`.
Normal bridge execution cannot write/clear it. Anchor fixes authority, terminal
path/hash/physical identity and writer identity hash. Verification requires
exact realpath, root:wheel, regular `0444`, `nlink=1`, `UF_IMMUTABLE`, stable
full identity and controller-returned anchor hash. Self-consistent mutable
rewrite cannot replace the external anchor and STOPs. No anchor is created now.

The writer is a separate authority, never an ambient capability of the Mac or
VPS handoff. Before even preparing an anchor, the executor requires a
controller-supplied, version-addressed and hash-bound
`CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1` receipt. The normal
operation authority binds only the fixed `authority_path` and `manifest_path`;
it cannot pre-authorize content that does not exist before the scans. After
the six scan receipts, the normal controller freezes the source snapshot,
signed binary, terminal preparation receipt and manifest. Only then may an
external privileged controller publish, root:wheel `0444` plus `uchg`, the
authority receipt that binds authority/generation, manifest/source/binary/
signature hashes, the original privileged-claim hash and the authority-path
hash, with `attempt=1`, `retry=false`, `raw_values=false` and
`normal_executor_authorized=false`. Missing,
malformed, relocated or unhashed writer authority is
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`; normal execution cannot
mint, infer or substitute it. This task grants no such authority.

## 10. CI-3 continuity and exact allowlist

Mac B0–B7 supersede only original Task 1 “Operational bridge”. Frozen tasks
retain names: Task 2 transport; Task 3 Today adapter; Task 4 dependency wiring;
Task 5 Today states; Task 6 staging integration; Task 7 XCUI; Task 8 focused/
full gates; Task 9 unsigned builds; Task 10 scans/reviews; Task 11 selective
commit/publication. Authority label “continuation 12” is only final report/
preservation wrapper, not a fabricated implementation task/path.

Exact 23 paths:

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

Five existing Task-1 paths stay preserved. Parent remains
`277873755bf29771a10b5f362b522c2e6a6c21d6`; subject remains
`feat(ios): connect Today to authenticated staging`.

## 11. STOP

Any absent concrete trust, authority/snapshot/hash/metadata/schema/relation
drift, claim ambiguity, capture absence, simulator/SSH/install/scan/anchor or
allowlist mismatch STOPs without retry, overwrite, cleanup or raw output.

## 12. Atualização operacional 1.7.1 — authority executável

Esta atualização sucede o contrato generator-only sem apagar seu histórico.
Os bridges V1/V2/V3 continuam congelados byte a byte e não são executáveis. A
authority 1.7.1 passa a ter treze paths Git: os sete paths anteriores mais o
controller, teste do controller, launcher, teste do launcher, source Swift do
writer e teste do writer. O commit futuro deve ter parent
`9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52` e subject exato
`build(ops): authorize executable CI-3 bridge tooling`.

### 12.1 Launcher e provenance

`scripts/ci3/ci3-bridge-launcher.zsh` é o único entrypoint Mac. Ele aceita
somente `--self-test`, `plan`, `verify-simulator`, `verify-ssh`, `fetch`,
`install-simulator`, `scan`, `write-terminal-anchor`, `resume` e `status`; usa
`set -euo pipefail`, `umask 077`, resolve o Git root, lê os treze blobs somente
por `git cat-file`, materializa snapshots 0600 em diretório 0700 e rejeita
qualquer divergência do próprio launcher. A launch attestation V2 liga commit,
parent, tree, hash do subject, hash do manifest ordenado dos treze paths, os
blobs/hashes de generator/controller/launcher/writer e hashes de path/binário/
versão de Node, `/usr/bin/ssh`, Swift e Xcode. Somente o controller snapshot
Git-bound é executado. Não há `eval`, env sourcing, tracing, host/path remoto,
credential ou output arbitrário.

### 12.2 Um controller e uma máquina de estados

`scripts/ci3/ci3-bridge-controller.mjs` contém a única máquina de estados:

```text
INIT -> AUTHORITY_VERIFIED -> WORKTREE_VERIFIED -> SIMULATOR_VERIFIED
-> SSH_VERIFIED -> RECEIPT_FETCHED -> CONFIG_FETCHED -> CREDENTIAL_FETCHED
-> LOCAL_PUBLISHED -> INSTALLED -> CREDENTIAL_REMOVED -> SCANNED
-> WRITER_INVOKED -> ANCHOR_VERIFIED -> COMPLETE
```

O bootstrap claim é criado somente depois do gate de simulador e de
`/usr/bin/ssh -G`. Cada um dos três reads tem claim original O_EXCL antes do
spawn e result separado, ligando bootstrap, path/hash esperado, provenance SSH,
generation, capture hash, bytes, timestamps, exit e stderr class. `attempt=1`,
`retry=false`. Claim sem capture/result consome o budget e bloqueia refetch;
claim+capture/result permite somente recovery local. Capture, bundle, install,
result ou anchor sem claim original produz
`REJECT_UNCLAIMED_EXISTING_STATE`. Nenhuma recuperação cria claim retroativo,
muda generation, apaga evidência ou reabre rede.

Generations fechadas:

```text
remote-<sha256>
controller-<sha256>
simulator-<sha256>
terminal-<sha256>
```

### 12.3 Trust e simulador

O trust descriptor futuro é sanitizado, version-addressed, owner-only e
fornecido exclusivamente pelo VPS PASS com seu SHA-256. O controller não aceita
fallback por argv/env. Ele fixa `/usr/bin/ssh`, config e known_hosts isolados,
destino único/root/porta/identity, fingerprints de chave pública e host ED25519,
agent/password/kbd/ProxyJump/ProxyCommand/forwarding/ControlMaster desligados e
nenhuma herança user/global. A saída nativa completa de
`/usr/bin/ssh -G -F <ISOLATED_CONFIG> <ALIAS>` é preservada em ordem, incluindo
duplicatas/defaults, canonicalizada e hashada; raw destination nunca é
reportado. Falta do descriptor/hash concreto é `STOP_MAC_FETCH_TRUST_AUTHORITY`.

O simulador é gate B0 estritamente local e anterior a qualquer Git remoto ou
SSH. As fases exatas são `SELECT_DEVICE`, `RESOLVE_CONTAINER`, `INSTALL_PROBE`,
`LAUNCH_PROBE`, `ACK_PROBE`, `REMOVE_PROBE`, `REOBSERVE`. O receipt liga device,
runtime, Debug app, source commit, bundle id `com.bodyflow.app`, container físico
sem symlink, config/credential probe 0600, ACK, remoção e uma tentativa por fase,
sem raw container path. Qualquer read remoto antes de `SIMULATOR_GATE_PASS`
é proibido.

### 12.4 Publicação, instalação e boundary de visibilidade

O bundle Mac fica em
`$HOME/.config/agentempp/ci3/bundles/AUTHORITY_SHA/REMOTE_GENERATION_ID/`.
Claim determinístico O_EXCL+fsync precede staging. Config e credential são
criados com `O_EXCL|O_NOFOLLOW`, 0600, single-link e identidade física completa;
files e diretório recebem fsync. Publicação no-replace ocorre somente quando o
target está ausente. O commit-marker `local-bridge.receipt.json` é publicado por
último e nunca regravado: diretório/config podem existir durante recovery, mas
todo consumer os trata como **UNPUBLISHED** enquanto o receipt estiver ausente.
Exact-existing exige receipt original, claim original e igualdade de bytes,
authority, generations, components, predecessor/successor e metadata
`uid/gid/mode/nlink/size/mtime/dev/ino` antes/depois. Essa é a fronteira
receipt-last; nenhum consumer adota estado parcial.

Instalação usa `/usr/bin/install -m 0600` somente nos paths relativos
`Library/Application Support/Agentempp/mobile-staging-config.json` e
`Library/Application Support/Agentempp/synthetic-patient.credentials.json`
dentro do container resolvido. Owner/type/nlink/mode/inode/hash/readback são
verificados fisicamente. Após ACK real, somente a cópia da credential no
simulador é removida e reobservada; o bundle canônico Mac permanece.

### 12.5 Scans e writer privilegiado

Os seis IDs, nesta ordem e sem normalização, são:

```text
argv
history
terminal-log
attachment
xcresult
runtime
```

Cada receipt liga authority, controller/remote/simulator/terminal generations,
bundle local, install, diff, input manifest, tool/command, timestamps, output,
`CLEAN`, `match_count=0`, `redaction=true` e
`input_stable_after_scan=true`. Missing/extra/duplicate/out-of-order, generation
antiga, scan anterior a publication/install ou input alterado STOP.

O writer `scripts/ci3/ci3-terminal-anchor-writer.swift` é compilado do blob
exato para binary owner-only por `xcrun swiftc`; source, binary e assinatura são
hash-bound. O production binary aceita somente `--write`, path fixo do manifest
sanitizado e os quatro IDs de authority/generation. Ele não lê secret/body e
não aceita test root no build de produção. Uma authority privilegiada externa,
original e O_EXCL deve existir antes da única elevação administrativa macOS;
senha nunca passa pelo controller/Codex e não existe helper/daemon/socket.

Output fixo:

```text
/Library/Application Support/Agentempp/ci3-terminal-authority/
  AUTHORITY_SHA/TERMINAL_GENERATION_ID/terminal-anchor.json
```

O writer reabre cada evidência com `O_NOFOLLOW`, exige regular/single-link/0600,
compara hash e metadata completa antes/fd/depois, valida os quatro components,
quatro generations, todos os claims/results, simulator/install, seis scans e
terminal state. Publica uma vez com `O_EXCL`, 0444, root:wheel, fsync file/parent,
`UF_IMMUTABLE`, readback e link count 1. Exact-existing requer o privileged
claim original e byte equality. A execução normal jamais pode criar, regravar
ou inferir essa authority. Se a authority/writer privilegiado não estiver
explicitamente autorizado, o resultado obrigatório é
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`; esta authoring operation não
criou anchor nem concedeu privilégio.

### 12.6 Matriz final sem deduplicação

| ID | fechamento executável | receipt | anchor |
|---|---|---|---|
| `RA-FINAL-I-1` | launcher Git-bound alcançável | `launcher_blob_oid` | `components.launcher` |
| `RA-FINAL-I-2` | exact-existing exige claim original e provenance completa | `bootstrap_claim_sha256` | `claim_result_chain_sha256` |
| `RA-FINAL-I-3` | seis scans fechados e input revalidado | `scan_receipts` | `scan_receipts` |
| `RA-FINAL-I-4` | anchor fecha authority e quatro generations | `terminal_generation_id` | `generations` |
| `RA-FINAL-I-5` | authority privilegiada externa e hash-bound | `writer_authority_path_sha256` | `privileged_claim_sha256` |
| `RA-FINAL-I-6` | contagens/finding IDs atuais | `important_finding_ids` | `important_finding_ids` |
| `RB-FINAL-I-1` | launcher executa somente controller snapshot | `controller_blob_oid` | `components.controller` |
| `RB-FINAL-I-2` | controller Mac único e state machine fechada | `controller_generation_id` | `generations.controller` |
| `RB-FINAL-I-3` | parser da saída real completa de `ssh -G` | `ssh_provenance_sha256` | `ssh_provenance_sha256` |
| `RB-FINAL-I-4` | gate simulador sete fases antes de claim | `simulator_gate_sha256` | `simulator_gate_sha256` |
| `RB-FINAL-I-5` | scanner fecha as seis superfícies literais | `scan_ids` | `scan_receipts` |
| `RB-FINAL-I-6` | writer exige privileged claim original | `writer_claim_sha256` | `privileged_claim_sha256` |
| `RB-FINAL-I-7` | install/readback físico congelado | `install_receipt_sha256` | `simulator_install_sha256` |
| `RA-FINAL-M-1` | contagem antiga substituída por ledger 1.7.1 | `test_counts` | `important_finding_ids` |
| `RB-FINAL-M-1` | nomenclatura/handoff alinhados aos Tasks originais | `continuation_contract` | `authority_sha` |

### 12.7 Estado desta operação

Os testes locais/sintéticos cobrem generator, controller, launcher, writer e 48
casos E2E do mesmo state machine. A única chamada nativa SSH é `ssh -G` sobre
config sintética isolada e não abre conexão. Nenhum `--create`, SSH connect,
rede, simulador real, install real, stream, privilégio, remote bundle, anchor,
Task 2, provider, produção, commit ou push foi executado. A implementação ainda
depende de reviews independentes e de um único commit controller para virar
authority; não é permitido overclaim `PUBLISHED` antes disso.

### 12.8 Dispatch operacional e boundary pós-scan

Os modos públicos não são stubs. Com launch attestation e operation authority
válidas, `plan`, `verify-simulator`, `verify-ssh`, `fetch`,
`install-simulator`, `scan`, `write-terminal-anchor`, `resume` e `status`
alcançam, respectivamente, fases reais da mesma máquina de estados. A
authoring operation exercitou somente adapters sintéticos; o dispatch de
produção permanece fail-closed e não foi chamado.

`scan` encerra a fase normal: persiste os seis receipts, compila e assina o
writer a partir do snapshot Git-bound, congela 62 evidências, publica o
`CI3_TERMINAL_PREPARATION_RECEIPT_V1` e o manifesto por O_EXCL/fsync. Nenhum
admin prompt ocorre nessa fase. `write-terminal-anchor` reabre tudo
fisicamente, exige o receipt privilegiado externo imutável e o claim original,
e só então permite a única invocação administrativa. Ausência ou drift em
qualquer um deles é
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`; o executor normal nunca
possui authority para mintar esse receipt.

Contagens GREEN finais desta rodada: generator `152`, controller `383`,
launcher `46`, writer `122`; `0` fail/cancelled/skipped/todo. Os `48` testes
E2E percorrem individualmente todos os efeitos da state machine. RED adicional pós-review: authority
privilegiada `14/14` falhou antes da validação existir; GREEN `14/14` após o
fechamento. A surface-authority dos seis scans teve RED `0/7` e GREEN `7/7`,
impedindo observer vazio ou path duplicado.

O manifest Git exige mode `100755` para launcher e controller e `100644` para
o source Swift. O launcher valida esses três modes no commit antes de despachar
o controller. `COMPONENT_MISSING` no self-test direto pré-commit é o STOP
esperado enquanto HEAD não contém os blobs novos; uma fixture com os treze
paths prova a transição pós-commit para PASS sem relaxar esse STOP.

## 13. Contrato executável fechado após o Round 1

### 13.1 Authority única e manifest resolvível

O único subject admissível é
`build(ops): authorize executable CI-3 bridge tooling`, com parent
`9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52`. O commit futuro contém exatamente
estes treze paths, nesta ordem; launcher e controller usam mode `100755`, os
demais `100644`:

```text
docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md
docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md
docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md
docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md
docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md
scripts/ci3/create-ios-staging-bridge-config.mjs
scripts/ci3/create-ios-staging-bridge-config.test.mjs
scripts/ci3/ci3-bridge-controller.mjs
scripts/ci3/ci3-bridge-controller.test.mjs
scripts/ci3/ci3-bridge-launcher.zsh
scripts/ci3/ci3-bridge-launcher.test.mjs
scripts/ci3/ci3-terminal-anchor-writer.swift
scripts/ci3/ci3-terminal-anchor-writer.test.mjs
```

OID e SHA-256 não podem ser gravados dentro dos próprios treze blobs sem
circularidade. O controller do commit único os resolve e publica em receipt
write-once. Para cada path literal acima, a resolução obrigatória é:

```sh
OID=$(/usr/bin/git rev-parse "$AUTHORITY_SHA:$AUTHORITY_PATH")
SHA256=$(/usr/bin/git cat-file blob "$AUTHORITY_SHA:$AUTHORITY_PATH" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
MODE=$(/usr/bin/git ls-tree "$AUTHORITY_SHA" -- "$AUTHORITY_PATH" | /usr/bin/awk '{print $1}')
```

Qualquer path ausente/extra/duplicado, mode diferente, OID/hash não hexadecimal,
parent/tree/subject divergente ou receipt regravável é `STOP_PRE_AUTHORITY`.

### 13.2 Handoff VPS autocontido, futuro e não executado

Inputs obrigatórios: `AUTHORITY_SHA`, `VPS_NODE_PATH` e
`VPS_NODE_SHA256`, todos vindos do PASS do controller; nenhum é aceito de
ambiente livre. O launcher VPS é o snapshot versionado abaixo, não o source
mutável do checkout:

```sh
case "$AUTHORITY_SHA" in (*[!0-9a-f]*|'') exit 70;; esac
test "${#AUTHORITY_SHA}" -eq 40 || exit 70
test "$(/usr/bin/git rev-parse "$AUTHORITY_SHA^")" = 9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52 || exit 70
test "$(/usr/bin/git show -s --format=%s "$AUTHORITY_SHA")" = 'build(ops): authorize executable CI-3 bridge tooling' || exit 70
test -f "$VPS_NODE_PATH" -a ! -L "$VPS_NODE_PATH" -a -x "$VPS_NODE_PATH" || exit 70
test "$(/usr/bin/shasum -a 256 "$VPS_NODE_PATH" | /usr/bin/awk '{print $1}')" = "$VPS_NODE_SHA256" || exit 70
GENERATOR_REL=scripts/ci3/create-ios-staging-bridge-config.mjs
GENERATOR_OID=$(/usr/bin/git rev-parse "$AUTHORITY_SHA:$GENERATOR_REL") || exit 70
GENERATOR_SHA256=$(/usr/bin/git cat-file blob "$AUTHORITY_SHA:$GENERATOR_REL" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}') || exit 70
LAUNCH_DIR="/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA"
/usr/bin/install -d -o root -g root -m 0700 "$LAUNCH_DIR" || exit 70
GENERATOR_FINAL="$LAUNCH_DIR/create-ios-staging-bridge-config.mjs"
GENERATOR_TEMP=$(/usr/bin/mktemp "$LAUNCH_DIR/.generator.XXXXXXXX") || exit 70
/usr/bin/git cat-file blob "$AUTHORITY_SHA:$GENERATOR_REL" > "$GENERATOR_TEMP" || exit 70
/bin/chmod 0600 "$GENERATOR_TEMP" || exit 70
test "$(/usr/bin/git hash-object "$GENERATOR_TEMP")" = "$GENERATOR_OID" || exit 70
test "$(/usr/bin/shasum -a 256 "$GENERATOR_TEMP" | /usr/bin/awk '{print $1}')" = "$GENERATOR_SHA256" || exit 70
if ! /bin/ln "$GENERATOR_TEMP" "$GENERATOR_FINAL" 2>/dev/null; then
  /usr/bin/cmp -s "$GENERATOR_TEMP" "$GENERATOR_FINAL" || exit 70
fi
/bin/rm -f "$GENERATOR_TEMP" || exit 70
test "$(/usr/bin/stat -c '%u:%g:%a:%h' "$GENERATOR_FINAL")" = '0:0:600:1' || exit 70
"$VPS_NODE_PATH" "$GENERATOR_FINAL" --self-test || exit 70
"$VPS_NODE_PATH" "$GENERATOR_FINAL" --create || exit 70
```

`--create` abre com `O_NOFOLLOW` os cinco inputs fixos, valida owner/mode/nlink/
size/dev/ino/mtime e os hashes congelados, cria claim determinística
`<root>/<authority>/<remote-generation>.claim.json` por `O_EXCL`+fsync, publica
por staging no mesmo filesystem e usa hard-link no-replace. Config pode ficar
fisicamente visível durante recovery, mas somente
`bridge.receipt.json` é commit marker; receipt ausente é `UNPUBLISHED` para
todo consumidor. Recovery usa claim/bytes já capturados, não cria generation e
não relê source. O PASS VPS retorna somente hashes, paths versionados e o
descriptor SSH sanitizado; nunca raw destination/origin/credential.

### 13.3 Publisher privilegiado e handoff Mac

Antes de qualquer modo operacional, uma autoridade humana/externa distinta
deve instalar uma cópia exata do runtime Node em
`/Library/Application Support/Agentempp/ci3-controller-authority/<authority>/runtime/node`
como root:wheel `0555`, `nlink=1`, `uchg`; e publicar no mesmo root
`mac-operation-authority.v1.json` root:wheel `0444`, `nlink=1`, `uchg`. O
receipt liga commit/parent/tree/manifest, quatro component OIDs/hashes, quatro
generations, worktree congelado, B0 simulator, descriptor SSH completo,
três paths remotos por hash, seis scan inputs e os dois paths fixos do writer.
Esse publisher é o modo separado `publish-operation-authority` do launcher,
consome receipt humano próprio e não pertence à state machine operacional;
authority/request ausente é `STOP_PRE_AUTHORITY`.

O operador Mac então executa somente o launcher oficial:

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

`verify-simulator` conclui sete claims/results/receipts físicos antes de Git
remoto ou SSH. `verify-ssh` executa somente `/usr/bin/ssh -G -F <isolated>
<alias>` e compara o stream ordenado duplicate-aware ao descriptor. `fetch`
faz exatamente três spawns, cada qual com claim original, command
`exec /usr/bin/cat -- <exact-path>`, stdout diretamente em fd `O_EXCL`, result
e capture receipt; recovery nunca refaz a read. O bundle local usa diretório
staging, final no-replace e receipt-last. `install-simulator` congela
`/usr/bin/install -m 0600`, destinations relativas ao container e readback.
`scan` usa scanners/schemas/counters independentes para `argv`, `history`,
`terminal-log`, `attachment`, `xcresult`, `runtime` e reabre todos inputs antes
do terminal.

Após `scan`, o modo privilegiado separado compila os bytes Git-bound via stdin
com `/usr/bin/xcrun swiftc -parse-as-library - -o <binary>`, assina
e instala o binary verificado em
`/Library/Application Support/Agentempp/ci3-terminal-authority/<authority>/<terminal-generation>/writer/ci3-terminal-anchor-writer`
root:wheel `0555`, `nlink=1`, `uchg`. Ele publica e fsynca por O_EXCL o claim
original antes da instalação final do writer e então cria o receipt
`CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1`, root:wheel
`0444`, `nlink=1`, `uchg`, ligando executable path/identity/hash,
source/signature/manifest/claim/anchor paths e hashes. A execução normal não
pode publicar esse receipt. Sem autoridade explícita do publisher:
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`; nenhum handoff presume ou
transfere esse privilégio.

O writer root reabre authority, claim, manifest, 62 evidence roles e seis
inputs com `O_NOFOLLOW`; recomputa components/generations/claims/results/
simulator/install/scans, publica anchor root:wheel `0444` por `O_EXCL`, fsync e
`uchg`, e faz readback físico. O ledger terminal contém, sem deduplicação:
`RA1-I-5`, `A4-I-1`, `A4-I-3`, `A5-I-1`, `A5-I-2`, `RA0-I-4`, `RA0-I-7`,
`R2-I-2`, `R5-I-1`, `R5-I-2`, `R5-I-3`, `RA-FINAL-I-1`..`RA-FINAL-I-6` e
`RB-FINAL-I-1`..`RB-FINAL-I-7`.

Os 48 E2E Round 1, preservados como histórico e superseded pela matriz Round 3,
percorriam a state machine com claims/results duráveis. Nada
deste protocolo real foi executado nesta authoring operation.

## Superseding executable closure — Round 2

Esta seção substitui toda frase anterior que dizia que os dois publishers não
estavam implementados. Eles agora são modos fechados do launcher Git-bound:
`publish-operation-authority` e `publish-privileged-writer-authority`. A
existência do código não concede autoridade: cada modo consome um receipt humano
versionado, apresenta exatamente um prompt administrativo e falha antes de
qualquer efeito se o receipt, os hashes ou a geração divergirem. Nenhum dos dois
modos foi executado nesta authoring operation.

### Publisher 1: Node e operation authority

O único input é
`~/.config/agentempp/ci3/publisher-input/<authority>/operation-authority.publisher-request.json`,
`0600`, no-follow/single-link. Seu schema exato é `schema_version=1`,
`purpose=CI3_OPERATION_AUTHORITY_PUBLISHER_REQUEST_V1`, `authority_sha`,
`authority_candidate_path/sha256`, `node_candidate_path/sha256`,
`publisher_input_manifest_path/sha256`,
`vps_operation_authority_pass_path/sha256`,
`human_authorization_receipt_path/sha256`, `attempt=1`, `retry=false`,
`raw_values=false`. Os valores não são livres: authority, manifest, Node,
collector contract root e transfer payload vêm do PASS VPS versionado e são
cruzados com o launch attestation do commit. O receipt humano
tem schema exato
`CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V1`, liga authority manifest,
Node, operation-authority e a ação literal
`PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY`.

O modo cria uma geração nova com `mkdir` no-clobber, instala Node/controller
`0555` e authority/human receipt/VPS PASS/input manifest `0444`,
verifica cada SHA-256 dentro do domínio root, faz `root:wheel`, `nlink=1`,
`chflags uchg`, fsync de cada arquivo e diretório e só emite o PASS sanitizado.
Uma geração já existente não é adotada nem reescrita. O launcher posterior
aceita apenas o Node version-addressed root-owned/immutable e o controller volta
a reabrir o operation receipt `0444` pelo mesmo inode antes de B0.

### Publisher 2: writer privilegiado

Depois de `scan`, o input humano único é
`~/.config/agentempp/ci3/publisher-input/<authority>/<terminal-generation>/privileged-writer.publisher-authorization.json`,
schema exato `CI3_PRIVILEGED_WRITER_PUBLISHER_AUTHORIZATION_V1`, com authority,
terminal generation, hashes do manifest/source/binary, `human_authorized=true`,
`attempt=1`, `retry=false`, `raw_values=false`. O candidate é recompilado dos
bytes Git-bound via stdin usando `swiftc -parse-as-library`, assinado e
revalidado antes do prompt.

O publisher cria o diretório terminal por `mkdir` exclusivo; publica primeiro
o original claim `CI3_PRIVILEGED_TERMINAL_ANCHOR_CLAIM_V1` root-owned `0444`,
fsynca claim/diretório e somente depois instala o writer final `0555`. O Node
imutável do Publisher 1 reabre o binary instalado, verifica hash e metadata e
calcula a identidade física completa
`uid/gid/mode/nlink/size/mtime_ns/dev/ino`. Ele então cria com `wx` o
`privileged-authority.receipt.json` que liga claim, manifest, source, binary,
signature, paths de authority/manifest/anchor/executable e essa identidade.
Binary, claim e receipt tornam-se `root:wheel`, single-link, `uchg`; arquivos e
diretórios são fsyncados. O controller exige o claim root original e uma cópia
byte-idêntica junto ao manifest; o writer reabre essa cópia e a valida contra o
receipt root. Ausência de autoridade humana ou do writer root resulta em STOP,
nunca em autoridade implícita.

### Recovery físico e publicação local

Cada fase durável cria claim antes do efeito, physical receipt antes do result
e event por último. Um claim sem physical receipt é ambíguo e resulta em
`CLAIM_CONSUMED_NO_RESULT`; o efeito jamais é repetido. Um physical receipt
existente é reaberto no-follow e o observation hash é recalculado dos bytes e
de `uid/gid/mode/nlink/size/mtime_ns/dev/ino`; somente então o result/event
faltante pode ser recuperado. Estados físicos sem claim original são
`REJECT_UNCLAIMED_EXISTING_STATE` para bundle e install.

A publicação do bundle não cria arquivos canônicos individualmente. Config,
credential e receipt são fsyncados dentro de um único staging determinístico
`0700`; um helper Swift estreito mantém fds/identidades do staging e parent e
executa `renameatx_np(..., RENAME_EXCL)`. Após o syscall ele exige que o inode
do staging seja o inode do final, que staging desapareceu, que os três filhos
continuam single-link `0600` e que o parent foi fsyncado. Corrida ou final
preexistente preserva staging como evidência e STOPa.

### Evidence e terminal recomputation

O manifest transporta o manifest literal ordenado de 13 paths, launch
attestation, bootstrap, três read claims/results/captures, remote/local receipt,
SSH provenance, install receipt, os sete trios simulator claim/physical
receipt/result e os sete trios controller claim/physical receipt/result que
precedem o scan. O writer Swift exige roles exatas, reabre cada input,
recomputa schemas, relações, hashes e physical observation roots e rejeita
qualquer rewrite autoconsistente de um campo ignorado. Os seis scanners são
contratos distintos e fixos (`argv`, `history`, `terminal-log`, `attachment`,
`xcresult`, `runtime`), com collector version, format, path, patterns e schema
hash próprios; caller nenhum escolhe path arbitrário.

Os 48 E2E Round 2, agora superseded pela matriz Round 3, eram oito fases por seis boundaries: before-claim,
after-claim, after-effect, after-receipt, after-result e after-event. Cada caso
injeta seu crash na mesma state machine, retoma o ledger e prova zero repetição
de efeito; claim/effect sem receipt termina em STOP, e receipt/result/event
durável recupera deterministicamente.

## 15. Round 3 authority contract — superseding normative text

This section supersedes every earlier 48-scenario, 59-role, prepublished scan
surface, or 703-test statement.

### 15.1 Publisher 1 input authority

Publisher 1 accepts exactly one owner-only request binding five inputs:
operation-authority candidate, Node candidate, human authorization receipt,
publisher input manifest and VPS operation-authority PASS. The input manifest
has purpose `CI3_VPS_PUBLISHER_INPUT_MANIFEST_V1`, exactly two materialized
entries (`operation-authority`, `node-runtime`), path hashes, byte hashes,
authority/remote/controller generations, collector-contract root and transfer
payload root. The PASS has purpose `CI3_VPS_OPERATION_AUTHORITY_PASS_V1` and
binds authority parent/tree/subject/manifest, source/remote/controller
generations, both candidate hashes, input-manifest hash, collector-contract
root and transfer payload root. Human authorization independently binds the
PASS and input-manifest hashes. Missing transfer-controller or privileged-
publisher authority is STOP; no ordinary Mac/VPS handoff implies it.

Publisher 1 installs immutable Node/controller plus operation authority,
human receipt, VPS PASS and input manifest. It MUST NOT install terminal
surfaces or collector receipts. All values are supplied by the trusted VPS PASS
and hash-bound before the admin prompt; none may be entered as a free variable.

### 15.2 Typed effect observation and simulator non-adoption

Every durable phase receipt contains a typed observation derived by reopening
the actual effect target. The result's `physical_observation_sha256` is the
canonical observation hash, never the receipt's own byte/metadata hash.
Recovery invokes only the typed observer and compares the complete persisted
observation; it never repeats the effect. An effect that cannot be reobserved
unambiguously is `CLAIM_CONSUMED_NO_RESULT` or recovery divergence, not PASS.

Before the original simulator claim, config, credential and ACK are absent.
Before `INSTALL_PROBE` and `LAUNCH_PROBE` claims, the relevant absence is
rechecked. Original install/launch runs once. Recovery reopens the physical
device/runtime/container, installed bytes, ACK and terminal absence. A matching
preexisting probe cannot acquire provenance retroactively.

### 15.3 Current-generation scanner contract

Authority fixes six collector contracts, not six prebuilt inputs. Only after
the operation creates its final sources does the controller construct
generation-bound `argv`, `history`, `terminal-log`, `attachment`, `xcresult`
and `runtime` surfaces from fixed authenticated source roles. A surface carries
authority/controller/terminal generations and the source byte/identity roots.
Each collector receipt binds its literal ID, collector version, format,
source-role, controller tool, command root, scanner-schema root, final input
path/hash/metadata, counters, exact output root and post-scan reobservation.
Caller-chosen paths, stale surfaces and VPS-published fixtures are invalid.

The SSH provenance records two different roots:
`identity_public_key_sha256` hashes public-key bytes, while
`identity_public_key_fingerprint_sha256` hashes the fingerprint command output.
Both are cross-bound to the concrete trust descriptor and recomputed by the
writer.

### 15.4 Non-circular terminal settlement

The pre-terminal manifest contains exactly 62 roles: 17 central roots, seven
simulator claim/receipt/result triples and eight controller triples through
`RUN_SCANS`. `terminal-preparation.receipt.json` binds the physical
`RUN_SCANS` result. Two versioned contracts then authorize
`INVOKE_WRITER` and `VERIFY_ANCHOR`; the second contract's predecessor is the
first contract hash and the first is rooted in the `RUN_SCANS` result. The
anchor therefore does not contain or authorize its own hash.

The privileged Swift writer MUST independently recompute every edge among the
literal authority manifest, launch attestation, claims, results, commands,
captures, remote/local receipts, SSH descriptor/provenance, simulator phases,
install receipt, scan inputs/commands/schemas/outputs, terminal receipt and
settlement contracts. Schema-valid or self-consistent rewrites are rejected
before the root-owned O_EXCL anchor write.

### 15.5 Verification matrix and current boundary

The current matrix is 60 scenarios: ten durable phases by six crash boundaries
(`before-claim`, `after-claim`, `after-effect`, `after-receipt`,
`after-result`, `after-event`). Each scenario executes the official Git-bound
launcher and the compiled `CI3_SYNTHETIC_TEST` writer. Current local counts are
152 generator + 408 controller + 108 launcher + 128 writer = 796 PASS, zero
fail/cancel/skip/todo. This evidence is synthetic and grants no real publisher,
SSH, simulator, anchor, commit/push or Task-2 authority.

## 16. Round 4 executable closure contract

This section supersedes the stale counts and any earlier sentence that called
the pre-anchor terminal PASS. The lifecycle has two non-circular publications:

1. `pre-anchor.json` is root-owned, append-only/no-clobber and has exactly
   `terminal_state=PENDING_VERIFICATION`. Its manifest state is
   `PRE_ANCHOR_PENDING_SETTLEMENT`.
2. `terminal-settlement.json` is a later root-owned append-only/no-clobber
   receipt. The privileged writer reopens the pre-anchor and the actual
   claim/receipt/result files for `INVOKE_WRITER` and `VERIFY_ANCHOR`. Only this
   second artifact may contain `terminal_state=TERMINAL_PASS`.

The normal controller is not the terminal authority. Settlement requires the
version-addressed root-owned writer binary and its separately published
`CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1`. If the real privileged
writer authority, its writer binary, or the external issuer material is absent,
the future run MUST return `STOP_PRE_AUTHORITY`; a handoff MUST NOT silently
infer or mint that authority.

### 16.1 External VPS issuer and Publisher 1

The VPS PASS is authenticated by an externally supplied, root-owned immutable
`CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1`. It freezes an Ed25519 public key,
issuer generation/identity, authority commit, allowed PASS purpose and
`normal_executor_authorized=false`. No real public key is embedded here or in
the implementation. Publisher 1 verifies the canonical signed PASS, operation
authority, publisher input manifest, human authorization and SSH roots before
the prompt. Its privileged script then installs Node/controller and these
seven immutable records under the versioned authority root:

```text
mac-operation-authority.v1.json
human-authorization.receipt.json
vps-operation-authority.pass.json
vps-issuer-authority.receipt.json
publisher-input.manifest.json
ssh-trust-descriptor.json
ssh-identity.pub
```

It hashes every installed target, including the human receipt, before
chown/mode/`uchg`, then reopens every root-owned target after the prompt and
checks owner, type, single link, exact mode, immutable flag and hash. A source
swap therefore stops and preserves evidence; it cannot yield Publisher PASS.

### 16.2 Privileged recomputation and physical recovery

The writer reconstructs the literal 13-line Git authority manifest and hashes
those reconstructed bytes. It cross-binds the root-installed operation
authority, signed VPS PASS, issuer, human receipt, publisher manifest, SSH
descriptor, public-key bytes and freshly recomputed `ssh-keygen` fingerprint.
In production those roots must have their exact versioned `/Library/Application
Support/Agentempp/ci3-controller-authority/<AUTHORITY>/...` paths.

Every durable phase observation carries its absolute authority-fixed target
path and full physical metadata. A settled-event resume always invokes the
current typed observer and compares the complete observation. Read-only
worktree, simulator and SSH verification sources are reobserved; `RUN_SCANS`
reopens the six receipts, six generation-bound final surfaces and the six
semantic sources (or the explicit current-generation `xcresult` absence).

The six source contracts remain literal and independent:

- `argv`: actual controller invocation record;
- `history`: current phase claim/physical-receipt/result history;
- `terminal-log`: current controller event transcript;
- `attachment`: current evidence attachment roots;
- `xcresult`: actual fixed result path, or a hash-bound proof of absence;
- `runtime`: current controller executable/version environment record.

No receipt is renamed to impersonate a source. Each source uses a fixed
`final-sources/<id>.surface` path, a complete byte range and physical identity;
the writer reopens it and reruns all six closed scanners.

### 16.3 Integrated synthetic matrix

The 60 cases are no longer label-only self-tests. Each case creates a fresh
13-path synthetic Git authority commit, enters through the executable Git-bound
launcher, injects one crash at its selected phase/boundary, resumes without
effect replay or returns the durable after-claim STOP, and invokes the compiled
Swift test build as the actual `INVOKE_WRITER` effect. The fresh dimensions are
152 generator, 434 controller, 108 launcher and 137 writer tests: 831 total.

All Round 4 runs remain synthetic/local. No real key, VPS transfer, SSH
connection, simulator mutation, privilege prompt, root publication, terminal
anchor, Task 2, commit or push is authorized or claimed.

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

## Round 6 executable trust boundary (normative)

### Publisher 0 is not the worktree launcher

The Git worktree launcher MUST reject `publish-vps-operation-authority-pass`.
Root MUST NOT execute that launcher, a checkout-resolved controller, `env node`,
`command -v node`, an inherited `PATH`, `NODE_OPTIONS`, or any user-provided
startup environment. Publisher 0 begins only at an externally installed,
root-owned immutable bootstrap under the exact version address:

```text
/var/lib/agentempp/ci3-publisher0-bootstrap/<AUTHORITY_SHA>/<BOOTSTRAP_GENERATION_ID>/
  publisher0-bootstrap-authority.json  root:root 0444 immutable
  runtime/node                         root:root 0555 immutable
  runtime/ci3-bridge-controller.mjs    root:root 0555 immutable
```

`AUTHORITY_SHA` and `BOOTSTRAP_GENERATION_ID` are read from the external issuer
receipt; they are never free environment variables. The external issuer root is
`/etc/agentempp/ci3-publisher0-issuers/<AUTHORITY_SHA>.json`, root-owned,
single-link, `0444`, immutable. The bootstrap authority is
`CI3_VPS_PUBLISHER0_BOOTSTRAP_AUTHORITY_V1` and binds the issuer receipt hash,
the absolute Node/controller paths and hashes, the authority and bootstrap
generations, `user_checkout_executable=false`, and the exact environment
`HOME=/var/empty`, `LANG=C`, `PATH=/usr/bin:/bin`.

The separately authorized root materializer validates every directory from
`/var` through the generation using no-follow dirfds, rejects a symlink,
non-root owner, writable mode or identity change, verifies the issuer and
component hashes, promotes the complete directory no-clobber, fsyncs it and its
parent, reapplies immutability, and reopens every component. Only then may it
execute this exact vector:

```text
/usr/bin/env -i HOME=/var/empty LANG=C PATH=/usr/bin:/bin \
  <ROOT_OWNED_BOOTSTRAP>/runtime/node \
  <ROOT_OWNED_BOOTSTRAP>/runtime/ci3-bridge-controller.mjs \
  publish-vps-operation-authority-pass
```

The angle-bracket values are resolved exclusively from the already verified
external receipt, not typed or exported by the normal executor. Missing
external issuer, root materializer, immutable bootstrap, exact hash, directory
identity, or clean environment is `STOP_PRE_AUTHORITY`. No such root
materializer or real key is created by this bundle.

Publisher 0 produces one Ed25519-authenticated no-clobber VPS PASS and a
transfer manifest. Publisher 1 transports the fixed manifest with an
authority-pinned authenticated transport, opens a new Mac staging directory by
dirfd, copies only manifest-listed bytes, fsyncs, promotes no-clobber, installs
the operation authority and SSH snapshots root-owned/immutable, reopens all
bytes/metadata, then consumes the separate human authorization. No user path is
reopened after verification.

### Frozen SSH snapshot and policy

Publisher 1 installs this exact generation root:

```text
/Library/Application Support/Agentempp/ci3-controller-authority/<AUTHORITY_SHA>/ssh-snapshots/<CONTROLLER_GENERATION_ID>/
  ssh_config
  known_hosts
  id_ed25519
  id_ed25519.pub
  ssh-trust-descriptor.json
```

All five paths are bound by the externally authenticated operation authority,
root-owned, single-link, no-follow and immutable. The controller verifies their
physical identity and bytes before and after `/usr/bin/ssh -G`, before and after
each of the exactly three SSH children, and uses those same immutable snapshot
paths for both `ssh -G` and connect. Policy rejects nonempty `SendEnv` and
`SetEnv`, `AddKeysToAgent` other than `no`, `ForkAfterAuthentication` other than
`no`, `IdentityAgent` other than `none`, plus all previously frozen forwarding,
proxy, command, password and multiplexing hazards. Each remote command remains
exactly `exec /usr/bin/cat -- <AUTHORITY_FIXED_PATH>`; exactly receipt, config
and credential are read once. Any snapshot drift is `STOP` without refetch.

### Semantic scans and terminal completion

`history`, `terminal-log` and `attachment` collectors scan each original raw
payload before any Base64 framing. The writer decodes every frame, verifies its
canonical Base64, byte length and SHA-256, then scans the decoded bytes again.
A reversible encoding is never accepted as redaction. Runtime evidence contains
only the closed keys `HOME`, `LANG`, `LC_ALL`, `PATH`, `TMPDIR`; credential-like
keys (including cloud access keys, service-role variables, tokens, passwords,
`NODE_OPTIONS` and `SSH_AUTH_SOCK`) STOP before persistence. The scanner counter
is derived from these semantic bytes and cannot be supplied by a receipt.

The final domain is fixed as `process-argv`, `controller-journal`,
`controller-stdout`, `controller-stderr`, `terminal-attachments`,
`simulator-xcresult`, `runtime-environment`, `writer-output`,
`terminal-settlement`, and `complete-result`. The single privileged `--write`
transaction reopens all current evidence, verifies remote receipt/config/
credential hashes against `context.remote`, writes and reads back the pre-anchor
and terminal phases, writes and reads back `terminal-settlement.json`, scans
the terminal bytes into `terminal-final-scan.json`, and publishes
`complete-result.json` last. `complete-result.json` binds the actual settlement
and final-scan byte hashes. A non-circular `complete-final-scan.json` then scans
the exact complete-result bytes; the frozen directory and controller readback
bind that last scan. Only this two-scan DAG represents controller `COMPLETE`.

All ten `after-claim` recovery cases, including `VERIFY_ANCHOR`, return
`STOP_CLAIM_CONSUMED_NO_RESULT`; a later physical object is never retroactively
adopted. The remaining synthetic boundaries reobserve exact durable physical
effects without replay. Real Publisher 0, transport, SSH, simulator, privilege,
anchor and Task 2 remain unexecuted and unauthorized in this change.

### Synthetic E2E durable-state binding

The test matrix has no pre-materialized writer fixture. Its synthetic adapter
may materialize writer inputs only when the live Git-bound state machine enters
`INVOKE_WRITER`. It MUST reopen the current
`protocol-state/journal-snapshot.json`, preserve its bytes across the helper
process, and bind an exact envelope as the ordered
`controller-durable-state-root` evidence role:

```text
schema_version=1
purpose=CI3_SYNTHETIC_DURABLE_PROTOCOL_STATE_V1
scenario_id + sha256(UTF8(scenario_id))
sha256(physical durable-state path)
sha256(canonical snapshot)
snapshot={records,events,claims,results,scenario_trace,crash_observed,
          phase_claims,phase_receipts,phase_results,phase_produced,
          phase_effect_counts,phase_paths}
raw_values=false
```

The controller validates the descriptor and unchanged source snapshot before
and after materialization. The Swift test build independently reopens the role,
validates exact keys/types and recomputes scenario/snapshot hashes. The role is
included in the terminal manifest and therefore its bytes are included in the
pre-anchor/settlement roots. This adapter is local/synthetic only and cannot be
used to infer external VPS, Mac or privileged authority.

## Round 8 normative closure: executable external bootstrap and post-controller terminalizer

This section supersedes any earlier text that allowed an operational launcher
to fall back to a checkout, a `PATH`-resolved runtime, inherited startup hooks,
or a `COMPLETE` event without the post-controller commit marker.

### Closed first-exec boundary

The official entrypoint has `#!/bin/zsh -f`. Before any Node process it either
reexecutes itself with `/usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C
PATH=/usr/bin:/bin /bin/zsh -f`, or rejects a forged closed-bootstrap marker.
Caller-provided `CI3_GIT_BOUND_*`, `NODE_OPTIONS`, `NODE_PATH`, `ZDOTDIR` and
all listed `DYLD_*` loader hooks are rejected. No operational branch consults
`which`, `command -v`, inherited `PATH`, `NODE_OPTIONS` or a user checkout.

An external launcher is reachable only at one of these version-addressed
roots, after a separately authorized root materializer has installed it:

```text
/var/lib/agentempp/ci3-publisher0-bootstrap/<AUTHORITY_SHA>/<BOOTSTRAP_GENERATION>/runtime/
/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/<AUTHORITY_SHA>/<BOOTSTRAP_GENERATION>/runtime/
/Library/Application Support/Agentempp/ci3-controller-authority/<AUTHORITY_SHA>/runtime/
```

`<AUTHORITY_SHA>` and the generation are not free operator variables. They are
read from the external issuer/VPS PASS handoff, then matched to the physical
path. Each runtime contains the executable launcher, fixed Node, controller,
launch attestation, literal authority manifest, and the following exact
root-owned immutable line authority:

```text
CI3_EXTERNAL_LAUNCHER_AUTHORITY_V1
authority_sha <40-lower-hex>
controller_generation_id controller-<64-lower-hex>
node_sha256 <64-lower-hex>
controller_sha256 <64-lower-hex>
launcher_sha256 <64-lower-hex>
launch_attestation_sha256 <64-lower-hex>
authority_manifest_sha256 <64-lower-hex>
allowed_modes <closed-comma-list>
raw_values false
```

The launcher parses this file with zsh builtins before Node, verifies the
physical root/regular-file/no-link/mode/immutable boundary and every listed
hash, and then uses only the fixed Node/controller with the closed environment.
Missing external issuer/root installation is `STOP_PRE_AUTHORITY`; this bundle
does not invent a VPS key or authorize its own first privileged installation.

### Descriptor-relative Publisher 0 and Publisher 1

Linux Publisher 0 retains every directory descriptor and opens descendants
through `/proc/self/fd/<parent-fd>/<component>` with `O_DIRECTORY|O_NOFOLLOW`;
the PASS leaf is opened `O_EXCL|O_NOFOLLOW`, fsynced, made immutable through
the descriptor-relative leaf, read back, and the retained identities are
revalidated. Darwin uses the already authorized Swift helper's internal
`--descriptor-transaction`, which performs `openat`, `fstatat`, `fchmod`,
`fsync`, `fchflags`, readback and parent-fd revalidation. No Python, shell
interpreter selected by `PATH`, package, or non-core Node dependency is part
of either transaction.

Publisher 1 installs and reopens exactly 16 targets: fixed Node; controller;
launcher; launcher-bootstrap authority; launch attestation; authority
manifest; operation authority; human authorization; signed VPS PASS; VPS
issuer authority; publisher input manifest; and the exact five-file SSH
snapshot (`ssh_config`, `known_hosts`, `id_ed25519`, `id_ed25519.pub`,
`trust-descriptor.json`). Executables are `0555`, the private key is `0400`,
the remaining files are `0444`; every target is root:wheel, regular,
single-link, immutable and hash-read-back. The launcher authority is derived
only from the already authenticated transport bytes and is installed in the
same no-clobber version root.

SSH policy accepts the native safe `AddKeysToAgent` encodings `no` or `false`
only as one record and rejects duration, confirmation, case/whitespace drift,
duplicates, `SendEnv`, `SetEnv`, `IdentityAgent`, and
`ForkAfterAuthentication`. All five snapshot objects are reobserved after
`ssh -G` and after each of the exactly three fixed `exec /usr/bin/cat --`
reads.

### Receipt-last terminal visibility

`runProtocol()` may durably settle `COMPLETE`, but the public controller result
is then only `PRE_TERMINAL_UNPUBLISHED`. It MUST NOT be consumed as PASS. The
same authenticated launcher invokes the same fixed controller once in its
closed internal `--terminalize-tail` mode. The normal controller cannot create
a terminal claim, receipt, marker, or status transition. It opens the fixed
root terminal-generation objects, validates the privileged marker and emits
the already retained/scanned stdout bytes directly; it never reopens an output
pathname with `cat` after validation.

The single privileged writer invocation creates the anchor, fsyncs/readbacks
it, settles the terminal transaction, materializes the actual reversible
journal frame, scans the final stdout/stderr/settlement/complete/final-scan
bytes, writes the fixed root-owned frames, and creates this commit marker last:

```text
/Library/Application Support/Agentempp/ci3-terminal-authority/
  <authority>/<terminal-generation>/terminal-pass.marker.json
```

`CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1` binds the authority, all four
generations, controller/launcher hashes, privileged authority receipt,
`COMPLETE`, terminal settlement, complete result, complete final scan, actual
journal-frame hash/length, stdout/stderr hash/length and every fixed path hash.
It declares `normal_executor_authorized=false` and
`receipt_is_commit_marker=true`. Every object is root:wheel, immutable,
single-link and `0444`; absence, reuse from another generation, path drift or
any byte drift leaves status `PRE_TERMINAL_UNPUBLISHED` or STOPs. Only this
privileged last marker can produce `TERMINAL_PASS`.

The journal artifact has purpose
`CI3_OPERATIONAL_DURABLE_JOURNAL_FRAME_V1`. It frames every real journal
object as length/path/length/bytes, scans each raw object and the combined raw
frame before Base64, and records ordered object path/hash/length/physical
identity. The Swift writer decodes the frame, recomputes every relationship and
rescans every decoded object. A hash-only pointer is not evidence.

### Round 9 Publisher 0 to Publisher 1 boundary

Publisher 0 still starts only from the externally installed root-owned VPS
issuer/bootstrap. Its signed PASS and V2 eleven-role manifest are the only
transport authority; no real key is embedded. On the Mac, missing the external
materializer authority at the exact root below is `STOP_PRE_AUTHORITY`:

```text
/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/
  <authority>/<controller-generation>/publisher1-materializer.authority.json
/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/
  <authority>/<controller-generation>/vps-issuer-authority.receipt.json
/Library/Application Support/Agentempp/ci3-publisher1-bootstrap/
  <authority>/<controller-generation>/runtime/ci3-terminal-anchor-writer
```

That external receipt binds the fixed binary path/hash, writer Git source hash,
issuer receipt hash, closed four-variable environment and
`normal_executor_authorized=false`. The root-owned immutable materializer
revalidates its own executable and receipt before accepting the exact
hash-bound owner-only `0600` transaction request. It walks every absolute
directory component with retained `openat(O_DIRECTORY|O_NOFOLLOW)`
descriptors, opens all sixteen deterministic receiver leaves once, verifies
the external issuer Ed25519 signature and all PASS/manifest/operation/
attestation/human/SSH relationships independently, and retains those bytes.

Only after source validation does it publish
`publisher1.claim.json` with `O_EXCL` and fsync. It builds the complete
authority in a sibling descriptor-bound staging directory, creates every leaf
no-clobber, freezes leaves and all directories (`0555`, except private key
`0400` and other files `0444`), promotes the whole directory with
`renameatx_np(RENAME_EXCL)`, fsyncs, reobserves through retained descriptors,
and writes `publisher1.result.json`. Recovery with a claim never refetches or
reexecutes: a complete tree is physically reobserved and yields
`EXISTS_RECOVERED/EXISTS_VERIFIED`; a partial or absent effect STOPs. A
preexisting tree without the exact original claim is never adopted.

No external Publisher 0/1 install, real SSH, network, simulator, admin prompt,
anchor write or Task 2 action was performed while implementing this section.

## Round 10 authority amendment: one finalization and fixed Publisher 1 request

This section supersedes every earlier description that split terminal
publication between the normal controller and the privileged writer. The
normal controller settles `RUN_SCANS`, writes one `events/COMPLETE.json` whose
only result is the hash of the terminal commit contract, and seals a reversible
length-prefixed journal frame. That object is a pre-terminal contract, never a
PASS marker. The six scanners (`argv`, `history`, `terminal-log`, `attachment`,
`xcresult`, `runtime`) cover the actual normal objects and decoded frame bytes
before privilege is invoked. The controller then invokes the privileged writer
exactly once and performs no normal filesystem write afterward.

That single writer invocation reopens and semantically recomputes the sealed
journal, manifest, evidence, contracts and physical pre-anchor. It durably
creates the `INVOKE_WRITER` and `VERIFY_ANCHOR` claim/receipt/result roots,
settlement, final scans, COMPLETE result, COMPLETE final scan, retained stdout,
empty stderr and exact journal frames. Only after re-reading all of them does it
create `terminal-pass.marker.json` with no-clobber semantics and freeze the
generation. The marker is therefore the literal last publication. Missing or
invalid marker means `PRE_TERMINAL_UNPUBLISHED`, even when earlier objects
exist. A restart may only reopen the exact privileged roots/marker; it must not
append an alternative finalization or repeat an admin prompt. Partial or
divergent privileged state STOPs.

Publisher 1 materialization authority is now
`CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2`. It externally binds the one fixed
`publisher1-transaction.request.json` pathname hash, request SHA-256 and full
physical identity (`uid`, `gid`, `mode`, `nlink`, `dev`, `ino`, size and
mtime), plus the exact receiver-root pathname hash and descriptor identity.
Production accepts only `--publisher1-transaction <exact-path> <exact-sha>`;
stdin, path-free input, suffix matching and a different receiver are invalid.
The controller observes the root-owned fixed claim, result and sixteen-leaf
tree before deciding whether an admin child is necessary. Exact settled state
is reobserved and reused; claim-without-a-complete-effect and any divergence
STOP without a second `osascript` child.

The Darwin install order is construct and fsync the private descriptor-relative
staging tree, promote the complete directory with
`renameatx_np(RENAME_EXCL)`, then reopen the destination, freeze its leaves and
directories, fsync and read back. Staging is never made immutable before the
rename. A real non-synthetic Darwin probe exercises promotion, destination
freeze, exact-existing reobservation and the no-clobber race in a temporary
local root. It does not use the real receiver or authority.

The external issuer, immutable materializer authority, root runtime and real
operation/writer authority remain mandatory future inputs and were not
invented here. Their absence remains `STOP_PRE_AUTHORITY`; this amendment did
not execute privilege, network, SSH, simulator, anchor publication or Task 2.

## Round 11 authority amendment: sixteen physical leaves and terminal recovery

`CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2.receiver_leaves` is an ordered,
closed list of exactly sixteen objects. Each object has only the fixed role,
`path_sha256`, content `sha256`, `uid`, `gid`, numeric mode `0600`, `nlink=1`,
size, decimal-string `mtime_ns`, `dev`, `ino` and `identity_sha256`. The
identity is the hash of the canonical physical metadata tuple. The
transaction request repeats these values as `source_*`; the original claim and
result preserve them without retroactive generation. External authority,
request and retained descriptor observations must be byte-for-byte equal.

Before the claim, the Swift materializer opens every leaf no-follow beneath the
retained receiver chain, performs `fstat/read/fstat`, validates all physical
fields and bytes, and then reobserves the receiver directory plus all leaves
descriptor-relatively. No same-content replacement, owner/mode drift or
hardlink is authority-equivalent. Exact-existing recovery requires the
original physical claim/result and reopens the complete installed tree.

Terminal authority is only
`CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1`. The operational recovery state machine
validates that marker against its fixed paths and actual privileged authority,
journal frame, COMPLETE event, stdout/stderr frames, settlement, COMPLETE
result and COMPLETE final scan. A complete marker yields PASS; no marker yields
`PRE_TERMINAL_UNPUBLISHED`; a recoverable exact prefix may be completed only by
the same externally authorized writer transaction; divergence STOPs. Crash
boundaries after COMPLETE final scan, final frames, marker readback and
generation freeze are exact-existing recovery gates. `resume` cannot synthesize
PASS from settlement or internal state.

The one-invocation recovery implementation is the root writer itself. The
verified binary remains as a transient supervisor and starts a same-absolute-
binary worker through the platform spawn primitive with only the closed
environment. Worker crash/signal permits one exact-existing retry. The normal
controller never restarts `osascript`; after its own restart it only performs a
bounded marker observation. No marker when the supervisor is gone is
`STOP_PRE_AUTHORITY`. The supervisor is not a daemon, persistent helper,
socket or installed service. No real authority or privileged action was
created here.

## Round 12 authority amendment: recoverable immutable edge and eighteen-root marker

Every privileged terminal file publication takes the already validated
`privileged_claim_sha256` as explicit recovery authority. The fixed file is
opened no-follow and no-clobber, written and fsynced, then `UF_IMMUTABLE` is set
with `fchflags` on the retained descriptor. Recovery may adopt the narrow
post-fsync/pre-flag prefix only if the original claim is still valid, bytes and
hash are exact, the file is regular/root-owned/`0444`/single-link, every
physical identity field is unchanged across descriptor reads, and the parent
entry still names that descriptor identity. It then sets the flag, fsyncs file
and parent and performs retained-descriptor readback. Without the original
claim, preexisting state is never authority and must STOP.

`CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1.paths` is a closed eighteen-key map.
Besides the original authority, journal/output, settlement, COMPLETE and marker
paths it includes pre-anchor, writer output, terminal final scan and the six
`INVOKE_WRITER`/`VERIFY_ANCHOR` claim-receipt-result paths. The marker directly
binds hashes for these three posterior roots and the ordered six-object phase
root. The common reader accepts only the exact fourteen terminal-root entries,
the exact six phase-directory entries and the single fixed writer-binary entry,
validates stable root-owned `0555`
directories, and reopens every file as root-owned immutable `0444` with stable
metadata. It recomputes all transitive semantic relations before PASS; any
missing, extra, path-substituted, metadata-drifted or byte-mutated root STOPs.

This amendment provides no missing external publisher/writer authority.
Operational use remains `STOP_PRE_AUTHORITY`, and no real effect was executed.

## Round 13 authority amendment: one complete semantic corpus validator

Terminal PASS readers MUST invoke the canonical corpus validator over the
eighteen physical roots and the marker. The privileged authority receipt is
accepted only by the publication-grade exact validator with independent
expected manifest, fixed authority/anchor/manifest/writer paths, retained
writer hash/identity, owner/group/mode/immutable flag, source/binary/signature,
original claim, attempt 1, retry false and raw false.

`CI3_PRE_TERMINAL_ANCHOR_V1` has one closed schema equal to the Swift output.
The reader MUST recompute the ordered external-authority-root and phase-target-
root array hashes, require the literal six scan IDs and receipt hashes, require
the literal 24 Important IDs, and cross-bind authority tree/manifest/components,
four generations, writer provenance/claim, fixed paths, settlement contracts,
timestamp and policy booleans. It MUST then validate settlement, phase graph,
physical results, posterior scans/COMPLETE objects and marker in the same
corpus call. Rehashing invalid inner objects never creates authority.

The terminal manifest is reopened from its authority-fixed path before corpus
validation and its retained bytes provide the independently pinned manifest
hash and writer provenance expected by the immutable authority receipt. Any
drift is STOP, including on exact-existing recovery. This amendment grants no
real external or privileged authority.

## Round 14 authority amendment: publication-equivalent evidence semantics

Every common terminal reader MUST run the externally bound immutable writer's
read-only semantic validator against the authority-fixed manifest path. The
validator MUST be the same implementation invoked by the privileged write
path, not a JavaScript approximation: it reopens and semantically validates all
71 ordered evidence roles and all six ordered scan receipts. Its subprocess
contract is an absolute writer path, four exact generations, the manifest path,
an empty/closed environment, no inherited loader hooks, bounded output and no
write or privilege behavior.

The success output is one exact hash-only
`CI3_TERMINAL_SEMANTIC_VALIDATION_RECEIPT_V1`. It binds the manifest hash,
writer binary/signature/physical identity, ordered role and scan roots, complete
semantic-root object, reopened `RUN_SCANS` result and two canonical terminal
contracts. The controller MUST reject extra fields, malformed counts/order,
hash drift, stderr, extra stdout or any process failure.

The common corpus MUST initialize its predecessor from the validated
`RUN_SCANS` result bytes. For each terminal phase it MUST require
`claim.contract_sha256 == SHA256(canonical exact contract)` and the exact prior
validated result root. The expected pre-anchor semantic fields MUST come from
the validation receipt, not from manifest assertions. The receipt is transient
and recomputed on each read; normal storage cannot manufacture terminal PASS.

## Round 15 authority amendment: exact physical integer serialization

All JavaScript identities crossing the Swift boundary MUST originate from
BigInt filesystem stats. Their canonical preimage is exactly
`uid=<d>;gid=<d>;mode=<mode&0777>;nlink=<d>;size=<d>;mtime=<mtimeNs>;dev=<d>;ino=<d>`
with canonical decimal integers and no `mtimeMs`, floating-point or prior
`Number` conversion. Swift MUST use the same formula over `st_uid`, `st_gid`,
permission bits, `st_nlink`, `st_size`, exact `st_mtimespec`, `st_dev` and
`st_ino`.

Descriptor/path reobservations compare all eight BigInt fields. Metadata fields
whose schemas remain JSON integers are converted only after the identity hash
and only when safely representable; otherwise validation STOPs. This applies
to root immutable files and directories, receiver/materializer leaves,
captures, scan sources, SSH snapshots, simulator install receipts and the
privileged authority receipt producer.

## Round 16 authority amendment: exact promotion and container identity

`promoteDirectoryNoReplace` MUST observe staging, its parent, final absence,
the promoted destination and staging disappearance using BigInt `lstat`.
Same-device and exact-staging promotion are direct BigInt comparisons; no
`dev` or `ino` may pass through Number or decimalize after Number conversion.

The resolved simulator data container MUST be a non-symlink directory whose
BigInt stat supplies all eight canonical physical identity fields. Its
`container_identity_sha256` is the shared full physical identity hash, not a
separate three-field JSON hash. External simulator authority MUST bind this
exact digest. Any missing BigInt field, adjacent identity mismatch or legacy
rounded digest is `SIMULATOR_GATE`/publication STOP.

## Round 17 authority amendment: exact generator metadata projection

Generator `lstat`/`fstat` observations MUST retain `uid`, `gid`, `mode`,
`nlink`, `size`, `mtimeNs`, `dev` and `ino` as BigInt through all entry/path
and retained-descriptor comparisons. `assertStableIdentity` accepts only exact
BigInt or canonical decimal representations; it MUST reject Number inputs even
when their rendered strings match.

The generator physical identity digest uses the same canonical preimage as the
controller and Swift writer. A bounded JSON or POSIX policy field may become a
Number only through an explicit safe-integer check after the exact physical
identity has been retained. Original claim, exact-existing, staging, recovery
and final verification all consume the same owner-only reader and STOP on any
one-field divergence.

## Round 18 authority amendment: private immutable VPS Node runtime capsule

The VPS bridge generator runtime is no longer an ambient `/usr/bin/node` or
NVM executable. `/usr/bin/node` is a frozen bootstrap-only source with exact
SHA-256; it is never chmodded, chowned, updated or given an immutable flag.
The operational runtime is a private version-addressed copy published by
`PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V1`.

The runtime builder is itself a root-owned `0600` Git-blob snapshot. Its
original O_EXCL/fsynced claim precedes one filesystem capability probe and all
copy effects. The probe proves real immutable semantics and removes the flag
only from its synthetic file. The final Node is root:root `0555`, receipt is
root:root `0444`, both are single-link and immutable, and their directory is
root:root `0555` immutable. No mutable alias exists and no published capsule
is ever thawed.

The receipt binds the runtime authority separately from bridge authority
`ba8473799a19aec586b0fe706bb7d4084589c86c`, plus bootstrap identity,
builder, tools, filesystem and dynamic closure before/after. Only after exact
verification may a detached clean `ba847...` worktree use the capsule for the
154 generator tests, self-test and the single bridge `--create`. The bridge
authority/output generation remains unchanged.

## Round 19 — full-path Node closure V2

Runtime V1 stays failed at 1/1. V2 uses
`PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V2` and
`NOFOLLOW_COMPONENT_CANONICALIZATION_V1`; bridge authority stays `ba847...`.
Independent dimensions are 7 entries, 7 traversing symlink, 0 traversing none,
2 final symlinks, 5 final regular/intermediate-only, 9 hops/max2, 7 canonical
targets and zero duplicates. `direct_entry_count` is not a V2 field.

The BigInt lstat/readlink walker binds trusted parents, bounded target chains,
cycles/hops, final O_NOFOLLOW descriptor bytes and complete revalidation. A
durable claim precedes operational ldd; root-only capture permits recovery
without rerunning the source list. Receipt schema 2 binds corrected hashes,
classifications, V1 STOP, fresh V2 attempt and false controls. Mac/Task 2 remain
blocked; credential copy, service-role output and external writes are forbidden.

## Round 20 — read-only adoption verifier for the existing V2 capsule

The consumed V2 create attempt is never retried. Its physically complete
immutable capsule may become operational only through
`READ_ONLY_NODE_RUNTIME_CAPSULE_V2_ADOPTION_VERIFIER_V1`, a new Git path that
does not modify or import the V2 builder as an execution entrypoint. The tool
has only `--self-test` and `--verify-existing`; there is no creation mode.

An authority-addressed adoption claim outside the capsule MUST be written
O_EXCL/O_NOFOLLOW and fsynced before the real attempt opens capsule artifacts.
Claim without receipt consumes the one adoption attempt and blocks retry. An
exact-existing receipt is accepted only with its original byte-exact claim.

Verification reopens all original artifacts no-follow, checks owner, mode,
nlink, hashes and stable physical identities, verifies all three immutable
flags, and reconstructs the full closure solely from the durable capture. It
MUST NOT run loader discovery, immutable capability probing or attribute
mutation. Source/capsule bytes and identities are compared before/after.

Bounded version and core-module smokes precede two receipt-bound verification
phases: bootstrap Node and then capsule Node self-hosting the verifier. The
self-hosted phase creates no second claim or receipt. Only after every gate and
an unchanged artifact projection may a version-addressed external adoption
receipt be published last. A PASS receipt binds both authorities, old builder,
terminal STOP, artifact identities/hashes, closure, smokes and explicit zero
effect counters. Bridge execution remains conditional on this PASS.

## Successor contract: bounded Git streaming and Mac-only launcher

Bridge V1 is frozen at 1/1 after its pre-claim 64 KiB reader failure. Bridge
V2 has an independent 1/1 budget and reads every authority blob with a
1,048,576-byte ceiling. It verifies object type and size before the body,
streams exactly once with incremental SHA-256 and bounded stderr, applies a
timeout, requires exact bytes, and revalidates type/size without reading the
body again. There is no retry and no `maxBuffer`-only repair.

The zsh launcher is target-specific executable material for `mac_local` at
`/bin/zsh`. VPS syntax execution is not applicable; installing zsh, creating a
zsh capsule, or treating Bash as equivalent is forbidden. The authority must
prove equality between the predecessor and current normalized structural
skeletons. Normalization may cover only authority path literals, parent and
subject; all grammar, control flow, redirects, quoting, functions and call
edges remain byte-relevant.

The remote receipt records `zsh_syntax_validation_deferred=true`, required
environment `mac_local`, required-before-network true, status
`not_executed_on_vps`, both equal skeleton hashes and equality true. The Mac
must materialize the exact Git blob, verify `/bin/zsh`, run `/bin/zsh -n`,
require empty output and stable launcher identity, then atomically publish an
owner-only syntax receipt before simulator, claim, SSH or remote read. Any
failure has zero network/effect and consumes no silent retry.

## Canonical staging receipt successor

The current architecture is
`VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING_WITH_CANONICAL_ENV_RECEIPT_V1`.
Its authority parent is the published Bridge V2 STOP, and its closed manifest
contains exactly 15 paths. Bridge V1 and V2 remain consumed predecessors.

The environment receipt accepts no aliases or fallbacks. It requires purpose
`ci3-staging-mobile-bff`, boolean legacy-key true, exposure `no`, permission
`api_gateway_keys_read`, and the exact URL/anon/service-role classifications
documented in the reconciliation evidence. All other schema, ref, preview,
hash, control-plane, no-write, no-production and no-emission gates remain
mandatory. Validation is read-only and cannot rewrite either input.

## Canonical deployment receipt successor

The current successor architecture is
`VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING_WITH_CANONICAL_INPUT_CONTRACTS_V1`.
Its authority parent is `70a7d60dd9c4224e3be9072ce5fbd966bd534560`,
its exact subject is `build(ops): reconcile remaining CI-3 bridge input contracts`,
and its closed manifest contains 16 paths.

The deployment receipt requires literal purpose
`ci3-dedicated-mobile-bff-deployment` and literal Vercel Node `22.x`. It keeps
framework `nextjs`, root `apps/mobile-bff`, Preview/READY, Production zero,
env `3/0/0`, SSO null, route/probe arithmetic, hashes, implementation and
origin bindings unchanged. No alias, range, normalization, fallback, unknown
key or receipt rewrite is accepted.

Deployment Node is independent from the adopted immutable VPS execution
runtime. The remote bridge receipt binds both separately: `deployment_node`
and execution runtime adoption authority/hash/status. Missing or divergent
runtime adoption fails without comparing deployment Node to `process.version`
or the capsule version.

Bridge V1/V2 stay consumed; c517 stays unexecuted and superseded. The successor
gets one fresh no-retry attempt only after the 16-path authority is published
and the five-input read-only preflight passes. The Mac exact-blob zsh Gate 0,
three remote reads, six scans, terminal anchor and CI-3 base remain unchanged.

## Canonical credential and provisioning input contracts

The credential marker is an operation-scoped identifier matching only
`ci3-synthetic-YYYYMMDDTHHMMSSZ-[A-Z2-7]{16}`. Calendar components must round
trip exactly; whitespace, controls, aliases, case folding, normalization,
suffixes and the static family label are rejected. Only its SHA-256 may enter
sanitized evidence. Credential e-mail must be the exact marker plus
`@example.invalid`; Supabase lowercase canonicalization does not modify the
marker.

The provisioning receipt requires purpose `ci3_authenticated_today`, authority
`5cecaa7af3f2c61f387e4e2d77a2b5e61f2d9a1c`, state `TODAY_VERIFIED`, cleanup
class `CREATED_AT_PLUS_14_DAYS`, canonicalization class
`NORMALIZED_ALIAS_DOCUMENTED`, fixture cardinalities `1/1/1/1/1/1/1/0`, the
published attempt counters, patient/service HTTP counts `1/7`, and exact ID
hash bindings. Marker, project ref, environment, creation/expiry/deadline and
implementation identities must agree across the five inputs.

`--preflight-inputs` is the only third CLI mode. It uses the exact source
readers and the same source-document validator as `--create`, returning only a
closed sanitized PASS/failure projection. It performs zero writes, claims,
outputs, receipts, retries, network, SSH or primary/live opens.

## Pre-Gate0 Git object bootstrap V1

`PRE_GATE0_GIT_OBJECT_BOOTSTRAP_V1` is a narrow availability prerequisite for
the Mac launcher. It does not modify the bridge architecture, current bridge
authority `7a929b0cebb28c339010dd5bf115e67b79523156`, generation, config,
receipt, credential boundary, simulator protocol, SSH protocol, three-read
budget, six scans, terminal anchor or CI-3 continuation.

The Mac begins with a local object-availability decision. The object-bootstrap
authority SHA supplied by the handoff, its terminal-documentation parent, the
bridge authority and launcher blob must all exist and validate to require zero
fetch. If any is absent, at most one logical invocation may update only
`refs/remotes/origin/codex/better-ahead-rebranding-design` from exact HTTPS
origin `https://github.com/corehealth-app/agentempp.git`, using the literal
no-tags/no-submodules/no-maintenance/no-gc command frozen in the companion plan
and evidence. There is no force refspec, prune, shallow mutation, checkout,
local branch update, pull, merge, rebase or retry.

The fetch transports Git commits/blobs only and is classified
`code-provenance network`. It may not access the operational VPS, SSH, bundle,
config, credential, secrets, simulator, remote-read claims or CI-3 worktree.
After the fetch, readback must prove the new authority parent, remote-tracking
tip, current bridge authority, ordered 16-path manifest, exact launcher
`100755`/blob/SHA and byte-identical manager and CI-3 states.

Only then may the launcher be materialized from the local object database.
`MAC_GATE_0=EXACT_LAUNCHER_ZSH_SYNTAX` remains mandatory and must pass before
simulator, `/usr/bin/ssh -G`, SSH, remote reads, claims, config/credential or
any operational network. Its receipt includes bootstrap authority, fetch count
0 or 1 and `network-after-bootstrap-before-gate0=false`. Fetch/readback/Gate 0
failure is terminal and has no retry. Predecessor bridges remain prohibited.
