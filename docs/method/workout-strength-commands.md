# Comando de treino durável — etapa dormente

A admissão registra uma preparação original antes da futura captura, preservando
a identidade (owner, lifecycle, chave e tipo original exato). Não ativa captura,
resposta, reset, consumidor, WhatsApp ou projeção semanal, nem modifica a API legada.

A tabela privada workout_strength_commands possui sete colunas NOT NULL:
user_id, lifecycle_key, operation_key, original_operation_type, legacy_arguments,
admitted_at e recent_cutoff. A PK contém as quatro primeiras; a FK owned do ciclo
cascata a exclusão. RLS sem policies e grants externos revogados. Essas permissões
não impedem owner-DML e não provam sozinhas imutabilidade ou proveniência.

read_or_admit_workout_strength_command(uuid,uuid,text,text,jsonb) é backend-only:
trusted guard, sintaxe F1, READ COMMITTED, advisory legado, owner ativo NO KEY UPDATE
e ciclo owned aberto precedem lookup. Owner ausente/inativo gera P0002; sintaxe ou
candidato inválido gera 22023; guard/ACL, 42501. Ciclo stale devolve forbidden/stale_lifecycle.
SQL NULL faz lookup-only. Sem comando, JSON null/forma inválida não é lookup-only.

Existindo a PK, os sete campos originais vencem, mesmo se os argumentos preparados
da tentativa seguinte divergem ou são inválidos. Isso é F1; o conflito de conteúdo
canônico de respostas F2 continua separado. Nenhuma atualização ou recálculo no retry.
Nova admissão valida todas as 13 chaves e tipos SQL legados, sem defaults ou limites
clínicos novos. Os oito nullable permanecem explícitos. Números inteiros devem ser
integrais e representáveis; JSONB mantém numeric/literais exatos sem arredondar por JS.
Datas/timestamps legados aceitam casts SQL compatíveis, preservando os textos, sem
exigir ISO novo. Proveniência e datas absolutas do produtor são gates de integração.

Uma clock DB após locks/validação fixa admittedAt e cutoff exato de seis horas. O
wire novo usa UTC com seis casas; resultado é provisório até COMMIT. A primeira
transação que confirma vence; rollback deixa a seguinte admitir seu próprio comando.

## Verificação

Verificado localmente em 14/10/2026: 88 assertions SQL sequenciais PASS e dois
casos A/B reais PASS. A primeira execução parou por uma premissa errada do teste
(raw já maiúsculo comparado a upper(raw)); a segunda usou lower(raw) e exigiu
explicitamente textos distintos. O runtime permaneceu intacto entre as execuções.
As nove assertions repetidas da primeira execução não são somadas às 88.
O caso A commit/B recebe A apesar de onze argumentos preparados divergentes;
A rollback/B cria B. A observa pg_blocking_pids(B), sem hook ou terceira sessão.
O relógio antes da liberação é limite inferior, não instante exato do unlock nem
benchmark. Setup concorrente confirma somente dados sintéticos/objetos novos; um
manifesto durável de OIDs, owners, definições/ACLs/schema permite teardown explícito
sem CASCADE, inclusive após perder a resposta do setup COMMIT. Controller verifica
baseline completo e para o PG; driver apenas fecha suas duas sessões.

O encerramento do driver também cobre uma interrupção depois de criar Actor e
antes de registrá-lo: quatro casos A/B × SIGINT/TERM falharam causalmente no
driver anterior e passaram no corrigido. Esse teste isolado usa FakeActor e
sinais no opcode do caller, sem processo psql ou banco. Está preservado em
`supabase/tests/fixtures/workout_strength_commands_actor_registration_test.py`;
execute com `--driver-path` apontando o driver e `--output-dir` em pasta nova.
A proteção adia os sinais só durante criação/registro, sem bloquear a máscara
herdada pelo filho, e restaura os handlers antes de propagar a interrupção.

O before/after completo (linhas, esquema, funções, ACLs e sequência) ficou
byte a byte idêntico. Os atores, leitores e PostgreSQL local foram encerrados.
Essas provas locais não estabelecem ativação, staging/produção, performance do
app, nova infraestrutura ou aceite de beta. Integração e distribuição continuam
etapas próprias.
