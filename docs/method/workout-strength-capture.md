# Captura atômica da proveniência do treino — S8

## Escopo

A nova fronteira de backend é public.register_workout_strength_atomic(uuid,uuid,text,text,jsonb,jsonb). Ela permanece dormente: nenhum consumidor, flag, reset, rotina, cálculo nutricional ou WhatsApp é alterado. São seis entradas: owner, lifecycle esperado, chave de operação, tipo original literal, observação completa do catálogo e decisão trusted TS. Os 13 argumentos da API antiga e o corte recente são lidos diretamente do journal owned S7; nenhum novo preparo é feito em JavaScript.

O resultado externo contém somente legacy_result e strength. O primeiro conserva o JSON real retornado por register_workout_atomic, inclusive a diferença X26 entre snapshot da tentativa e snapshot original do UUID. O segundo usa os resultados R2 e o fact histórico da row real owned. A API antiga, seus defaults, normalização e calorias permanecem byte exatos.

## Autoridade e atomicidade

Guard trusted, sintaxe e READ COMMITTED precedem a aquisição catálogo SHARE → advisory legado de treino → owner ativo NO KEY UPDATE → lifecycle aberto. Binding válido é retomado antes de exigir journal ou novo envelope. Tombstone, fact de outro lifecycle ou anchor inválido não viram gap novo. Sem binding e sem journal não há admissão implícita.

Dedup provider/tipo literal e recente usa somente o journal e rows reais. Sem dedup, a observação completa disponível deve ter forma estrita e CAS de todo conjunto ativo, incluindo competidores. A decisão trusted não recebe categoria; a cópia vem da row real selecionada. Uma forma JSON válida não autentica a origem: o produtor SQL e o matcher TS literal são gates separados de integração.

Inserção nova da API antiga, fact e binding pertencem à mesma transação. Falhas obrigatórias do writer ou metadata propagam, revertendo inclusive correção real. Não há catch geral que converta erro operacional em indisponibilidade. Fact legado ausente não é preenchido retroativamente.

Classificação, pergunta UUID, calendário e revisão inicial são snapshots persistidos. Calendário provado exige timezone oficial válido exato e data local do performed_at real igual à data do snapshot; caso contrário conserva zone_unproved/calendar_conflict sem alterar calorias ou data legadas. Âncora infinita ou fora do formato persistido permitido aborta pela constraint de metadata.

## Verificação

**Verificado localmente no PostgreSQL 17.11:** 76 verificações SQL únicas e cinco casos A/B reais passaram em uma execução. Os 12 comandos do controlador terminaram com código zero. Isso não comprova staging, interface, ativação ou entrega integral do beta.

O teste sequencial usa as APIs SQL reais, BEGIN/ROLLBACK, perda intencional apenas do resultado da função, precisão numeric SQL, oito NULLs legados, X26, todas quatro resoluções, CAS completo, correção e tombstone, owner/lifecycle/ACL/guard/isolation. Uma CHECK temporária na fixture testa rollback obrigatório; não é hook de produto.

O driver usa duas sessões persistentes e módulos Actor S7 pinados, sem chamar S7.run. Observa pg_blocking_pids para commit/replay, rollback/new, mutação do catálogo/SHARE e histórico. O limite de relógio é obtido depois do bloqueio observado e antes da liberação; não representa o instante exato da liberação nem benchmark.

Antes da execução, uma revisão encontrou leituras STABLE na mesma expressão que chamava a RPC VOLATILE. Os testes foram fortalecidos para concluir a chamada em uma instrução separada antes de comparar o estado completo, preservando os 76 oráculos. Isso segue a [regra de snapshots do PostgreSQL](https://www.postgresql.org/docs/17/xfunc-volatility.html); não foi alegado RED de produto.

Root conferiu os 29 logs, os recibos dos atores e a restauração do snapshot completo antes/depois, ambos com SHA256 8de248c473811ced70a4f6140e93579551a0bd30221464ea244bdfb3da3ada53. O teardown comprovou propriedade/OID/definição/ACL/owner; o banco retido ficou parado, sem PID25564, pidfile, socket ou lock. Evidência local: codex-u2-c59a3a-s8-evidence-20261014/run-r1/REGISTRY.json, SHA256 c0f362874201ad93e349bb5f630b50ec61244e050072a85037a94a352074d102.

Não houve clone, DROP DATABASE, staging, deploy ou recurso pago. Revisão final e commit são registrados separadamente do resultado destes testes. F3, reset, integração e ativação continuam fora deste grupo.
