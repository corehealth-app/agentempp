# Fronteira de revisão do treino no app

A migration `20261015115000_mobile_workout_registration_boundary.sql` prepara a
fronteira de revisão do produtor de treino. Ainda não habilita callers no BFF,
no Swift, no Flow ou no legado de WhatsApp. Editar/cancelar/confirmar com CAS,
a integração e o cutover são etapas obrigatórias antes da ativação.

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
aceitas, com revisão sucessora e hash. Esta etapa não oferece uma API EDIT.
Fixtures de teste podem inserir um receipt sintético como owner para exercitar
o detector; isso não demonstra uma edição funcional.

## Único cálculo e gravação

O corpo literal dos 13 argumentos de `register_workout_atomic` foi copiado para
uma função privada INVOKER, sem mudar cálculos, defaults ou retorno. O corpo
strength S8 foi movido para outra função privada, mudando somente esse callee.
Ambas são exclusivas do owner. Os OIDs públicos permanecem.

Os wrappers públicos executam o guard backend real e exigem READ COMMITTED.
O de 13 argumentos adquire `:workouts` em um statement e consulta a proteção
em outro, após a espera, antes de qualquer UPSERT de snapshot. O strength
mantém a ordem catálogo SHARE → `:workouts` e consulta a key congelada do
command exato antes do replay F1 ou da deduplicação. A futura confirmação CAS
chamará a seam privada somente depois de verificar sua autoridade.

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

`get_mobile_workout_registration(owner, pending)` usa um SELECT para obter
conteúdo e revisão no mesmo snapshot: usuário ativo, epoch atual, admissão
owned com revisão, pending original e marker exato. Retorna `ui-v1` e os campos
já persistidos. Qualquer vínculo ausente devolve `invalid_admission`. Não
reabre pending, cria lifecycle ou autoriza gravação. O proposal raw é interno;
o futuro DTO HTTP ainda deverá aplicar a whitelist existente.

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
