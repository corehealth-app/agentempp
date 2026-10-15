# Projeção semanal de treinos confirmados — S12

Grupo dormente, sem caller/flag/reset/WhatsApp ou publicação. A RPC backend `get_confirmed_workouts_for_strength_week(uuid,uuid,uuid,text,date,date)` projeta somente fatos confiáveis para o core existente; não calcula X, Y, porcentagem ou calorias.

## Autoridade e leitura

Guard backend real, seis argumentos nãoNULL, READ COMMITTED e conta ativa. Depois de advisory de workout e conta NO KEY UPDATE, uma única instrução revalida o scope S11 owned e lifecycle ainda aberto, enumera todos os workout_logs vivos da conta, preserva gaps nos LEFT JOINs e constrói o resultado. O scope persistido não comprova cobertura, não expira pelo relógio atual e created_at não limita workouts posteriores/backdated. Nenhum catálogo/fuso atual reclassifica registros.

A precedência é: scope/lifecycle inválido→calendar_unproved; anchor real contraditório→identity_unproved; qualquer calendário/cobertura desconhecida no histórico vivo, oldlife ou fuso literal diferente→calendar_unproved; só com calendário global provado, classificação indisponível relevante→provenance_gap. Toda negativa traz workouts:null. Não existe subtotal. Legacy distante não é excluído por snapshot/instante/offset presumido.

Success tem apenas status available e workouts. Cada evento possui ownerKey, workoutKey real, localDate ISO persistida, state confirmed, catalogueCategory congelada ouNULL para unrecognized e storedStrengthAnswer owned de três campos ouNULL. Um unrecognized sem resposta continua válido. A ordem é localDate/UUID. Só após comprovar todo o calendário filtra as datas inclusivas do scope. Universo owned realmente vazio ou inteiramente provado fora da janela pode resultar em available[].

## Verificação local

Testes revisados e adotados antes do corpo da migração. Em PostgreSQL 17.11 local, passaram 59 assertivas SQL e quatro cenários A/B. Os dois primeiros chamaram S9 answer real e verificaram confirmação ou reversão após bloqueio observado. O terceiro inseriu um treino legado real sob advisory comum: depois do bloqueio e do commit, o UUID novo levou a calendar_unproved. No quarto, sem advisory, a primeira leitura retornou o universo vazio antes do commit e a seguinte negou o mesmo scope após o commit. Isso não comprova captura S8, reset ou todos os writers.

A consistência vale na snapshot da leitura final, sem promessa de bloquear DML direto ou congelar cobertura para sempre. O inventário real confirmou ausência dos overloads reservados antes do DDL. Dados, schema, funções, permissões e sequência ficaram idênticos antes/depois; os atores terminaram e o banco retido foi encerrado. Testes, runtime e controlador tiveram revisão independente antes da execução. O custo da varredura em históricos grandes, a integração de callers e a validação em staging/iPhone continuam pendentes. Históricos legacy/oldlife/foreignzone podem continuar indisponíveis. S12 não libera o beta integral.
