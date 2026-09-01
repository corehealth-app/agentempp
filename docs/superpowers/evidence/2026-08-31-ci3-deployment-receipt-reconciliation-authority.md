# CI-3 canonical input contracts reconciliation authority

## Operation and frozen STOP

```text
OPERATION=RECONCILE_ADDITIONAL_BRIDGE_INPUT_CONTRACT
PREDECESSOR_STOP=70a7d60dd9c4224e3be9072ce5fbd966bd534560
ENV_RECEIPT_AUTHORITY=c5172be7752f79c1acbf0e68d0d75a6bd880948a
ENV_RECEIPT_AUTHORITY_ATTEMPTS=0/1_NOT_EXECUTED_SUPERSEDED
BRIDGE_V1_ATTEMPTS=1/1_CONSUMED_NO_RETRY
BRIDGE_V2_ATTEMPTS=1/1_CONSUMED_NO_RETRY
NODE_RUNTIME_V2_CAPSULE_STATUS=VERIFIED_ADOPTED_READ_ONLY
```

O STOP anterior é válido. A authority c517 não invocou `--create`; não existe
authority root, claim, staging, generation, config, bundle ou receipt dela.
Nenhum predecessor pode ser executado novamente ou receber claim retroativo.

## Physical receipt and provenance

O deployment receipt físico foi aberto por descriptor com `O_NOFOLLOW`, lido
uma vez, validado como root:root 0600, regular, single-link, em parent 0700 e
confirmado pelo SHA-256 publicado
`f9f2b8cdb4aaa066ceb5ec73978f32d8710c434a9582b68ed9b1375096ce60b6`.
O body integral, origin, provider IDs e valores não foram relatados.

Campos canônicos não sensíveis:

```text
schema_version=1
purpose=ci3-dedicated-mobile-bff-deployment
environment=staging
framework=nextjs
node=22.x
root=apps/mobile-bff
target=preview
ready_state=READY
production_deployment_count=0
env_preview_production_development=3/0/0
sso_protection=null
route_count=40
public_probes=30/30
```

O próprio receipt liga a recovery authority
`7b08e67c81e63b3302de6d8642b3855f5ec60ed9`. Essa authority publicou o
contrato do Preview dedicado com root `apps/mobile-bff`, Node `22.x` e
framework `nextjs`; o commit final
`34636d321d5d5fa2d108a88ffda2dc2a7072de90` registrou o mesmo estado e o hash
físico final. A busca histórica não encontrou reclassificação posterior de
purpose ou Node. O generator c517 introduziu expectativas incompatíveis:
purpose com underscores e Node de execução `24.14.0`.

## Two independent Node contracts

`deploymentReceipt.node` é a configuração/runtime Vercel e exige igualdade
literal com `22.x`; não aceita aliases, ranges, prefixos, trim ou normalização.
O runtime de execução é o capsule privado governado pelas authorities
`b08e6326fbd22c96b852ccfe53abdeb254e54bd1` e
`461a2e0dbe091a5c352d5dfdc1952b444f41aac0`. A adoção permanece
`VERIFIED_ADOPTED_READ_ONLY`; deployment Node não seleciona executable, e
capsule version/hash não reclassifica o deployment receipt.

## Successor authority contract

```text
ARCHITECTURE=VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING_WITH_CANONICAL_INPUT_CONTRACTS_V1
AUTHORITY_PARENT=70a7d60dd9c4224e3be9072ce5fbd966bd534560
AUTHORITY_SUBJECT=build(ops): reconcile remaining CI-3 bridge input contracts
AUTHORITY_PATH_COUNT=16
BRIDGE_DEPLOYMENT_RECEIPT_ATTEMPTS=0/1
BRIDGE_DEPLOYMENT_RECEIPT_RETRY=NO
```

Os 16 paths são o dossiê, quatro evidências, spec, dois planos e oito
componentes/testes. Reader bounded, protocols do controller/launcher/writer,
seis scans, três futuras leituras Mac, terminal anchor e Gate 0 zsh permanecem
fechados. O receipt remoto registra separadamente o deployment Node e a
authority/hash/status do runtime de execução, sem path bruto.

Antes do commit, a authority exige 62 testes de reconciliação, generator >=390,
reader >=48, controller >=704, E2E >=60, launcher >=22, writer >=4, self-test,
preflight read-only real dos cinco inputs, scans e duas reviews com zero
Critical/Important. O preflight não pode escrever, criar claim/output ou abrir
primary/live. Os cinco hashes precisam permanecer exatos.

## Safety and terminal disposition

Nenhum receipt/secret é editado. Não há ldd, probe, chattr, instalação, zsh,
Vercel, Supabase, banco, primary/live, produção, simulator, CI-3 Task 2, CI-4
ou cleanup. A tentativa operacional só pode existir após publicação/readback
remoto da authority. Qualquer falha ou ambiguidade consome no máximo a única
tentativa real e preserva claim/staging/final sem retry.

## Canonical credential marker and provenance

A authority publicada `e4159e853e6a5938f4620afdce194eb8dab3232d`, o
launcher contemporâneo preservado, o claim, a credential, o recovery receipt,
o provisioning receipt e os ledgers comprovam que `synthetic_marker` é um
identificador específico da operação. Seu formato fechado é
`ci3-synthetic-YYYYMMDDTHHMMSSZ-<BASE32>`, com 16 caracteres do alfabeto
maiúsculo `A-Z2-7`. A credential relaciona o marker byte-exact ao e-mail no
domínio reservado `example.invalid`. A canonicalização lowercase aplicada pelo
Supabase Auth vale somente para a identidade persistida e nunca reescreve o
marker.

O label estático do provisioning receipt é `ci3_authenticated_today`. Marker,
e-mail sintético, e-mail canonicalizado, operation/actor IDs e Auth/patient/
entitlement/event IDs são classes distintas. O marker é igual entre claim,
credential, recovery e provisioning; ele não é igual a nenhum desses IDs. O
SHA-256 sanitizado do marker físico é
`9f768034584af72f213b9d89816d4f1d506141a37375477369a4817180e4bdd3`.
Marker, e-mail e senha brutos não foram emitidos.

## Closed reconciliation matrix

| Artifact / field | Canonical contract | Classification | Evidence |
|---|---|---|---|
| credential.synthetic_marker | operation-scoped marker V1 | `GENERATOR_EXPECTATION_BUG` | `e4159e85…`, creator/claim/credential/receipt hashes |
| credential.email | exact marker plus reserved domain | `GENERATOR_EXPECTATION_BUG` | `e4159e85…`, credential hash |
| provisioning.purpose | `ci3_authenticated_today` | `GENERATOR_EXPECTATION_BUG` | resume builder, receipt hash, `9f5cbb61…` |
| provisioning.authority_sha | resume authority `5cecaa7…` | `GENERATOR_EXPECTATION_BUG` | resume builder and receipt hash |
| provisioning.cleanup_deadline_class | `CREATED_AT_PLUS_14_DAYS` | `GENERATOR_EXPECTATION_BUG` | original authority and receipt hash |
| provisioning.email_canonicalization | `NORMALIZED_ALIAS_DOCUMENTED` | `GENERATOR_EXPECTATION_BUG` | `5cecaa7…` and receipt hash |
| fixture_counts.progress | `1` | `GENERATOR_EXPECTATION_BUG` | authenticated completion and receipt hash |
| settlement attempt counters | both `0` | `GENERATOR_EXPECTATION_BUG` | resume state machine and receipt hash |
| Supabase HTTP request counts | patient `1`, service `7` | `GENERATOR_EXPECTATION_BUG` | contemporaneous launcher and receipt hash |
| cross-document relations | marker/ref/environment/times exact | canonical | claim, recovery and provisioning receipts |
| deployment purpose/node | dedicated BFF / `22.x` | canonical prior fix | Preview authority and deployment receipt |
| env receipt seven literals | canonical prior fix | canonical prior fix | c517 authority and env receipt |

Não existe field não resolvido, artifact drift ou security-gate failure. Os
cinco inputs e os dois artifacts auxiliares permaneceram root-owned, `0600`,
regular, single-link, sob parent `0700`, com hashes exatos e zero escrita.

## Read-only five-input preflight

O mode fechado `--preflight-inputs` lê exatamente ENV_SOURCE, env receipt,
deployment receipt, credential e provisioning receipt pelos mesmos readers e
chama a mesma `validateSourceDocuments` usada por `--create`. Ele não cria
claim, staging, final, config, bundle ou receipt; não usa rede/SSH; não abre
primary/live; não aceita quarto mode.

```text
ENV_SOURCE_PHYSICAL=PASS
ENV_RECEIPT_PHYSICAL=PASS
DEPLOYMENT_RECEIPT_PHYSICAL=PASS
CREDENTIAL_PHYSICAL=PASS
PROVISIONING_RECEIPT_PHYSICAL=PASS
ENV_RECEIPT_SEMANTIC_PREFLIGHT=PASS
DEPLOYMENT_RECEIPT_SEMANTIC_PREFLIGHT=PASS
CREDENTIAL_SEMANTIC_PREFLIGHT=PASS
PROVISIONING_RECEIPT_SEMANTIC_PREFLIGHT=PASS
CROSS_DOCUMENT_RELATIONS_PREFLIGHT=PASS
ALL_FIVE_INPUTS_SEMANTIC_PREFLIGHT=PASS
PREFLIGHT_WRITES=0
PREFLIGHT_CLAIMS_CREATED=0
PREFLIGHT_OUTPUTS_CREATED=0
PREFLIGHT_NETWORK_CALLS=0
RAW_MARKER_REPORTED=NO
RAW_EMAIL_REPORTED=NO
RAW_PASSWORD_REPORTED=NO
```

O digest sanitizado do marker da operação também fica ligado ao receipt remoto;
o marker bruto permanece ausente de config, receipt, logs e erros.

## Verificação e revisões pré-authority

O ciclo TDD final fechou em 102/102 casos adicionais de input-contract. A suíte
integral do generator passou 426/426, a reconciliação do deployment receipt
62/62, o Git reader bounded 48/48 incluindo o blob de 82.675 bytes, o
controller 708/708, o launcher source 22/22 e o writer source 4/4. O preflight
real dos cinco inputs passou todos os gates físicos e semânticos com zero
write, claim, output, receipt, rede, SSH, retry ou abertura de primary/live.

Review A cobriu schema de credential/provisioning, gramática do marker por
operação, coerência de datas/deadline, shapes de request/response evidence,
leituras no-follow, exclusão de secrets e sanitização do receipt. Resultado:
`0 Critical / 0 Important / 0 Minor`.

Review B cobriu manifest exato de 16 paths, bindings de parent/subject, Git
reader bounded, compatibilidade dos protocols controller/launcher/writer,
budgets V1/V2/c517, preservação do capsule, zsh deferred, invariância do
manager/inputs e zero efeitos externos. Resultado:
`0 Critical / 0 Important / 1 Minor`. O Minor registra que um wrapper de scan
read-only resolveu acidentalmente o Node padrão NVM e encerrou em `ENOENT` por
um path de deployment receipt incorreto. Não houve output de valor, mutation,
generator ou tentativa. O scan foi repetido integralmente pelo capsule adotado
com o path canônico e terminou com zero sensitive raw matches.

## Terminal PASS — canonical five-input bundle

```text
AUTHORITY_SHA=7a929b0cebb28c339010dd5bf115e67b79523156
AUTHORITY_PARENT=70a7d60dd9c4224e3be9072ce5fbd966bd534560
AUTHORITY_TREE=902a89cab73ebe5ea78b246a9961aa20a6eaaf96
AUTHORITY_REMOTE_READBACK=PASS
INPUT_CONTRACT_AUTHORITY_ATTEMPTS=1/1
INPUT_CONTRACT_AUTHORITY_RETRY=NO
BRIDGE_CLAIM_BEFORE_EFFECT=YES
BRIDGE_REMOTE_GENERATION_ID=rb-b1ec265eb71070f50932a4d7af8af5fed4ba4937c8858319d3550b76a04880ad
BRIDGE_REMOTE_RECEIPT_PATH_HASH=e76eac812e1aff61a19f9e3797f3a4b90da56eddadaba2e0b43c71c69d21c8a2
BRIDGE_REMOTE_RECEIPT_SHA256=349842c03aaaa039ddaf0da9e14ccb6b7793618cb346ab301de7f45fa146c10d
BRIDGE_REMOTE_CONFIG_PATH_HASH=ee92379f73ed156ebbbb5141ea4b8efe83de6aba40925e2643c97e789a868ba8
BRIDGE_REMOTE_CONFIG_SHA256=5132de192dba24912d65aa61228606864e3e86a56c04593cf63126c66554ee2a
SYNTHETIC_CREDENTIAL_PATH_HASH=3ece3ed674cd3ffd605565f05170297b549fa50fcf9c9ad1a8ea1bfe1702a677
SYNTHETIC_CREDENTIAL_SHA256=d36c96998b5879150d5dbd45a8118de0e50b24a815f5ff5cbeb0d87d449d8208
SYNTHETIC_MARKER_SHA256=9f768034584af72f213b9d89816d4f1d506141a37375477369a4817180e4bdd3
SERVICE_ROLE_OUTPUT=NO
CREDENTIAL_COPY=NO
RAW_MARKER_REPORTED=NO
RAW_EMAIL_REPORTED=NO
RAW_PASSWORD_REPORTED=NO
RAW_VALUES_REPORTED=NO
```

O snapshot exato tinha blob `9bfb6006847ab63471021755c19f44ab8cf556db`,
SHA-256 `d1d7958db00daebcaa823fdfdc3aced873e7167c8cd56931f6f5d56ddd27ec4f`,
110.710 bytes, root:root 0600 e nlink 1. Os gates pós-authority repetiram
generator 426/426, controller 708/708, launcher 22/22, writer 4/4, self-test
8/8 e preflight físico/semântico completo antes da única invocação. O readback
final confirmou claim 1, dois outputs, publication receipt last e zero raw
marker/e-mail/password/service-role.

As reviews documentais terminais A e B terminaram cada uma com
`0 Critical / 0 Important`. Nenhum input, capsule ou predecessor foi alterado;
não houve zsh, SSH, simulador, provider/database/production write, CI-3 Task 2,
CI-4 ou cleanup. Próximo gate: `FETCH_VERSIONED_CI3_BRIDGE_BUNDLE_AND_RESUME_CI3`
no Mac local, começando pelo Gate 0 `/bin/zsh -n` exato pre-network.

## Read-only compatibility with the Mac executor successor

Este deployment receipt continua evidência imutável da authority remota
`7a929b0cebb28c339010dd5bf115e67b79523156`; ele não é reatribuído ao executor
Mac. O executor sucessor usa parent `65a06d3e7426117ea80679933f6a7bb611be5988`,
subject `build(ops): authorize mac-compatible CI-3 bridge executor` e manifest
exato de 17 paths. Controller e writer validam explicitamente as duas
attestations sem exigir que tree/manifest/component hashes remotos sejam os do
executor local.

Generator creation, config/receipt schemas, generation/path derivation, cinco
inputs e claim/publication semantics permanecem iguais; portanto
`REMOTE_BUNDLE_COMPATIBILITY=REUSE_READ_ONLY`. O Gate 0 desse receipt não é
reutilizável para o novo launcher: após publicação futura será obrigatório um
novo `/bin/zsh -n`, ainda antes de qualquer network operacional.
