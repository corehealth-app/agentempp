# Scope de calendário de treino — S11

Grupo dormente: prepara uma observação de calendário para uma conta e um lifecycle já aberto. Não registra treino, responde pergunta, calcula meta ou comprova cobertura histórica. Nenhum caller, flag, reset ou WhatsApp é ativado.

## Contrato

`prepare_workout_strength_calendar_scope(uuid, uuid)` é uma RPC de backend com guard confiável existente, permissão de execução para service_role/owner e armazenamento privado sem DML externo. Primeiro serializa pela chave workout da conta e bloqueia a conta ativa; só depois lê o lifecycle aberto existente e captura uma única hora do banco. O fuso vem da conta bloqueada e deve corresponder literalmente a um nome listado pelo PostgreSQL.

O sucesso retorna somente `status` (`prepared` ou `reuse_existing`) e `scope`: `ownerID`, `lifecycleKey`, `scopeKey`, `timeZone`, `weekStartDate`, `asOfLocalDate`. Datas são ISO; `created_at` fica no banco. O início da semana é segunda ISO, e a data observada pertence a essa semana.

Uma nova linha possui sete campos: os seis dados acima, com nomes SQL, e `created_at`. O fuso tem collation C. A unicidade é conta + lifecycle + fuso literal + segunda + data observada. Repetir essa mesma tupla conserva a chave e a hora originais, inclusive depois de A→B→A. A troca de dia ou de fuso pode criar outra observação. Não existe garantia de recuperar a mesma tentativa através da meia-noite. A RPC faz apenas INSERT, sem trigger próprio; a exclusão da conta ou do lifecycle remove os scopes por cascade. O owner privilegiado do banco continua capaz de administrar as linhas.

Lifecycle ausente, de outra conta ou fechado retorna `forbidden/stale_lifecycle`; fuso sem prova retorna `unavailable/zone_unproved`; calendário irrepresentável retorna `unavailable/calendar_unproved`. Erros SQL, de configuração, lock ou escrita propagam. A RPC não abre lifecycle e não converte erro em sucesso ou fallback.

## Verificação local

Testes revisados e adotados antes do corpo da migração. Em PostgreSQL 17.11 local, passaram 71 assertivas sequenciais e dois cenários reais A/B (`scope-commit-reuse`, `scope-rollback-new`). Incluem guard real, permissões, shape, fuso oficial, armazenamento, reaproveitamento sem refresh, conservação de treino legado sem fato, falha atômica de INSERT, cascades e colisões CREATE-only. O inventário real confirmou ausência dos objetos reservados antes do DDL. O snapshot integral de dados, schema, funções, permissões e sequência ficou idêntico antes/depois; os atores terminaram e o banco retido foi encerrado.

As duas disputas observaram bloqueio real por `pg_blocking_pids`, com margem objetiva até a meia-noite maior que o prazo total. Sem margem, o setup aborta; não simula relógio nem atribui mudança legítima de data a bug. O limite inferior após a espera vale só para a nova linha; reuse conservou `created_at` anterior. Fronteiras ano1/9999 e o dia histórico semeado são controles de armazenamento/matemática, não execução do runtime em um relógio raro.

Teste, runtime e controlador tiveram revisão independente antes da execução limitada. A verificação local deste grupo não comprova autenticação PostgREST, cobertura histórica do S12, integração com callers, staging, produção, beta completo ou funcionamento no iPhone. Nenhuma ativação foi realizada.
