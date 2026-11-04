# Interpretação persistente de um comando de refeição

O serviço privado `interpretPersistedConversationMeal` compõe o journal, a captura original e a interpretação semântica. Não instala rota, flag ou transporte iOS. Não calcula nutrição, grava consumo, concede XP ou publica mensagens.

A entrada continua sendo o comando fechado `conversation.command.v1`, vinculado ao dono autenticado e ao ID permanente. A mesma identidade com outro conteúdo é recusada. Um resultado já persistido retorna antes de admissão, captura ou chamada ao provedor. Listas nominais chegam ao intérprete completo; não passam pelo gate verbal ou pelo extrator de candidatos antigos.

## Permissão para uma tentativa

Somente uma resposta **nova** `claimed` de `start_conversation_meal_semantic_attempt` autoriza a chamada física. O banco cria o ID da tentativa, com epoch, versão do intérprete e hash da fonte. Ler `started`, renovar um cache HTTP ou reenviar o comando nunca recria essa permissão. Não há TTL, reclaim ou retry do provedor nessa composição.

Se a resposta do start se perder, o serviço apenas lê o estado. Se a resposta do commit do resultado se perder, também apenas lê: não repete o commit nem a interpretação. Uma falha da interpretação tenta registrar o marcador genérico `provider_outcome_unknown`, sem guardar texto privado do erro. O estado incerto exige reconciliação; não é apresentado como refeição salva.

O orçamento recebido do backend é limitado a 45 segundos e inclui o tempo já gasto na admissão e captura. O leaf do provedor aplica o tempo restante, `maxRetries: 0`, limite explícito de saída e ausência de ferramentas. O orquestrador não transforma uma exceção ou um timer em nova tentativa paga.

## Transporte e autoridade

`createSupabaseConversationMealSemanticStore` só usa os quatro RPCs de tentativa/resultado. Os callbacks e comandos são destacados antes do primeiro await. As respostas são fechadas, vinculadas ao dono/comando/hash/tentativa; o resultado completo é imutável. O hash numérico retornado pelo PostgreSQL é um token opaco: a serialização decimal de JSONB pode diferir da notação exponencial do JavaScript.

A interpretação é um julgamento sobre as fontes originais, com referências verificáveis. Não é prova física de consumo nem, sozinha, a autorização de gravação SQL. A composição futura do writer precisa resolver os alimentos, preservar quantidades e cobertura, conferir os recibos das fontes e respeitar a versão/dia aberto e as proteções clínicas. O modelo nunca fornece metas, calorias oficiais, dono, epoch ou comandos de domínio.

O resultado histórico preserva os fatos originais. A futura timeline pública ainda precisa aplicar a apresentação clínica atual separadamente. Este serviço não afirma entrega no TestFlight, execução por usuário real ou aprovação do Roberto.
