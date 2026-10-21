# Fronteira de revisão do treino no app

A migration `20261015115000_mobile_workout_registration_boundary.sql` prepara a
fronteira de revisão do produtor de treino. A migration
`20261015160000_mobile_workout_registration_mutations.sql` acrescenta edição e
cancelamento por revisão. O BFF tem o caminho explícito `ui-v1` descrito abaixo,
desativado por padrão. Swift, cutover e QA integrado continuam obrigatórios
antes da ativação. Não habilita o Flow ou o legado de WhatsApp.

## Origem e dados históricos

A admissão continua no journal privado de
[propostas móveis](mobile-workout-proposal-authority.md). `content_revision` e
`confirmed_lifecycle_key` são nullable, sem default ou backfill. Admissões
anteriores mantêm NULL e nunca são promovidas em um retry. A nova admissão usa
`wui1:<UUID>` literal: o prefixo é minúsculo; os dígitos hexadecimais podem variar
em case, sem normalização. Ela nasce com revisão zero na mesma transação.

O pending original recebe `workout_ui_admission_id`, com FK composta pelo
owner. A materialização real S16 vincula a admissão e o pending; o wrapper
marca esse pending na mesma transação. Falhar após o vínculo ou após o marker
reverte a operação inteira. Um replay exige o marker existente; não o repara.
A ausência posterior do pending conserva o histórico e não cria substituto.

`mobile_workout_registration_edit_receipts` reserva receipts owned de edições
aceitas, com revisão sucessora e hash do input. Os testes da fronteira S17B
inserem receipts sintéticos para exercitar o detector; os testes das mutações
executam edições reais sobre admissões/materializações reais.

## Edição e cancelamento por revisão

As duas RPCs novas são DEFINER, VOLATILE, owner postgres e search_path restrito
a pg_catalog. Somente o backend tem EXECUTE; o guard backend real precede os
argumentos. Exigem READ COMMITTED. Não criam tabelas, colunas ou lifecycle, não
chamam os writers de treino e não recalculam calorias.

A ordem é advisory workouts → usuário ativo FOR NO KEY UPDATE → epoch →
admissão → pending original FOR UPDATE. O journal owned localiza a admissão
por pending histórico, sem usar o marker como prova. Admissão ausente,
ambígua ou com revisão NULL é inválida; epoch antiga precede pending removido.
Depois do rowlock, o marker deve corresponder à admissão e o pending original
deve existir. Lifecycle não NULL com status diferente de confirmed é inválido.
Negativos de autoridade retornam somente status/reason, sem dados do registro.

`edit_mobile_workout_registration(owner, pending, expected_revision, key,
input, proposal)` aceita key literal `wue1:<UUID>`, distinta da criação `wui1`.
Preserva case dos dígitos e usa collation C. Uma key de outra admissão do mesmo
owner, inclusive de outro epoch ou ainda sem pending, conflita. Outro owner
mantém seu domínio independente. O domínio amplo do produtor S16 permanece.

Um receipt existente compara o hash S16 do input e a revisão esperada, sem
validar a proposta recalculada. Seu replay retorna o receipt original e a
projeção atual: depois de 0→1→2, o primeiro retry retorna receipt 0/1 com
conteúdo/revisão 2. Não renova validade, reverte conteúdo nem recria pending.
Sem receipt, a precedência é confirmed, outro terminal, revisão divergente,
timestamp vencido, colisão da key, validação do candidato e limite de revisão.

A nova edição valida os mesmos doze campos do candidato S16; somente o
provider passa a ser a key EDIT. Mantém a truncagem de submilissegundos do
builder JS quando performed_at foi informado. Atualiza somente proposta e
validade do mesmo pending, incrementa a revisão e insere um receipt de seis
campos, atomicamente. A validade é clock_timestamp após os locks mais 24 horas
transcorridas. Revisão 2147483647 recusa nova edição; receipts aceitos que
chegaram a esse limite ainda podem ser repetidos.

`cancel_mobile_workout_registration(owner, pending, expected_revision)` recusa
confirmed antes da revisão; depois verifica revisão, cancelled e demais
terminais. Cancelled na mesma revisão é replay. Pending com timestamp vencido
continua cancelável, como no serviço existente. Só status e resolved_at mudam;
conteúdo, validade, revisão e receipts permanecem.

Os resultados incluem a mesma projeção interna de oito campos, `ui-v1`, e,
para edição aceita/repetida, o receipt requestKey/expectedRevision/resultRevision.
Conflitos owned incluem projeção atual sem receipt. Exceções de persistência
propagam e revertem toda a chamada; não são convertidas em sucesso parcial.

O serviço BFF sonda o receipt antes de calcular e aplica a whitelist HTTP ao
proposal raw. Isso permite recuperar a edição aceita mesmo se o recálculo
posterior estiver indisponível ou peso/horário tiverem mudado. A RPC SQL isolada
não demonstra a integração do cliente ou sua apresentação.

## Único cálculo e gravação

O corpo literal dos 13 argumentos de `register_workout_atomic` foi copiado para
uma função privada INVOKER, sem mudar cálculos, defaults ou retorno. O corpo
strength S8 foi movido para outra função privada, mudando somente esse callee.
Ambas são exclusivas do owner. Os OIDs públicos permanecem.

Os wrappers públicos executam o guard backend real e exigem READ COMMITTED.
O de 13 argumentos adquire `:workouts` em um statement e consulta a proteção
em outro, após a espera, antes de qualquer UPSERT de snapshot. O strength
mantém a ordem catálogo SHARE → `:workouts` e consulta a key congelada do
command exato antes do replay F1 ou da deduplicação. A confirmação CAS dormente
chama a seam privada somente depois de verificar sua autoridade.

Uma key pertence à revisão quando sua admissão tem revisão não NULL e
`pending_id` histórico não NULL. O detector considera a key inicial e as keys
de receipts EDIT aceitos. Não depende do status, da epoch atual, do tipo de
treino nem da presença atual do pending. Colisão recusada sem vínculo e
admissão S16 histórica com revisão NULL conservam o caminho legado.

A mesma transação retira somente INSERT/UPDATE diretos de `workout_logs` do
`service_role`, preservando SELECT/DELETE, e retira seu EXECUTE nas duas RPCs
S16 antigas. Os novos wrappers as reutilizam como owner. O preflight recusa
privilégios inesperados por coluna, PUBLIC, roles herdadas ou acesso ao owner;
não corrige grants alheios silenciosamente.

## Pending e leitura

O trigger INVOKER não adquire advisories ou locks de usuário depois do row
lock. Operações externas não atribuem/apagam/trocam marker e não alteram um
pending protegido, mesmo que seu marker esteja NULL por corrupção. Permite
somente pending → cancelled/expired com `resolved_at` finito e todos os outros
campos idênticos. Pendings legados sem proteção preservam INSERT e UPDATE do
BFF/WhatsApp, incluindo edição, confirmação e link da mensagem.

O predicate DEFINER do trigger concede ao backend apenas um booleano owned;
nenhuma tabela privada recebe DML. A execução como postgres é uma capacidade
ACL das seams, nunca prova CAS. Não há GUC, flag ou contexto como autorização.

A followup `20261015150000_mobile_workout_registration_trigger_visibility.sql`
move esse predicate para `public`, preservando OID, corpo, owner e ACL de
EXECUTE somente para postgres e service_role. O trigger continua INVOKER e
troca apenas as três referências ao predicate. Não concede USAGE em
`private` nem muda os grants dos schemas. Isso permite resolver a função em
uma conexão nova do backend; EXECUTE na função, sozinho, não dava acesso ao
nome no schema privado. Não introduz um caller no aplicativo.

A presença anterior de USAGE em `private` também é compatível e deve ser
preservada: as migrations `20260720220813` (coach) e `20260722172407` (rotina)
já concedem essa capacidade ao backend. A followup não exige que ela esteja
ausente, não a revoga e compara os dois schemas integralmente antes/depois.
Mantém as verificações exatas de owner, corpo, OID, dependências e EXECUTE
das duas funções; acesso adicional de `anon` ou `authenticated` continua
recusado. Assim, não retira uma capacidade usada pelos caminhos antigos.

`mobile_workout_registration_visibility_schema_usage.sql` reproduz essa
compatibilidade no prefixo real completo até `20261015115000`, antes da
followup. O controlador local fornece `visibility_payload` com o DO literal
da migration, sem seu BEGIN/COMMIT, pois o teste possui a transação e sempre
faz ROLLBACK. `with_private_usage=true` exige o grant real da cadeia;
`false` o retira somente dentro do teste. Ambos devem preservar os schemas,
as funções e a chamada booleana sob `service_role`. O negativo
`reject_extra_execute=true`, com USAGE false, deve falhar com o erro exato
`42501/mobile_workout_registration_visibility_acl_drift`; o controlador
confere o catálogo em uma nova conexão após o término do backend. Os testes
antigos com alvo C5 explícito continuam cobrindo o baseline sem USAGE, sem
alterar seus guards. Esses checks SQL não provam autenticação JWT ou HTTP.

`get_mobile_workout_registration(owner, pending)` usa um SELECT para obter
conteúdo e revisão no mesmo snapshot: usuário ativo, epoch atual, admissão
owned com revisão, pending original e marker exato. Retorna `ui-v1` e os campos
já persistidos. Qualquer vínculo ausente devolve `invalid_admission`. Não
reabre pending, cria lifecycle ou autoriza gravação. O proposal raw é interno;
o DTO HTTP aplica a whitelist existente.

## Limites e verificação

O modo OFF continua sem factories ou RPCs novas no BFF. A proteção negativa
dentro dos writers existentes é sempre aplicada no banco. Ela também afeta o
caminho compartilhado com o WhatsApp; suas operações legadas sem membership
precisam continuar funcionais. Provider NULL/trocado não prova origem; não se
infere origem por texto. Não há garantia contra owner com SQL arbitrário ou
service adversarial que invente uma intenção sem vínculo.

A suíte `supabase/tests/mobile_workout_registration_boundary.sql` usa as RPCs
reais, roles efetivas, preservação de estado e rollback. O driver correspondente
exercita quatro corridas COMMIT/ROLLBACK contra os dois writers, com bloqueio
real em `:workouts`. Os probes locais isolados verificam o preflight literal
para grant de coluna e membership inesperada. Esses testes não substituem a
integração BFF/Swift, a revisão CAS ou a validação no iPhone. Status e evidências
de execução são registrados no diário operacional, não inferidos deste texto.

`supabase/tests/mobile_workout_registration_trigger_permissions.sql` mantém o
mesmo teste positivo antes e depois da followup, em dois backends novos. Cobre
INSERT/EDIT legados com proposta, validade e demais dados exatos, primeiro sem
operação anterior e depois de um INSERT real pelo owner. Os dois cenários
exigem sucesso, rollback integral e ausência de USAGE em `private` para o
service_role; uma falha anterior não é convertida em resultado esperado.

`supabase/tests/mobile_workout_registration_mutations.sql` define 45 checks
sequenciais: Natação 40→45, replay após revisão 2, cancelamento, validação,
autoridade, keys históricas, overflow e rollback após gravações reais. Inclui
uma admissão vizinha real ainda sem pending e verifica a proteção dos writers
13/S8 após EDIT aceito seguido de reset/DELETE. O driver de mutações define
16 corridas reais com COMMIT/ROLLBACK, terminal legado, reset, DELETE e relógio
cruzando a validade enquanto a row está bloqueada. A janela de teste é armada
uma vez antes do segundo ator; não rearma o FK depois do bloqueio. A execução
e os resultados pertencem ao diário operacional; a existência desses testes
não demonstra integração ou disponibilidade do beta.

## Confirmação UI atômica dormente

`confirm_mobile_workout_registration(owner, pending, expected_revision,
legacy_arguments, catalogue_observation, catalogue_decision)` é exclusiva do
backend e acrescenta uma função, sem alterar os corpos 13/S7/S8 ou fórmulas.
O caller BFF exige protocolo/revisão e a configuração específica do projeto;
o cliente Swift e a ativação ainda são etapas separadas. Catálogo SHARE precede `:workouts`,
usuário, epoch, todas as admissões owned, pending sem filtro de status e vida.
A validade usa relógio DB depois dos locks; respostas antigas não autorizam
uma confirmação de outra revisão.

O provider da revisão zero é a key inicial. Nas demais revisões, deve existir
receipt EDIT owned com a mesma key literal e a revisão resultante atual. Não
se reconstrói o hash do input a partir do proposal. A operation key é derivada
pelo servidor: `ui:<admission UUID>:r:<revision>`, com tipo original literal.
O preparo escolhido pelo S7 deve corresponder ao owner, tipo, duração,
intensidade, provider atual e instante absoluto; replacement UI é false/NULL.
O JSONB original permanece inteiro, incluindo escala numérica e NULLs.
Calorias, metas, notes e data são do primeiro preparo oficial atual: não são
forçadas aos valores antigos do preview, nem recalculadas pelo SQL ou retry.

Sem preparo existente, SQL NULL retorna `preparation_required` sem criar vida.
A vida existente precisa estar provada e aberta no ponteiro atual; vida órfã
não é adotada. Se nenhuma vida existe, a criação e o ponteiro pertencem ao
mesmo bloco transacional que S7, captura real S8, vínculo da admissão e status
confirmed/resolved_at. A UI não fabrica mensagem IN nem admissão Flow.

Uma negativa JSON legítima do S8 desfaz todo esse bloco antes de retornar
`capture_not_accepted`, com rascunho inalterado e wire real da captura. O sinal
privado P17D0 só é consumido quando marcado localmente para essa negativa;
erros de writer, constraints e P17D0 externo propagam e revertem a operação.
O sucesso prova operation owned, resultado legado armazenado e resolver real.
Preserva as quatro resoluções e o gap legado legítimo, sem inventar um novo
workout/fact/snapshot para dedup, nem reclassificar ou fazer backfill.

Uma confirmação já persistida exige revisão, vínculo da vida original,
ponteiro e operation existentes. Recupera somente o resultado original e o
fact atual pelo resolver, inclusive resposta S9 posterior. Não entra novamente
no writer, não renova clocks e ignora preparo/catálogo novos ou inválidos.
Binding ausente, tombstone ou vida obsoleta não autorizam recriar a captura.
O DTO/whitelist e a apresentação desses resultados ainda pertencem à integração.

`mobile_workout_registration_confirmation.sql` define 39 checks sequenciais,
incluindo os vínculos 13, recuperação, dedups/X26, precisão e falhas após cada
gravação. X26 por padding cobre a compatibilidade do core pelo Flow/S7/S8
reais: a admissão UI rejeita tipo com espaços nas pontas, e essa rejeição também
é exigida sem efeitos. Não se fabrica uma confirmação UI para alcançar X26.
Seu driver define 19 corridas reais, com catálogo primeiro, relógio
cruzando validade, reset/DELETE e confirmação/edição/cancelamento. As fontes
foram congeladas e revisadas antes do body; execução e evidências pertencem ao
diário operacional. Isso não constitui aceite do beta ou publicação.

## Adapter de backend, sem ativação

`apps/admin/src/lib/mobile-api/workout-registration-repository.ts` reúne as
seis RPCs de admissão, materialização, leitura, edição, cancelamento e
confirmação. A construção é lazy: não lê o port, cria cliente, consulta banco
ou ativa flag. O serviço e as rotas abaixo o usam somente no caminho explícito
habilitado por configuração. O caminho legado recebe apenas o guard negativo
para recusar um marker protegido sem revisão. O WhatsApp não foi alterado.

O adapter conserva owner, key literal, revisão esperada e os valores de cada
tentativa. Valida a projeção única `ui-v1`, o ID solicitado e o receipt EDIT
original, aceitando a revisão atual posterior no replay. Materialização e
edição com candidato SQL NULL podem retornar o sinal interno
`preparation_required` somente para a exceção exata
`22023/invalid_mobile_workout_proposal_candidate`. Com candidato real ou outro
erro, a falha propaga. A confirmação conserva o resultado SQL, inclusive
`capture_not_accepted`; essa negativa nunca é convertida em falta de preparo.

`toWorkoutRegistrationDto` usa uma lista fechada com protocolo/revisão e a
whitelist existente do proposal. Admission, provider, raw_args, hashes,
argumentos13 e capture não entram nessa projeção HTTP. O capture permanece
JSON interno, sem reinterpretação de calorias ou classificação: sua prova é
feita pela transação SQL e pelo resolver. Validar o formato não prova origem
no banco e não substitui a autenticação do futuro caller.

Os testes do adapter cobrem os parâmetros das seis RPCs, probes e erros
exatos, owner/ID/revisão/receipt, replay e whitelist. São testes com port
controlado, sem PostgreSQL ou HTTP. A preservação do formulário e a ligação da
tentativa à sessão no iOS continuam parte da integração antes de ativar.

## Serviço e rotas versionadas do app

`workout-registration-service.ts` e `registration-handlers.ts` ligam as seams
às rotas existentes. O novo `GET /registrations/:id` recupera uma projeção
owned; os wrappers continuam passando pela autenticação e pelo entitlement.
`/pending` usa a mesma leitura owned, obtendo a projeção oficial de cada row
protegida quando o recurso estiver habilitado. Se essa projeção for recusada
ou tiver virado terminal, não há fallback para um DTO legado daquela row.

O opt-in é explícito por intenção: `workout_protocol: "ui-v1"`, mais
`expected_revision` na edição, confirmação e cancelamento. A criação mantém
os campos atuais de workout; a edição acrescenta a revisão. Confirmação e
cancelamento recebem somente protocolo/revisão. Corpo ausente nessas duas
rotas mantém o contrato legado; JSON presente inválido não vira ausência.
Esses metadados entram no hash HTTP, mas são retirados do input enviado ao
hash SQL S16. Owner, proposal calculado, argumentos13 e authority não vêm do
cliente. A key HTTP é o UUID literal da tentativa; o servidor acrescenta
`wui1:` ou `wue1:` sem gerar outro UUID ou normalizar seu case.

`MOBILE_WORKOUT_REGISTRATION_PROJECT_REF` precisa listar o ref da URL
Supabase configurada; ausente significa OFF, e a produção antiga é sempre
recusada. OFF retorna 503 para a intenção versionada antes de acessar o port
ou preparar dados. Os endpoints legados continuam disponíveis. O guard de
compatibilidade lê o marker opcional sem exigir uma coluna nova de servidores
anteriores à migration: `select('*')` interno, saída sempre por whitelist.
Marker não NULL recusa o caller legado antes de status/tool/UPDATE, inclusive
quando o switch estiver OFF. É somente um guard negativo; marker NULL por
corrupção do owner não prova ausência de membership ou permissão CAS.

Na criação, a admissão real precede até o claim/cache HTTP. A closure da
mesma admissão materializa ou recupera o UUID original. No replay HTTP de
qualquer operação UI, `refreshReplay` reapresenta a mesma intenção/revisão/key
às seams duráveis para devolver a projeção atual. Não renova a validade ou
troca silenciosamente a revisão do comando. O cache legado mantém sua regra.

A confirmação começa com argumentos13/observação/decisão SQL NULL. Replay
confirmado não exige cálculo ou catálogo novo. `preparation_required` permite
usar o preparo oficial extraído existente e o observer real. Um command S7
existente, ainda sem capture e recusado no primeiro probe com a negativa
exata `capture_not_accepted`/`forbidden invalid_authority`, permite apenas uma
observação e repetição com13 ainda NULL. Nenhuma outra negativa ou erro é
interpretado como falta de preparo, e nenhuma recusa cai no writer legado.

Conflitos owned incluem somente a projeção sanitizada em
`error.details.registration`; authority recusada não inclui registro ou IDs
privados. EDIT devolve o receipt original explícito junto da projeção atual.
CONFIRM conserva `already_confirmed` e `deduped`; capture e seus dados internos
não saem no DTO. O kcal do proposal continua sendo o preview estimado:
`legacy_result.exercise_calories` é total diário e não o substitui.

Os testes de serviço usam o adapter real com port controlado; os de handlers
usam o executor HTTP de idempotência real com store controlado. Os três casos
de interoperabilidade executam o builder e o preparador reais para Natação40,
incluindo70kg/moderada,82kg/alta e fallback70kg, sem chamar writer. São evidência
local; execução HTTP real, iOS, cutover e QA físico não são inferidos deles.
