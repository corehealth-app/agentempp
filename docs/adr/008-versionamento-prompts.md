# ADR 008 — Versionamento imutável de prompts via trigger Postgres

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo

## Contexto

Mudanças em prompts afetam diretamente o comportamento do produto. Precisamos de auditoria total (quem mudou o quê, quando, por quê) e capacidade de rollback granular.

## Decisão

- Tabela `agent_rules` armazena versão atual.
- Trigger `snapshot_rule_version` cria entrada imutável em `agent_rules_versions` a cada UPDATE de `content` ou `status`.
- Cada versão preserva: `topic`, `tipo`, `content`, `status`, `change_reason`, `changed_by`, `changed_at`.
- Mesma estrutura para `agent_configs` / `agent_configs_versions`.
- Diretório `prompts/` no git é espelho dos prompts ativos (gerado por sync job).
- Mudanças via PR no GitHub disparam eval suite (gate de deploy).

## Consequências

- **+** Auditoria completa
- **+** Rollback granular
- **+** Compliance com práticas de mudança em produção
- **+** Diff visual entre versões na admin UI
- **−** Tabela `_versions` cresce continuamente (mitigado por arquivamento periódico)
