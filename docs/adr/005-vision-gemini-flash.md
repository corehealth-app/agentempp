# ADR 005 — Gemini 2.0 Flash via OpenRouter para vision

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo

## Contexto

Sistema legado usa GPT-4o ($2.50/$10 per M tokens) para análise de fotos de refeição. Custo por imagem: ~$0.003. Para 1.000 usuários e ~90 imagens/usuário/mês, custo: ~$270/mês.

## Decisão

Usar **Gemini 2.0 Flash** via OpenRouter ($0.075/$0.30 per M tokens). Custo por imagem: ~$0.0003. Para mesma carga: ~$30/mês.

## Consequências

- **+** Custo cai ~90% (~$240/mês economia a 1k usuários)
- **+** Qualidade comparável em PT-BR para identificação de comida brasileira
- **+** Mesma conta OpenRouter (não adiciona provider)
- **+** Structured output nativo (JSON mode)
- **−** Modelo mais novo, menos histórico em produção
