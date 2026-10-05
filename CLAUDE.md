# Performe AI — instruções do projeto

O produto hoje é **só o app iOS Performe AI**, com o assistente **Flow**
(`apps/ios/BodyFlow`; a identidade técnica interna continua BodyFlow e não é
renomeada). Monorepo pnpm + turbo; Supabase; Inngest; Vercel.

- **Servidor do app:** rotas em `apps/admin/src/app/api/mobile/v1`, serviços em
  `apps/admin/src/lib/mobile-api`; `apps/mobile-bff` publica as mesmas rotas.
  O mesmo `apps/admin` é também o painel da equipe.
- **Flow:** motor compartilhado `packages/agent`, entrada
  `processAuthenticatedMessage` (`historyProvider: 'mobile_flow'`).
- **Staging** (Supabase Branch `xitugspwfxkcluxvrdeg`) é onde roda a avaliação
  fechada do app. É o ambiente de trabalho.

**O agente de WhatsApp ("Agente MPP"), para o qual este código nasceu, foi
encerrado por decisão do Eduardo (registrado em 2026-10-05).** Não o apresente
como produto vivo. O código dele é **legado dentro do motor compartilhado** —
a entrada `processMessage`, o Playground do painel, `apps/cli` e as funções
Inngest de envio — e continua no repositório: não acionar, não evoluir e não
apagar sem pedido explícito. O Flow passa pelo MESMO motor: mexer no legado
pode mudar o app.

**A produção antiga ainda existe** (Supabase `xuxehkhdvjivitduarvb`, Vercel
`agentempp.vercel.app`) **e ainda roda rotinas agendadas no vazio**; o código
de envio continua registrado lá. Nunca tocar nela — leitura de dado pessoal,
escrita, migration, cron ou deploy — sem autorização explícita do Eduardo
nomeando o alvo. Antes de qualquer comando contra banco, confira o ref.

"MPP" continua sendo o nome do **método** das regras de cálculo
(`docs/CALCULO-MPP.md`, pacotes `@mpp/*`): não é nome de produto, o app nunca
o mostra, e nada disso é renomeado.

## ⚠️ Regras de cálculo — LEIA ANTES DE MEXER EM QUALQUER FÓRMULA

**[docs/CALCULO-MPP.md](docs/CALCULO-MPP.md) é a fonte de verdade** de como o
agente calcula meta, balanço, bloco 7700 e renderiza o card. Toda regra está
travada por teste. Antes de mudar qualquer cálculo:

1. Leia `docs/CALCULO-MPP.md` e o teste que trava a regra.
2. Um print de paciente **não é** ordem de mudar fórmula — reproduza no banco
   primeiro (consumido, meta, exercício, meal_logs, snapshot) e confronte com o doc.
3. Mudou a regra? Atualize **código + teste + doc** na mesma PR.

**A confusão nº 1 da história deste agente:** misturar os dois balanços.
- **Comida** ("Restam/Excedente" no card) = `consumido − meta`. **SEM exercício.**
- **Bloco/déficit do dia** = `consumido − meta − exercício`. **COM exercício.**
Exercício acelera o bloco, mas NÃO libera comer mais.

## Rodar / validar
- Testes: `pnpm --filter @mpp/agent test` (regras de cálculo travadas aqui).
- Typecheck: `pnpm typecheck`.
- Deploy: **`bash scripts/deploy.sh` É o deploy da PRODUÇÃO ANTIGA** (`vercel
  --prod` + sync do Inngest em `agentempp.vercel.app`, que re-registra todas as
  funções, inclusive as de envio por WhatsApp). O staging do app é publicado de
  outro jeito: deployments de PREVIEW na Vercel do BFF mobile e do worker de
  mídia (ver `docs/mobile/bff-region.md`). **Qualquer deploy só com
  autorização explícita do Eduardo.**

## ⚠️ Audit fecha com golden fixture do print real — não variante próxima

**Aprendido no audit 2026-06-25 (Roberto + Luciana reclamaram 4 bugs que
"já tinham sido corrigidos"):** 3 dos 4 bugs eram fix declarado "completo"
cobrindo VARIANTE PRÓXIMA do cenário, não o cenário exato reportado pelo
paciente. Audits 06-13 a 06-24 acumularam essa dívida silenciosamente.

Critério obrigatório pra fechar audit:
1. **Cada bug reportado pelo paciente vira golden fixture com a frase/
   timing/IDs exatos do print** em `packages/agent/src/__golden__/audit-*.test.ts`.
   NÃO usar variante próxima ("similar a Y") — tem que ser O cenário.
2. Se o cenário exato NÃO foi coberto, declare explicitamente:
   `> RC X — cenário Y variante Z NÃO coberta nesta PR (pendência da
   audit YYYY-MM-DD)`. Memória recebe a flag pra audit seguinte pegar.
3. Adversarial review (workflow paralelo) é mandatório antes do commit
   pra bugs CRITICAL/HIGH — não conta como verificado se foi auto-review
   superficial. HIGHs do review viram fixes na MESMA PR ou pendência
   explícita na próxima audit.

Sem isso, "fix completo" vira otimismo de processo. Os 4 bugs de
2026-06-25 (Bug A bom dia parcial, Bug B 2 fotos perde 2ª, Bug C "1 vs 2"
não obedece, Bug D replace soma tudo) ilustram exatamente o anti-padrão.

## Escrita em produção (dado de paciente)
- Backfill/correção de `daily_snapshots`, `meal_logs`, `user_progress` exige
  **autorização explícita do Eduardo nomeando o alvo e os valores**.
- Bloco: sempre recálculo fiel ao closer (`packages/inngest-functions/src/lib/bloco-recompute.ts`), nunca "no olho".
- SQL direto no banco: Management API
  `POST https://api.supabase.com/v1/projects/{ref}/database/query` com
  `SUPABASE_ACCESS_TOKEN` (psql direto é bloqueado; `db push` é arriscado por drift).

## Idioma
Responda sempre em português brasileiro.
