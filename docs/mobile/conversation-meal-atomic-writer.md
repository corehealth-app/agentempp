# Refeição conversacional — autoridade SQL inativa

A migração `20261103233331_conversation_meal_atomic_writer.sql` adiciona a autoridade
SQL de uma refeição resolvida, sua gravação atômica e o recibo factual original.
Não ativa uma rota ou caller, não sela feedback v2 e não implementa a experiência
completa do Flow. O adaptador real do calculador e a autoridade semântica integral
continuam obrigatórios antes de qualquer ativação.

## Sequência interna

1. Admitir a identidade permanente no journal existente. Um replay deve consultar
   o recibo antes de extrair, calcular, capturar ou inicializar o dia novamente.
2. Em um comando novo, a aplicação clínica diária existente pode inicializar o dia
   quando elegível. Esta autoridade não calcula nem inventa metas.
3. `capture_conversation_meal_source(owner, command_id)` grava uma captura privada
   imutável antes do calculador. Retorna `source_hash`, `captured_at` e `context`.
4. O calculador usa os lookups históricos reais descritos abaixo, coletando todos
   os recibos de fonte; nenhuma consulta à história viva substitui esse caminho.
5. `prepare_conversation_meal(owner, command_id, resolved)` valida e guarda uma
   preparação autoritativa imutável. Retorna seu `resolved_hash`.
6. `commit_conversation_meal(owner, command_id, resolved_hash)` usa somente essa
   preparação guardada. Pending confirmado, grupo de logs, fatos originais e
   recibo obrigatório são gravados na mesma transação.

`read_conversation_meal_effect(owner, command_id)` apenas consulta o recibo.
Nenhum estado ou status do candidato opaco autoriza gravação.

## Captura e fontes nutricionais

A captura contém o DTO original, epoch, dono/país/fuso, estado clínico estável,
versão exata da mídia processada e metas oficiais do dia. Exclui snapshot ID,
contadores de consumo e relógios de atualização do snapshot: uma segunda refeição
legítima deve continuar podendo usar uma captura anterior à primeira inclusão.
Dia ausente é normalizado como dia aberto com metas/protocolo desconhecidos.

A mídia conserva apenas a referência/versionamento e seu resultado processado,
legenda e transcrição privados; bucket/path/URLs de acesso não são copiados do
registro do ativo. As unidades de evidência são somente `command_text`,
`media_caption`, `media_transcript` e `vision_items`, quando realmente presentes.
Resultado de Vision permanece evidência de alimento; o gesto/texto original
continua necessário para a autoridade semântica de consumo.

Um epoch global privado avança em INSERT/UPDATE/DELETE que afetem linhas e em
TRUNCATE de `food_db`, `user_food_corrections` e `global_config`. Captura,
preparação e commit mantêm SHARE NOWAIT dessas fontes. Isso cobre aliases do
catálogo, verificação, remapeamentos pessoais, configuração e ABA sem transportar
valores de configuração alheios ao contexto clínico. Uma alteração não relacionada
nessas tabelas pode conservadoramente invalidar uma preparação em andamento.

`read_conversation_meal_nutrition_source(owner, command_id, kind, food_name)` é um
**lookup de preparação que persiste recibo**, não um GET público de status:

- `trusted_recent`, com nome NULL: últimos 50 registros das fontes confiáveis,
  kcal positivas e janela de 30 dias.
- `exact_median`, com nome: últimos 20 registros confiáveis que correspondem ao
  mesmo ILIKE usado pelo calculador existente, na mesma janela.

A janela termina no `captured_at` do banco; a ordenação é `created_at DESC,id DESC`.
O RPC grava consulta, linhas e hash antes de retornar. Tanto hits quanto misses
entram no recibo, junto a IDs, macros, referência e `food_db.is_verified`. O retorno
inclui `source_receipt_id`, `source_receipt_hash`, `as_of`, dono e comando. O adaptador
real deve consumir essas linhas e esse relógio, mantendo o caminho legado padrão.
Correções pessoais continuam usando o epoch de fonte e o mesmo `as_of` na janela.

Toda consulta executada deve constar em `source_receipts`; não se pode omitir uma
consulta vazia ou uma segunda referência. Preparar sela o conjunto e impede novos
lookups. Preparação e commit repetem as consultas com o mesmo cutoff e comparam
as linhas exatas, sob locks. Edição, exclusão ou miss que vira hit conflitam;
novos consumos posteriores ao cutoff não invalidam a inclusão independente.
O novo grupo recebe `created_at` igual ao relógio autoritativo do evento, evitando
que `now()` do início de uma transação entre em uma janela histórica anterior.

## Envelope resolvido fechado

`conversation.meal-resolved.v1` exige as chaves:

- `input_hash`, `source_hash`, `meal_type` e `semantic_proof`.
- `items`: nome canônico, `food_db_id` ou NULL, `nutrition_source`, quantidade e
  quatro nutrientes, confidence ou NULL, `input_indexes`, `quantity_basis`,
  `display_qty` e `display_unit` explícitos ou NULL.
- `totals`: quatro nutrientes na precisão de uma casa da proposta existente.
- `source_receipts`: todos os objetos `{ id, hash }` retornados pelos lookups.
- `preparation_annotations`: lista de anotações estruturadas efetivamente usadas.

A prova `conversation.meal-semantic.v1` contém `decision: consumed_meal`, os dois
hashes, `complete_source: true`, todas as `source_units` capturadas e `input_count`.
Os índices dos resultados devem cobrir todos os inputs do cálculo; nomes canônicos
duplicados são recusados antes do writer base. Este é um contrato de backend:
o classificador atual ou um match de uma palavra não produz essa prova sozinho.

Uma anotação de cozido padrão usa `consumed.preparation.v1`, `kind: default_cooked`,
índices reais de input, nome, política e referência. SQL não a deduz de warnings,
nome cozido ou fonte fuzzy. `pending_approved` não é fonte de um novo comando;
nenhuma linha de pending mutável pode ser injetada como outra proveniência.

## Commit, replay e recibo

A ordem é advisory do dono `:workouts` → usuário → epoch/comando → upgrade clínico
antes do lock de data → fontes/perfil/mídia/snapshot. READ COMMITTED é obrigatório.
O relógio após locks define dia, timestamp e provider exclusivo. O dia atual deve
estar aberto e o tipo selecionado no comando é preservado. Metas existentes,
inclusive NULL, permanecem exatamente iguais; dia novo recebe NULL se não houver
meta oficial. Nenhum fallback de perfil é publicado como meta.

O writer base recebe `replace=false`; não cancela outro pending ou inicializa
workout lifecycle. O grupo completo é relido e confrontado com IDs, fontes,
quantidades e nutrientes salvos a duas casas. Os totais da proposta e o snapshot
inteiro mantêm suas precisões próprias. Leitura/retry não cria XP, bloco ou efeito.

O recibo `conversation.meal-effect.v1` contém somente identidades, IDs de logs,
provider, refeição, fuso/data/timestamp e `effect_version`. Não contém números de
saúde, metas ou orientação. Fatos originais exatos ficam em tabela privada imutável.
O helper privado de feedback v2 é tentado sob os mesmos locks e sua fonte original
é congelada se disponível; falha opcional não desfaz nem repete a refeição.
Falha no recibo factual obrigatório desfaz também pending, logs e snapshot.

Uma futura selagem v2 deve usar essa fonte congelada; não recapturar estado atual
após C11 e chamá-lo de original. Esse sealer ainda não está instalado. Edits reais
C11 podem mudar os logs atuais, mantendo o registro factual original do comando.

Reset invalida os IDs permanentes e remove captura, lookups, preparação e fatos
pessoais em cascata pela fonte do journal. Um UUID concluído nunca readquire epoch.
Exclusão da conta pode apagar seus tombstones. Nenhuma tabela nova tem grant direto;
RLS sem policies e RPCs somente `service_role`, com contexto UTC/ISO fixo.

## Verificação e limites

As suítes SQL e o fixture de duas sessões cobrem o fluxo real de banco, incluindo
metas NULL/oficiais, mídia, catálogo/correções/configuração, história completa e
misses, clock/isolamento, falhas obrigatórias/opcionais, replay após 24 horas,
reset, C11 real, fontes congeladas e inclusão concorrente. São dados sintéticos
com rollback/cleanup em stack local de propriedade confirmada; não são QA de app.

O ensaio de migração remove somente o protótipo local comprovadamente vazio,
instala/transaciona/testa/rollback e compara catálogo/dados. Não é downgrade de
produção e não autoriza apagar tombstones reais. Nenhum rollout cloud foi feito.
Continua faltando integrar e qualificar o preparador semântico/calculador real,
selagem v2 a partir da fonte original, proteção de apresentação clínica atual,
correção/desfazer do comando, binding de mensagens e timeline paginada.
