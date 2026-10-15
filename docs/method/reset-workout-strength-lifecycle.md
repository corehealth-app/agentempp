# Redefinição da conversa e ciclo dos treinos — S14

A redefinição compartilhada por Flow e WhatsApp passa a encerrar o ciclo aberto dos treinos de força da conta. A API mantém os overloads `reset_user_conversation_atomic(uuid, boolean)` e `reset_user_conversation_atomic(uuid)`; o segundo continua delegando com preservação dos planos.

## Ordem e atomicidade

Depois do guard backend e da validação dos argumentos, a função adquire o advisory da conta com `hashtextextended(user_id || ':workouts', 0)`, antes do `users FOR UPDATE` existente. Essa ordem vale também quando a conta não tem ciclo aberto. Encontrada a conta, fecha apenas seu ciclo aberto, usando `clock_timestamp()` depois dos locks e uma chave `reset_user_conversation:` com UUID gerado pelo banco. Em seguida executa a limpeza existente.

O CHECK de fechamento continua exigindo `closed_at >= opened_at`. Um fechamento inválido aborta a operação inteira. Um ciclo já fechado conserva data e chave originais. A redefinição não admite um ciclo novo; a admissão posterior pertence ao produtor. O comportamento legado para conta existente inativa permanece, enquanto os produtores de força continuam exigindo conta ativa.

## Dados e concorrência

As operações, comandos e scopes antigos conservam a identidade do ciclo fechado. As FKs existentes removem os fatos dos treinos apagados e anulam suas referências vivas nas operações. Uma resposta antiga não pode ser transferida para um UUID novo gerado por uma correção de treino. Os modos de preservação dos planos, confirmação de rascunhos, metadados, identidade, progresso, contagem `deleted_rows`, guard e permissões seguem o corpo legado.

Captura e resposta de força revalidam o ciclo depois do advisory comum. Uma operação que obtém o lock após uma redefinição confirmada encontra o ciclo antigo fechado. Se a redefinição é revertida, o ciclo anterior permanece válido. O writer legado de 13 argumentos também usa o advisory, mas não valida o ciclo nem o status da conta; a serialização não significa uma barreira global para gravações legadas posteriores. Hard delete da conta e status de conta são cenários distintos.

## Evidência e limites atuais

O teste causal foi escrito e revisado antes da correção. Em PostgreSQL 17.11 local, a função anterior produziu exatamente `C59S14_ASSERT:exact_old_reset_closes_open_lifecycle`. A preparação instalou os 13 assets reais em uma transação, preservando objetos e dados anteriores. Após o teste, os fingerprints dos quatro bancos permitidos coincidiram com a base posterior à preparação, e o banco foi encerrado.

Em 15/10/2026, a regressão com a correção passou: 38 assertivas sequenciais, os dois arquivos legados inalterados com 23 oráculos e 13 cenários de duas sessões reais. Cada disputa observou o bloqueio de B por A no banco, incluindo commit, rollback, exclusão da conta e redefinição sem ciclo. Os dois processos de teste terminaram com código zero e seus leitores foram encerrados.

A migração foi aplicada uma única vez, diretamente, com seu próprio `BEGIN`/`COMMIT`. Seu inverso remove somente o `BEGIN` acrescentado, o comentário inicial, o advisory e o fechamento, recuperando o trecho anterior byte a byte. A preparação local precisou corrigir a propriedade dos objetos novos para `postgres`, conforme o bootstrap existente, e instalar três tabelas reais de rotina exigidas pelo trigger de status já presente. Foram preservados seus checks, FKs, RLS, políticas e privilégios originais, sem dados de rotina ou hooks substitutos. As tentativas incompletas anteriores ficaram registradas; seus resultados parciais não foram contados como aprovação.

Após a preparação, 17 snapshots completos e um packet interno de instalação permitiram conferir os objetos, ACLs, dados e sequências. Os quatro fingerprints finais coincidiram com a base posterior à preparação, os dados de teste foram removidos pelo teardown delimitado e o PostgreSQL local foi parado com o diretório de dados preservado. A migração e a normalização dos proprietários não foram reaplicadas na execução final.

Os testes reproduzíveis estão em `supabase/tests/reset_workout_strength_lifecycle.sql`, com fixture e controlador de concorrência em `supabase/tests/fixtures/reset_workout_strength_lifecycle_*`. O teste sequencial usa rollback; a execução de concorrência requer preparação e teardown explícitos do seu próprio namespace. O controlador exige bindings locais revisados e dois processos reais, sem simular o bloqueio.

Esta evidência local não comprova ativação dos produtores, autenticação HTTP, staging ou funcionamento no iPhone. A validação dessas integrações integra os grupos seguintes da entrega beta.
