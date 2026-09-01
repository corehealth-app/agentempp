# CI-3 — STOP V3 e autoridade da ponte versionada

**Data:** 29/08/2026
**Status desta evidência:** `BRIDGE_AUTHORITY_AUTHORED_NOT_EXECUTED`
**Arquitetura sucessora:** `VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1_WITH_EXECUTABLE_MAC_CONTROLLER`

## 1. Escopo e limite da operação

Esta evidência registra o STOP terminal da ponte V3 e a autoridade documental
para um gerador Git-tracked. Ela não executa a V1, V2 ou V3, não abre SSH, não
consome stream, não lê os cinco inputs reais da VPS, não cria bundle remoto,
não busca config/credential, não chama `xcrun`/`simctl`, não instala arquivos
no simulador e não continua a CI-3 além dos cinco paths já preservados da Task
1. Supabase, Vercel, fixture, primary/live, produção, cleanup e CI-4 permanecem
intocados.

O authority base lido foi:

```text
AUTHORITY_SHA=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
AUTHORITY_PARENT=5cecaa7af3f2c61f387e4e2d77a2b5e61f2d9a1c
AUTHORITY_TREE=b2f630786efde79a72d203c271e5b3106e49a490
AUTHORITY_SUBJECT=docs(ios): authorize CI-3 Today staging vertical slice
CI2_BASE=277873755bf29771a10b5f362b522c2e6a6c21d6
CI3_HEAD=277873755bf29771a10b5f362b522c2e6a6c21d6
CI3_BRANCH=codex/ci3-today-staging-v1
CI3_STAGING=EMPTY
CI3_WORKING_PATHS=5
```

Os cinco paths continuam exatamente:

```text
apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift
apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift
apps/ios/BodyFlow/BodyFlow/Core/Configuration/MobileStagingConfiguration.swift
apps/ios/BodyFlow/BodyFlowTests/CI3StagingLaunchConfigurationTests.swift
apps/ios/BodyFlow/BodyFlowTests/MobileStagingConfigurationTests.swift
```

## 2. STOP V3 autoritativo

Cinco rodadas foram consumidas. A rodada final terminou:

| Review | Critical | Important | Minor | Gate |
|---|---:|---:|---:|---|
| A round 5/5 | 0 | 5 | 1 | FAIL |
| B round 5/5 | 0 | 6 | 1 | FAIL |

O controller fresh registrou `174/174` testes sintéticos PASS, mas isso não
superou os findings estáticos. SSH real, rede, streams, `simctl`, mutação de
simulador, claims/results/captures e publicação canônica permaneceram em zero.
Os budgets config/credential ficaram em `0/1`; o pair canônico permaneceu
ausente. Não existe sexta rodada autorizada no desenho V3.

```text
BRIDGE_V1_STATUS=FROZEN_SUPERSEDED
BRIDGE_V2_STATUS=FROZEN_SUPERSEDED
BRIDGE_V3_STATUS=FROZEN_REJECTED_AFTER_ROUND5
BRIDGE_V3_EXECUTION_AUTHORIZED=NO
V3_CONFIG_STREAM_ATTEMPTS=0/1
V3_CREDENTIAL_STREAM_ATTEMPTS=0/1
REAL_SSH_PROCESSES=0
REAL_SIMCTL_CALLS=0
FINAL_CANONICAL_BUNDLE=ABSENT
CI3_IMPLEMENTATION_STARTED_BEYOND_TASK1=NO
CI4_STARTED=NO
```

## 3. Matriz completa dos 11 findings Important

Os findings permanecem independentes, sem deduplicação entre reviewers.

| ID | Reviewer | Severidade | Path/símbolo | Causa | Cenário | Impacto | Prova exigida | Arquitetura sucessora | Teste/gate | Receipt field | Gate terminal |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `RA1-I-5` | A | Important | scans / `TERMINAL_PASS` | pre/post scans mutáveis e seis surfaces reais incompletas | rewrite coordenado ou surface ausente | PASS sem evidência terminal íntegra | cada surface real e raiz terminal imutável | receipt local terminal liga scans, phases, claims e results | leak/rewrite deve STOP | `scan_phase_hashes` | todos os scans terminalmente ligados |
| `A4-I-1` | A | Important | simulator phase chain | cadeia recomputável sem evidence root externo | reescrita autoconsistente da história | recovery aceita efeitos alternativos | root terminal sobre fases e estado físico | simulator gate receipt + terminal receipt | rewrite integral deve STOP | `simulator_gate_hash` | phase root exato |
| `A4-I-3` | A | Important | staging `bindBundle()` | inspeção semântica antes do binding | troca entre inspeção e open | bytes não inspecionados promovidos | validar somente buffers/fds vinculados | bundle local por geração imutável | entry/directory swap deve STOP | `local_bundle_hashes` | geração local exata |
| `A5-I-1` | A | Important | capture/result | capture reaberto por pathname | inode trocado após fsync | result não representa stdout capturado | ler/hashear no mesmo fd e reobservar inode | claims/results ligam capture fechado | same-size replacement deve STOP | `claim_result_hashes` | capture inode exato |
| `A5-I-2` | A | Important | controller source | source reaberto após preflight | replacement antes do stream | filtro diferente do revisado executa | buffer/hash do blob Git único | gerador versionado; Mac não envia filtro | source swap deve STOP | `generator_blob_sha` | blob Git exato |
| `RA0-I-4` | B | Important | simulator recovery | efeitos físicos não reobservados por phase | symlink/hardlink/mode/inode divergente | recovery aceita path adulterado | metadata e efeito tipado por phase | gate simulador anterior à rede | cada mutação física deve STOP | `simulator_gate_hash` | efeitos físicos exatos |
| `RA0-I-7` | B | Important | scanner attachment | rewrite coordenado e attachment sem counter de leak | marker somente em attachment | segredo pode não reprovar | counter independente por surface | scan terminal pós-instalação | marker em cada classe deve STOP | `scan_phase_hashes` | todas as classes limpas |
| `R2-I-2` | B | Important | phase semantics | hashes fecham cadeia, não semântica/autoridade | história inteira recalculada | PASS autoconsistente falso | efeito tipado + anchor terminal externo | terminal receipt imutável | self-consistent rewrite deve STOP | `terminal_state_hash` | autoridade terminal exata |
| `R5-I-1` | B | Important | staging opens | bytes validados antes dos fds finais | troca antes de open | publicação de trio alternativo | descriptor-first/no-follow | bundle local valida bytes já capturados | replace-before-open deve STOP | `local_bundle_hashes` | descriptors exatos |
| `R5-I-2` | B | Important | `/usr/bin/ssh -G` | fixture reduzida não representa defaults nativos | saída real tem chaves adicionais | caminho operacional não executável | validar saída nativa completa e policy de segurança | Mac executa `/usr/bin/ssh -G` real | mutações auth/proxy/forward devem STOP | `ssh_effective_config_sha256` | effective config real exata |
| `R5-I-3` | B | Important | remote filter source | source reaberto depois do freeze | in-place/replacement pós-preflight | payload remoto divergente | geração aberta uma vez | nenhum filtro remoto customizado | source mutation deve STOP | `generator_blob_sha` | geração Git exata |

Minors permanecem registrados separadamente: `A3-M-1` e `RB0-M-2` descrevem
a ausência de atribuição independente do comando/teste na evidência do runner
V3. A arquitetura nova elimina essa superfície operacional: o gerador e sua
suíte ficam no Git; commit, blob, hash do arquivo e resultado TAP completo são
revisáveis diretamente.

## 4. Manifest sanitizado de congelamento V1/V2/V3

Aliases: `$MAC_CONFIG=$HOME/.config/agentempp` e
`$MAC_CACHE=$HOME/Library/Caches/codex-sdd`. `CURRENT_MAC_USER` substitui nome
e UID. Todos os paths foram revalidados read-only: V1 `21/21`, V2 `4/4`, V3
`7/7`, mismatch `0`. Nenhum arquivo foi executado, editado, chmodded ou
removido.

| Gen | Path sanitizado | Owner | Mode | Type | Links | Bytes | SHA-256 |
|---|---|---|---:|---|---:|---:|---|
| V1 | `$MAC_CONFIG/ci3/remote-filter.js` | CURRENT_MAC_USER | 0600 | regular | 1 | 17930 | `86c3e542f5420ae702f2127821e82c60fe02503e6cb4a4f320b65a564f2f9f11` |
| V1 | `$MAC_CONFIG/ci3/bridge-self-test.js` | CURRENT_MAC_USER | 0600 | regular | 1 | 36862 | `4bfe6ed8eae9fdb520ee9b87c00346987183eb1ebabe6301f1577b2e571e151e` |
| V1 | `$MAC_CONFIG/ci3/ci3-bridge-public.pem` | CURRENT_MAC_USER | 0600 | regular | 1 | 625 | `b1f8ef280d0c9a322ef4e60a877df57bb60955d830b6635fd21631a2bf5c3a4f` |
| V1 | `$MAC_CONFIG/control-plane/ci3-bridge-private.pem` | CURRENT_MAC_USER | 0600 | regular | 1 | 2484 | `88802f1c7b08635fedbe11d88c120dc5911814911161d66c64f922f1742ad0e2` |
| V1 | `$MAC_CONFIG/control-plane/ci3-staging-bridge` | CURRENT_MAC_USER | 0700 | regular | 1 | 33035 | `7060fd1c77ee52922bda10a411684a2e4c0de09d945b6966498dc0a0522ea411` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/progress.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 8686 | `1828bda11e83d064df6cc1185e122b2d8b77f1d0a235465b69b604eb167b013a` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/remote-filter-diagnostic.js` | CURRENT_MAC_USER | 0644 | regular | 1 | 18996 | `008c2ebbfd86f8ee28e5e28d6df9b1e9797c73fefbb3d31591357ec2d6d681db` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-brief.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 5608 | `04574a6506e9f5c9927eeba2b806bade5cd943691bdd3a155dc8aab13a7ff6bf` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r1-review-package.diff` | CURRENT_MAC_USER | 0644 | regular | 1 | 114435 | `f113bdf68829218796cda27e32b7e27a2e0b85852a2eee974713e8b5f0db4fb8` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r2-findings.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 3834 | `e538df8df00c7d2c757d5ebc609d5c9e1be00424e129d5b6979332df0bdc0134` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r2-review-package.diff` | CURRENT_MAC_USER | 0644 | regular | 1 | 135236 | `1de179a807fbc3d589236e8ab6105b9a94904fcbc3248267e23e5d7c1cd0b4c1` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r3-findings.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 2914 | `b26e7f1a79ac9d3652f2344334884d90ac10b39dba22967e69c7feb80e85f260` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r3-review-package.diff` | CURRENT_MAC_USER | 0644 | regular | 1 | 133927 | `bca44b9a45e48a5ec7047f69025c50716c9e0c3db97fd9e3eee31aef14897e3e` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r4-brief.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 2986 | `2b8314f6ff1ae200108a99ed6581bf575980462dc77eaa143708f7b00c9cf7a1` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r4-review-package.diff` | CURRENT_MAC_USER | 0644 | regular | 1 | 63475 | `fc792f8f33e60a07d93b5657d32daa3e94e0752199d996a54c9bbc8c4856e1e4` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r5-brief.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 2538 | `46aaa58c0d26d4afc4c5ea59cc5972d8b00cc636e3f858cb441ca3c6c166e259` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-r5-review-package.diff` | CURRENT_MAC_USER | 0644 | regular | 1 | 72372 | `20ffb9931fc426821ad005c6019102da97dc180f2e0815494167f0d7e4c30f95` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-remote-structure.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 5054 | `3c8fcd9638d6cc97977a2112ec41bbcd118eac9f5a7e40c60a5e0e93278008e4` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-report.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 43944 | `925deb6819c5f78aeb3e77723fd24b486ac04831914b51b0d8cc30b6d7f5c281` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-review-findings.md` | CURRENT_MAC_USER | 0644 | regular | 1 | 6430 | `436a02948314d88541a5d51a16beeb6c2498f2280474e75d276484e841c00a0d` |
| V1 | `$MAC_CACHE/ci3-today-staging-resume/task-1-review-package.diff` | CURRENT_MAC_USER | 0644 | regular | 1 | 55949 | `02419f692cd6b3a25eb9eb315a6f27073f25b5b5617f038186a1f0dce962294e` |
| V2 | `$MAC_CONFIG/control-plane/ci3-staging-bridge-filter-v2.mjs` | CURRENT_MAC_USER | 0600 | regular | 1 | 19065 | `678ad539d50e7dad2c90b12e2d8ec67cd263548d51717b3fa22f7239c290ffd1` |
| V2 | `$MAC_CONFIG/control-plane/ci3-staging-bridge-filter-v2.test.mjs` | CURRENT_MAC_USER | 0600 | regular | 1 | 24964 | `3e66cbc2114f9b06553a969b4db3e7d2b283595cd4fd0a9b1f6fcf3b51dd97bb` |
| V2 | `$MAC_CONFIG/control-plane/ci3-staging-bridge-runtime-v2.mjs` | CURRENT_MAC_USER | 0600 | regular | 1 | 20894 | `98fb03c26c4dee476b911f20a41e2842ab1a8bf45de8db088c37d28e9be8c659` |
| V2 | `$MAC_CONFIG/control-plane/ci3-staging-bridge-launcher-v2.zsh` | CURRENT_MAC_USER | 0700 | regular | 1 | 745 | `4b188756982a23e18dc0d00e277003dc9297070c60d8e784f4b330e7df4a5c9d` |
| V3 | `$MAC_CONFIG/control-plane/ci3-bridge-v3/ci3-bridge-v3.mjs` | CURRENT_MAC_USER | 0600 | regular | 1 | 178980 | `0ea3e54a7dae44f479598da11140a7088f4a474df857b5ac475adfdb6155b46c` |
| V3 | `$MAC_CONFIG/control-plane/ci3-bridge-v3/ci3-bridge-v3.test.mjs` | CURRENT_MAC_USER | 0600 | regular | 1 | 162631 | `2a4b7bc2dc9111b5625e236af5298e3519e5093c40879003a384b94c34fed40a` |
| V3 | `$MAC_CONFIG/control-plane/ci3-bridge-v3/transition-coverage.receipt.json` | CURRENT_MAC_USER | 0600 | regular | 1 | 30384 | `fe405a0596b0cf00aa58735e80428852facb09c468fa0a840ec92bea8d861bbf` |
| V3 | `$MAC_CONFIG/control-plane/ci3-bridge-v3/ci3-bridge-v3.zsh` | CURRENT_MAC_USER | 0700 | regular | 1 | 1039 | `70011c92944e3191329dcefa6a14d3d86a65c7a7a84b9596f7c0e7cddf0f7002` |
| V3 | `$MAC_CONFIG/control-plane/ci3-bridge-v3/ssh_config` | CURRENT_MAC_USER | 0600 | regular | 1 | 832 | `2f28dab30a477fc24569918b9f98679d5f3e6767e2ad1a266c0c58e8386cbccc` |
| V3 | `$MAC_CONFIG/control-plane/ci3-bridge-v3/known_hosts` | CURRENT_MAC_USER | 0600 | regular | 1 | 97 | `2f770c19d80fd5fdab2518763d8b98f40b93b90c04291c8a437ddca821b165f1` |
| V3 | `$MAC_CONFIG/control-plane/ci3-bridge-v3/frozen-v1-v2.manifest.json` | CURRENT_MAC_USER | 0600 | regular | 1 | 9102 | `428598448dfa630db44602441ebe0893913e6217a26416a44e8702f0a6fe3f7b` |

## 5. Tooling Git-tracked, TDD original e remediação

O ciclo inicial foi RED `90 tests / 1 pass / 89 fail` por implementação
ausente e GREEN `90/90`. Esta rodada adicionou comportamento antes das
correções:

```text
RED_1=node --test scripts/ci3/create-ios-staging-bridge-config.test.mjs
TESTS=123
PASS=91
FAIL=32
SKIPPED=0
TODO=0

RED_2=node --test scripts/ci3/create-ios-staging-bridge-config.test.mjs
TESTS=125
PASS=123
FAIL=2
SKIPPED=0
TODO=0

RED_3=node --test scripts/ci3/create-ios-staging-bridge-config.test.mjs
TESTS=126
PASS=125
FAIL=1
SKIPPED=0
TODO=0

GREEN=node --test scripts/ci3/create-ios-staging-bridge-config.test.mjs
TESTS=126
PASS=126
FAIL=0
SKIPPED=0
TODO=0
```

`node --check` passou. O gerador continua Node-core, com somente `--self-test`
e `--create`; self-test é temp-only/local e network zero. Nenhum `--create`
foi executado.

## 6. Fechamento dos findings desta remediação

- B6 publica `local-publication.receipt.json` pre-terminal; B7 publica outro
  receipt versionado após install/scans. Não há dependência circular.
- A autoridade terminal é anchor externo root-owned, O_EXCL, `0444`,
  `UF_IMMUTABLE`, fora do bundle mutável; path/hash/identidade são verificados.
- O launcher captura `git cat-file` antes de executar snapshot versionado; o
  worker não usa `hash-object` nem o pathname mutável do checkout.
- `created_at_utc` é o timestamp do commit; exact-existing valida receipt
  existente/claim sem rerender.
- Claim determinística durável precede staging; publicação usa `link(2)`
  no-replace e receipt-last. Recovery usa capturas, sem source reread/refetch.
- O receipt remoto não tem exceção sintética: purpose errado/ausente, mesmo
  com claim/hash reescrito de forma autoconsistente, STOPa. O self-test usa o
  schema completo. Config-only fisicamente visível antes do receipt é
  `UNPUBLISHED`; nenhum consumer pode ler/usar esse config e receipt presente
  ainda exige validação integral antes de PASS.
- Output root/final/files e inputs usam no-follow, chain/owner/mode/link e
  identidade completa antes/depois.
- Schemas validam purpose/authority/ref/URL/origin/implementation/counts e o
  Preview count é derivado.
- Trust SSH depende de descriptor concreto version-addressed/hash-bound por
  VPS PASS; ausência STOP, sem valor livre. `ssh -G` preserva defaults,
  duplicatas e ordem.
- Simulator gate, `/usr/bin/install -m 0600`, physical readback, scans,
  anchor e mapping literal das Tasks originais estão congelados na spec/plan.

## 7. Handoff A integral — VPS, não executado

```text
OPERATION=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
NEXT_ENVIRONMENT=VPS
AUTHORITY_SHA=CONTROLLER_PASS.authority_sha
AUTHORITY_PARENT=9f5cbb61a7266c6e0f40179fc6dcdafd55aecd52
AUTHORITY_TREE=CONTROLLER_PASS.authority_tree
AUTHORITY_SUBJECT=build(ops): authorize executable CI-3 bridge tooling
GENERATOR_PATH=scripts/ci3/create-ios-staging-bridge-config.mjs
GENERATOR_EXECUTION=/root/.config/agentempp/bridges/ci3/.launchers/$AUTHORITY_SHA/create-ios-staging-bridge-config.mjs --create
GENERATOR_MODES=SELF_TEST_AND_CREATE_ONLY
INPUT_HASHES=FIVE_EXACT_HASHES_IN_SPEC
OUTPUT_ROOT=/root/.config/agentempp/bridges/ci3/AUTHORITY_SHA
OUTPUT_CONFIG=mobile-staging-config.json
OUTPUT_RECEIPT=bridge.receipt.json
CLAIM=DETERMINISTIC_O_EXCL_FSYNC_ATTEMPT_1
PUBLICATION=RECEIPT_LAST_LINK_NOREPLACE
RECOVERY=CAPTURED_BYTES_ONLY_NO_SOURCE_REREAD
HISTORICAL_GENERATOR_ONLY_EXPECTED_TESTS=131_PASS_0_FAIL_0_SKIP_0_TODO
OVERWRITE=NO
CREDENTIAL_COPY=NO
SERVICE_ROLE_OUTPUT=NO
PRIMARY_OPEN=NO
GIT_VERCEL_SUPABASE_PRODUCTION_WRITE=NO
CI4=NO
```

VPS PASS também deve fornecer descriptor de trust concreto, version-addressed
e hash-bound; sem isso Mac permanece STOP.

## 8. Handoff B integral — Mac, não executado

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
B0=STRICT_LOCAL_NO_NETWORK
TRUST=FIXED_VERSIONED_DESCRIPTOR_AND_MATERIAL_HASH_BOUND_BY_VPS_PASS
SIMULATOR_GATE=BEFORE_REMOTE_GIT_OR_SSH
SSH_EFFECTIVE_CONFIG=/usr/bin/ssh -G -F VERIFIED_CONFIG VERIFIED_DESCRIPTOR_ALIAS
REMOTE_READS=3_TOTAL_1_EACH
CLAIMS=O_EXCL_FSYNC_ATTEMPT_1_NO_RETRY
NO_REFETCH_AFTER_CLAIM=YES
LOCAL_RECEIPT=CI3_LOCAL_PUBLICATION_RECEIPT_V1_PRE_TERMINAL
INSTALL=/usr/bin/install -m 0600
TERMINAL_RECEIPT=SEPARATE_VERSIONED_AFTER_INSTALL_AND_SCANS
TERMINAL_ANCHOR=EXTERNAL_ROOT_OWNED_O_EXCL_UCHG
PRIVILEGED_ANCHOR_WRITER_AUTHORITY=SEPARATE_CONTROLLER_SUPPLIED_HASH_BOUND_REQUIRED
PRIVILEGED_ANCHOR_WRITER_AUTHORITY_MISSING=STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY
NORMAL_BRIDGE_EXECUTOR_MAY_MINT_ANCHOR_AUTHORITY=NO
V1_V2_V3_EXECUTION=NO
CI3_EXISTING_PATHS=5_PRESERVED
CI3_ALLOWLIST=23_EXACT_PATHS
CI3_ORIGINAL_TASKS=2_THROUGH_11
CONTINUATION_LABEL_12=FINAL_REPORT_ONLY
CI3_PARENT=277873755bf29771a10b5f362b522c2e6a6c21d6
CI3_SUBJECT=feat(ios): connect Today to authenticated staging
CI4=NO
```

O protocolo executável completo, syscalls, schemas, paths e recovery estão na
spec e no plano versionado. Esta evidência não executa o handoff.

## 9. Estado final desta authoring operation

```text
CI3_BRIDGE_V3_STATUS=FROZEN_REJECTED
CI3_BRIDGE_V3_EXECUTED=NO
CI3_BRIDGE_ARCHITECTURE=VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1
CI3_BRIDGE_GENERATOR_TRACKED=YES
CI3_BRIDGE_GENERATOR_TESTS=131_PASS
CI3_WORKTREE_PRESERVED=YES
CI3_IMPLEMENTATION_STARTED_BEYOND_TASK1=NO
SSH_REAL_EXECUTED=NO
CONFIG_STREAM_EXECUTED=NO
CREDENTIAL_STREAM_EXECUTED=NO
REMOTE_BUNDLE_CREATED=NO
SIMULATOR_REAL_EXECUTED=NO
VERCEL_WRITE=NO
SUPABASE_WRITE=NO
PRIMARY_LIVE_OPEN=NO
CLEANUP_EXECUTED=NO
CI4_STARTED=NO
NEXT_ENVIRONMENT=VPS
NEXT_GATE=CREATE_VERSIONED_CI3_BRIDGE_BUNDLE_ON_VPS
```

## 10. Atualização operacional 1.7.1 — implementação executável local

O STOP generator-only permanece evidência histórica; não é apagado nem
reinterpretado. A rodada executável adicionou seis paths e passou a authority
para treze paths. TDD genuíno antes da produção:

```text
GENERATOR_RED=150_TOTAL_134_PASS_16_FAIL
CONTROLLER_RED=208_TOTAL_0_PASS_208_FAIL
LAUNCHER_RED=40_TOTAL_0_PASS_40_FAIL
WRITER_RED=96_TOTAL_0_PASS_96_FAIL
PROTOCOL_E2E_RED=48_TOTAL_0_PASS_48_FAIL
LAUNCH_ATTESTATION_V2_RED=15_TOTAL_0_PASS_15_FAIL
```

GREEN observado localmente nesta worktree, sem external action:

```text
GENERATOR_GREEN=150_PASS_0_FAIL_0_SKIP_0_TODO
CONTROLLER_GREEN_BASE=208_PASS_0_FAIL_0_SKIP_0_TODO
LAUNCHER_GREEN_BASE=40_PASS_0_FAIL_0_SKIP_0_TODO
WRITER_GREEN=96_PASS_0_FAIL_0_SKIP_0_TODO
PROTOCOL_E2E_GREEN=48_PASS_AS_NAMED_SUBSET_OF_CONTROLLER_SUITE
NATIVE_SSH_G_SYNTHETIC_CONFIG=PASS_NETWORK_CONNECT_0
WRITER_TEST_BUILD=PASS_PRIVILEGE_PROMPTS_0
```

As contagens finais devem ser reemitidas após o último diff; nenhum número
histórico `131` ou `174` é contagem atual da authority 1.7.1.

### 10.1 Findings finais, preservados sem deduplicação

```text
RA-FINAL-I-1 launcher Git-bound alcançável
RA-FINAL-I-2 original claim e full provenance em exact-existing/recovery
RA-FINAL-I-3 seis scans fechados e revalidação de input
RA-FINAL-I-4 anchor fecha components/generations/claims/results
RA-FINAL-I-5 authority e writer privilegiados externos
RA-FINAL-I-6 contagem/finding ledger atual
RB-FINAL-I-1 launcher executa controller snapshot Git-bound
RB-FINAL-I-2 controller Mac único e state machine completo
RB-FINAL-I-3 trust descriptor completo e parser nativo de ssh -G
RB-FINAL-I-4 simulator gate de sete fases antes de remote
RB-FINAL-I-5 scanner fecha argv/history/terminal-log/attachment/xcresult/runtime
RB-FINAL-I-6 privileged writer claim original e no-clobber
RB-FINAL-I-7 install 0600 e readback físico
RA-FINAL-M-1 stale count removido do estado corrente
RB-FINAL-M-1 Tasks 2-11 e 23 paths mantidos literalmente
```

Os seis scan IDs exatos são `argv`, `history`, `terminal-log`, `attachment`,
`xcresult`, `runtime`. Nenhum foi normalizado, renomeado ou deduplicado.

### 10.2 Boundary e authority privilegiada

`local-bridge.receipt.json` é o commit marker final da publicação Mac. A
existência de diretório/config antes dele durante crash/recovery não publica o
bundle; consumer e recovery devem tratar receipt ausente como `UNPUBLISHED` e
nunca adotar o estado. Existing exige claim original, receipt original, bytes e
metadata exatos; divergent existing STOP sem overwrite.

O terminal anchor é um domínio root-owned/version-addressed separado, publicado
por writer Swift O_EXCL+fsync+0444+`UF_IMMUTABLE`. O controller normal não é
authority para escrevê-lo. A ausência de privileged claim/writer authority
produz `STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`. Nenhuma authority
privilegiada, admin prompt ou anchor real foi criada nesta operação.

### 10.3 Preservação observada

```text
V1_V2_V3_EXECUTED=NO
GENERATOR_CREATE_EXECUTED=NO
SSH_CONNECT_EXECUTED=NO
NETWORK_EXECUTED=NO
SIMULATOR_REAL_EXECUTED=NO
INSTALL_REAL_EXECUTED=NO
STREAM_EXECUTED=NO
REMOTE_BUNDLE_CREATED=NO
TERMINAL_ANCHOR_CREATED=NO
PRIVILEGE_PROMPTS=0
CI3_TASK2_EXECUTED=NO
SUPABASE_VERCEL_PRODUCTION_WRITE=NO
COMMIT_PUSH=NO
```

Estado correto antes das reviews independentes e do único commit controller:

```text
FINAL_STATUS=STOP_PRE_AUTHORITY
CI3_BRIDGE_EXECUTABLE_AUTHORITY_STATUS=NOT_PUBLISHED
NEXT_GATE=INDEPENDENT_FINAL_REVIEWS_THEN_SINGLE_CONTROLLER_COMMIT
```

### 10.4 Fechamento do dispatch e da circularidade privilegiada

RED pós-review observado antes da implementação:

```text
OPERATIONAL_MODES_STUB_RED=9_TOTAL_0_PASS_9_FAIL
VERSIONED_JOURNAL_RED=4_TOTAL_0_PASS_4_FAIL
PRIVILEGED_WRITER_AUTHORITY_RED=14_TOTAL_0_PASS_14_FAIL
SCAN_SURFACE_AUTHORITY_RED=7_TOTAL_0_PASS_7_FAIL
```

GREEN final local/sintético:

```text
GENERATOR_GREEN_ROUND1_HISTORICAL=152_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
CONTROLLER_GREEN_ROUND1_HISTORICAL=383_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
LAUNCHER_GREEN_ROUND1_HISTORICAL=46_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
WRITER_GREEN_ROUND1_HISTORICAL=122_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
PROTOCOL_E2E_ROUND1_HISTORICAL=48
PRIVILEGED_WRITER_AUTHORITY_GREEN=14_PASS_0_FAIL
SCAN_SURFACE_AUTHORITY_GREEN=7_PASS_0_FAIL
TOTAL_GREEN_ROUND1_HISTORICAL=703_PASS
```

Os nove modos operacionais agora despacham para a mesma máquina de estados e
alcançam sua fase sob authority sintética. Produção não foi exercitada. O
operation-authority inicial contém somente paths fixos do writer/manifest; não
contém hashes futuros. Depois dos seis receipts, `scan` prepara source, binary,
signature, 62 evidências, preparation receipt e manifest. O normal executor
para aí. `write-terminal-anchor` só avança se existirem claim original e
`CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1` externo, root:wheel 0444,
`uchg`, no path versionado. Esse receipt liga os hashes já congelados e
`authority_path_sha256`; nunca é criado pela execução normal. Ausência de
autoridade de privileged writer continua STOP explícito, não handoff implícito.

Preservação deste fechamento:

```text
REAL_OPERATIONAL_MODE_EXECUTED=NO
XCRUN_SIMCTL_EXECUTED=NO
SSH_CONNECT_EXECUTED=NO
REMOTE_READ_EXECUTED=NO
INSTALL_EXECUTED=NO
WRITER_PRODUCTION_BINARY_EXECUTED=NO
PRIVILEGED_AUTHORITY_CREATED=NO
ADMIN_PROMPT=0
ANCHOR_CREATED=NO
```

Gate incremental de modes Git:

```text
EXECUTABLE_GIT_MODES_RED=3_TOTAL_0_PASS_3_FAIL
EXECUTABLE_GIT_MODES_GREEN=3_PASS_0_FAIL
LAUNCHER_GIT_MODE=100755
CONTROLLER_GIT_MODE=100755
WRITER_SOURCE_GIT_MODE=100644
PRE_COMMIT_SELF_TEST=ERROR_COMPONENT_MISSING_EXPECTED
POST_COMMIT_SYNTHETIC_SELF_TEST=PASS
REAL_COMMIT_PUSH=NO
```

## 11. Remediação executável Round 1 — evidência sem deduplicação

### 11.1 RED genuíno e GREEN atual

Antes das correções desta rodada, as quatro suites juntas observaram
`653 total / 544 pass / 109 fail / 0 skipped / 0 todo`. O helper de capture
same-fd teve RED focado `2 total / 0 pass / 2 fail` por export ausente e GREEN
`2/2`. Os testes de launcher/controller posteriores registraram RED para
reexec forjado, runtime root-owned, seis scanners específicos e a matriz E2E
Round 1 posteriormente superseded,
publisher/authority e recovery antes da produção correspondente.

GREEN final local/sintético:

```text
GENERATOR=152_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
CONTROLLER=383_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
LAUNCHER=46_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
WRITER=122_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
TOTAL_ROUND1_HISTORICAL=703_PASS
FULL_PROTOCOL_E2E_ROUND1_HISTORICAL=48
REAL_NETWORK_SSH_SIMULATOR_INSTALL_PRIVILEGE_ANCHOR=0
```

### 11.2 Findings Review A

| Finding | Fechamento nos bytes atuais |
|---|---|
| `RA1-I-5` | terminal exige seis IDs ordenados, receipts/schemas/generations/claims/results e root privilegiado; helper paralelo não aceita array parcial |
| `A4-I-1` | sete fases do simulator possuem claim pré-efeito, receipt/result físico write-once e root semântico externo |
| `A4-I-3` | bundle local usa staging no mesmo filesystem, diretório final no-replace e receipt-last como commit marker |
| `RA0-I-4` | cada fase tem claim/result separado; recovery reobserva efeitos físicos e não inventa claim retroativa |
| `RA0-I-7` | seis schemas/patterns/counters independentes cobrem secret, PII, JWT, token e raw destination; cada surface tem injeção negativa |
| `R2-I-2` | writer parseia roles e recomputa authority/components/generations/bootstrap/read chain/remote/local/SSH/simulator/install/scans |
| `R5-I-1` | chains são no-follow/root-only, files single-link e bytes lidos por fd; publication revalida root/final/entries/metadata |
| `A5-I-1` | child stdout vai diretamente ao fd capture O_EXCL e hash/read usam o mesmo fd/inode; claim precede spawn |
| `A5-I-2` | generator/controller/launcher são snapshots Git-bound, e o launcher reexec verifica a si mesmo antes do dispatch |
| `R5-I-2` | parser consome a saída nativa ordenada e duplicate-aware de `/usr/bin/ssh -G` contra descriptor separado completo |
| `R5-I-3` | não existe filtro remoto customizado; command é `exec /usr/bin/cat -- <exact-path>` com gramática fechada |
| `RA-FINAL-I-1` | subject único e launcher VPS version-addressed materializam/executam o generator blob exato |
| `RA-FINAL-I-2` | claim original liga parent/tree/subject/manifest/components/source+remote generations; exact-existing exige essa claim |
| `RA-FINAL-I-3` | claims de scan ligam path/hash/metadata originais; controller e writer reabrem os seis inputs antes do anchor |
| `RA-FINAL-I-4` | anchor fecha quatro components, quatro generations e todos claims/results; readback é root/no-follow/immutable |
| `RA-FINAL-I-5` | receipt privilegiado externo e claim original são obrigatoriamente consumidos; normal executor não os cria |
| `RA-FINAL-I-6` | ledger terminal tem exatamente os 24 IDs independentes; counts Round 1 de 703/48 foram superseded pelo bloco Round 3 |
| `RB-FINAL-I-1` | launcher materializa seu blob, reexec valida repo/HEAD/self hash/Git hash e usa Node operacional root-owned imutável |
| `RB-FINAL-I-2` | todos os modos operacionais alcançam a mesma state machine e usam journal claim/result/recovery durável |
| `RB-FINAL-I-3` | descriptor versionado liga alias/destination/port/identity/public fingerprints/known_hosts/ssh binary e full `ssh -G` |
| `RB-FINAL-I-4` | sete receipts de simulator existem fisicamente e o gate encerra antes de bootstrap remoto/SSH/read |
| `RB-FINAL-I-5` | seis scanners são implementações semânticas distintas e terminal revalida inputs completos |
| `RB-FINAL-I-6` | writer exige privileged claim + authority root-owned immutable e rejeita inputs user-controlled sem eles |
| `RB-FINAL-I-7` | install receipt 0600 é persistido, hash-bound, ligado a executable/destinations/readback/metadata e consumido pelo writer |

`RA-FINAL-M-1` foi fechado pelas contagens correntes separadas; `RB-FINAL-M-1`
pelas Tasks originais 2–11, cinco paths preservados e 23 paths literais.

### 11.3 Findings Review B novos

| Finding | Fechamento nos bytes atuais |
|---|---|
| `RB-EXEC-C-1` | controller nunca eleva o candidate user-owned: exige e executa somente writer root:wheel `0555`, single-link, `uchg`, path+hash+identity ligados ao receipt externo; replacement do candidate ou do root binary STOP |
| `RB-EXEC-I-1` | caminho operacional usa exatamente `xcrun swiftc -parse-as-library -o ...`; o source de produção compila sem transformação |
| `RB-EXEC-I-2` | writer não deriva boundary de `NSHomeDirectory()` elevado; manifest/authority são argumentos/paths fixos e hash-bound |
| `RB-EXEC-I-3` | remote command builder exige `exec /usr/bin/cat --` e path absoluto com gramática fechada, rejeitando metacaracteres/newline |
| `RB-EXEC-I-4` | receipt/config/credential são parseados e cross-validados em todos os campos/relações críticas antes da publication local |
| `RB-EXEC-I-5` | spec/plan/dossier agora contêm manifest literal, resolver OID/hash, launcher VPS, entrypoint Mac, fases e boundary dos dois publishers |

### 11.4 Limite honesto de authority

Fechamento em código/testes não cria authority operacional. Um controller
humano ainda precisa, depois de reviews independentes `0C/0I`, produzir o
único commit; o VPS precisa publicar o PASS; e publishers externos com
autoridade concreta precisam instalar o Node/operation receipt e o writer/
privileged receipt root-owned. Se qualquer autoridade estiver ausente, o
resultado continua `STOP_PRE_AUTHORITY` ou
`STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY`. Nenhuma authority futura é
presumida, delegada ou mintada silenciosamente por estes treze paths.

## Round 2 remediation evidence

Os findings dos reviews Round 2 foram convertidos em contratos executáveis:
SSH argv sem separador espúrio; cinco paths preservados e allowlist de 23
literal/hash-bound; config/credential/receipt com exact schemas; trust
descriptor cruzado à authority concreta; seis surface collectors fixed e
autenticados; claims físicos e evidence roles das sete fases simulator;
manifest literal e full semantic recomputation no Swift; claim original para
bundle/install/writer; directory promotion exclusiva descriptor-bound; e 48
cenários distintos de crash/recovery.

Claim sem result não chama o effect. O journal primeiro tenta reabrir o physical
receipt; se ele não existe, retorna `CLAIM_CONSUMED_NO_RESULT`. Se existe, bytes
e metadata (`uid/gid/mode/nlink/size/mtime_ns/dev/ino`) produzem um observation
hash independente antes de completar result/event. Um exact-existing sem claim
anterior é rejeitado. A publicação local promove o diretório inteiro por
`renameatx_np(RENAME_EXCL)`, sem arquivo canonical individual prévio.

Os dois gaps de handoff foram implementados como modos públicos Git-bound. O
Publisher 1 consome request + human receipt + PASS VPS, publica Node/controller,
operation authority e seis collectors/surfaces root-owned immutable. O
Publisher 2 consome um segundo human receipt, publica original claim antes do
writer, recomputa a identidade física no domínio root e cria o privileged
authority receipt com O_EXCL. Ambos preservam no-clobber/fsync/readback e
retornam saída sanitizada. Código não é autoridade: nenhum receipt humano foi
fornecido e nenhum publisher/admin prompt foi executado nesta rodada.

As contagens Round 1 `676`/controller `358` foram superadas pelos gates finais
desta implementação e devem ser lidas do implementation report atualizado.
Até review independente atingir `0 Critical / 0 Important`, o estado continua
`STOP_PRE_AUTHORITY`; não há autorização para commit/push/handoff/Task 2.

## 12. Evidência superseding Round 3

Esta seção substitui as contagens 703/48 e qualquer afirmação de que o
Publisher 1 instala surfaces fornecidas pelo VPS. O VPS PASS agora liga apenas
operation authority, Node, publisher input manifest e os seis contratos; as
surfaces finais nascem depois de B0/fetch/install, da generation corrente.

REDs genuínos antes da produção correspondente:

```text
CONTROLLER_ROUND3=9_TESTS_0_PASS_9_FAIL
SIMULATOR_RECOVERY=3_TESTS_0_PASS_3_FAIL
WRITER_SEMANTIC=4_TESTS_1_PASS_3_FAIL
LAUNCHER_WRITER_E2E_ATTESTATION=1_TEST_0_PASS_1_FAIL
```

GREEN fresco:

```text
GENERATOR=152_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
CONTROLLER=408_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
LAUNCHER=108_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
WRITER=128_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
TOTAL_GREEN=796_PASS
SWIFT_EXACT_PARSE_AS_LIBRARY=PASS
ZSH_SYNTAX=PASS
```

Os 60 E2E são dez fases por seis boundaries e executam o launcher Git-bound e
o writer compilado para synthetic test. `RUN_SCANS` passou a integrar os 24
roles de controller do manifest; `INVOKE_WRITER`/`VERIFY_ANCHOR` são dois
contratos posteriores encadeados ao result físico de `RUN_SCANS`, evitando
self-hash do anchor.

O writer agora recompõe o grafo semântico completo: claims/results/captures,
commands e expected bytes, parent/subject/source commit, read chains, remote/
local/SSH/simulator/install, predecessor+contract+observation de cada fase,
input/terminal receipts, seis tool/command/schema/output roots e settlement
contracts. Ele distingue hash dos bytes da public key do hash da saída de
fingerprint e rejeita mutations autoconsistentes.

Recovery de fase reexecuta somente observers tipados sobre alvos físicos; o
simulator revalida ausência antes de claims originais e jamais adota config,
credential ou ACK. Os scans aceitam apenas sources fixos autenticados da
execução atual, materializam surfaces generation-bound e reabrem bytes e
metadata após o scan.

O Publisher 1 exige `CI3_VPS_PUBLISHER_INPUT_MANIFEST_V1`,
`CI3_VPS_OPERATION_AUTHORITY_PASS_V1` e receipt humano que liga ambos. Ele
publica PASS/input manifest junto de Node/controller/authority, mas não mintou
nem recebeu authority durante esta rodada. Nenhum modo real, rede, SSH,
simulator, install, prompt administrativo, anchor, Task 2, commit ou push foi
executado; `STOP_PRE_AUTHORITY` permanece até reviews independentes 0C/0I e o
único commit do controller.

## Round 4 remediation evidence

The prior 796 count and its label-only E2E characterization are superseded.
Strict RED was observed before production implementation:

```text
CONTROLLER_ROUND4_INITIAL=18_TESTS_0_PASS_18_FAIL
CONTROLLER_ROUND4_MATERIALIZER=1_TEST_0_PASS_1_FAIL
CONTROLLER_ROUND4_TERMINAL_SETTLEMENT=1_TEST_0_PASS_1_FAIL
WRITER_ROUND4=5_TESTS_0_PASS_5_FAIL
LAUNCHER_INTEGRATED_E2E=1_TEST_0_PASS_1_FAIL
```

Focused GREEN after implementation:

```text
CONTROLLER_ROUND4=20_PASS_0_FAIL
WRITER_ROUND4=5_PASS_0_FAIL
LAUNCHER_OPERATIONAL_E2E=60_PASS_0_FAIL
```

The controller's settled-event fast path now invokes the typed physical
observer for all ten durable phases. The operational observers re-read the
current worktree, simulator and native SSH inputs where the effect remains
observable, and `RUN_SCANS` reopens each scan receipt, final surface and fixed
semantic source. Mutation of any current observation produces
`PHASE_RECOVERY_DIVERGENCE`.

The six scanners consume actual current-operation sources under fixed
`final-sources/<id>.surface` paths. `xcresult` alone may use its explicit
authenticated absence contract. The writer verifies source path/range/parent,
current bytes or current absence, surface bytes, scanner command/schema/tool,
counters, output root and post-scan metadata. No event/claim/receipt alias is a
source.

The writer also reconstructs the 13-line authority manifest and reopens exact
production paths for operation authority, signed VPS PASS, external issuer,
human authorization, publisher manifest, SSH descriptor and public key. It
recomputes the public-key fingerprint with `/usr/bin/ssh-keygen` and cross-binds
all descriptor/operation-authority fields. No real issuer key is present; a
future missing issuer or privileged-writer authority is a mandatory
`STOP_PRE_AUTHORITY`.

The terminal publication is one privileged transaction. `pre-anchor.json` is
`PENDING_VERIFICATION`; the same writer invocation reopens it, derives the two
final phase chains, scans terminal bytes and creates the append-only/no-clobber
`terminal-settlement.json`. Only that receipt declares `TERMINAL_PASS`.

Each of the 60 E2E cases uses a fresh synthetic 13-path authority commit and
the official executable launcher, injects the selected crash into the
production state machine, resumes or fail-closes without effect replay, and
runs the compiled writer test build as the `INVOKE_WRITER` effect. This remains local/synthetic: zero real SSH/network,
simulator mutation, admin prompt, publisher, root anchor, Task 2, commit or
push.

Final fresh suite totals for this remediation are:

```text
GENERATOR=152_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
CONTROLLER=434_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
LAUNCHER=108_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
WRITER=137_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
TOTAL=831_PASS_0_FAIL_0_CANCEL_0_SKIP_0_TODO
EXACT_SWIFT_PARSE_AS_LIBRARY=PASS
NODE_CHECK_6=PASS
ZSH_N=PASS
```

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

## Round 6 evidence boundary

Synthetic evidence now proves: the worktree launcher rejects Publisher 0;
Publisher 0 validates a fixed root-owned bootstrap, issuer hash, component
hashes, clean environment and full `/var/lib/agentempp/...` directory chain;
runtime persistence uses a closed sanitized allowlist; SSH policy rejects
`SendEnv`, `SetEnv`, agent persistence and background authentication; SSH
snapshot identity is stable across `ssh -G` and connects; raw history,
terminal-log and attachment bytes are scanned before and after Base64 framing;
the writer binds all three remote content hashes; and `complete-result.json` is
published after the final settlement scan. This is synthetic proof only. The
external issuer/bootstrap materializer and real authorities are absent, so the
observed operational state remains `STOP_PRE_AUTHORITY`.

The Round 6 E2E correction also removes the pre-created terminal fixture from
the 60-case matrix. At `INVOKE_WRITER`, the same Git-bound controller reopens
its settled durable snapshot, requires it byte-stable across a closed-env local
materializer, and publishes its copy only as the
`controller-durable-state-root` manifest role. Descriptor path/hash,
scenario/hash and canonical snapshot hash are cross-checked by the controller;
the Swift test writer reopens that role, validates all durable-map fields and
recomputes the hashes. `after-claim` cases have no effect, no materialization
and `STOP_CLAIM_CONSUMED_NO_RESULT`. This is synthetic provenance evidence,
not a real authority receipt.

## Round 8 remediation evidence

Strict RED was observed before each implementation cluster: three terminal
tests returned `COMPLETE`, rejected the internal terminalizer mode and called
the old status reader; the durable journal lacked `claimTerminalTail`; the
worktree Publisher 0 returned `MODE_INVALID` instead of the explicit authority
STOP; the external launcher fell into `GIT_AUTHORITY`; the Publisher 1 contract
lacked its launcher-bootstrap authority; and hostile bootstrap variables were
silently discarded instead of explicitly rejected. The corresponding focused
tests are now GREEN.

The implemented evidence is local and synthetic: a Swift `openat` transaction
and Node-core retained-fd Linux transaction reject symlink/writable/swap and
no-clobber cases; the external launcher self-test validates its ten-line
authority before a fixed synthetic Node and rejects a changed Node hash; the
Publisher 1 contract reopens sixteen targets and all five SSH files; and the
terminal journal keeps `PRE_TERMINAL_UNPUBLISHED` until its receipt-last marker,
then rejects mutation of every posterior surface. The scanner counter test
proves two disjoint destination ranges count as two while an overlapping
specific/fallback match counts once.

No `/usr/bin/python3`, Python helper, network, SSH, simulator, root/admin,
external issuer, remote bundle or anchor was invoked. The real external
issuer/bootstrap and privileged writer authorities remain absent. Therefore
the honest operational evidence state is still `STOP_PRE_AUTHORITY`, even
though the executable adapters and synthetic gates are now present.

## Round 9 remediation evidence

The first RED cluster proved that a normal journal could not yet consume a
privileged marker, the marker schema/path functions did not exist, and the
terminalizer still lacked retained emission. The second RED cluster returned
`MODE_INVALID` for the Publisher 1 transaction; subsequent REDs proved the
hash-bound request entrypoint was absent and that installed directories stayed
`0700` instead of frozen `0555`. Focused GREEN now covers the privileged marker,
actual journal frame, interleaving pathname swap, hash-bound request,
descriptor-retained source swap, destination-ancestor swap, post-promotion
crash recovery, directory-tree freeze and exact-existing reobservation.

The normal journal no longer owns a terminal claim/receipt. The single Swift
writer transaction creates root-owned journal/stdout/stderr/COMPLETE frames and
`CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1` last. That marker binds authority,
four generations, controller/launcher, privileged authority, settlement,
complete/final-scan, fixed paths and exact bytes. `status` cannot report
`TERMINAL_PASS` without rereading that exact privileged marker. The launcher
no longer reopens the scanned final output with `cat`; the controller emits the
already retained Buffer, and a swap between scan and emission still emits only
the clean retained bytes.

`controller-durable-state-root` now contains a reversible frame of every real
journal object, not a digest pointer. Every raw object and the combined frame
are scanned before Base64; Swift decodes it, verifies path/hash/length/identity
records and scans decoded objects again. A late dirty journal object stops the
materialization test.

Publisher 1 no longer uses the Node `/usr/bin/install` shell or pathname
readback. The normal side snapshots authenticated retained bytes; a fixed
root-owned immutable materializer authority and issuer receipt are mandatory.
The Swift binary validates its own fixed path/hash/authority, opens the
hash-bound request once, walks absolute ancestors with retained
`openat/O_NOFOLLOW`, independently verifies the issuer Ed25519 PASS and
transport relationships, writes the claim `O_EXCL` only after source
validation, promotes one complete directory `RENAME_EXCL`, fsyncs/readbacks,
and records a result. Claim recovery reobserves without refetch/reexecution;
unclaimed/partial/divergent state is never adopted.

The real external issuer/materializer/bootstrap objects are intentionally not
present and were not created. No network, SSH, simulator, admin prompt, root
write, terminal anchor, Task 2, commit or push occurred. Current real state:
`STOP_PRE_AUTHORITY`.

## Round 10 closure evidence

Round 10 removed the remaining double-finalization path. The normal state
machine now stops publication after one COMPLETE commit-contract event and one
reversible journal frame. It calls one privileged writer and writes nothing
afterward. The writer independently constructs both privileged phase triples,
settlement, final scans, COMPLETE objects and output frames, reopens every
object, then publishes `terminal-pass.marker.json` last. Absence of that exact
root-owned marker is unpublished; there is no normal-owned fallback PASS.

The integrated synthetic launcher exercises the real Git-bound controller and
compiled Swift writer at each of six crash boundaries for both privileged
phases. Crash controls exist only in the synthetic build and are written before
the PASS marker; restart accepts only byte-identical partial roots and never
creates a second effect. The production source has no crash-control surface.

Publisher 1 now consumes a fixed request path plus expected hash under external
V2 materializer authority. That authority binds request physical identity and
the exact receiver descriptor, so stdin, suffix collision, source/ancestor
swap and an alternate receiver fail closed. Root settled state is physically
observed before any admin child; exact state is reused, while claim-only,
partial or divergent state STOPs without reprompt. The Swift transaction fsyncs
staging, performs `RENAME_EXCL`, and only then freezes/readbacks destination.
A non-synthetic Darwin temporary-root probe validates this ordering and the
exclusive race without touching the real receiver.

These are synthetic/local proofs only. No external issuer/materializer/root
authority was supplied, and no privilege, network, SSH, simulator, real anchor,
Task 2, commit or push occurred. Current real state remains
`STOP_PRE_AUTHORITY`.

## Round 11 remediation evidence

Strict RED first showed that the V2 Publisher 1 authority rejected the new
ordered leaf schema, accepted no full physical leaf proof, returned an internal
terminal PASS without a privileged marker and had no partial-root recovery
state machine. A second RED showed that artifact/freeze crash injection was
absent and that `resume` still reported pre-terminal after a marker-validating
status had returned PASS.

Focused GREEN now binds all sixteen receiver leaves across external authority,
request, original claim and result with exact role/path/content plus
uid/gid/mode/nlink/size/mtime/dev/inode/identity. Swift validates stable
descriptor metadata before and after every read and repeats receiver-directory
and leaf identity checks immediately before the claim. Negative fixtures cover
wrong owner, wrong mode, hardlink, same-bytes inode swap and source pathname
swap, all before a durable claim.

The operational terminal path no longer accepts the earlier five-object
subset. A PASS result requires the privileged marker hash and validation of its
authority-fixed transitive roots. Exact partial state re-enters the reviewed
writer recovery; dirty state fails. Synthetic artifact crashes after COMPLETE
final scan, retained frames, marker readback and directory freeze all recover
to the same marker and a subsequent exact-existing result. `resume` reports
PASS only after `terminalStatus` validates that marker.

Privilege continuity is now executable without a persistent helper: the one
authorized Swift invocation is a transient supervisor and spawns the exact
same absolute binary with a closed environment as its worker. Four worker
crashes are recovered internally with one marker and no second controller
effect/admin child. Controller recovery is observe/wait-only. If the root
supervisor itself is gone before the marker, the tested outcome is
`STOP_PRE_AUTHORITY`, not a new prompt or PASS. No real privilege, Publisher,
network, SSH, simulator, anchor, Task 2, commit or push occurred. Real state
remains `STOP_PRE_AUTHORITY` because the external authorities are absent.

## Round 12 remediation evidence

Strict RED first reproduced both residuals. The immutable-boundary test
observed `-` instead of `uchg` on a marker interrupted around flag publication;
the controller marker test observed an undefined `preAnchor` path because only
nine roots were bound. GREEN now uses the original validated privileged-claim
hash at every anchor publication, retained descriptor `fstat/read/fstat`,
descriptor-relative parent reobservation and `fchflags`. Synthetic Darwin tests
crash exactly before and after flags, recover one exact marker with real
`UF_IMMUTABLE`, and reject exact bytes when the original claim is absent.

The common marker reader now derives eighteen fixed paths and reads all of them
as immutable root files. It also validates the exact terminal and phase
directory entry sets and stable directory metadata. Semantic verification
recomputes the two phase triples and graph, authority/generations, fixed target
paths, physical target metadata, pre-anchor, writer output, settlement, final
scan, COMPLETE event/result/final scan and marker fields. Missing, extra or
mutated roots fail closed.

Fresh local gates passed: generator `152/152`, controller `462/462`, launcher
and integrated E2E `114/114`, writer `159/159`, total `887/887`; exact Swift
production compilation and writer self-test also passed. No real external
authority, privilege, SSH/network, simulator, anchor, Task 2, commit or push
occurred. Current real state remains `STOP_PRE_AUTHORITY`.

## Round 13 remediation evidence

The strict RED used a complete real-schema authority receipt and pre-anchor,
then regenerated every downstream phase hash, settlement, writer output,
COMPLETE root and marker. The prior transitive reader accepted an extra
authority field (`Missing expected exception: authority extra field`), proving
that byte-hash consistency did not imply semantic authority consistency.

GREEN introduces one shared `validatePrivilegedTerminalPassCorpus` route for
the operational marker reader, journal `terminalStatus`, recovery and terminal
emission. It reuses `validatePrivilegedWriterAuthorityReceipt` verbatim and a
single exact pre-anchor validator. The negative matrix covers extra/missing or
mutated schema, attempt, retry, raw policy, purpose, result/state, timestamp,
fixed path, source/binary/signature/claim, array/hash and transitive relations;
each invalid corpus is downstream-rehashed and still STOPs. A complete corpus
passes twice to prove exact-existing revalidation.

All verification remained local and synthetic. No external authority,
privilege, SSH/network, simulator, real terminal root, Task 2, commit or push
was used; the real state remains `STOP_PRE_AUTHORITY`.

Fresh final Round 13 gates passed on the completed corpus: generator `152/152`,
controller `464/464`, launcher plus 60 causal E2E `114/114`, and writer
`159/159`; aggregate `889/889`, zero fail/cancel/skip/todo. The final aggregate
duration was `317013.458375 ms`.

## Round 14 evidence — canonical validation of all 71 roles

Review A Round 13 reproduced `ADVERSESARIAL_PHASE_CONTRACTS=ACCEPTED`: the
common reader reopened only the eight normal phase receipts, obtained the
initial terminal predecessor from the manifest itself and accepted arbitrary
but self-consistently rehashed `INVOKE_WRITER`/`VERIFY_ANCHOR` contract roots.

Strict RED was captured in two independent gates. The controller test failed
with `Missing expected exception: ADVERSESARIAL_PHASE_CONTRACTS=ACCEPTED`; the
read-only writer test failed with `ERROR MODE_INVALID`. GREEN adds a read-only
mode to the already Git-bound immutable Swift writer. It shares the exact
publication-grade `validateManifest()` and `validateSemanticRoots()` functions,
reopens all 71 role files plus all six scan receipts, and emits only a closed
hash receipt. The operational controller invokes that absolute binary with a
closed environment on every marker read and rejects any nonzero exit, stderr,
extra output or receipt mismatch.

The common corpus now starts with the reopened `RUN_SCANS` result, reconstructs
both terminal settlement contracts from constants, requires each claim's exact
contract hash and requires `RUN_SCANS → INVOKE_WRITER result → VERIFY_ANCHOR` as
the predecessor chain. A negative matrix rewrites and rehashes manifest
pointers for authority manifest, launch/bootstrap/read, remote/local, SSH,
simulator, install/input/terminal/durable state, external authority, simulator
phase, controller claim/receipt/result and scan-receipt classes; every case
STOPs and no anchor appears.

All work and tests are synthetic/local. No real root/admin action, prompt,
network/SSH, simulator, external authority, anchor, continuation, commit or push
was performed; real execution remains `STOP_PRE_AUTHORITY`.

Fresh completed Round 14 gates passed on the final corpus: generator `152/152`,
controller `466/466`, launcher plus 60 causal E2E `114/114`, and writer
`161/161`; aggregate `893/893`, zero fail/cancel/skip/todo. The aggregate
duration was `309028.555542 ms`. Exact Swift production compilation, writer
self-test, Node syntax, zsh syntax, diff/allowlist and sensitive-literal scans
remain mandatory controller gates before the single authority commit.

## Round 15 evidence — exact BigInt identity parity

Review A Round 14 reproduced a legitimate writer rejection caused by Node
rounding `mtimeMs` to nanoseconds while Swift hashed exact `st_mtimespec`
nanoseconds. Strict RED compiled the real synthetic writer, assigned a
sub-millisecond mtime and compared its `--validate-manifest` receipt with the
current Node formula: `equal=false`. A second RED showed that the canonical
BigInt helper did not yet exist.

GREEN introduces one exact decimal serializer and routes every controller
identity-producing `lstat/fstat` through BigInt stats. The hash formula is
field-for-field equal to Swift and covers uid, gid, permission mode, nlink,
size, mtimeNs, dev and ino before any bounded JSON conversion. Generator
identity paths now also require native `mtimeNs` and have no `mtimeMs`
fallback. The real probe compares equal, while a one-nanosecond mutation and
independent mutations of every identity field produce different hashes.

All verification is synthetic/local. No external authority, root/admin
operation, network/SSH, simulator, anchor, continuation, commit or push was
performed; real execution remains `STOP_PRE_AUTHORITY`.

Fresh completed Round 15 gates passed on the final corpus: generator `152/152`,
controller `468/468`, launcher plus 60 causal E2E `114/114`, and writer
`161/161`; aggregate `895/895`, zero fail/cancel/skip/todo. The aggregate
duration was `333387.497084 ms`. The production-source audit found zero
`mtimeMs` or Number-to-BigInt rounding paths in the controller, generator and
Swift writer identity boundary.

## Round 16 evidence — residual `dev`/`ino` authority boundaries

Review A Round 15 found two residual common `lstat` calls: local directory
promotion compared rounded Number `dev`/`ino`, and simulator-container
authority hashed their already-rounded decimal strings. Strict RED exercised
the production boundaries with exact adjacent integers above `2^53`.
Promotion incorrectly completed (`promotionDevInoEqual=true`), and the legacy
simulator digests were equal (`simulatorHashEqual=true`); the focused result
was `0/2` in `3165.418541 ms`.

GREEN routes every promotion observation through BigInt `lstat` and direct
BigInt comparison. The simulator observer uses BigInt `lstat` and the shared
canonical `uid;gid;mode;nlink;size;mtimeNs;dev;ino` identity. Both boundary
tests now reject or distinguish `9007199254740992` from
`9007199254740993`; focused result: `2/2` in `2862.024791 ms`.

The controller/generator/test audit found no other unbounded physical field
entering an authority identity or `dev`/`ino` equality through Number. Plain
stats that remain in production are absence/existence probes or bounded
type/mode/owner checks followed by descriptor-bound BigInt reobservation.
Intentional Number conversion remains only in regression tests that prove the
legacy collision. Verification is synthetic/local and real execution remains
`STOP_PRE_AUTHORITY`.

Fresh completed Round 16 gates passed on the final corpus: generator `152/152`,
controller `470/470`, launcher plus 60 causal E2E `114/114`, and writer
`161/161`; aggregate `897/897`, zero fail/cancel/skip/todo. Aggregate duration:
`331884.740209 ms`. Exact Swift production compilation/self-test, Node and zsh
syntax, diff/allowlist and sensitive-literal gates also passed locally.

## Round 17 evidence — exact generator owner-only metadata

Review A Round 16 found that `metadataView()` converted BigInt `size` to
Number before the owner-only reader's descriptor/path comparisons. Strict RED
proved `stableIdentityAccepted=true` for exact sizes `2^53` and `2^53+1` and
showed the production reader lacked the required exact test seam: `0/2` in
`72.151417 ms`.

GREEN keeps every physical field BigInt in `identity()` and `metadataView()`,
requires BigInt or canonical decimal strings in stable comparison, and hashes
the shared eight-field controller/Swift preimage. The actual owner-only reader
was exercised in original-claim, exact-existing, staging and recovery contexts;
each rejects the adjacent-size transition after both descriptor observations.
Focused result: `2/2` in `74.53875 ms`; generator full result: `154/154` in
`746.886833 ms`.

The complete generator audit found no unbounded physical field converted to
Number before identity, equality or hashing. Remaining conversions use a
closed safe-integer gate only for bounded owner, mode and link checks. Work and
tests remain synthetic/local; real execution remains `STOP_PRE_AUTHORITY`.

Fresh completed Round 17 gates passed: generator `154/154`, controller
`470/470`, launcher plus 60 causal E2E `114/114`, and writer `161/161`;
aggregate `899/899`, zero fail/cancel/skip/todo. Aggregate duration:
`350569.14525 ms`. Exact Swift compilation/self-test and all final local scope,
syntax, precision and sensitive-literal gates also passed.

## Successor environment ruling — Bridge V2

Esta evidência histórica não é reclassificada como execução da nova bridge.
O launcher que ela validou no Mac é o predecessor estrutural da authority V2.
A comparação na VPS congela skeleton SHA-256 igual em ambos os lados:
`ad3ab9d577d413c611bf000f1a64ef351e7060f5eb068dfca11879c163dfc1a8`.
Logo, somente constants, authority bindings e manifest data mudaram; grammar,
controle de fluxo, redirects, quotes, funções e call graph não mudaram.

`VPS_ZSH_SYNTAX_EXECUTION=NOT_APPLICABLE`. A validação sintática continua
obrigatória no Mac, pelo blob exato e `/bin/zsh -n`, antes de rede, simulador,
SSH, claim ou remote read. Bash não é substituto e a VPS não instala zsh.

## Successor receipt ruling

A authority canônica do env receipt muda apenas constants, manifest data e o
contrato semântico de sete campos. O skeleton do launcher permanece idêntico
ao predecessor Mac-validado; esta evidência não concede PASS zsh na VPS. O
Gate 0 continua sendo `/bin/zsh -n` sobre o blob exato antes de toda rede.

## Successor deployment receipt ruling

A reconciliação do deployment receipt altera apenas bindings de dados do
launcher: parent, subject e manifest de 16 paths. O skeleton estrutural deve
permanecer byte-equal ao predecessor Mac-validado; shebang, funções, fluxo,
redirects, quotes, pipelines, traps, FDs e call graph não mudam. A VPS continua
sem instalar ou executar zsh, e não pode declarar syntax PASS.

O novo receipt remoto registra separadamente `deployment_node=22.x` e a
authority de adoption do capsule. Essa separação não muda o executable do Mac
nem reabre qualquer comando remoto. O Gate 0 permanece `/bin/zsh -n` sobre o
blob exato antes de simulador, SSH, claims ou network.
