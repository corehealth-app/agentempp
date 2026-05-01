# ADR 009 — Greenfield, sem migração de dados

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo + CoreHealth

## Contexto

Sistema legado (n8n + Notion + Chatwoot + Evolution API) está em ambiente de desenvolvimento, sem usuários reais, sem assinantes pagantes, sem dados a preservar.

## Decisão

Construir o novo sistema do zero, sem migrar dados do legado. As 88 regras de comportamento e 6 configurações de sub-agentes são re-importadas no Postgres como configuração inicial.

Sistema legado será desligado sem cerimônia após validação do novo em staging.

## Consequências

- **+** Sem complexidade de migração de dados
- **+** Sem necessidade de shadow mode ou canary
- **+** Velocidade: 5-7 semanas até MVP em prod (vs 8-12 com migração)
- **−** Prompts em produção precisam de validação manual (eval suite cobre)
