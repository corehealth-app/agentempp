# Armazenamento dos vínculos de treino

Esta estrutura é dormente. Não abre ciclos automaticamente, não recebe DML dos
papéis externos e não ativa captura, perguntas, contagem semanal ou consumidores.

## Identidade e exclusão

`private.workout_strength_lifecycles` pertence à conta e permite um ciclo aberto
por conta, conservando ciclos fechados. Ele é independente de autenticação,
fotos, semana e meta de frequência.

`private.workout_strength_operations` separa os endereços de captura e resposta.
A captura usa conta, ciclo, chave e texto original exato; a resposta usa conta,
ciclo e chave. Chaves e texto original usam collation C. O armazenamento conserva
espaços e caixa, sem criar equivalência por nome normalizado.

O UUID original do treino permanece mesmo após sua exclusão. Uma referência viva
separada usa FK composta com a conta; a exclusão limpa somente essa referência.
O treino substituto não recebe automaticamente operações do treino excluído.
A exclusão da conta remove seus ciclos e operações por cascade.

Uma resposta com chave B pode conservar o recibo vencedor A. Ela guarda o próprio
conteúdo original, inclusive a revisão esperada, sem reescrever a chave do recibo.
Os CHECKs validam a forma e as correlações locais, inclusive NULL/JSON null.
O recibo JSON, sozinho, não autentica uma resposta nem comprova um fact existente.

Imutabilidade contra alterações feitas pelo owner, admissão no ciclo atual,
captura atômica, replay, calendário e primeira resposta vencedora precisam das
funções futuras. Os testes de DML como owner verificam apenas o armazenamento.

## Índices e implantação

O único índice público novo é `workout_logs_user_id_id_key`, necessário à FK de
conta e treino. O PK global de `id` já garante a unicidade dos dados existentes.
As operações têm dois índices privados não únicos para localizar vínculos por
ciclo e por treino vivo, além das duas chaves parciais por tipo de operação.
FKs não criam automaticamente índices nas colunas que fazem a referência.
[Documentação do PostgreSQL 17](https://www.postgresql.org/docs/17/ddl-constraints.html#DDL-CONSTRAINTS-FK).

Antes de aplicar remotamente, conferir versão, dados, tamanho, locks e estratégia
de implantação do índice. A compatibilidade local com PG17 não comprova a versão
ou o comportamento do staging. Os grants legados e o registro de treino existente
permanecem fora desta migração.

## Teste local

`supabase/tests/workout_strength_bindings.sql` roda somente em banco sintético
exclusivo, com todos os caminhos e hashes fixados pelo executor. Ele inclui a API
legada real e cria treinos antes de aplicar a migração. Verifica replay, correção
com novo UUID e totais oficiais, referências excluídas, conta vizinha, constraints
e permissões dentro de BEGIN/ROLLBACK. A exclusão direta de treino é um caso de FK,
sem alegação de recomputar calorias.

O executor compara schema, funções, ACLs, dados e sequências antes/depois e prova
o encerramento do PostgreSQL pertencente ao teste. Esse teste não é um benchmark
nem substitui integração do app, concorrência ou validação no staging.
