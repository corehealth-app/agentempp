# Observação do catálogo de treinos

Esta etapa é dormente: não há consumidor ativo, nova flag de ambiente ou alteração
no registro de treinos, nas calorias, no app ou no WhatsApp.

## Componentes

- `packages/core/src/workout-strength-classification.ts`: classificação pura pelo
  slug ativo ou por um único nome normalizado. `outro` continua genérico.
- `packages/agent/src/workout-strength-catalogue.ts`: porta RPC injetada. Sem
  `enabled: true`, retorna apenas `disabled`, sem construir cliente ou ler dados.
- `public.get_workout_strength_catalogue_context()`: leitura sem argumentos,
  protegida pelo guard existente e com EXECUTE somente para owner/service_role.

A RPC obtém quantidade e todas as linhas ativas na mesma consulta. O resultado
contém quantidade decimal em texto, UUIDs ordenados, valores literais e horários
UTC com seis casas decimais. Não normaliza o catálogo nem calcula calorias.
Fonte conhecida inválida produz `catalogue_invalid`; falhas SQL propagam.
As permissões SELECT existentes da tabela permanecem preservadas.

O observer valida o conjunto inteiro antes de classificar. Uma resposta parcial
vira `catalogue_incomplete`, sem concluir que o treino é desconhecido. Somente
falha da chamada RPC auxiliar vira `catalogue_read_error`; erros de configuração
ou defeitos internos do parser/classificador propagam. Não há retry automático.

## Limites da etapa

O formato válido, a porta injetada e a chave da observação não autenticam a origem
do dado. A observação também não prova que o catálogo permaneceu igual até a
confirmação de um treino. A integração futura deve vincular o texto original à
operação e validar o conjunto completo na transação de captura. Esta etapa não
cria esse vínculo, ciclo de vida, resposta de força, cobertura de calendário ou
contador semanal.

## Verificação local

O teste `supabase/tests/workout_strength_catalogue.sql` exige banco local sintético
exclusivo, guard/roles existentes e ausência dos objetos que cria. O executor deve
fixar o caminho absoluto e o hash da migration na variável `migration_path`.
O teste inclui a fixture, aplica a migration e verifica leitura/permissões dentro
de BEGIN/ROLLBACK. O executor compara também schema, funções, ACLs, dados e
sequências antes/depois e encerra somente o PostgreSQL pertencente ao teste.
Não executar este teste em staging ou produção.

Os testes TypeScript ficam junto ao observer e ao classificador. Os testes
existentes de tipos de treino, deduplicação e calorias continuam gates vizinhos.
Nenhum resultado local substitui validação de integração, PostgREST ou release.
