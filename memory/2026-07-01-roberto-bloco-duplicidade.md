# Debug report — Roberto bloco incompleto + mensagem duplicada

- Data: 2026-07-01
- Status: DONE

## Sintomas

- Dia com gap de refeição recebeu aviso de que não creditava bloco 7700, mas ainda adicionou crédito.
- Mensagem única "40 minutos de musculação" gerou resposta perguntando se eram duas mensagens/sessões.

## Causa raiz

- `creditDayToBloco` ainda creditava `incomplete_no_response` quando havia déficit observado ou interação após o reminder.
- `loadContext` lia a mensagem atual já persistida em `messages` e o pipeline adicionava `input.text` novamente ao prompt.

## Correção

- `incomplete_no_response` agora retorna crédito 0 no bloco.
- `daily-closer` e `bloco-recompute` não passam mais `interactedAfterReminder`.
- O histórico do prompt exclui a mensagem cujo `provider_message_id` é o da entrada atual.
- Detector de falso positivo cobre a frase "Recebi as duas mensagens — foi uma sessão...".

## Evidência

- `pnpm --filter @mpp/core test`
- `pnpm --filter @mpp/agent test`
- `pnpm --filter @mpp/inngest-functions test`
- `pnpm typecheck`
