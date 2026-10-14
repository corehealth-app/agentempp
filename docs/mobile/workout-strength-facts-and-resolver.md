# Fatos de treino e resolução de vínculos

Etapa dormente: não ativa captura, perguntas, consumidores, reset ou WhatsApp.
O contrato não muda calorias, nome do treino nem a API legada.
O índice novo `(user_id,id)` em `daily_snapshots` atende à FK composta; a
tabela é compartilhada com o legado do WhatsApp. A implantação futura exige
verificar versão, alvo e locks; esta etapa permanece local.

## Armazenamento privado

`private.workout_strength_facts` mantém 30 colunas:

- Âncora: `user_id`, `workout_log_id`, `lifecycle_key`, `snapshot_id`,
  `stored_workout_type`, `performed_at`, `snapshot_date`.
- Classificação: `classification_status`, `classification_reason`,
  `observation_key`, `observed_at`, `matcher_version`, `active_row_count`,
  `match_method`, `catalogue_id`, `catalogue_slug`, `catalogue_display_name`,
  `catalogue_category`, `catalogue_updated_at`.
- Calendário: `calendar_status`, `calendar_reason`, `local_date`, `time_zone`,
  `zone_source`, `zone_observed_at`.
- Resposta: `question_key`, `answer`, `answer_operation_key`,
  `answer_accepted_at`, `revision`.

Grupos e NULLs devem ser coerentes. FKs compostas ligam conta, ciclo, treino e
snapshot reais. RLS sem policies e revogação de DML externo não impedem o owner
de alterar linhas; não comprovam proveniência ou imutabilidade funcional.

## Leitura autorizada

O helper privado `workout_strength_fact_snapshot(uuid,uuid,uuid)` é owner-only,
SECURITY INVOKER, com search_path `pg_catalog`. Compara o fact à linha owned do
treino e ao snapshot real, inclusive ciclo, tipo, instante e data. Falta ou
inconsistência retorna SQL NULL. Não consulta catálogo ou fuso atuais.

Contrato da RPC pública `resolve_confirmed_workout_strength_capture`:
`p_user_id`, `p_expected_lifecycle_key`, `p_operation_key`,
`p_original_operation_type`. O texto original é exato, anterior a btrim.
EXECUTE é somente owner/service_role; guard existente primeiro. Exige READ
COMMITTED, advisory legado de treinos e owner ativo FOR NO KEY UPDATE antes de
validar ciclo aberto e binding de captura. Não abre ciclos automaticamente.

- Ciclo ausente/fechado: `forbidden/stale_lifecycle`.
- Binding ausente: `unavailable/operation_key_missing`, ID nulo.
- Tombstone ou âncora/fact ausente ou incoerente: `forbidden/stale_workout`.
- Gap legado: `unavailable/legacy_provenance_gap`, com UUID real, sem fact novo.
- Fact válido: `reuse_existing`, binding e fact no formato R2.

Owner ausente/inativo gera P0002; sintaxe/isolamento inválidos, 22023; guard,
42501. Falhas operacionais não viram lista vazia ou sucesso. O DTO não expõe
`active_row_count`. Instantes usam UTC com seis casas, sem arredondar; calendário
e classificação persistidos não são refeitos pelo estado atual. No replay X26,
a âncora segue o UUID real/snapshot original, não o snapshot da tentativa.

## Verificação local

Execução local: 92 verificações SQL únicas aprovadas, incluindo a guarda em
REPEATABLE READ e os cenários em READ COMMITTED, API legada real e rollback.
Schema, funções, ACLs, dados e sequência ficaram byte idênticos no snapshot
antes/depois. PostgreSQL local encerrado, sem autostart. Evidência registrada
em `codex-u2-c59a3a-s5-evidence-20261014/run-r1`. Sem execução em staging/produção. Sem prova de CAS, concorrência,
primeira resposta, cobertura semanal, integração do app ou beta completo.
