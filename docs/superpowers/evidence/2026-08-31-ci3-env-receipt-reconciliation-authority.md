# CI-3 — authority de reconciliação do receipt de staging

**Data:** 2026-08-31
**Operação:** `AUTHORIZE_ENV_RECEIPT_RECONCILIATION_AND_FRESH_BRIDGE_ATTEMPT`
**Arquitetura:** `VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING_WITH_CANONICAL_ENV_RECEIPT_V1`

## Estado preservado e root cause

Bridge V1 e Bridge V2 permanecem históricas, ambas com tentativa `1/1`
consumida e sem retry. A V2 terminou `ENV_RECEIPT_STATE` antes de claim,
staging, generation, config ou receipt. O Node capsule V2 adotado, o reader
Git bounded de 1 MiB e os cinco inputs root-only permanecem byte-idênticos.

O receipt físico foi lido por descriptor no-follow e seu hash corresponde à
primeira authority documental que o registrou. A authority original de
control-plane definiu o schema sanitizado e publicou
`STAGING_SECRET_SOURCE_STATUS=VERIFIED`. A história posterior não
reclassificou o receipt. A divergência nasceu exclusivamente no generator V2,
que esperava sete aliases incompatíveis.

## Contrato canônico

O purpose é `ci3-staging-mobile-bff`; o marcador legacy-key é booleano true;
a exposição elevated local é `no`; e a permissão verificada é
`api_gateway_keys_read`. As três classificações, respectivamente para URL,
anon key e service-role, são `public-configuration`,
`legacy-public-project-key` e `legacy-server-sensitive-elevated`.

Cada entrada continua única, validada e ligada por SHA-256 ao ENV_SOURCE.
Todos os gates de schema, staging/parent ref, preview, control-plane, ausência
de criação/rotação/desativação, produção, database write, argv/Git/printing e
primary/live permanecem fail-closed. O receipt e o ENV_SOURCE nunca são
reescritos; nenhum valor bruto é incluído em log, receipt ou bundle.

## Authority sucessora

A authority sucessora é filha do STOP V2 publicado, usa exatamente 15 paths e
mantém V1, V2 e seu STOP somente como lineage. Ela conserva o reader bounded,
zero retry, o controller/writer protocol e o launcher estruturalmente idêntico.
Na VPS, zsh continua `NOT_APPLICABLE`; `/bin/zsh -n` permanece Gate 0 do Mac,
obrigatório sobre o blob exato antes de rede, simulador, claim, SSH ou remote
read.

Uma tentativa nova e independente da bridge pode ser consumida somente após
testes completos, scans, duas reviews com zero Critical/Important, commit e
readback remoto exatos. A credential não é copiada, service-role não é
emitida, e CI-3 Task 2, CI-4, produção e cleanup permanecem fora do escopo.

## Gates pré-publicação

O RED específico executou sete contratos e falhou sete vezes nos literals
V2 esperados. O GREEN final passou 47 casos comportamentais de receipt, além
dos sete contratos literais. A suíte completa do generator passou `260/260`,
incluindo reader `48/48`; self-test `8/8`, network zero. Controller passou
`704/704`, incluindo E2E completo `60/60`; launcher source/structural passou
`22/22`; writer source-contract passou `4/4`. Todos tiveram zero
fail/skip/todo e zero privilege prompt.

Os scans confirmaram exatamente 15 paths, staging vazio, `git diff --check`,
package/lockfile inalterados, ausência de material sensível e ausência de
mutação do receipt/runtime. Review A (receipt/provenance/generator) e Review B
(continuidade executável/preservação) concluíram GO com
`0 Critical / 0 Important` cada.

## Resultado terminal pós-authority

A authority foi publicada e confirmada. O snapshot materializado do blob Git
passou self-test `8/8`, e o reader bounded leu os 15 blobs. Capsule e adoption
receipt permaneceram exatos. O env receipt físico passou o contrato canônico.

O preflight do deployment receipt então retornou
`DEPLOYMENT_RECEIPT_STATE`. Diagnóstico read-only e sanitizado localizou duas
divergências de expectativa: os campos `purpose` e `node`; todos os demais
gates daquele receipt passaram. O comando `--create` não foi invocado, logo a
tentativa sucessora permanece `0/1`, sem claim ou output. O próximo gate é
`RECONCILE_DEPLOYMENT_RECEIPT_CONTRACT_AND_FRESH_BRIDGE_ATTEMPT`.

## Successor deployment contract

O env receipt continua canônico e imutável. A operação sucessora corrige apenas
as duas expectativas que divergiram no preflight: purpose físico
`ci3-dedicated-mobile-bff-deployment` e Node Vercel físico `22.x`. Os outros
gates do deployment receipt, os sete valores canônicos do env receipt, hashes,
project refs e relações entre os cinco inputs permanecem fail-closed.

`c5172be7752f79c1acbf0e68d0d75a6bd880948a` é classificada definitivamente
como `0/1_NOT_EXECUTED_SUPERSEDED`. Seu snapshot pode permanecer para auditoria,
mas a authority root, claim, staging, generation, config e receipt continuam
ausentes e ela não pode ser executada.
