# Autoridade durável de pedidos de treino — fundação dormente

Este grupo acrescenta duas tabelas privadas e duas RPCs de backend. Nenhum caller,
flag, protocolo de chave ou produto foi ativado. Não altera regras nutricionais,
calorias, S7/S8, DTOs públicos R2 ou os writers legados.

## Problema e limite

Um pedido Flow pode ter sua mensagem apagada pelo reset e ser repetido depois que
o ledger HTTP liberou/expirou a tentativa. Esse ledger tem TTL e pode renovar a
mesma chave; ele não prova a autoridade original do pedido.

A admissão persiste enquanto o owner existe: `(owner, mobile_flow_turn, key)` não
inclui epoch, inbound ou lifecycle e nunca é apagada pelo reset. Uma admissão E0
não ganha E1 em retry. O grupo protege pedidos enabled já admitidos duravelmente.
Não recupera intenção de tráfego antigo OFF/nunca admitido.

## Persistência privada

- `workout_strength_authority_epochs`: uma fence por owner, epoch DB,
  `current_lifecycle_key` nullable sem FK live e `changed_at` finito.
- `workout_strength_request_admissions`: admission ID DB, namespace/key literais,
  SHA256, epoch original, `admitted_at` DB e par inbound/lifecycle original.
  O par começa nulo e só é preenchido pela inicialização; não referencia objetos
  live por FK, preservando o tombstone quando o reset os apaga.

A FK da admissão referencia somente o owner da fence. Hard delete do owner faz
cascade. O core da admissão não é atualizado pelas RPCs; somente os dois snapshots
são preenchidos uma vez. DML direto pelo owner SQL está fora dessa garantia.
Tabelas postgres-owned, RLS sem policies e sem DML para PUBLIC, anon,
authenticated ou service_role. Não há grants globais/default ACL.

`changed_at` é o relógio da criação/troca da epoch, não da vinculação da life.
Init preenche somente o ponteiro da fence; `opened_at` é o relógio próprio da nova
life. Replay não atualiza relógios. Nenhuma relação temporal nova entre esses
relógios é exigida.

## RPCs internas de backend

`admit_workout_strength_request(owner, requestKey, requestHash)` retorna
`admitted|reused` com recibo original, `forbidden/stale_epoch` ou
`conflict/request_content_conflict`. Namespace é fixo no servidor. A chave é
ASCII literal de 8–128 caracteres `[A-Za-z0-9._:-]`, sem trim SQL; hash são
64 hex minúsculos SHA256 do UTF8 de `input.text` já validado pela borda Flow,
sem JSON.stringify, normalização Unicode ou novo trim.

`initialize_workout_strength_lifecycle(owner, admissionID, originalInboundID)`
retorna `initialized` no primeiro preenchimento do par, mesmo reutilizando a life
atual; `reused` só repete a mesma admissão já ligada. Retorna o UUID/instante real.
Negativas são `stale_epoch`, `invalid_admission`, `inbound_mismatch`,
`stale_lifecycle` ou `unproved_lifecycle`, conforme contrato Root e adendo de wire.
São wires internos novos; nenhum enum R2 foi ampliado.

As duas RPCs são SECURITY DEFINER, `search_path=pg_catalog`, trusted guard real e
EXECUTE apenas owner/service_role. Guard/sintaxe/READ COMMITTED precedem advisory
`owner:workouts` e users ativo `NO KEY UPDATE`; clocks DB vêm depois dos locks.
Sintaxe:22023; guard/ACL:42501; owner ausente/inativo:P0002. Falhas operacionais
propagam; nunca viram unavailable ou fallback legado.

Init recarrega fence/admissão owned e nega epoch antiga antes de replay/vínculos.
Confere a linha real de messages: UUID/owner/in/user/text/mobile_flow,
provider ID `mobile_flow/<owner>/<requestKey>` exato e SHA256 UTF8 do content.
NULL não comprova igualdade; não há fallback bare legado. A linha conferida fica
sob SHARE até o fim da transação. UUID original já ligado não é substituído nem
por mensagem idêntica recriada.

Life missing/foreign é unproved; owned fechada é stale. Com par já ligado, a life
owned/aberta deve ser exatamente o ponteiro atual da fence, senão stale. Sem par,
só o ponteiro owned/aberto pode ser reutilizado; ponteiro null com qualquer life
aberta órfã é unproved. Só null sem aberta cria uma life DB nova e liga os dois
snapshots atomicamente. Caller não envia epoch/lifecycle como autoridade.

## Reset compartilhado

A nova migração reapresenta somente a função reset de dois argumentos, preservando
literalmente o corpo S14 e acrescentando, após o owner encontrado, um UPDATE da
fence existente: epoch DB nova, ponteiro null, changed_at DB. Não cria fence para
owner nunca admitido, nem depende da flag atual. O mesmo advisory e transação do
reset coordenam epoch, close e deletes; erro tardio reverte tudo. Wrapper,
keep_plans, JSON, deleted_rows e ACL existentes são preservados.

Esse reset é compartilhado com código legado de WhatsApp; o impacto foi avisado
a Eduardo. Nenhum sender, webhook ou caller WhatsApp foi habilitado/alterado.
O patch inverso entregue é uma prova de preservação de fonte, não uma instrução
para restaurar corpo antigo no banco.

## Instalação e verificação

A migração tem um único BEGIN/COMMIT; exige execução como postgres e recusa colisão
de nomes antes de criar objetos. No harness C5, Root usa SET ROLE postgres na mesma
sessão para incluir o arquivo e volta ROLE NONE. Não requer normalizar owners,
novos grants, outro banco, seed ou dependência.

O guard final de ACL compara somente as duas tabelas/RPCs novas, owner, grantee,
grantor, privilégio e grant option contra a ACL canônica. DefaultACL herdada
inesperada aborta toda a migração com 42501; nenhum grant extra/default é removido.


Testes SQL/fixture foram adotados e revisados antes do runtime. O grupo requer
execução local real:53 oráculos sequenciais, disputas A/B revisadas separadamente,
regressão reset pertinente38+23, preservação de dados/metadados e stop comprovado.
Ausência das novas RPCs é setup, não RED causal de uma implementação anterior.
Esta documentação não afirma que gates foram executados ou passaram.

Antes de ativar, ainda faltam protocolo/cutover, OFF zero novo trabalho no caller,
transporte de autoridade até tools e coordenação atômica da admissão com a criação
de inbound. Admit COMMIT → reset → INSERT IN tardio ainda pode recriar mensagem;
init nega X, não prova integridade completa do histórico. Mobile confirm, WhatsApp
e bursts precisam producers equivalentes antes de qualquer habilitação.
