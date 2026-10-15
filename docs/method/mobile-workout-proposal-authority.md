# Autoridade da proposta de treino do app

Fundação dormente para o produtor real do iOS:
`registrations/propose → pending_registrations → confirmRegistration`.
O chat Flow só permite ferramentas de leitura e propostas de plano; não produz
esse registro. Uma proposta não é uma confirmação. Não fabricar uma mensagem IN
nem habilitar ferramentas de registro no Flow para adaptar esse caminho.

## Escopo

Duas RPCs de backend admitem uma intenção e materializam seu rascunho real. Não há
caller, flag, protocolo ou ativação neste grupo. Nenhum treino, snapshot,
lifecycle ou mensagem é criado. As fórmulas e os writers existentes permanecem.

A tabela privada `mobile_workout_proposal_admissions` usa a epoch já existente em
`workout_strength_authority_epochs`. O reset S15 troca essa epoch e apaga os
rascunhos na mesma transação; não precisa conhecer a tabela nova. A admissão
permanece como tombstone até o hard delete da conta, sem TTL ou FK ao rascunho.
Um pedido admitido antes do reset não pode obter outra epoch em retry.

A tabela guarda somente IDs, chave, digests, relógios e eventual recusa. O input
cru não é persistido. `pending_id`, `first_proposal_hash` e `bound_at` começam
nulos e são preenchidos juntos uma vez. Uma colisão com rascunho sem vínculo
comprovado registra `rejection_reason=unproved_pending` permanentemente para esse
pedido. Apagar a colisão posteriormente não autoriza uma nova materialização.

## Fronteiras internas

`admit_mobile_workout_proposal(owner, key, input)` valida o input estruturado já
validado pelo BFF e devolve `admitted|reused` com o recibo original de sete campos:
ownerID, admissionID, epoch, requestNamespace, requestKey, requestHash, admittedAt.
O namespace é `mobile_workout_proposal_v1`. Chave ASCII literal de 8–128 caracteres,
sem trim, e relógio UTC com seis casas decimais. Uma epoch antiga é recusada antes
de comparar o hash; conteúdo diferente na epoch atual é conflito.

O helper privado valida os campos atuais de workout, sem novos defaults. O hash
é SHA256 do UTF8 da representação JSONB do input, com `duration_min` convertido
para inteiro. Portanto, 10 e 10.0 têm o mesmo digest. Ordem das chaves e espaços
externos do JSON não identificam intenções diferentes; Unicode e strings não
recebem normalização. Esse hash SQL é próprio desse namespace: não é
`hashMobileRequest` nem o hash textual de Flow. O backend envia input, sem
calcular ou aceitar hash/epoch do cliente. A documentação do PostgreSQL descreve
as diferenças da representação [JSONB](https://www.postgresql.org/docs/17/datatype-json.html).

`materialize_mobile_workout_proposal(owner, admissionID, input, proposal, expiry)`
recarrega a admissão e a epoch sob a mesma transação que cria o rascunho. Recusa
admissão ausente/de outra conta, epoch antiga ou input diferente. No primeiro
vínculo confere tipo raw, duração, intensidade, raw_args, fontes e chave. O valor
calórico vem do cálculo existente, sem recalcular nesta RPC. `performed_at`,
quando fornecido, compara com `source_timestamp` pelo instante com a precisão
de milissegundos do `Date.toISOString` existente: os dígitos fracionários além
dos primeiros três do input ISO são descartados antes do cast SQL, que poderia
arredondá-los. O input original continua literal no hash. Quando ausente, não
é criado outro default temporal.

A criação usa `replace_pending_registration_atomic` existente. O helper deve
retornar `created=true`; uma linha anterior com a mesma source key não prova
vínculo com a admissão nova. A recusa dessa colisão não cancela nem adota a linha.
O rascunho recém-criado fica ligado ao UUID original, digest da primeira proposta
e relógio DB. Erro posterior reverte cancelamentos, insert e vínculo juntos.

Replay usa somente o UUID original owned e devolve seu status atual. Não recancela,
regrava, renova a validade nem compara a primeira proposta ao conteúdo editado.
Input original continua obrigatório; proposta recalculada e validade são ignoradas
nesse replay. Se o UUID sumiu, retorna `pending_missing`: outro rascunho com a
mesma chave não é adotado. Resultado positivo contém somente status
`materialized|reused`, pendingID, pendingStatus e cancelledCount (zero no replay).

## Concorrência e acesso

Ordem: trusted backend → shape → READ COMMITTED → advisory `owner:workouts` →
owner ativo `NO KEY UPDATE` → epoch/admissão → advisory `owner:pending-registration`
→ rascunho. As RPCs são postgres-owned, SECURITY DEFINER e
`search_path=pg_catalog`, com EXECUTE apenas para owner/service_role. A tabela tem
RLS sem policies e não concede DML; o helper privado não concede EXECUTE a outros
papéis. ACL inesperada herdada aborta a migração inteira, sem revogar defaults
globais. Erros operacionais propagam e não acionam fallback legado.

O helper de rascunhos e os dados são compartilhados com o código legado do
WhatsApp: a criação continua cancelando os pendings anteriores do owner como já
acontecia no app. O aviso de impacto precede a mudança. Nenhum caller, sender ou
webhook legado ganha essa autoridade automaticamente.

## Antes da ativação

Ainda são obrigatórios:

- Integrar admissão antes dos awaits de cálculo e antes de replay do cache HTTP.
- Provar protocolo novo por intenção, preservado em retry; OFF não faz trabalho
  novo e não promove pedidos antigos nunca admitidos.
- Implementar edição com versão/CAS e preservar cancelamento/expiração.
- Confirmar pending/epoch/versão e gravar S7/S8 atomicamente, incluindo os caminhos
  de deduplicação. Um precheck TS seguido de outra RPC não fecha a corrida.
- Respeitar a ordem de catálogo SHARE antes de workouts na captura S8.
- Integrar o cliente e validar a jornada real, acessibilidade e desempenho.

A fronteira de IN atômico de Flow é separada e ainda necessária antes de ativar
seu protocolo. Este grupo não declara entrega do beta nem QA físico concluído.
