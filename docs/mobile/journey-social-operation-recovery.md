# Jornada social — recuperação de um envio interrompido

Estado: implementação de servidor e camada nativa protegida, com testes locais. A funcionalidade social
continua desligada por padrão e as migrações ainda precisam de qualificação
conectada. O build 1.0(20) distribuído não contém esta recuperação.

## Contrato

`POST /api/mobile/v1/profile/journey-social/operations/resolve` recebe somente
`kind` (`profile`, `block` ou `report`) e o `command` original completo. Este
comando mantém UUID, revisão esperada e conteúdo. A chave específica é
`jsocial-resolve1:<UUID da operação original>`, separada da chave de envio.
Os headers de proprietário e sessão são derivados do login atual verificado.
O novo login pode ser da mesma conta; nenhuma autorização é herdada do token
antigo. A isenção já existente de Perfil mantém a recuperação de privacidade
acessível após expirar a assinatura.

A resposta fechada contém `status`, `operation_id`, `kind`,
`expected_revision`, `receipt` e `profile`:

| Estado | Significado |
| --- | --- |
| `applied` | A operação original já foi gravada. Retorna seu recibo e o perfil atual, sem executá-la novamente. |
| `fenced` | A operação ainda não foi gravada e foi cancelada definitivamente. O recibo é nulo; um envio atrasado com aquele UUID não pode produzir efeitos. |

Uma retirada de consentimento posterior continua prevalecendo. O recibo é
histórico: um recibo de denúncia enviada não prova que a denúncia ainda esteja
pendente de moderação. Repetir a recuperação consulta o estado atual sem
recriar participação, bloqueio, denúncia, pontos ou metas.

## Atomicidade e preservação

`resolve_journey_social_operation_authenticated` valida o vínculo domínio/Auth
e a sessão atual antes e depois da operação. Compartilha o lock da conta usado
pelos writers existentes. Se o envio ganhou a corrida, o recibo original
prevalece. Se a recuperação ganhou, grava apenas um marcador privado em
`private.journey_social_operation_fences`, com IDs técnicos e hash do comando,
sem apelido histórico, token, texto de denúncia ou fatos clínicos.

O trigger na inserção do recibo recusa um UUID cancelado. A exceção reverte toda
a transação original, inclusive alterações anteriores no perfil, bloqueio ou
denúncia. Os writers existentes não são reimplementados. A tabela tem RLS sem
acesso direto da API e acompanha a exclusão da conta por FK. O novo RPC é
executável apenas pelo backend confiável. Identificadores de domínio, Auth e
login não são aceitos como membros públicos.

Após ativação, um rollback de servidor deve preservar a tabela e o trigger de
cancelamento. Removê-los poderia permitir a execução de envios atrasados. A
mudança é aditiva; não exige alteração de metas, histórico de XP ou recibos
antigos.

## Camada nativa e integração ainda necessária

`JourneySocialPendingSession` já persiste a operação imutável no Keychain por
origem e conta antes de enviar. Uma falha de rede não autoriza descartá-la nem gerar outra chave.
Recuperação em novo login usa o comando antigo e a autorização atual da mesma
conta, por uma ação explícita que informe a possibilidade de cancelar o envio
não aplicado. Somente o recibo exato ou a resposta `fenced` validada permite
retirar a operação pendente. GET do perfil e erro 409 genérico não são provas
suficientes. Troca de conta continua isolando os dados pendentes.

O payload fechado e seu checksum preservam também o login original e os bytes
canônicos do comando. O repositório vinculado ao login atual e o transporte
validam separadamente a recuperação: conta de domínio/Auth iguais, origem
original, chave/corpo exatos, sem 401 automático ou redirecionamento. Uma falha
ao remover o pendente após o recibo preserva o comando para resolução explícita;
não permite substituí-lo silenciosamente.

Ainda falta conectar essa camada às telas de privacidade e ao descarte local
após exclusão comprovada da conta. A interface deve explicar que a resolução
pode cancelar um envio não aplicado. Não deve apresentar isso como reenvio nem
apagar pendentes no logout.

## Evidência reproduzível

- `journey_social_operation_resolution.sql`: recibos dos três tipos, retirada
  atual, cancelamento de efeitos atrasados, sessão expirada, isolamento,
  payload fechado, privilégios e cascata; fixtures em rollback.
- `journey_social_resolution_concurrency.py`: duas conexões reais em três
  ordens, com espera por lock comprovada e limpeza exata de UUIDs sintéticos.
- Testes do serviço e das rotas: chaves distintas, autorização antes/depois,
  recibos coerentes e recuperação própria sem assinatura ativa.

Os testes locais não substituem QA conectado, controles nativos, moderação,
missão em dupla, distribuição e aceite do Roberto.
