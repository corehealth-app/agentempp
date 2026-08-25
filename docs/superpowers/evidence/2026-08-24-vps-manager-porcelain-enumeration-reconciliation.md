# VPS Manager Porcelain Enumeration Reconciliation

**Classificação das fontes:**

- `USER-SUPPLIED MAC/VPS READ-ONLY AUDIT`;
- `VPS READ-ONLY REVALIDATION`.

Esta evidência registra uma reconciliação de enumeração Git. Ela não autoriza
PAT, acesso ao Supabase ou Vercel, secret store, testes, build, deploy, CI-3,
CI-4 ou produção.

## Identidade

| Campo | Valor |
| --- | --- |
| Path / Git root | `/root/agentempp` |
| Branch | `codex/better-ahead-rebranding-design` |
| HEAD | `d497b89361636fa282d3c97e5b80f4c0a65bdaef` |
| Parent | `726628b4e690fd585ca32d0ef51ae7c34c2565e2` |
| Tree | `0035062074b271f0d00c94e6700b9a02f0d47304` |
| Subject | `docs(ios): record CI-1 and authorize CI-2` |
| Staging | vazio |
| Timestamp da revalidação | `2026-08-25T13:51:02Z` |
| Hostname | `srv1302975` |
| Usuário | `root` |

O remote da branch documental foi observado no mesmo HEAD antes da edição. A
worktree de deploy `/root/agentempp-ci3-staging-bff-v1` foi revalidada
read-only, detached em
`277873755bf29771a10b5f362b522c2e6a6c21d6`, com staging e porcelain vazios.

## Baseline histórica canônica

O comando canônico é:

```text
LC_ALL=C git status --porcelain=v1 -uall
```

Resultados reproduzidos nesta VPS:

| Medida | Resultado |
| --- | --- |
| Entradas | 25 |
| Tracked | 5 |
| Untracked | 20 |
| Porcelain SHA-256 | `455000fe5f148dcad3034f03d57e2683deedb8ae5ec655b8a459639117f040e0` |
| Tracked status stream SHA-256 | `429841c416296c3f41cd3ea75ff4cbad7528a13d9e28bf21b3be9bc04f248c8a` |
| Untracked status stream SHA-256 | `913259345be829c189b40e68932ba1b726369edf8ca80ef4c0deb05574bd9d66` |
| Tracked binary diff SHA-256 | `7262d613d02df890c8e0c02922fa778afb90a6b7c27aa25a417bf0c717bdbefb` |
| Staged diff SHA-256 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

Os cinco tracked históricos foram verificados por hashes físicos, sem imprimir
seu conteúdo. Seus status permaneceram modificados e nenhum deles foi staged.
Os 20 untracked históricos foram enumerados individualmente pelo modo `-uall`.

## Visão compacta

O comando observacional é:

```text
LC_ALL=C git status --porcelain=v1
```

Resultados reproduzidos:

| Medida | Resultado |
| --- | --- |
| Entradas | 22 |
| Tracked | 5 |
| Untracked compactas | 17 |
| Porcelain SHA-256 | `256e29e64780b2100e569f222d810a49addbe6099254637519c30615c99bd26c` |

Essa visão não é uma baseline substituta e não pode ser comparada como se
usasse a mesma semântica de enumeração do modo `-uall`.

## Explicação da diferença 22 → 25

No modo compacto, estas quatro entradas representam diretórios:

- `docs/architecture/`;
- `docs/audits/`;
- `docs/business/`;
- `memory/`.

Com `-uall`, elas se expandem exatamente para estes sete arquivos:

- `docs/architecture/BodyFlow-Arquitetura-Legada-WhatsApp.pdf`;
- `docs/architecture/arquitetura-legada-whatsapp.html`;
- `docs/audits/2026-07-02-full-platform-audit.md`;
- `docs/business/2026-07-16-relatorio-precificacao-economia-unitaria-app-nativo.md`;
- `docs/business/2026-07-16-relatorio-precificacao-economia-unitaria-app-nativo.pdf`;
- `memory/2026-07-01-roberto-bloco-duplicidade.md`;
- `memory/2026-07-02-duplicidade-goiaba.md`.

Quatro entradas compactas tornam-se sete entradas expandidas: diferença
líquida de três. Todos os sete paths existem como arquivos regulares e nenhum
deles está ignored. A auditoria fornecida e a revalidação confirmam:

- nenhum arquivo desapareceu;
- nenhum byte mudou;
- nenhum path foi movido, removido ou commitado;
- nenhum path passou a ser ignored;
- nenhum drift material ocorreu;
- o hash histórico canônico continua válido e não é substituído;
- a visão compacta permanece apenas observacional.

## Regra futura

Todo gate de preservação da VPS deve:

1. usar explicitamente `LC_ALL=C git status --porcelain=v1 -uall`;
2. registrar o comando exato;
3. registrar as contagens total, tracked e untracked;
4. registrar o SHA-256 do stream integral;
5. comparar contagens e hashes somente quando o modo de enumeração for
   idêntico;
6. tratar a visão compacta apenas como observação;
7. executar STOP quando o mesmo comando canônico `-uall` divergir.

## Classificação final

```text
VPS_MANAGER_DRIFT_STATUS=RECONCILED_NON_MATERIAL
CANONICAL_BASELINE_CHANGED=NO
CANONICAL_ENUMERATION_MODE=PORCELAIN_V1_UALL
FILES_MISSING=0
BYTES_CHANGED=0
```
