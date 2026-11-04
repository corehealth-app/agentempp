# Factory BFF da fonte nutricional vinculada

`createSupabaseConversationMealSourceFactory(serviceClient)` é inerte. Seu único
efeito possível começa em `capture(originalBound)`, chamado explicitamente após
a admissão no journal. Não admite comando, inicializa dia, calcula alimento ou
ativa rota/writer. Os dois RPCs usados são os reais da migração
`20261103233331_conversation_meal_atomic_writer.sql`.

Antes do primeiro await, a factory recomputa `bindConversationCommand`, confronta
o objeto original completo e conserva cópia imutável de dono, ID, hash e input.
O método SDK `rpc` é vinculado no construtor; trocar a propriedade depois não
retargeteia captura ou lookups. O dono vem do comando já vinculado pelo backend
autenticado; esta factory não transforma texto do paciente em identidade.

A captura valida envelope fechado, esquema, dono/ID/hash/input original e epoch,
conservando `source_hash` e `captured_at` armazenados pelo SQL. A cápsula congelada
expõe `action`, `sourceHash`, `capturedAt`, `epoch`, `context`, `sourceReader`,
`sourceReceipts()`, `auditSink` e `auditEvents()`. Nenhum relógio do BFF substitui
o timestamp do banco. O contexto é privado e seus valores JSON são destacados e
congelados, sem inventar `observed_at`; uma remoção silenciosa de chave pelo
decoder é recusada em vez de reescrever a fonte. Esse contexto **não** é `CurrentClinicalAuthority` nem
feedback público. Validação clínica/semântica mais profunda pertence ao futuro
preparador e não é autorizada pela presença desse JSON.

`sourceReader.ownerId`, `asOf` e closure de leitura são imutáveis. `read` chama
somente `read_conversation_meal_nutrition_source`, passando o tipo e nome original
sem trim, normalização ou tradução para outro lookup. Linhas usam DTO fechado:
UUIDs, dono, referência segura, números finitos ou NULL, proveniência confiável,
join de verificação, timestamp civil válido, janela de 30 dias e limites 50/20.
Ordem e IDs duplicados são verificados. A janela usa precisão de nanossegundos
para não aceitar uma linha um microssegundo após o cutoff. `as_of` deve ser a
string exata de `captured_at`; não é renormalizado para outro texto equivalente.

Todo retorno válido entra no coletor `{id, hash}`, inclusive MISS. Repetir o
mesmo lookup exige os mesmos ID, hash e linhas; um ID não pode representar dois
lookups diferentes. O snapshot do coletor é congelado e sem duplicatas. Uma
falha de leitura interrompe o cálculo; o futuro preparador não pode ignorá-la e
usar apenas o subconjunto anterior de recibos. O SQL continua conferindo o
conjunto completo e reexecutando as fontes antes de preparar/gravar.

O sink de auditoria está sempre disponível e guarda somente intenções em RAM,
destacadas e vinculadas ao dono, para os três eventos existentes do calculador.
Não há insert em `product_events`. O futuro caller deve fornecer **ambos**
`sourceReader` e `auditSink` em `MealCalculationOptions`; omitir o sink continua
sendo o comportamento legado do calculador e não é a integração nova.

Refusals conhecidos são `MobileApiError` redatados, sem causa/detalhes SQL:
`conversation_meal_source_<action>`/409 para absent, stale epoch, dia fechado,
fonte ausente/conflitante ou lookup selado; busy/503 para SQLSTATE 55P03;
conflict/409 para 40001; demais erros ou DTOs inválidos usam unavailable/503.
Não há retry automático, consulta de história viva, fallback de cálculo ou
efeito público. Os nomes de erro são privados desta integração ainda dormente.

Os tipos SDK incluem somente as duas assinaturas existentes: captura com dono e
comando; lookup com dono, comando, tipo textual e nome explicitamente NULL ou
texto. Nenhuma migração, grant ou instalação de dependência é necessária aqui.

Verificação local usa RPC mockado, testes de contrato/journal/preparação vizinhos,
typecheck de admin/db e lint dos arquivos novos. A prova integrada com SDK/REST e
SQL reais, autoridade semântica, preparação/commit, selagem de feedback e ativação
continuam gates separados sob coordenação do orquestrador.
