# Performe AI — pacote consolidado de SQL (M1 + M2 + M3)

> **SUBSTITUÍDO** em 2026-09-28 por `2026-09-28-performe-ai-sql-package-v2.md`.
> O hash da M1 abaixo não é mais o do arquivo, a M4 não está aqui e a seção 7
> descreve a reversão como "só de estrutura", o que está errado. Não usar
> este documento para aprovar nada.

Operação: `PERFORME_AI_COMPLETE_FUNCTIONAL_BETA_EXECUTION_V3`.
Data: 2026-09-28.

**Estado: NÃO APLICADO em nenhum banco remoto.** As três migrations existem
como arquivos e foram aplicadas somente a um Postgres local, descartável,
criado para esta operação. A aplicação no staging depende de aprovação
explícita deste pacote.

Alvo único, se aprovado: Supabase **staging** `xitugspwfxkcluxvrdeg`.
Produção (`xuxehkhdvjivitduarvb`) não faz parte deste pacote.

## 1. Arquivos e hashes (SHA-256)

| Ordem | Arquivo | SHA-256 |
|---|---|---|
| 1 | `supabase/migrations/20260928120000_bodyflow_weight_measurement.sql` (M1) | `e92c2884143e12334e01ca813667640f38ed549f929417148ef51c6a1819a6ce` |
| 2 | `supabase/migrations/20260928130000_bodyflow_plan_drafts.sql` (M2) | `68b3b2ed6a2c446959a7a44517e5cbeae46bf7f5f5e89676f2831baf496ea9fd` |
| 3 | `supabase/migrations/20260928140000_bodyflow_plan_documents.sql` (M3) | `1766702c035380f8c0f5581171410096dc99cd28ecdb370343cf7e5cb527f8f0` |

Testes:

| Arquivo | SHA-256 |
|---|---|
| `supabase/tests/bodyflow_weight_measurement.sql` | `862a4a1e7bdbbedba36429678ed6029c3c36c707b2da11bef78932d667ae0904` |
| `supabase/tests/bodyflow_plan_drafts.sql` | `791ed6c42e5bb092caf5475231d45943eab65176778fba80ae70e8f6df006d34` |
| `supabase/tests/bodyflow_plan_documents.sql` | `934aa7031ce3101ce77c60e27dd853f3f66b64aaef7711e92e6cdd245c320eaa` |

Commits que contêm os arquivos: `17d19661` (M1), `18b87e81` (M2, M3),
`075a9c96` (correções da revisão). Qualquer alteração posterior muda o hash
e invalida a aprovação.

## 2. O que cada migration faz

### M1 — peso na fonte oficial
- Coluna nova `user_profiles.weight_measured_at` (anulável, sem backfill).
- Gatilho `private.sync_weight_measured_at` em `user_profiles`
  (`BEFORE INSERT OR UPDATE OF weight_kg, weight_measured_at`).
- `private.apply_weight_measurement` (caminho ordenado) e
  `public.record_weight_atomic` (entrada do app).
- Não escreve em `daily_snapshots`, `user_progress` nem no bloco 7.700; não
  altera fórmula.

### M2 — rascunhos de plano
- Tabela nova `public.plan_drafts`, com RLS ligada.
- Coluna nova `prescriptions.source_request_key` + índice único parcial.
- Índices únicos novos: `media_assets (id, user_id)` e `messages (id, user_id)`.
- Índice único parcial: um rascunho por documento.
- Gatilho `private.enforce_plan_draft_transition`.
- Função interna `private.replace_active_training_plan`;
  `public.save_training_plan_atomic` é recriada com a **mesma** assinatura,
  o mesmo resultado e os mesmos efeitos, passando a usar a função interna.
- RPCs novas: `create_plan_draft_atomic`, `resolve_plan_draft_work_atomic`,
  `update_plan_draft_atomic`, `discard_plan_draft_atomic`,
  `confirm_plan_draft_atomic`.

### M3 — documentos de plano
- Bucket privado novo `plan-documents` (20 MiB; PDF e imagens).
- Novo valor `plan_document` nas restrições de `media_assets` (tipo, bucket,
  MIME, tamanho). As regras dos tipos existentes ficam iguais.
- Documento de plano **nunca** tem data de retenção: o job de retenção não o
  alcança. Quem apaga é o paciente.

## 3. Permissões, RLS e buckets

| Objeto | anon | authenticated | service_role |
|---|---|---|---|
| `plan_drafts` (tabela) | nada | `SELECT` só das colunas de estado (`id`, `user_id`, `domain`, `origin`, `status`, `payload_version`, datas), e só das próprias linhas | leitura e escrita |
| `plan_drafts.payload`, `extraction_payload`, `request_key`, `origin_detail` | nada | nada | leitura e escrita |
| RPCs de rascunho e `record_weight_atomic` | nada | nada | `EXECUTE` |
| `save_training_plan_atomic` | nada | nada | `EXECUTE` (como antes) |
| Funções `private.*` | nada | nada | `EXECUTE` só em `replace_active_training_plan` |
| Bucket `plan-documents` | sem política | sem política | acesso pelo backend (URL assinada) |

Toda RPC `SECURITY DEFINER` chama `private.assert_trusted_backend()` na
primeira instrução e usa `search_path` fixo terminando em `pg_temp`.

## 4. Ordem de aplicação

0. **Opcional, recomendado se `messages` for grande:** criar antes, um
   comando por vez e fora de transação:
   ```sql
   CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS media_assets_id_user_unique
     ON public.media_assets (id, user_id);
   CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS messages_id_user_unique
     ON public.messages (id, user_id);
   ```
   A M2 encontra os índices prontos e não os reconstrói.
1. M1.
2. M2.
3. M3.
4. Testes SQL dos três arquivos (cada um roda em transação e termina em
   `ROLLBACK`).

Pré-verificações no staging (somente leitura) antes de aplicar:
- `select has_schema_privilege('service_role', 'private', 'USAGE')` deve ser
  `true` (a `save_training_plan_atomic` passa a depender disso).
- `select count(*) from public.messages` para decidir o passo 0.
- `select to_regclass('public.plan_drafts')` deve ser nulo.
- Versão do Postgres ≥ 15 (a M2 usa `ON DELETE SET NULL (coluna)`).

## 5. Compatibilidade

- **Código antes do SQL:** seguro. `/profile` tolera a falta de
  `weight_measured_at`; o chat do Flow responde sem o atalho da proposta se
  `plan_drafts` não existir; a exclusão de mídia trata a falta da tabela como
  "nenhum rascunho". `POST /weight`, rascunhos e importação respondem erro
  até o SQL existir.
- **SQL antes do código:** seguro. O código atual não conhece os objetos
  novos; a `save_training_plan_atomic` mantém o contrato.
- **WhatsApp:** nenhuma ferramenta nem fluxo muda. O único objeto existente
  que é recriado é `save_training_plan_atomic` (ver riscos).

## 6. Impacto e bloqueios

- M1: `ALTER TABLE ... ADD COLUMN` anulável (instantâneo) e criação de
  gatilho em `user_profiles`.
- M2: os dois índices únicos bloqueiam escrita nas tabelas enquanto são
  construídos, se o passo 0 não for feito. Em `messages` isso pausa a
  entrada de mensagens pelo tempo da construção. As chaves estrangeiras
  pegam bloqueio breve em `messages`, `media_assets` e `users`.
- M3: troca de restrições `CHECK` em `media_assets` (valida as linhas
  existentes; as novas regras são um superconjunto das atuais).
- Custo permanente: um índice a mais em cada escrita de `messages` e de
  `media_assets`.
- Recomendado aplicar com `SET lock_timeout = '5s'` e repetir se expirar.

## 7. Backup e reversão

- Antes de aplicar: confirmar no painel do Supabase que há backup/PITR do
  staging do dia.
- Reversão (nenhum dado de paciente é alterado pelas migrations, então a
  reversão é só de estrutura):
  - M3: recriar as cinco restrições anteriores e remover o bucket
    (só possível se não houver `plan_document`).
  - M2: `DROP TABLE plan_drafts`; remover as funções novas; recriar
    `save_training_plan_atomic` a partir de
    `20260712001000_save_training_plan_atomic.sql`; remover
    `prescriptions.source_request_key` e os índices novos.
  - M1: remover o gatilho, as funções e a coluna.
- Um script de reversão não foi escrito nem testado; se a reversão for
  necessária, ela será preparada e apresentada antes de ser executada.

## 8. Testes executados (somente local)

Ambiente: container próprio `performe-v3-db`
(`public.ecr.aws/supabase/postgres:17.6.1.167`), 165 migrations aplicadas do
zero.

| Verificação | Resultado |
|---|---|
| Todos os testes SQL do repositório | 35 de 39 passam |
| As 4 falhas | As mesmas de antes destas migrations: 3 dependem da data do dia; 1 verifica crons do staging |
| `bodyflow_weight_measurement.sql`, `bodyflow_plan_drafts.sql`, `bodyflow_plan_documents.sql` | passam |
| Remoção de cada proteção (11 variações) | o teste correspondente falha em todas |
| 8 confirmações simultâneas por domínio | 1 confirmada, 7 recusadas (`plan_changed_during_review`) |
| A mesma confirmação 6 vezes ao mesmo tempo | 1 plano, 6 respostas iguais |
| Confirmação de treino contra gravação do WhatsApp | 1 vencedor |
| Confirmação de dieta iniciada durante uma gravação direta não commitada | espera e é recusada |
| 24 registros de peso simultâneos fora de ordem | vence o mais novo |

Não testado: aplicação sobre um banco com os dados reais do staging;
duração dos bloqueios; comportamento com `messages` grande.

## 9. Revisão independente

Revisão adversarial por agente somente de leitura em 2026-09-28. Nenhum
achado crítico. Dois altos e oito médios; os corrigidos estão no commit
`075a9c96`.

Corrigidos: serialização da confirmação de dieta; teste como `service_role`;
teste do guard isolado; âncora de mensagem preservando o rascunho; índices
criáveis antes; falsa recusa por prescrição vencida; proteção de plano
prescrito também na dieta; documento de plano sem data de retenção;
confirmação só pela RPC; versão que não retrocede; instante do peso que não
retrocede.

## 10. Diferenças em relação ao desenho v1.1 (pedem aprovação junto)

1. M1 usa gatilho para os escritores legados, em vez de alterar cada
   escritor; a conversão de libra acontece na RPC.
2. M2 tem uma quinta RPC (`resolve_plan_draft_work_atomic`) para o resultado
   da leitura de documento.
3. `domain: auto` não existe: o paciente escolhe treino ou plano alimentar.
4. Limite de 20 rascunhos abertos por paciente.
5. Expiração avaliada na leitura e na escrita; não há job que grave
   `expired`.
6. Um documento gera um rascunho (índice único parcial).
7. Plano importado não recebe validade; o gerado segue a regra dos
   geradores.
8. Plano confirmado registra `flow_draft`, `patient_import` e o sufixo
   `_edited`.
9. Documento de plano sem retenção automática (a proposta de 90 dias do
   desenho não é política aprovada).

## 11. Pendências conhecidas (não resolvidas por este pacote)

| Item | Situação |
|---|---|
| A redefinição de conversa (`reset_user_conversation_atomic`) não limpa os rascunhos do paciente | Decisão pendente. Hoje o rascunho sobrevive sem a âncora da mensagem |
| Peso: escrita legada com o **mesmo** valor não renova o instante | Documentado na M1 |
| Peso: a chave de idempotência é validada e não é gravada; a idempotência real é (instante, valor) | Documentado |
| `generated_by = 'professional'` não é gravado por nenhum código hoje | A proteção existe e só age quando esse valor existir |
| Entrega diária pelo WhatsApp envia o plano ativo, inclusive um confirmado no app, se o paciente já tinha a entrega ligada | Fora deste pacote (toca o job do WhatsApp) |
| M2 não é reexecutável inteira (a tabela e as restrições não usam `IF NOT EXISTS`) | Aplicar uma vez |
| Configuração `agent_configs.allowed_tools` do staging | Se a lista existir e não tiver `propoe_plano_treino` e `propoe_plano_dieta`, o Flow não oferece propostas. Alterar essa lista é escrita remota e precisa de autorização própria |

## 12. Autorização pedida

Texto exato:

> Autorizo aplicar no Supabase staging `xitugspwfxkcluxvrdeg`, nesta ordem,
> as migrations M1 (`e92c2884…a6ce`), M2 (`68b3b2ed…a9fd`) e M3
> (`1766702c…f8f0`), com o passo 0 de índices concorrentes, e rodar em
> seguida os três arquivos de teste. Não autorizo produção, backfill nem
> alteração de dados de paciente.

Sem essa autorização nada é aplicado.
