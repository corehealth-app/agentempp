# Calculador de refeição — fonte vinculada opcional

`calcMealMacros` aceita `MealCalculationOptions` com `sourceReader` e `auditSink`.
Os tipos são exportados por `@mpp/agent`. Sem essas opções, consultas, relógio e
auditoria seguem o comportamento legado. O incremento não ativa rota, writer ou
prova semântica e não implementa a factory Supabase do backend.

## Contrato da fonte

`MealNutritionSourceReader` fornece `ownerId`, `asOf` e
`read(kind, foodName): Promise<readonly MealHistoryRow[]>`:

- `trusted_recent`, nome `null`: linhas reais da consulta de histórico recente.
- `exact_median`, nome original: linhas reais da consulta da mediana nutricional.

Cada linha inclui ID, dono, timestamp, nome, referência, quantidade, macros,
proveniência e `food_db.is_verified`. A factory deve fechar sobre dono e comando
imutáveis e chamar somente `read_conversation_meal_nutrition_source`, consumindo
suas linhas reais. Ela deve coletar **todos** os recibos retornados, inclusive
misses e consultas repetidas, para o conjunto `source_receipts` da preparação.
Não há SDK fluente artificial ou fallback para histórico vivo no calculador.

`asOf` é o timestamp RFC3339 retornado pela captura SQL anterior ao cálculo.
Não pode ser um relógio escolhido pelo BFF. Ele fixa também a janela de 30 dias
das correções pessoais; a consulta existente dessas correções continua protegida
pelo epoch SQL de fontes. Alterações de catálogo, correções ou configuração são
revalidadas pela autoridade SQL antes de preparar e gravar.

Antes do primeiro `await`, o calculador captura dono, relógio, callback de leitura,
política e sink; com fonte vinculada, também copia os inputs. Cada retorno de
histórico é copiado e validado antes do uso, incluindo dono, tipos numéricos,
timestamps e limite da consulta. Falha da fonte interrompe o cálculo sem consulta
alternativa. O port não transforma essas linhas em autoridade semântica sobre o
texto ou a mídia original.

## Preparação sem auditoria persistida

O preparador deve sempre fornecer um `auditSink` coletor junto à fonte vinculada.
Os três eventos existentes — valores aprovados rejeitados, kcal informadas
rejeitadas e histórico reutilizado — são entregues como intenções copiadas ao sink.
Nesse modo o calculador não insere `product_events`. Uma falha do sink opcional é
isolada e não provoca fallback de escrita nem repetição do domínio.

Sem sink, o comportamento legado continua inserindo os eventos como antes.
O processamento persistente e idempotente dessas intenções após o commit será
uma integração posterior. As [anotações estruturadas de cozido padrão](conversation-consumed-preparation-annotations.md)
têm opt-in próprio e saem somente do branch real de referência verificada.

## Verificação deste incremento

Os nove testes novos exercitam os dois lookups reais pela interface, miss e erro
sem fallback, isolamento de dono, relógio inválido, mutação dos inputs/opções
durante um `await`, falha do sink e preservação do caminho legado. Os resultados
esperados são macros factuais explícitos. A suíte completa do agente e os testes
vizinhos de política de consumo e cálculo foram executados; nenhuma operação de
Postgres, runtime ou cloud foi necessária neste incremento.
