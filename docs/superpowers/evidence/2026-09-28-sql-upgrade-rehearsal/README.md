# Ensaio local de upgrade e recuperação — M1, M2, M3, M4

Data: 2026-09-28. **Somente local.** Nenhum banco remoto foi acessado.

Ambiente: container próprio e separado `performe-v3r-db`
(`public.ecr.aws/supabase/postgres:17.6.1.167`, porta local 55433), criado só
para este ensaio. O container de testes `performe-v3-db` não foi alterado.

## 1. Base anterior às migrations
- 162 migrations aplicadas, todas as anteriores a `20260928120000`.
- Dados legados sintéticos gravados pelos escritores antigos
  (`01-seed-legacy.sql`): 2 pacientes, peso escrito direto em `weight_kg`,
  5 mídias de todos os tipos existentes e em vários estados, 3 mensagens,
  1 prescrição e 1 plano de treino no formato dos geradores do WhatsApp, e
  1 refeição com quantidade decimal.
- Impressões digitais registradas: dados das 8 tabelas legadas, calculados
  só sobre as colunas que já existiam (`02-fingerprint-gen.sql`), e catálogo
  dos objetos tocados (`03-catalog-fingerprint.sql`).
- Dump lógico completo da base (`pg_dump -Fc`, 1,9 MB, cerca de 1 s).

## 2. Pré-checagem (`04-preflight.sql`)

| Caso | Situação preparada | Resultado |
|---|---|---|
| P1 | Base limpa | OK; os 3 índices ausentes serão criados pela M2 |
| P2 | Índice com o nome esperado e definição errada `(user_id, id)` | **Recusado**, com a definição encontrada |
| P2b | O mesmo índice errado diante da M2 | A M2 **pula** o índice (`already exists, skipping`). `IF NOT EXISTS` não garante equivalência |
| P3 | Índice inválido, estado deixado por um `CONCURRENTLY` cancelado | **Recusado** (`valid=f`) |
| P3b | O índice inválido diante da M2 | A M2 **pula** o índice inválido |
| P4 | Recuperação: `DROP INDEX CONCURRENTLY` e nova criação `CONCURRENTLY` | OK; índice pré-criado, válido e equivalente |

Conclusão: depois de um timeout ou cancelamento na criação concorrente, o
estado deve ser inspecionado com a pré-checagem antes de aplicar a M2. Não se
deve repetir a migration às cegas.

## 3. Aplicação
Cada migration foi aplicada em uma transação própria, na ordem M1, M2, M3, M4.

| Migration | Comandos | Tempo total | Locks de tabela observados |
|---|---|---|---|
| M1 | 13 | 48,9 ms | `user_profiles` AccessExclusive (ADD COLUMN, CHECK, gatilho) |
| M2 | 41 | 26,2 ms | `prescriptions` AccessExclusive; `media_assets`, `messages` Share e ShareRowExclusive (índices e FKs); `users` ShareRowExclusive |
| M3 | 3 | 4,5 ms | `media_assets` AccessExclusive (troca das CHECK, valida as linhas existentes) |
| M4 | 6 | 2,9 ms | nenhum lock de tabela (só funções) |

Os tempos valem para tabelas quase vazias. Com dados reais, os índices da
M2 e a validação das CHECK da M3 levam tempo proporcional ao tamanho, sob
lock. No staging, `lock_timeout` curto e pré-criação `CONCURRENTLY` dos
índices, conferida pela pré-checagem.

A listagem de locks da M1 e da M2 também mostrou `storage.buckets`
AccessExclusive, embora nenhuma das duas referencie Storage. O lock **não se
reproduziu** em nenhum teste:
- a M1 aplicada sobre a base restaurada só pega lock exclusivo em
  `user_profiles`;
- `COMMENT`, `CREATE FUNCTION`, `CREATE TRIGGER` e `ADD COLUMN` isolados no
  banco atualizado não pegam lock em `storage`.

A causa não foi identificada. Fica como observação aberta, a conferir no
staging com a pré-checagem de locks.

## 4. Depois do upgrade

| Verificação | Resultado |
|---|---|
| Dados legados (8 tabelas, colunas antigas) | **Idênticos** à base |
| Peso legado | Sem backfill: instante e origem continuam nulos |
| Escritor legado de peso | Funciona e grava origem `recorded`, nunca `measured` |
| Escritor legado de mídia (todos os tipos antigos) | Funciona sob as CHECK novas |
| Escritor legado de prescrição | Funciona; `source_request_key` fica nulo |
| Redefinição legada de 1 argumento | Mantém os planos |
| EXECUTE das RPCs novas | Só `service_role`; `anon` e `authenticated` sem acesso |
| Funções `private.*` novas | Sem EXECUTE para papéis de cliente |
| `plan_drafts` | RLS ligada, sem privilégio de tabela para clientes |
| Coluna `weight_instant_source` | Sem UPDATE para papéis de cliente |
| Bucket `plan-documents` | Privado e com limite de tamanho |
| Índices | Todos válidos e prontos |
| Suíte SQL completa sobre a base atualizada | 38 de 40; as 2 falhas são as já classificadas: catálogo de mensagens no push do servidor e crons do staging |
| Concorrência de rascunhos (replay e corrida) | 1 plano ativo; corrida recusada com `plan_changed_during_review`; nada órfão |
| Concorrência de peso (24 gravações fora de ordem) | 3 aplicadas, 21 recusadas por serem mais antigas; vence a mais nova |

Um teste falhou só neste banco e foi corrigido em `f12aa20`:
`p0_authorization_matrix` contava a tabela inteira de perfis e presumia um
banco vazio.

## 5. Quatro formas de recuperação, com resultados

| Forma | O que faz | Perda de dados | Ensaio |
|---|---|---|---|
| **Rollback de transação** | Falha ou `ROLLBACK` durante a aplicação | Nenhuma: nada foi confirmado | M1 a M4 aplicadas numa transação e desfeitas. Catálogo e dados idênticos à base |
| **Reversão de aplicação** | Voltar o deploy anterior do servidor, mantendo o SQL | Nenhuma. Os objetos novos ficam parados | As funções que o código antigo chama mantêm a assinatura. A de 1 argumento da redefinição continua existindo |
| **Restauração** | Restaurar um backup anterior | **Tudo o que foi gravado depois do backup** | `pg_restore` do dump da base num banco novo: dados idênticos. O catálogo difere só pelas 38 entradas do `pg_cron`, excluídas porque ele só existe no banco `postgres`, e pela reescrita cosmética de parênteses nas CHECK |
| **Reversão destrutiva** (`06-destructive-reversal.sql`) | Remove os objetos da M4 à M1 | **Sim**: rascunhos de plano, documentos de plano, chaves de idempotência das prescrições, instante e origem de cada peso medido | Executada dentro de uma transação desfeita, com 1 rascunho e 1 peso medido criados antes. Catálogo resultante igual à base, exceto o bucket `plan-documents`. Esse bucket só sai pela API de Storage, porque `storage.protect_delete` bloqueia o `DELETE` por SQL. Dados legados idênticos |

A reversão destrutiva **nunca é automática**. Ela só roda com autorização
escrita que cite o arquivo e o hash, e recusa rodar enquanto houver objetos no
bucket `plan-documents`.

## 5b. Novo ensaio depois da revisão adversarial (M1 alterada)

A revisão encontrou um defeito HIGH na M1: a segunda pesagem feita pelo app
era rotulada `recorded`. A M1 foi corrigida e passou a ter o SHA-256
`0e7789f173e5c6ed4ed7b6778c1aae06be729400e486e177b1af23923c173447`. O ensaio
foi refeito sobre uma restauração da base anterior às migrations:

| Passo | Resultado |
|---|---|
| Restauração do dump da base num banco novo com dono `postgres` | 0 erros; dados idênticos à base |
| Pré-checagem | OK |
| M1 (nova), M2, M3, M4, uma transação cada | Aplicadas |
| Dados legados | Idênticos |
| Checagens pós-upgrade 1 a 9 | OK |
| Testes de peso, rascunhos, documentos, redefinição (2), matriz de autorização e refeição | 7 de 7 passam |
| Reversão destrutiva, em transação desfeita | Remove 1 rascunho e o instante de 1 peso medido, como esperado |

Achado do procedimento de restauração: o banco de destino precisa ter o
usuário `postgres` como dono. A ACL do schema `public` dá `CREATE` ao dono do
banco (`pg_database_owner`). Um banco criado por `supabase_admin` impede as
migrations de criar funções.

## 6. O que este ensaio não prova
- Duração dos locks com o volume real do staging.
- Disponibilidade de backup ou PITR no staging: **não verificada** (acesso
  remoto bloqueado). O ensaio de restauração usou `pg_dump` local, não o
  backup da plataforma.
- A versão do Postgres do staging. O ensaio usou a 17.6. A M2 exige 15 ou
  mais.

## 7. Arquivos
- `01-seed-legacy.sql` — dados legados sintéticos
- `02-fingerprint-gen.sql` — gera a impressão digital dos dados legados
- `03-catalog-fingerprint.sql` — impressão digital do catálogo
- `04-preflight.sql` — pré-checagem somente leitura
- `05-post-upgrade-checks.sql` — checagens pós-upgrade, em transação desfeita
- `06-destructive-reversal.sql` — reversão destrutiva, nunca automática

Os hashes estão no pacote SQL v2.
