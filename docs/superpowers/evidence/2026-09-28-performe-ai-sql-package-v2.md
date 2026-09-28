# Performe AI — pacote SQL consolidado v2 (M1, M2, M3, M4)

Data: 2026-09-28. Substitui o pacote v1
(`2026-09-28-performe-ai-functional-beta-v3-sql-package.md`). **A aprovação
do v1 não vale para este pacote:** o hash da M1 mudou duas vezes e a M4 é
nova.

**Estado: NÃO APLICADO em nenhum banco remoto.** Tudo foi aplicado só em
bancos locais descartáveis. **Este documento não aprova SQL remoto.** Nada é
aplicado sem o texto de autorização da seção 12, escrito pelo Eduardo.

Alvo único, se aprovado: Supabase **staging** `xitugspwfxkcluxvrdeg`.
Produção `xuxehkhdvjivitduarvb`: fora deste pacote. Não acessar.

## 1. Arquivos e hashes (SHA-256)

| Ordem | Arquivo | SHA-256 |
|---|---|---|
| 1 | `supabase/migrations/20260928120000_bodyflow_weight_measurement.sql` (M1) | `0e7789f173e5c6ed4ed7b6778c1aae06be729400e486e177b1af23923c173447` |
| 2 | `supabase/migrations/20260928130000_bodyflow_plan_drafts.sql` (M2) | `68b3b2ed6a2c446959a7a44517e5cbeae46bf7f5f5e89676f2831baf496ea9fd` |
| 3 | `supabase/migrations/20260928140000_bodyflow_plan_documents.sql` (M3) | `1766702c035380f8c0f5581171410096dc99cd28ecdb370343cf7e5cb527f8f0` |
| 4 | `supabase/migrations/20260928150000_bodyflow_reset_keeps_plans.sql` (M4) | `24ce40fa6f1561f95fdf0c55d3bb65110e58841bfc927020601e9b4a7d056636` |

Testes que rodam depois da aplicação (cada um em transação terminada em
`ROLLBACK`):

| Arquivo | SHA-256 |
|---|---|
| `supabase/tests/bodyflow_weight_measurement.sql` | `002285e0f5ffd4345b513aeae28a8f25a44eb61b6587547f17797e6524d54b85` |
| `supabase/tests/bodyflow_plan_drafts.sql` | `791ed6c42e5bb092caf5475231d45943eab65176778fba80ae70e8f6df006d34` |
| `supabase/tests/bodyflow_plan_documents.sql` | `934aa7031ce3101ce77c60e27dd853f3f66b64aaef7711e92e6cdd245c320eaa` |
| `supabase/tests/bodyflow_reset_keeps_plans.sql` | `917505535f93d38fe17cddb4242036ed9a1e951556ad73fd29f059912ca9e853` |
| `supabase/tests/reset_user_conversation_atomic.sql` | `1a24513d4d86836a698a66005ba7dd6fbbbd6a332201850381feea5bf5b7483e` |

Scripts auxiliares (`docs/superpowers/evidence/2026-09-28-sql-upgrade-rehearsal/`):

| Arquivo | Uso no staging | SHA-256 |
|---|---|---|
| `04-preflight.sql` | Sim, somente leitura, antes de aplicar | `b1bd41d6ae557e20c7d375412087bbe67abab52ddcb0546877ed5135512ddc88` |
| `06-destructive-reversal.sql` | **Só com autorização própria e escrita**; nunca automático | `b7c377e0dbe240e57d44f5c4a608bf9c2c20a48fb4e9987c27e76cf7611273c6` |
| `01-seed-legacy.sql` | Não; só no ensaio local | `efdb41e8efa122e42499f3ad9f65aea0620a6a2d43d84440cd0bfbd0c4bfe5a7` |
| `02-fingerprint-gen.sql` | Não; só no ensaio local | `ecacc1b660f7ff8220718bee517f40466e5fc418127af48269518d98f65f79e1` |
| `03-catalog-fingerprint.sql` | Não; só no ensaio local | `be46499f5ce9abd6f44bb0af22d8faf0bbad325a1fad1905e087d08cb3e76d31` |
| `05-post-upgrade-checks.sql` | Não; usa os pacientes sintéticos do ensaio | `ffd01e1df07199c2fee13e06cf0313237c74d8e0f210c4a13ca99e5528f6e01c` |

## 2. Por que a M1 mudou (e por que a aprovação anterior não vale)

1. Em `2a88c19`: coluna `weight_instant_source` (`measured` ou `recorded`).
   Um instante de gravação não pode ser apresentado como instante de medição.
2. Em `1a1322d`, depois da revisão adversarial: a segunda pesagem do app era
   rotulada `recorded` (HIGH). O caminho ordenado agora marca a própria
   gravação numa configuração local da transação. Instante apagado deixa a
   origem nula. A `CHECK` é recriada com `DROP ... IF EXISTS`.

Diff completo: `git diff 3d450e6 1a1322d -- supabase/migrations/20260928120000_bodyflow_weight_measurement.sql`.

## 3. O que cada migration faz

- **M1 — peso na fonte oficial.** Colunas anuláveis `weight_measured_at` e
  `weight_instant_source` em `user_profiles`, sem backfill. Gatilho para os
  escritores legados (rotulados `recorded`). Caminho ordenado
  `private.apply_weight_measurement` e `public.record_weight_atomic`
  (rotulados `measured`). Não escreve `daily_snapshots`, `user_progress` nem
  o bloco 7.700. Não altera fórmula.
- **M2 — rascunhos de plano.** Tabela `plan_drafts` com RLS; coluna
  `prescriptions.source_request_key`; índices únicos `media_assets (id,
  user_id)` e `messages (id, user_id)`; cinco RPCs de rascunho;
  `save_training_plan_atomic` recriada com a mesma assinatura.
- **M3 — documentos de plano.** Bucket privado `plan-documents` (20 MiB) e o
  tipo `plan_document` nas restrições de `media_assets`. Documento sem prazo
  de retenção automática. O bucket e o banco aceitam HEIC. A API do app não
  aceita HEIC para documento de plano, então o banco é mais amplo que a API.
- **M4 — redefinição que mantém planos.** `reset_user_conversation_atomic(uuid,
  boolean)`. Com `true`, que é o padrão, mantém planos, prescrições,
  rascunhos e a entrega diária do treino. A versão de 1 argumento passa a ser
  um invólucro que mantém os planos. A M4 também passa a exigir
  `assert_trusted_backend()` e recusa argumentos nulos.

## 4. Permissões
- RPCs novas e `record_weight_atomic`: `EXECUTE` só para `service_role`.
- Funções `private.*` novas: nenhum papel de cliente executa.
- `plan_drafts`: RLS ligada; papéis de cliente sem privilégio de tabela.
- `weight_instant_source`: papéis de cliente sem `UPDATE`.
- Bucket `plan-documents`: privado, sem política pública.

Tudo conferido no ensaio (checagens 5 a 7 de `05-post-upgrade-checks.sql`).

## 5. Ordem de aplicação no staging

0. **Antes de tudo:** o Eduardo confirma no painel do Supabase
   (Database → Backups) se o staging tem backup do dia ou PITR, e anota o
   resultado. Nada é contratado para isso.
1. Rodar `04-preflight.sql` (somente leitura). Qualquer erro: parar.
2. **Opcional, se `messages` ou `media_assets` forem grandes:** criar os
   índices antes, um comando por vez e fora de transação:
   ```sql
   CREATE UNIQUE INDEX CONCURRENTLY media_assets_id_user_unique ON public.media_assets (id, user_id);
   CREATE UNIQUE INDEX CONCURRENTLY messages_id_user_unique ON public.messages (id, user_id);
   ```
   Depois, rodar `04-preflight.sql` de novo. `IF NOT EXISTS` só confere o
   nome. Um índice inválido, deixado por um cancelamento, ou com outra
   definição seria mantido em silêncio pela M2, como o ensaio mostrou. Se a
   pré-checagem recusar, usar `DROP INDEX CONCURRENTLY` e criar de novo.
3. M1, M2, M3 e M4, **cada uma numa transação**, com `SET LOCAL lock_timeout =
   '5s'`. Se o tempo acabar, a transação volta inteira. Inspecionar o estado
   com a pré-checagem antes de tentar de novo. Não repetir às cegas.
4. Rodar os cinco arquivos de teste da seção 1.
5. Só depois: publicar o código que chama a M4. A tela do admin envia
   `p_keep_plans`, e sem a M4 a redefinição falha, sem apagar nada.

Pré-requisitos a conferir no passo 1: Postgres 15 ou mais novo (a M2 usa `ON
DELETE SET NULL (coluna)`) e `service_role` com `USAGE` em `private`.

## 6. Locks e duração (ensaio local, tabelas quase vazias)

| Migration | Tempo | Locks |
|---|---|---|
| M1 | 48,9 ms | `user_profiles` AccessExclusive |
| M2 | 26,2 ms | `prescriptions` AccessExclusive; `media_assets`, `messages` Share; `users` ShareRowExclusive |
| M3 | 4,5 ms | `media_assets` AccessExclusive (valida as linhas existentes) |
| M4 | 2,9 ms | nenhum lock de tabela |

Com o volume real, os índices da M2 e a validação da M3 levam mais tempo sob
lock. Uma observação de lock em `storage.buckets` não se reproduziu e segue
aberta (ver o `README.md` do ensaio).

## 7. Compatibilidade
- **Código antigo com o SQL novo:** compatível. As assinaturas usadas pelo
  código antigo não mudaram. A redefinição de 1 argumento continua existindo
  e mantém os planos. Os escritores legados de peso, mídia e prescrição
  funcionam, conforme o ensaio.
- **Código novo sem o SQL:** `/profile` tolera a falta das colunas; peso,
  rascunhos e importação respondem erro. A redefinição do admin falha.
- **WhatsApp:** nenhuma ferramenta muda. A entrega diária não envia plano
  confirmado no app (`2a88c19`).

## 8. Recuperação — quatro formas, ensaiadas localmente

| Forma | Perda de dados | Ensaio |
|---|---|---|
| Rollback de transação | Nenhuma | M1–M4 numa transação desfeita: catálogo e dados idênticos à base |
| Reversão de aplicação (voltar o deploy) | Nenhuma | Assinaturas preservadas |
| Restauração de backup | Tudo que foi gravado depois do backup | `pg_restore` local: dados idênticos. O banco de destino precisa ter `postgres` como dono |
| Reversão destrutiva (`06-destructive-reversal.sql`) | **Sim**: rascunhos, documentos de plano, chaves de idempotência de prescrição, instante e origem dos pesos medidos | Exercitada em transação desfeita. O bucket só sai pela API de Storage |

**A reversão destrutiva não é "sem perda de dados" e nunca é automática.**

## 9. Testes
- Base limpa local: SQL 38 de 40. As 2 falhas estão classificadas:
  - `bodyflow_coach_messages`: desvio de produto no push do servidor, fora
    do beta;
  - `p0_crons_inactive`: asserção só do ambiente de staging.
- Ensaio de upgrade a partir da base anterior: 38 de 40, as mesmas duas.
- Novo ensaio com a M1 final: checagens 1 a 9 e 7 testes de migration passam.
- Concorrência: 24 pesos fora de ordem, vence o mais novo; replay e corrida
  de confirmação de rascunho sem duplicar nem deixar órfão.

## 10. Revisão adversarial
Agente somente leitura, 2026-09-28, sobre `2a88c19`. Duas HIGH (rótulo da
segunda pesagem; dose separada em número e unidade) e cinco MEDIUM do código
corrigidas em `1a1322d`. As duas restantes eram deste pacote: a ordem de
deploy (seção 5) e o pacote v1 desatualizado (este documento o substitui).
Limites aceitos e registrados: nome de remédio sem unidade nem termo ("Losartana
50") não é reconhecido; "gotas" não conta como dose. **Revisão de agente não
substitui revisão humana.**

## 11. Pendências fora deste pacote
- `agent_configs.allowed_tools` do staging precisa listar
  `propoe_plano_treino` e `propoe_plano_dieta`. É escrita remota e tem
  autorização própria.
- `bodyflow_coach_messages`: dono do push do servidor decide.
- Conta de autenticação não apagada pela rotina de exclusão (ver
  `docs/legal/performe-ai/evaluation-2026-10/checklist-decisoes.md`).

## 12. Texto exato de autorização

> Autorizo aplicar no Supabase staging `xitugspwfxkcluxvrdeg`, nesta ordem e
> cada uma em sua própria transação, as migrations M1
> (`0e7789f173e5c6ed4ed7b6778c1aae06be729400e486e177b1af23923c173447`), M2
> (`68b3b2ed6a2c446959a7a44517e5cbeae46bf7f5f5e89676f2831baf496ea9fd`), M3
> (`1766702c035380f8c0f5581171410096dc99cd28ecdb370343cf7e5cb527f8f0`) e M4
> (`24ce40fa6f1561f95fdf0c55d3bb65110e58841bfc927020601e9b4a7d056636`),
> precedidas da pré-checagem `04-preflight.sql` (`b1bd41d6…dc88`) e, se
> necessário, da criação concorrente dos dois índices; e rodar em seguida os
> cinco arquivos de teste listados. Não autorizo produção, backfill, alteração
> de dados de paciente, a reversão destrutiva nem mudança em
> `agent_configs`.

Se qualquer hash mudar, esta autorização deixa de valer para o arquivo
alterado. Uma autorização de M1 a M4 não cobre migrations adicionais.
