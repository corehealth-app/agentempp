# Persistência atômica de mensagens do Flow — fundação dormente

Esta fundação acrescenta dois campos privados e uma RPC de backend. Não ativa
caller, flag, ferramenta do Flow, lifecycle, endpoint HTTP ou contrato iOS.
O caminho atual do chat continua dependendo da integração posterior. Testes de
fonte não substituem a execução SQL, as disputas nativas e o QA da aplicação.

## Identidade preservada

A [admissão durável](workout-strength-request-authority.md) não é apagada pelo
reset. Ela guarda a epoch original da requisição. A nova RPC coordena o INSERT
de `messages` e o vínculo desse UUID na mesma transação que usa o lock do reset.

Em `private.workout_strength_request_admissions`:

- `flow_inbound_id`: primeiro UUID criado por este writer, sem FK para messages.
- `flow_inbound_refusal`: motivo `unproved_inbound`, persistido quando a requisição
  encontra uma mensagem scoped ou um par S15 anterior que não pode adotar.

Os campos começam NULL. O CHECK impede UUID e recusa simultâneos e recusa motivos
desconhecidos. Não há backfill. O par S15 `original_inbound_id/lifecycle_key` e o
ponteiro de lifecycle da fence permanecem intactos. Conversar não abre lifecycle.

Somente o próprio `INSERT ... RETURNING` estabelece o vínculo. Uma mensagem
encontrada por chave, texto, request ID ou timestamp não comprova esse vínculo.
Uma colisão recusada permanece recusada mesmo depois de remover a mensagem.
Um UUID removido ou substituído por outro UUID idêntico não é recriado/adotado.

## RPC interna

`access_workout_strength_flow_inbound(userID, admissionID, text, mode, requestID, startedAt)`

São seis parâmetros obrigatórios, sem defaults. `mode` é `probe|persist`.
`probe` exige request ID e instante NULL e não cria mensagem, attempt ou clock.
Se encontrar uma colisão sem vínculo, grava somente a recusa durável prevista.
`persist` exige request ID ASCII literal de 8–128 caracteres e instante finito,
em milissegundos exatos, com ano UTC entre 1 e 9999. Texto não vazio de até 4.000
caracteres. O SHA256 usa os bytes UTF8 exatos: sem JSON, trim ou normalização.

Ordem: trusted guard, forma e READ COMMITTED; advisory `owner:workouts`; users
ativo `NO KEY UPDATE`; fence e admissão owned `FOR UPDATE`. Bloquear users antes
do INSERT mantém a ordem do trigger de `last_active_at`. Epoch antiga nega antes
de hash, recusa, replay ou criação. Ausência não cria admissão implicitamente.

Com vínculo, a RPC confere o UUID real, owner, in/user/text, provider mobile_flow,
provider ID `mobile_flow/<owner>/<key>` e hash literal, mantendo a row sob SHARE.
Um par S15 já preenchido precisa apontar para o mesmo UUID. Não chama initializer.

Resultados internos:

| Resultado | Significado |
| --- | --- |
| `unbound` | Probe atual sem vínculo nem colisão; só contém status. |
| `inserted` | Esta execução criou e vinculou o IN. |
| `reused` | Persist encontrou o UUID já vinculado e validado. |
| `bound` | Probe encontrou o UUID já vinculado e validado. |
| `forbidden` | invalid_admission, stale_epoch, unproved_inbound ou inbound_mismatch. |
| `conflict` | request_content_conflict, sem gravar recusa. |

Positivos contêm apenas `status,inbound`. A mensagem contém
`id,direction,content,delivery_status,raw_payload,created_at`. O payload mantém
somente as chaves operacionais existentes: request_id, conversation_id,
attempt_started_at, provider_started_at, retry_started_at e last_retry_at.
Preserva os valores JSON dessas chaves para o mapper atual; não expõe outros
campos privados. Esse wire não é uma nova resposta HTTP pública.

O primeiro attempt usa o instante operacional recebido, em UTC ISO3. Replay não
renova request ID, created_at, attempt, validade ou atividade. Uma row existente
com precisão sub-ms preserva ISO6 no wire; o novo writer não gera essa precisão.
`inserted` e `reused` são distintos mesmo quando request ID e relógio coincidem.

## Segurança, concorrência e limites

A RPC é postgres-owned, DEFINER, search_path pg_catalog, trusted guard real e
EXECUTE somente postgres/service_role. Não concede DML privado nem altera
privilégios globais/default. A migração recusa ACL herdada fora dessa
superfície, mantendo toda a criação na própria transação. Os campos e ACLs
anteriores não são ampliados.

Writer/reset usam o mesmo advisory. Se o writer confirmar primeiro, o reset
apaga a mensagem e invalida a epoch; retry não a recria. Se reset confirmar
primeiro, o writer bloqueado recusa a epoch antiga. Rollback preserva o estado
anterior. Falha entre INSERT e vínculo desfaz mensagem, vínculo e last_active_at.

Uma disputa com INSERT legado não cooperativo pode produzir 40P01 pelo trigger
de users; essa exceção operacional propaga com rollback. Não se promete recusa
durável nessa corrida. Apenas violações comprovadas dos índices de provider ID
de messages viram recusa; outros erros 23505 propagam.

O grupo escreve apenas mensagens mobile_flow. A tabela messages e o reset são
compartilhados com o legado WhatsApp; esse impacto foi avisado. Nenhum sender,
webhook, ingest de WhatsApp ou corpo do reset é alterado/ativado nesta migração.

A integração ainda precisa capturar a admissão antes do cache HTTP, verificar a
mesma admissão antes dos dois replays, provar o UUID existente e usar o writer
sem fallback ao legado quando enabled. `reused` não autoriza repetir provider.
OFF deve fazer zero trabalho novo. OUT, LLM, attempts posteriores, cache,
cutover e writers de treino não são cercados somente por esta fundação.

## Verificação e instalação

As regressões estão em `supabase/tests/flow_inbound_authority.sql` e fixtures
correspondentes. Chamam as RPCs reais; não definem corpos substitutos do produto.
Cobrem identidade, resposta perdida, colisões recusadas, clocks, guard/ACL,
rollback entre INSERT e vínculo e oito disputas A/B com bloqueio nativo observado.

O executor usa somente o retained C5 local, com baseline de quatro bancos,
delta esperado derivado da fonte antes da DDL, cleanup de QA owned e own stop.
Um novo commit DDL; continuação reconhece o produto instalado sem reinstalar.
O baseline local de entrada não contém admissions preenchidas: não é evidência
de upgrade de linhas antigas populadas. Não há escrita no staging, publicação
ou mudança na produção antiga autorizada por esta documentação.

## Primeiro gate de integração HTTP

O executor de idempotência mobile aceita um hook opcional `beforeReplay`.
Somente uma claim `replay` executa e aguarda esse hook, antes de atualizar uma
capacidade temporária (`refreshReplay`), projetar o corpo ou devolver a resposta
armazenada. Se a checagem falhar, o erro propaga sem executar a mutação, liberar
a claim concluída ou regravar seu cache. Claims novas, conflitos e tentativas
em andamento não executam o hook; sem ele, o caminho anterior é preservado.

Os testes exercitam o executor real com um store controlado: recusa, checagem
assíncrona pendente e os dois caminhos de replay, além dos ramos sem replay.
Isso prepara o ponto de checagem do S17J. Nenhuma rota produtiva fornece o hook
neste grupo. Captura na rota, integração do serviço, cutover e
validação com SQL/HTTP reais continuam pendentes; esse ponto isolado não cerca
reset, provider, OUT ou ferramentas e não ativa o novo protocolo do Flow.

## Adapter backend por injeção

`flow-inbound-authority.ts` prepara uma fonte de handles capturados, sem caller
na composição produtiva. A fonte usa somente as duas RPCs existentes: admissão
e acesso ao IN. Captura escalares e o método RPC com seu cliente original antes
da primeira espera; owner UUID é comparado por identidade, enquanto chave,
texto e SHA256 UTF8 permanecem literais. O handle é imutável e conserva a
admissão original em probe e persist; nunca inicializa lifecycle ou tenta um
writer alternativo. Uma vez observado o UUID do IN, não adota outro UUID nem
uma resposta unbound posterior no mesmo handle.

Os parsers fechados verificam status por modo, recibos e os seis campos do IN.
Preservam timestamps ISO3/ISO6 e os valores JSON operacionais de bound/reused,
inclusive chaves aninhadas, sem reinterpretá-los como attempts válidos. Já
inserted exige o instante ISO3 exato da tentativa, status processing e os cinco
campos iniciais definidos pelo INSERT SQL, com request ID e relógio originais.
Uma resposta contraditória não concede autoria da execução nem fixa o UUID.
Recusas conservam motivo
interno distinto, com HTTP 409 opaco; erros de entrada interna, wire ou transporte
retornam HTTP 500 sem paths Zod ou mensagens SQL. Nenhuma falha produz fallback
ou retry automático, e reused nunca equivale a inserted.

Capturar pode gravar uma admissão, probe pode gravar a recusa durável prevista
no SQL, e persist pode criar o IN. São efeitos da futura chamada backend, não
operações somente leitura. Os testes deste adapter usam um port controlado;
não chamam Supabase, não comprovam isolamento SQL ou o fluxo HTTP real. O adapter
isolado não prova a integração descrita abaixo, cutover ou ativação do S17J.

## Integração TS dormente do handler e serviço

O POST aceita a fonte somente nas dependências internas. Após validar o texto e
a chave, captura uma admissão antes do ledger HTTP. O callback claimed recebe
o mesmo handle; o hook beforeReplay exige bound sem criar IN, attempt ou clock.
Owner, chave e texto divergentes, fonte sem handle e handle sem fonte recusam a
operação. O payload público continua somente text. GET não captura autoridade.

No serviço ON, probe substitui as duas buscas de IN scoped/bare. Persist ocorre
somente depois do primeiro orçamento; reused recusa a corrida mesmo com request
ID e horário iguais. Uma resposta de persist perdida não comprova UUID e não
autoriza limpeza inferida por chave. Retries posteriores partem da prova bound
do recibo original e conservam lease, orçamento e CAS atuais.

CAS, cleanup e conclusão ON sem C5 também fixam o UUID. Conclusão usa retorno
de linhas e recusa zero resultados; a chamada OFF mantém seus dois argumentos
e filtros anteriores. O gate da mesma admissão e UUID original verifica os
replays iniciais, segunda leitura de OUT, C5 prior/commit/recovery e colisão OUT.
Não adota um IN posterior para reparar um OUT observado inicialmente sem vínculo.
Os probes do serviço usam o saldo do prazo original de 165 segundos; os três
conflitos de cursor C5 e seu resultado confirmado não são reescritos pelo gate.

Os testes executam handler, ledger e serviço reais com ports controlados. Não
substituem SQL/HTTP/iPhone reais nem comprovam cutover. A composição route.ts
continua sem fonte e a flag UI não a habilita. A seleção sticky de protocolo e
os gates de ativação seguem pendentes. Probe não torna retorno HTTP, provider,
OUT, ferramentas ou reset uma única transação. O grupo não altera WhatsApp,
motor compartilhado, migrations, regras nutricionais ou contratos do iOS.
