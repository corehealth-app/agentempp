# Better Ahead — auditoria física da worktree de implementação

**Classificação:** `PHYSICALLY_INCOMPLETE_WORKTREE`

**Origem:** `USER-SUPPLIED MAC READ-ONLY AUDIT`

**Momento da auditoria:** 20/08/2026, 22:20:44–22:24:45, timezone `-03:00`
**Status desta evidência:** preservação e STOP; não é uma tentativa de recuperação.

## Escopo e limites

Esta evidência foi fornecida por uma auditoria exclusivamente read-only executada
no Mac. A VPS não reexecutou Xcode, simulador, XCUI, pnpm, Docker, renderer,
captura de environment ou qualquer teste do renderer. Os fatos abaixo devem ser
tratados como observações do Mac, não como medições da VPS.

Deliberadamente não foram executados:

- `git worktree prune`;
- repair, remove ou alteração da metadata `worktree1`;
- escrita no path antigo;
- recuperação/recriação do log RED;
- reconstrução por aproximação dos seis blobs dirty ausentes;
- staging das 1.420 deleções órfãs;
- renderer, Docker, pnpm, Xcode, simulador ou testes nativos;
- push, PR, merge, deploy, migração ou produção.

## Git manager preservado

| Campo | Valor |
| --- | --- |
| Path | `/Users/eduardohenrique/Developer/bodyflow` |
| Branch | `codex/bodyflow-ios-library-mascot-gamification-v1` |
| HEAD | `0ce7f20f22b0e66a6de0544d4a46345181f2fccb` |
| Parent | `a31449f7254d0697652866e192363c303dd9978e` |
| Staging | vazio |
| Entradas porcelain | 0 |
| SHA-256 porcelain | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| SHA-256 diff binário | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

## Repositório diagnóstico preservado

| Campo | Valor |
| --- | --- |
| Path | `/Users/eduardohenrique/Developer/bodyflow-brand-design-system-v1` |
| Branch | `codex/bodyflow-ios-brand-design-system-v1` |
| HEAD | `03df7894e4cdb37db08351aafb6dd20ad4cb4103` |
| Parent | `5f5e9a485847291acbae3ae7de23b27824d49343` |
| Paths tracked modificados | 9 |
| Untracked | 0 |
| Staging | vazio |
| SHA-256 porcelain | `4fc733aeb4f41ce17e7ed094920c0d5ab70da26b879d49c594a84f050e58550c` |
| SHA-256 diff binário | `90a36577ad148e5391c147e72c4566716fe97adf02e02ddc53b7be594681bde8` |

Os nove paths diagnósticos permaneceram byte e status-equivalentes durante a
auditoria. Eles são evidência; não podem ser apagados, staged ou usados como
baseline de uma nova renderização.

## Worktree de implementação fisicamente incompleta

| Campo | Valor |
| --- | --- |
| Path | `/private/tmp/better-ahead-ios.GQgTa0/worktree` |
| `.git` | ausente |
| Arquivos regulares | 0 |
| Diretórios | 5.270 |
| Symlinks | 2.057 |
| Paths tracked no índice preservado | 1.420 |
| Paths tracked presentes fisicamente | 0 |
| Paths tracked ausentes fisicamente | 1.420 |
| Entradas porcelain pela metadata órfã | 3.477 |
| SHA-256 porcelain | `f273f8482cb1b0e54aa0f43e526784c22fa3b7b2605c34a19e56cfaec236340f` |
| SHA-256 diff binário | `133e0eb2f6f4713a843f93c2845308d098b7a02bbf28506e83b736f2a2914bb7` |
| SHA-256 staged diff | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

Todos os symlinks remanescentes pertencem a árvores `node_modules`. Não há
`package.json`, `pnpm-lock.yaml`, root Git funcional, environment, bundle,
review PNG, lock, journal, transaction ou exports Better Ahead no path.

## Metadata órfã que deve permanecer intacta

| Campo | Valor |
| --- | --- |
| Metadata path | `/Users/eduardohenrique/Developer/bodyflow/.git/worktrees/worktree1` |
| Gitdir target esperado | `/private/tmp/better-ahead-ios.GQgTa0/worktree/.git` |
| Target existe | não |
| Branch registrada | `refs/heads/codex/better-ahead-ios-rebrand-v1` |
| HEAD registrado | `ad9869c0d6b11222263ea40c7b72e329092aeef5` |
| Parent registrado | `8f4020b0ae27d27c0de1b97d1682f507cd0be57c` |
| Tamanho do index | 184.050 bytes |
| SHA-256 do index | `2e4cef4ed2f2bfe7e7e4cb2825001401ff80ef1252227f07f13ae36fcd545dd0` |
| Staging registrado | vazio |

É proibido reparar, remover, podar, reanexar ou sobrescrever esta metadata
durante o naming hold. Ela descreve o estado perdido; não constitui uma área de
desenvolvimento utilizável.

## Sete paths dirty históricos

Os sete paths eram:

| Path | SHA-256 histórico | Recuperação comprovada |
| --- | --- | --- |
| `design/brand/better-ahead-brand-assets.json` | `5da5284c219f4b556110944c837c2dcbf0f406aa6327aec821cb72d6bf5cb11b` | não |
| `scripts/brand/better-ahead-brand-contract.mjs` | `c9438906d4073813e15faec31332174e557888e0460705ddc6ff7bd89a7a99f0` | não |
| `scripts/brand/better-ahead-brand-contract.test.mjs` | `61facfae43bc5be7b45c2c5d406ccc20f88ba75ee13d3ec97b1d4232ecd0bcf1` | sim, objeto Git |
| `scripts/brand/capture-better-ahead-environment.mjs` | `7bc9239e37ad8f219b92f59f5476cd6e58276ca2b095b81c27716edbed8d0435` | não |
| `scripts/brand/render-better-ahead-brand-assets.mjs` | `9a5cb0ea098c787bcc80ef0bea30eb28636178211fac07ebfb6c0f29c282220b` | não |
| `scripts/brand/render-better-ahead-brand-review.mjs` | `e3bac5f60c9892ef936cf87585ce74820f8fa24ac6879e5e17cc2211baf05e42` | não |
| `scripts/brand/run-better-ahead-brand-renderer.sh` | `686b89883bd21df8c95c7eb49244b93e81cea8d6094ddf689236ea10c9092dc0` | não |

O único blob comprovadamente existente no object database é:

| Campo | Valor |
| --- | --- |
| Blob | `4c6619113829b83494292164696ee9abbd315eaf` |
| Tipo | `blob` |
| Tamanho | 482.022 bytes |
| SHA-256 do conteúdo | `61facfae43bc5be7b45c2c5d406ccc20f88ba75ee13d3ec97b1d4232ecd0bcf1` |

Conhecer os seis hashes ausentes não recupera seus bytes. Não é permitido
fabricar conteúdo, inferir arquivos por hash, copiar aproximações ou alegar
recuperação.

## Evidência temporária ausente

Os seguintes paths `/tmp` não existem mais:

- `/tmp/better-ahead-native-v3-oracle-red-attempt2.log`;
- `/tmp/better-ahead-implementation-repo.txt`;
- `/tmp/better-ahead-task2-plist-baseline-root.txt`.

O log histórico conserva somente valor documental:

| Campo | Valor |
| --- | --- |
| Registros TAP | 43 |
| Pass | 10 |
| Fail | 33 |
| Skipped | 0 |
| SHA-256 histórico | `fb79890356f3c9541615736ab185ef61a58e7882f0f76dffe94095b8e289b58d` |

Ele não será recriado, rerodado ou usado como autorização para continuar Task 3.

## STOP final

A classificação `PHYSICALLY_INCOMPLETE_WORKTREE` é definitiva para a worktree
antiga até que uma autoridade futura trate recuperação de bytes com evidência
nova. A Task 3 não pode continuar nela. A próxima implementação iOS, caso
autorizada, deve começar em worktree nova, limpa e durável, fora de
`/private/tmp`, a partir de uma base que o Mac prove read-only.
