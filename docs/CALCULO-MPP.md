# Regras de cálculo do Agente MPP — fonte de verdade

> Este documento é a **referência canônica** de COMO o agente calcula tudo.
> Toda regra aqui deve estar **travada por teste**. Se mudar uma regra, mude:
> (1) o código, (2) o teste que a trava, (3) este documento — na mesma PR.
> Nunca mude uma fórmula "no susto" por um print de paciente sem checar aqui.

Última revisão: 2026-05-21.

---

## 1. Meta calórica diária (`calories_target`)

- **Recomposição:** `meta = BMR × 1.2 − design_deficit`.
  - `design_deficit` (fome do paciente): leve 400 / médio 500 / alto 600.
  - O TDEE é **apenas informativo** na recomp — NÃO é a meta.
- Manutenção / ganho: conforme `calc_config` do protocolo.
- Código: `packages/agent/src/calc-targets.ts`, `calc-config-loader.ts`.

## 2. Balanço do dia — DOIS números distintos (NÃO confundir)

Esta é a regra que mais gerou bug. Existem **dois** balanços, com finalidades diferentes:

### 2a. Balanço de COMIDA (o que o paciente vê no card como "Restam/Excedente")
```
balanço_comida = consumido − meta
```
- **O EXERCÍCIO NÃO ENTRA AQUI.** (Regra Roberto 2026-05-21.)
- `< 0` → "🎯 Restam: X kcal" (ainda dá pra comer X pra bater a meta).
- `> 0` → "🎯 Excedente: X kcal" (comeu X acima da meta de ingestão).
- Queimar no treino **NÃO libera comer mais** — não soma no "Restam".
- Código: `packages/agent/src/balance-card.ts` (linha "🎯 Restam/Excedente").
- Teste: `balance-card.test.ts` ("REGRA MPP ... Restam = meta − consumido").

### 2b. Balanço NET / déficit do dia (alimenta o BLOCO 7700)
```
daily_balance = consumido − meta − exercício
```
- O exercício **conta aqui** (vira déficit que acelera a perda de gordura).
- É o número usado pelo `daily-closer` pra creditar o bloco.
- Roberto confirmou: déficit do dia = `design_deficit − excedente_comida + exercício`.
  Ex. 19/05: `500 − 233 + 565 = 832`.
- Fica salvo em `daily_snapshots.daily_balance`.

> Regra de ouro: **comida = sem exercício; bloco = com exercício.** O card mostra
> "Restam" (comida) + linha "🏃🏻 Exercício (acelera o bloco)" separada.

## 3. Bloco 7700 (`user_progress.deficit_block`)

1 kg de gordura = 7700 kcal. O bloco acumula o déficit creditado por dia.

Crédito por dia (fiel ao `daily-closer` + `computeProgress`):
```
newDeficit = max(0, designDeficit_efetivo + (−daily_balance))
```
- `designDeficit_efetivo = designDeficit` se o dia credita; senão 0.
- `deficit_block = soma(newDeficit) % 7700`; `blocks_completed = floor(soma / 7700)`.
- Código: `packages/core/src/progress-calc.ts` (`computeProgress`),
  `packages/inngest-functions/src/functions/daily-closer.ts`.
- Recálculo do zero (auditoria/backfill): `lib/bloco-recompute.ts`.

### Quando um dia CREDITA o bloco (regras de integridade)
- **Sem atividade** (0 refeição E 0 treino) → crédito **0** (`bloco7700.skipped_inactive_day`).
- **Incomplete (não respondeu lembrete de gap)** → NÃO credita design_deficit;
  credita só déficit observado se houver (`bloco7700.skipped_incomplete_day`).
- **Sub-registro (<50% da meta, exceto `user_skipped`)** → zera o `daily_balance`
  (o déficit observado é FAKE); dia *complete* credita só `design_deficit`,
  *incomplete* credita 0 (`bloco7700.skipped_subregistro`).
- **user_skipped** (paciente confirmou "pulei") → credita normal (déficit real).
- **complete ≥50%** → `design_deficit + déficit_observado`.

## 4. Card de balanço (renderizado pelo SISTEMA, não pelo LLM)

5 linhas canônicas (`renderBalanceCard`):
```
🔥 Consumido: C / meta kcal (X%)
🎯 Restam|Excedente: |consumido−meta| kcal      ← SEM exercício (§2a)
💪 Proteína: P / meta_P g (X%)
🏃🏻 Exercício: E kcal [(acelera o bloco 7700) se recomp e E>0]
📊 Bloco 7700: deficit_block / 7.700 kcal (X%)   ← recomp; senão Orçamento 14d
```
- O pipeline **substitui** qualquer card que o LLM escrever pelo card canônico
  com dados frescos do banco (`injectCanonicalCard`). O LLM nunca "calcula" o card.
- A prosa fora do card é reconciliada (`reconcileBalanceProse`) pela mesma base
  do card (comida, §2a) — rótulo e número não podem contradizer o card.

## 5. Defesas anti-erro (não remover)

- **Fake-registration detector** (`pipeline.ts`): se o LLM diz "registrado" com
  card mas NÃO chamou `registra_refeicao`/`registra_treino` → re-prompt forçado.
  Sem isso, refeições viram fantasma (card mostra, banco não tem). Eventos:
  `llm.fake_registration_detected/_unresolved`.
- **Card canônico** substitui alucinação numérica do LLM (`llm.card_replaced`).
- **reconcileBalanceProse** corrige rótulo déficit/superávit + magnitude na prosa.
- **Validador numérico / sentiment** loga divergências (`llm.numeric_mismatch`,
  `llm.sentiment_mismatch`).
- **Dedup intra-array** em `registra_refeicao` (itens repetidos somam quantidade).
- **Sub-registro / inactive / incomplete** no closer (§3) evitam déficit fake.

## 6. Auditoria automática (3×/dia, 9h/15h/21h BRT)

- `daily-audit` (cron nativo Inngest). Coleta métricas + manda Telegram.
- **Auto-corrige blocos** divergentes via `recomputeUserBloco` (§3), com
  **circuit-breaker**: se >8 usuários divergem num run, NÃO aplica e alerta
  (sinal de bug de fórmula). Evento `audit.bloco_autofixed`.
- Divergência snapshot↔meal_logs = só **ALERTA** (qual valor é verdadeiro é
  ambíguo — não auto-corrige).

## 7. Timezone

- Cada usuário tem `users.timezone`. Datas/janelas usam `getTzOffset`,
  `getLocalDateString`. Roberto = America/New_York; maioria = America/Sao_Paulo.
- ⚠️ **Pendência conhecida:** o `daily-closer` tica 00:30–03:30 UTC, que NÃO cobre
  bem a meia-noite de New_York (04:00 UTC) → dia de paciente em NY pode fechar
  com atraso. Investigar ticks adicionais pra fusos ocidentais.

---

## Como NÃO errar de novo (para humanos e para o agente)

1. **Toda regra de cálculo vive no código + teste**, não na cabeça de ninguém.
   Antes de mudar fórmula, leia este doc e o teste que a trava.
2. **Print de paciente ≠ ordem de mudar fórmula.** Reproduza no banco primeiro
   (consumido, meta, exercício, meal_logs, snapshot) e confronte com este doc.
3. **Card e bloco usam balanços diferentes** (§2). 90% da confusão histórica veio
   de misturar os dois. Comida sem exercício; bloco com exercício.
4. **Nunca confie só na ausência de evento** — um detector que não estava
   deployado não loga. Cheque o dado direto quando investigar período antigo.
5. Backfill de dado de paciente = sempre recálculo fiel ao closer
   (`bloco-recompute.ts`) + autorização explícita do Eduardo + evento de auditoria.
