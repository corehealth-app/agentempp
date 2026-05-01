# ADR 004 — TTS híbrido: ElevenLabs + Cartesia

- Status: Accepted
- Data: 2026-05-01
- Decisores: Eduardo

## Contexto

ElevenLabs entrega a voz custom do Dr. Roberto Menescal (voice_id `oArP4WehPe3qjqvCwHNo`), parte da identidade da marca. Mas custo é alto: ~$3.930/mês para 1.000 usuários ativos a 22M chars/mês.

## Decisão

Estratégia híbrida:
- **ElevenLabs** apenas para mensagens-âncora (15% do volume): boas-vindas, resumo diário, conquistas grandes (badges, blocks completos), reavaliação quinzenal.
- **Cartesia Sonic** para mensagens operacionais (85% do volume): confirmações de refeição, avisos de progresso, respostas curtas.
- **Cache de TTS por hash do texto** com hit rate típico de 30-40% (frases recorrentes).

## Consequências

- **+** Custo cai ~61% vs ElevenLabs puro: de ~$3.930 para ~$1.525/mês a 1k usuários
- **+** Identidade de voz preservada nos pontos críticos da experiência
- **+** Cartesia tem latência <150ms (excelente)
- **−** Lógica de roteamento de TTS adiciona complexidade
- **−** Dois providers para gerenciar
