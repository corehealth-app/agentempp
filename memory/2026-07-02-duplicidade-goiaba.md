# Debug Report — Duplicidade de contexto e goiaba

Data: 2026-07-02

## Symptom

- Roberto viu o agente contar `20 min de bicicleta` duas vezes quando enviou duas mensagens em burst: `20 min de bicicleta` e `E 35 min de musculação`.
- Paulo teve `goiaba` registrada como ~383 kcal para 150g, mesmo depois de corrigir para 95 kcal no card de confirmação.

## Root Cause

- O `buffer-listener` agregava varias mensagens em um unico `input.text`, mas enviava para `message.received` apenas o `providerMessageId` da ultima mensagem. O pipeline filtrava do historico apenas esse ID, deixando mensagens anteriores do mesmo burst aparecerem tanto no historico quanto no input atual.
- A `food_db` nao tinha `goiaba` fruta; `search_food_trgm('goiaba')` casava `goiabada` (`doces`, 255 kcal/100g), gerando ~383 kcal para 150g.
- Mesmo quando o pending tinha 95 kcal aprovado, o tap handler passava `kcal`, mas `registra_refeicao` so respeitava `user_kcal`; a tool recalculava pela base errada.

## Fix

- `message.received` agora carrega `providerMessageIds` com todos os IDs do burst, mantendo `providerMessageId` como ID principal/ultimo.
- `buildPromptRecentMessages` filtra todos os IDs atuais e remove taps crus `confirm_*`/`edit_*` do historico natural da LLM.
- `parseUserKcalOverrides` ignora frases negadas como `goiaba nao tem 383 kcal`.
- `calcMealMacros` rejeita fruta fresca simples casando com doce derivado (`goiaba -> goiabada`) e ignora historico pessoal implausivel para fruta fresca simples.
- Pendings preservam `user_kcal`; o interactive handler repassa o campo e `registra_refeicao` usa esse valor.
- Nova migracao idempotente adiciona/atualiza `food_db.goiaba` com 95 kcal por 150g (63.33 kcal/100g).

## Evidence

- `pnpm --filter @mpp/agent test` passou: 42 files, 805 tests.
- `pnpm --filter @mpp/inngest-functions test` passou: 6 files, 26 tests.
- `pnpm typecheck` passou em todos os pacotes.

## Regression Tests

- `packages/agent/src/pipeline-context.test.ts`: burst multi-ID e taps interativos fora do historico.
- `packages/inngest-functions/src/functions/buffer-listener.test.ts`: preserva todos os provider IDs do burst.
- `packages/agent/src/meal-pipeline.test.ts`: goiaba nao casa com goiabada, goiabada continua valida, historico antigo implausivel nao vence match canonico, frase negada nao vira override.
- `packages/agent/src/tools-replace-logic.test.ts`: `user_kcal` aprovado no pending chega ate `registra_refeicao`.

## Status

DONE_WITH_CONCERNS: codigo e testes estao prontos. A migracao da goiaba foi criada, mas nao foi aplicada em producao porque o escopo pedido proibia deploy/backfill sem autorizacao explicita.
