# Mídia conversacional privada v2 — descarte no staging

Estado deste documento: implementação local; não comprova ativação no servidor.

O transporte alternativo para reduzir execuções vazias está descrito em [Limpeza de mídia no Supabase de staging](conversation-media-maintenance-bridge.md). A troca depende da qualificação hospedada; nenhuma configuração deste documento, sozinha, comprova essa troca.

## Identidade e limites

- Banco permitido: `xitugspwfxkcluxvrdeg`, URL exata HTTPS, com `/` final opcional.
- Worker permitido: `INNGEST_FUNCTION_SET=media-conversation-staging`.
- Opt-in de limpeza: `MOBILE_CONVERSATION_PRIVATE_DISPOSAL_ENABLED=true`.
- A limpeza independe de `MOBILE_CONVERSATION_PRIVATE_CATALOG_ENABLED` e de `MOBILE_CONVERSATION_PHOTOS_ENABLED`. Desativar novos envios/interpretação não encerra a obrigação de descarte das mídias já aceitas.
- As sete migrations de catálogo/lifecycle/captura/descarte/routing/admission guard/owned disposal precisam estar aplicadas e conferidas antes de ativar esse worker. Não usar `db push` amplo.

## Jobs e exclusão de conta

`conversation-private-media-retention-cleanup` roda a cada 15 minutos, com concorrência 1, uma tentativa adicional e um único lote de até 100 obrigações por execução. O lote seguinte fica para a próxima execução. A seleção e a prova de elegibilidade pertencem ao SQL, não ao modelo de IA.

Com a limpeza habilitada, o conjunto conversacional substitui somente o callback de `user-deletion-purger` pelo coordenador privado, mantendo o mesmo ID, agenda e carência de uma hora. Não registra dois purgadores concorrentes. A ordem é: prontidão privada, prontidão conversacional legada, prontidão das fotos de reavaliação e exclusão existente. Uma resposta negativa preserva a conta para outra visita. Falha privada nunca aciona fallback legado.

O SDK relê o controle de ativação antes e depois de cada RPC e operação de Storage. O coordenador da conta também o relê nas fronteiras das operações existentes. A retirada da autorização interrompe os próximos efeitos; operações já concluídas não são repetidas como compensação.

Os conjuntos de produção, `media-staging` e `media-clinical-staging` permanecem como antes. A flag desligada conserva o conjunto conversacional anterior.

## Objetos, histórico e capacidades pendentes

O protocolo remove apenas a versão observada do objeto privado e instala, sem upsert, um marcador de zero bytes. Verifica a presença desse marcador antes de reconhecer o descarte. Repetir a limpeza preserva o marcador e não regrava o conteúdo. Uma capacidade de upload ainda desconhecida não é declarada drenada.

A exclusão da conta desanexa o catálogo privado somente após essa prova. Permanecem as obrigações técnicas, os tickets pendentes, a reserva de identidade e os marcadores aprovados. O namespace `conversation-v2/` nunca é espelhado no catálogo público; os leitores e removedores antigos não obtêm esses paths. Mídias antigas de origem incerta e as regras anteriores de retenção continuam preservadas. As refeições e os recibos congelados não são reescritos pelo descarte de uma mídia.

## Ativação e retirada

Antes de permitir uploads privados, conferir as sete migrations, os buckets privados e sem versionamento, a ausência de políticas diretas de escrita do cliente e o registro efetivo dos jobs no ambiente Inngest isolado. Qualificar a API real de Storage: remoção condicional, marcador sem upsert, concorrência com assinatura tardia, isolamento de contas e repetição após exclusão de conta. Testes locais com HTTP sintético não substituem essa conferência.

Para suspender novos processamentos, desligar o catálogo/interpretação e manter o descarte habilitado no worker já qualificado. A desativação da própria limpeza exige uma alternativa operacional comprovada para as obrigações pendentes; retirar o job do registro não elimina essas obrigações. Não trocar o alias atual nem a versão do iPhone antes da qualificação do candidato.

São usados o worker e o Storage existentes, sem novo provedor ou projeto. A agenda consome o runtime normal do plano atual; não cria infraestrutura recorrente dedicada.
