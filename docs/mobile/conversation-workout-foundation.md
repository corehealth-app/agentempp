# Atividade no Flow: fundação dormente

Incremento da especificação aprovada em `docs/superpowers/plans/2026-11-03-performe-conversational-app.md`. Esta fundação não registra uma atividade no app atual. Registro SQL real, feedback/histórico públicos, correção/Undo e integração nativa continuam em andamento. Nenhuma migration/capability/rota/default factory foi ativada; o protótipo SQL não foi executado.

## Interfaces e decisões deste incremento

- `bindConversationWorkoutCommand(owner, cmsg1:UUID, raw)`: `conversation.command.v1` + `workout.report`, origem textual ou mídia com `register_performed_workout`, corpo fechado/imutável e SHA-256 canônico. O tipo é interno. O usuário deverá enviar texto livre ao mesmo Flow; intake/classificador compartilhado fará o dispatch. Nunca reinterpretar bytes/hash de `meal.report` antigo. O protótipo inclui fence bidirecional de colisão do mesmo UUID entre os dois tipos.
- `parseConversationWorkoutSource(command, raw)`: transporte privado de fonte selada, owner/epoch/corpo/hash, admissão/observação do servidor, data civil aberta e estado clínico atual capturado. Áudio requer transcript processado owned; `gym_photo` atual descreve equipamento. Imagem ou intenção explícita do cliente, sozinhas, não provam realização. Texto original, caption e transcript são preservados. Metadados privados não são DTO público.
- `resolveConversationWorkoutReport(source)`: primeiro guard executável para uma cláusula integral literal, como `Fiz 30 minutos de caminhada leve`, em catálogo capturado. Pergunta/futuro/hábito/negação/terceiro/mistura não autorizam registro; duração ausente produz uma pergunta estável ligada ao source hash. Gramática limitada é uma fundação conservadora, não o interpretador multimodal final. Variantes ainda não cobertas retornam pergunta. Tipo com palavra de intensidade ambígua entre slugs também pede esclarecimento.
- `prepareConversationWorkout(source, ports)`: conserva fonte/data/atividade; intensidade ausente e kcal desconhecida ficam `null`. Não há fórmula nova, peso padrão, calorias de Vision, consulta de histórico ou substituição recente. Uma porta opcional pode fornecer resultado do `calc_workout_kcal` existente depois de provar peso atual, catálogo exato e escopo. Não existe implementação default dessa porta. Ausência/erro/resultado inválido preserva energia indisponível. Não emite crédito alimentar, bloco, XP ou evento de recompensa.
- `parseConversationWorkoutEffect(source, prepared, raw)`: recibo próprio `conversation.workout-effect.v1`, proveniência `conversation.workout.v1`, operação/provider key `cwork1:UUID`, IDs reais de workout/snapshot/lifecycle, preparação e origem vinculadas. Reusa o decoder protegido completo de strength e exige `sql_insert/sql_replay`, calendário provado e anchors coincidentes; rejeita dedupe por janela e prova `ui-v1`.
- `createConversationWorkoutWriter(rpcPort, scopePort)`: bridge inerte sem cliente default. Lê antes; se ausente, tenta um commit e faz uma leitura independente com a mesma identidade. Resultado rico de mutation não é ACK. Falha/revogação não reenvia o writer e não aceita receipt inventado. A leitura não admite, captura, prepara, calcula nem escreve. `projectConversationWorkoutFacts` projeta somente fatos históricos para futura integração v2; não publica dia/bloco/política/recompensa.

Objetos JS, booleans/model output e codecs não autenticam o produtor SQL. A fonte real precisa vir do backend autorizado; o futuro core transacional terá de refazer suas precondições contra a origem selada. Não é permitido compor esses ports com uma rota real antes dos gates abaixo.

## Reaproveitamento e bloqueios observados

A tabela `workout_logs` já permite duração/kcal nulas (`20260501120200_operational.sql`, schema gerado). Não foi proposta alteração de nullability. O core protegido `private.register_workout_atomic_core` rejeita kcal `NULL`; o core strength usa dedupe recente de seis horas. A preparação legada usa peso padrão 70 kg e `null -> 0`; a captura de feedback existente parte de confirmação `ui-v1` ou chave direta legada. Nenhuma dessas políticas foi alterada ou usada como se comprovasse atividade conversacional.

Os helpers protegidos de snapshot/resolver de strength e o contrato de fatos/renderer v2 são reutilizáveis. O registro conversacional precisará de um core aditivo com a mesma ordem de locks/captura, proveniência própria e compensação futura. SQL dump/inventário/teste de port não prova que esse core existe ou funciona.

O agregado legado soma `estimated_kcal` com `COALESCE(sum(...),0)`. Antes de registrar energia desconhecida é obrigatório qualificar cobertura nos leitores oficiais/closer: número/credit derivado não comprovado fica indisponível. Preservar o ledger/política existentes; não criar crédito imediato, aumentar saldo alimentar ou alterar fórmula/XP para acomodar o novo tipo. Não foi executada auditoria do runtime, triggers ou rollups nesta fatia.

## Protótipo SQL e gates restantes

`prototypes/conversation-workout-foundation.sql` é desenho inerte de tombstone permanente, corpo/fonte imutáveis, slots de preparação/receipt, fences de owner/epoch/kind, capture owned e leitura de efeito. Não está em `supabase/migrations`, não concede EXECUTE e não define `commit_conversation_workout`. As tabelas de slots não produzem prova de realização por si. Não cria epoch silenciosamente. Reset torna epoch antigo ilegível; retenção/limpeza física desses novos conteúdos ainda precisa ser integrada ao reset existente.

Antes de runtime/publicação:

1. Qualificar admission quotas/backpressure compartilhados e captura clínica/catálogo/mídia com row waits, dois donos, meia-noite, dia fechado e reset/retention. O novo tipo deve consumir o mesmo limite protegido combinado da fila, sem terceiro transporte.
2. Implementar e testar no PG explicitamente autorizado o core atômico próprio: fonte e semântica integral verificadas no servidor, energia atual conhecida/indisponível, workout+snapshot+strength operation/fact+receipt/evento juntos. Duas atividades idênticas com UUIDs distintos produzem dois efeitos; retry conserva identidade. Nada de pending/ui-v1 fabricados ou chamada que herde dedupe6h.
3. Provar ausência de novos créditos/XP e cobertura desconhecida em Today/Histórico/closer/bloco. Preservar as fórmulas e a autoridade oficial atual.
4. Selar feedback v2 próprio, aplicar política clínica atual antes/depois da apresentação, integrar timeline paginada e reconciliação read-only. Original factual continua histórico após correção.
5. Completar grupo atual/CAS, edição/Undo de cinco minutos com recibo compensatório, snapshot/strength coerentes e original preservado.
6. Integrar intake/classificador do texto livre, mesma fila/outbox protegida combinada, mídia/câmera/galeria/áudio, cards/seis blocos e abas oficiais; qualificar envio→feedback→edição→reabrir→Undo no mesmo Flow.

**Decisão de integração ainda aberta:** mensagens com refeição e atividade realizadas, ou múltiplas atividades, preservam a entrada completa e não-ready nesta fundação. Não foi inventada política de múltiplos efeitos/atomicidade/clarificação. Essa composição precisa ser definida antes da ativação; uma refeição ou atividade não pode ser silenciosamente ignorada.

Verificação desta fatia: testes Node com ports controlados, typecheck e lint locais; SQL/PG, HTTP real, UI/nativo e publicação permanecem NOT VERIFIED. A próxima qualificação não pode declarar o primeiro candidato completo por API isolada ou fluxo manual da aba Treino.
