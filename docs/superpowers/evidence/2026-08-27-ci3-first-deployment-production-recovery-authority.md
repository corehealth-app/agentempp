# CI-3 — authority de recuperação do primeiro deployment Production da Vercel

**Data:** 2026-08-27
**Operação:** `RECONCILE_UNEXPECTED_VERCEL_PRODUCTION_TARGET_AND_AUTHORIZE_RECOVERY`
**Dossiê:** `1.6.17`
**Base documental:** `047130f334950ec50de56ac11025cdf9a78b4b96`
**Source dedicado:** `e3e1e252b48e42554e75899b950692c05186f60d`

## Objetivo e limite

Esta authority permite recuperar o projeto staging da classificação Production
automática de seu primeiro deployment da CLI. Ela autoriza, em ordem:

1. exatamente um segundo deployment com `--target=preview`;
2. verificação remota `preview` + `READY` + source SHA exato;
3. exatamente uma remoção do ID do primeiro deployment Production;
4. settlement remoto e inspeção completa do Preview preservado;
5. um SSO forward e, somente nas condições fail-closed abaixo, um rollback;
6. probes públicos e descoberta read-only de paciente sintético;
7. exatamente um outcome documental.

Não autoriza terceiro deployment, segundo delete, remoção de Preview/projeto/
env/domínio, alteração de settings/env/Git Integration, uso de primary/live,
Supabase/database write, produção do produto, CI-4, PR, merge, tag ou force.

## Reconciliação do comportamento

As fontes atuais produzem dois contratos que coexistem:

- `vercel deploy` é a forma geral documentada de criar Preview;
- o primeiro deployment de um projeto novo criado/vinculado pela CLI inicializa
  Production, e os deployments seguintes voltam a Preview.

O cliente instalado 50.35.0 converte `target="preview"` em target omitido antes
do POST. Logo, o argumento futuro documenta intenção, mas somente a resposta e
os readbacks oficiais provam o target remoto.

```text
VERCEL_FIRST_DEPLOYMENT_CLASSIFICATION=FIRST_CLI_DEPLOYMENT_BOOTSTRAP_PRODUCTION
DOCUMENTATION_CONFLICT=GENERAL_PREVIEW_DEFAULT_VS_FIRST_DEPLOYMENT_BOOTSTRAP
RECOVERY_ORDER=CREATE_AND_VERIFY_PREVIEW_THEN_DELETE_BOOTSTRAP_PRODUCTION
```

Referências:

- https://vercel.com/docs/projects/deploy-from-cli
- https://vercel.com/docs/cli/deploy
- https://vercel.com/blog/default-production-domain
- https://github.com/vercel-labs/full-stack-service-previews
- https://github.com/vercel/vercel/issues/17069

## Estado material congelado

O preflight anterior tinha deployments zero. O comando único não usou
`--prod`, promoção, alias, domínio, redeploy ou Git connection. O estado atual
foi novamente lido pelas interfaces oficiais:

```text
VERCEL_CLI_VERSION=50.35.0
VERCEL_PROJECT_ROOT=apps/mobile-bff
VERCEL_PROJECT_FRAMEWORK=nextjs
VERCEL_PROJECT_NODE=22.x
VERCEL_ENV_PREVIEW_PRODUCTION_DEVELOPMENT=3/0/0
VERCEL_DEPLOYMENT_TOTAL=1
VERCEL_DEPLOYMENT_TARGET=production
VERCEL_DEPLOYMENT_READY=YES
VERCEL_DEPLOYMENT_SOURCE_SHA=e3e1e252b48e42554e75899b950692c05186f60d
VERCEL_GENERATED_ALIAS_COUNT=2
VERCEL_CUSTOM_DOMAIN_COUNT=0
VERCEL_CUSTOM_ENVIRONMENT_COUNT=0
VERCEL_PROJECT_GIT_LINK=ABSENT
VERCEL_PROJECT_SSO=all_except_custom_domains
PRIMARY_LIVE_PRODUCT_PRODUCTION_TOUCHED=NO
CI4=NOT_STARTED
```

O receipt no-clobber do incidente é root:root 0600, regular, nlink1, fora do
Git e tem SHA-256
`dae421f7a86897ca16cc09d4a52590bf451a0017695ffc6c7aad8879d6065813`.
IDs, URLs e aliases brutos existem exclusivamente nele. Nenhum valor ou token
foi relatado.

## Reviews pré-authority

- Review A — target/deployment: GO, `0 Critical / 0 Important / 0 Minor`,
  SHA-256 `883442248fa7df9776c5827485bcb278116c4829ee63faa9ffdbe4f18d89fd75`.
- Review B — delete/aliases/SSO após hardening: GO,
  `0 Critical / 0 Important / 0 Minor`, SHA-256
  `03c7e22d6736a5c66b3c50f990d5ea6af2f7b2b1e63b33438e569288592b9018`.

## Budgets

```text
RECOVERY_AUTHORITY_COMMIT_ATTEMPTS=1
RECOVERY_AUTHORITY_PUSH_ATTEMPTS=1
RECOVERY_PREVIEW_DEPLOYMENT_ATTEMPTS=1
BOOTSTRAP_PRODUCTION_DELETE_ATTEMPTS=1
SSO_FORWARD_ATTEMPTS=1
SSO_ROLLBACK_ATTEMPTS=1
FINAL_DOCUMENTATION_COMMIT_ATTEMPTS=1
FINAL_DOCUMENTATION_PUSH_ATTEMPTS=1
```

Os budgets operacionais só existem após esta authority estar publicada e
confirmada no remote. Falha de commit/push é `STOP_PRE_AUTHORITY` e não permite
deployment ou delete.

## Protocolo do Preview

Após preflight exato, executar uma única vez na dedicated deploy worktree:

```text
vercel deploy --yes --target=preview \
  --meta githubCommitSha=e3e1e252b48e42554e75899b950692c05186f60d \
  --meta recovery=first-deployment-bootstrap-production
```

Stdout/stderr ficam root-only. O sucesso exige target remoto `preview`, estado
`READY`, source SHA exato, root `apps/mobile-bff`, Node `22.x`, framework
`nextjs` e Git Integration ausente. Um target `production` ou qualquer falha
termina em STOP, mantém SSO, preserva todos os deployments, proíbe retry e usa
`NEXT_GATE=ESCALATE_VERCEL_FIRST_DEPLOYMENT_TARGET_BEHAVIOR` quando aplicável.

O Preview aprovado recebe receipt root-only no-clobber. Enquanto SSO está
ativo, Today precisa retornar o envelope Mobile 401/no-store/Vary Authorization
com request ID, enquanto `/` e `/api/admin/send-message` precisam retornar 404.
Falha dessa inspeção não autoriza forward, mas não bloqueia remover o original
se target/READY/source do Preview continuarem exatos.

## Remoção do bootstrap Production

Antes da remoção, original e Preview devem estar ancorados pelos receipts,
ser distintos, manter targets/source exatos, SSO ativo, custom domains zero e
budget `0/1`. O help do cliente instalado aceita deployment ID; portanto o
único operando autorizado é o ID bruto original lido do receipt. URL, project
name e wildcard são proibidos.

Depois da única invocação `vercel remove <ORIGINAL_DEPLOYMENT_ID> --yes`, GETs
em +10/+20/+40 devem provar:

- original ausente e sem alias ligado;
- Production target count `0`;
- Preview target count `1` e total ativo `1`;
- Preview exato `READY` no source SHA exato;
- custom aliases/domains `0`;
- Project link ausente;
- env `3/0/0`;
- SSO original ativo.

Exit nonzero pode ser `DELETE_COMMAND_AMBIGUOUS_REMOTE_VERIFIED` somente com
esse estado remoto exato. Original ou alias persistente termina em STOP, sem
segunda remoção e com
`NEXT_GATE=RECONCILE_REMAINING_PRODUCTION_ALIAS_OR_DEPLOYMENT`.

## Review C e máquina SSO fail-closed

Com Production count zero, a inspeção completa deve provar 40 Mobile API
routes, zero admin routes/pages/Server Actions/middleware, target Preview,
READY/source, env `3/0/0`, manifests e logs sanitizados. Review C precisa
retornar `0 Critical / 0 Important`; caso contrário SSO permanece ativo.

Imediatamente antes do único forward, Project GET deve provar igualdade
estrutural do objeto remoto com o descritor original. Hash do arquivo original:
`c671d990e24fc57160578375e4ff8cd37bc51c3e8e6d159104691785b4836064`;
hash canônico do objeto original/remoto:
`cef42fb8d4536a4c4fdcafbba6da011139a4e35d785563248912efd384dbc591`.
Qualquer divergência é STOP antes de PATCH.

O forward `{"ssoProtection":null}` pode ocorrer uma vez. Project GET
+10/+20/+40 precisa ser estável com SSO null, link ausente, env `3/0/0`,
Production zero e Preview único/READY. Se PATCH/readback falhar ou ficar
ambíguo:

1. SSO ainda exatamente original: STOP sem rollback;
2. SSO exatamente null: consumir a única tentativa de rollback e exigir três
   readbacks estáveis do original;
3. SSO indeterminável: STOP com `SSO_STATE=UNRESOLVED`, sem nova mutação e com
   escalonamento operacional.

O único rollback é compartilhado com falha dos probes públicos; nunca existe
segundo forward ou segundo rollback. Estado team default não é lido nem
alterado.

## Probes, paciente e outcomes

Após forward estável, os probes usam somente a URL única do Preview. As três
rotas Mobile exigem 401 JSON/no-store/Vary Authorization/request ID; rotas
forbidden e os 19 paths congelados exigem 404, sem redirect, HTML de login,
stack, secret ou PII. Falha consome no máximo o rollback compartilhado e não é
reprovada.

Paciente sintético é somente discovery read-only. Não se cria usuário,
profile, senha ou credential. O resultado é `VERIFIED` ou `MISSING`; Today
autenticado é `PASS` ou `DEFERRED_TO_MAC_BY_DESIGN` quando comprovadamente
Mac-only.

Outcomes com parent exclusivo `PRODUCTION_RECOVERY_AUTHORITY_SHA`. Estes três
contratos substituem integralmente todas as allowlists, versões, subjects e
paths finais históricos desta continuação:

- `PASS_COMPLETE`: somente
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-authority.md`,
  `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`,
  `docs/superpowers/specs/2026-08-27-ci3-today-staging-vertical-slice.md` e
  `docs/superpowers/plans/2026-08-27-ci3-today-staging-vertical-slice.md`;
  `1.6.17→1.7`; subject
  `docs(ios): authorize CI-3 after dedicated Mobile BFF verification`.
- `PASS_PARTIAL`: somente
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-dedicated-mobile-bff-preview-verification.md`
  e `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`;
  `1.6.17→1.6.18`; subject
  `docs(staging): record verified dedicated Mobile BFF preview`; próximo gate
  `AUTHORIZE_SYNTHETIC_STAGING_PATIENT_PROVISIONING`.
- `STOP_DOCUMENTED`: somente
  `docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md`,
  `docs/superpowers/evidence/2026-08-27-ci3-production-target-recovery-stop.md`
  e `docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md`;
  `1.6.17→1.6.18`; subject
  `docs(staging): record Production target recovery stop`; próximo gate
  material exato.

Qualquer commit final exige allowlist exata, staging seletivo, diff-check,
scan de token/secret/raw origin/raw ID/PII, duas reviews a zero Critical/
Important, um commit e um push fast-forward, sem histórico staged, force, tag,
PR ou merge.
