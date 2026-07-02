# Engine: Unificação do crédito do bloco 7700 (Sub-projeto A — Fase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar `@mpp/core/engine/bloco.ts` como fonte única da regra de crédito do bloco 7700 e fazer `bloco-recompute.ts` usá-la, com testes de paridade — sem mudar comportamento.

**Architecture:** Extrair a regra de crédito por dia (hoje replicada em `bloco-recompute.ts` e, em camadas, em `daily-closer.ts` + `progress-calc.ts`) para uma função pura testada. Esta fase migra só o caminho do AUDIT (`bloco-recompute`); o caminho do fechamento diário (closer) vem na Fase 2. Paridade provada por teste contra os blocos já validados (Gleidson/Raphaela batem exato).

**Tech Stack:** TypeScript, monorepo pnpm, Vitest. Pacote `@mpp/core` (puro, sem I/O).

---

## File Structure

- Create: `packages/core/src/engine/bloco.ts` — funções puras `creditDayToBloco`, `accumulateBloco`, const `KCAL_BLOCK`.
- Create: `packages/core/src/engine/bloco.test.ts` — unit + property + paridade.
- Modify: `packages/core/src/index.ts` — exportar o engine.
- Modify: `packages/inngest-functions/src/lib/bloco-recompute.ts` — usar o engine em vez da regra inline.

Escopo desta fase NÃO inclui: `daily-closer.ts`/`progress-calc.ts` (Fase 2), `targets`/`balance`/`render` (fases seguintes).

---

### Task 1: Criar a função pura de crédito do bloco

**Files:**
- Create: `packages/core/src/engine/bloco.ts`
- Test: `packages/core/src/engine/bloco.test.ts`

- [ ] **Step 1: Escrever o teste que falha**

```typescript
// packages/core/src/engine/bloco.test.ts
import { describe, it, expect } from 'vitest'
import { creditDayToBloco, accumulateBloco, KCAL_BLOCK } from './bloco.js'

describe('creditDayToBloco — regra de crédito por dia (fiel ao daily-closer)', () => {
  const base = {
    hasActivity: true,
    dayStatus: 'complete' as const,
    caloriesConsumed: 1500,
    caloriesTarget: 1843,
    dailyBalance: -343, // consumido - meta - exercício
    designDeficit: 500,
  }

  it('dia complete >=50%: designDeficit + déficit observado', () => {
    // max(0, 500 - (-343)) = 843
    expect(creditDayToBloco(base)).toBe(843)
  })

  it('sem atividade: crédito 0', () => {
    expect(creditDayToBloco({ ...base, hasActivity: false })).toBe(0)
  })

  it('sub-registro <50% complete: credita só o designDeficit', () => {
    expect(
      creditDayToBloco({ ...base, caloriesConsumed: 400, dailyBalance: -1443 }),
    ).toBe(500)
  })

  it('sub-registro <50% incomplete: credita 0', () => {
    expect(
      creditDayToBloco({
        ...base,
        dayStatus: 'incomplete_no_response',
        caloriesConsumed: 400,
        dailyBalance: -1443,
      }),
    ).toBe(0)
  })

  it('incomplete >=50%: credita 0 enquanto o gap segue aberto', () => {
    // Superseded 2026-07-01: Roberto escolheu opção 1 — gap aberto não entra no bloco.
    expect(creditDayToBloco({ ...base, dayStatus: 'incomplete_no_response' })).toBe(0)
  })

  it('user_skipped: credita normal (designDeficit + déficit), mesmo com consumo baixo', () => {
    // Roberto 19/05: dd 500, balance -332 → 832
    expect(
      creditDayToBloco({
        ...base,
        dayStatus: 'user_skipped',
        caloriesConsumed: 2076,
        dailyBalance: -332,
      }),
    ).toBe(832)
  })

  it('comeu acima da meta sem exercício: crédito 0 (não negativo)', () => {
    expect(creditDayToBloco({ ...base, caloriesConsumed: 2200, dailyBalance: 357 })).toBe(0)
  })

  it('protocolo não-recomp (designDeficit 0) on-plan: crédito 0', () => {
    expect(creditDayToBloco({ ...base, designDeficit: 0, dailyBalance: 0 })).toBe(0)
  })
})

describe('accumulateBloco', () => {
  it('soma % 7700 e conta blocos cheios', () => {
    expect(accumulateBloco([4000, 4000])).toEqual({ deficitBlock: 300, blocksCompleted: 1 })
  })
  it('lista vazia = 0/0', () => {
    expect(accumulateBloco([])).toEqual({ deficitBlock: 0, blocksCompleted: 0 })
  })
  it('arredonda a soma antes do módulo', () => {
    expect(accumulateBloco([100.4, 100.4])).toEqual({ deficitBlock: 201, blocksCompleted: 0 })
  })
})

describe('property: bloco sempre em [0, KCAL_BLOCK)', () => {
  it('para somas variadas', () => {
    for (const total of [0, 1, 7699, 7700, 7701, 15400, 23100.6]) {
      const r = accumulateBloco([total])
      expect(r.deficitBlock).toBeGreaterThanOrEqual(0)
      expect(r.deficitBlock).toBeLessThan(KCAL_BLOCK)
    }
  })
})
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `pnpm --filter @mpp/core test -- bloco.test`
Expected: FAIL — `Cannot find module './bloco.js'`.

- [ ] **Step 3: Implementar a função pura**

```typescript
// packages/core/src/engine/bloco.ts

/**
 * Regra de crédito do bloco 7700 — FONTE ÚNICA.
 * Fiel ao daily-closer.ts + computeProgress (ver docs/CALCULO-MPP.md §3).
 * Validado 2026-05-20: Gleidson (1967) e Raphaela (0) batem exato; crédito do
 * dia 19/05 do Roberto = 832.
 *
 * ⚠️ Esta é a única implementação da regra. daily-closer e bloco-recompute
 * devem chamá-la — NÃO replicar a lógica em outro lugar.
 */
export const KCAL_BLOCK = 7700

export type DayStatus = 'complete' | 'incomplete_no_response' | 'user_skipped'

export interface DayCreditInput {
  /** houve refeição OU treino no dia */
  hasActivity: boolean
  /** status do dia; null = tratado como 'complete' (dias antigos sem o campo) */
  dayStatus: DayStatus | null
  caloriesConsumed: number
  caloriesTarget: number | null
  /** consumido − meta − exercício (coluna gerada daily_snapshots.daily_balance) */
  dailyBalance: number
  /** déficit estrutural do protocolo: recomp ? deficit_level(400/500/600) : 0 */
  designDeficit: number
}

/** kcal creditadas ao bloco 7700 por UM dia fechado. */
export function creditDayToBloco(d: DayCreditInput): number {
  if (!d.hasActivity) return 0
  if (d.dayStatus === 'user_skipped') return Math.max(0, d.designDeficit - d.dailyBalance)
  if (
    d.caloriesTarget != null &&
    d.caloriesTarget > 0 &&
    d.caloriesConsumed < 0.5 * d.caloriesTarget
  ) {
    // sub-registro: déficit observado é fake → zera; complete credita só design.
    return d.dayStatus === 'complete' || d.dayStatus == null ? d.designDeficit : 0
  }
  if (d.dayStatus === 'incomplete_no_response') return 0
  return Math.max(0, d.designDeficit - d.dailyBalance)
}

/** Acumula créditos diários → bloco atual (resto) + blocos completos. */
export function accumulateBloco(credits: number[]): {
  deficitBlock: number
  blocksCompleted: number
} {
  const total = Math.round(credits.reduce((a, b) => a + b, 0))
  return { deficitBlock: total % KCAL_BLOCK, blocksCompleted: Math.floor(total / KCAL_BLOCK) }
}
```

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `pnpm --filter @mpp/core test -- bloco.test`
Expected: PASS (todos os casos).

- [ ] **Step 5: Commit**

```bash
git add packages/core/src/engine/bloco.ts packages/core/src/engine/bloco.test.ts
git commit -m "feat(core): engine/bloco — fonte única da regra de crédito do bloco 7700"
```

---

### Task 2: Exportar o engine no índice do @mpp/core

**Files:**
- Modify: `packages/core/src/index.ts`

- [ ] **Step 1: Adicionar o export**

Adicionar ao final de `packages/core/src/index.ts`:

```typescript
export * from './engine/bloco.js'
```

- [ ] **Step 2: Verificar typecheck do core**

Run: `pnpm --filter @mpp/core typecheck`
Expected: sem erros.

- [ ] **Step 3: Commit**

```bash
git add packages/core/src/index.ts
git commit -m "feat(core): exporta engine/bloco no índice"
```

---

### Task 3: Migrar bloco-recompute.ts para usar o engine

**Files:**
- Modify: `packages/inngest-functions/src/lib/bloco-recompute.ts`

- [ ] **Step 1: Substituir a regra inline pela chamada ao engine**

Em `packages/inngest-functions/src/lib/bloco-recompute.ts`:

1. Adicionar import no topo (junto aos outros imports):

```typescript
import { creditDayToBloco, accumulateBloco } from '@mpp/core'
```

2. Substituir o bloco de cálculo (o loop que hoje calcula `credit` inline e faz `total += credit`, e o `return` com `% KCAL_BLOCK`) por:

```typescript
  const credits = rows.map((s) => {
    const hasAct =
      (mealCounts[s.id] ?? 0) > 0 || (s.exercise_calories ?? 0) > 0 || !!s.training_done
    return creditDayToBloco({
      hasActivity: hasAct,
      dayStatus: (s.day_status ?? null) as
        | 'complete'
        | 'incomplete_no_response'
        | 'user_skipped'
        | null,
      caloriesConsumed: s.calories_consumed ?? 0,
      caloriesTarget: s.calories_target,
      dailyBalance: s.daily_balance ?? 0,
      designDeficit,
    })
  })
  const { deficitBlock, blocksCompleted } = accumulateBloco(credits)
  return {
    userId,
    daysClosed: rows.length,
    correctDeficitBlock: deficitBlock,
    correctBlocksCompleted: blocksCompleted,
  }
```

3. Remover a const local `KCAL_BLOCK` deste arquivo (agora vem do engine) se ela não for mais usada.

- [ ] **Step 2: Typecheck**

Run: `pnpm --filter @mpp/inngest-functions typecheck`
Expected: sem erros.

- [ ] **Step 3: Commit**

```bash
git add packages/inngest-functions/src/lib/bloco-recompute.ts
git commit -m "refactor(audit): bloco-recompute usa engine/bloco (fonte única)"
```

---

### Task 4: Teste de paridade com dados reais (fixture)

**Files:**
- Create: `packages/core/src/engine/bloco.parity.test.ts`

- [ ] **Step 1: Escrever o teste de paridade com fixture dos dados reais validados**

```typescript
// packages/core/src/engine/bloco.parity.test.ts
import { describe, it, expect } from 'vitest'
import { creditDayToBloco, accumulateBloco } from './bloco.js'

// Fixture: dias fechados reais (recomp, designDeficit do perfil) e o bloco
// esperado já validado em produção em 2026-05-20.
// Gleidson (designDeficit 500) → bloco 1967; Raphaela (1 dia) → 0.
type Day = {
  hasActivity: boolean
  dayStatus: 'complete' | 'incomplete_no_response' | 'user_skipped' | null
  caloriesConsumed: number
  caloriesTarget: number | null
  dailyBalance: number
}

function bloco(days: Day[], designDeficit: number) {
  return accumulateBloco(
    days.map((d) => creditDayToBloco({ ...d, designDeficit })),
  ).deficitBlock
}

describe('paridade: regra do engine reproduz blocos validados em prod (2026-05-20)', () => {
  it('Roberto 19/05 (user_skipped) credita 832', () => {
    expect(
      creditDayToBloco({
        hasActivity: true,
        dayStatus: 'user_skipped',
        caloriesConsumed: 2076,
        caloriesTarget: 1843,
        dailyBalance: -332,
        designDeficit: 500,
      }),
    ).toBe(832)
  })

  it('Raphaela: 1 dia sem atividade → bloco 0', () => {
    const dias: Day[] = [
      { hasActivity: false, dayStatus: 'complete', caloriesConsumed: 0, caloriesTarget: 980, dailyBalance: -980 },
    ]
    expect(bloco(dias, 500)).toBe(0)
  })
})
```

> Nota pro executor: se quiser ampliar a paridade, exportar os dias fechados
> reais via a Management API (somente leitura) e congelar como fixture. O caso
> Roberto 19/05 e Raphaela já travam a regra nos dois extremos.

- [ ] **Step 2: Rodar e ver passar**

Run: `pnpm --filter @mpp/core test -- bloco`
Expected: PASS (unit + property + paridade).

- [ ] **Step 3: Rodar a suíte inteira do agent (garantir que nada quebrou)**

Run: `pnpm --filter @mpp/agent test`
Expected: PASS (100+ testes).

- [ ] **Step 4: Commit**

```bash
git add packages/core/src/engine/bloco.parity.test.ts
git commit -m "test(core): paridade do engine/bloco com blocos validados em prod"
```

---

## Validação final da fase (antes de deploy)

- [ ] `pnpm typecheck` (repo todo) — PASS
- [ ] `pnpm --filter @mpp/core test && pnpm --filter @mpp/agent test` — PASS
- [ ] Revisar diff: `bloco-recompute.ts` deve ter MENOS lógica (delegou ao engine), comportamento idêntico.
- [ ] **Deploy:** somente com autorização explícita do Eduardo (regra da sessão). O audit 3×/dia usa `bloco-recompute`; após deploy, o primeiro run deve reportar **0 correções** (paridade — nada mudou).

---

## Próximas fases da Sub-projeto A (planos separados)
- **Fase 2:** migrar `daily-closer.ts` + `computeProgress` pra usar `creditDayToBloco` (caminho de escrita diária — maior cuidado, golden tests do fechamento).
- **Fase 3:** `engine/targets.ts` (mover `computeDailyTargets`) e `engine/balance.ts` (os dois balanços explícitos).
- **Fase 4:** mover `renderBalanceCard` pra `@mpp/core/render` + montador de estado no pipeline.

## Self-review
- Cobertura do spec (Fase 1): "regra do bloco em um só lugar" ✓ (Task 1-3); "paridade provada" ✓ (Task 4); "property test do bloco" ✓ (Task 1). Demais itens do spec A → fases 2-4.
- Sem placeholders: todos os steps têm código/comando reais.
- Consistência de tipos: `DayCreditInput`, `creditDayToBloco`, `accumulateBloco`, `KCAL_BLOCK` usados de forma idêntica entre tasks.
