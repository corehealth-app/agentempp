# Preparação durável de candidatos — integração inativa

O BFF já liga `prepareConversationMealDraft` ao journal privado por meio de
`preparePersistedConversationMealCandidate`. Ainda não há rota pública, composição
ativa ou autorização para salvar consumo. `prepared` continua sendo somente um
candidato: faltam a interpretação completa da fonte, a resolução nutricional
autorizada e sua ligação ao writer atômico.

## Fluxo e repetição

1. Validar o dono autenticado, o DTO original fechado e `cmsg1:<UUID>`.
2. Consultar primeiro o journal permanente. Candidato já persistido é devolvido
   exatamente, sem extrator, consulta de mídia, cálculo ou lease novo.
3. Admitir uma vez o comando ainda ausente. Se a resposta for perdida, reconciliar
   por leitura; não repetir a admissão cegamente.
4. Usar o cache distribuído existente apenas como lease de trabalho de dez minutos.
   Ele não é a autoridade de deduplicação permanente.
5. Preparar e anexar uma vez o envelope fechado. Ler o primeiro candidato persistido
   se houver concorrência ou resposta perdida, preservando a fonte original.

O mesmo dono/UUID com outro conteúdo conflita; um ID invalidado por reset não volta
a ser admitido. Dois consumos legítimos iguais devem receber UUIDs distintos.
O serviço de status usa apenas a RPC de leitura, sem inicializar qualquer estado.

O cache guarda somente `{command_id, candidate_attached: true}`. Não contém texto,
alimentos ou outros dados de saúde. Como esse cache reutiliza o ID da linha após a
expiração, uma tentativa antiga não consegue provar que ainda possui o lease.
Por isso este serviço não chama `fail_mobile_api_request`: falha sem resultado
persistido mantém a aquisição até expirar, evitando liberar o trabalho de outro
worker. A conclusão do cache só ocorre depois de comprovar o candidato durável.

## Evidência e limites

O codec privado valida fonte, dono, hash, versão, status, referências dos itens,
mídia e transcrição. Ele destaca os dados de aliases mutáveis e congela o resultado.
Texto e callbacks são capturados antes do primeiro await. Erros de provedor não
expõem seu conteúdo na resposta.

Áudio vazio pode produzir um esclarecimento persistente. Evidência de mídia que
excede os limites de legenda/transcrição não vira um trecho truncado utilizável:
o preparador mantém apenas SHA-256 e comprimento UTF-16. Esses resultados não podem
conter draft alimentar nem intenção de consumo apta a preparação. Pergunta ou
negação inequívoca da outra fonte permanece como resultado conversacional seguro.
O envelope completo continua limitado a 128 KiB.

## Qualificação e limitações

Os testes cobrem codec com o preparador multimodal real, troca de aliases/sessão,
reabertura, resposta perdida, conflito de entrada, reset, duas tentativas simultâneas
e aquisição expirada cujo ID foi reutilizado por outro worker.

O ensaio conectado local usa serviço BFF → SDK Supabase → REST → PostgreSQL real e contas
sintéticas. Confirmou quatro comandos/candidatos, quatro preparações, repetição
exata sem nova extração, IDs distintos para relatos iguais, isolamento entre contas
e nenhuma gravação de alimento, pending ou mensagem. As fixtures foram removidas e
a stack local foi parada, com PID ausente e portas liberadas verificados.

Esse ensaio usa contexto autenticado sintético de backend; não qualifica GoTrue,
app nativo, registro ao enviar ou TestFlight. Nenhum ambiente cloud foi alterado.
