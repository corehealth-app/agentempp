# Journal de comandos de refeição — fundação inativa

A migração `20261103225726_conversation_meal_command_journal.sql` adiciona somente
admissão durável, fonte original, candidato imutável e consulta de status. Não tem
caller HTTP ou ligação ao preparador, não registra consumo, não confirma pending,
não congela recibo, não altera recompensas e não ativa a experiência conversacional.

## Identidade e conteúdo

`private.conversation_meal_command_ids` conserva `(user_id, command_id)`, protocolo,
kind, hash do DTO validado, epoch e relógio de admissão do servidor. Não tem TTL ou
FK para mensagens/pending. Excluir a conta pode remover seus registros em cascata.

A fonte pessoal fica em `conversation_meal_command_sources`; o candidato fica em
`conversation_meal_command_candidates`. Ambos são imutáveis depois da inserção.
O hash da admissão usa a mesma serialização canônica do DTO TypeScript: chaves
ordenadas, sem espaços estruturais, mantendo texto, Unicode, espaços e escapes.
Os limites de texto contam unidades UTF-16, como o schema atual do cliente.
UUIDs seguem o contrato Zod instalado: layout hexadecimal minúsculo 8-4-4-4-12,
incluindo nil, sem impor uma versão/variant adicional somente no banco.

Dois UUIDs novos com fontes iguais são dois comandos. Repetir o mesmo par dono/UUID
com outra fonte devolve conflito. Repetir depois de 24 horas conserva a identidade;
o banco não usa o TTL do cache HTTP como deduplicação permanente.

## RPCs somente para backend

- `admit_conversation_meal_command(user_id, input)` valida o DTO fechado no banco e
  calcula seu hash. Retorna `admitted`, `replay`, `input_conflict` ou `stale_epoch`.
- `attach_conversation_meal_candidate(user_id, command_id, input_hash, candidate)`
  grava uma vez o envelope candidato. Repetição igual devolve `replay`; uma
  substituição devolve `candidate_conflict`. Não aceita sobrescrever a fonte.
- `read_conversation_meal_command(user_id, command_id)` apenas consulta: devolve
  `available`, `absent` ou `stale_epoch`. Não inicializa, sela ou atualiza nada.

O candidato é um objeto fechado com `schema: conversation.meal-candidate.v1`,
`input_hash`, `status` (`prepared`, `conversational` ou `clarification_required`) e
`candidate` (objeto privado, limitado a 128 KiB no envelope). Seu payload é evidência
intermediária opaca. Nem o status `prepared` nem esse conteúdo autorizam um writer.
A fonte original permanece separada de qualquer texto derivado do candidato.

As três tabelas têm RLS sem policies e nenhum grant direto para `anon`,
`authenticated` ou `service_role`. Somente as três RPCs recebem EXECUTE de
`service_role`, com `assert_trusted_backend` e search path fixo. O futuro caller
precisa obter o dono da autenticação; este incremento não oferece uma rota pública.

## Reset e concorrência

Admissão/anexo exigem READ COMMITTED e seguem a ordem já existente:
advisory do dono `:workouts` → usuário ativo `FOR NO KEY UPDATE` → epoch → comando.
Não reutilizam a tabela de admissions nem inicializam o lifecycle de workout.

O reset existente já gira `workout_strength_authority_epochs.epoch`. Um trigger
restrito à mudança desse epoch invalida os tombstones e apaga fontes/candidatos na
mesma transação. O ID antigo nunca recebe um epoch novo, mesmo com fonte alterada.
A admissão inicializa o epoch quando necessário; reset anterior a qualquer lifecycle
ou journal continua válido. Consultas usam um único snapshot, sem locks ou efeitos.

## Qualificação local e limites

Qualificado em PostgreSQL real 17.11, na stack local sintética já pertencente à task,
sem recriar/aplicar novamente as 257 migrações de base:

- 68 assertions SQL: deduplicação, relógio, hash TypeScript/Unicode, formas inválidas,
  fonte/candidato congelados, isolamento, reset, ACL/RLS, rollback de falhas após
  inserts, preservação de pending alheio e cursor v1; todas com ROLLBACK.
- READ COMMITTED obrigatório; rejeição de REPEATABLE READ e SERIALIZABLE.
- 7 cenários de duas sessões com bloqueador real observado: duas admissões, dois
  anexos, reset/anexo nas duas ordens com commit/rollback e reset/admissão.
- Reset atômico/isolamento e a suíte existente de recibos v2/workout protegido.
- Ensaio de instalação + testes + ROLLBACK com fingerprint idêntico do catálogo,
  dados sintéticos zerados e catálogo alimentar preservado.

O ensaio removeu somente o protótipo local comprovadamente vazio antes da instalação
transacional. Não é um plano de downgrade de produção: tombstones reais devem ser
preservados. A migração permanece sem rollout cloud neste incremento.

A autoridade SQL atômica inativa foi adicionada separadamente em
`conversation-meal-atomic-writer.md`; ela não está ligada ao preparador ou a rotas.
Ainda faltam integrar e qualificar o preparador semântico/calculador, suas anotações
de preparo e os vínculos de mídia/clínica/dia aberto com essa autoridade SQL.
Selagem v2/retry a partir da fonte original, correção/desfazer, binding de mensagens
e timeline paginada também continuam pendentes. O writer separado já qualifica
localmente efeitos/recibos atômicos; a experiência completa do aplicativo continua
sem ativação ou QA de ponta a ponta neste incremento.
