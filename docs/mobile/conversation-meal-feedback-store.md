# Adapter BFF de feedback original do comando

`createSupabaseConversationMealFeedbackStore(serviceClient)` é inerte. Vincula
o método SDK no construtor e usa somente as três RPCs de comando da migração
`20261104010224_conversation_meal_frozen_feedback_v2.sql`:

- `readSource(originalBound)` chama `read_conversation_meal_feedback_source`.
- `readReceipt({command, receipt})` chama `read_conversation_meal_feedback_v2`.
- `commit({command, receipt, feedback})` chama `commit_conversation_meal_feedback_v2`
  com a versão factual exata e o JSON proposto.

Cada operação é explícita e faz uma chamada, sem composição de serviço, retry
automático, consulta genérica T2C, captura viva, diário, domínio ou analytics.
O caller já deve possuir o comando autenticado/admitido e o recibo obrigatório
real do writer SQL ou de sua leitura de efeito; não recebe esses objetos de um
body mobile. Forma JSON sozinha não comprova proveniência.

Antes do await, o adapter recomputa e confronta o Bound inteiro, destaca seus
valores e valida o recibo factual fechado `conversation.meal-effect.v1`. Dono,
comando, hash original, provider exclusivo, refeição selecionada, data/fuso,
timestamp, registro, IDs únicos de logs e `cmeal1:<hash>` permanecem vinculados.
Objetos retornados são destacados e congelados. Nenhum campo privado é incluído
no recibo factual.

Uma fonte disponível passa pelo `parseFeedbackV2Capture` existente, com os fatos
e parser v2 oficiais. O adapter confronta o contexto preservado, comando declarado
na proposta, provider/timestamp/fuso/refeição, registro e conjunto de logs com o
recibo. Uma remoção silenciosa de chave pelo decoder é recusa, não reescrita.
`originalObservation` é contexto histórico privado; sua informação clínica não
é autoridade clínica atual nem apresentação pública. Não se inventa `observed_at`
ou máscara atual. A apresentação futura deve ter sua autoridade própria sem
alterar o original.

Quando a captura opcional original é NULL, SQL retorna `unavailable` com
`reason: original_context_unavailable` e o mesmo recibo factual. O adapter conserva
esse resultado; nunca recaptura para substituir o enriquecimento ausente nem
repete o registro da refeição. Um envelope `available` malformado/NULL é recusado.

As leituras preservam `absent`, `stale_epoch`, `event_conflict`, v1 `legacy` e v2
`available`. O v1 é validado pelo parser histórico existente e não é promovido.
O v2 também vincula data, refeição e IDs de logs ao recibo factual. Toda leitura
consulta SQL novamente; nenhum cache local contorna o fence de epoch.

O commit valida somente transportabilidade JSON antes da RPC. Não faz uma leitura
de fonte nem valida antecipadamente o DTO v2, preservando a ordem SQL: epoch,
primeiro vencedor v1/v2, depois versão/payload de uma nova selagem. Assim `replay`
e `legacy` podem vencer um payload NULL/inválido ou versão factual divergente.
`committed` exige retorno v2 válido, vinculado ao recibo e igual ao JSON enviado.
Refusals fechados `source_conflict`, `event_conflict`, `absent` e `stale_epoch`
permanecem explícitos. Unavailable deve trazer o mesmo recibo completo.

Falhas SQL/transporte/DTO viram `MobileApiError` 503 com código
`conversation_meal_feedback_unavailable`, sem mensagem privada, causa ou detalhes.
Após resultado de commit desconhecido, o caller deve usar somente `readReceipt`;
não repetir selagem automaticamente e jamais repetir o writer do domínio.

Este leaf não ativa rota, capacidade, source público, feedback público ou serviço
do Flow. SDK/REST + SQL integrados são um gate do orquestrador; os testes locais
usam mocks RPC, parsers reais e regressões v1/v2. Mascaramento clínico atual,
envelope terminal do Flow e composição de serviços ficam para o próximo passo.
