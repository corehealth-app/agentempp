# ADR 003 — Saída total do n8n para código TypeScript + Inngest

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo

## Contexto

Workflow n8n atual tem 170+ nodes e 12+ ramificações de Switch. Manutenibilidade comprometida, sem testes, sem CI/CD, sem versionamento granular, dificuldade de evolução.

## Decisão

Reescrever toda a orquestração em código TypeScript versionado, organizado como:
- **Inngest** para step functions com retries durables, concurrency control e visibility
- **Edge Functions Supabase** apenas para webhooks (parsing, dedupe, persist, enqueue)
- **packages/core** com lógica de domínio pura, testada com Vitest
- **pg_cron** disparando eventos Inngest para crons (closer, engagement)

## Consequências

- **+** Testes unitários para toda lógica determinística
- **+** Type safety end-to-end
- **+** CI/CD com eval gate
- **+** Concurrency control por user_id (sem race condition)
- **+** Step durability (resume após crash)
- **−** Reescrita completa da lógica
- **−** Perda da visualização gráfica (compensada por logs do Inngest dashboard)
