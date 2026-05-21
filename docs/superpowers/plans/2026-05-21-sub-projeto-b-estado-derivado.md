# Sub-projeto B — Persistir estado derivado Implementation Plan

> REQUIRED SUB-SKILL: subagent-driven-development ou executing-plans.

**Goal:** Persistir dados que hoje a LLM joga fora/inventa: água/sono/passos (captura leve), BF% das fotos (estimativa separada), e agregados semana/mês (cálculo determinístico).

**Tech Stack:** TS, pnpm, Vitest. `@mpp/core` (engine), `@mpp/agent` (tools), Supabase.

**Inventário (2026-05-21):** `daily_snapshots` já tem `water_consumed_ml`/`sleep_hours`/`steps` (sem migration). `user_profiles` só tem `body_fat_percent` confirmado → BF% estimado PRECISA de migration.

---

### Bloco 1 — Agregados semana/mês (engine, sem migration)

**Files:** Create `packages/core/src/engine/aggregates.ts` + `.test.ts`; Modify `index.ts`; Modify `packages/agent/src/tools.ts` (nova tool `consulta_resumo_periodo`).

- [ ] Engine `aggregates.ts`: `computePeriodSummary(snapshots, days)` puro → médias de consumido, proteína, déficit (netBalance), nº dias completos, % aderência. Retorna struct tipado.
- [ ] Tests: snapshots sintéticos → médias corretas; janela vazia → zeros.
- [ ] Tool `consulta_resumo_periodo(periodo: 'semana'|'mes')`: lê daily_snapshots da janela, chama o engine, retorna struct. Registrar em ALL_TOOLS.
- [ ] Commit.

### Bloco 2 — Água/sono/passos (captura leve, sem migration)

**Files:** Modify `packages/agent/src/tools.ts` (nova tool `registra_metrica_diaria`).

- [ ] Tool `registra_metrica_diaria({ water_ml?, sleep_hours?, steps? })`: grava nas colunas existentes do snapshot de HOJE (criar/achar snapshot do dia local do usuário — reusar helper de snapshot existente). Só grava o que veio (parcial). Sem meta obrigatória, sem linha de card.
- [ ] Description deixa claro: usar quando o paciente MENCIONA água/sono/passos; não inferir.
- [ ] Registrar em ALL_TOOLS. Evento `metric.captured`.
- [ ] Commit.

### Bloco 3 — BF% estimado das fotos (PRECISA migration — GATED)

**Files:** Migration nova; Modify vision flow (`process-message.ts`), `protocol-router.ts`.

- [ ] **Migration** (≤100 linhas, dry-run BEGIN/ROLLBACK primeiro): add em `user_profiles` colunas `bf_percent_estimated numeric`, `bf_source text`, `bf_estimated_at timestamptz`. **APLICAR só com autorização explícita do Eduardo** (protocolo CLAUDE.md). Commit do arquivo de migration só após aplicar e validar.
- [ ] Vision/process-message: ao analisar foto corporal com BF% estimado + confidence, gravar em `bf_percent_estimated`/`bf_source='vision'`/`bf_estimated_at` — NUNCA sobrescrever `body_fat_percent` (confirmado).
- [ ] protocol-router: pode usar `bf_percent_estimated` (marcado como estimativa) quando `body_fat_percent` confirmado é null; pedir confirmação em decisão crítica.
- [ ] Tests: estimativa nunca sobrescreve confirmado; router usa estimativa marcada.
- [ ] Commit.

---

## Validação / deploy
- Suítes core + agent PASS; typecheck repo PASS.
- Migration: dry-run + autorização + validação pós-aplicação.
- Deploy: só com autorização explícita.
