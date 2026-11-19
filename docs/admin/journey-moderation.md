# Moderação operacional da Jornada

Esta é a interface operacional e a dependência de servidor da tarefa T6,
qualificadas localmente. As sete migrações do esquema foram aplicadas e
conferidas no staging `xitugspwfxkcluxvrdeg` (R202), conforme a
[fundação social](../mobile/journey-social-foundation.md#aplicação-do-esquema-no-staging).
A qualificação conectada da interface e a ativação continuam pendentes. Não está incluída no
build 1.0(20). `MOBILE_JOURNEY_SOCIAL_ENABLED` permanece desligado por padrão.
Nenhuma migração social é hospedada somente por existir neste repositório.

## Autoridade e composição

`loadJourneyModerationOperator` é restrito ao servidor. Verifica o token exato
obtido do cookie com `Auth.getUser(token)`, confere o papel atual em
`admin_users` e fixa o par operador/login. Somente `operations_admin` e
`master_admin` são admitidos. O guarda de página em cache e `is_admin()` não
autorizam estas operações. A matriz de páginas também reserva
`/journey-moderation` a esses dois papéis. A página começa pelo guarda antes
do bootstrap. O menu é restrito aos mesmos papéis. Com a capacidade desligada,
a página mostra indisponibilidade, sem criar cliente de serviço nem gravar.

As declarações do token, após a verificação pelo Auth, vinculam usuário,
emissor, audiência, validade e `session_id`. Metadados editáveis do usuário
não determinam permissões. O token não aparece em resultados, registros de
operação nem armazenamento do navegador. Cada chamada repete a admissão antes
e depois de uma única invocação física. Não há repetição automática.

O RPC de fila e comandos usado pelo serviço é
`journey_social_operator_authenticated(actor, login, action, input)`, concedido
apenas a `service_role`. Dentro da transação, ele bloqueia a linha do papel
operacional, a identidade no Auth e a sessão original, antes e depois do trabalho. Uma sessão que
expira durante uma gravação invalida também o efeito e o recibo. Concorrência
com outra operação do mesmo operador retorna conflito; a interface não deve
criar outro identificador ou reenviar silenciosamente.

A migração de revogação social recusa também `auth.users.deleted_at` e o
bloqueio atual no Auth, mesmo com token/sessão ainda válidos. O lock compartilhado
da identidade serializa bloqueio/exclusão lógica com uma operação já admitida;
se a revogação estiver em curso, a admissão recusa por conflito, sem gravar.

`journey_social_operator_profile_authenticated(actor, login, member)` oferece
uma consulta mínima ao perfil público, protegida pelo mesmo bloqueio e
conferência da sessão. Permite restaurar o perfil depois que a denúncia saiu
da fila. Não retorna UUIDs de Auth/domínio, contatos, metas ou saúde.

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

A interface oferece consulta por identificador público, suspensão/restauração
explícita e decisões separadas para resolver/arquivar cada denúncia. Há fila
paginada e estados de indisponibilidade e de resultado incerto. A composição
conectada só monta os dados depois de conferir a referência opaca da sessão
inicial. Um novo usuário/login ou logout invalida a tela de forma síncrona;
uma conferência assíncrona antiga não pode reabri-la. A renovação do token da
mesma sessão preserva a tela. Eventos nunca autorizam operações. Encerrar limpa fila, perfil e campo de consulta, sem
apagar uma intenção cujo resultado ainda seja desconhecido.

Cada ação recebe um identificador novo e é persistida antes do envio. O
armazenamento tem namespace por origem e operador, comando fechado, referência
opaca do login e checksum, sem token, senha ou apelido. Web Locks serializam
reservas e remoções entre abas; sem o recurso ou sem persistência, uma nova
gravação não é enviada. Uma operação diferente não sobrescreve a pendência.
Abrir, atualizar e receber evento de armazenamento apenas leem. A remoção local
exige o recibo exato ou resposta `applied`/`fenced` validada e o mesmo snapshot.
O checksum detecta corrupção; não substitui autorização no servidor.

Um novo login do mesmo operador pode conferir explicitamente a pendência
anterior, mas não reenviar seu escritor. Outro operador não a carrega. O
contexto de origem/operador/login recebido pelo navegador é opaco e comparado
ao contexto derivado novamente pelo servidor. Cabeçalhos de origem servem
somente para namespace, não dão permissão ou destino de requisição.

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

Os testes de `journey-moderation` verificam serviço, ações, armazenamento,
estado da interface, eventos de sessão e a composição com
dependências externas controladas. `journey_social_operator_gateway.sql`
executa o gateway real com fixtures transacionais, incluindo expiração dentro
do escritor. `journey_social_operator_concurrency.py` usa conexões reais em
uma cópia local isolada: papel/logout concorrentes, recibo único e escritor
atrasado depois da barreira. Exige registro de propriedade do ambiente, não
cria banco nem acessa projetos hospedados e remove apenas suas fixtures.

A conferência de navegador usa os componentes e o modelo reais, Web Locks e
localStorage reais e os gateways SQL em cópia local. Somente a autenticação
externa é substituída por identidades fictícias no roteiro isolado, fora do
código da plataforma. Inclui encerramento separado, consulta após reabrir,
resposta perdida após commit, repetição técnica com a mesma chave, isolamento
de operador, pendência compartilhada entre abas, cancelamento antes da gravação,
paginação e limpeza visual. A composição conectada real também é exercitada
com evento de novo login sem recarregar: a tela anterior é retirada, a pendência
permanece e somente a recuperação explícita na nova sessão pode conferi-la.
Isso não comprova uma sessão hospedada no GoTrue,
uma instalação nativa ou liberação da capacidade.

Antes da ativação, ainda são necessários: QA conectado com contas distintas; limpeza
local somente após exclusão comprovada da conta; missões em dupla; acessibilidade,
performance, distribuição e aceite da versão instalada. T1–T7, Android e todas
as demais áreas do plano continuam obrigatórias.
