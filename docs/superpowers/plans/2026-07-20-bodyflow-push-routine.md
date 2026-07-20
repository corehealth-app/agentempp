# BodyFlow Push And Routine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** entregar contratos e backend auditavel para devices iOS, preferencias,
lembretes, hidratacao e adesao, sem enviar push real.

**Architecture:** o BFF autenticado executa mutacoes idempotentes e o Postgres
mantem ownership, transacoes e claims. Uma funcao Inngest avalia regras contra o
estado oficial e enfileira entregas sem chamar APNs nesta fase.

**Tech Stack:** Next.js 15, Zod, Supabase/PostgreSQL, Inngest 3, Vitest, pnpm.

## Global Constraints

- Usar somente `/root/.codex/worktrees/agentempp-bodyflow-p0`.
- Produção `xuxehkhdvjivitduarvb` permanece intocada.
- Supabase staging e somente `xitugspwfxkcluxvrdeg`.
- Nao configurar ou imprimir secrets APNs.
- Nao sincronizar Inngest, reativar crons ou fazer deploy.
- Nao alterar formulas nutricionais ou do bloco 7700.
- Implementar por RED, GREEN e refactor.

---

### Task 1: Schema privado e invariantes transacionais

**Files:**
- Create: `supabase/migrations/<timestamp>_bodyflow_push_routine_foundation.sql`
- Create: `supabase/tests/bodyflow_push_routine.sql`
- Modify: `packages/db/src/generated/database.ts`

**Produces:** tabelas `mobile_devices`, `notification_preferences`,
`reminder_rules`, `routine_items`, `hydration_logs`, `routine_adherence_logs`,
`reminder_events` e `notification_deliveries`; RPCs backend-only para as mutacoes
atomicas e claims.

- [ ] Escrever primeiro o teste SQL para buckets de ownership, grants, RLS,
  idempotencia, hidratacao atomica, adesao, quiet hours e claim sem duplicidade.
- [ ] Executar o teste contra banco sem a migration e confirmar falha pela ausencia
  das relacoes.
- [ ] Criar a migration com `supabase migration new bodyflow_push_routine_foundation`.
- [ ] Implementar constraints, indices, RLS, grants e RPCs service-only.
- [ ] Aplicar em banco local descartavel e executar o teste ate passar.
- [ ] Regenerar tipos e executar `pnpm --filter @mpp/db typecheck`.
- [ ] Commit: `feat(database): add push and routine foundation`.

### Task 2: Contratos e servicos mobile

**Files:**
- Modify: `apps/admin/src/lib/mobile-api/contracts.ts`
- Create: `apps/admin/src/lib/mobile-api/routine-service.ts`
- Create: `apps/admin/src/lib/mobile-api/routine-service.test.ts`
- Create: `apps/admin/src/lib/mobile-api/supabase-routine.ts`
- Create/modify: rotas em `apps/admin/src/app/api/mobile/v1/`

**Consumes:** RPCs e tabelas da Task 1.

**Produces:** endpoints de devices, preferencias, reminders, hidratacao e `taken`.

- [ ] Escrever testes RED para validacao de token, horarios, dias, ownership,
  idempotencia, DTO sem token, hidratacao e tipo correto de routine item.
- [ ] Implementar schemas Zod estritos e DTOs minimizados.
- [ ] Implementar servico com dependencias injetaveis e erros mobile explicitos.
- [ ] Implementar adaptador Supabase e rotas usando `executeSupabaseIdempotent`.
- [ ] Rodar `pnpm --filter @mpp/admin test` e typecheck.
- [ ] Commit: `feat(mobile-api): add reminders and routine endpoints`.

### Task 3: Scheduler e fila idempotente

**Files:**
- Modify: `packages/inngest-functions/src/client.ts`
- Modify: `packages/inngest-functions/src/index.ts`
- Create: `packages/inngest-functions/src/functions/reminder-scheduler.ts`
- Create: `packages/inngest-functions/src/functions/reminder-scheduler.test.ts`

**Consumes:** claims da Task 1 e estado oficial de `daily_snapshots`, meal/workout
logs, reavaliacoes e adesao.

**Produces:** funcao Inngest registrada e evento tipado contendo apenas IDs.

- [ ] Escrever testes RED para regra resolvida, quiet hours, limite, retry e ausencia
  de fonte oficial.
- [ ] Implementar avaliador puro de elegibilidade.
- [ ] Implementar repositorio Supabase e claim transacional.
- [ ] Registrar scheduler com concorrencia limitada, sem provider APNs.
- [ ] Garantir que nenhum token ou texto sensivel entre no evento/log.
- [ ] Rodar `pnpm --filter @mpp/inngest-functions test` e typecheck.
- [ ] Commit: `feat(workers): queue official-state reminders`.

### Task 4: Daily state, documentacao e staging

**Files:**
- Modify: `packages/agent/src/daily-state-service.ts`
- Modify: `packages/agent/src/daily-state-service.test.ts`
- Modify: `docs/mobile/api-v1.md`
- Create: `docs/adr/013-push-routine-outbox.md`

**Consumes:** hidratacao e rotina das Tasks 1-3.

**Produces:** daily state informa meta/status de hidratacao e disponibilidade real
de suplementos/medicamentos sem inventar dados.

- [ ] Escrever teste RED para meta opcional e itens privados da rotina.
- [ ] Fazer mudanca aditiva no DTO mantendo `bodyflow.daily-state.v1`.
- [ ] Documentar contratos, estados, limites e fronteira sem APNs.
- [ ] Rodar suites completas, typecheck, build, Biome dos arquivos alterados e
  `git diff --check`.
- [ ] Fazer dry-run e aplicar migrations somente em staging apos validar o ref.
- [ ] Rodar teste SQL transacional, lint e advisors em staging.
- [ ] Confirmar zero dados sinteticos remanescentes e crons ainda inativos.
- [ ] Commit: `docs(mobile): document push and routine contracts`.
- [ ] Push da branch e abrir PR draft contra `codex/bodyflow-secure-media-v1`.

