# Regras de cálculo do Agente MPP — fonte de verdade

> Este documento é a **referência canônica** de COMO o agente calcula tudo.
> Toda regra aqui deve estar **travada por teste**. Se mudar uma regra, mude:
> (1) o código, (2) o teste que a trava, (3) este documento — na mesma PR.
> Nunca mude uma fórmula "no susto" por um print de paciente sem checar aqui.

Última revisão: 2026-10-04.

---

## 1. Meta calórica diária (`calories_target`)

- **Recomposição:** `meta = BMR × 1.2 − design_deficit`.
  - `design_deficit` (fome do paciente): leve 400 / médio 500 / alto 600.
  - O TDEE é **apenas informativo** na recomp — NÃO é a meta.
- Manutenção / ganho: conforme `calc_config` do protocolo.
- Código: `packages/agent/src/calc-targets.ts`, `calc-config-loader.ts`.

## 2. Balanço do dia — DOIS números distintos (NÃO confundir)

Esta é a regra que mais gerou bug. Existem **dois** balanços, com finalidades diferentes:

### 2a. Balanço de COMIDA (o que o paciente vê no card como "Restam/Excedente")
```
balanço_comida = consumido − meta
```
- **O EXERCÍCIO NÃO ENTRA AQUI.** (Regra Roberto 2026-05-21.)
- `< 0` → "🎯 Restam: X kcal" (ainda dá pra comer X pra bater a meta).
- `> 0` → "🎯 Excedente: X kcal" (comeu X acima da meta de ingestão).
- Queimar no treino **NÃO libera comer mais** — não soma no "Restam".
- Código: `packages/agent/src/balance-card.ts` (linha "🎯 Restam/Excedente").
- Teste: `balance-card.test.ts` ("REGRA MPP ... Restam = meta − consumido").

### 2b. Balanço NET / déficit do dia (alimenta o BLOCO 7700)
```
daily_balance = consumido − meta − exercício
```
- O exercício **conta aqui** (vira déficit que acelera a perda de gordura).
- É o número usado pelo `daily-closer` pra creditar o bloco.
- Roberto confirmou: déficit do dia = `design_deficit − excedente_comida + exercício`.
  Ex. 19/05: `500 − 233 + 565 = 832`.
- ⚠️ `daily_snapshots.daily_balance` é **COLUNA GERADA** (`= consumido − meta −
  exercício`). NÃO dá pra setar via UPDATE/PATCH (erro 428C9). Ao corrigir
  `calories_consumed`, o banco recalcula o `daily_balance` sozinho.
- Invariante: `calories_consumed` deve ser sempre `= SUM(meal_logs.kcal)` do dia
  (a auditoria alerta se divergir >50). Backfill manual: corrigir consumed/
  protein/carbs/fat = SUM(meal_logs); daily_balance segue automático.

> Regra de ouro: **comida = sem exercício; bloco = com exercício.** O card mostra
> "Restam" (comida) + linha "🏃🏻 Exercício (acelera o bloco)" separada.

## 3. Bloco 7700 (`user_progress.deficit_block`)

1 kg de gordura = 7700 kcal. O bloco acumula o déficit creditado por dia.

**MODELO LÍQUIDO (Roberto 2026-05-28):** o cofrinho é **líquido** — dia bom
soma, dia ruim **subtrai**. Pra perder 1 kg de fato, precisa de déficit
*líquido* de 7700 kcal (não só "somar os dias bons"). Um dia de superávit
re-armazena energia → tem que descontar do progresso.

Crédito por dia (fonte única: `@mpp/core/engine/bloco` `creditDayToBloco`):
```
newDeficit = designDeficit_efetivo − daily_balance   ← pode ser NEGATIVO
```
- `designDeficit_efetivo = designDeficit` se o dia credita; senão 0.
- Ex dia bom: dd 500, balance −343 → +843 no bloco.
- Ex excedente leve: dd 500, balance +357 → +143 no bloco.
- Ex dia ruim (excedente > dd): dd 500, balance +1000 → **−500** no bloco.
- `deficit_block = max(0, soma) % 7700`; `blocks_completed = floor(max(0, soma) / 7700)`.
- **O cofrinho do paciente nunca fica negativo** (clamp em 0 no total). Se
  uma sequência de dias ruins zerar o cofrinho, recomeça do zero pro próximo.
- **Inteiros**: o acumulado total é sempre `Math.round`ado antes do clamp em
  `computeProgress` (audit 06-26) e dentro de `accumulateBloco`. Isso impede
  drift FP em séries longas (~30 dias) — em prod `dayCredit` costuma ser
  inteiro porque vem de `calories_consumed - calories_target - exercise`,
  todos integers no banco, então o impacto real é ~0. Round é defesa.
- **NaN/Infinity** em `dayCredit` (snapshot corrompido / divisão por zero
  em `creditDayToBloco`) → `computeProgress` clampa em 0 + log warning
  (audit 06-26 review HIGH 1). Evita propagar NaN pra `deficit_block`.
- Código: `packages/core/src/engine/bloco.ts`. Chamado por `computeProgress`,
  `daily-closer.ts` e `bloco-recompute.ts`.
- Recálculo do zero (auditoria/backfill): `lib/bloco-recompute.ts`.

### Quando um dia CREDITA o bloco (regras de integridade)
- **Sem atividade** (0 refeição E 0 treino) → crédito **0** (`bloco7700.skipped_inactive_day`).
- **Incomplete (gap aberto no fechamento)** → crédito **0**. Decisão Roberto
  2026-07-01: enquanto falta refeição esperada, qualquer valor parcial é
  imprevisível (`bloco7700.skipped_incomplete_day`).
- **Sub-registro (<50% da meta, exceto `user_skipped`)** → zera o `daily_balance`
  (o déficit observado é FAKE); dia *complete* credita só `design_deficit`,
  *incomplete* credita 0 (`bloco7700.skipped_subregistro`).
- **user_skipped** (paciente confirmou "pulei") → credita normal (déficit real).
- **complete ≥50%** → `design_deficit + déficit_observado`.

## 4. Card de balanço (renderizado pelo SISTEMA, não pelo LLM)

5 linhas canônicas (`renderBalanceCard`):
```
🔥 Consumido: C / meta kcal (X%)
🎯 Restam|Excedente: |consumido−meta| kcal      ← SEM exercício (§2a)
💪 Proteína: P / meta_P g (X%)
🏃🏻 Exercício: E kcal [(acelera o bloco 7700) se recomp e E>0]
📊 Bloco 7700: deficit_block / 7.700 kcal (X%)   ← recomp; senão Orçamento 14d
```
- O pipeline **substitui** qualquer card que o LLM escrever pelo card canônico
  com dados frescos do banco (`injectCanonicalCard`). O LLM nunca "calcula" o card.
- A prosa fora do card é reconciliada (`reconcileBalanceProse`) pela mesma base
  do card (comida, §2a) — rótulo e número não podem contradizer o card.

### 4a. Estado diário para clientes mobile

- Fonte pura: `@mpp/core/daily-state` (`buildDailyState`).
- Serviço de aplicação: `@mpp/agent/daily-state-service`
  (`loadOfficialDailyState`).
- API: `GET /api/mobile/v1/today`.
- `remaining_food_kcal` deriva de `eatingBalance` (§2a), sem exercício.
- `daily_balance_kcal` deriva de `netBalance` (§2b), com exercício.
- O saldo é `provisional` enquanto o dia está aberto, `final` após fechamento
  válido e `insufficient_data` quando o fechamento não possui informação
  suficiente. O bloco exposto é sempre o progresso persistido em `user_progress`;
  o cliente não projeta crédito para o dia aberto. Sem uma linha persistida de
  progresso, o bloco é `unavailable` e seus números são `null`, não zero.
- Snapshot, refeições e treinos são lidos juntos. Uma releitura da versão do
  snapshot evita misturar totais anteriores com logs de uma confirmação
  concorrente; após duas leituras instáveis, a API falha sem publicar estado
  híbrido.
- Hidratação usa somente `daily_snapshots.water_consumed_ml`; meta, quando
  configurada, vem de `notification_preferences.hydration_target_ml`. Percentual
  e restante não existem sem essa meta explícita.
- Suplementos e medicamentos são lidos exclusivamente por
  `list_mobile_routine_items`, que usa o fuso armazenado do usuário e o `now` do
  servidor para definir a data local. O `local_date` das duas leituras deve ser
  idêntico à data oficial do estado; qualquer divergência falha sem publicar um
  dia híbrido. Itens arquivados não entram na leitura.
- Cada item expõe `dose_text`, `origin`, `reminders_enabled`, a lista ordenada de
  horários e todas as ocorrências exatas do dia. Cada ocorrência mantém
  `reminder_rule_id`, `scheduled_for`, `status`, `last_action_at` e
  `snoozed_until`; horários do mesmo item são independentes. A chave interna da
  ocorrência não faz parte do estado público. A ordem técnica é determinística:
  tipo (`supplement` antes de `medication`) e ID do item; `local_time` e ID do
  horário; `scheduled_for` e `reminder_rule_id` da ocorrência. A serialização
  ordena cópias e não altera os arrays recebidos.
- A versão da semântica é `bodyflow.daily-state.v2`. A v2 muda somente o contrato
  de suplementos e medicamentos: cálculos de calorias, macros, hidratação,
  exercício e bloco 7700 permanecem idênticos à v1. O estado não calcula dose,
  prescrição nem recomendação, e o app nunca replica estas fórmulas.

### 4b. Estado do dia que o MODELO lê no Flow (contexto e tool)

A regra do §2 vale também para o texto entregue ao modelo. Um balanço sem
rótulo vira "o treino já foi descontado, pode comer mais".

Origem: iPhone, staging, 2026-10-04, chat do Flow (conta QA A). Paciente:
"Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?".
Flow: "Sim! Sua meta já considera esse gasto…". Dia naquele turno: meta 2980,
consumido 541, exercício 322, `daily_balance` −2761. O contexto entregava só
`Balanço calórico de hoje: -2761 kcal` (o líquido do §2b, com exercício); o
balanço de comida do §2a (restam 2439) não aparecia em lugar nenhum.

**Nenhuma fórmula mudou.** Mudou o rótulo, a instrução e quem responde a
pergunta direta. Tudo abaixo vale SÓ no canal Flow (`historyProvider ===
'mobile_flow'` / `assistantIdentity === 'flow'`); o WhatsApp está igual.

- **Contexto do turno** (`flowEnergyContextLines`,
  `packages/agent/src/flow-energy-context.ts`, chamado por `formatUserContext`):
  - `Para COMIDA hoje (meta − consumido, SEM exercício): restam X kcal` ou
    `… (consumido − meta, SEM exercício): excedente de X kcal acima da meta` → §2a.
  - `Exercício hoje: E kcal queimadas — NÃO aumenta a meta e NÃO entra no que
    resta para comida`.
  - `Balanço calórico de hoje COM exercício (consumido − meta − exercício): N
    kcal … — NÃO é o que resta para comer` → §2b. Em recomposição a linha diz
    também o que esse número NÃO é: `o crédito do bloco 7700 só é calculado no
    fechamento do dia (déficit programado − este número); até lá o valor é
    provisório`. O crédito é `designDeficit − daily_balance` (§3) — com dd 500
    e balanço −903, 1.403, não 903 — e de manhã o fechamento pode creditar 0
    (sub-registro, dia incompleto). A versão anterior dizia "é o número que o
    fechamento do dia usa no bloco 7700" e empurrava o modelo a citar o balanço
    como crédito (revisão de 2026-10-04, 2ª rodada).
  - Sem linha do dia em `daily_snapshots`, saem só a linha de comida e a REGRA
    (nenhum "déficit de 2980" de manhã, que o contexto antigo também não tinha).
  - `REGRA: exercício NÃO libera comida nem apaga excedente. …`. Abaixo da meta
    ou na meta exata: `o que o paciente pode comer é só o que está na linha
    "Para COMIDA"` e `mostre meta, consumido e o que resta para comida`. Com
    excedente de comida: `a linha "Para COMIDA" mostra excedente, então não
    resta nada para comida hoje` e `mostre meta, consumido e o excedente` (a
    regra não pede um "resto" que o contexto não tem). O bloco 7700 só é citado
    em recomposição.
  - Os dois números saem de `eatingBalance`/`netBalance` sobre a MESMA meta
    impressa no contexto (a do snapshot do dia; sem ela, a do perfil), como na
    tela Hoje (§4a). A coluna `daily_balance` não é usada no Flow: num snapshot
    sem meta gravada ela vale `consumido − 0 − exercício` e não bate com a meta
    impressa.
- **`consulta_progresso` no Flow** devolve `energia_hoje` (`meta_kcal`,
  `consumido_kcal`, `restam_para_comida_kcal` ou `excedente_de_comida_kcal`,
  `exercicio_kcal`, `balanco_do_dia_com_exercicio_kcal`, `regra`) e não expõe a
  chave crua `daily_balance` em `hoje`. No WhatsApp o retorno segue
  `{ progresso, hoje }` com a linha crua.
- **Pergunta direta** ("treinei, posso comer N kcal a mais / preciso repor / o
  treino aumenta a meta?"): quem responde é o sistema, sem modelo. A regra é
  uma lista branca — **só a pergunta direta, mensagem inteira dentro da
  gramática; qualquer outra coisa vai para o modelo com o contexto corrigido**.
  - Normalização: sem acento, minúsculas, ponto de milhar removido ("1.200" =
    1200), pontuação reduzida a quebra de frase, espaços colapsados. Símbolo
    fora disso (emoji, "+", aspas) não é aceito por nenhuma regra. Mais de 160
    caracteres depois de normalizar: não casa.
  - **Como a mensagem termina** (lido no texto bruto, antes da normalização):
    se a mensagem não tem nenhum `?` e termina em `.`, `!`, `…`, `,`, `;` ou
    `:` (ignorando espaços e aspas de fechamento), é afirmação e NÃO casa —
    "Treinei hoje e posso comer mais!", "Treinei hoje, então posso comer
    mais.". O `?` final só é opcional para mensagem SEM pontuação final (voz,
    digitação rápida): "treinei hoje posso comer mais" casa — e, pela mesma
    razão, a afirmação sem pontuação "treinei hoje e posso comer mais" também
    (pendência declarada abaixo). Um `?` em qualquer
    ponto mantém a mensagem como pergunta ("Posso comer 322 kcal a mais?
    Treinei musculação hoje e gastei 322 kcal.").
  - A mensagem INTEIRA tem de ser: (saudação opcional: oi, olá, bom dia, boa
    tarde, boa noite, Flow) + **relato do treino** + **pergunta direta**, numa
    das duas ordens abaixo, e mais nada. Uma palavra sobrando e o predicado
    devolve falso. **Toda forma de pergunta exige o relato do treino na mesma
    mensagem**: nenhuma pergunta vale sozinha.
  - Relato do treino — 1ª pessoa, passado, afirmativo, hoje ou sem dia:
    `treinei [modalidade]`, `malhei`, `corri`, `nadei`, `pedalei`, `caminhei`,
    `fiz [N min de] [um/o/meu] <modalidade>`, `fui (na|à|pra) academia`;
    seguido, se houver, de `hoje`, `agora`, `cedo`, `de manhã`, `de tarde`,
    `N min/h/horas/km`, `pesado`/`leve`; e de `(e|,) (gastei|queimei) N kcal`.
    Ou só o gasto: `(gastei|queimei) N kcal (no|na|de|com o|com a) <treino,
    academia, modalidade>`. Modalidades: musculação, academia, treino, cardio,
    bike, esteira, crossfit, pilates, funcional, corrida, natação, caminhada,
    spinning, luta, yoga, futebol.
  - Pergunta direta. Verbo de permissão: `posso`, `dá pra` (com `eu`
    opcional). **`consigo` não é verbo de permissão** — em "treinei e consigo
    comer mais" é capacidade ou apetite — e não está na gramática.
    - comer a mais: `(posso|dá pra) comer [N kcal | N | um pouco] (a
      mais|mais|extra)`, `… comer mais (N kcal|um pouco|calorias)`, `… comer N
      kcal`, `… comer (essas|as) [N] calorias [do treino|que gastei|que
      queimei] [a mais]`;
    - repor: `(posso|devo|preciso|tenho que|dá pra) (repor|comer de volta)
      [as|essas] [N] calorias [do treino|que gastei]`;
    - a meta: `(a|minha) meta [de hoje] (aumenta|muda|sobe)`;
    - só DEPOIS do relato: `isso (aumenta|muda|altera|sobe) minha meta`, `o
      treino (aumenta|muda|altera|sobe) (a|minha) meta [de hoje|de calorias]`,
      `(a|minha) meta (aumenta|muda|sobe) (com o treino|porque treinei|quando
      treino|já que treinei)`.
    - Pode terminar em `hoje`/`agora` e em `né`/`então`; `certo` só depois de
      uma pausa ("…a mais, certo?" casa; "comer mais certo" não).
  - Número que precisa repetir o gasto dito no relato (`gastei|queimei N
    kcal`): número sem unidade ("comer 322 a mais"), calorias sem "a mais"
    ("comer 322 kcal") e `comer (essas|as) N kcal` (com ou sem "a mais" —
    "essas 500 kcal" pode ser um alimento citado antes na conversa). Sem gasto
    no relato, ou com número diferente, não casa. `comer N kcal a mais` e
    `comer mais N kcal` casam com qualquer número.
  - Ordens e ligações aceitas — só estas duas:
    1. **relato → pergunta** (qualquer forma de pergunta): ligados por quebra
       de frase (`.`, `!`, quebra de linha), vírgula, nada, `e`, `então`, `e
       então`, `por isso`, `e por isso`; o relato pode vir depois de `como` ou
       `já que` ("Já que treinei, posso…"). Um `?` entre o relato e a pergunta
       NÃO é aceito ("Treinei hoje? Posso comer mais?" pergunta se treinou).
    2. **pergunta → relato** (só "comer a mais", "repor" e "a meta
       aumenta/muda/sobe"): ligados por `porque`, `já que`, quebra de frase,
       vírgula ou `?` ("Posso comer mais? Treinei.", "Minha meta aumenta porque
       treinei?").
  - Sem o relato nada casa: "Posso comer mais?", "O treino muda minha meta?",
    "Minha meta muda quando eu treino?", "Posso comer as calorias do treino?",
    "Preciso repor as calorias do treino?" vão para o modelo. No Flow "treino"
    também é o plano de treino (o canal cria sugestões de plano) e a rotina do
    perfil; depois de uma sugestão de plano, "o treino muda minha meta?" é
    sobre o plano (revisão de 2026-10-04, 2ª rodada).
  - Falso por construção (nada disso está na gramática): negação ou ausência
    do treino, futuro ou outro dia, outra pessoa (`treinou`, `ele pode`),
    perguntas abertas (`o que`, `como`, `quanto`), segundo pedido, sintoma,
    nome de alimento, plano/cardápio/dieta, `mas`, `sei que`, `já me disse`,
    `não entendi`, `consigo`, `?` entre o relato e a pergunta nessa ordem,
    afirmação terminada em `.` ou `!`.
  - **Texto da resposta** (`renderExerciseFoodAnswer`): meta, consumido,
    `restam = meta − consumido` (ou "já bateu a meta" / "N kcal acima da
    meta") e o exercício do BANCO, dito como tal: "As N kcal de treino
    registradas hoje ficam à parte e não entram no que resta para comida."
    (singular: "A 1 kcal de treino registrada hoje fica…"; em recomposição
    "…aceleram o bloco de 7.700 kcal, mas não entram…"; na meta exata "…não
    liberam mais comida"; com excedente "…não apagam esse excedente"). Quando a
    mensagem diz um gasto diferente do gravado ("gastei 400 kcal" com 150 no
    banco), a resposta acrescenta "Esse é o valor registrado no app." — não diz
    que o treino citado está faltando, e nenhum número digitado pelo paciente
    entra no texto.
  - **Sem treino no banco** (`exercise_calories` 0): a resposta não fala em
    "gasto do treino" nem em bloco. Depois da frase de comida vem, em todos os
    protocolos: "Não encontrei treino registrado hoje. Quando você registrar o
    treino no app, o gasto fica à parte e não entra no que resta para comida."
    (O chat do Flow não registra treino; digitar "treinei e gastei 322 kcal"
    não grava nada.)
  - **Pergunta repetida** (`lastReplyIsSameAnswer`): o modelo só responde
    quando o texto que o sistema daria AGORA é idêntico, caractere a caractere
    (depois de tirar espaços das pontas), ao conteúdo da última resposta do
    Flow nesta conversa — repetir o mesmo texto não ajuda. Em qualquer outro
    caso o sistema responde de novo: números do dia mudaram (consumido 302 →
    541), a resposta anterior do sistema era para outro estado do dia (meta
    batida, excedente, sem treino, outro treino gravado, com/sem a frase "Esse
    é o valor registrado no app."), o Flow disse outra coisa depois, ou a
    resposta idêntica é de um dia anterior (o histórico a entrega datada, então
    o texto não é igual). Não é comparação de prefixo: a versão anterior olhava
    só a frase de abertura e, depois de UMA resposta do sistema, mandava a
    frase do relato para o modelo pelo resto do dia.
  - O resto da regra (evento, texto do relato, onde fica o retorno) está no §5.
- Testes: `packages/agent/src/__golden__/audit-10-04-flow-exercise-food.test.ts`
  (frase, estado e horário exatos do relato, pelo `processAuthenticatedMessage`
  real; "perguntou duas vezes", "mesmo dia, números mudaram" e "outra forma
  primeiro, mesmo estado"; as mensagens que as duas rodadas da revisão de
  2026-10-04 viram respondidas pelo sistema no pipeline, com o histórico em que
  apareceram — apetite depois de "Está conseguindo comer…?", sugestão de plano
  de treino, açaí de 500 kcal; treino gravado diferente do digitado; e a fiação
  de `consulta_progresso` — o modelo
  chama a tool num dia sem meta gravada e lê `energia_hoje` com meta e restam,
  sem `daily_balance`), `flow-energy-context.test.ts` e
  `exercise-food-guard.test.ts` (tabelas casa / fora da gramática de propósito
  / não casa, com todas as mensagens citadas na revisão).
- WhatsApp travado byte a byte em
  `packages/agent/src/__golden__/audit-10-04-whatsapp-context-lock.test.ts`
  (verde antes e depois da correção).

Pendências declaradas (critério do CLAUDE.md):

> RC A — cenário canal WhatsApp NÃO coberto nesta PR (pendência da audit 2026-10-04).
> O contexto do WhatsApp continua entregando só `Balanço calórico de hoje: N`
> (líquido, sem rótulo) e não há resposta do sistema; a mensagem proativa do
> `engagement-sender` também. Mudar exige decisão do Eduardo/Roberto e golden
> próprio. Travado como está em `audit-10-04-whatsapp-context-lock.test.ts`.

> RC A — cenário pergunta direta fora da gramática NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Erro de digitação ("trenei"), "será que", "ingerir", "consigo comer mais?",
> "repor" sem dizer calorias, emoji, modalidade fora da lista ("joguei
> futebol", "treino de perna"), "passar da meta", "tenho N kcal a mais?", "o
> treino libera/soma/conta…", a pergunta sem o relato do treino de hoje ("o
> treino aumenta minha meta?", "posso comer as calorias do treino?") e "essas
> N kcal" que não repete o gasto do relato: todas vão para o modelo com o
> contexto corrigido. A lista está em `exercise-food-guard.test.ts`
> (`OUTSIDE_THE_GRAMMAR`), afirmada como falso.

> RC A — cenário mensagem mista (relato do treino + pergunta direta + outro pedido, sintoma, alimento ou segunda pergunta) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A resposta do sistema não entra; quem responde é o modelo, com o contexto
> corrigido.

> RC A — cenário resposta do MODELO com o contexto corrigido NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Não é provada por teste nem por evento. Vale para tudo que fica fora da
> gramática (inclusive as afirmações terminadas em "." ou "!") e para a
> pergunta repetida quando a última resposta do Flow é o mesmo texto que o
> sistema daria agora. Só nova rodada no iPhone/staging prova.

> RC A — cenário redação da resposta do sistema e da REGRA NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Texto clínico para o paciente, ainda sem aprovação do Roberto. Inclui a frase
> "Não encontrei treino registrado hoje…", "As N kcal de treino registradas
> hoje…", "Esse é o valor registrado no app.", a linha do balanço com exercício
> em recomposição ("o crédito do bloco 7700 só é calculado no fechamento…") e
> o caso de ganho de massa abaixo da meta.

> RC A — cenário exercício no balanço de ganho_massa/manutenção NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Decisão do Roberto em aberto. Nesses protocolos a resposta só diz que o gasto
> "fica à parte"; o bloco 7700 só é citado em recomposição e só com treino
> gravado no dia.

> RC A — cenário `consulta_resumo_periodo` (média de `daily_balance` sem rótulo), "balanço de ontem" e resumo persistente do paciente NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC A — cenário afirmação sem pontuação final ("treinei hoje e posso comer mais") NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Sem `?` e sem marca no fim não dá para separar a pergunta ditada da
> afirmação: a mensagem continua recebendo a resposta do sistema (que, nesse
> caso, corrige a crença). Também "Eu treinei hoje e por isso posso comer
> mais" e "Treinei hoje dá pra comer mais". Com "." ou "!" no fim vai para o
> modelo. Travado como está em `exercise-food-guard.test.ts` (`MUST_MATCH`) e
> no golden.

## 5. Defesas anti-erro (não remover)

- **Fake-registration detector** (`pipeline.ts`): se o LLM diz "registrado" com
  card mas NÃO chamou `registra_refeicao`/`registra_treino` → re-prompt forçado.
  Sem isso, refeições viram fantasma (card mostra, banco não tem). Eventos:
  `llm.fake_registration_detected/_unresolved`.
- **Card canônico** substitui alucinação numérica do LLM (`llm.card_replaced`).
- **reconcileBalanceProse** corrige rótulo déficit/superávit + magnitude na prosa.
- **Validador numérico / sentiment** loga divergências (`llm.numeric_mismatch`,
  `llm.sentiment_mismatch`).
- **Dedup intra-array** em `registra_refeicao` (itens repetidos somam quantidade).
- **Confirmação, no app, de proposta criada pelo app é aditiva**
  (`ToolContext.additiveConfirmation`). O campo é definido SÓ por
  `confirmRegistration` do BFF mobile e SÓ quando a proposta carrega
  `registration_origin: 'mobile_app'`. Quem escreve o marcador é
  `POST /registrations/propose`; a edição (`PATCH /registrations/:id`) MANTÉM a
  origem do pending editado — pending sem marcador continua sem marcador depois
  de editado. Com o campo, `registra_refeicao` NÃO promove `replace` por
  sobreposição de nomes em 30 min e NÃO descarta item pela dedup contra o dia:
  cada proposta confirmada é um registro novo, e repetir a mesma refeição soma,
  a qualquer distância no tempo. A idempotência por proposta continua
  (`raw_provider_message_id` + índice único): reenviar a MESMA proposta não
  duplica.
  - **Sobra só medição, em dois eventos** — contagens e ids, nenhum nome de
    item (nome de item é texto do paciente):
    `tool.replace_implicit_skipped_additive_confirmation` (`meal_type`,
    `overlap_ratio`, `recent_count`, `new_count`, `provider_message_id`), quando
    havia sobreposição de nomes em 30 min; e
    `tool.same_day_duplicate_kept_additive_confirmation` (`meal_type`,
    `existing_count`, `provider_message_id`), quando algum item da proposta
    (nome sem acento + gramas inteiras, a mesma chave da dedup contra o dia) já
    existia nessa refeição do dia — é o que ainda dispara depois de 30 min.
    Nenhum dos dois corrige nada, e duplicata com gramas diferentes depois de
    30 min não dispara nenhum. Nesse caminho, erro na leitura de 30 min, na
    leitura do dia ou no insert de um desses eventos NÃO derruba a confirmação
    (leitura que falha vale como "sem evidência").
  - **Edição depois de gravar sem fechar o pending.** Se a tool gravou e o
    UPDATE `pending → confirmed` falhou, o pending continua `pending`.
    `editRegistration` procura as linhas pela chave da proposta atual
    (`meal_logs` por `raw_provider_message_id`; treino: `workout_logs` por chave
    + tipo); se existem, conclui a transição e recusa o `PATCH` com
    `409 registration_already_confirmed`. Sem isso a edição trocava a chave e a
    confirmação seguinte gravava a refeição pela segunda vez. Se essa leitura
    falha, a edição é recusada (`500 registration_lookup_failed`).
    - **Código próprio, não `registration_not_pending`.** O iPhone trata
      `registration_not_pending` como "pending inválido": descarta a proposta e
      oferece "Criar nova proposta", que repropõe o rascunho — e, como a
      confirmação do app soma, grava a mesma refeição de novo. Um código que o
      build atual não conhece vira falha genérica: a proposta fica na tela e o
      Confirmar recebe `already_confirmed: true`, sem segunda gravação. O
      `PATCH` de um pending que já está `confirmed` responde o mesmo código
      (é o que o "Tentar novamente" do app reenvia depois que a guarda fechou
      o pending, e o que acontece quando a resposta do confirm se perdeu).
      Pending `cancelled`/`expired` continua em `registration_not_pending`.
    - **Refeição: só proposta do app.** A guarda de refeição vale só para
      proposta com `registration_origin: 'mobile_app'`: a chave dela é o
      `Idempotency-Key` de uma tentativa, então linha sob essa chave só pode
      ser dela. A chave de um pending do WhatsApp é o id da mensagem, que pode
      ter linhas de OUTRA refeição da mesma mensagem (registro expresso +
      pending no mesmo turno); fechar esse pending perderia uma refeição nunca
      gravada. Pending de refeição sem o marcador é editado como antes desta
      regra.
    - **Treino: qualquer origem.** A proposta de treino não carrega marcador,
      e a chave + tipo é exatamente a idempotência de `registra_treino`: linha
      sob ela significa que o confirm desse pending não gravaria nada.
  - **WhatsApp inalterado.** Pipeline e tap do botão nunca definem o campo: sem
    frase de adição, a 2ª proposta com os mesmos nomes em 30 min substitui;
    depois disso, item idêntico (nome + quantidade) no mesmo `meal_type` é
    descartado; e erro na leitura de 30 min ou na leitura do dia continua
    derrubando o registro (lá essas linhas decidem o que é substituído).
  - **Pending sem o marcador** (criado no WhatsApp ou antes desta regra)
    confirmado pela API do app segue o caminho antigo; a substituição é medida
    por `mobile.registration.implicit_replace` (id do pending, contagens e, em
    `cross_from`, só um tipo de refeição conhecido).
  - Nenhuma fórmula muda: comida = `consumido − meta` (sem exercício); bloco =
    `consumido − meta − exercício`.
  - Origem: iPhone, staging, 2026-10-04 — o mesmo almoço (150 g de frango,
    238,8 kcal) confirmado duas vezes em 1 min ficou com UMA linha (541 kcal no
    dia em vez de 780). Travado por
    `packages/agent/src/__golden__/audit-10-04-app-second-portion.test.ts` e
    `apps/admin/src/lib/mobile-api/registration-service.second-portion.test.ts`.

  Pendências declaradas do Defeito B (critério do CLAUDE.md):

  > RC B — cenário WhatsApp primeiro e app depois, em até 30 min NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Tap do WhatsApp e, em seguida, a mesma refeição confirmada no app: agora
  > SOMA (2 linhas, 780 kcal); antes desta PR substituía (1 linha, 541). Muda o
  > total de quem usa os dois canais para a mesma refeição. Só caracterizado
  > (caso 18 do golden); falta decisão do Eduardo/Roberto.

  > RC B — cenário app primeiro e WhatsApp depois NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Inalterado: em até 30 min o tap do WhatsApp SUBSTITUI a linha confirmada no
  > app (1 linha, 541; caso 19 do golden); depois disso o item idêntico do
  > WhatsApp é descartado como já registrado.

  > RC B — cenário dois itens com o mesmo nome dentro de UMA proposta do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Inalterado, anterior a esta PR. Mesmas gramas: grava uma linha só e o card
  > mostrou o dobro (perda silenciosa; caso 20 do golden). Nutrição diferente
  > entre as cópias: a tool lança "conflito nutricional" e o confirm devolve 500
  > em toda tentativa, até o paciente editar (caso 21). "Cada proposta
  > confirmada é um registro novo" não vale para cópias dentro da mesma
  > proposta.

  > RC B — cenário treino confirmado duas vezes no app NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Inalterado: `registra_treino` descarta treino idêntico (tipo + duração) em
  > 6 h enquanto o app mostra "confirmado".

  > RC B — cenário reclamação C8-35 do WhatsApp (2ª porção sem frase de adição) NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Inalterado por desenho: substitui em 30 min, descarta depois.

  > RC B — cenário SQL real das RPCs NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > `register_meal_atomic` e `register_meal_atomic_scoped` são emuladas em
  > TypeScript a partir das migrações; nenhum teste executa o SQL.

  > RC B — cenário editar ou apagar refeição já confirmada no app NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Não existe no app nem na API mobile. Como toda confirmação soma, um engano
  > (duplicata acidental) não pode ser desfeito por lá; os dois eventos só medem.

  > RC B — cenário foto e áudio no app NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Usam o mesmo confirm, mas não foram reproduzidos no aparelho.

  > RC B — cenário pending sem o marcador (criado no WhatsApp ou antes desta PR) confirmado pela API do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Segue o caminho antigo, com perda (1 linha, 541), só medido.

  > RC B — cenário pending de correção do WhatsApp editado pela API do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Inalterado em relação a antes desta PR: a edição reconstrói a proposta sem
  > `replace`/`writeItems`/`corrections`; o item que a correção trocaria continua
  > gravado (4 linhas em vez de 3). A tela do iPhone só edita proposta criada
  > por ela.

  > RC B — cenário pending de treino editado para refeição pela API NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > A proposta de treino não carrega o marcador; a refeição resultante segue o
  > caminho antigo. A tela do iPhone não troca o tipo ao editar.

  > RC B — cenário cancelar (DELETE) um pending cuja escrita já aconteceu NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Inalterado, anterior a esta PR: o pending vira `cancelled` e a refeição fica
  > gravada. A guarda nova cobre só a edição (`PATCH`). Com o pending já
  > `confirmed`, o `DELETE` continua respondendo `409 registration_not_pending`
  > (o iPhone oferece "Criar nova proposta").

  > RC B — cenário PATCH simultâneo a um confirm em andamento NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > A guarda lê `meal_logs` antes do UPDATE, sem trava: um confirm que grava
  > entre a leitura e o UPDATE ainda deixa a proposta com chave nova.

  > RC B — cenário mensagem "já registrado" no iPhone para o código registration_already_confirmed NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > O build atual não conhece o código: mostra "Não foi possível concluir. Tente
  > novamente.", mantém a proposta na tela, "Tentar novamente" reenvia o mesmo
  > `PATCH` (mesma resposta) e Confirmar responde "Registro confirmado." sem
  > gravar de novo. Falta a mudança no iOS (mensagem própria e fechar a
  > proposta). Sequência lida no código do app, não executada no aparelho.

  > RC B — cenário pending de refeição sem o marcador cuja escrita já aconteceu, editado pela API NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > A guarda da edição vale só para proposta com `registration_origin`
  > `mobile_app`. Sem o marcador (WhatsApp, ou app antes desta PR) a edição é
  > aceita como antes desta PR: chave nova, e o confirm segue o caminho antigo
  > (substitui em 30 min; depois disso duplica).

  > RC B — cenário pending de treino do WhatsApp com treino do MESMO tipo já gravado pela mesma mensagem, editado pela API NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > A proposta de treino não carrega marcador, então a guarda de treino vale
  > para qualquer origem, por chave + tipo (a idempotência de `registra_treino`):
  > o `PATCH` fecha esse pending sem gravar o segundo treino. O confirm direto
  > do mesmo pending já terminava igual (deduplicado).

  > RC B — cenário pending expirado cuja escrita já aconteceu NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Inalterado: `PATCH` e confirm respondem `410 registration_expired`, que o
  > iPhone trata com "Criar nova proposta" (a refeição seria gravada de novo).
  > Exige a tela aberta 24 h depois de um confirm que falhou na transição.

- **Pergunta direta exercício × comida (só Flow)**: quando o paciente pergunta
  no chat do Flow se pode comer a mais / precisa repor / se a meta muda por ter
  treinado, a resposta é do SISTEMA (`renderExerciseFoodAnswer`,
  `packages/agent/src/exercise-food-guard.ts`), sem chamar o modelo: meta,
  consumido, `restam = meta − consumido` (§2a) e o exercício do banco à parte.
  No relato: "…sua meta continua em 2.980 kcal. Você consumiu 541 kcal, então
  restam 2.439 kcal para comer hoje (meta menos consumido). As 322 kcal de
  treino registradas hoje ficam à parte e não entram no que resta para
  comida." O retorno
  antecipado fica em `processResolvedMessage`, antes do router de modelo, e só
  com `historyProvider === 'mobile_flow'`. Evento:
  `pipeline.deterministic_exercise_food` (sem texto do paciente). O predicado
  (`asksExerciseFoodQuestion`) é uma LISTA BRANCA, não uma busca com lista de
  exclusões: só a pergunta direta, mensagem inteira dentro da gramática do
  §4b; qualquer outra coisa vai para o modelo com o contexto corrigido. Não
  acrescente "exceções" a ele — a primeira versão procurava a pergunta em
  qualquer ponto da mensagem e a revisão de 2026-10-04 mostrou o sistema
  respondendo a pedido de treino, sintoma, quem não treinou, "o que posso comer
  a mais?", fala de terceiro e pergunta de perfil. Erro de omissão vai para o
  modelo; falso positivo cala outra mensagem. Toda forma de pergunta exige o
  relato do treino de hoje na mesma mensagem, e afirmação terminada em "." ou
  "!" não é pergunta (§4b). Sem treino no banco a resposta diz "Não encontrei
  treino registrado hoje…" e não cita bloco; com treino no banco diz "de
  treino registradas hoje" e, se o paciente digitou outro gasto, "Esse é o
  valor registrado no app.". Pergunta repetida só vai para o modelo quando a
  última resposta do Flow é idêntica ao texto que o sistema daria agora; com
  números ou estado diferentes o sistema responde de novo (§4b). Julgar
  o texto do modelo por regex foi descartado na revisão (resposta errada que
  contém "a meta continua" passava). O bloco 7700 só é citado em recomposição
  e com treino gravado. Travado por `packages/agent/src/exercise-food-guard.test.ts`
  (tabelas casa / fora da gramática / não casa e todas as variantes do texto) e
  pelo golden do §4b.
  > RC A — cenário canal WhatsApp NÃO coberto nesta PR (pendência da audit 2026-10-04).
- **Sub-registro / inactive / incomplete** no closer (§3) evitam déficit fake.

## 6. Auditoria automática (3×/dia, 9h/15h/21h BRT)

- `daily-audit` (cron nativo Inngest). Coleta métricas + manda Telegram.
- **Auto-corrige blocos** divergentes via `recomputeUserBloco` (§3), com
  **circuit-breaker**: se >8 usuários divergem num run, NÃO aplica e alerta
  (sinal de bug de fórmula). Evento `audit.bloco_autofixed`.
- Divergência snapshot↔meal_logs = só **ALERTA** (qual valor é verdadeiro é
  ambíguo — não auto-corrige).

## 7. Timezone

- Cada usuário tem `users.timezone`. Datas/janelas usam `getTzOffset`,
  `getLocalDateString`. Roberto = America/New_York; maioria = America/Sao_Paulo.
- ⚠️ **Pendência conhecida:** o `daily-closer` tica 00:30–03:30 UTC, que NÃO cobre
  bem a meia-noite de New_York (04:00 UTC) → dia de paciente em NY pode fechar
  com atraso. Investigar ticks adicionais pra fusos ocidentais.

---

## Como NÃO errar de novo (para humanos e para o agente)

1. **Toda regra de cálculo vive no código + teste**, não na cabeça de ninguém.
   Antes de mudar fórmula, leia este doc e o teste que a trava.
2. **Print de paciente ≠ ordem de mudar fórmula.** Reproduza no banco primeiro
   (consumido, meta, exercício, meal_logs, snapshot) e confronte com este doc.
3. **Card e bloco usam balanços diferentes** (§2). 90% da confusão histórica veio
   de misturar os dois. Comida sem exercício; bloco com exercício.
4. **Nunca confie só na ausência de evento** — um detector que não estava
   deployado não loga. Cheque o dado direto quando investigar período antigo.
5. Backfill de dado de paciente = sempre recálculo fiel ao closer
   (`bloco-recompute.ts`) + autorização explícita do Eduardo + evento de auditoria.
