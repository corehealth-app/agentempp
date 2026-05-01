# ADR 002 — Saída total do Notion como CMS de prompts

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo

## Contexto

O sistema legado armazenava 88 regras de comportamento + 6 configurações de sub-agentes em databases do Notion, lidas em runtime pelo n8n. Problemas: latência (200-800ms), rate limit (3 req/s), sem RLS, sem CI/CD de prompts, vendor lock-in.

## Decisão

Migrar tudo para tabelas Postgres no Supabase:
- `agent_rules` (com versionamento imutável via trigger)
- `agent_configs`
- `agent_rules_versions` / `agent_configs_versions`
- View `v_active_prompts` para consumo runtime

UI de edição construída em Next.js (Tiptap + diff visual + preview + playground).

## Consequências

- **+** Latência de leitura cai de ~500ms para <5ms
- **+** RLS granular (admin / editor / viewer)
- **+** CI/CD de prompts via GitHub Actions com eval gate
- **+** Stack única (apenas Supabase)
- **−** Investimento de ~3-5 dias para construir admin UI
- **−** Migração one-time das 88 regras
