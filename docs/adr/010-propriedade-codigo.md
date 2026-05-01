# ADR 010 — Propriedade do código e responsabilidades

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo + CoreHealth

## Contexto

Definir formalmente propriedade do código, custos de operação e responsabilidades durante e após o desenvolvimento.

## Decisão

| Item | Responsável |
|---|---|
| Propriedade do código | CoreHealth (work-for-hire) |
| Repositório | `corehealth-app/agentempp` (GitHub Org do cliente) |
| Custos de APIs (Supabase, OpenRouter, etc) | CoreHealth |
| Desenvolvimento | Eduardo (gestao-hub), único dev |
| Manutenção pós go-live | Eduardo, com acesso permanente |
| Resposta a incidentes em prod | Eduardo |
| Handover ao cliente | Treinamento ao final + documentação completa |

## Consequências

- **+** Cliente é dono do produto
- **+** Eduardo mantém continuidade técnica via contrato de manutenção
- **−** Single point of failure (Eduardo) — mitigado por documentação extensa em `docs/runbook/` e treinamento ao cliente
