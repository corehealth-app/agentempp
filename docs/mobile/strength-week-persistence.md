# Persistência semanal de treinos de força

## Estado

O conjunto local adiciona armazenamento, fontes e composição dormentes. A conclusão do cadastro pode abrir a geração comprovada; a confirmação de plano captura uma fonte apenas quando essa geração está legitimamente aberta. Essas integrações estão nas migrations de conclusão do cadastro, vínculo de lifecycle e confirmação de plano; não são uma adoção automática do histórico legado. Elas ainda dependem dos gates próprios de ativação no ambiente de destino.

A regra pura está em `packages/core/src/strength-training-week.ts`. O repositório de `apps/admin/src/lib/mobile-api/strength-training-week-service.ts` permanece desligado por padrão. Seu preparador puro reutiliza o resolver pelo subpath específico `@mpp/core/strength-training-week`, sem modificar a fórmula. `strength-training-week-composer.ts` compõe leitura, preparação e CAS; não há caller HTTP/Hoje/iOS instalado por essa composição.

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

O repositório continua desligado por padrão. A composição ainda não é chamada por HTTP, Hoje ou iOS. Os testes de contrato usam respostas de RPC controladas; os testes nativos de P5 foram executados separadamente. Isso não comprova a integração HTTP/autenticação/PostgreSQL completa nem a publicação de X/Y no app.

Também permanecem os gates integrados de durabilidade/concorrência/HTTP dos escritores reais, leitura dos consumidores, interface e ativação. Registros legados sem origem comprovada não podem virar histórico inventado nem um contador completo artificialmente zerado.
