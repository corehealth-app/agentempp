# Persistência semanal de treinos de força

## Estado

O conjunto local adiciona armazenamento, fontes, composição e apresentação iOS preparados. A conclusão do cadastro pode abrir a geração comprovada; a confirmação de plano captura uma fonte apenas quando essa geração está legitimamente aberta. Essas integrações estão nas migrations de conclusão do cadastro, vínculo de lifecycle e confirmação de plano; não são uma adoção automática do histórico legado. Elas ainda dependem dos gates próprios de ativação no ambiente de destino.

A regra pura está em `packages/core/src/strength-training-week.ts`. O repositório de `apps/admin/src/lib/mobile-api/strength-training-week-service.ts` permanece desligado por padrão. Seu preparador puro reutiliza o resolver pelo subpath específico `@mpp/core/strength-training-week`, sem modificar a fórmula. `strength-training-week-composer.ts` compõe leitura, preparação e CAS; o caller de `GET /today` tem um switch independente, também desligado por padrão. O iOS prepara o card condicional; não há ativação remota nesta fatia.

## Contrato

- `private.strength_week_scopes`: geração por usuário, apenas uma atual. Abrir/repetir/encerrar não usa timestamps de fotos como identidade.
- `private.strength_week_source_versions`: recibos append-only de plano aceito e frequência informada, com cobertura separada por fonte. Ausência explícita, frequência zero e histórico desconhecido são diferentes.
- `private.strength_week_targets`: um alvo por usuário/geração/segunda-feira. O fuso não cria uma segunda chave para a mesma semana. Alvo e prova de origem são imutáveis.
- Escritas usam READ COMMITTED, lock do usuário antes da geração e relógio depois do lock. O resultado retornado antes do COMMIT continua provisório.
- Recibos de mudança passam a valer na próxima segunda-feira local; desempate usa ordem bigint do banco, preservada como string, e instantes UTC com seis casas.
- Leitura e congelamento verificam dono, geração, fuso e semana. Um alvo já gravado prevalece sobre proposta/prova de origem antigas bem formadas; sem alvo, a prova completa deve corresponder ao snapshot atual.
- Leituras não criam geração nem inferem histórico a partir do perfil/plano atual. A última fonte elegível é selecionada antes de avaliar sua validade inclusiva na segunda-feira civil à meia-noite. Expirar durante a semana não troca o alvo; na segunda seguinte, uma fonte expirada permite somente o fallback comprovado, sem ressuscitar um plano substituído.
- O contexto `source_facts` fornece `week_start_at` UTC com seis casas. O adaptador mantém os instantes e ordens bigint como strings, sem `Date`/`Number` para decidir validade ou desempate. Um plano expirado é projetado como `plan:null` apenas para o core; seu recibo original permanece na prova enviada ao CAS.
- Mesmo diante de `existing_target`, o compositor revalida geração, semana e fuso pelo CAS. Somente seu resultado `frozen/reused` fornece um target ao consumidor. Conflitos, indisponibilidade e erros não viram uma proposta publicada, não usam o winner de uma leitura anterior e não iniciam retry automático.

As RPCs de contexto, CAS, vínculo de lifecycle e projeção são restritas ao backend confiável. Tabelas, sequências e helpers privados não têm acesso direto para anon, authenticated ou service_role. Os helpers privados de teste com relógio explícito não são endpoints públicos.

## Projeção atômica dormente

`get_mobile_strength_week_projection(uuid,uuid,uuid)` recebe dono, geração esperada e o identificador do target adquirido pelo CAS. A operação consulta a autoridade atual e o vínculo geração/lifecycle sem criá-los, revalida o target armazenado e usa um único instante após os locks para o calendário e a projeção dos treinos. O wrapper público não aceita relógio explícito. O preparador público de calendário mantém sua assinatura e delega ao mesmo corpo privado, usando o relógio real.

Somente `available` inclui target, vínculo, calendário, projeção e instante observado. Mudanças de geração, target ou semana retornam conflito; ausência de vínculo ou incompatibilidade de fuso permanece indisponível. Toda a história do dono continua sujeita às verificações de origem da projeção existente. Um histórico sem prova não vira uma lista vazia. Um resultado indisponível após criar calendário desfaz esse novo recibo; recibos anteriores permanecem e erros inesperados propagam.

Os testes locais de 20/10 usaram cadastro e plano de 42 dias reais, confirmaram um treino com seu timestamp atual e comprovaram o vínculo produzido. A projeção positiva foi observada pela função privada na próxima semana efetiva, com lista vazia esperada; isso não comprova contagem positiva futura nem relógio público futuro. Também passaram replay, preservação do calendário público anterior, conflitos, reset e falhas após INSERT. Um teste separado em REPEATABLE READ comprovou a recusa exata pelo wrapper público literal, sem produzir Y/L ou instalar a migration inteira nesse isolamento. Todas essas transações foram desfeitas.

### Durabilidade, reset concorrente e relógio após espera

Um teste local posterior, também em 20/10, confirmou o setup real em COMMIT, conferiu sua visibilidade por outra conexão e executou quatro cenários com conexões reais: relógio público após espera no usuário, reset desfeito permitindo a projeção, calendário confirmado e replay idêntico em novo backend, e reset confirmado recusando a geração antiga. Os bloqueios foram observados por PID, XID e chave advisory, com identidade e permissões do lock preservadas. A observação do relógio público foi feita somente na cópia local instrumentada, sem alterar o instante usado pelo produto.

A projeção positiva continua sendo a observação privada na semana futura efetiva, com lista vazia esperada. O wrapper público usou o relógio real e recusou esse target futuro. O teste não comprova contagem positiva futura, isolamento entre dois donos, crash, perda de ACK, autenticação HTTP ou interface iOS.

O teste aprovado executou 41 comandos com saída zero e 32 fingerprints dos quatro bancos. Após os quatro atores e seus leitores serem encerrados, o teardown restrito removeu o grafo sintético e restaurou as definições, OIDs e ACLs anteriores. O único delta foi a alocação natural de duas fontes, 141→143; nenhuma sequência foi reiniciada. PostgreSQL ficou parado, com configurações intactas e arquivos de credenciais vazios removidos. Duas tentativas anteriores do harness foram preservadas como falhas, com regressões exatas e limpeza verificada; elas não contam como aprovação dos quatro cenários.

## Regressão SQL sequencial

Use um banco **local exclusivo e sintético** que já tenha o schema necessário e esta migration. O bootstrap mínimo usado na evidência não comprova compatibilidade com todo o schema remoto nem autenticação criptográfica de JWT. Não executar estes testes em staging ou produção: as inserções com identidade avançam a sequência mesmo quando a transação faz ROLLBACK. Os valores acima de 2^53 são fixtures inseridas com `OVERRIDING SYSTEM VALUE`, não uma alegação de identidades naturais nessa faixa.

Com socket local, porta, dono e banco previamente conferidos, executar por `psql -w -X -v ON_ERROR_STOP=1` nesta ordem:

1. `supabase/tests/fixtures/strength_week_fixture_support.sql` — helpers somente do dono do teste, instalados nesse banco exclusivo.
2. `supabase/tests/strength_week_persistence.sql` — prioridade/ausência/zero, prova completa, imutabilidade, calendário/DST, gerações, replay, precisão, RLS/ACL e exclusão da conta; termina em ROLLBACK.
3. `supabase/tests/strength_week_replay_supplement.sql` — replay de recibo original após o plano atual ser substituído; termina em ROLLBACK.

A execução local de 14/10/2026 em PostgreSQL 17.11 passou 212 verificações sequenciais e 6 complementares. Contagens das tabelas voltaram ao baseline zero e o guard de backend existente permaneceu byte-equivalente pelo fingerprint. O cluster foi encerrado e os dados sintéticos retidos sem autostart.

Além da execução sequencial, passaram quatro cenários locais com duas conexões reais: A confirma primeiro, B confirma primeiro, A faz ROLLBACK e B grava o único vencedor, e captura do relógio após espera real pelo lock do usuário. Os testes observaram ambas as chegadas antes do lock, bloqueio real, COMMIT/ROLLBACK externos, um único alvo durável, releituras/replay idênticos e preservação do usuário de controle. O teste do relógio comparou o instante gravado com um limite coletado antes do COMMIT que liberou a espera; não mede o instante exato de liberação nem desempenho.

A instrumentação de observação pertenceu somente à cópia local instalada; não faz parte desta migration. O hook no wrapper ocorreu antes do guard READ COMMITTED interno; os dois atores iniciaram suas transações nesse isolamento. Após os testes, a definição original, ACLs, metadados e funções vizinhas foram comparados ao snapshot anterior e restaurados; processos dos atores/driver foram encerrados e o cluster novamente parado. Advertências de limpeza do harness (ROLLBACK sem transação e unlock já liberado) foram preservadas nos logs, sem ERROR/FATAL/PANIC.

## Próximas integrações

Em 20/10, o teste nativo local do produtor real de plano de 42 dias passou na leitura, freeze e winner após o RED correspondente. Também passaram as fronteiras inclusivas de um microssegundo, leitura tardia, plano B expirado, zero/ausência/desconhecido e regressão RC/RR. As quatro transações foram desfeitas; isso não comprova instalação durável, HTTP, concorrência ou ativação do candidato. As evidências e limites atuais ficam no checkpoint operacional de M3A e no diário local.

A publicação de X/Y exige target, binding e calendário coerentes e somente os treinos confirmados oficiais. Geração e lifecycle são identidades distintas. A aquisição do target isoladamente não é um contador completo.

Essa composição interna está preparada em `readStrengthTrainingWeek`: aquisição oficial, uma RPC de projeção atômica e o resumo puro do core. O parser compara o target completo com o winner do CAS, mantém as nove provas do binding e reutiliza os parsers de calendário/treinos pelo subpath explícito `@mpp/agent/workout-strength-projection`. A frequência original do cadastro no binding pode diferir da fonte semanal selecionada. Indisponibilidade e conflito não produzem resumo parcial nem lista vazia; somente uma projeção disponível chega ao core. Não há retry implícito, mudança de fórmula ou acesso separado a calendário/vínculo durante essa composição.

O repositório continua desligado por padrão. `GET /today` tem um caller preparado, descrito abaixo; o iOS decodifica e preserva a seção opcional e prepara sua apresentação em Hoje. Os testes HTTP usam wrapper real, autenticação controlada e respostas de RPC controladas; os testes nativos de P5/P7 foram executados separadamente. Isso não comprova a integração HTTP/autenticação/PostgreSQL completa nem a publicação de X/Y no app distribuído.

Também permanecem os gates integrados de durabilidade/concorrência/HTTP dos escritores reais, leitura dos consumidores, interface e ativação. Registros legados sem origem comprovada não podem virar histórico inventado nem um contador completo artificialmente zerado.

## Seção semanal opcional em Hoje

Somente `GET /today`, após autenticação, autorização de acesso, fechamento sob demanda e leitura diária bem-sucedida, chama o compositor semanal. `loadToday` compartilhado com `/protocol` e Flow permanece inalterado. O caller usa o mesmo cliente de serviço e o identificador interno do paciente autenticado, nunca parâmetros de query ou o UUID do Auth.

`MOBILE_STRENGTH_WEEK_PROJECT_REF` precisa listar explicitamente o projeto da URL Supabase configurada. Ausência, alvo não comprovado ou produção antiga, inclusive em lista mista, mantém OFF. O switch de treino versionado não o habilita. OFF ou objetivo atual fora de recomposição, ganho e manutenção omite `strength_training_week` sem acessar RPC semanal e preserva a resposta diária anterior.

A seção disponível contém somente calendário semanal, instante observado literal, X, Y, origem, disponibilidade e percentual do core. Zero e ausência de Y preservam X e percentual nulo. Conflito e indisponibilidade contêm somente status e motivo; falhas operacionais ou de contrato continuam sendo erros HTTP, sem retry ou contador artificial. IDs, geração, binding, recibos e identidades de treinos não são publicados.

As leituras diária e semanal são independentes: não há alegação de transação ou relógio único entre elas. A seção semanal conserva `week_start`, `as_of_local_date`, `time_zone` e `observed_at` oficiais próprios, mesmo se a data diária ou o fuso lido anteriormente diferir. A interface deve rotular esse escopo explicitamente e não reinterpretá-lo pelo relógio do aparelho. A pergunta persistida para treino desconhecido tem um contrato HTTP preparado e desligado, descrito abaixo; seu fluxo iOS ainda está pendente. Somente este card não encerra M3A.

### Contrato iOS e dia sem registros

`TodaySnapshot.strengthTrainingWeek` é opcional: servidor antigo ou campo nulo conserva o contrato anterior. O decoder valida o calendário civil fornecido em Gregorian/UTC, a segunda-feira e o intervalo de sete dias, o identificador de fuso e a forma UTC com seis casas. `observedAt` permanece String literal inclusive ao codificar; não passa pelo `APITimestamp`, que converte para `Date`. Isso não é uma nova decisão de semana nem valida a correspondência entre a observação e a data/fuso informados pelo servidor.

Valores disponíveis malformados são erros de contrato. `planned_days` e `percentage` são chaves obrigatórias: zero conserva Y=0 e percentual nulo; ausência conserva ambos nulos. O cliente não recalcula o percentual. Negativos ou status futuros não adquirem métricas parciais. Um dia com `no_records` conserva o snapshot quando há seção semanal; sem essa seção, o estado vazio anterior permanece. A pergunta de classificação e a ativação continuam pendentes.

### Apresentação semanal preparada no iOS

`TodayStrengthTrainingWeekDescriptor` formata somente os campos oficiais, em português ou inglês. O card opaco aparece antes dos treinos diários, dentro do mesmo grupo, quando a seção está presente. Semana, data de apuração e fuso são explícitos e independentes do cabeçalho diário. Gregorian/UTC serve apenas para formatar a data civil; o instante observado e o relógio do aparelho não escolhem a data apresentada.

X representa dias com treino de força, não quantidade de sessões. Para Y positivo, X/Y e percentual permanecem literais, inclusive X maior que Y. Zero e ausência mostram X isolado e sua condição explícita, sem percentual ou divisão inventados. Negativos e status futuros mostram mensagem sem métricas parciais ou códigos internos.

O componente não tem tarefa nem provider. Atualizar reutiliza o coordenador de Hoje, preservando os dados durante a leitura e desabilitando a ação enquanto há atualização. O título é um cabeçalho acessível; as informações são agrupadas separadamente do botão com o estilo compartilhado de 44 pontos mínimos. Essas propriedades de fonte não comprovam acionamento ou leitura física por VoiceOver.

### Identidade do treino após a confirmação

A confirmação versionada pode acrescentar `confirmed_workout_id`, o UUID real de `workout_logs`, quando o capture positivo inteiro passa pelo parser de binding/fact e corresponde ao paciente autenticado e ao tipo original da proposta. Esse ID não substitui o `id` da proposta pendente nem sua `content_revision`. A classificação, o calendário e a resposta persistida são validados sem nova leitura de catálogo, escolha de captura ou RPC adicional. A prova de origem continua pertencendo ao produtor SQL confiável.

O campo é opcional. Captures antigos opacos, indisponíveis ou incoerentes conservam a confirmação anterior sem publicar identidade parcial. Um UUID isolado de legado não é promovido. Erros de RPC, preparação e autoridade continuam propagando como antes; somente o decoder puro dessa identidade opcional tolera wire incompatível. Calorias, dedup e replay permanecem inalterados. A leitura/resposta HTTP da pergunta está preparada e desligada; sua interface ainda é uma integração posterior. Esse campo sozinho não ativa o fluxo.

### Leitura e resposta da pergunta no backend

As RPCs dormentes `get_mobile_workout_strength_clarification` e `answer_mobile_workout_strength_clarification` recebem o UUID real do treino e exigem authority atual e lifecycle pertencente ao paciente e aberto. A leitura não abre autoridade, escolhe captura, exige uma nova admission nem consulta o catálogo atual. O fact e a âncora armazenada são comprovados no mesmo SELECT após os locks; fact de lifecycle antigo é stale, distinto de legado sem fact. Known ou classificação indisponível conservam `not_applicable`.

O wrapper verifica a autoridade atual antes de delegar ao writer de resposta existente. Ele mantém a revisão, pergunta, valor e chave da tentativa original: o replay de revisão0 continua válido após revisão1 enquanto o contexto permanece atual. Após reset, inclusive esse replay é recusado. A resposta persistida pode indicar a operação vencedora anterior, diferente da segunda tentativa. Não há confirmação adicional do treino nem alteração de calorias.

Os testes nativos locais de 21/10 usaram confirmação S17D real para dois pacientes sintéticos, respostas sim/não e estados known/indisponível produzidos pelo catálogo real. Passaram 58 verificações em READ COMMITTED e seis em REPEATABLE READ real; 16 fingerprints dos quatro bancos permaneceram iguais ao baseline143. As duas transações foram desfeitas e o cluster encerrado. Uma tentativa anterior falhou pelo oráculo QA incorreto de um retorno legado; a correção seguiu o contrato `inserted/workout_log_id/snapshot_id` e preservou essa evidência.

Essas evidências cobrem SQL local, sem instalação persistente. O produtor da fixture pertence ao substrato S17D retido; a pilha completa futura, HTTP/autenticação real, durabilidade, reset COMMIT, concorrência, interface e ativação exigem seus próprios gates. As verificações de claims usam o shim local e não comprovam JWT/PostgREST. Nenhuma função compartilhada anterior, caller WhatsApp ou fórmula foi alterado.

### Contrato HTTP preparado para a pergunta

`GET` e `POST /api/mobile/v1/workouts/{id}/strength-clarification` usam autenticação e entitlement existentes, antes do handler. O dono vem somente do paciente autenticado. A flag existente de treino versionado permanece OFF por padrão, inclusive para produção antiga; não houve ativação. OFF impede acesso ao port da pergunta, mas o cliente usado pela autenticação já foi criado pelo wrapper comum.

A leitura disponível publica `status`, `workout_id`, `lifecycle_key` e `fact_revision`. `unanswered` acrescenta `question_key`, com revisão0; `answered` usa revisão1 e acrescenta a pergunta e `receipt: {answer, accepted_at}`. `not_applicable` conserva revisão0 sem pergunta. Legado sem prova retorna somente `unavailable/provenance_gap`. Recibos internos precisam corresponder ao dono e treino antes da projeção. Owner, capture, classificação, catálogo e chave de operação não são publicados. O instante UTC com seis casas é preservado literalmente.

O POST exige JSON estrito de até2048 bytes, sem chaves duplicadas, com somente `expected_lifecycle_key`, `expected_fact_revision` (inteiro0…2147483647), `question_key` e `answer` (`yes` ou `no`). O header `Idempotency-Key` precisa ser UUID. UUIDs são canonicalizados em lowercase; o namespace de operação é `wsa1:<uuid>`. Não se usa o cache HTTP de sucesso: cada chamada delega ao wrapper SQL que confere a autoridade atual. Não há retry automático, preparação de outra tuple ou GET após a escrita. O cliente deve conservar o corpo e a chave originais, inclusive revisão0 após revisão1.

`accepted/reuse_existing` publica o mesmo DTO `answered`, com revisão1 comprovada pelo writer. O recibo vencedor pode pertencer à tentativa anterior A quando B envia a mesma resposta; isso não é erro. Resposta divergente não substitui a anterior. Contexto stale/foreign resulta em409 neutro `workout_strength_unavailable`; conflitos de resposta ou revisão usam409 `workout_strength_answer_conflict`, sem detalhes internos. Erros operacionais e wire inválido continuam erros500 pela fronteira sanitizada, sem se tornarem sucesso, vazio ou indisponibilidade artificial.

Os testes de handler usam o wrapper HTTP real e respostas controladas de autenticação/RPC. O build local comprova que as duas RPCs chegam somente à nova rota, os quatro métodos do factory anterior não chegam às rotas e as RPCs semanais continuam exclusivas de Hoje. Isso é evidência separada dos testes SQL locais: não comprova HTTP+JWT+PostgREST integrados, iOS, instalação persistente ou ativação. A nova rota adiciona exatamente um item ao inventário anterior de55; os verificadores globais com contagem/hash congelados permanecem um gate de candidato até sua reconciliação controlada. Nenhum fixture antigo ou WIP foi enfraquecido.

Os probes locais de acessibilidade usados no desenvolvimento retornaram árvores vazias tanto no Root quanto no controle diário isolado. As tentativas e fontes foram preservadas como falhas de harness; não contam como RED do produto ou aprovação de acessibilidade. Testes de apresentação, layout e imagens nativas cobrem camadas próprias. AX do Root, acionamento acessível, VoiceOver físico, integração completa e distribuição permanecem gates separados.
