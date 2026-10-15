# Resposta à pergunta de musculação — S9

## Fronteira dormente

Uma RPC de backend implementada no checkout local: public.answer_confirmed_workout_strength(uuid,uuid,uuid,integer,uuid,text,text). Não há consumidor, flag, reset, F3, UI, mensagem ou ativação neste grupo. Os facts e perguntas vêm da captura S8 real; a resposta não registra treino nem consulta catálogo/fuso atual.

## Autoridade e replay

Guard trusted, sintaxe, READ COMMITTED, advisory legado de treino, owner ativo NO KEY UPDATE e lifecycle aberto precedem o workout/fact/question real owned. Fact matched ou unavailable não aceita resposta. UUID removido, antigo ou incoerente permanece stale; uma pergunta diferente não ganha autoridade por conhecer a chave de operação.

Operação existente valida primeiro a própria autoridade ORIGINAL e o recibo vencedor exato do fact original. Depois compara o conteúdo canônico ORIGINAL, inclusive a revisão enviada na primeira tentativa. A/revisão0 pode ser retomada após o fact chegar à revisão1; alterar somente a revisão sob a mesma chave conflita. Uma operação B nova com revisão1 e resposta igual conserva seu canônico B, mas recebe e persiste o recibo vencedor A. Chave B não precisa ser igual à chave do recibo A.

Só operação nova aplica CAS atual. A primeira resposta atualiza answer, answer_operation_key, answer_accepted_at e revisão0→1, junto da binding, na mesma transação. Resposta divergente após CAS válido conflita, sem sobrescrever o vencedor. Âncora, classificação, calendário, pergunta, captura, treino, snapshots e calorias ficam preservados.

Correção real remove a autoridade do UUID antigo e tombstona as operações por FK; não carrega resposta para a pergunta nova. Lifecycle fechado nega antes do replay. O teste de fechamento do lifecycle é de fixture e não substitui a futura integração do reset.

## Verificação

**Verificado localmente:** a segunda execução Root passou as 72 assertions SQL únicas e os quatro casos A/B reais. São os 70 oráculos originais e duas regressões do fingerprint. Doze comandos terminaram com exit0. A revisão independente final precede o commit local; não houve implantação ou ativação.

As quatro disputas cobrem yes/no nas duas ordens, A COMMIT e A ROLLBACK, bloqueio real observado por pg_blocking_pids, recibo original e exatamente uma resposta durável. Em rollback, o clock do vencedor é comparado ao limite DB observado depois do bloqueio e antes de liberar A; não é instante exato da liberação ou benchmark.

Os testes usam o writer e a captura reais, resultado da função descartado (sem alegar perda HTTP), recibo contraditório com CHECK ainda válido, correção/tombstone, CHECK temporária da fixture para falha obrigatória de inserção, ACL/guard/isolamento e cópias imutáveis. Chamada VOLATILE e leitura STABLE de estado pertencem a statements separados.

Execução limitada ao banco sintético retido, com propriedade/OID/definição/ACL/owners e quatro owners sintéticos. Root conferiu teardown explícito sem CASCADE e baseline antes/depois byte idêntico (SHA 8de248c473811ced70a4f6140e93579551a0bd30221464ea244bdfb3da3ada53). Os atores terminaram com exit0, foram recolhidos e seus leitores encerrados. O servidor ficou STOPPED_RETAINED; PID29418 e backends29494/29493, pidfile/socket/lock ausentes após encerramento. Nenhum clone, DROP DATABASE, staging, push, recurso pago ou WhatsApp é ativado. Este grupo não conclui o beta nem o fluxo de cliente.

### Reparação do oráculo de fingerprint

A primeira execução Root passou 69 dos 70 labels originais e falhou na comparação final de metadata. O diagnóstico separado preservado em codex-u2-c59a3a-s9-fingerprint-diagnostic-evidence-20261014/run-r1 (registry c0d8f630) comprovou catálogo bruto igual em oito fases. Somente DateStyle alterou uma leaf renderizada do CHECK de representação: limites de data ISO passaram a SQL/DMY; TimeZone isolado não mudou o payload. Restauro de settings, CHECK add/drop com rollback e rename com rollback recuperaram o payload inteiro. BEFORE/AFTER permaneceram 8de248c4 e o banco foi parado pelo Root. Isso é falha de contexto do oráculo, sem alteração do runtime.

R2 canoniza DateStyle=ISO,YMD e TimeZone=UTC somente na configuração da função test-only object_fingerprint, mantendo search_path=pg_catalog e todos os campos comparados. O retorno da função deve restaurar SQL,DMY/Auckland antes do statement seguinte; os RPCs permanecem no contexto adversarial. Duas regressões exigem payload completo invariante com settings externos restaurados e detecção da CHECK física temporária de atomicidade. As duas regressões passaram na segunda execução. As 69 verificações anteriores se sobrepõem aos oráculos repetidos e não foram somadas às 72 finais.


Evidência local: codex-u2-c59a3a-s9-evidence-20261014/run-r2, REGISTRY b28941bc e ROOT-VERIFICATION 7208cc22; 29 logs e 94 pacotes JSON do driver conferidos. A sonda de causa usa pasta própria e não integra a contagem funcional. Não houve build iOS ou novo gate TypeScript neste grupo SQL/Python; integração com consumidores e beta integral permanecem abertos.
