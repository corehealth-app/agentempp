# Preparação de comandos conversacionais

Implementação inicial, sem rota pública ou writer: `conversation-command-contracts.ts`,
`conversation-meal-preparation.ts` e `@mpp/agent/conversation-meal-intent`.
Não equivale a registro ao enviar, idempotência durável ou timeline pronta.

## Identidade e fonte

O DTO fechado `conversation.command.v1` admite por enquanto somente `meal.report`:
UUID minúsculo, refeição escolhida opcional e texto até 2.000 caracteres ou referência
a mídia com gesto explícito de registro. O header deve ser `cmsg1:<command_id>`.
Dono vem da autenticação; não se aceitam calorias, transcrição do cliente, URLs,
resultados de IA, epoch ou política clínica no corpo.

O hash usa o DTO validado completo, em JSON de chaves ordenadas, preservando o texto
original. Não depende de relógio, extração ou banco. A unicidade permanente é
`(dono, command_id)`: repetir esse par com fonte diferente deve conflitar;
dois IDs novos para refeições iguais devem continuar sendo dois consumos legítimos.
O módulo atual só produz a identidade. A fundação SQL inativa descrita em
`conversation-command-journal.md` já oferece persistência, mas ainda não está ligada
a este preparador nem a uma rota.

## Interpretação e extração

O classificador puro é uma primeira barreira conservadora para **preparar candidatos**,
não uma prova suficiente para gravar. Reconhece um conjunto limitado de relatos
explícitos de primeira pessoa. Perguntas, planos, hábitos, negações, falas citadas,
outras pessoas e predicados adicionais conhecidos ficam conversacionais ou pedem
esclarecimento. Sintaxe não suportada não deve cair no writer legado. A qualificação
de linguagem completa e a cobertura integral da fonte continuam no marco do writer.

Fotos exigem gesto de registro ou relato explícito na legenda. Áudio usa a transcrição
do ativo processado e pertencente à conta. Texto/contexto produzido pelo Vision nunca
comprova consumo. A legenda atual e a transcrição ficam em evidência privada separada;
não podem ser substituídas pelo comentário do Vision nem expostas como autoridade pública.

O preparador reutiliza os extratores de refeição existentes sem ferramentas e sem
calcular/gravar nutrição. Captura callbacks antes dos awaits e destaca o ativo de seus
aliases mutáveis. Guarda ID, tipo, versão/horário e hash do processamento para um futuro
CAS; não guarda paths, credenciais ou URL assinada nesse vínculo. Ainda falta conferir
esse vínculo atomicamente no banco antes de qualquer gravação.

Quantidades explícitas da legenda substituem estimativas visuais somente quando o nome
corresponde a um único candidato. Preparo/nome incompatível, duplicidade ou divergência
entre legenda e fala pedem esclarecimento, preservando ambas as listas. Não inferir que
arroz cru é cozido. A refeição explicitamente selecionada permanece no comando, sem
substituição pelo horário.

Quantidade ausente, nome ambíguo, baixa confiança e trechos omitidos pelo extrator
retêm os demais candidatos e devolvem `clarification_required`. Estimativas de porção
válidas permanecem identificadas e editáveis. Falha do provedor não vira alimento zero.
A ausência integral de candidatos vira esclarecimento sem uma segunda extração.

## Gates ainda obrigatórios

Antes de ativar registro ao enviar: integração do journal e recuperação de resposta,
autoridade semântica completa do relato, fonte/epoch atuais, resolução nutricional e
anotações estruturadas de preparo, dia aberto após locks, writer atômico com recibo
original congelado, correção/undo por versão e timeline paginada. A fundação SQL de
journal foi adicionada separadamente, ainda sem rollout cloud ou caller. Nenhuma flag, rota, recompensa, upload ou versão do TestFlight foi ativada.
