# Feedback v2 do comando — fonte original congelada

Este incremento SQL é inativo. Acrescenta leitura e selagem para uma refeição já
gravada pelo journal; não ativa rota, escritor de domínio ou experiência do Flow.
O feedback usa somente `conversation_meal_effects.feedback_context`, capturado
opcionalmente dentro da transação original, junto aos fatos obrigatórios.

## RPCs internas

Todas exigem backend confiável, role `service_role` e READ COMMITTED. Leituras
usam um snapshot sem writes, locks de linhas, inicialização clínica ou cálculo.

`read_conversation_meal_feedback_v2(owner, command_id)` retorna:

- `available` com o primeiro feedback v2 ligado ao comando e à fonte original.
- `legacy` com o primeiro feedback v1 cujo hash corresponde à proposta original.
- `absent`, `stale_epoch` ou `event_conflict`, sem contexto privado no erro.

`read_conversation_meal_feedback_source(owner, command_id)` retorna:

- `available`, `receipt` imutável e `context` original privado do T2C.
- `unavailable`, `reason: original_context_unavailable` e o mesmo `receipt`
  factual, quando a captura opcional não existe ou não corresponde aos fatos.
- `absent` ou `stale_epoch` quando não há efeito atual acessível.

`commit_conversation_meal_feedback_v2(owner, command_id,
expected_effect_version, feedback)` usa a versão exata do recibo factual para
uma nova selagem. A identidade/epoch é cercada antes de qualquer replay. Um
vencedor existente retorna `replay` ou `legacy` antes da validação do payload ou
da versão recebida. Uma nova selagem valida `RegistrationFeedbackV2` com a mesma
shape e autoridade de fontes do T2C, recebendo exclusivamente o contexto privado
guardado. Os hashes de proposta e fonte são calculados no banco sobre esse
original, sem transportar um contexto histórico escolhido pelo cliente.

Captura opcional NULL é indisponibilidade definitiva daquele enriquecimento.
Nunca se chama a captura viva para substituí-la, nem se repete a gravação da
refeição. O recibo factual permanece disponível para informar que houve registro.
Uma versão factual incorreta retorna `source_conflict`; DTO inválido produz erro
`invalid_conversation_meal_feedback`, sem detalhes ou conteúdo privado.

## Edição, versões e retenção

Uma edição C11 pode substituir os logs vivos depois do commit e antes da selagem.
Ela não altera o contexto, os IDs, os números ou o snapshot originais usados
neste recibo. Dia atual, contadores posteriores, fuso atual e estado clínico
atual não são recapturados para essa autoridade. Uma eventual máscara clínica
atual pertence à apresentação pelo backend e não reescreve o original guardado.

A tabela v2 existente recebe `command_id` nullable, FK composta para o efeito
conversacional e unicidade por dono/comando. Inserts T2C existentes usam listas
explícitas de colunas e continuam com `command_id` NULL. O writer v1 permanece
intacto: seu fence da tabela v2 impede nova seleção de frases após o vencedor
v2. V1 já gravado impede upgrade, desde que seu hash seja o original; outro hash
é conflito. Um recibo v2 antigo sem vínculo nunca é relabelado como original.

O commit v2 genérico conserva o caminho T2C dos eventos antigos. Sob o lock
comum do dono, ele recusa eventos de comando antes de uma captura viva. O novo
commit usa a lane `workouts` → dono → epoch/comando, serializando com reset, v1
e v2 sem adquirir logs/snapshot vivos para provar o original.

A FK do efeito apaga o novo recibo quando a transição de epoch elimina as fontes
privadas, mesmo se o pending ainda existe. O guard de imutabilidade permite essa
cascata somente quando o efeito pai já não existe; mantém as permissões antigas
de cascata por pending ou exclusão da conta. Não há grants diretos de tabela ou
helper privado, inclusive para `service_role`. O BFF deve projetar somente o DTO
público validado; o contexto privado nunca integra a resposta ao aplicativo.

## Qualificação

Na qualificação local, passaram 39 assertions principais, 3 checks de READ
COMMITTED, 6 corridas entre sessões e 14 scripts vizinhos em Postgres real. Esses
casos cobrem leitura sem efeitos, fonte congelada após C11, ausência opcional,
hash/DTO/owner/epoch, rollback de selagem, primeiro vencedor v1/v2 e reset.
O ensaio de migração fresca com rollback preservou os hashes de schema e
catálogo e os dados vazios de QA; a reinstalação passou novamente nas 39
assertions. Isso qualifica o incremento SQL local e não ativa um caller público.
