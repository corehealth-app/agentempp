# ADR 007 — Cálculos e roteamento determinísticos em código, não LLM

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo

## Contexto

Decisões críticas (qual protocolo aplicar, cálculo de calorias da refeição, atualização de XP/streak/blocks) não devem depender do LLM. Razões: precisão, reproducibilidade, auditabilidade, debug, custo.

## Decisão

Toda lógica determinística vai para `packages/core` em TypeScript puro, com testes unitários (Vitest):

- `protocol-router.ts` — decisão de protocolo (BF/IMC + treino) → recomposição/ganho/manutenção
- `progress-calc.ts` — XP, level, streak, blocks 7700, badges
- `nutrition.ts` — BMR (Mifflin/Katch-McArdle), TDEE, déficit, conversões TACO

LLM é usado **apenas** para:
- Conversação natural
- Identificação de itens em foto (vision)
- Classificação de intent
- Formatação de resposta

## Consequências

- **+** Testes unitários cobrem regras críticas
- **+** Mudanças em fórmulas via PR + diff
- **+** Resultado idêntico para mesma entrada (sem variação de LLM)
- **+** Custo de LLM cai (LLM não precisa raciocinar sobre cálculo)
- **−** Mais código em `packages/core` para manter
