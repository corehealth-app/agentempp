# CI-3 Bridge V2 — STOP do reader, reconciliação zsh e authority

**Data:** 2026-08-31
**Status terminal:** `STOP_DOCUMENTED_ENV_RECEIPT_STATE`
**Arquitetura:** `VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING`

## Baseline preservada

- Bridge V1 authority: `ba8473799a19aec586b0fe706bb7d4084589c86c`.
- Budget V1: `1/1_CONSUMED_NO_RETRY`.
- Falha V1: `ERROR GIT_AUTHORITY` antes de claim, input secreto ou output.
- Root cause: reader síncrono limitado a 64 KiB para um blob real de 82.675
  bytes; ENOBUFS ocorreu antes do claim.
- Node runtime capsule V2: adotado, read-only e não modificado.
- Bridge V2 antes desta authority: claim/staging/final ausentes; budget 0/1.
- VPS zsh: ausente, esperado e não instalado.

## Correção do reader

`BOUNDED_GIT_OBJECT_READER_V2` aceita somente OID compatível com o object
format, consulta type e size, exige `blob` e tamanho <=1.048.576 bytes, abre o
body uma vez com shell desativado, timeout e stderr bounded, conta bytes e
calcula SHA-256 e Git object OID incrementalmente, exige tamanho/hash/OID
exatos e revalida Git,
repository identity, type e size sem reler o body. Retry é sempre false.

O RED reproduziu a fronteira real de 82.675 bytes. O GREEN específico possui
48 casos e a suíte completa do generator preserva toda a cobertura anterior,
acrescida dos contratos environment-correct.

## Ruling do launcher

O launcher é um artefato executável exclusivo do Mac. A VPS não executa zsh,
não instala zsh e não usa Bash como substituto. O predecessor validado no Mac
é o blob `ade9531832da39715a815f4c34831780ce5063e3`, SHA-256
`c4c33a522125bc08823d9bac4a8344cf674df3e5e375f7c7e4fd22a1bcdf0ac2`.

O launcher atual muda apenas lista de paths, parent e subject. Ambos produzem
o mesmo skeleton SHA-256:
`ad3ab9d577d413c611bf000f1a64ef351e7060f5eb068dfca11879c163dfc1a8`.
Testes negativos cobrem mutações de controle de fluxo, nome de função,
redirect, quote e call graph. LF, UTF-8, ausência de NUL, newline final,
shebang zsh e `set -euo pipefail` permanecem congelados.

Classificação autoritativa:

- `VPS_ZSH_SYNTAX_EXECUTION=NOT_APPLICABLE`;
- `LAUNCHER_ZSH_SYNTAX_GATE=DEFERRED_TO_MAC_EXACT_BLOB_PRE_NETWORK`;
- `LAUNCHER_TARGET_ENVIRONMENT=MAC_LOCAL`;
- `LAUNCHER_RUNTIME_PATH=/bin/zsh`;
- `BASH_SUBSTITUTION=FORBIDDEN`.

O receipt remoto carrega o target/runtime, status deferred, ambiente Mac,
required-before-network, os dois skeleton hashes e equality true. Não declara
PASS zsh na VPS.

## Gate obrigatório do Mac

Antes de simulador, bootstrap claim, SSH ou qualquer remote read, materializar
o launcher do blob exato, validar `/bin/zsh` e sua cadeia/identidade/assinatura,
executar exatamente `/bin/zsh -n`, exigir exit 0 e streams vazios, provar bytes
unchanged e criar `mac-zsh-syntax.receipt.json` owner-only/no-clobber. Falha
implica zero rede, zero claim, zero stream e STOP sem retry.

## Authority e escopo

Parent obrigatório: `92cccf3dca21a29d601d2f274a67ea2ba284914b`.
Subject obrigatório: `build(ops): authorize bounded Git blob reader for CI-3 bridge`.
Allowlist: exatamente os 14 paths documentados no plano, sem package/lockfile,
iOS, backend, migration, runtime builder/verifier ou capsule artifacts.

Após testes, scans e duas reviews com zero Critical/Important, a authority pode
ser publicada. Somente depois a Bridge V2 pode consumir 1/1 pelo Node capsule
adotado. O launcher não será executado na VPS. Em qualquer falha, preservar
claim/evidência e publicar STOP documental sem retry ou cleanup.

## Gates VPS-applicable e reviews pré-publicação

Execução final sequencial pelo Node capsule adotado:

- reader: 48/48 casos nomeados dentro do generator completo;
- generator: 206/206, zero fail/skip/todo;
- generator self-test: 8/8, network calls 0;
- controller: 689/689, zero fail/skip/todo, incluindo 44 casos protocol E2E;
- launcher source/structural: 22/22, zero fail/skip/todo;
- writer source-contract: 4/4, zero fail/skip/todo;
- `ZSH_SYNTAX_TEST_VPS=NOT_APPLICABLE_ENVIRONMENT_CORRECT`;
- Swift/Xcode/simulator/SSH remoto/privilege prompt: não executados.

Scans: `git diff --check` PASS; allowlist exatamente 14; package/lockfile
unchanged; nenhum private-key marker, JWT literal, secret assignment ou IP
literal adicionado; reader sem `execFileSync`, shell true, eval/source ou loop
de retry; zsh binário ausente; staging vazio.

Review A — Git reader/generator: root cause, type/size bounds, timeout/kill,
SHA-256 e Git object OID incrementais, single body read, zero retry, identity
pre/post, authority bindings e schema foram auditados. Não há reparo apenas de
sintoma e a criação do bundle independe do runtime zsh.
Resultado: `0 Critical / 0 Important`.

## Deployment receipt successor continuity

O reader `BOUNDED_GIT_OBJECT_READER_V2` permanece com limite explícito de
1 MiB, object type/size antes do body, streaming contado, stderr limitado,
timeout, tamanho exato, SHA-256 incremental, revalidação type/size e zero retry.
A authority sucessora apenas amplia o manifest fechado de 15 para 16 paths ao
adicionar a evidência do deployment receipt. O caso real de 82.675 bytes deve
continuar PASS antes da publicação.

Bridge V1 e Bridge V2 seguem consumidas em 1/1. A authority `c5172be7…` não
executou `--create`, não criou claim/output e fica superseded. Nenhuma dessas
linhagens pode ser usada como authority corrente ou ganhar claim retroativo.

## Reconciliação sucessora do receipt

O STOP V2 e seu budget `1/1` permanecem históricos. A authority sucessora
aceita exclusivamente o schema canônico comprovado do receipt físico, adiciona
a nova evidência ao manifest de 15 paths e concede um budget independente.
Reader bounded, limite de 1 MiB, zero retry, capsule adotado e gate zsh deferred
permanecem inalterados. O receipt físico não é reescrito.


## Execução terminal da Bridge V2

Authority publicada/confirmada:
`c8e1d00c8d43912e55c5ecae3b2e3d84ae232026`, parent `92cccf3d...`, tree
`d623ac1057ce33520e869d24acaf7f92a033e6a8`, subject exato e 14 paths.

O snapshot do generator foi materializado do blob exato, root-owned 0600 e
single-link. Self-test: 8/8 PASS, network 0. A única tentativa real 1/1 pelo
capsule adotado retornou `ERROR ENV_RECEIPT_STATE`. Diagnóstico read-only:
purpose, legacy-key marker, local elevated exposure, required permission e as
três variable classifications divergem do contrato congelado.

Estado físico pós-falha: authority root, claim, staging, generation, config e
receipt ausentes. Snapshot, capsule e inputs preservados; retry NO; cleanup NO.
Zsh continuou ausente/não executado. Nenhum valor, service-role, credential,
token, PII, origin, host ou IP foi emitido.

Review documental A confirmou que o STOP não reclassifica o reader GREEN nem
autoriza retry: `0 Critical / 0 Important`. Review documental B confirmou
preservação, gate Mac ainda deferred e bloqueio material correto antes do
handoff: `0 Critical / 0 Important`.

Próximo gate: `AUTHORIZE_ENV_RECEIPT_RECONCILIATION_AND_FRESH_BRIDGE_ATTEMPT`
na VPS. Não executar esse gate nesta operação.

Review B — launcher/controller/handoff: diff real do launcher limitado aos
três data bindings autorizados; testes de mutação fecham grammar/flow/redirect/
quote/function/call graph/comment; skeletons iguais; classificação VPS N/A;
gate Mac `/bin/zsh -n` exato antes de rede; controller e writer exigem todos
os fields e igualdade. Nenhuma segurança foi enfraquecida.
Resultado: `0 Critical / 0 Important`.

## Successor Mac repository identity policy

O reader root-owned VPS permanece default e inalterado. Somente quando uma
policy `CI3_MAC_REPOSITORY_IDENTITY_POLICY_V1` explícita é fornecida no Darwin,
o reader aceita o UID atual, após validar root físico canônico, SHA-256 do root,
attestation SHA-256, modos owner-only e grammar do `/usr/bin/git`; o sufixo
atestado ` (Apple Git-N)` é aceito sem relaxar versões arbitrárias. Policy
ausente continua fail-closed no contrato root-only.

O executor sucessor é separado do bundle remoto: manifest de executor com 17
paths e parent `65a06d3e7426117ea80679933f6a7bb611be5988`; receipt/config remotos continuam
presos ao predecessor `7a929b0cebb28c339010dd5bf115e67b79523156`.
`REMOTE_BUNDLE_COMPATIBILITY=REUSE_READ_ONLY`. Nenhuma leitura remota, rede,
SSH, simulator ou mutação da worktree CI-3 ocorreu nesta correção.
