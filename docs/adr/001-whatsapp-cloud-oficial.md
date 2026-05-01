# ADR 001 — WhatsApp Cloud API oficial desde o MVP

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo

## Contexto

O sistema legado (n8n) usava Evolution API / UAZAPI (não-oficiais, baseadas em Baileys). Riscos: banimento do número, instabilidade, ausência de templates HSM, problemas de compliance LGPD.

## Decisão

Usar exclusivamente **WhatsApp Cloud API oficial (Meta)** desde o MVP. Engagement fora de janela de 24h via templates HSM aprovados.

## Consequências

- **+** Estabilidade, conformidade, monitoring de quality rating, tier escalável
- **+** 1.000 conversas/mês gratuitas (Meta)
- **−** Aprovação inicial leva 24-72h (caminho crítico da Fase 1)
- **−** Templates HSM precisam aprovação Meta (24-72h cada)
- **−** Custo per-conversation fora de janela 24h
