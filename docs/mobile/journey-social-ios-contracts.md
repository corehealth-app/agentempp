# Jornada social — contratos nativos

## Estado e limite de ativação

Esta camada implementa os contratos e o repositório iOS das rotas de
participação, bloqueio, denúncia e ranking, com telas nativas opcionais de
privacidade. A composição real ainda não instala essa capacidade por padrão. `MOBILE_JOURNEY_SOCIAL_ENABLED` continua desabilitado por padrão;
as migrações de Jornada ainda precisam de qualificação conectada antes da
publicação. O build 1.0(20) distribuído não contém esta camada.

A integração com a exclusão verificada da conta, a moderação, as missões em
dupla, o QA integrado e a distribuição continuam necessários para concluir T6/T7.
As telas no código não substituem esses entregáveis nem ativam o recurso.

## Autoridade e sessão

`MobileJourneySocialRepository.scoped` vincula o repositório à sessão original
do coordenador de autenticação. Lê `/me` para resolver o usuário de domínio,
sem criar cadastro, participação, consentimento, pontos ou metas. O `sub` e o
`session_id` do token já validado pelo ciclo de sessão identificam o vínculo;
não substituem a autenticação e a autorização do servidor.

Antes e depois de cada chamada, o repositório verifica conta, geração e login
originais. A publicação de estado visível passa pela operação protegida do
coordenador. Trocar de conta ou login invalida o trabalho anterior. As rotas
sociais recusam construção genérica, redirecionamento e repetição automática
após 401; não reutilizam uma sessão renovada como se fosse o login original.

As únicas capacidades de rede são:

| Rota em `/api/mobile/v1` | Método | Finalidade |
| --- | --- | --- |
| `/profile/journey-social` | GET / PATCH | Ler ou alterar participação e apelido |
| `/profile/journey-social/blocks` | GET / POST | Ler bloqueios ou alterar um bloqueio |
| `/profile/journey-social/reports` | POST | Denunciar por motivo fechado |
| `/journey/ranking` | GET | Ler classificação semanal oficial |
| `/profile/journey-social/operations/resolve` | POST | Comprovar ou cancelar um envio anterior sem executá-lo |

`X-Journey-Owner` e `X-Journey-Session` vêm exclusivamente do vínculo original.
Não existe capacidade nativa de moderação. O servidor continua verificando
propriedade, sessão viva, direitos de acesso e papéis operacionais.

## Consentimento e resposta perdida

Uma operação imutável contém UUID, revisão esperada, ação e bytes do corpo.
A chave é `jsocial1:<uuid>`. Repetir o envio explicitamente exige o mesmo login,
comando e chave. Consultar o resultado ou cancelar um envio ainda não aplicado
usa a capacidade separada `jsocial-resolve1:<uuid>`, permitindo um novo login
da mesma conta sem executar o consentimento antigo. Dois comandos legítimos
distintos têm identificadores distintos.

`JourneySocialPendingSession` grava a intenção antes do envio no
`JourneySocialPendingStore`, um ator serial compartilhado por origem canônica.
O Keychain usa proteção do dispositivo, sem sincronização, e separa as contas
Auth. O payload fechado contém origem, vínculos, tipo, comando original e
checksum; não contém tokens ou senhas. Uma ação diferente não sobrescreve uma
pendente. Falha de armazenamento impede o envio; falha de rede preserva a ação.

Somente o recibo exato ou uma resolução `applied`/`fenced` validada retira o
pendente. A verificação inclui a sessão atual antes e depois do trabalho.
Ler o pendente ou o perfil não reenvia, resolve ou descarta nada. O transporte
também recusa uma recuperação para outra origem antes da chamada física.

A entrada exige apelido e consentimento explícito `journey-social.v1`. A saída
envia apelido e versão de consentimento nulos. Um recibo repetido pode trazer
uma revisão atual posterior: o perfil atual prevalece, inclusive quando a
pessoa já retirou sua participação. O recibo antigo não restaura consentimento.

## Projeções públicas

DTOs e envelopes são fechados. Identificadores públicos não podem ser os UUIDs
privados de domínio, Auth ou login do vínculo. Campos de saúde, contatos e
campos desconhecidos são recusados. O apelido segue a mesma contagem de pontos
Unicode e restrições do servidor, sem normalização silenciosa.

O ranking aceita somente `closed_daily_xp`, semana de segunda a domingo e
valores oficiais consolidados. Empates mantêm posição compartilhada (1, 1, 3);
o UUID ordena apenas a apresentação dos empatados. Ler o ranking não concede
XP. O cursor mantém contexto, participante, data civil e deslocamento. O
servidor invalida o contexto quando a audiência ou os fatos oficiais mudam,
em vez de manter participantes que saíram.

Bloqueios preservam revisão e ordem do cursor. O apelido pode ficar ausente
quando o participante já não é visível; o cliente não o recupera por outra
rota. Respostas de sucesso exigem HTTP 200, `X-Journey-Social: 1` e
`Cache-Control: no-store`.

## Verificação

`JourneySocialContractTests` cobre consentimento, projeções fechadas, vínculos,
empates e cursores. Os casos `journeySocial*` de `MobileAPITransportTests`
exercitam o repositório com o coordenador real de sessão e transporte HTTP
controlado: troca de conta, publicação tardia, 401, redirecionamento, resposta
perdida e repetição da mesma operação. Não usam contas, credenciais ou dados
de pacientes. Estes testes não são evidência de ativação conectada.

`JourneySocialPendingTests` cobre restauração do comando, armazenamento negado
ou corrompido, confirmação exata, falhas de rede e descarte local, cancelamento,
troca de conta/login e reentrância. Os testes de recuperação HTTP usam o
coordenador real de sessão e verificam corpo/chave imutáveis, nenhuma renovação
ou repetição automática e recusa de publicação tardia. Antes da ativação, ainda
é obrigatória a integração com a exclusão verificada da conta; logout não pode
apagar envios incertos.

## Apresentação nativa e ciclo da sessão

`JourneySocialSessionSource` é inerte: ao abrir verifica o Auth esperado, resolve
propriedade por `/me` e cria o modelo com armazenamento protegido. Não admite
transporte com adaptador de sessão legado. A capacidade opcional em
`AppDependencies` permanece nula na composição real até a qualificação.

`Prompt14SessionOwner` mantém e encerra `JourneySocialShellCoordinator`. A
invalidação é síncrona; depois aguarda trabalhos em andamento e libera capacidades.
O modelo e a janela de denúncia removem dados visíveis ao encerrar. Uma resposta
tardia não publica em outra conta. O Form inteiro é retirado ao fechar a sessão,
impedindo que seu cache nativo mantenha células de participantes no acesso visual.

`JourneySocialView` oferece apelido e aceite explícito, saída, ranking semanal
paginado, bloqueio/desbloqueio, denúncia por motivo fechado e consulta/cancelamento
de envio pendente. Abrir ou atualizar faz apenas leituras. O perfil oficial atual
determina elegibilidade. Não há consentimento ou gravação ao aparecer. Os cartões
clínicos da Jornada são preservados. Datas civis não são convertidas pelo fuso do aparelho.

Mutação passa por `JourneySocialPendingSession`. Se gravar foi comprovado, mas ler
as listas falhou, a tela informa ação salva e oferece consulta, sem reenviar.
A janela de denúncia fecha somente após o resultado da operação que acabou de
enviar. Entrada inválida não reaproveita uma mensagem de sucesso anterior.

Falha de página elimina a audiência visível até nova consulta. Combinar páginas
recusa duplicação de membros, mudança de contexto e quebra de empates. Nenhum UUID
privado ou dado clínico é acrescentado à projeção pública.
