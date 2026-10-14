# Persistência semanal de treinos de força

## Estado

Esta migration adiciona armazenamento e primitivas dormentes. Não conecta os escritores de plano/perfil/reset, não abre gerações automaticamente e não publica um contador no app. A regra pura está em `packages/core/src/strength-training-week.ts`; o adaptador desligado está em `apps/admin/src/lib/mobile-api/strength-training-week-service.ts`.

## Contrato

- `private.strength_week_scopes`: geração por usuário, apenas uma atual. Abrir/repetir/encerrar não usa timestamps de fotos como identidade.
- `private.strength_week_source_versions`: recibos append-only de plano aceito e frequência informada, com cobertura separada por fonte. Ausência explícita, frequência zero e histórico desconhecido são diferentes.
- `private.strength_week_targets`: um alvo por usuário/geração/segunda-feira. O fuso não cria uma segunda chave para a mesma semana. Alvo e prova de origem são imutáveis.
- Escritas usam READ COMMITTED, lock do usuário antes da geração e relógio depois do lock. O resultado retornado antes do COMMIT continua provisório.
- Recibos de mudança passam a valer na próxima segunda-feira local; desempate usa ordem bigint do banco, preservada como string, e instantes UTC com seis casas.
- Leitura e congelamento verificam dono, geração, fuso e semana. Um alvo já gravado prevalece sobre proposta/prova de origem antigas bem formadas; sem alvo, a prova completa deve corresponder ao snapshot atual.
- Leituras não criam geração nem inferem histórico a partir do perfil/plano atual. Guardas conservadoras de calendário/validade sinalizam indisponibilidade; a integração completa de validade e mudança de fuso é trabalho seguinte, antes de ativar consumidores.

Somente `get_mobile_strength_week_context(uuid)` e `freeze_mobile_strength_week_target(uuid,uuid,text,date,jsonb,jsonb)` são RPCs públicas, restritas ao backend confiável. Tabelas, sequências e helpers privados não têm acesso direto para anon, authenticated ou service_role. Os helpers privados de teste com relógio explícito não são endpoints públicos.

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

Antes de ativar, concluir o vínculo e as provas de concorrência dos escritores reais/reset, cobertura e regras de calendário/validade, proveniência dos treinos confirmados, leitura dos consumidores e interface. Registros legados sem origem comprovada não podem virar histórico inventado nem um contador completo artificialmente zerado.
