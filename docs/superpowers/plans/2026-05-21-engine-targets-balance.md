# Engine: targets + balance (Sub-projeto A — Fase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: subagent-driven-development ou executing-plans. Steps em checkbox.

**Goal:** Mover `computeDailyTargets` (meta cal/proteína) e os dois balanços (comida/net) para `@mpp/core/engine`, com o código do agent delegando — paridade total.

**Architecture:** Funções puras no engine; `balance-card.ts` e `pipeline.ts` passam a usar `eatingBalance`; `calc-targets.ts` (agent) re-exporta `computeDailyTargets` do core e mantém só `loadDailyTargets` (I/O).

**Tech Stack:** TS, pnpm, Vitest. `@mpp/core` (puro), `@mpp/agent`.

---

### Task 1: `engine/balance.ts` (dois balanços explícitos)

**Files:** Create `packages/core/src/engine/balance.ts` + `.test.ts`; Modify `packages/core/src/index.ts`.

- [ ] **Step 1 — teste falha** (`balance.test.ts`):
```typescript
import { describe, it, expect } from 'vitest'
import { eatingBalance, netBalance } from './balance.js'
describe('balanços (regra MPP)', () => {
  it('eatingBalance = consumido − meta (SEM exercício)', () => {
    expect(eatingBalance(1407, 1843)).toBe(-436)
    expect(eatingBalance(2076, 1843)).toBe(233)
  })
  it('netBalance = consumido − meta − exercício (déficit do dia / bloco)', () => {
    expect(netBalance(2076, 1843, 565)).toBe(-332)
    expect(netBalance(1210, 1843, 467)).toBe(-1100)
  })
})
```
- [ ] **Step 2 — rodar e ver falhar:** `pnpm --filter @mpp/core test -- balance.test`
- [ ] **Step 3 — implementar `balance.ts`:**
```typescript
/**
 * Dois balanços distintos (ver docs/CALCULO-MPP.md §2):
 *  - COMIDA: consumido − meta (linha 🎯 Restam/Excedente do card; SEM exercício)
 *  - NET:    consumido − meta − exercício (déficit do dia; alimenta o bloco)
 */
export function eatingBalance(caloriesConsumed: number, caloriesTarget: number): number {
  return caloriesConsumed - caloriesTarget
}
export function netBalance(
  caloriesConsumed: number,
  caloriesTarget: number,
  exerciseCalories: number,
): number {
  return caloriesConsumed - caloriesTarget - exerciseCalories
}
```
- [ ] **Step 4 — exportar:** adicionar `export * from './engine/balance.js'` ao `packages/core/src/index.ts`.
- [ ] **Step 5 — rodar:** `pnpm --filter @mpp/core test -- balance.test` → PASS; `pnpm --filter @mpp/core typecheck`.
- [ ] **Step 6 — commit:** `git commit -m "feat(core): engine/balance — eatingBalance + netBalance"`

### Task 2: usar `eatingBalance` no balance-card e no pipeline

**Files:** Modify `packages/agent/src/balance-card.ts`, `packages/agent/src/pipeline.ts`.

- [ ] **Step 1 — balance-card.ts:** importar `eatingBalance` de `@mpp/core` e trocar `const eatingBalance = data.caloriesConsumed - data.caloriesTarget` por `const eb = eatingBalance(data.caloriesConsumed, data.caloriesTarget)` (renomear a variável local pra não colidir com o import; ajustar os usos `eatingBalance>0`/`-eatingBalance`).
- [ ] **Step 2 — pipeline.ts:** onde calcula `const eatingBalance = snapTyped.calories_consumed - snapTyped.calories_target` (bloco do reconcile) e `ctx.todaySnapshot.calories_consumed - ctx.dailyTargets.calories_target` (sentiment), usar a função `eatingBalance(...)` do `@mpp/core`. Cuidar de nome (importar como `eatingBalance`, renomear locais).
- [ ] **Step 3 — rodar:** `pnpm --filter @mpp/agent test` (100 testes do card etc. devem passar — paridade); `pnpm --filter @mpp/agent typecheck`.
- [ ] **Step 4 — commit:** `git commit -m "refactor(agent): card+pipeline usam engine/balance.eatingBalance"`

### Task 3: mover `computeDailyTargets` para `engine/targets.ts`

**Files:** Create `packages/core/src/engine/targets.ts` + `.test.ts`; Modify `packages/core/src/index.ts`, `packages/agent/src/calc-targets.ts`.

- [ ] **Step 1 — mover** `ProfileRow`, `DailyTargets`, `rowToProfile`, `computeDailyTargets` de `calc-targets.ts` para `engine/targets.ts` (imports relativos dentro do core: `../nutrition.js`, `../calc-config.js`, `../types.js` conforme necessário). Lógica IDÊNTICA.
- [ ] **Step 2 — exportar:** `export * from './engine/targets.js'` no índice do core.
- [ ] **Step 3 — calc-targets.ts (agent):** remover as definições movidas; re-exportar do core (`export { computeDailyTargets, type DailyTargets, type ProfileRow } from '@mpp/core'`) e manter `loadDailyTargets` (I/O) chamando `computeDailyTargets`.
- [ ] **Step 4 — teste** `engine/targets.test.ts`: assertir meta recomp (BMR×1.2 − déficit), ganho (TDEE×1.05), manutenção (TDEE) e protein_target, com um profileRow sintético + config default. (Replicar valores esperados calculados.)
- [ ] **Step 5 — rodar:** `pnpm --filter @mpp/core test`, `pnpm --filter @mpp/agent test`, `pnpm typecheck` → tudo PASS.
- [ ] **Step 6 — commit:** `git commit -m "refactor(core): move computeDailyTargets para engine/targets"`

---

## Validação final
- [ ] `pnpm typecheck` repo — PASS
- [ ] core + agent suites — PASS (paridade: card e metas idênticos)
- [ ] Deploy: só com autorização (paridade pura — comportamento idêntico).

## Self-review
- balance e targets no engine ✓; agent delega ✓; paridade por testes existentes do card + novos do targets/balance.
