# Engine bloco — Fase 2: closer + computeProgress usam o engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development ou executing-plans. Steps em checkbox.

**Goal:** Fazer o `daily-closer` (fechamento noturno) e o `computeProgress` usarem `creditDayToBloco` do engine — removendo a regra de crédito duplicada do caminho de escrita —, mantendo comportamento e logs idênticos.

**Architecture:** `computeProgress` deixa de calcular o crédito (passa a receber um `dayCredit` já pronto e só acumular XP/streak/bloco/badges). O closer computa `dayCredit = creditDayToBloco(raw)` e mantém os eventos `bloco7700.skipped_*` (logging) baseados nas mesmas condições. Paridade travada por golden tests.

**Tech Stack:** TypeScript, monorepo pnpm, Vitest. `@mpp/core` (puro), `@mpp/inngest-functions`.

**⚠️ Risco:** caminho de escrita noturno (credita o bloco real). Paridade é obrigatória; deploy só após validação extra + autorização explícita.

---

## File Structure
- Modify: `packages/core/src/progress-calc.ts` — `computeProgress` recebe `dayCredit` em vez de calcular `newDeficit`.
- Modify: `packages/core/tests/progress-calc.test.ts` — atualizar chamadas + assertir acumulação.
- Modify: `packages/inngest-functions/src/functions/daily-closer.ts` — computar `dayCredit` via engine; preservar eventos `bloco7700.skipped_*`.
- (Sem novos arquivos.)

---

### Task 1: `computeProgress` recebe `dayCredit` (não calcula mais o crédito)

**Files:** Modify `packages/core/src/progress-calc.ts`; Modify `packages/core/tests/progress-calc.test.ts`

- [ ] **Step 1 — atualizar os testes (golden) primeiro.** Em `progress-calc.test.ts`, as chamadas hoje passam `designDeficit` como 4º arg. Trocar para passar o **crédito já calculado**. Para cada teste de bloco existente, computar o crédito esperado (o mesmo número que `creditDayToBloco` daria) e passá-lo. Ex.: um teste que hoje faz `computeProgress(snap, prev, cfg, 500)` com `snap.dailyBalance=-343` esperando `deficitBlock` += 843 passa a `computeProgress(snap, prev, cfg, 843)`. Manter as asserções de `deficitBlock`/`blocksCompleted` idênticas. Rodar e ver falhar (assinatura ainda não mudou / valores).

- [ ] **Step 2 — mudar a assinatura e o corpo.** Em `progress-calc.ts`, trocar o 4º parâmetro de `designDeficit = 0` para `dayCredit = 0` e substituir as linhas 86-92 (o cálculo de `newDeficit`) por:

```typescript
  // Bloco 7700: o crédito do dia já vem pronto do engine (creditDayToBloco),
  // chamado pelo daily-closer. computeProgress só ACUMULA — não recalcula a regra.
  const totalDeficit = prev.deficitBlock + dayCredit
  const blocksDelta = Math.floor(totalDeficit / config.kcal_block)
  const blocksCompleted = prev.blocksCompleted + blocksDelta
  const deficitBlock = totalDeficit % config.kcal_block
```

Atualizar o JSDoc do parâmetro (`@param dayCredit kcal já creditadas neste dia, vindas de creditDayToBloco`).

- [ ] **Step 3 — rodar `pnpm --filter @mpp/core test`** → todos PASS (incl. progress-calc + bloco).
- [ ] **Step 4 — commit:** `git commit -m "refactor(core): computeProgress recebe dayCredit (crédito vem do engine)"`

---

### Task 2: `daily-closer` computa `dayCredit` via engine, preservando os eventos

**Files:** Modify `packages/inngest-functions/src/functions/daily-closer.ts`

- [ ] **Step 1 — importar o engine** no topo: `import { creditDayToBloco } from '@mpp/core'`.

- [ ] **Step 2 — preservar os eventos, delegar o crédito.** No bloco que hoje faz a pré-adjustagem (calcula `blocoCreditaThisDay`, `effectiveDesignDeficit`, zera `dailySnap.dailyBalance` para `!hasActivity` e sub-registro, e emite os eventos `bloco7700.skipped_inactive_day` / `skipped_subregistro`):
  - MANTER as condições que decidem emitir os eventos `bloco7700.skipped_inactive_day`, `bloco7700.skipped_subregistro` e `bloco7700.skipped_incomplete_day` (logging — não remover).
  - REMOVER o cálculo de `effectiveDesignDeficit` e a manipulação de `dailySnap.dailyBalance` voltada ao crédito.
  - Computar o crédito do dia com o engine, a partir dos valores RAW:

```typescript
  const dayCredit = creditDayToBloco({
    hasActivity,
    dayStatus: finalDayStatus,
    caloriesConsumed: kcalConsumed,
    caloriesTarget: targets.calories_target,
    dailyBalance: snap.daily_balance ?? 0,
    designDeficit,
  })
```

  - Passar `dayCredit` ao `computeProgress`: `const next = computeProgress(dailySnap, prev, calcConfig, dayCredit)`.

- [ ] **Step 3 — typecheck:** `pnpm --filter @mpp/inngest-functions typecheck` → sem erros.
- [ ] **Step 4 — commit:** `git commit -m "refactor(closer): crédito do bloco via engine, eventos preservados"`

---

### Task 3: Golden test de paridade do fechamento

**Files:** Create `packages/inngest-functions/src/functions/daily-closer.bloco.test.ts` (ou local equivalente de teste)

- [ ] **Step 1 — escrever cenários de fechamento e o crédito esperado**, cobrindo: dia complete normal, sub-registro complete, sub-registro incomplete, sem atividade, user_skipped, excedente leve. Para cada um, montar os inputs e assertir `creditDayToBloco(...)` == valor esperado (os mesmos valores travados em `bloco.test.ts`/`bloco.parity.test.ts`). Como a regra agora é única, este teste confirma que o closer alimenta o engine com os campos certos.

- [ ] **Step 2 — rodar suíte:** `pnpm --filter @mpp/core test && pnpm --filter @mpp/inngest-functions typecheck && pnpm --filter @mpp/agent test` → tudo PASS.
- [ ] **Step 3 — commit:** `git commit -m "test(closer): paridade do crédito do bloco no fechamento"`

---

## Validação final (antes de deploy)
- [ ] `pnpm typecheck` repo — PASS
- [ ] Todas as suítes — PASS
- [ ] **Validação extra recomendada:** rodar `recomputeUserBloco` (read-only, Management API) para os usuários ativos ANTES e DEPOIS do deploy do closer e confirmar 0 divergência no próximo fechamento. (O closer e o audit agora usam a MESMA função → devem concordar sempre.)
- [ ] **Deploy:** só com autorização explícita do Eduardo. Como é o caminho de escrita noturno, validar o primeiro fechamento pós-deploy (audit das 9h deve reportar 0 correções).

## Self-review
- Cobertura: closer + computeProgress passam a usar o engine ✓; eventos preservados ✓; paridade ✓.
- Risco do dayCredit divergir do antigo: mitigado por Task 1 (golden) + Task 3 + a regra ser a mesma função já validada na Fase 1.
