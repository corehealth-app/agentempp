# Flow: custo e velocidade do chat

O chat do Flow (app iOS) usa o mesmo código de agente do WhatsApp
(`packages/agent`). Tudo o que está aqui vale **só para o Flow**; o WhatsApp
continua byte a byte igual. Dois goldens travam isso, cada um a sua parte:

- `packages/agent/src/__golden__/audit-10-04-whatsapp-request-lock.test.ts`
  trava o pedido inteiro de dois turnos de WhatsApp. Pega o vazamento de
  qualquer mudança que apareça no pedido desses dois turnos: janela do
  histórico, contexto enxuto, texto da anti-repetição, telemetria por chamada
  e limites de tempo.
- `packages/agent/src/__golden__/audit-10-04-flow-turn-calls.test.ts` pega os
  vazamentos que esses dois turnos não mostram: teto de iterações, chamada de
  fechamento, status em texto simples e cliente medido das ferramentas. O
  lock de pedido fica verde nesses quatro casos (conferido por mutação).

Nada aqui foi para staging ou produção ainda: os números de "depois" são da
sonda local (pipeline real, banco falso), não de cobrança.

## Linha de base (staging, conta de QA, lida em 2026-10-04)

- Uma chamada ao modelo leva cerca de **11.000 tokens de entrada** para uma
  resposta de 20 a 150 tokens. Custo médio por resposta: **US$ 0,035**. Tempo:
  mediana 14 s, p90 74 s.
- Desses 11.000, cerca de 5.060 são o prefixo em cache (tools, regras e
  política do Flow), lido a 10% do preço. Os outros ~5.900 são pagos a preço
  cheio em toda chamada: ~1.550 de contexto do turno e ~4.400 de histórico.
- Chamada com cache lido: US$ 0,0206. Com cache escrito (1 h): US$ 0,0495.
  Turno com ferramenta são duas chamadas e paga a parte sem cache duas vezes.

## Parte 1 — o tamanho de uma chamada

Três mudanças em `packages/agent/src/pipeline.ts`, todas atrás de
`historyProvider === 'mobile_flow'`:

1. **Histórico: a sessão atual inteira, e do que veio antes só o que falta
   para 16 linhas** (`mobileFlowPromptHistory`,
   `MOBILE_FLOW_PROMPT_HISTORY_LINES`, `MOBILE_FLOW_SESSION_HOURS`). Conta
   como sessão atual, e vai sempre para o modelo, toda linha que a leitura
   trouxe e que é:
   - do dia local atual do paciente, a qualquer hora; ou
   - das 6 horas anteriores ao turno, mesmo sendo do dia anterior (a conversa
     que atravessa a meia-noite).

   As linhas mais antigas que isso só entram, das mais recentes para as mais
   antigas, até o total chegar a 16. Toda linha de um dia anterior continua
   levando o prefixo de data, esteja ou não na sessão. A leitura do banco
   continua em 50 linhas, e a resposta pronta do sistema sobre treino e comida
   continua lendo a lista inteira.

   A primeira versão cortava nas últimas 16 linhas, de qualquer dia. A revisão
   mostrou o efeito: uma alergia dita 18 linhas antes, na mesma sessão, saía
   da vista do modelo, e o gerador de cardápio (que só recebe restrições pelos
   argumentos do modelo) recebia "(nenhuma)". A segunda versão contava só o
   dia local, e a segunda revisão mostrou o mesmo efeito à meia-noite: às
   00:05, as 49 linhas ditas entre 23:10 e 23:59 viravam "dia anterior" e só
   as 16 mais novas iam ao modelo. Por isso as 6 horas. A economia do
   histórico **só existe quando há linhas de fora da sessão** (números
   abaixo). O que a regra não cobre está em RC PERF-W1 e RC PERF-W2.
2. **Contexto do turno enxuto** (`MOBILE_FLOW_LEAN_CONTEXT`). Saiu só o que o
   Flow não usa: as ordens de chamar `confirma_pais_residencia` e
   `pausar_agente` (tools que ele não tem), a tabela de `meal_type`, a
   sugestão de refeição e o aviso de `replace` (servem ao registro de
   refeição), as duas regras de foto e a citação das duas últimas respostas
   (já são as últimas linhas do histórico). Perfil, linha de data e hora,
   regra de idioma e o bloco "Dados numéricos REAIS" inteiro (com as linhas de
   energia e a REGRA) ficaram palavra por palavra. As três instruções de
   anti-repetição também ficaram; só a citação saiu, e a primeira instrução
   passou de "se já estão acima" para "se já estão nas suas últimas respostas
   do histórico" (sem a citação, "acima" apontava para os números do contexto).
3. **Telemetria por chamada, só números**: um evento `llm.flow_calls` por
   turno em `product_events`, ao lado do `llm.cache_usage`. Para cada chamada:
   índice, modelo, tokens de entrada e saída, tokens lidos e escritos no
   cache, custo, milissegundos, linhas de histórico enviadas, caracteres de
   cada bloco do system, número e caracteres das mensagens. Nenhum texto do
   paciente nem da resposta. O evento também é gravado quando o turno termina
   em erro (ver Parte 2, item 6).

O prefixo em cache não mudou (mesmas tools, mesmo bloco estável): a mudança
não invalida o cache.

### Antes → depois (sonda, conta parecida com a de QA: 50 linhas disponíveis, 39 delas de dias anteriores)

Tokens estimados por caracteres ÷ 3,0, a calibração do mapa de 04/10.

| Bloco de uma chamada | Antes | Depois |
|---|---|---|
| Tools (em cache) | 4.446 car. / ~1.480 tok | igual |
| System estável (em cache; regras de exemplo na sonda) | 1.734 car. | igual |
| Contexto: localização e idioma | 764 car. / ~255 tok | 415 car. / ~138 tok |
| Contexto: hora local | 711 car. / ~237 tok | 110 car. / ~37 tok |
| Contexto: perfil | 404 car. / ~135 tok | igual |
| Contexto: dados numéricos REAIS | 1.227 car. / ~409 tok | igual |
| Contexto: regras importantes | 769 car. / ~256 tok | 305 car. / ~102 tok |
| Contexto: anti-repetição | 832 car. / ~277 tok | 421 car. / ~140 tok |
| **Contexto do turno, total** | **4.719 car. / ~1.573 tok** | **2.894 car. / ~965 tok** |
| **Histórico** | **49 linhas, 14.849 car. / ~4.950 tok** | **16 linhas (10 de hoje + 6 de dias anteriores), 4.221 car. / ~1.407 tok** |
| Mensagem atual | 48 car. | igual |
| **Total pago a preço cheio** | **19.616 car. / ~6.539 tok** | **7.163 car. / ~2.388 tok** |

**Com as 49 linhas todas de hoje** (uma sessão longa no mesmo dia), a mesma
sonda dá outro resultado: as 49 linhas vão para o modelo, como antes
(10.988 car.), e só o contexto encolhe. O total a preço cheio vai de
15.755 car. / ~5.252 tok para **13.930 car. / ~4.643 tok**: cerca de 600
tokens a menos (12%). Com o corte fixo em 16 linhas da primeira versão esse
caso ia a ~2.178 tokens; a troca pela regra do dia devolveu ~2.465 tokens por
chamada a esse caso, que é o preço de o modelo ver a sessão inteira. A
cobrança real de 04/10 (~5.950 tokens a preço cheio) fica entre os dois
cenários de "antes".

**Com as mesmas 49 linhas ditas entre 23:11 e 23:59 e o turno às 00:05** (a
sessão que atravessa a meia-noite), as 49 linhas também vão para o modelo,
todas com o prefixo de data (15.839 car.). O total a preço cheio vai de
20.600 car. / ~6.867 tok para **18.786 car. / ~6.262 tok** (~600 tokens a
menos, 9%). Com a regra só do dia local esse caso ia a 16 linhas e ~2.719
tokens, e era nele que a alergia sumia; as 6 horas devolveram ~3.540 tokens
por chamada a esse caso.

- **Custo de uma chamada com cache lido**, a preço de lista do Sonnet 4.6
  (entrada 3, leitura de cache 0,30, saída 15 por milhão; 5.060 tokens em
  cache, 80 de saída), na sonda:
  - conta com 39 das 49 linhas em dias anteriores: de US$ 0,0223 para
    **US$ 0,0099**, menos da metade;
  - 49 linhas todas de hoje: de US$ 0,0185 para **US$ 0,0166**, 10% a menos;
  - 49 linhas da sessão que atravessou a meia-noite: de US$ 0,0233 para
    **US$ 0,0215**, 8% a menos.
  A cobrança real de "antes" foi US$ 0,0206.
- Chamada com cache escrito: de US$ 0,0495 (cobrança) para cerca de US$ 0,039
  no primeiro caso, cerca de US$ 0,045 no segundo e cerca de US$ 0,050 no
  terceiro.
- Chamadas por turno: igual (1 sem ferramenta, 2 com ferramenta).
- Passos aguardados no banco dentro do agente: igual (17 no turno de uma
  chamada, 19 no de duas). O evento novo é gravado junto com o
  `llm.cache_usage`, no mesmo passo.
- Tempo: não medido. O mapa estimou 0,1 a 0,4 s por chamada.

### Como conferir em staging

```sql
select occurred_at, c->>'index' as chamada, c->>'prompt_tokens' as entrada,
       c->>'cache_read_tokens' as cache_lido, c->>'cache_write_tokens' as cache_escrito,
       c->>'history_lines' as linhas, c->'system_chars' as blocos, c->>'ms' as ms
from product_events, jsonb_array_elements(properties->'calls') c
where event = 'llm.flow_calls'
order by occurred_at desc;
```

Esperado: `blocos` = [tamanho do bloco estável, ~2.900]. `linhas` = todas as
linhas da sessão atual (as de hoje e as das 6 horas antes do turno); 16 quando
a sessão tem menos de 16 e há linhas mais antigas. `entrada` perto de 7.400
nesse segundo caso (era ~11.000); numa sessão com 49 linhas fica perto de
9.700 (de hoje) ou de 11.300 (do outro lado da meia-noite, com o prefixo).

### Como reverter (cada um é uma linha em `packages/agent/src/pipeline.ts`)

- Histórico: `MOBILE_FLOW_PROMPT_HISTORY_LINES = 50` (com 50 a janela deixa
  de cortar: tudo o que a leitura traz é enviado). Para voltar só à regra do
  dia local, sem as 6 horas: `MOBILE_FLOW_SESSION_HOURS = 0`.
- Contexto enxuto: `MOBILE_FLOW_LEAN_CONTEXT = false`.
- Telemetria: trocar `options.historyProvider === 'mobile_flow' ? [] : null`
  por `null` na declaração de `flowCalls`.

Com as duas primeiras revertidas, o pedido do Flow volta a ser idêntico ao de
antes (conferido na sonda). O golden
`audit-10-04-flow-prompt-budget.test.ts` trava os valores novos e precisa
acompanhar a reversão.

### Testes

- `audit-10-04-whatsapp-request-lock.test.ts` (3 testes) e o fixture
  `fixtures/audit-10-04-whatsapp-request-lock.json`: dois turnos de WhatsApp
  (paciente estabelecido com ferramenta e retry de guarda; paciente novo com
  botões). Trava todos os argumentos de cada chamada ao modelo, a saída e a
  ordem das consultas ao banco. Gerado antes de qualquer mudança. Vazar para
  o WhatsApp a janela, o contexto enxuto, o texto da anti-repetição ou a
  telemetria quebra este teste (conferido, uma a uma). Ele não pega tudo: ver
  o começo deste documento.
- Diferencial fora do repositório (sonda): 24 turnos de WhatsApp (30 chamadas
  ao modelo) rodados no commit anterior e na árvore atual, com pedidos, saídas
  e consultas ao banco idênticos. Os mesmos 24 turnos no Flow: mesma saída,
  mesmo número de chamadas, mesmas tools e mesmo bloco estável; mudam só o
  bloco do turno, a janela do histórico e o evento novo.
- `audit-10-04-flow-prompt-budget.test.ts` (46 testes): a janela (hoje
  inteiro, inclusive linhas de hoje ditas há mais de 6 horas; 16 linhas quando
  a sessão é curta; só dias anteriores; a meia-noite local há três minutos,
  com 49, 29, 9 e 2 linhas na sessão; a função da janela sozinha), prefixo de
  data mantido, leitura de 50 linhas mantida,
  resposta pronta de treino e comida com histórico longo, contexto do turno
  caractere por caractere, cada linha do contexto igual à do WhatsApp ou
  cortada/trocada em ponto conhecido, evento só com números, falha da
  telemetria não chega ao paciente, e o evento do turno que falha (uma vez,
  sem texto, sem esconder o erro do turno).
- `audit-10-04-flow-turn-calls.test.ts`, bloco "an allergy said earlier the
  same day": o cenário da revisão, com a frase exata ("Importante: sou
  intolerante a lactose e alérgico a castanhas.") dita 2, 6, 10, 14, 16, 18,
  20, 30 e 48 linhas antes de "Agora monte um cardápio para hoje", 49 linhas
  todas de hoje. Em todas o gerador recebe "lactose, castanhas" (antes, de 18
  em diante recebia "(nenhuma)"). No mesmo bloco, o cenário da segunda
  revisão: paciente em America/Sao_Paulo, turno às 00:05 de 05/10
  (2026-10-05T03:05Z), 49 linhas ditas entre 23:10 e 23:59, a mesma frase 10,
  16, 18 e 30 linhas antes do pedido. Nas quatro o gerador recebe "lactose,
  castanhas" e as 49 linhas vão ao modelo com o prefixo de 04/10 (com a regra
  só do dia local, 18 e 30 davam "(nenhuma)"). Também: a linha dita exatamente
  6 horas antes do turno fica e a dita um minuto antes disso é cortada; a
  alergia dita às 00:10 do mesmo dia local, 12 horas antes, chega ao gerador.

## O que não foi feito nesta parte, e por quê

- Reordenar o prompt para pôr o histórico em cache: muda o papel do contexto e
  rende menos do que encolher.
- Mudar o TTL ou os pontos de cache: decisão que depende de uma semana do
  evento `llm.flow_calls`.
- Encurtar o prefixo de dia anterior: reabre o bug de 28/09 e mexe em golden.
- Tirar tools do Flow: não há dado de quais são chamadas.
- Modelo, `max_tokens` e `agent_configs`: não tocados.

## Pendências

> RC PERF-1 — cenário histórico e linha do dia REAIS da conta de QA às 15:21 NÃO coberto nesta PR (pendência da audit 2026-10-04). A leitura do baseline não trouxe o texto das mensagens nem a linha do dia daquele minuto: a frase é a exata, o perfil e a linha do dia são os da leitura de 15:03:40Z do mesmo dia e o histórico do golden é sintético (59 linhas).

> RC PERF-2 — cenário qualidade da resposta do MODELO com a janela do histórico e o contexto enxuto NÃO coberto nesta PR (pendência da audit 2026-10-04). Não há chave de modelo local. Só uma rodada em staging ou no iPhone com as mesmas perguntas prova que a resposta não piorou. O modelo vê a sessão atual inteira (o dia de hoje e as 6 horas antes do turno) e deixa de ver as linhas anteriores a ela além das que completam 16.

> RC PERF-W1 — cenário alergia ou intolerância dita em DIA ANTERIOR há mais de 6 horas, fora da janela (por exemplo, ontem de manhã, com 16 ou mais linhas na sessão atual) NÃO coberto nesta PR (pendência da audit 2026-10-04). O modelo não lê a linha e o gerador de cardápio recebe "(nenhuma)". Restrições não são gravadas no perfil; gravar é a solução de fundo e fica fora desta mudança. Travado como pendência em `audit-10-04-flow-turn-calls.test.ts`, em dois casos: dita ontem de manhã com 20 linhas hoje; e dita às 17:50, com o turno às 00:05 e 20 linhas depois das 23:30. A linha de dia anterior dita nas 6 horas antes do turno está coberta.

> RC PERF-W2 — cenário alergia dita há mais de 49 linhas no MESMO dia NÃO coberto nesta PR (pendência da audit 2026-10-04). A leitura do banco traz 50 linhas; o que ficou antes disso nunca chegou ao modelo, antes ou depois desta mudança.

> RC PERF-3 — cenário tokens reais (prompt_tokens cobrados) antes × depois NÃO coberto nesta PR (pendência da audit 2026-10-04). Os testes medem caracteres e linhas, e os tokens são estimativa (caracteres ÷ 3,0). O evento `llm.flow_calls` é o que mede em staging.

> RC PERF-4 — cenário linhas "DIA PENDENTE"/"FOTO PENDENTE"/fotos corporais do contexto (mandam chamar marca_refeicao_pulada/registra_refeicao, que o Flow não tem) NÃO coberto nesta PR (pendência da audit 2026-10-04). O mapa não mediu esses blocos no Flow e eles ficaram como estavam.

> RC PERF-5 — cenário paciente do app com país NÃO confirmado NÃO coberto em dado real nesta PR (pendência da audit 2026-10-04). O contexto deixa de mandar perguntar o país, porque o Flow não tem a tool que grava a resposta (travado no golden). Não sei se existe conta do app nesse estado.

> RC LOCK — cenário turno de WhatsApp com foto/áudio, registro com botões, correção (replace), reavaliação, "bom dia" e modelos não-Anthropic (system em string única) NÃO coberto nesta PR (pendência da audit 2026-10-04). Estes dois turnos travam o caminho de texto; os demais continuam cobertos só pelos testes que já existiam.

> RC LOCK — cenário regras reais de produção (agent_rules) NÃO coberto nesta PR (pendência da audit 2026-10-04). O banco é falso: as regras são três linhas de exemplo, não as do Notion.

## Parte 2 — quantas chamadas um turno faz e quanto ele pode esperar

**A economia na sugestão de plano (uma chamada em vez de duas) vale só para o
pedido simples, único e explícito — "Sugira um cardápio completo para hoje",
"Monta meu treino de 3 dias na academia"; todo o resto faz a segunda chamada,
como antes desta mudança.**

Seis mudanças, todas ligadas em `packages/agent/src/pipeline.ts`, atrás de
`historyProvider === 'mobile_flow'`; a terceira tem uma segunda trava no
serviço que só o Flow usa (`apps/admin/src/lib/mobile-api/flow-chat-service.ts`).
Nenhuma mexe no texto do prompt, no modelo, em `max_tokens`, em
`agent_configs` ou em regra de cálculo (a chamada de fechamento do item 2 muda
um parâmetro do pedido, `tool_choice`, não o prompt). O WhatsApp continua byte
a byte igual.

1. **Sugestão de plano sem a segunda chamada do modelo, quando a mensagem é
   um pedido simples, único e explícito**
   (`MOBILE_FLOW_DIRECT_PLAN_SUGGESTION`). O turno termina na chamada da
   ferramenta quando as quatro condições valem:
   - as únicas ferramentas do turno são `propoe_plano_treino` /
     `propoe_plano_dieta` e todas devolvem a sugestão;
   - nenhuma guarda forçou repetição antes;
   - a mensagem do paciente é um pedido único (`isSingleRequestMessage`, em
     `plan-suggestion-text.ts`): não tem "?" e vale **tudo** isto (a
     comparação ignora maiúsculas e acentos):
     - **(a) só palavras da lista.** Todas as palavras estão numa lista
       fechada (`SINGLE_REQUEST_VOCABULARY`) ou são um número que conta dias
       ou vezes ("3 dias", "3 vezes por semana"). A lista:
       - verbos de pedido: monte, monta, montar, sugira, sugere, sugerir,
         crie, cria, criar, faça, faz, fazer, gere, gera, gerar, prepare,
         quero, queria, preciso, pode, poderia, consegue, me, dá, passa, manda;
       - nomes de plano: sugestão, cardápio, dieta, menu, plano, alimentar,
         alimentação, refeições, treino, treinos, exercícios;
       - qualificadores: completo, completa, novo, nova, simples, rápido,
         outro, outra;
       - tempo e lugar: hoje, amanhã, agora, semana, dia, dias, vezes, por,
         na, em, casa, academia;
       - artigos, preposições e pronomes: um, uma, o, a, os, as, de, do, da,
         para, pra, pro, meu, minha, mim;
       - cortesia: oi, olá, bom, boa, tarde, noite, favor, pf, pfv, obrigado,
         obrigada, valeu, flow.

       **"e" não está na lista**: é a palavra que liga dois pedidos. "mais",
       "também" e "tb" nunca estiveram.
     - **(b) um plano só.** A mensagem cita cardápio ou treino, nunca os dois.
       "academia" ao lado de um nome de cardápio é o treino ("uma dieta e um
       plano pra academia", "dieta academia"); em "treino de 3 dias na
       academia" é o lugar de um treino só. Os nomes de plano formam um grupo
       só: entre o primeiro e o último só cabem de, do, da, para, pra, pro,
       meu, minha, completo, completa, novo, nova, simples e rápido ("sugestão
       de cardápio", "plano novo de treino"); "um cardápio um plano" e
       "cardápio pra hoje cardápio pra amanhã" são dois pedidos. E o pedido é
       para um dia só: "hoje" e "amanhã" na mesma mensagem são dois.
     - **(c) uma oração só.** A mensagem é cortada em tudo o que não é letra,
       número ou espaço (vírgula, ponto, quebra de linha, travessão,
       parêntese, emoji). Fora o pedido, só pode sobrar saudação ou
       agradecimento: oi, olá, bom dia, boa tarde, boa noite, por favor, pf,
       pfv, obrigado, obrigada, valeu, flow ("Oi, …", "Bom dia!", "…, por
       favor.", "… Valeu!!"). Qualquer outra coisa separada por pontuação é
       um segundo pedido ("Monte um cardápio para hoje, outro para amanhã").
     - **(d) o plano está escrito na mensagem.** Ela tem um nome de cardápio
       (cardápio, dieta, menu, alimentar, alimentação, refeições) ou de treino
       (treino, treinos, exercícios); "plano", "sugestão" e "academia"
       sozinhos não bastam. E todo "um", "uma", "o", "a", "os", "as", "outro"
       ou "outra" vem antes de um nome de plano, de tempo ou de lugar ("outro
       cardápio", "o meu treino", "a semana", "a academia"), com no máximo
       meu, minha e qualificadores no meio; no lugar do nome ("outro para
       amanhã", "o de amanhã", "os 2") é um segundo pedido ou uma referência
       à linha anterior. A resposta
       curta que tira o sentido da linha anterior do Flow — "Quero", "pode",
       "Pode ser", "manda", "quero os 2", "1 e 2", "faz os 2", "Quero, por
       favor" — não é pedido único: pode estar aceitando uma oferta de duas
       coisas. **Uma exceção, listada inteira** (`SINGLE_REQUEST_EXACT_REPLIES`):
       "Pode ser equilibrado no geral.", a resposta do paciente à pergunta do
       Flow sobre o foco do treino no turno do aparelho de 30/09, uma das duas
       frases em que o caminho de uma chamada foi medido. Vale a frase (as
       cinco palavras, nessa ordem), não as palavras dela: "Pode ser", "Pode
       ser equilibrado" e "o treino de hoje pode ser em casa" fazem a segunda
       chamada. O que a exceção deixa em aberto está em RC PERF-C10;
   - o modelo não escreveu texto junto da chamada da ferramenta.

   A resposta é então o texto que o código já enviava quando o modelo resumia
   ou parafraseava (`ensureSuggestionShown`, sem alteração): "Sua sugestão
   está pronta:" + a sugestão gravada + "É um rascunho: toque em "Revisar
   sugestão" para conferir, ajustar e confirmar. Ele só vale depois que você
   confirmar." O rascunho gravado, os validadores do texto final e o que o app
   recebe não mudam. Nesses turnos o paciente deixa de ver a frase livre de
   abertura do modelo.

   Em todos os outros casos o modelo faz a segunda chamada, como antes. A
   primeira versão olhava só as ferramentas, e a revisão mostrou o que isso
   custava: em "Monte uma sugestão de cardápio para amanhã. E quanto falta de
   proteína hoje?" a resposta era só a sugestão, sem uma palavra sobre a
   proteína. A segunda versão procurava marcas de um segundo pedido ("?",
   segunda frase), e a segunda revisão mostrou que ela deixava passar todo
   jeito de escrever que não tinha previsto: vírgula ("Monte um cardápio pra
   hoje, quanto falta de proteína hoje"), a pergunta antes, "tb quero saber",
   "e me diga", inglês, e o pedido de dois planos ("Sugira um cardápio e um
   treino" parava depois do cardápio). A terceira versão era só a lista
   fechada, e a terceira revisão mostrou o que uma lista de palavras sozinha
   não vê: "Monte uma dieta e um plano pra academia", "Quero um cardápio e um
   plano de academia" e "quero dieta e academia" eram escritas só com palavras
   da lista e passavam como um pedido (o turno parava no cardápio e o treino
   sumia); e as respostas "quero os 2", "1 e 2", "faz os 2", "Quero", "pode",
   "Pode ser" e "manda", depois de uma linha do Flow que oferecia duas coisas,
   também. Daí as condições (b), (c) e (d).

   A regra continua fechada, e o desconhecido vai para o outro lado: qualquer
   palavra fora da lista ("quanto", "falta", "proteína", "também", "tb",
   "joelho", "kcal", uma abreviação, um erro de digitação, qualquer palavra em
   inglês) manda o turno para a segunda chamada, como era antes de existir o
   caminho direto. Primeiro certo, depois barato. O custo é conhecido, e são
   pedidos únicos que ficam com as duas chamadas: escrito como pergunta
   ("Pode montar um cardápio para hoje?"), em inglês ("Please suggest a full
   menu for today"), com unidade ("…de 2.000 kcal"), com "hj", com "e" ("um
   cardápio simples e rápido", "por favor e obrigado"), com um número que não
   conta dias ou vezes ("um cardápio de 1500"), com quebra de linha ou emoji
   no meio do pedido, só com "plano" ("Monte um plano pra academia"), e o
   turno em que o modelo escreve uma frase junto da chamada.

   **O que ainda fica com uma chamada só** (medido na sonda e travado no
   golden): as duas frases da linha de base ("Sugira um cardápio completo para
   hoje", com ou sem acento, ~2.322 tokens a preço cheio; "Pode ser
   equilibrado no geral.", ~2.320), o pedido explícito de treino ("Monta meu
   treino de 3 dias na academia", ~2.322) e variantes simples com saudação ou
   agradecimento ("Oi, monte um cardápio pra hoje", "Bom dia! Sugira um
   cardápio completo para hoje, por favor", "Monte um cardápio pra hoje,
   obrigado 🙏", "Monta meu treino de 3 dias na academia. Valeu"). Das 22
   redações que a segunda revisão testou, 8 ficam com uma chamada (eram 16
   com a regra da pontuação e 8 com a lista sozinha) e as outras 14 fazem as
   duas, com pedidos e respostas iguais aos do commit anterior. Quantos turnos
   reais de sugestão caem em cada lado só se sabe em staging
   (`plan_suggestion_direct` no evento; RC PERF-C14). O que a regra ainda não
   distingue está em RC PERF-C10 e RC PERF-C16.
2. **No máximo 2 iterações com ferramenta, no código, e uma chamada de
   fechamento** (`MOBILE_FLOW_MAX_MODEL_ITERATIONS`,
   `MOBILE_FLOW_CLOSING_CALL`). Antes o número de iterações vinha só de
   `agent_configs.max_tool_iterations`, linha que a produção divide com o
   WhatsApp (padrão do banco: 5). As repetições de guarda continuam tendo a
   sua iteração própria. O WhatsApp usa o número configurado.

   Só o teto deixava um buraco: se o modelo pedia ferramenta nas duas
   iterações, o turno terminava sem texto e o serviço devolvia 502 depois de
   duas chamadas pagas (onde a config permite 3 ou mais, o modelo respondia na
   terceira). Agora, quando a última iteração permitida foi uma chamada de
   ferramenta, o modelo recebe **uma** chamada a mais com as ferramentas
   desligadas (`tool_choice: none`; as ferramentas continuam no pedido, então
   o prefixo em cache é lido como em toda chamada) para responder com o que
   as ferramentas já devolveram. A resposta passa pelas mesmas guardas de
   qualquer resposta do modelo. A chamada só é feita se o prazo do turno ainda
   permite, aparece em `llm.flow_calls` com `closing: 1`, e uma ferramenta que
   o modelo ainda peça nela não é executada. O pior caso passa a ser 3
   chamadas (2 + fechamento), mais as repetições de guarda.

   **Só um turno não ganha a chamada de fechamento:** o de pedido único
   (item 1) que já tem uma sugestão gravada. Nele a sugestão é a resposta
   inteira. A versão anterior negava a chamada a todo turno com sugestão
   gravada, e a segunda revisão mostrou o buraco: em "Monte uma sugestão de
   cardápio para amanhã. E quanto falta de proteína hoje?", com o modelo
   gastando as duas iterações em ferramentas (leitura e depois plano, ou o
   inverso), o turno terminava só com a sugestão e a proteína ficava sem
   resposta. O mesmo com "Como foi minha semana? E monte um cardápio para
   hoje.". Agora esses turnos fazem 3 chamadas e respondem as duas coisas,
   com config 2, 3 ou 5 (com a config 2 de staging o commit anterior também
   perdia a pergunta). O pedido de dois planos em que o modelo chama uma
   ferramenta por iteração ("Sugira um cardápio e um treino") também ganha a
   chamada: os dois rascunhos são gravados e as duas sugestões entregues,
   como no commit anterior, com uma chamada a mais do que ele quando a config
   é 2 (3 em vez de 2). O mesmo vale para as mensagens da terceira revisão
   que a regra de pedido único agora reconhece como dois pedidos ("Monte uma
   dieta e um plano pra academia", "Quero um cardápio e um plano de academia",
   "quero dieta e academia") e para as respostas "quero os 2", "1 e 2" e "faz
   os 2" depois de uma oferta de dois planos.

   **Erro do provedor na chamada de fechamento.** Se já há uma sugestão
   gravada, o turno não falha: a resposta é a sugestão gravada com o texto
   fixo do item 1 (a mesma saída que o prazo usa, item 3), e a chamada que
   falhou fica em `llm.flow_calls` com `closing: 1` e `failed: 1`, num evento
   sem `turn_failed`. Antes o erro subia: em "Monte uma sugestão de cardápio
   para amanhã. E quanto falta de proteína hoje?" com plano, leitura e a
   chamada de fechamento respondida com erro, o turno falhava depois de três
   chamadas pagas e do gerador, e o rascunho ficava pendente sem resposta no
   chat (com a config 2 de staging o commit anterior terminava em duas
   chamadas, com a sugestão). A outra pergunta continua sem resposta nesse
   turno (RC PERF-C13). Sem sugestão gravada não há o que responder e o turno
   falha, como antes (RC PERF-C8).

   O que a chamada de fechamento não garante está em RC PERF-C8 e RC
   PERF-C15: uma repetição de guarda feita depois dela volta a ter as
   ferramentas ligadas; um erro do provedor nela derruba o turno que não tem
   sugestão gravada; e, como ela vem com as ferramentas desligadas, o plano
   que o modelo só pede na terceira iteração (leitura, leitura, plano) não é
   gerado no turno.
3. **Limites de tempo próprios** (`MOBILE_FLOW_TIME_LIMITS`): 45 s por
   tentativa de chamada de chat (`MOBILE_FLOW_CHAT_CALL_TIMEOUT_MS`) e 150 s
   de trabalho de modelo por turno (`MOBILE_FLOW_TURN_DEADLINE_MS`), contados
   do início do agente. Nenhuma chamada começa depois do prazo, e cada
   tentativa é cortada nele. A nova tentativa do cliente (1) só é mantida
   enquanto duas tentativas de 45 s cabem no que resta. **O que essa conta não
   inclui é a espera do cliente entre as duas tentativas:** cerca de 0,5 s
   normalmente, e até 60 s quando o provedor responde 429 com `Retry-After`
   (o SDK obedece o cabeçalho). Nesse caso uma chamada de chat pode durar até
   45 + 60 + 45 s e terminar depois dos 150 s; quem encerra o turno então é a
   trava do serviço (RC PERF-T4). A regra ficou como estava de propósito:
   exigir que a espera de 60 s também coubesse (2 × 45 + 60 = 150 s) desligaria
   a nova tentativa em todo turno real, porque a primeira chamada nunca começa
   com os 150 s inteiros.

   Vencido o prazo, o turno falha com o erro que o serviço já devolve para
   falha do provedor (502 `flow_provider_failed`, mensagem do paciente em
   `failed`), e o app pode tentar de novo na hora — **a não ser que o turno já
   tenha uma sugestão gravada**: aí ele não falha. Se restam menos de 12 s do
   prazo (`MOBILE_FLOW_SUGGESTION_ANSWER_MIN_MS`; a cópia de uma sugestão
   levava de 8 a 12 s) nenhuma chamada nova é feita, e se uma chamada falha
   nessa faixa o erro não sobe: a resposta é a sugestão gravada, com o texto
   fixo do item 1. Antes o turno falhava com 502, o rascunho ficava pendente
   sem resposta no chat e o custo do gerador não aparecia em lugar nenhum. O
   evento marca esses turnos com `plan_suggestion_at_deadline: 1`.

   O serviço tem uma segunda trava, de 165 s contados do início do turno
   (`FLOW_TURN_HARD_LIMIT_MS`), para o que não é chamada de modelo. Os números
   ficam abaixo dos 180 s que o app espera (`MobileFlowChatRepository.swift`)
   e dos 300 s da função (`maxDuration`).
   **Gerador de plano:** o limite dele continua em 120 s. O mapa mostrou que
   ele podia passar do prazo (chamada de chat no pior caso + 120 s), então a
   menor mudança foi: a chamada do gerador recebe o menor entre os 120 s dele
   e o que resta do turno. Com a primeira chamada em até 30 s (todas as
   medidas ficaram abaixo de 13 s) nada muda para o gerador. Com mais do que
   isso, ou com dois planos pedidos na mesma mensagem, o gerador recebe menos
   de 120 s e pode ser cortado.
4. **Resposta de status em texto simples** (`MOBILE_FLOW_PLAIN_STATUS`,
   `flow-status-text.ts`). O caminho "status puro" (pergunta de status +
   `consulta_progresso`) devolvia ao app o card do WhatsApp com pictogramas,
   `**` e `_`. No Flow o mesmo texto sai sem essas marcas. É só formatação: o
   texto de entrada é o card pronto, então números, ordem e linhas são os
   mesmos. Três rótulos passam a ser os da tela Hoje do app: "Restam" →
   "Restam para comida", "Excedente" → "Excesso alimentar", "Bloco 7700" →
   "Bloco 7.700". "Consumido", "Proteína" e "Exercício" já eram iguais. A nota
   da linha de exercício acompanha o rótulo: "(acelera o bloco 7.700)", para a
   resposta ter uma grafia só. Nenhuma frase nova.
5. **O gerador de plano entra nos números do turno.** As chamadas de modelo
   feitas dentro das ferramentas do Flow (hoje, os geradores de cardápio e de
   treino) passam por um contador: tokens, custo e milissegundos de cada uma
   vão para `llm.flow_calls` (`generator_calls`, só números e o id do modelo)
   e somam nos totais do turno. **A partir daqui, `cost_usd`, `prompt_tokens`
   e `completion_tokens` de um turno de sugestão incluem o gerador.** O
   `cost_usd` gravado desses turnos sobe (cerca de US$ 0,04 a mais, estimado),
   embora o gasto real caia: comparar com a linha de base exige descontar o
   gerador. `model_used` continua sendo o modelo do chat. `llm.cache_usage`
   continua contando só as chamadas de chat.
6. **O turno que termina em erro também grava os números.** Antes,
   `llm.flow_calls` só existia quando o turno respondia: um turno derrubado
   pelo prazo depois de um gerador de US$ 0,04 não deixava rastro do custo.
   Agora o evento é gravado também no caminho de erro, uma vez, com
   `turn_failed: 1` e os números do que já foi gasto (chamadas de chat e do
   gerador). Uma chamada de chat que falha ou expira entra na lista com o
   tempo que levou, sem tokens e com `failed: 1`, como já acontecia com o
   gerador; `call_count` conta as tentativas, com as que falharam. Só números
   e ids de modelo: nem o texto do paciente nem a mensagem do erro. Se a
   gravação falhar, o erro do turno é o que sobe.

### Antes → depois por tipo de turno

"Antes" é a árvore com a Parte 1 aplicada; "depois" é a árvore atual. Sonda:
pipeline e ferramentas reais, banco falso, conta parecida com a de QA (49
linhas de histórico, 80% de dias anteriores). Tokens = caracteres ÷ 3,0. O
prefixo em cache (tools 4.446 car. + bloco estável 1.734 car. na sonda; 5.060
tokens na cobrança) é lido uma vez por chamada. US$ a preço de lista do Sonnet
4.6 (entrada 3, leitura de cache 0,30, saída 15 por milhão), com cache lido.
Os segundos são os da linha de base de staging; os de "depois" são estimativa
(nada foi publicado).

| Tipo de turno | Chamadas ao modelo | Tokens de entrada a preço cheio | US$ das chamadas de chat | Segundos |
|---|---|---|---|---|
| Resposta do sistema (treino × comida) | 0 → 0 | 0 → 0 | 0 → 0 | 4,3 → igual |
| Uma chamada | 1 → 1 | 2.314 → 2.326 | 0,0097 → igual | 6–7,5 → igual |
| Duas chamadas (ferramenta de leitura) | 2 → 2 | 4.723 → 4.746 | 0,0196 → 0,0197 | 10–12 → igual |
| Status (`consulta_progresso`) | 1 → 1 | 2.308 → 2.319 | 0,0097 → igual | não medido → igual |
| Sugestão de cardápio, pedido único | 2 → **1** (+ 1 do gerador, igual) | 5.170 → **2.322** | 0,028 → **0,009** | 46–56 → 8 a 12 s a menos (estimado) |
| Sugestão de treino, pedido único | 2 → **1** (+ 1 do gerador, igual) | 5.329 → **2.320** | 0,029 → **0,009** | 46 → 8 a 12 s a menos (estimado) |
| Sugestão em mensagem com outra pergunta ("Monte um cardápio pra hoje e me diga quanto falta de proteína") | 2 → 2 (+ 1 do gerador) | 5.186 → 5.208 | 0,028 → igual | igual |
| Outra pergunta + sugestão, com ferramenta nas duas iterações ("Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?"), config 2 | 2 → **3** (+ 1 do gerador) | 5.020 → **8.299** | 0,020 → **0,040** | uma chamada a mais (a que responde a proteína) |
| A mesma, config 5 | 3 → 3 (+ 1 do gerador) | 8.264 → 8.299 | 0,040 → igual | igual |
| Dois planos, uma ferramenta por iteração ("Sugira um cardápio e um treino"), config 2 | 2 → **3** (+ 2 do gerador) | 5.164 → **8.768** | 0,021 → **0,034** | uma chamada curta a mais |
| Dois planos escritos com "academia" ("Monte uma dieta e um plano pra academia"), uma ferramenta por iteração, config 2 | 2 → **3** (+ 2 do gerador) | 5.170 → **8.777** | 0,021 → **0,034** | uma chamada curta a mais |
| A mesma, config 5 | 3 → 3 (+ 2 do gerador) | 8.742 → 8.777 | 0,034 → igual | igual |
| Resposta sem nome de plano a uma oferta de dois planos ("quero os 2"), uma ferramenta por iteração, config 2 | 2 → **3** (+ 2 do gerador) | 5.122 → **8.705** | 0,021 → **0,034** | uma chamada curta a mais |
| Resposta sem nome de plano a uma oferta de cardápio + explicação ("Quero") | 2 → 2 (+ 1 do gerador) | 5.124 → 5.148 | 0,028 → igual | igual |
| Outra pergunta + sugestão, plano e depois leitura, erro do provedor na chamada de fechamento, config 2 | 2 → **3** (+ 1 do gerador; a terceira falha) | 5.196 → **8.474** enviados | 0,021 → 0,021 se o provedor não cobra a chamada que falhou, **0,032** se cobra a entrada dela | a espera da chamada que falhou |
| Leitura, leitura, plano ("Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?"), config 5 | 4 → **3** (gerador: 1 → **0**) | 11.148 → **7.844** | 0,051 → **0,032** | o plano não é gerado no turno (RC PERF-C15) |
| Config de produção (5), modelo pede ferramenta sempre | 5 → **3** (2 com ferramenta + fechamento) | 12.510 → **7.259** | 0,051 → **0,030** | cerca de 3–5 s a menos por chamada que saiu |

Os 11 tokens a mais por chamada nas linhas sem mudança de número de chamadas
são a frase da anti-repetição (34 caracteres), da correção descrita na
Parte 1. Nas linhas de sugestão, os US$ supõem 80 tokens de saída numa
chamada de ferramenta ou numa resposta curta e 555 na resposta que copia a
sugestão (a linha de base mediu de 502 a 608). Nas linhas que passam de 2
para 3 chamadas o turno fica mais caro do que na árvore anterior. Na primeira
("…E quanto falta de proteína hoje?"), é a chamada que responde a pergunta
que antes ficava sem resposta (o commit anterior, com config 2, também a
perdia, e gastava ~13.093 tokens a preço cheio nas duas chamadas). Nas de
dois planos ("Sugira um cardápio e um treino", "Monte uma dieta e um plano
pra academia", "quero os 2"), a resposta é a mesma do commit anterior, que
gastava ~13.238, ~13.244 e ~13.120 tokens em duas chamadas; na rodada
anterior desta mudança as duas últimas paravam depois de **uma** chamada
(~2.323 e ~2.299 tokens), só com o cardápio, e é esse erro que a terceira
chamada desfaz. A resposta "Quero" a uma oferta de cardápio + explicação
também parava em uma chamada (~2.300 tokens) sem a explicação; agora faz as
duas (~5.148), como o commit anterior (~13.126). Na linha do erro do
provedor, o commit anterior com config 2 entregava a sugestão em duas
chamadas e com config 5 falhava depois de três; agora responde com a
sugestão nos dois casos. Na linha de leitura, leitura e plano o turno fica
mais barato porque deixa de fazer o que foi pedido: com o modelo roteirizado
termina sem texto (RC PERF-C15). A linha da config 5 com ferramenta sempre é
o pior caso: o modelo roteirizado pede ferramenta até na chamada de
fechamento, e o turno termina sem texto (RC PERF-C8). Com um modelo que
responde na chamada de fechamento são as mesmas 3 chamadas, com texto.

- Na sugestão, a segunda chamada também lia o prefixo em cache de novo (5.060
  tokens a 10%) e escrevia a cópia da sugestão: 502 a 608 tokens de saída na
  linha de base, a parte mais lenta dessa chamada. Com o prompt da linha de
  base (sem a Parte 1) a economia por turno de sugestão seria de cerca de
  US$ 0,03.
- Passos aguardados no banco dentro do agente: iguais antes e depois (14 na
  resposta do sistema, 17 com uma chamada, 19 com duas, 22 no status, 27 no
  cardápio, 25 no treino). O turno de sugestão que o modelo parafraseava
  gravava um evento a mais (`llm.plan_suggestion_rewritten`); o turno direto
  não grava.
- Espera no pior caso. Antes: uma chamada de chat podia levar 181 s (90 s + 1
  nova tentativa) e o turno não tinha limite; passando de 300 s a função
  morria e o turno ficava "processing", respondendo 409 por até 10 minutos.
  Depois: 45 s por tentativa de chat, 150 s de trabalho de modelo, 165 s no
  serviço; o erro chega ao app antes dos 180 s dele, com "tentar de novo"
  funcionando.
- Diferencial fora do repositório: os mesmos 24 turnos da Parte 1 rodados na
  árvore de antes e na atual. WhatsApp: 30 chamadas ao modelo, saídas e
  consultas ao banco idênticas ao commit `7062816`. Flow: em 28 chamadas a
  única diferença do pedido são os dois argumentos de tempo
  (`requestTimeoutMs`, `maxRetries`); muda a saída só do turno de status
  (formatação) e do turno com três rodadas de ferramenta (o teto). Esse
  diferencial é anterior à correção pós-revisão (mensagem mista, chamada de
  fechamento, janela por dia, frase da anti-repetição) e não foi refeito; o
  que a correção mudou está travado nos goldens e nos dois locks do WhatsApp.

### Como conferir em staging

```sql
select occurred_at,
       properties->>'call_count' as chamadas_chat,
       properties->>'plan_suggestion_direct' as sugestao_direta,
       g->>'model' as modelo_gerador, g->>'prompt_tokens' as entrada_gerador,
       g->>'completion_tokens' as saida_gerador, g->>'cost_usd' as custo_gerador,
       g->>'ms' as ms_gerador, g->>'failed' as falhou
from product_events
left join lateral jsonb_array_elements(properties->'generator_calls') g on true
where event = 'llm.flow_calls'
order by occurred_at desc;
```

Esperado num turno de sugestão com pedido único (as condições do item 1: só
palavras da lista fechada, sem "?", um plano só, uma oração só, o plano
escrito na mensagem): `chamadas_chat` = 1, `sugestao_direta` = 1 e uma
linha do gerador (duas se o primeiro cardápio foi recusado). Em `messages`,
`prompt_tokens` perto de 7.400 + gerador (era ~22.000 sem o gerador). Em
qualquer outro pedido de sugestão, `chamadas_chat` = 2 e `sugestao_direta`
vazio.

Antes de liberar para o Roberto, rodar em staging, com o modelo real:

1. Um turno que encadeie duas ferramentas (por exemplo "Como foi minha
   semana? E monte um cardápio para hoje."): conferir `chamadas_chat` = 3,
   `closing` = 1 na terceira chamada e texto na resposta (RC PERF-C8). Se a
   terceira chamada vier com `failed` = 1, o provedor está recusando
   `tool_choice: none`: o turno responde só com a sugestão gravada e a outra
   pergunta fica sem resposta em todo turno desse formato.
2. "Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína
   hoje?": ver quantas ferramentas o modelo real chama antes do plano. Se
   forem duas leituras antes de `propoe_plano_dieta` (a sequência
   `consulta_progresso`, `consulta_metricas`, `propoe_plano_dieta` da
   terceira revisão), o plano não é gerado no turno: conferir que
   `chamadas_chat` = 3, que não há linha de gerador nem rascunho novo, e
   **ler o que o modelo escreveu** na chamada de fechamento (RC PERF-C15).
3. Um pedido de dois planos ("Monte uma dieta e um plano pra academia"): ver
   se o modelo real chama as duas ferramentas na mesma chamada (2 chamadas)
   ou uma por iteração (3 chamadas, a terceira com `closing` = 1), e conferir
   os dois rascunhos e as duas sugestões na resposta.
4. Uma resposta curta a uma oferta do Flow ("Quero", "quero os 2"): conferir
   `sugestao_direta` vazio e a resposta inteira.

Outros campos do evento, sempre números:
`properties->>'plan_suggestion_at_deadline'` (o prazo encerrou o turno com uma
sugestão já gravada), `properties->>'turn_failed'` (o turno terminou em erro)
e, em cada item de `calls`, `closing` (chamada de fechamento) e `failed`
(chamada que falhou ou expirou). Um evento sem `turn_failed` cuja última
chamada tem `closing` e `failed` é o turno que respondeu com a sugestão
gravada depois de um erro do provedor na chamada de fechamento.

No log da função, um turno encerrado pelo prazo aparece como
`[mobile-flow] turn_failed` com `internal_code` `flow turn deadline exceeded`
(agente) ou `flow turn time limit exceeded` (serviço). O código do agente vale
para os dois jeitos de o prazo vencer: antes de uma chamada começar, e no meio
de uma chamada (o agente troca o "Request timed out." do SDK pelo erro de
prazo quando a chamada falha com até 0,25 s do prazo; o erro do SDK fica como
`cause`). Uma chamada que expira nos seus próprios 45 s com prazo sobrando
continua aparecendo como timeout do provedor (`APIConnectionTimeoutError`,
`internal_code` nulo), porque é isso que ela é. Um turno que o prazo encerra
com sugestão gravada não aparece nesse log: ele responde.

### Como reverter (uma linha cada)

Em `packages/agent/src/pipeline.ts`:

- Sugestão direta: `MOBILE_FLOW_DIRECT_PLAN_SUGGESTION = false`.
- Teto de iterações: `MOBILE_FLOW_MAX_MODEL_ITERATIONS = Number.POSITIVE_INFINITY`.
- Chamada de fechamento: `MOBILE_FLOW_CLOSING_CALL = false` (o turno volta a
  terminar sem texto quando o modelo gasta as iterações em ferramentas).
- Limites de tempo do agente: `MOBILE_FLOW_TIME_LIMITS = false` (somem também
  a resposta com a sugestão gravada no fim do prazo e o erro de prazo).
- Status em texto simples: `MOBILE_FLOW_PLAIN_STATUS = false`.
- Gerador nos números do turno: apagar a linha
  `llm: flowToolLlm(deps.llm, flowDeadlineAt, flowToolLlmCalls),` (as
  ferramentas voltam a receber o cliente direto; some também o limite do
  gerador pelo prazo do turno).

Em `apps/admin/src/lib/mobile-api/flow-chat-service.ts`:

- Trava do serviço: `FLOW_TURN_HARD_LIMIT_MS = null`.

Os goldens desta parte travam os valores novos e precisam acompanhar a
reversão.

### Testes

- `packages/agent/src/__golden__/audit-10-04-flow-turn-calls.test.ts`
  (312 testes), pipeline e ferramentas reais com modelo roteirizado:
  - "Sugira um cardápio completo para hoje" (frase exata do turno de 10-04
    10:32) e "Pode ser equilibrado no geral." (frase e argumentos exatos do
    turno de treino do aparelho, 30/09): uma chamada ao modelo, o texto fixo
    com a sugestão gravada, rascunho gravado uma vez, mesmos eventos de antes;
    um rascunho já gravado pelo mesmo turno é mostrado de novo sem gravar
    outro;
  - mensagem com outra pergunta, com as frases exatas da primeira revisão:
    "Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína
    hoje?", "Monta meu treino de 3 dias na academia, sou iniciante. Posso
    treinar perna com dor no joelho?" e "Sugira um cardápio completo para hoje
    e me diga quanto de proteína ainda falta hoje?": duas chamadas, e a
    resposta traz a sugestão inteira e a resposta à outra pergunta. Também: o
    modelo que escreve texto junto da chamada da ferramenta (duas chamadas, e
    a segunda lê esse texto) e a segunda chamada que parafraseia (texto
    gravado, como antes);
  - segundo pedido na mesma frase, com as frases exatas da segunda revisão,
    cada uma com config 2 e 5: "Monte um cardápio pra hoje, quanto falta de
    proteína hoje", "Quanto falta de proteína hoje, e monta um cardápio pra
    hoje", "monta um cardapio pra hj tb quero saber quanto de proteina falta",
    "Monte um cardápio pra hoje e me diga quanto falta de proteína" e "Please
    suggest a full menu for today and tell me how much protein I have left":
    duas chamadas, a sugestão inteira e a outra resposta. "Monta meu treino de
    3 dias na academia e me diz se posso treinar perna com dor no joelho" (a
    antiga pendência): duas chamadas, o joelho respondido. "Sugira um cardápio
    e um treino" com uma ferramenta por iteração (config 2 e 5): dois
    rascunhos, as duas sugestões no texto, três chamadas. As variantes simples
    com saudação e agradecimento: uma chamada. A tabela da regra de pedido
    único (106 mensagens), a lista fechada, palavra por palavra, e a
    lista das respostas exatas (uma frase). "Monte um cardápio para hoje e
    outro para amanhã" (a antiga RC PERF-C10), config 2 e 5: duas chamadas e
    a resposta do modelo sobre o outro cardápio;
  - terceira revisão, com as frases exatas e uma ferramenta por iteração,
    config 2 e 5: "Monte uma dieta e um plano pra academia", "Quero um
    cardápio e um plano de academia" e "quero dieta e academia": dois
    rascunhos, as duas sugestões no texto, a chamada de fechamento com
    `tool_choice: none`. Depois da linha do Flow "Posso montar: 1) um
    cardápio para hoje; 2) um treino para a semana. Qual você prefere?", as
    respostas "quero os 2", "1 e 2" e "faz os 2": dois rascunhos e as duas
    sugestões. Depois de "Posso montar um cardápio para amanhã e também te
    explicar como bater a proteína de hoje. Quer?", as respostas "Quero",
    "pode", "Pode ser", "manda", "Quero, por favor", "sim" e "Sim, quero":
    duas chamadas e a explicação na resposta. "Monta meu treino de 3 dias na
    academia" e "Quero o treino" depois da oferta de dois planos: uma
    chamada. As duas pendências de RC PERF-C10 travadas: "Monte um cardápio
    pra hoje pra semana" e "Pode ser equilibrado no geral." depois de uma
    linha do Flow que oferece cardápio e treino (uma chamada, só a primeira
    sugestão);
  - sugestão gravada e outra pergunta, com ferramenta nas duas iterações, os
    três turnos da segunda revisão com config 2, 3 e 5: "Monte uma sugestão de
    cardápio para amanhã. E quanto falta de proteína hoje?" (leitura e depois
    plano; plano e depois leitura) e "Como foi minha semana? E monte um
    cardápio para hoje.": 3 chamadas, a terceira com `tool_choice: none`, a
    sugestão inteira e a resposta à outra pergunta. O pedido único com a
    mesma sequência de ferramentas continua com 2 chamadas; o fechamento que
    parafraseia vira o texto gravado; com menos de 12 s de prazo a sugestão é
    a resposta; o WhatsApp nunca recebe a chamada;
  - o modelo continua respondendo em: limite de 24 h, gerador que falha,
    argumentos recusados, outra ferramenta no turno, sugestão sem texto,
    repetição de guarda antes; no WhatsApp a ferramenta nem existe;
  - teto e fechamento: com config 5, 12, 2, 1 ou sem config, o Flow faz no
    máximo 2 iterações com ferramenta e depois a chamada de fechamento; o
    WhatsApp faz o número configurado e nunca recebe `tool_choice`; a
    repetição de guarda ainda ganha a sua iteração. Os três turnos da revisão
    ("Qual e o meu gasto diario, e como foi minha semana?", "Como foi minha
    semana comparada com hoje?", "Como foi minha semana e qual minha taxa
    basal?"), com config 5, 3 e 2: ferramenta, ferramenta, resposta — 3
    chamadas, texto presente, a terceira com `tool_choice: none` e as mesmas 6
    ferramentas no pedido. A resposta de fechamento passa pelas guardas; no
    pedido único com sugestão gravada não há fechamento; com o prazo vencido
    não há fechamento e o turno falha como prazo. As três pendências de RC
    PERF-C8 travadas: fechamento respondido só com ferramenta (texto vazio);
    repetição de guarda depois do fechamento com as ferramentas ligadas; e
    "Como foi minha semana e qual minha taxa basal?" com o provedor
    recusando a chamada de fechamento, sem sugestão gravada (o turno falha,
    evento gravado com `turn_failed` e a terceira chamada `closing` e
    `failed`);
  - erro do provedor na chamada de fechamento com sugestão gravada, o turno
    exato da terceira revisão, config 2 e 5: "Monte uma sugestão de cardápio
    para amanhã. E quanto falta de proteína hoje?", `propoe_plano_dieta`,
    `consulta_progresso`, e a chamada de fechamento respondida com "500
    upstream": a resposta é a sugestão gravada com o texto fixo, um evento
    `llm.flow_calls` sem `turn_failed` com a terceira chamada `closing` e
    `failed`, nenhum `llm.plan_suggestion_rewritten`, e o texto do erro em
    lugar nenhum. Com duas sugestões gravadas as duas são entregues. A
    pendência de RC PERF-C13 travada (a proteína fica sem resposta) e a de RC
    PERF-C15, com a sequência exata (`consulta_progresso`,
    `consulta_metricas`, `propoe_plano_dieta`), config 2 e 5: 3 chamadas,
    nenhum rascunho, texto vazio;
  - tempo: 45 s e 1 nova tentativa por chamada de chat; a segunda chamada
    nunca recebe mais do que resta; com o prazo vencido nenhuma chamada é
    feita e o turno falha; a chamada cortada pelo prazo falha como prazo, e a
    que expira com prazo sobrando falha como timeout do provedor; o gerador
    fica com 120 s enquanto o turno os tem e com menos quando não tem; o
    WhatsApp não recebe nenhum dos dois argumentos e as ferramentas dele
    recebem o cliente intacto;
  - prazo com rascunho gravado, cenários da revisão: plano + ferramenta de
    leitura com primeira chamada de 30 s e gerador de 119 s (nenhuma segunda
    chamada, a sugestão gravada é a resposta); a segunda chamada cortada pelo
    prazo (idem); dois planos numa chamada com primeira chamada de 20 s e 70 s
    por gerador (o cardápio gravado é entregue, o gerador de treino cortado
    aparece nos números); o piso de 12 s;
  - gerador: totais do turno = chat + gerador; `llm.flow_calls` com
    `generator_calls` só com números; tentativa recusada e chamada que falha
    também contam; turno sem gerador tem o evento de antes;
  - turno que falha: o evento é gravado uma vez, com `turn_failed`, a chamada
    que falhou e o custo do gerador já pago, sem texto; o WhatsApp não grava
    nada disso;
  - janela: a alergia dita no mesmo dia, e a dita antes da meia-noite numa
    sessão que a atravessa, chegam ao gerador (ver Parte 1);
  - pendências: cada entrada RC dos cabeçalhos dos quatro arquivos de teste
    do Flow — a linha e a explicação que vem depois dela, lidas como um texto
    só, qualquer que seja a largura das linhas — está neste documento,
    caractere por caractere, e vice-versa (32 entradas nos cabeçalhos, 30
    aqui);
  - status: a frase do app "Como está meu dia até agora?" no WhatsApp (card
    byte a byte) e no Flow (mesmos dígitos, na mesma ordem, sem pictograma e
    sem Markdown); recomposição com excedente e treino, com "7.700" nas duas
    linhas do bloco; a linha de comida continua sendo meta − consumido, sem
    exercício; os rótulos são lidos do catálogo de textos do app.
- `apps/admin/src/lib/mobile-api/flow-chat-service.turn-limit.test.ts` (10
  testes): agente que nunca responde falha o turno aos 165 s com 502
  `flow_provider_failed` e a mensagem do paciente em `failed`; o limite conta
  do início do turno; resposta dentro do limite é entregue sem deixar
  temporizador; resposta ou erro que chega depois não grava nada; o app ainda
  espera 180 s e a rota ainda permite 300 s (lidos dos arquivos).
- `packages/agent/src/pipeline-mobile-flow-runtime.test.ts`, bloco "audit
  09-30": os dois testes que travavam a segunda chamada do turno de sugestão
  pura foram ajustados. O turno do aparelho agora trava "uma chamada, texto
  gravado"; a troca do resumo genérico e a cópia fiel sem repetição de guarda
  continuam travadas num turno em que o modelo ainda escreve (com uma
  ferramenta de leitura junto).
- `audit-10-04-flow-prompt-budget.test.ts`: a lista de argumentos de uma
  chamada do Flow ganhou `requestTimeoutMs` e `maxRetries`; os testes da
  janela e do evento do turno que falha estão descritos na Parte 1.
- `audit-10-04-whatsapp-request-lock.test.ts` e
  `audit-10-04-whatsapp-context-lock.test.ts`: verdes. O fixture, o hash e o
  código de teste do primeiro não mudaram (só a frase do cabeçalho sobre o que
  ele pega, numa rodada anterior); o segundo não foi editado. Cada mudança desta parte foi vazada de
  propósito para o WhatsApp e pelo menos um teste quebrou em cada caso: o
  tempo e a frase da anti-repetição quebram o lock de pedido; o teto, o
  status, o cliente das ferramentas e a chamada de fechamento quebram
  `audit-10-04-flow-turn-calls.test.ts`.

### O que não foi feito nesta parte, e por quê

- **Pôr o histórico em cache** (reordenar o prompt): muda a posição do
  contexto do turno e pode mudar respostas; precisa dos goldens do Flow e de
  uma rodada no iPhone. Rende cerca de US$ 0,01 por chamada com o prompt da
  linha de base, menos depois da Parte 1.
- **TTL do cache (1 h × 5 min)**: decisão que depende dos intervalos reais
  entre mensagens dos pacientes; `llm.flow_calls` precisa de uma semana.
- **Mandar mais turnos para um modelo menor**: risco alto para a regra comida
  × bloco e ganho pequeno com o cache do Haiku frio. Só com avaliação do Flow
  nos dois modelos. Decisão do dono.
- **Gerar o plano fora da resposta do chat**: é o que tira os 25–90 s do
  gerador, mas muda o contrato da API e o app (estado "gerando", aviso,
  falha). Decisão do dono.
- **Streaming**: o provedor só tem `complete()`, a rota exige corpo JSON e as
  guardas reescrevem o texto depois de pronto; mostrar tokens mostraria texto
  que depois muda.
- **Novas respostas prontas do sistema** (estado do dia, proteína): texto novo
  para o paciente; precisa do aval do Roberto e de revisão em rodadas.
- **`max_tokens`**: é teto, não alvo; baixar não economiza e pode cortar texto.

### Pendências da Parte 2

> RC PERF-C1 — cenário saída REAL do gerador e argumentos REAIS da ferramenta no turno de cardápio de 10-04 10:32 NÃO coberto nesta PR (pendência da audit 2026-10-04). A frase é a exata. A saída do gerador não foi guardada: o fixture reproduz os totais lidos no aparelho (2.884 kcal, 152,3 g), não os alimentos. Os argumentos da ferramenta também não foram registrados: o golden usa o horizonte diário (`daily`).

> RC PERF-C2 — cenário turno de TREINO do baseline de 10-04 09:21 (21.750 tokens, 46,3 s) NÃO coberto nesta PR (pendência da audit 2026-10-04). O texto do paciente desse turno não foi registrado. O turno de treino coberto é o do aparelho de 30/09 15:56Z, com a frase e os argumentos exatos e o rascunho real gravado (956b82be…).

> RC PERF-C3 — cenário resposta de sugestão SEM a frase livre de abertura do modelo, vista pelo paciente, NÃO coberto nesta PR (pendência da audit 2026-10-04). Nos turnos de pedido único o paciente vê sempre a abertura fixa. Precisa do aval do Eduardo e de uma rodada no iPhone.

> RC PERF-C4 — cenário chamada de chat real acima de 45 s NÃO coberto nesta PR (pendência da audit 2026-10-04). Nenhuma foi observada (o maior turno de uma chamada levou 12,6 s), mas o limite não foi medido contra a distribuição real. `llm.flow_calls` traz `ms` por chamada.

> RC PERF-C5 — cenário card escrito pelo MODELO no Flow (troca pós-laço pelo card canônico, com pictogramas e negrito) NÃO coberto nesta PR (pendência da audit 2026-10-04). Só a resposta do caminho "status puro" sai em texto simples.

> RC PERF-C6 — cenário paciente do app em INGLÊS perguntando o status NÃO coberto nesta PR (pendência da audit 2026-10-04). O card é em português para todos os idiomas, como já era.

> RC PERF-C12 — cenário paciente do app em INGLÊS cuja sugestão o modelo parafraseia, ou cujo turno o prazo ou um erro na chamada de fechamento encerra, NÃO coberto nesta PR (pendência da audit 2026-10-04). Nesses casos a resposta é o texto fixo, com a abertura e o fecho em português para todos, e o botão do app em inglês se chama "Review suggestion", não "Revisar sugestão". Já era assim antes desta mudança. Nenhuma frase nova podia entrar; uma versão em inglês da moldura precisa de aval. A paráfrase está travada como pendência no golden. O pedido em inglês ("Please suggest a full menu for today") está fora da lista fechada: faz a segunda chamada e fica com a moldura que o modelo escreve, como antes (travado no golden).

> RC PERF-C7 — cenário tokens COBRADOS por uma chamada que falhou ou expirou, e turno encerrado pela trava de 165 s do serviço ou pela plataforma, NÃO coberto nesta PR (pendência da audit 2026-10-04). O turno que termina em erro grava `llm.flow_calls` com o que já gastou, mas a chamada que falhou entra só com o tempo (o provedor não devolve os tokens de uma chamada cortada). Quando é o serviço que encerra o turno aos 165 s, o agente continua rodando e grava o evento ao terminar, se a função ainda estiver viva; se a plataforma matou a função, nada é gravado.

> RC PERF-C8 — cenário chamada de fechamento com MODELO REAL, repetição de guarda DEPOIS dela (as ferramentas voltam a estar ligadas) e erro do provedor NA chamada de fechamento SEM sugestão gravada (o turno falha) NÃO coberto nesta PR (pendência da audit 2026-10-04). Não há chave de modelo local: não foi verificado como o provedor trata `tool_choice: none` com as ferramentas no pedido, nem a qualidade dessa resposta. Três casos travados como pendência no golden: (a) sem sugestão gravada, o modelo ainda devolve só uma chamada de ferramenta, ou texto vazio, na chamada de fechamento: o turno termina sem texto e o serviço devolve 502 depois de três chamadas pagas; (b) uma guarda recusa a resposta de fechamento: a repetição de guarda é feita com as ferramentas ligadas de novo, e se o modelo voltar a pedir ferramenta o turno termina sem texto depois de quatro chamadas (a chamada de fechamento é uma só por turno); (c) o provedor responde erro na chamada de fechamento e não há sugestão gravada: o turno falha com 502 e `llm.flow_calls` é gravado com `turn_failed` (onde a config permite 3 ou mais, o commit anterior respondia na terceira chamada, com as ferramentas ligadas). Com uma sugestão gravada o erro do provedor no fechamento não derruba o turno: a resposta é a sugestão gravada, sem a resposta à outra pergunta (RC PERF-C13); se o provedor recusar `tool_choice: none` sempre, é isso que acontece em todo turno desse formato. Com o prazo vencido a chamada não é feita.

> RC PERF-C10 — cenário dois pedidos do MESMO tipo numa oração só, sem "e", sem pontuação, sem pronome e sem repetir o nome do plano ("Monte um cardápio pra hoje pra semana"), e a resposta exata "Pode ser equilibrado no geral." depois de uma linha do Flow que ofereceu duas coisas, NÃO coberto nesta PR (pendência da audit 2026-10-04). A regra de pedido único lê palavras, não sentido. (1) A primeira mensagem conta como um pedido: se o modelo chamar a ferramenta uma vez, o turno termina nessa sugestão, sem uma palavra sobre a outra. (2) A frase exata do turno de treino do aparelho fica no caminho de uma chamada sem citar o plano; se a linha anterior do Flow ofereceu cardápio e treino e o modelo chama uma ferramenta por iteração, o turno termina na primeira sugestão. Os dois casos estão travados como pendência no golden. Está coberto, com a segunda chamada (ou a de fechamento): cardápio e treino na mesma mensagem, inclusive "plano pra academia" e "dieta e academia"; dois pedidos ligados por "e", vírgula ou outra pontuação ("Monte um cardápio para hoje e outro para amanhã"); "outro", "um", "o" ou "os 2" no lugar do nome do plano; "hoje" e "amanhã" juntos; a resposta que não cita o plano ("Quero", "pode", "Pode ser", "manda", "quero os 2", "1 e 2", "faz os 2"); e qualquer palavra fora da lista.

> RC PERF-C11 — cenário mensagem com outra pergunta em que o modelo PARAFRASEIA a sugestão na segunda chamada NÃO coberto nesta PR (pendência da audit 2026-10-04). A resposta vira o texto fixo com a sugestão gravada e a frase do modelo sobre a outra pergunta vai embora junto, como já era antes desta mudança. A outra pergunta só é respondida quando o modelo copia a sugestão palavra por palavra. Vale também para a chamada de fechamento (travado no golden).

> RC PERF-C13 — cenário turno que o PRAZO, ou um erro do provedor na chamada de fechamento, encerra com uma sugestão gravada e algo mais pedido NÃO coberto nesta PR (pendência da audit 2026-10-04). A resposta é a sugestão gravada com o texto fixo: não diz que o segundo plano não foi criado (dois planos na mesma mensagem) nem responde a outra pergunta. Nenhuma frase nova podia entrar nesta mudança. Travado no golden: no prazo o evento traz `plan_suggestion_at_deadline`; no erro do fechamento, a terceira chamada com `closing` e `failed`.

> RC PERF-C14 — cenário frequência REAL do caminho de uma chamada só NÃO coberto nesta PR (pendência da audit 2026-10-04). Só fica com uma chamada o pedido simples, único e explícito: escrito inteiro com palavras da lista fechada, sem "?", numa oração só, citando um plano só, e sem texto do modelo junto da chamada da ferramenta. Ficam com duas: o pedido escrito como pergunta ("Pode montar um cardápio para hoje?"), em inglês, com abreviação, com erro de digitação, com "e", com um número que não conta dias ou vezes ou com qualquer palavra fora da lista, e a resposta curta que não cita o plano. Não se sabe quantos turnos de sugestão caem em cada caso; `plan_suggestion_direct` mede em staging.

> RC PERF-C15 — cenário plano que o modelo só pede na TERCEIRA iteração (leitura, leitura, plano) NÃO coberto nesta PR (pendência da audit 2026-10-04). O teto é de 2 iterações com ferramenta e a chamada de fechamento vem com as ferramentas desligadas: a ferramenta de plano que o modelo pede nela não é executada e nenhum rascunho é gravado no turno. Travado como pendência no golden com a sequência exata da terceira revisão ("Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?", com `consulta_progresso`, `consulta_metricas`, `propoe_plano_dieta`), config 2 e 5: 3 chamadas, nenhum rascunho. O que o paciente lê depende do que o modelo real escreve sem a ferramenta (não medido); com o modelo roteirizado o texto sai vazio (502 no serviço). O commit anterior com config 5 fazia 4 chamadas e entregava a sugestão e a resposta; com a config 2 de staging terminava em 2 chamadas, sem rascunho e sem texto. A sequência está na lista do que rodar em staging.

> RC PERF-C9 — cenário ordem das linhas da resposta de status NÃO coberto nesta PR (pendência da audit 2026-10-04). A troca de card pós-laço põe a linha "Sequência" antes do card, no WhatsApp e no Flow. O Flow repete a ordem do WhatsApp; corrigir a ordem mexe no WhatsApp.

> RC PERF-C16 — cenário pergunta de sim ou não, ou pedido de reenvio, escrita SEM "?" só com palavras da lista ("Dá pra fazer o treino de hoje em casa", "pode treino hoje", "Preciso fazer dieta", "hoje faz treino", "Pode fazer treino em casa", "me passa o treino de hoje") NÃO coberto nesta PR (pendência da audit 2026-10-04). A regra de pedido único lê palavras, não sentido: a mensagem conta como pedido único. Se o modelo responder só com a ferramenta de plano, sem texto, o turno termina na sugestão com o texto fixo, sem o sim ou não (no commit anterior a segunda chamada respondia). Com texto do modelo junto da ferramenta o turno faz a segunda chamada. Medido pela quarta revisão de 04/10 (sonda Q-nomark); sem golden.

> RC PERF-C17 — cenário guarda que RECUSA a resposta da chamada de fechamento seguida de erro do provedor na repetição de guarda, com sugestão gravada NÃO coberto nesta PR (pendência da audit 2026-10-04). A saída que responde com a sugestão gravada vale só para a própria chamada de fechamento. Nessa falha dupla o turno falha com 502, `llm.flow_calls` é gravado com `turn_failed`, o rascunho fica pendente e nada chega ao chat ("Monte uma sugestão de cardápio para amanhã. E quanto falta de proteína hoje?": propoe_plano_dieta, consulta_progresso, fechamento recusado pela guarda de bloco, repetição com erro 500). Com a config 2 o commit anterior entregava a sugestão; com a config 5 falhava do mesmo jeito. A correção de uma condição foi testada em cópia pela quarta revisão de 04/10 (sonda G1); sem golden nesta PR.

> RC PERF-T1 — cenário função encerrada pela plataforma ANTES do limite (queda de instância, deploy no meio do turno) NÃO coberto nesta PR (pendência da audit 2026-10-04). O turno ainda fica "processing" até o lease; o limite só age enquanto a função vive.

> RC PERF-T2 — cenário leituras do banco ANTES do agente travadas (autenticação, idempotência, as quatro leituras iniciais) NÃO coberto nesta PR (pendência da audit 2026-10-04). O limite conta desde o início do turno, mas só interrompe a espera pelo agente.

> RC PERF-T4 — cenário chamada de chat com 429 e `Retry-After` do provedor NÃO coberto nesta PR (pendência da audit 2026-10-04). A espera do SDK entre as duas tentativas (até 60 s) não entra na conta do prazo: uma chamada pode durar até 150 s e terminar depois dos 150 s do turno. Medido na revisão com o SDK real e tempo virtual: 429 com `Retry-After: 55` e segunda tentativa pendurada só falha aos 100 s. Quem encerra o turno é a trava de 165 s do serviço, com o agente ainda rodando (RC PERF-T3). No golden o modelo é roteirizado: sem SDK.

> RC PERF-T3 — cenário agente que continua rodando DEPOIS que o serviço encerrou o turno NÃO coberto nesta PR (pendência da audit 2026-10-04). A resposta atrasada é descartada (travado em teste); uma ferramenta em andamento ainda pode gravar um rascunho, que a nova tentativa do mesmo turno reaproveita pela chave do turno.
