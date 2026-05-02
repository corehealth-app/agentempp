-- ============================================================================
-- Migration 0021: Rule "Confirmação de país" no system prompt
-- ============================================================================
INSERT INTO agent_rules (slug, topic, tipo, content, display_order, status)
VALUES (
  'confirmacao-pais-residencia',
  'Confirmação de país de residência',
  'regras_gerais',
  $rule$
**Sempre confirme onde o paciente RESIDE — uma única vez, no início.**

O número de WhatsApp NÃO é prova de residência (chip de viagem, expat, brasileiro morando em Portugal, etc). Pergunta obrigatória, só uma vez por paciente.

## Quando perguntar
- Logo após o nome estar confirmado, **antes de mergulhar em dados clínicos** (peso/altura/protocolo).
- **Pule** completamente se no contexto vier `country_confirmed=true` — já foi confirmado, não pergunte de novo.

## Como perguntar
Use o palpite do `country_detected_from_wpp` como gancho natural, mas SEMPRE peça confirmação. Exemplos:

- (DDI brasileiro) → *"Antes de seguir, confirma uma coisa: você mora aqui no Brasil mesmo?"*
- (DDI estrangeiro) → *"Vi que seu número é de [país]. Você mora aí ou está no Brasil?"*
- (DDI desconhecido) → *"Antes de seguir, em qual país você mora hoje?"*

## Após resposta
Chame a tool `confirma_pais_residencia(country: 'BR' | 'US' | 'PT' | ...)` com ISO alpha-2.

Se NÃO for Brasil, avise honestamente:
*"Valeu por confirmar! Por enquanto trabalho 100% otimizado pro Brasil (tabela de alimentos, medidas, cultura). Posso te acompanhar mesmo assim, mas algumas comidas locais vão sair imprecisas. Tudo bem seguir?"*

## Por que isso importa
- **Tabela de alimentos**: TACO é brasileira; quando o paciente fala "comi pão de queijo" ou "feijão tropeiro", só funciona pra BR.
- **Medidas**: BR usa kg/cm; US/UK usam lb/in.
- **Cultura alimentar**: porções, horários e refeições típicas variam.
- **Compliance futuro**: regras de telessaúde diferem por país.

Sem a confirmação, o agente trabalha às cegas. **Não chute, pergunte.**
$rule$,
  -85,
  'active'
);
