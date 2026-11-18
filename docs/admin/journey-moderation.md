# Moderação operacional da Jornada

Esta é a dependência de servidor da tarefa T6. A interface operacional, a
qualificação conectada e a ativação continuam pendentes. Não está incluída no
build 1.0(20). `MOBILE_JOURNEY_SOCIAL_ENABLED` permanece desligado por padrão.
Nenhuma migração social é hospedada somente por existir neste repositório.

## Autoridade e composição

`loadJourneyModerationOperator` é restrito ao servidor. Verifica o token exato
obtido do cookie com `Auth.getUser(token)`, confere o papel atual em
`admin_users` e fixa o par operador/login. Somente `operations_admin` e
`master_admin` são admitidos. O guarda de página em cache e `is_admin()` não
autorizam estas operações. A matriz de páginas também reserva
`/journey-moderation` a esses dois papéis; ainda não existe página nessa rota.

As declarações do token, após a verificação pelo Auth, vinculam usuário,
emissor, audiência, validade e `session_id`. Metadados editáveis do usuário
não determinam permissões. O token não aparece em resultados, registros de
operação nem armazenamento do navegador. Cada chamada repete a admissão antes
e depois de uma única invocação física. Não há repetição automática.

O único RPC usado pelo serviço é
`journey_social_operator_authenticated(actor, login, action, input)`, concedido
apenas a `service_role`. Dentro da transação, ele bloqueia a linha do papel
operacional e a sessão original, antes e depois do trabalho. Uma sessão que
expira durante uma gravação invalida também o efeito e o recibo. Concorrência
com outra operação do mesmo operador retorna conflito; a interface não deve
criar outro identificador ou reenviar silenciosamente.

## Operações fechadas

| Ação | Entrada | Efeito |
| --- | --- | --- |
| `queue.read` | `limit`, `cursor` | Página de denúncias pendentes, sem gravação. |
| `profile.moderate` | `operation_id`, `expected_revision`, `member_id`, `action` (`suspend`/`restore`) | Altera a moderação do perfil por revisão, com recibo idempotente. |
| `report.resolve` | `operation_id`, `expected_revision`, `report_id`, `status` (`resolved`/`dismissed`) | Encerra a denúncia por revisão; não altera a moderação do perfil. |
| `operation.resolve` | `kind` (`profile`/`report`), `command` original | Consulta o recibo ou cria uma barreira técnica para cancelar a chegada tardia; não executa a intenção original. |

Uma repetição exata retorna o recibo original. Conteúdo diferente com o mesmo
identificador é conflito. A mesma chave não pode mudar de espécie de operação.
`operation.resolve` retorna `applied` com recibo, ou `fenced` sem recibo. Um
trigger impede que o escritor interno atrasado contorne a barreira: toda sua
transação, inclusive a alteração do perfil ou da denúncia, é desfeita.

A recuperação após um novo login do mesmo operador é uma consulta/cancelamento
explícito, autorizado novamente. Nunca transfere uma gravação antiga para a
nova sessão nem executa automaticamente a intenção armazenada.

## Privacidade e apresentação

A fila contém somente identificador da denúncia, motivo fechado, estado,
revisão e data; identificador público, apelido, moderação e revisão do perfil.
Não contém denunciante, contatos, UUID privado do paciente ou dados clínicos.
O cursor usa `(created_at, report_id)` com precisão de microssegundos. O serviço
recusa campos extras, duplicações e páginas desordenadas ou incompatíveis com
o cursor. Uma nova consulta pode refletir denúncias encerradas por outro operador.

Suspender/restaurar e resolver/arquivar são decisões distintas, sempre explícitas.
Um recibo antigo não restaura o consentimento: em repetições, o perfil atual
prevalece. Ações operacionais não escrevem metas, saúde, créditos ou XP.

## Qualificação e próximos consumidores

Os testes de `journey-moderation` verificam o serviço e a composição com
dependências externas controladas. `journey_social_operator_gateway.sql`
executa o gateway real com fixtures transacionais, incluindo expiração dentro
do escritor. `journey_social_operator_concurrency.py` usa conexões reais em
uma cópia local isolada: papel/logout concorrentes, recibo único e escritor
atrasado depois da barreira. Exige registro de propriedade do ambiente, não
cria banco nem acessa projetos hospedados e remove apenas suas fixtures.

Antes da ativação, ainda são necessários: painel guardado com fila e ações
explícitas; pendência durável por operador/contexto, sem reenvio ao recarregar;
revisão de resultado incerto; QA conectado com contas distintas; limpeza
local somente após exclusão comprovada da conta; missões em dupla; acessibilidade,
performance, distribuição e aceite da versão instalada. T1–T7, Android e todas
as demais áreas do plano continuam obrigatórias.
