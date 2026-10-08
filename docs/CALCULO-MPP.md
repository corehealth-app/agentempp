# Regras de cálculo do Agente MPP — fonte de verdade

> Este documento é a **referência canônica** de COMO o agente calcula tudo.
> Toda regra aqui deve estar **travada por teste**. Se mudar uma regra, mude:
> (1) o código, (2) o teste que a trava, (3) este documento — na mesma PR.
> Nunca mude uma fórmula "no susto" por um print de paciente sem checar aqui.

Última revisão: 2026-10-07.

---

## 1. Meta calórica diária (`calories_target`)

- **Recomposição:** `meta = BMR × 1.2 − design_deficit`.
  - `design_deficit` (fome do paciente): leve 400 / médio 500 / alto 600.
  - O TDEE é **apenas informativo** na recomp — NÃO é a meta.
- **Ganho de massa:** `meta = BMR × fator de atividade × 1,05`
  (`calc.ganho_massa_surplus_multiplier`, padrão 1,05).
- **Manutenção** e protocolo ainda não definido: `meta = BMR × fator de
  atividade` (`calc.activity_factors`: sedentário 1,2 / leve 1,375 / moderado
  1,55 / alto 1,725 / atleta 1,9).
- A meta do dia fica gravada em `daily_snapshots.calories_target`. O "gasto do
  dia" usado no balanço do §2c é derivado dela, não recalculado do perfil.
- Código: `packages/core/src/engine/targets.ts` (`computeDailyTargets`),
  `packages/agent/src/calc-targets.ts`, `calc-config-loader.ts`.

## 1b. Meta de proteína diária (`protein_target`) — regra M1

> **Situação da regra:** dita pelo cliente (Dr. Roberto) no grupo do projeto em
> 15/04/2026 e em 15/05/2026 (texto); **implementada em 2026-10-04 a pedido do
> Eduardo; confirmação do cliente pendente.** Não é decisão nova do cliente.

```
recomposição:                         meta_proteína (g) = peso_kg × 1,5
ganho de massa / manutenção /
protocolo ainda não definido:         meta_proteína (g) = peso_kg × fator de calc.protein_factors
```

- **Recomposição: 1,5 g por kg de peso, fixo.** Fome e frequência de treino não
  entram.
  - 15/04/2026 (texto, relato C5-17, sobre o print "Meta de proteína: 180 g"
    com 100 kg): "A meta de proteina eu tinha pedido pra deixar fixa de 1,5 g de
    proteina por quilo de peso pra o protocolo de recomposição".
  - 15/05/2026 (texto): "poderiamos ajustar a meta de proteina do protocolo de
    recomposição corporal pra 1,5 g de proteina por kg de peso do usuario";
    perguntado se "Flat 1,5 pra todos" ou cascata por treino: "Mantém 1,5 para
    todos".
  - Substitui 1,7 / 1,8 / 1,9 por fome (24/02/2026) e a cascata 1,6 a 2,0.
- **Ganho de massa, manutenção e protocolo ainda não definido: nada mudou.** O
  fator vem de `calc.protein_factors` pela cascata de `resolveProteinFactor`
  (muita fome → `muita`; treino < 3 → `training_low`; pouca fome com treino ≥ 5
  → `optimal_high_training`; pouca fome com treino ≥ 4 → `optimal_mid_training`;
  resto → `moderada`). O cliente nunca disse se "todos" inclui esses
  protocolos; ver pendência.
- Arredondamento: 1 casa decimal. Sem peso, BMR ou nível de atividade a meta é
  `null`, nunca 0 g (relato C3-37).
- **Por que a regra mora no código e não na linha do banco:** em execução
  `protein_factors` vem de `global_config` e a linha inteira substitui o padrão
  do código. Em staging (lido em 2026-10-04) ela é a cascata da migration
  `20260507181000`: muita 1,6 / pouca 1,8 / moderada 1,8 / `training_low` 1,7 /
  `optimal_mid_training` 1,9 / `optimal_high_training` 2,0. O padrão do código
  (tudo 1,5, de 15/05/2026) nunca valeu ali. A recomposição agora lê
  `recomp_protein_g_per_kg`, que não tem linha no banco: vale o padrão do
  código (1,5). `calc.protein_factors` **não foi tocada** e não move mais a
  recomposição. Nenhuma migration e nenhuma escrita em banco foram feitas.

| Perfil (cascata do staging no banco) | antes | agora |
|---|---|---|
| recomposição, 100 kg, fome moderada, 5 treinos (C5-17) | 180 g | 150 g |
| recomposição, 100 kg, fome pouca, 5 treinos (C3-38) | 200 g | 150 g |
| recomposição, 100 kg, fome pouca, 4 treinos | 190 g | 150 g |
| recomposição, 100 kg, fome muita | 160 g | 150 g |
| recomposição, 100 kg, fome moderada, 2 treinos | 170 g | 150 g |
| recomposição, 99 kg, fome moderada, 5 treinos | 178,2 g | 148,5 g |
| recomposição, 62,5 kg, fome moderada, 5 treinos | 112,5 g | 93,8 g |
| recomposição, 80 kg, fome moderada, 4 treinos | 144 g | 120 g |
| ganho de massa, 80 kg, fome moderada, 4 treinos (QA A) | 144 g | 144 g |
| ganho de massa, 80,5 kg (QA A) | 144,9 g | 144,9 g |
| manutenção, 100 kg, fome pouca, 5 treinos | 200 g | 200 g |
| protocolo não definido, 100 kg, fome moderada, 4 treinos | 180 g | 180 g |

  Onde a linha do banco está em 1,5 (ou não existe), a recomposição já dava
  peso × 1,5 e não muda: 100 kg → 150 g, 99 kg → 148,5 g. A meta calórica (§1)
  é idêntica antes e depois.

- **Onde o número aparece:** a meta viva do perfil muda na hora (contexto do
  WhatsApp "- Meta de proteína de hoje", mensagens proativas, retorno de
  `define_protocolo` e `cadastra_dados_iniciais`, gerador de dieta). Card,
  tela Hoje e Flow leem a meta já gravada no `daily_snapshots` do dia (o
  primeiro registro do dia vence, `COALESCE` nas RPCs atômicas) e só usam a do
  perfil quando o dia ainda não tem meta gravada; o fechamento regrava a meta
  do dia com o valor calculado. O bloco 7700 não usa proteína.
- **Efeito colateral no XP do fechamento (não é mudança de código):** o
  `daily-closer` entrega a meta de proteína calculada ao `calcDailyXP`. Onde
  `calc.xp_rules` tem a tabela MPP (`meal_xp` / `protein_meta_xp` /
  `calories_meta_xp`), "bateu proteína" compara com a meta nova, menor: um dia
  de recomposição com 160 g, 100 kg e a cascata no banco não pagava o bônus
  (meta 200 g) e passa a pagar (meta 150 g) — 20 XP → 24 XP no exemplo do
  revisor (treino feito, 4 refeições, 1700/1745 kcal). Só recomposição, só onde
  `calc.protein_factors` ≠ 1,5. Com a fórmula antiga de `xp_rules` (staging,
  lido em 2026-10-04, e o padrão do código) nada muda: ela compara com
  `protein_threshold_g` = 100, não com a meta. "Dia perfeito" não é afetado (o
  closer passa foto e peso sempre `false`). O closer e `calcDailyXP` não foram
  tocados. **Conferir `calc.xp_rules` e `calc.protein_factors` de produção
  antes de qualquer deploy.** Ver pendência.
- **Na recomposição o agente não recebe um g/kg que não seja o da conta**
  (relato C3-38: "160 g (2,0 g/kg)" com 100 kg, protocolo de recomposição).
  `cadastra_dados_iniciais` devolve ao modelo a linha da view
  `v_user_metrics`, cujo `protein_factor` é um terceiro mapeamento fixo em SQL
  (pouca 1,6 / moderada 1,8 / muita 2,0). A ferramenta devolve a linha **sem**
  essa chave **somente quando** o perfil, depois da chamada, está em
  recomposição **e** o fator fixo está ligado — o caso em que o número da view
  contradiz a meta devolvida ao lado; aí o modelo recebe só os gramas
  (`protein_target_today_g`). **Em todos os outros casos o retorno é o de antes
  de 2026-10-04, chave por chave, em qualquer canal (WhatsApp e Flow):** ganho
  de massa, manutenção, perfil sem protocolo (ou sem linha em `user_profiles`)
  e recomposição com o interruptor desligado recebem `metrics` com
  `protein_factor`. A view não foi alterada. O protocolo vem da mesma leitura
  de `user_profiles` que calcula a meta (`loadDailyTargetsWithProtocol`): não
  há consulta nova.

  | Perfil depois da chamada | fator fixo | `metrics.protein_factor` no retorno |
  |---|---|---|
  | recomposição | ligado (padrão, ou linha com número em 0 < v ≤ 3, ou linha inválida) | **ausente** |
  | recomposição | desligado (linha = `0` ou `null`; ou `RECOMP_PROTEIN_G_PER_KG = null` sem linha) | presente (o da view), como antes |
  | ganho de massa / manutenção / sem protocolo | ligado ou desligado | presente (o da view), como antes |
  | view sem linha | qualquer | `metrics: null`, como antes |
- **Interruptor (um só para a regra inteira):** `recomp_protein_g_per_kg` = `0`
  (ou `null`) devolve a recomposição à cascata de `calc.protein_factors` **e**
  devolve o `protein_factor` da view ao retorno de `cadastra_dados_iniciais`
  (comportamento anterior nos dois pontos).
  - **Sem deploy (recomendado: `0`).** A linha `calc.recomp_protein_g_per_kg`
    não existe em nenhuma migration, a tela `/settings/calc` só edita linhas
    existentes, e `global_config.value` é `jsonb NOT NULL`: um `NULL` de SQL —
    o que a RPC `set_global_config` recebe quando o cliente manda JSON `null`,
    pela leitura das migrations — é recusado pela coluna. A linha tem de ser
    criada com um valor JSON. O
    comando exato (escrita em banco: **só com autorização explícita do
    Eduardo**; **não foi executado em banco nenhum**):

    ```sql
    INSERT INTO public.global_config (key, value, updated_at)
    VALUES ('calc.recomp_protein_g_per_kg', '0'::jsonb, now())
    ON CONFLICT (key) DO UPDATE
      SET value = EXCLUDED.value, updated_at = now();
    ```

    Vale em até 60 s (cache do carregador). Para religar a regra:
    `DELETE FROM public.global_config WHERE key = 'calc.recomp_protein_g_per_kg';`
    (volta o padrão do código, 1,5). `'null'::jsonb` também desliga, mas `0` é
    o valor recomendado: não se confunde com `NULL` de SQL.
  - **No código:** `RECOMP_PROTEIN_G_PER_KG = null` em
    `packages/core/src/calc-config.ts` (uma linha; exige deploy). Desliga a
    meta fixa e a retirada do `protein_factor` de uma vez, desde que não exista
    a linha no banco com um número válido.
  - **O que a linha do banco aceita** (`fixedRecompProteinFactor`,
    `packages/core/src/nutrition.ts`):

    | Valor da linha | Efeito |
    |---|---|
    | `0` ou `null` (explícitos) | regra desligada: recomposição volta à cascata |
    | número em 0 < v ≤ 3 (ex.: 1,2) | troca o fator (100 kg × 1,2 = 120 g) |
    | qualquer outra coisa: texto (`"1.5"`, `"0"`), negativo, acima de 3 (99, 1e9), booleano, objeto, lista | **ignorada: vale o padrão do código (1,5)** — nunca a cascata em silêncio, nunca uma meta absurda |
    | linha ausente | padrão do código (1,5) |

    O limite 3 é uma trava contra erro de digitação
    (`RECOMP_PROTEIN_G_PER_KG_SANITY_MAX`), **não** um número clínico e não foi
    dito pelo cliente. Antes desta trava (revisão de 2026-10-04): linha = 99 →
    meta de 9900 g para 100 kg; linha = 1e9 → 100000000000 g; linha = `"1.5"`
    (texto) → 200 g pela cascata, sem erro nem log. Agora as três dão 150 g.
- Código: `packages/core/src/calc-config.ts` (`recomp_protein_g_per_kg`,
  `RECOMP_PROTEIN_G_PER_KG`, `RECOMP_PROTEIN_G_PER_KG_SANITY_MAX`),
  `packages/core/src/nutrition.ts` (`resolveProteinFactorForProtocol`,
  `fixedRecompProteinFactor`, `computeMetrics`),
  `packages/core/src/engine/targets.ts` (`computeDailyTargets`, o único ponto
  de cálculo), `packages/agent/src/calc-targets.ts`
  (`loadDailyTargetsWithProtocol`), `packages/agent/src/tools.ts`
  (`cadastraDadosIniciais`).
- Testes: `packages/core/src/engine/targets.test.ts` (recomposição com toda
  combinação de fome e treino; os outros protocolos iguais à função anterior;
  interruptor), `packages/core/tests/protein-factor.test.ts`,
  `packages/agent/src/calc-config-loader.test.ts` (linha = 0, null, texto e
  99 pelo carregador), `packages/agent/src/calc-targets.test.ts`,
  `packages/agent/src/tools-profile-write-safety.test.ts` (o retorno de
  `cadastra_dados_iniciais` em cada ramo: recomposição ligada / desligada /
  linha inválida, ganho de massa, manutenção, sem protocolo, sem perfil, view
  sem linha, WhatsApp e Flow) e o golden
  `packages/agent/src/__golden__/audit-10-04-protein-recomp.test.ts` (C5-17,
  C3-38 e C3-37 pelo carregador real, pelas duas ferramentas reais e pela linha
  do contexto no WhatsApp e no Flow, com `global_config` igual ao de staging;
  mais as entradas dos revisores de 2026-10-04: ganho de massa 80 kg com a
  view em 1,8 e o interruptor desligado → `metrics` com `protein_factor` 1,8,
  2980 kcal e 144 g; linha = 99 / 1e9 / `"1.5"` → 150 g; `null` e `0` → 200 g;
  1,2 → 120 g).
  Os goldens `audit-10-01-flow-weight-day-target` e
  `audit-10-04-whatsapp-context-lock` (ganho de massa, 144 g e 144,9 g) não
  foram editados e seguem verdes.

> RC M1 — cenário ganho_massa e manutenção ("Mantém 1,5 para todos", 15/05/2026: o cliente nunca disse se "todos" inclui os outros protocolos) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterados: seguem `calc.protein_factors` (staging 1,6 a 2,0).

> RC M1 — cenário protocolo ainda não definido durante o cadastro pelo WhatsApp (cadastra_dados_iniciais antes de define_protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: usa `calc.protein_factors` e o retorno traz o `protein_factor` da view, como antes. Em staging o modelo recebe 200 g com `protein_factor` 1,6 (100 kg, fome pouca, 5 treinos) e, depois de escolher recomposição, 150 g. O 1,6 recebido antes da escolha continua no histórico do turno: o resumo da recomposição escrito em seguida ainda pode citá-lo.

> RC M1 — cenário coluna `protein_factor` da view `v_user_metrics` (pouca 1,6 / moderada 1,8 / muita 2,0) NÃO coberto nesta PR (pendência da audit 2026-10-04). A coluna continua no banco e continua sendo entregue ao modelo em ganho de massa, manutenção, perfil sem protocolo e recomposição com o interruptor desligado, mesmo quando não é o fator da conta (ex.: ganho de massa, fome pouca, 5 treinos: view 1,6, cascata do staging 2,0). Só deixou de ser entregue na recomposição com o fator fixo ligado. Sem migration.

> RC M1 — cenário valor de `calc.protein_factors` em PRODUÇÃO NÃO coberto nesta PR (pendência da audit 2026-10-04). Não foi lido. Se não estiver em 1,5, a meta de quem está em recomposição muda no deploy; conferir antes.

> RC M1 — cenário XP do fechamento (`calcDailyXP` recebe a meta de proteína nova: onde `calc.xp_rules` tem a tabela MPP, o bônus "bateu proteína" passa a ser pago em dias em que não era) NÃO coberto nesta PR (pendência da audit 2026-10-04). O closer não foi tocado e nenhum teste desta PR o exercita; o exemplo 20 XP → 24 XP é do revisor. `calc.xp_rules` de produção não foi lido: conferir `calc.xp_rules` e `calc.protein_factors` de produção antes de qualquer deploy.

> RC M1 — cenário interruptor executado num banco real (o upsert de `calc.recomp_protein_g_per_kg` = 0 em `global_config`) NÃO coberto nesta PR (pendência da audit 2026-10-04). Nenhum banco foi tocado; o SQL acima foi escrito a partir das migrations (`20260502140000`, `20260720014221`) e não foi executado. Os testes só provam que a linha, uma vez lida pelo carregador real, desliga a regra.

> RC M1 — cenário histórico (metas de proteína já gravadas em `daily_snapshots`, inclusive a do dia da troca) NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem backfill: card, tela Hoje e Flow seguem a meta já gravada no dia; o gráfico de Progresso mostra um degrau.

> RC M1 — cenário conversa real (o modelo citar um g/kg tirado do roteiro ou das regras gravadas no banco) NÃO coberto nesta PR (pendência da audit 2026-10-04). Os roteiros ficam no banco; os testes só provam que nenhuma ferramenta entrega um fator.

> RC M1 — cenário altura, idade, atividade e fome reais dos prints C5-17 e C3-38 (e as metas calóricas 1914 e 1806) NÃO coberto nesta PR (pendência da audit 2026-10-04). Os prints não trazem esses dados.

## 2. Balanço do dia — DOIS números distintos (NÃO confundir)

Esta é a regra que mais gerou bug. Existem **dois** balanços, com finalidades diferentes:
o de COMIDA (§2a) e o do dia (§2b, que o fechamento usa no bloco). Desde
2026-10-04 a tela Hoje do app e o Flow mostram o balanço do dia **contra o gasto
do dia, por protocolo** (§2c); o §2a não mudou em nenhum protocolo.

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
- É o número usado pelo `daily-closer` pra creditar o bloco, o da coluna do
  banco, o do contexto do WhatsApp e o da mensagem de bom dia — **em todo
  protocolo, sem mudança**. É medido contra a META.
- **Não é mais** o número da linha "Balanço do dia" do app (até 2026-10-04 o
  rótulo era "Déficit líquido") nem o da linha "Balanço calórico de hoje" do
  Flow: esses seguem o §2c. Exceções em que a tela e o Flow voltam a ESTE
  número: protocolo ainda não definido e dia de troca de protocolo (§2c, "Dia
  de troca de protocolo").
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
> "Bloco = com exercício" é a regra do cliente para a **recomposição**. Em ganho
> de massa e manutenção ele disse que o exercício não entra no balanço do dia
> (§2c); o fechamento ainda credita o bloco com exercício nesses dois
> protocolos — pendência declarada no §2c, não regra.

### 2c. Balanço do dia POR PROTOCOLO — tela Hoje e Flow (regras R1 e R2)

> **Situação da regra:** dita pelo cliente (Dr. Roberto) no grupo do projeto em
> 20/01/2026 e 09/03/2026 (texto) e em 22/02/2026 e 23/02/2026 (áudio);
> **implementada em 2026-10-04 a pedido do Eduardo; confirmação do cliente
> pendente.** Não é decisão nova do cliente.

```
balanço do dia = consumido − gasto do dia        (negativo = déficit, positivo = superávit)

recomposição:    gasto do dia = BMR × 1,2 + exercício do dia
ganho de massa:  gasto do dia = BMR × fator de atividade     (exercício NÃO é somado)
manutenção:      gasto do dia = BMR × fator de atividade     (exercício NÃO é somado)
```

- O que o cliente escreveu:
  - 20/01/2026 17:38 (texto): "Balanço diário Recomposição: Somatório das
    calorias consumidas no dia - (BMR x 1,2 + calorias gastas no exercicio do
    dia)"; "Balanço calórico Ganho de massa muscular: Somatório das calorias
    totais consumidas no dia - (BMR x fator de atividade)"; "Balanço calórico
    Manutenção: Somatório das calorias totais consumidas no dia - (BMR x fator
    de atividade)".
  - 22/02/2026 12:10 (áudio): "A fórmula que tá lá do balanço é meta né não é
    meta … é o BMR vezes o fator de atividade física"; "o único que é
    exatamente igual a meta é a manutenção".
  - 23/02/2026 20:14 (áudio): "o exercício físico … só vai entrar no balanço
    quando for recomposição corporal".
  - 09/03/2026 12:37 (texto): as mesmas três fórmulas; 13:18: "nos protocolos de
    ganho de massa e manutenção, mesmo q o usuario informe a atividade fisica
    do dia ela não deve entrar no calculo do balanço pq ela ja foi contemplada
    no fator multiplicador".
  - Recomposição, os números que ele pediu: 20/05/2026 08:39 "O déficit de
    ontem deveria ser 500 - 233=267 + 565 = 832"; 21/05/2026 22:11
    "500-126=374 / 374+523=897 kcal de déficit hj".
- **De onde sai o gasto** (`dayEnergyBalance`, `referenceKcal`): da META DO
  DIA, nunca recalculado do perfil.
  - recomposição: `meta + déficit programado` (= BMR × 1,2, §1). O déficit
    programado é a expressão do fechamento, aplicada ao **protocolo efetivo**
    do dia (abaixo): protocolo efetivo em recomposição ? `deficit_level ?? 500`
    : 0. O balanço é `consumido − (meta + déficit) − exercício` =
    `daily_balance − déficit programado` = o "déficit real do dia" com o sinal
    trocado.
  - ganho de massa: `round(meta ÷ multiplicador)` (padrão 1,05; = BMR × fator).
    O multiplicador é lido da configuração com `Number()`, a mesma coerção que
    o cálculo da meta já faz (`tdee * multiplicador`): uma linha
    `calc.ganho_massa_surplus_multiplier` gravada como o texto `"1.05"` vale
    1,05 (antes da revisão de 2026-10-04 a meta saía 2799 e a referência
    também 2799, saldo +1 em vez de +134). Multiplicador ausente ou `null`:
    1,05. Zero, negativo, não finito ou texto que não é número: a referência é
    a própria meta (nada é inventado).
    Com multiplicador zero ou negativo **e** meta gravada no dia, a meta de
    ganho calculada do perfil vira 0, não bate com a meta gravada e o dia cai
    no número de antes (contra a meta, com exercício,
    `daily_balance_includes_exercise` verdadeiro); com texto que não é número
    o dia fica na regra sem exercício.
  - manutenção: a própria meta.
  - Por que da meta do dia: é a meta impressa ao lado do número; vale em dia
    que só guarda a meta; não muda quando o peso muda no meio do dia. Custo: em
    ganho de massa pode diferir 1 kcal de `round(BMR × fator)`.
- **Protocolo efetivo do dia:** o da linha do dia
  (`daily_snapshots.current_protocol`, gravado só no fechamento) quando ela o
  tem; senão o do perfil. A tela Hoje e o Flow usam o mesmo, e o déficit
  programado é o DESSE protocolo. Antes da revisão de 2026-10-04, num dia
  fechado em recomposição com o perfil já em ganho de massa (2076 / 1843 / 565),
  a tela dizia −332 contra 1843 (protocolo da linha com o déficit do protocolo
  do perfil, 0) e o Flow +321 contra 1755 (protocolo do perfil); agora os dois
  dizem −832 contra 2343. No inverso (linha em ganho de massa 2980 / 2980 /
  322, perfil em recomposição/500): tela e Flow +142 contra 2838 (o Flow dizia
  −822 contra 3480). O `deficit_level` é sempre o do perfil de agora: a linha
  do dia não guarda o déficit com que foi fechada.
- **Dia de troca de protocolo** (revisão de 2026-10-04). As RPCs de registro
  mantêm a PRIMEIRA meta do dia (`COALESCE`), então depois de uma troca de
  protocolo a linha do dia continua com a meta do protocolo antigo. Derivar o
  gasto dessa meta com a regra do protocolo novo dava número com sinal
  invertido: homem, 81 kg, 180 cm, 44 anos, moderado; manhã em ganho de massa
  grava 2799; ao meio-dia o perfil vira recomposição/500; consumido 2500 →
  "−799 contra 3299" (déficit), quando a regra do cliente dá 2500 − 2064 =
  +436 (superávit).
  - **O que é comparado:** a meta gravada na linha do dia
    (`daily_snapshots.calories_target`) contra as três metas que
    `computeDailyTargets` dá AGORA para o mesmo perfil e a mesma configuração,
    uma por regra — recomposição (com o `deficit_level` atual), ganho de massa
    (com o multiplicador atual) e manutenção (`dailyTargetByProtocol`). As
    quatro são inteiras (`Math.round`).
  - **Critério:** a meta gravada vale como meta do protocolo efetivo quando
    está **pelo menos tão perto** da meta desse protocolo quanto de cada uma
    das outras duas. Empate fica com o protocolo efetivo. Não há tolerância
    numérica fixa nem arredondamento a compensar: é comparação de distâncias.
  - **Por que proximidade e não igualdade:** um peso novo registrado depois da
    primeira refeição muda a meta em poucas kcal e NÃO é troca de protocolo. A
    própria conta QA do relato de 04/10 é um dia assim: meta gravada 2980 (com
    80 kg), perfil com 80,5 kg dá 2988. Com igualdade, todo dia de pesagem
    cairia no número legado, inclusive o cenário exato do relato. Uma troca de
    protocolo move a meta em centenas de kcal (2799 → 1564).
  - **Quando a meta gravada é de outra regra:** a tela Hoje E o Flow ficam com
    o número legado naquele dia — `consumido − meta gravada − exercício`,
    `daily_balance_includes_exercise` `true`, `daily_balance_reference_kcal` =
    a meta gravada. No exemplo: −299. No inverso (1564 gravada em recomposição,
    ganho de massa ao meio-dia, consumido 2000): +436 (antes +510 contra 1490;
    a regra do cliente daria 2000 − 2666 = −666). Primeiro dia (2666 gravada
    sem protocolo, depois recomposição, consumido 1800): −866 (antes −1366
    contra 3166; a regra do cliente daria −264). O `protocol` publicado
    continua sendo o do perfil; só o balanço volta ao número anterior.
  - **Sem comparação possível, vale a regra do protocolo:** dia sem meta
    gravada (a meta é a do perfil), protocolo que não é um dos três, perfil
    cuja meta não pode ser calculada.
  - Uma função só decide isso para a tela e para o Flow:
    `resolveDayBalanceInputs`
    (`packages/core/src/engine/day-balance-inputs.ts`), chamada por
    `daily-state-service` e por `flowDayBalanceInputs`.
- **Protocolo ainda não definido** (`null`) ou texto desconhecido: nada mudou —
  `consumido − meta − exercício`.
- **O que NÃO mudou:** "Restam / Excedente" (§2a) continua contra a META, sem
  exercício, em todo protocolo. `eatingBalance`, `netBalance`,
  `realDailyDeficit`, `creditDayToBloco`, o fechamento, `bloco-recompute`, o
  card, o bom dia, o contexto do WhatsApp e a coluna gerada
  `daily_snapshots.daily_balance` não foram tocados. Nenhuma migration,
  nenhuma escrita em banco. A coluna gerada **não é** o balanço deste parágrafo.
- **Onde vale:** tela Hoje do app (`daily_balance_kcal`, linha "Balanço do
  dia", antes "Déficit líquido"; §4a) e chat do Flow (linha "Balanço calórico
  de hoje" do contexto e `consulta_progresso`; §4b). Os três leem a mesma
  função, com as mesmas entradas (`resolveDayBalanceInputs`), então mostram o
  mesmo número. Todo número publicado é inteiro (o app decodifica `Int`),
  inclusive `daily_balance_reference_kcal` no caminho legado, que antes da
  revisão de 2026-10-04 repassava a meta sem arredondar.

| Cenário | meta / consumido / exercício | antes | agora | "Restam" |
|---|---|---|---|---|
| recomposição 19/05/2026 (déficit 500) | 1843 / 2076 / 565 | −332 | −832 (contra 2343 + 565) | excedente 233, igual |
| recomposição 21/05/2026 | 1843 / 1969 / 523 | −397 | −897 | excedente 126, igual |
| recomposição, dia aberto 22/05/2026 12:37 | 1843 / 568 / 648 | −1923 | −2423 | restam 1275, igual |
| recomposição, manhã sem registro | 1900 / 0 / 0 | −1900 | −2400 | restam 1900, igual |
| ganho de massa, conta QA 04/10/2026 | 2980 / 541 / 322 | −2761 | −2297 (contra 2838) | restam 2439, igual |
| ganho de massa comendo a meta, com treino de 322 | 2980 / 2980 / 322 | −322 | +142 | 0, igual |
| ganho de massa comendo a meta, sem treino | 2980 / 2980 / 0 | 0 | +142 | 0, igual |
| ganho de massa acima da meta | 2980 / 3200 / 322 | −102 | +362 | excedente 220, igual |
| ganho de massa entre a referência e a meta | 2980 / 2900 / 322 | −402 | +62 | restam 80, igual |
| manutenção | 3044 / 3044 / 400 | −400 | 0 | 0, igual |
| exemplo derivado (ver nota) | 2799 / 2799 / 300 ou 0 | −300 ou 0 | +133 (contra 2666) | 0, igual |
| protocolo não definido | 2980 / 541 / 322 | −2761 | −2761 | restam 2439, igual |
| dia de troca: ganho de massa de manhã, recomposição/500 ao meio-dia | 2799 / 2500 / 0 | −299 | −299 (legado, contra 2799) | restam 299, igual |
| dia de troca, inverso: recomposição de manhã, ganho de massa ao meio-dia | 1564 / 2000 / 0 | +436 | +436 (legado, contra 1564) | excedente 436, igual |
| primeiro dia: meta gravada sem protocolo, depois recomposição | 2666 / 1800 / 0 | −866 | −866 (legado, contra 2666) | restam 866, igual |

  O crédito do bloco em 19/05 continua 832 (5.254 → 6.086) e em 21/05 continua
  897 (5.757 → 6.654): o fechamento não foi tocado. Na recomposição a tela e o
  bloco coincidem em valor nos dias que creditam normalmente **e** em que a
  meta do dia não é recalculada no fechamento. O fechamento recalcula a meta
  com o perfil da hora do fechamento: em dia de troca de peso, de nível de
  atividade, de `deficit_level` ou de protocolo a tela (meta gravada de manhã)
  e o crédito (meta nova) diferem — pendências abaixo.

  Nota: o "+133" (2799 contra 2666; homem, 81 kg, 180 cm, 44 anos, moderado) é
  **recálculo da auditoria**, não número dito pelo cliente.
- **Interruptor:** `DAY_BALANCE_AGAINST_EXPENDITURE` em
  `packages/core/src/engine/balance.ts`, um booleano por protocolo
  (`recomposicao`, `ganho_massa`, `manutencao`). `false` devolve aquele
  protocolo ao número anterior (`consumido − meta − exercício`) na tela Hoje,
  na linha do Flow e na tool, de uma vez. Ao desligar os três, voltar também
  `DAILY_STATE_CALCULATION_VERSION` para `bodyflow.daily-state.v2` em
  `packages/core/src/daily-state.ts`. Os dois campos novos do `/today` são
  aditivos e podem ficar.
- **Interruptor da revisão de 2026-10-04:** `DAY_BALANCE_DAY_ROW_GUARD` em
  `packages/core/src/engine/day-balance-inputs.ts`. `enabled: false` desfaz,
  na tela e no Flow de uma vez, as duas coisas que ele ligou: a comparação da
  meta gravada (o dia de troca volta a "−799 contra 3299") e o protocolo
  efetivo (o Flow volta a usar só o protocolo do perfil e a tela volta ao
  déficit do protocolo do perfil). A leitura do multiplicador com `Number()` e
  o arredondamento de `daily_balance_reference_kcal` não têm interruptor: não
  mudam nenhum número em dado que o sistema grava hoje (colunas inteiras,
  multiplicador numérico).
- Código: `packages/core/src/engine/balance.ts` (`dayEnergyBalance`),
  `packages/core/src/engine/day-balance-inputs.ts`
  (`resolveDayBalanceInputs`, `dailyTargetByProtocol`),
  `packages/core/src/daily-state.ts` (`buildDailyState`),
  `packages/agent/src/daily-state-service.ts`,
  `packages/agent/src/flow-energy-context.ts` (`flowEnergyNumbers`,
  `flowDayBalanceInputs`, `flowEnergyContextLines`),
  `packages/agent/src/pipeline.ts` (só o ramo `mobile_flow`),
  `packages/agent/src/tools.ts` (`consultaProgresso`, só o ramo Flow),
  `packages/agent/src/numeric-validator.ts` (`reconcileBalanceProse`,
  `opts.dayBalance`).
- Testes: `packages/core/src/engine/balance.test.ts` (os três protocolos,
  interruptor desligado por protocolo, multiplicador inválido, protocolo nulo
  idêntico a `netBalance`, recomposição = `netBalance − déficit`),
  `packages/core/src/daily-state.test.ts`,
  `packages/agent/src/flow-energy-context.test.ts`,
  `packages/agent/src/numeric-validator.test.ts`,
  `packages/agent/src/daily-state-service.test.ts` e o golden
  `packages/agent/src/__golden__/audit-10-04-day-balance-by-protocol.test.ts`
  (os cenários da tabela pelo `loadOfficialDailyState` real, pelo contexto real
  do Flow e pela `consulta_progresso` chamada pelo modelo; crédito do bloco
  pelo `creditDayToBloco` real; interruptor). A revisão de 2026-10-04 está em
  `packages/core/src/engine/day-balance-inputs.test.ts` (as três metas por
  regra, proximidade e empate, conta QA com peso novo, protocolo efetivo,
  multiplicador como texto, interruptor desligado), em `balance.test.ts` e
  `daily-state.test.ts` (número legado quando a meta é de outra regra;
  referência inteira no caminho legado) e no fim do mesmo golden, pelas
  mesmas três entradas de produção: os três dias de troca (tela = linha do
  Flow = tool), a frase "déficit de 299 kcal" sobre excedente de 201, a linha
  do dia fechada com protocolo diferente do perfil (os dois sentidos), o
  multiplicador 1,10 chegando à `consulta_progresso` (2709 / −2168), o
  multiplicador gravado como texto e o interruptor desligado. O golden
  `audit-10-04-whatsapp-context-lock` e os testes de fechamento, bloco e card
  não foram editados e seguem verdes.

Pendências declaradas (critério do CLAUDE.md):

> RC R1/R2 — cenário crédito do bloco e fechamento diário em ganho_massa/manutenção (o cliente escreveu em 08/05/2026 que nesses protocolos o bloco de 7.700 "é substituido pelo bloco acumaldo de Kcal em 14 dias"; o bloco de 14 dias não está definido) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Inalterado: o fechamento credita `meta + exercício − consumido`. Manutenção
> 3044 / 3044 com treino de 400: a tela mostra 0 e o fechamento credita +400.
> Mexer nisso grava dado de paciente e exige autorização do Eduardo.

> RC R1/R2 — cenário contexto do WhatsApp e consulta_progresso do WhatsApp NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Inalterado e travado em `audit-10-04-whatsapp-context-lock.test.ts`: o
> WhatsApp entrega `Balanço calórico de hoje: N` contra a meta e com exercício.

> RC R1/R2 — cenário mensagem de bom dia do WhatsApp (engagement-sender) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Em ganho/manutenção continua rotulando ontem como "déficit real … alimenta o
> bloco 7700" a partir do balanço com exercício contra a meta.

> RC R1/R2 — cenário consulta_resumo_periodo (média da coluna gerada, com exercício e contra a meta, também no Flow) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> No Flow, a média do período pode contradizer o balanço do dia.

> RC R1/R2 — cenário coluna gerada daily_snapshots.daily_balance (consumido − meta − exercício em todo protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Sem migration. Quem ler a coluna (painel admin, scripts, auditoria) vê o
> número antigo.

> RC R1/R2 — cenário rótulo "Balanço do dia" e legenda do exercício do iPhone vistos no aparelho NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Coberto no código do app em commit separado do mesmo dia (9624cd5): rótulo
> "Balanço do dia", valor em palavras ("Déficit de N kcal" / "Superávit de N
> kcal"), legenda lida de `daily_balance_includes_exercise` (campo ausente =
> "Exercício incluído"). Ainda não verificado no aparelho. Continua aberto: o
> VoiceOver lê o valor duas vezes nessa linha; as frases da trilha e do tour
> sobre o bloco de 7.700 aparecem para todo protocolo; o app mostra o número do
> dia aberto. Um build anterior a esse commit mostra "Déficit líquido" com o
> número cru e a legenda fixa "Exercício incluído".

> RC R1/R2 — cenário protocolo ainda não definido (null) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Inalterado: `consumido − meta − exercício`.

> RC R1/R2 — cenário número de dia aberto na tela Hoje (o cliente disse em 22/05/2026 12:38 que "O deficit ou não do dia só pode ser falado após o dia fechado") NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A tela continua mostrando o número provisório do dia em andamento, agora 500
> kcal maior na recomposição (22/05 12:37: −1923 → −2423), atrás de "Mais
> detalhes" e ao lado de "Dia em andamento".

> RC R1/R2 — cenário dia em que o fechamento não credita o balanço observado (sub-registro abaixo de 50% da meta, dia incompleto, dia sem atividade) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Nesses dias o número da tela e do Flow não é o crédito do bloco (22/05
> 12:37: tela −2423; um fechamento naquele momento creditaria 500).

> RC R1/R2 — cenário resposta do MODELO no Flow com as linhas novas (conversa real) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Só nova rodada no iPhone/staging prova.

> RC R1/R2 — cenário redação das linhas novas do Flow (texto entregue ao modelo, sem aprovação clínica do cliente) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R1/R2 — cenário prosa do Flow sobre o balanço do dia sem o número exato ("você está em superávit", "superávit de quase 60 kcal") NÃO coberto nesta PR (pendência da audit 2026-10-04).
> `reconcileBalanceProse` só poupa a frase que cita o balanço do dia com o
> número exato (±1) e o sinal certo (§4); no WhatsApp ela não mudou.

> RC R1/R2 — cenário acréscimo do ganho de massa ("mais o zero mais os cinco por cento", 22/02/2026: 5% fixo ou faixa de 0 a 5%?) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A referência é a meta do dia dividida pelo multiplicador configurado (1,05).

> RC R1/R2 — cenário degraus de déficit na passagem recomposição → manutenção (áudios de 25/03/2026) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R1/R2 — cenário deficit_level ou multiplicador alterado depois de a meta do dia ter sido gravada NÃO coberto nesta PR (pendência da audit 2026-10-04).
> `deficit_level`: a referência é a meta gravada no dia + o déficit ATUAL do
> perfil. Multiplicador: se a meta gravada ficar mais perto da meta de
> manutenção do que da de ganho com o multiplicador novo (conta QA com 1,10:
> gravada 2980, ganho 3131, manutenção 2846), o dia cai no número legado
> (−2761, travado no golden); senão a referência é a meta gravada ÷ o
> multiplicador atual.

> RC R1/R2 — cenário dia de troca de protocolo: balanço do dia pela regra do cliente com o gasto do protocolo NOVO NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Nesse dia a linha do dia guarda a meta do protocolo antigo, e a tela e o Flow
> mostram o número legado (`consumido − meta gravada − exercício`, "Exercício
> incluído"): manhã em ganho de massa 2799, recomposição ao meio-dia, 2500
> consumido → −299 (a regra do cliente daria 2500 − 2064 = +436). O número
> legado desse dia não é o que o fechamento credita: o fechamento regrava a
> meta (1564) e credita 500 − 936 = −436.

> RC R1/R2 — cenário dia em que o peso, o nível de atividade ou a idade mudam depois de a meta do dia ter sido gravada (mesmo protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> O gasto continua derivado da meta gravada: conta QA 04/10, gravada 2980 com
> 80 kg, perfil com 80,5 kg dá 2988 → tela e Flow −2297 contra 2838 (com a meta
> nova seria −2305 contra 2846). O fechamento recalcula a meta com o perfil da
> hora do fechamento: nesses dias a tela e o crédito do bloco diferem pela
> diferença entre as duas metas.

> RC R1/R2 — cenário meta gravada mais perto da meta de outro protocolo por mudança grande de peso ou de nível de atividade no dia (sem troca de protocolo), e troca manutenção ↔ ganho de massa junto com mudança de peso NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A comparação é por proximidade entre a meta gravada e as três metas que o
> perfil dá agora, sem tolerância fixa. Ganho de massa e manutenção diferem só
> pelo multiplicador (133 kcal no exemplo da auditoria): uma mudança de alguns
> quilos no dia cai no número legado sem troca de protocolo, e uma troca
> manutenção ↔ ganho junto com mudança de peso pode não ser percebida.

> RC R1/R2 — cenário perfil incompleto (meta não calculável) com meta gravada no dia NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Sem meta calculada não há comparação: vale a regra do protocolo sobre a meta
> gravada.

> RC R1/R2 — cenário dia fechado em recomposição cujo deficit_level do perfil mudou depois do fechamento NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A linha do dia guarda o protocolo do fechamento, não o déficit programado: a
> tela e o Flow usam o `deficit_level` atual do perfil (500 quando ausente).

> RC R1/R2 — cenário dados reais de perfil dos dias 19/05, 21/05 e 22/05/2026 (altura, idade, peso; BMR × 1,2 lido do banco) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Os relatos trazem meta, consumido, exercício e bloco; a referência 2.343 é
> meta 1.843 + déficit 500.

> RC R1/R2 — cenário painel admin (/users/[id] e /formulas, que mostram a coluna gerada e a fórmula antiga) NÃO coberto nesta PR (pendência da audit 2026-10-04).

### 2d. kcal do exercício: o tipo digitado no app (regra W)

De onde vem o kcal de um treino sem foto: `calc_workout_kcal` (SQL, migration
`20260504165600`; lida no staging em 2026-10-04 — os testes a emulam, não a
executam):

```
kcal = ROUND(kcal_per_min × duração_min × fator × peso_kg / 70)
```
- `kcal_per_min`: linha ativa de `workout_types` cujo slug é o `lower()` do
  tipo recebido; se não houver, a linha 'outro' (6,0).
- `fator`: leve 0,75 · moderada 1,0 · alta 1,25. Peso do perfil; 70 kg quando
  o perfil não tem peso.

**App, desde 2026-10-04.** No iPhone o tipo é texto livre e a API o passava
como digitado: "Natação" não é o slug `natacao` e saía pela taxa genérica, sem
aviso. Agora a API do app, **só para a consulta da taxa**, normaliza o texto
(trim, minúsculas, sem acento, espaços, hífens e "_" viram um único "_") e usa
o resultado quando ele é um slug ativo; senão, o único slug ativo cujo
`display_name`, normalizado do mesmo jeito, é igual ("Polichinelos" →
`jumping_jacks`); senão passa o texto como digitado e a função cai em 'outro',
como antes. Sem sinônimo e sem busca aproximada. Vale na proposta, na edição e
na confirmação (`registra_treino` recalcula ao gravar: só na proposta, a tela
mostraria 400 e o banco gravaria 240). **O tipo gravado e mostrado continua o
texto digitado** (`workoutType` do pending, `workout_logs.workout_type`); só o
kcal muda.

**Como a confirmação entrega o slug à ferramenta.** Por um campo opcional e
tipado do contexto, `workoutKcalLookupSlug` (`packages/agent/src/tools/types.ts`),
definido só pela confirmação do app e só quando o texto digitado resolve para
outra grafia. `registra_treino` o lê em um único ponto, o argumento `p_slug` de
`calc_workout_kcal` (`ctx.workoutKcalLookupSlug ?? args.workout_type`); o tipo
gravado, a idempotência e o descarte de treino idêntico em 6 h continuam
usando o texto recebido. O cliente de banco entregue à ferramenta é o próprio
cliente, sem invólucro. **No WhatsApp o campo nunca é definido** (nem o
pipeline nem o toque de botão o mencionam) e a ferramenta envia ao banco
exatamente o que enviava: leituras, RPCs e argumentos travados em
`packages/agent/src/tools-workout-kcal-lookup.test.ts`. Lá o modelo escolhe o
slug pela lista da ferramenta.

**Leitura do catálogo.** A consulta da taxa lê `workout_types` uma vez em toda
proposta, edição e confirmação de treino do app, inclusive para slug exato e
tipo desconhecido. Se essa leitura falha: texto cujo minúsculo já é a própria
normalização (sem acento, espaço nem hífen: `musculacao`, `MUSCULACAO`,
`Capoeira`) segue como digitado, como antes da mudança, porque a função SQL
faz `lower()` sozinha e devolve para ele o mesmo que devolveria para o slug;
qualquer outro texto ("Natação", "jiu-jitsu", "corrida leve") responde
`500 workout_calculation_failed`, e nada é gravado nem alterado. Corrigido em
2026-10-05 (revisão, LOW): a primeira versão comparava o texto digitado com a
normalização sem passar para minúsculas, e "MUSCULACAO" (40 min, moderada,
70 kg) respondia 500 onde antes respondia 240 pela taxa do catálogo.

Caso do revisor ("Natação", 40 min, moderada, 70 kg): antes 'outro'
6,0 × 40 × 1,0 × 70/70 = **240**; agora `natacao` 10,0 × 40 × 1,0 × 70/70 =
**400**. Com as taxas do staging, no mesmo treino: Tênis 7,5 → 300, Muay thai
11,0 → 440, Jiu-jitsu 10,5 → 420, Elíptico 8,5 → 340, Corrida leve 8,0 → 320.

- Código: `apps/admin/src/lib/mobile-api/registration-service.ts`
  (`workoutLookupSlug`); `packages/agent/src/tools.ts` (`registra_treino`, o
  `p_slug` da consulta) e `packages/agent/src/tools/types.ts`
  (`workoutKcalLookupSlug`).
- Testes: `apps/admin/src/lib/mobile-api/registration-service.workout-type.test.ts`
  (serviço real e `registra_treino` real, banco em memória com o catálogo do
  staging; compara o catálogo do teste com as duas migrations e as linhas
  `RC W` abaixo com o cabeçalho do teste);
  `packages/agent/src/tools-workout-kcal-lookup.test.ts` (o lado do WhatsApp).

> RC W — cenário esporte que o catálogo não tem ("Capoeira", "Surfe") NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: taxa genérica 'outro' (6,0 kcal/min; 40 min, moderada, 70 kg = 240 kcal), sem aviso na resposta nem na tela, e o treino entra em `exercise_calories`. Travado no teste.

> RC W — cenário outra palavra para uma atividade que o catálogo tem ("Bike" para `bicicleta`, "Academia", "Futsal", "Natação no mar", duas atividades no mesmo campo, travessão ou outro separador como "Jiu–jitsu" e "jiu.jitsu") NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem sinônimo e sem busca aproximada: taxa genérica, em silêncio. No WhatsApp o modelo escolhe o slug; no app ninguém escolhe. "Bike" e "Natação no mar" travados no teste.

> RC W — cenário WhatsApp (o modelo manda para `registra_treino` um tipo com acento, espaço ou fora do catálogo) NÃO coberto nesta PR (pendência da audit 2026-10-04). O pipeline não foi tocado e nunca define o campo `workoutKcalLookupSlug` do contexto: sem ele a ferramenta passa o tipo como veio e a função cai em 'outro'.

> RC W — cenário treinos e propostas gravados antes desta mudança NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem backfill: a "Natação" de 240 kcal segue em `workout_logs`, em `exercise_calories` do dia e no bloco já creditado.

> RC W — cenário fechamento do dia (crédito do bloco 7.700) com o treino recalculado NÃO coberto nesta PR (pendência da audit 2026-10-04). O teste vai até `workout_logs.estimated_kcal` e `daily_snapshots.exercise_calories` (400); o closer não é executado e nenhum número de bloco é afirmado.

> RC W — cenário catálogo `workout_types` de PRODUÇÃO NÃO coberto nesta PR (pendência da audit 2026-10-04). Não foi lido. Taxas e nomes são os do staging em 2026-10-04 (58 linhas ativas, iguais às migrations 20260504165600 e 20260504172500).

> RC W — cenário tipo gravado como texto livre ("Natação" e "natacao" são tipos diferentes para a idempotência e para o descarte de treino idêntico em 6 h; histórico e tela mostram o que foi digitado) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado de propósito: o valor gravado não muda nesta PR.

> RC W — cenário peso do perfil ou catálogo alterados entre a proposta e a confirmação NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: a confirmação recalcula, e o kcal gravado pode diferir do kcal mostrado na proposta.

> RC W — cenário uma leitura a mais de `workout_types` em toda proposta, edição e confirmação de treino do app (inclusive slug exato e tipo desconhecido; sem cache) NÃO coberto nesta PR (pendência da audit 2026-10-04). Com a leitura funcionando, slug exato e tipo desconhecido saem como no HEAD; o custo é uma ida ao banco a mais por pedido. Travado no teste.

> RC W — cenário leitura do catálogo falha NÃO coberto nesta PR (pendência da audit 2026-10-04). Texto cujo minúsculo já é a própria normalização (sem acento, espaço nem hífen: "musculacao", "MUSCULACAO", "natacao", "Capoeira", "Bike") segue como digitado, como antes da mudança: a função SQL faz `lower()` sozinha e responde pela taxa do catálogo quando o slug existe ("MUSCULACAO", 40 min, moderada, 70 kg = 240; "NATACAO" = 400) e pela genérica quando não existe. Qualquer outro texto ("Natação", "jiu-jitsu", "corrida leve") responde `500 workout_calculation_failed`, onde antes respondia pela taxa genérica (240 no mesmo treino). E um texto do primeiro grupo que o catálogo só casa pelo nome de exibição sai pela taxa genérica enquanto a leitura falhar; no catálogo de staging são cinco, em qualquer combinação de maiúsculas: "polichinelos" ou "Polichinelos" (`jumping_jacks`) e, só se digitados com "_" no lugar dos espaços, "biceps_e_triceps", "costas_e_biceps", "ombro_e_trapezio" e "peito_e_triceps". Para "polichinelos": 240 em vez de 320 e, se a falha for só na confirmação, grava 240 sob uma proposta que mostrou 320. Travado no teste.

> RC W — cenário tela do iPhone (tipo digitado e kcal da proposta vistos no aparelho) NÃO coberto nesta PR (pendência da audit 2026-10-04). Nada foi executado no aparelho nem no simulador.

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
  `daily-closer.ts`, `bloco-recompute.ts` e, no fechamento sob demanda do
  ambiente de teste (§3a), `packages/agent/src/day-close.ts`.
- Recálculo do zero (auditoria/backfill): `lib/bloco-recompute.ts`.
- **Fora da recomposição** (`designDeficit` 0) o fechamento credita
  `−daily_balance` = `meta + exercício − consumido`, em qualquer protocolo. O
  cliente escreveu em 08/05/2026 que em ganho de massa e manutenção "o bloco de
  7.700 kcal é substituido pelo bloco acumaldo de Kcal em 14 dias", e em
  09/03/2026 que o exercício não entra no balanço desses protocolos. Isso
  **não está implementado no fechamento**: é pendência declarada no §2c, não
  regra nova. O balanço por protocolo do §2c não é lido aqui.

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

### 3a. Onde o dia fecha para uma conta do app no ambiente de teste (fechamento sob demanda)

**Produção não mudou.** Lá o `daily-closer` fecha "ontem" de toda conta com
`users.status = 'active'`, com ou sem WhatsApp; conta do app entra igual.
`packages/inngest-functions/src/functions/daily-closer.ts` não foi tocado.

**No ambiente de teste (staging) nenhum dia fechava.** O worker de lá serve só
o processamento de mídia, de propósito, para que nenhum lembrete de WhatsApp
possa sair. Lido em 2026-10-04 (somente leitura): 13 linhas de dia, 0 fechadas,
11 linhas de `user_progress` zeradas. Para a conta do app, bloco, sequência,
XP, nível e medalhas nunca andavam, e o resumo semanal do Flow não via dia
nenhum.

**O que existe agora.** `closeLocalDay` e `closePastOpenDays`
(`packages/agent/src/day-close.ts`) seguem o roteiro do `daily-closer` para UMA
data local explícita e chamam as MESMAS funções e a MESMA RPC: `calcDailyXP`,
`creditDayToBloco`, `computeProgress`, `resolveClosedDayStatus` (movida para
`@mpp/core`, `engine/day-status.ts`; o arquivo antigo do worker só a
reexporta), `getGapForDate`, `loadCalcConfig`, `loadDailyTargets` e
`finalize_daily_close_atomic`. Nenhuma regra dos §1 a §3 foi reescrita. O que
existe em dobro é o roteiro de leituras e escritas; o teste de paridade
compara, para o mesmo dia, os doze parâmetros da RPC, os campos gravados na
linha do dia, o `user_progress` final e os eventos.

Dois chamadores, e só eles:
- **API do app**, em `GET /today` e `GET /progress`, antes da leitura, **só
  com o interruptor ligado** (`docs/mobile/api-v1.md`, "Fechamento do dia sob
  demanda"). Desligado por padrão: sem a variável, nenhuma consulta é feita.
  Nunca em produção: o ref do projeto de produção é recusado em código.
- **Script de operador** `scripts/close-open-days.ts`: simulação por padrão,
  `--apply` para gravar, recusa qualquer banco que não seja o de staging.

**Não envia nada.** O único I/O é o cliente de banco recebido por parâmetro.
Sem provedor de mensagem, sem evento, sem chamada HTTP, sem modelo. Um teste
estático lê o código e falha se aparecer qualquer um deles.

#### Regras do caminho sob demanda

Onde a produção passa (fechar ONTEM enquanto a hora local é de 0 a 4, isto é,
de 00:30 a 04:59 neste caminho), o resultado é o mesmo da produção. As regras
abaixo valem onde a produção nunca passa.

1. **As datas vêm dos dados, em ordem crescente, e a ordem é estrita.**
   Candidatas: datas locais anteriores a hoje (fuso da conta) com refeição,
   treino ou mensagem recebida. O calendário não é percorrido: doze datas
   vazias antes de um dia registrado não custam nada. **Linha aberta de
   `daily_snapshots` sem nenhum dos três** (dia só com água, peso, suplemento
   ou medicamento) **não é candidata** (revisão de 2026-10-05): a varredura
   decide isso com as leituras iniciais, pelo mesmo teste de `closeLocalDay`
   (os limites do dia local), não a visita, não gasta consulta nem orçamento
   com ela e a deixa aberta, como a produção; ela sai em `inactiveOpenDates`.
   Antes, cada linha dessas custava 6 consultas em todo pedido, e 30 seguidas
   esgotavam os 4 s antes de a varredura chegar ao dia registrado que vinha
   depois. Exceção: com página cheia (1000 linhas numa das leituras iniciais)
   as linhas lidas podem não ser todas, e toda linha aberta é visitada como
   antes. Uma data só é tentada depois que todas as
   candidatas anteriores foram resolvidas: fechadas (por esta chamada ou por
   outra), sem atividade, ou atrás da fronteira. **Se uma data volta
   `changed_concurrently`** (a linha do dia mudou ou surgiu entre a leitura e a
   escrita: um registro confirmado no meio, ou outro pedido que criou a linha
   de um dia só com mensagem), **a varredura para ali**: essa data e todas as
   posteriores ficam pendentes (`pendingDates`) e o pedido seguinte recomeça
   dela. Motivo (revisão de 2026-10-05): seguir adiante fechava o dia
   posterior, a fronteira (regra 3) passava do dia anterior e ele nunca mais
   fechava, perdendo XP, crédito do bloco e o dia de sequência.
2. **Hoje nunca fecha. Ontem só fecha 30 minutos depois da meia-noite local**
   (a pessoa pode estar confirmando a última refeição do dia). Decisão técnica
   de 2026-10-04. Exceção declarada nas pendências: fuso de offset positivo
   cuja troca de horário de verão cai à meia-noite, no dia da troca.
3. **Fronteira monotônica.** Só fecha data posterior a
   `user_progress.last_active_date` e posterior a todo dia já fechado da
   conta. Uma data antiga aberta que receba registro depois fica aberta, como
   em produção, e é só relatada. Motivo: `computeProgress` continua a
   sequência apenas se `last_active_date` for a véspera, e a finalização grava
   a data fechada como novo `last_active_date`; fechar um dia antigo depois
   dos seguintes reiniciaria a sequência em 1 e andaria a data para trás.
4. **Fechamento atrasado mantém a meta gravada no dia** — decisão técnica de
   2026-10-04, ampliada em 2026-10-05; confirmação do cliente pendente. Um
   fechamento é **atrasado** quando a data é anterior a ontem **ou** quando é
   ontem e a hora local do fechamento é 5 ou mais (o `daily-closer` só fecha
   ontem enquanto a hora local é de 0 a 4). O fechamento atrasado mantém
   `calories_target` e `protein_target` já gravados na linha do dia quando
   não são nulos e só usa a meta do perfil para o campo que estiver nulo (dia
   só com mensagem não tem linha: usa o perfil). Dentro da janela da produção
   (00:30 a 04:59 locais) ONTEM é fechado exatamente como o `daily-closer`:
   grava a meta do perfil na hora do fechamento. **`current_protocol` e o
   déficit programado do crédito vêm do perfil na hora do fechamento nos dois
   casos, atrasado ou não**: a linha do dia não guarda o `deficit_level`, e uma
   troca de protocolo antes de um fechamento atrasado é pendência declarada
   abaixo (travada como está). Motivo: o §1 diz que "a meta do dia fica
   gravada"; a produção nunca fecha fora da madrugada seguinte, então nunca
   regrava a meta de um dia com um perfil alterado depois, e o crédito do
   bloco sai da meta (§2b).
   Caso do revisor (2026-10-05): recomposição, 80 kg, meta gravada 1576, 1500
   kcal por dia, 4 dias sem abrir o app. 05/10 08:00: o primeiro pedido fecha
   01, 02 e 03/10 (orçamento de 3). 08:01: pesagem, 82 kg (a meta do perfil
   passa a 1600). 08:02: o pedido seguinte fecha 04/10. Antes: meta regravada
   1600, crédito 600, bloco 2.328. Agora: atrasado, meta 1576, crédito 576,
   bloco **2.304**, igual ao que quatro fechamentos às 00:30 gravariam.
   O que esta regra NÃO iguala à produção, declarado abaixo: perfil alterado
   no próprio dia depois do primeiro registro (a linha guarda a meta do
   primeiro registro; a produção, às 00:30, regravaria com a do perfil).
   Caso real (staging, conta QA de ganho de massa, 11 dias de 22/09 a 03/10,
   lido em 2026-10-04): com a meta de cada dia o bloco soma **5.885**; com a
   meta do perfil de hoje (2988) somaria 4.836. Os três dias que mudam: 27/09
   gravada 3355 → crédito 3355 − 2683 = 672 (305 com 2988); 28/09 gravada 3361
   → 3361 + 380 − 2810 = 931 (558); 01/10 gravada 3361 → 3361 + 380 − 2259 =
   1.482 (1.109).
5. **Inatividade, uma vez por varredura.** Depois de fechar o que havia, se a
   última data fechável está 2 ou mais dias à frente de `last_active_date` e a
   sequência é maior que zero, a sequência é zerada (mesma regra do
   `daily-closer`: um dia vazio é tolerado, o segundo zera). A atualização é
   condicional aos valores lidos, e o evento `streak.reset_inactive` só é
   gravado quando uma linha mudou. Enquanto houver data com dado esperando
   (orçamento da chamada), a sequência não é zerada.
6. **Escritas condicionais.** A linha do dia é relida imediatamente antes da
   escrita; se já fechou, nada é gravado. Onde a linha existe, a escrita é um
   `update` condicionado a `day_closed = false` e ao `updated_at` lido: um
   registro confirmado no meio faz a tentativa não gravar nada. Dia só com
   mensagem (sem linha): a linha é criada sem sobrescrever uma que tenha
   surgido no meio. Nos dois casos a data volta `changed_concurrently`, a
   varredura para nela (regra 1) e um pedido seguinte a fecha com as somas
   novas, seguida das posteriores.
7. **Exatamente uma vez.** XP, sequência e bloco entram pela RPC atômica; quem
   perde a corrida recebe `applied = false` e não grava evento nenhum (os
   eventos são gravados depois da finalização, nunca antes).
8. **Orçamento por chamada** (API: 3 dias ou 4 s) conta dias fechados e tempo
   decorrido, nunca datas visitadas, e é conferido **só entre um dia e o
   seguinte**: não interrompe um dia em andamento nem uma leitura em curso, e
   por isso não é um teto do tempo do pedido (leitura que falha: pendência
   declarada abaixo). O que sobra fecha no pedido seguinte, em ordem. Uma
   segunda chamada sem nada a fazer não grava nada. `pendingDates` traz o que
   ficou para depois, pelo orçamento ou pela parada das regras 1 e 9.
   **Custo em idas ao banco, por chamada** (contado em
   `day-close-on-request.test.ts`; a API soma uma, a leitura da conta):
   - ontem já fechou: 1;
   - nenhuma data candidata (ontem sem registro, ou só linhas abertas com
     água, quantas forem): 5 leituras; mais 2 escritas se a sequência for
     zerada;
   - por dia fechado com refeição ou treino: até 18 no fechamento atrasado
     com meta gravada (15 leituras, a escrita da linha, a RPC e a inserção dos
     eventos); até 19 dentro da janela da produção ou sem meta gravada (mais a
     leitura das metas do perfil);
   - por dia fechado só com mensagem: 13;
   - mais 3 leituras quando há data sem registro entre o último dia fechado e
     o dia (regra 9);
   - mais 1 na primeira vez que a instância carrega a configuração de cálculo;
   - mais 1 leitura de progresso ao fim da chamada que fechou algum dia.
   Três dias seguidos num pedido da API: 61.
9. **Releitura das datas anteriores antes de finalizar** (revisão de
   2026-10-05). As candidatas são fixadas pelas leituras iniciais. Na
   varredura, junto com a última leitura de `user_progress` e imediatamente
   antes da RPC de finalização de cada data, são relidos refeições, treinos e
   mensagens recebidas entre a primeira data que ainda pode estar aberta (o dia
   seguinte ao último dia fechado ou, sem dia fechado, a primeira data
   permitida) e o início da data que está fechando. Se
   aparece um instante que as leituras iniciais não devolveram, a data volta
   `earlier_date_changed`, **não é finalizada**, a varredura para (como na
   regra 1) e um pedido seguinte fecha a data anterior primeiro. A linha do
   dia já foi gravada nesse ponto e segue aberta (o mesmo estado de uma
   finalização que perde a corrida). Quando a data é o dia seguinte ao último
   fechado não há nada no meio e nenhuma consulta é feita; senão são três
   leituras. Não é feita em simulação, nem com página cheia, nem em
   `closeLocalDay` chamada para uma data só.
   Caso do revisor: 03/10 vazio, 04/10 com 2016 kcal, um pedido às 05:00 de
   05/10 e um jantar de 500 kcal entrando em 03/10 logo depois do 18º acesso
   ao banco desse pedido (04/10 gravado, ainda não finalizado). Antes: 04/10
   fechava, a fronteira passava de 03/10 e ele ficava aberto para sempre (XP
   10, sequência 1, bloco 60). Agora: o pedido para sem finalizar, e o
   seguinte fecha 03/10 (500 < 50% de 1576, sub-registro: crédito 500, XP 10)
   e 04/10 (500 − (2016 − 1576) = 60, XP 10): XP 20, sequência 2, bloco
   **560**, igual à varredura que já enxergasse o jantar. O que sobra,
   declarado abaixo: o registro que entra na última ida ao banco, depois da
   releitura e antes da RPC.

   **Pendência conhecida, sem linha RC (revisão de 2026-10-05, LOW):** uma
   linha de dia aberta só com água não é mais visitada. Se a primeira
   refeição desse dia entra logo depois das leituras iniciais do pedido e não
   há dia posterior com registro, esse pedido zera a sequência por
   inatividade e só o pedido seguinte fecha o dia, com sequência 1 (XP e
   bloco iguais). Antes desta regra o dia fechava no mesmo pedido e a
   sequência continuava. O caso é o mesmo que já acontecia quando o dia não
   tinha linha nenhuma. Caso reproduzido: 02/10 fechado com sequência 5,
   03/10 só com água, refeição de 1500 kcal entrando em 03/10 durante o
   pedido das 08:00 de 05/10.

O que o caminho sob demanda **não faz**: não avança a agenda de reavaliação
(opção `advanceReevaluation`, desligada por padrão); não grava
`daily_closer.skipped`; não grava `daily_snapshots.deficit_accumulated`
(ninguém grava: o gráfico "Bloco 7.700 acumulado" do app segue em zero); não
cria regra para ganho de massa e manutenção (o crédito segue `meta + exercício
− consumido`, pendência do §3); não fecha dia de conta com WhatsApp nem de
conta sem fuso (API); não recredita dia já fechado; não visita nem fecha
linha de dia sem refeição, treino ou mensagem recebida; não põe prazo nas
próprias leituras.

#### Conta de um dia em cada protocolo (golden)

Pessoa do teste: homem, 80 kg, 180 cm, 40 anos, atividade leve. BMR 1730.
XP pela regra gravada em staging (igual ao padrão do código): 10 + 5 com
treino + 5 com proteína ≥ 100 g.

| Protocolo | Meta | Dia | `daily_balance` | Crédito | XP |
|---|---|---|---|---|---|
| Recomposição (déficit 500) | 1730 × 1,2 − 500 = 1576 | 1809 kcal, treino 565, 100 g | 1809 − 1576 − 565 = −332 | 500 − (−332) = **832** | 20 |
| Ganho de massa | 1730 × 1,375 × 1,05 = 2498 | 2600 kcal, treino 300, 140 g | 2600 − 2498 − 300 = −198 | 0 − (−198) = **198** | 20 |
| Manutenção | 1730 × 1,375 = 2379 | 2100 kcal, treino 250, 100 g | 2100 − 2379 − 250 = −529 | 0 − (−529) = **529** | 20 |

A linha da recomposição é o exemplo do cliente do §2b (500 − 233 + 565 = 832).
Semana inteira fechando dia a dia: recomposição termina com 105 XP, nível 2,
sequência 7, bloco 2.925 e a medalha "Primeira Semana"; ganho de massa, 100 XP
e bloco 598; manutenção, 105 XP e bloco 587.

#### O que a simulação deve imprimir para staging (lido em 2026-10-04)

Só três contas ativas têm o que fechar. Com `--from 2026-09-17`, rodando depois
de 00:30 de 05/10 e sem registro novo:
- **conta-10 (ganho de massa):** 11 dias, de 22/09 a 03/10 (25/09 sem
  registro), todos atrasados, meta gravada mantida. XP 20, 15, 20, 20, 15, 20,
  20, 15, 20, 15, 20 = 200, nível 2 a partir de 28/09; crédito 300, 134, 35,
  392, 672, 931, 219, 814, 1.482, −447, 1.353 = bloco **5.885**; sequência 1,
  2, 3, 1, 2, 3, 4, 5, 6, 7, 8; "Primeira Semana" em 02/10. O dia 04/10 ainda
  estava em andamento na leitura (1018 kcal, treino 322, meta gravada 2980):
  se não mudou, entra como 12º dia com XP 20, crédito 0 (1018 < 50% da meta),
  sequência 9, XP 220, bloco 5.885. **Mudou com a regra 4 de 2026-10-05:**
  rodando em 05/10 entre 00:30 e 04:59 (horário de São Paulo) esse dia é
  "ontem" dentro da janela e a meta do fechamento é a do perfil (2988); a
  partir das 05:00 de 05/10 é atrasado e fica a gravada (2980) — antes, a
  gravada só valia a partir de 06/10. O crédito é 0 nos dois casos, e os
  outros números das três contas não mudam.
- **conta-11 (ganho de massa):** 27/09 só com mensagem no Flow (linha criada;
  meta do perfil, 2214 / 111,6 pela fórmula do §1 aplicada em SQL): XP 10,
  crédito 0, sequência 1. 30/09: 383 kcal contra 2214 gravada, sub-registro:
  XP 10, crédito 0, sequência 1. Sequência zerada por inatividade. Fim: 20 XP,
  sequência 0, maior 1, bloco 0.
- **conta-09 (recomposição):** 17/09 só com mensagem (meta do perfil 1563 /
  112,5): XP 10, crédito 0, sequência 1; zerada por inatividade. Fim: 10 XP,
  sequência 0, maior 1, bloco 0.
- As outras quatro contas ativas não têm dado: nada a fechar, nada gravado.
  As quatro contas bloqueadas são puladas.

Esses números vêm de SELECTs e dos goldens; a simulação **não foi rodada**
contra o banco e nada foi gravado. Gravar exige autorização nomeada do Eduardo.

- Código: `packages/agent/src/day-close.ts`,
  `packages/core/src/engine/day-status.ts`,
  `apps/admin/src/lib/mobile-api/day-close-on-request.ts`,
  `scripts/close-open-days.ts`.
- Testes: `packages/agent/src/__golden__/audit-10-04-app-day-close.test.ts`
  (semana por protocolo fechada às 00:30 e às 08:00, dias atrasados, registro
  retroativo, três dias inativos, ontem fechado depois das 05:00 com pesagem
  no meio, varreduras intercaladas com registro no último dia e no dia do
  MEIO, dois pedidos simultâneos em conta com dia só de mensagem, regra dos
  30 minutos em America/Sao_Paulo e Asia/Kolkata, caracterização de
  Africa/Cairo e Asia/Beirut, dias abertos de staging, e os dois casos da
  revisão de 2026-10-05: 10, 30 e 45 linhas só com água antes de um dia com
  refeição, e o jantar que entra em 03/10 depois do 18º acesso ao banco);
  `packages/agent/src/day-close.test.ts` (mecânica, inclusive a releitura da
  regra 9 e a linha só com água);
  `packages/inngest-functions/src/functions/daily-closer.parity.test.ts`
  (paridade com o fechador de produção, às 00:30 e às 04:59 locais, a borda
  das 05:00 e a divergência declarada das 50 mensagens);
  `apps/admin/src/lib/mobile-api/day-close-and-evaluation-access.read-retry.test.ts`
  (cliente supabase-js real com `fetch` falso: os ~7 s de uma leitura que
  falha);
  `apps/admin/src/lib/mobile-api/day-close-on-request.concurrent.test.ts`
  (os handlers reais de `GET /today` e `GET /progress` ao mesmo tempo);
  `packages/agent/src/day-close.no-send.test.ts` (prova estática de que não
  envia); `packages/agent/src/day-close.operator-script.test.ts`;
  `apps/admin/src/lib/mobile-api/day-close-on-request.test.ts` (travas e o
  custo em idas ao banco de cada tipo de pedido) e os `route.test.ts` de
  `today` e `progress`.

> RC F — cenário gráfico "Bloco 7.700 acumulado" do app (lê `daily_snapshots.deficit_accumulated`, coluna que o fechamento não grava) NÃO coberto nesta PR (pendência da audit 2026-10-04). Continua em zero com os dias fechados, em qualquer ambiente.

> RC F — cenário crédito do bloco em ganho de massa e manutenção (o fechamento credita meta + exercício − consumido; o cliente escreveu em 08/05/2026 que nesses protocolos o bloco de 7.700 "é substituido pelo bloco acumaldo de Kcal em 14 dias") NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado, e agora visível no app de avaliação: comer abaixo da meta enche o bloco. Travado abaixo como está.

> RC F — cenário agenda de reavaliação de 14 dias (`advance_reevaluation_schedule`) no caminho sob demanda NÃO coberto nesta PR (pendência da audit 2026-10-04). Desligada por padrão: o contexto de reavaliação do Flow nunca foi exercitado no app. `next_reevaluation` fica nulo em conta fechada só por este caminho.

> RC F — cenário convergência dos dois roteiros (o worker de produção passar a chamar `closeLocalDay`) NÃO coberto nesta PR (pendência da audit 2026-10-04). `daily-closer.ts` não foi tocado; a igualdade entre os dois é travada pelo teste de paridade.

> RC F — cenário dia antigo aberto que recebe registro depois de um dia posterior já ter fechado NÃO coberto nesta PR (pendência da audit 2026-10-04). Fica aberto, como em produção: não entra em sequência, XP nem bloco; a varredura só o relata.

> RC F — cenário primeiro registro retroativo num dia anterior aberto que entra na última ida ao banco antes da finalização do dia posterior (depois da releitura das datas anteriores, antes da RPC) NÃO coberto nesta PR (pendência da audit 2026-10-04). O dia posterior fecha, a fronteira passa do anterior e ele fica aberto para sempre, sem XP, bloco nem sequência, como na linha anterior. A releitura (regra 9) cobre o registro que entra antes dela, e não é feita com página cheia (1000 linhas numa leitura). Travado abaixo como está, com o caso do revisor deslocado para essa janela: 03/10 vazio, 04/10 com 2016 kcal, jantar de 500 kcal em 03/10 no instante da RPC: XP 10, sequência 1, bloco 60, e 03/10 aberto.

> RC F — cenário refeição ou treino registrado num dia JÁ fechado NÃO coberto nesta PR (pendência da audit 2026-10-04). Igual à produção: o dia não é recreditado e `calories_consumed` passa a divergir do que foi creditado.

> RC F — cenário dia só com água, peso, suplemento ou medicamento (sem refeição, treino nem mensagem recebida) NÃO coberto nesta PR (pendência da audit 2026-10-04). Conta como dia inativo, como em produção: a linha fica aberta e a sequência quebra. A varredura não visita essa linha: ela não custa consulta, não gasta o orçamento e não segura o dia seguinte. Caso do revisor travado abaixo: 30 linhas só com água e depois 04/10 com refeição fecham 04/10 no primeiro pedido, com 28 idas ao banco; antes, com o relógio simulado do revisor (150 ms por linha visitada), eram 161 consultas por pedido, 26 linhas visitadas e 04/10 não fechava em nenhum de três pedidos seguidos. Com página cheia (1000 linhas numa leitura) toda linha aberta volta a ser visitada.

> RC F — cenário status `incomplete_no_response` num fechamento atrasado (o padrão de refeições é o dos 14 dias anteriores a AGORA, não à data fechada) NÃO coberto nesta PR (pendência da audit 2026-10-04). Só alcança dia com lembrete de lacuna gravado, que conta do app em staging não tem.

> RC F — cenário fechamento atrasado (data anterior a ontem, ou ontem a partir das 05:00 locais) depois de troca de protocolo ou de `deficit_level` NÃO coberto nesta PR (pendência da audit 2026-10-04). A meta gravada no dia é mantida; o déficit programado do crédito e o `current_protocol` gravado são os do perfil na hora do fechamento. Travado abaixo como está: recomposição trocada para ganho de massa às 08:01, ontem (1500 kcal, meta gravada 1576) fecha às 08:02 com meta 1576, protocolo `ganho_massa` e crédito 76; o fechador de produção teria gravado `recomposicao` e 576.

> RC F — cenário perfil alterado no PRÓPRIO dia depois do primeiro registro (pesagem ao meio-dia) e dia fechado atrasado NÃO coberto nesta PR (pendência da audit 2026-10-04). O fechamento atrasado mantém a meta gravada na linha, que é a do primeiro registro do dia (a pesagem não regrava a linha); o fechador de produção, às 00:30, regravaria com a meta do perfil. Travado abaixo como está: 80 → 82 kg às 13:00 de ontem, 1500 kcal: fechado às 08:00 fica meta 1576 e crédito 576; fechado às 00:30 fica meta 1600 e crédito 600.

> RC F — cenário duas varreduras simultâneas que enxergam datas diferentes (um registro retroativo entra entre as duas leituras) NÃO coberto nesta PR (pendência da audit 2026-10-04). A finalização grava valores absolutos: o progresso de um dos dois dias pode ser sobrescrito. Resolver exige a RPC conferir a versão anterior (migration).

> RC F — cenário registro confirmado entre a gravação da linha do dia e a finalização NÃO coberto nesta PR (pendência da audit 2026-10-04). Mesma janela da produção, com uma ida ao banco de largura.

> RC F — cenário eventos de telemetria intermediários (`streak.reset_inactive` de cada intervalo antigo e `daily_closer.skipped`) NÃO coberto nesta PR (pendência da audit 2026-10-04). O caminho sob demanda grava um zeramento por varredura e nunca grava "skipped"; o `user_progress` final é o mesmo.

> RC F — cenário dia sem refeição nem treino com mais de 50 mensagens em que as 50 lidas pelo fechador de produção são todas enviadas NÃO coberto nesta PR (pendência da audit 2026-10-04). Divergência DENTRO da janela da produção: o `daily-closer` lê até 50 mensagens do dia, sem filtro de direção e sem ordenação, e procura uma recebida entre elas; o caminho sob demanda pergunta por uma mensagem recebida com o filtro `direction = 'in'`. Travado como está no teste de paridade, com o caso do revisor: 04/10 com 50 mensagens enviadas seguidas de 3 recebidas, fechado às 00:30 de 05/10 (America/Sao_Paulo). Produção: dia inativo, nada gravado além de `daily_closer.skipped`. Caminho sob demanda: linha criada e fechada, XP 10, sequência 1, `last_active_date` 04/10. Com 49 enviadas e 1 recebida os dois voltam a concordar. A leitura da produção não foi copiada.

> RC F — cenário leitura do fechamento sob demanda que falha por erro de rede ou HTTP 503 ou 520 NÃO coberto nesta PR (pendência da audit 2026-10-04). O orçamento de 4 s é conferido só entre um dia e o seguinte e nenhuma leitura tem prazo de cancelamento. O cliente de banco (supabase-js 2.105.1) repete todo GET três vezes, esperando 1, 2 e 4 s (ou o que o cabeçalho `Retry-After` de um 503 mandar), antes de devolver o erro: com o interruptor ligado, `GET /today` e `GET /progress` ficam cerca de 7 s parados e depois respondem com o que está gravado. Caso do revisor travado em day-close-and-evaluation-access.read-retry.test.ts (cliente real, `fetch` falso, relógio simulado): 503 sem `Retry-After` em `users`, em `user_progress` ou em `meal_logs`, 4 pedidos e 7 s cada. HTTP 500 não é repetido; a RPC e as escritas (POST e PATCH) também não. Com o interruptor ausente nenhuma consulta é feita.

> RC F — cenário fechador de PRODUÇÃO em fuso de meia hora e em dia de troca de horário de verão NÃO coberto nesta PR (pendência da audit 2026-10-04). Não foi tocado: usa "agora − 24 h" e ticks no minuto 30 UTC. O caminho sob demanda usa a data do calendário e espera 30 min depois da meia-noite local (travado abaixo em America/Sao_Paulo e Asia/Kolkata), com a exceção da linha seguinte.

> RC F — cenário fuso de offset positivo cuja troca de horário de verão cai à meia-noite (Africa/Cairo em 24/04/2026, Asia/Beirut em 29/03/2026) NÃO coberto nesta PR (pendência da audit 2026-10-04). `localMidnightUtc` (auxiliar antigo, usado também pelo fechador de produção e não tocado) devolve o início desse dia uma hora adiantado: a última hora da véspera é contada no dia da troca e, nesse dia, ontem fica fechável já no primeiro instante, sem a espera de 30 min. Hoje nunca fecha. Travado abaixo como está.

> RC F — cenário botão "Fechar dia" do painel admin (marca o dia como fechado sem aplicar progresso) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado. Um dia fechado assim vira fronteira: os dias abertos anteriores a ele não fecham mais.

> RC F — cenário banco real (cliente supabase-js contra o Postgres de staging: filtro por `updated_at`, `upsert` com `ignoreDuplicates`, a RPC e a coluna gerada de verdade) NÃO coberto nesta PR (pendência da audit 2026-10-04). Toda a suíte usa banco em memória; nada foi executado contra banco algum. O cliente supabase-js real foi conferido à mão em 2026-10-05 com `fetch` falso, sem rede e sem banco: a escrita da linha existente sai como `PATCH daily_snapshots?id=eq…&day_closed=eq.false&updated_at=eq…`, a criação como `upsert` com `resolution=ignore-duplicates`, e zero linhas devolvidas encerram a tentativa sem finalizar.

> RC F — cenário dias abertos de staging fechados de fato NÃO coberto nesta PR (pendência da audit 2026-10-04). Nenhuma escrita foi feita e a simulação não foi rodada contra o banco; os números esperados vêm de SELECTs de 2026-10-04 e do último bloco deste arquivo.

> RC F — cenário app no aparelho (Progresso, bloco e resumo semanal do Flow depois de um fechamento) NÃO coberto nesta PR (pendência da audit 2026-10-04). Nada foi executado no aparelho, no simulador nem no BFF publicado.

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
  - **Só no Flow** (2026-10-04, §2c): o contexto também entrega o balanço do
    dia contra o gasto, que é um segundo número verdadeiro e pode ter sinal
    diferente do de comida (ganho de massa com 2900 de 2980: restam 80 **e**
    superávit de 62; recomposição 19/05: excedente de 233 **e** déficit de
    832). A frase que cita esse balanço com o número exato (±1) e o sinal certo
    ("superávit de 62 kcal", "62 kcal de superávit") não é reescrita. Qualquer
    outro número continua corrigido para a linha de comida. No WhatsApp a
    reconciliação é a de antes (a opção `dayBalance` nunca é passada); com o
    interruptor do §2c desligado, o Flow também volta ao de antes. Em dia de
    troca de protocolo (§2c) o balanço do dia é o número legado e nenhuma
    frase é poupada: com 3000 consumido contra 2799 gravada, "déficit de 299
    kcal" volta a ser corrigido para "excedente de 201 kcal".

### 4a. Estado diário para clientes mobile

- Fonte pura: `@mpp/core/daily-state` (`buildDailyState`).
- Serviço de aplicação: `@mpp/agent/daily-state-service`
  (`loadOfficialDailyState`).
- API: `GET /api/mobile/v1/today`.
- `remaining_food_kcal` e `food_excess_kcal` derivam de `eatingBalance` (§2a):
  contra a meta, sem exercício, em todo protocolo. Não mudaram.
- `daily_balance_kcal` (a linha "Balanço do dia" do app, antes "Déficit
  líquido") deriva de
  `dayEnergyBalance` (§2c): `consumido − gasto do dia`, por protocolo — dito
  pelo cliente em 20/01/2026, 22/02/2026, 23/02/2026 e 09/03/2026; implementado
  em 2026-10-04 a pedido do Eduardo; confirmação do cliente pendente.
  Recomposição: `consumido − (meta + déficit programado) − exercício`. Ganho de
  massa: `consumido − round(meta ÷ multiplicador)`, sem exercício. Manutenção:
  `consumido − meta`, sem exercício. Protocolo não definido: `consumido − meta
  − exercício` (como antes). O protocolo é o da linha do dia quando ela o tem
  (só depois do fechamento), senão o do perfil; o déficit programado é a
  expressão do fechamento aplicada a ESSE protocolo, com o `deficit_level` do
  perfil; o multiplicador vem da configuração carregada, lido como número.
  As entradas vêm de `resolveDayBalanceInputs`, a mesma função que o Flow usa
  (§4b), então a tela e o Flow dizem o mesmo número também num dia fechado cuja
  linha traz protocolo diferente do perfil.
- **Dia de troca de protocolo** (§2c): quando a meta gravada na linha do dia
  está mais perto da meta que o perfil dá agora em OUTRO protocolo do que da
  meta do protocolo efetivo, `daily_balance_kcal` é o número legado
  (`consumido − meta gravada − exercício`), `daily_balance_reference_kcal` é a
  meta gravada e `daily_balance_includes_exercise` é `true`. O `protocol`
  publicado não muda. Um peso novo no dia não dispara isso.
- Dois campos **aditivos** dizem contra o que o número foi medido:
  `daily_balance_reference_kcal` (o gasto de referência, sem exercício; sempre
  inteiro, também no caminho legado) e
  `daily_balance_includes_exercise` (`true` quando o exercício do dia é
  subtraído além da referência). Sem meta, os três são `null`.
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
- A versão da semântica é `bodyflow.daily-state.v3` (2026-10-04). A v3 muda
  **só** a fórmula de `daily_balance_kcal` (§2c) e acrescenta os dois campos
  acima; metas, consumo, `remaining_food_kcal`, `food_excess_kcal`,
  `exercise_kcal`, `daily_balance_status`, hidratação, rotina e bloco 7700 são
  idênticos à v2. (A v2 tinha mudado só o contrato de suplementos e
  medicamentos em relação à v1.) O estado não calcula dose, prescrição nem
  recomendação, e o app nunca replica estas fórmulas. O iPhone trata a versão
  como texto livre e ignora campos desconhecidos. No código do app (commit
  separado do mesmo dia, 9624cd5; ainda não verificado no aparelho) a linha é
  "Balanço do dia", o valor sai em palavras ("Déficit de N kcal" / "Superávit
  de N kcal") e a legenda vem de `daily_balance_includes_exercise` (campo
  ausente = "Exercício incluído"). Um build anterior continua funcionando, com
  o rótulo "Déficit líquido" e a legenda fixa "Exercício incluído". O que fica
  aberto no app está na pendência do §2c (VoiceOver lê o valor duas vezes
  nessa linha; frases da trilha e do tour sobre o bloco de 7.700 para todo
  protocolo; número de dia aberto).

### 4b. Estado do dia que o MODELO lê no Flow (contexto e tool)

**C1 — apresentação pública do Flow (2026-10-08, somente alteração local).**
O contexto factual e `consulta_metricas` do canal autenticado não entregam
metabolismo basal, gasto energético total, massa magra estimada, fator ou nome
de fórmula ao modelo. Gordura corporal mantém o percentual, com rótulo público.
As contas internas, metas oficiais do snapshot, sinais e balanços dos §§2a–2c
continuam iguais; o valor de referência desses balanços não vira uma meta.
O schema da ferramenta é projetado em cópia, sem mudar o objeto compartilhado.

As perguntas isoladas `qual é o meu BMR?` e `qual fórmula você usa?`, e seus
equivalentes reconhecidos em inglês, recebem as metas oficiais sem chamar o
modelo. Perguntas mistas seguem para o modelo e ferramentas. Sem meta disponível,
o Flow informa a ausência; não calcula nem inventa substituto. O idioma da
pergunta reconhecida prevalece sobre o locale salvo.

As cópias de regras/RAG, resumo e mensagens anteriores do assistente omitem
afirmações técnicas conhecidas, preservando dados públicos e restrições adjacentes.
As falas do paciente e o histórico persistido ficam intactos. A política proíbe
reconstruir as contas. Após nomes públicos e reconstrução de sugestões, a saída
passa pelo filtro de vocabulário/equações conhecidas; não se troca um número
basal pelo rótulo de meta. Sugestões mantêm identificadores, itens públicos e
instrução de revisão, sem alterar o rascunho gravado. Isso não equivale à validação
de qualquer redação possível do modelo; smoke de staging continua necessário.

Não há backfill de mensagens, resumos ou planos. As rotas mobile `GET/POST
/flow/chat` também projetam o texto do assistente: no GET depois da leitura e,
no POST, **depois da idempotência**, cobrindo replay de mensagem e de resposta
HTTP antiga. O texto do usuário, IDs, ordem, quantidade, datas, estados, metas
públicas históricas e ponteiro do rascunho permanecem iguais. Nenhuma busca de
metas atuais nem escrita de saneamento é acrescentada. O POST mantém suas
gravações/transições normais; o cache HTTP original continua intacto.

Uma mensagem antiga inteiramente técnica recebe orientação neutra para Hoje e
Perfil, com o mesmo ID; não informa que a meta está ausente nem insere números
de outro dia. Idioma histórico reconhecível é preservado; grafias ambíguas usam
o locale já autenticado. Resposta HTTP 2xx malformada é recusada com
`500 flow_response_invalid`, sem devolver o corpo bruto; erros existentes
mantêm status e headers. A janela GET continua limitada a 50 mensagens.

Conteúdo antigo já em memória do iOS, fora de uma nova leitura, não recebe
atualização retroativa nesta mudança. O canal WhatsApp permanece legado, com
seus fixtures/hash de request e contexto preservados. Copy pública,
confirmação clínica e smoke de staging seguem seus gates; testes locais não os
substituem.

A regra do §2 vale também para o texto entregue ao modelo. Um balanço sem
rótulo vira "o treino já foi descontado, pode comer mais".

Origem: iPhone, staging, 2026-10-04, chat do Flow (conta QA A). Paciente:
"Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a mais?".
Flow: "Sim! Sua meta já considera esse gasto…". Dia naquele turno: meta 2980,
consumido 541, exercício 322, `daily_balance` −2761. O contexto entregava só
`Balanço calórico de hoje: -2761 kcal` (o líquido do §2b, com exercício); o
balanço de comida do §2a (restam 2439) não aparecia em lugar nenhum.

**Nenhuma fórmula mudou** na correção do relato: mudou o rótulo, a instrução e
quem responde a pergunta direta. Depois, no mesmo dia, a linha do balanço do
dia (e só ela) passou a seguir o §2c. Tudo abaixo vale SÓ no canal Flow
(`historyProvider === 'mobile_flow'` / `assistantIdentity === 'flow'`); o
WhatsApp está igual.

- **Contexto do turno** (`flowEnergyContextLines`,
  `packages/agent/src/flow-energy-context.ts`, chamado por `formatUserContext`):
  - `Para COMIDA hoje (meta − consumido, SEM exercício): restam X kcal` ou
    `… (consumido − meta, SEM exercício): excedente de X kcal acima da meta` → §2a.
  - `Exercício hoje: E kcal queimadas — NÃO aumenta a meta e NÃO entra no que
    resta para comida`.
  - A linha do balanço do dia segue o §2c (dita pelo cliente em 20/01/2026,
    22/02/2026, 23/02/2026 e 09/03/2026; implementada em 2026-10-04 a pedido do
    Eduardo; confirmação do cliente pendente). O prefixo `Balanço calórico de
    hoje` é mantido nas três formas:
    - **recomposição:** `Balanço calórico de hoje COM exercício (consumido −
      gasto do dia; gasto do dia = R kcal de gasto de referência + E kcal de
      exercício): N kcal (negativo=déficit, positivo=superávit) — é o déficit
      ou superávit real do dia até agora, provisório até o dia fechar; o
      crédito no bloco 7700 só acontece no fechamento do dia e este número NÃO
      é o que resta para comer`. Em 20/05 (1407 / 1843 / 467, déficit 500): R
      2343, N −1403 (antes −903, contra a meta). A linha continua sem dizer
      que o número "é o que o fechamento usa": de manhã o fechamento pode
      creditar só o déficit programado ou nada (sub-registro, dia incompleto;
      §3). A versão de antes do §2c dizia `o crédito do bloco 7700 só é
      calculado no fechamento do dia (déficit programado − este número)`.
    - **ganho de massa e manutenção:** `Balanço calórico de hoje (consumido −
      gasto de referência de R kcal; o exercício já está no fator de atividade
      e não é somado): N kcal (negativo=déficit, positivo=superávit) — NÃO é o
      que resta para comer`. Sem "7700" e sem "bloco". Conta QA: R 2838, N
      −2297 (antes `COM exercício (consumido − meta − exercício): -2761`).
    - **protocolo não definido** (ou interruptor desligado): a linha de antes,
      `Balanço calórico de hoje COM exercício (consumido − meta − exercício): N
      kcal … — NÃO é o que resta para comer`.
    - **dia de troca de protocolo** (§2c; a meta gravada é de outra regra): a
      mesma linha legada, com o número legado, igual ao da tela Hoje. Em
      recomposição ela sai SEM a frase "o crédito do bloco 7700 só é calculado
      no fechamento do dia (déficit programado − este número)": o fechamento
      regrava a meta, então essa conta seria falsa nesse dia. Exemplo (2799
      gravada, recomposição ao meio-dia, 2500 consumido): `… (consumido − meta
      − exercício): -299 kcal (negativo=déficit, positivo=superávit) — NÃO é o
      que resta para comer` (antes: `gasto do dia = 3299 kcal de gasto de
      referência + 0 kcal de exercício): -799 kcal … é o déficit ou superávit
      real do dia até agora`).
    - O protocolo da linha é o **efetivo** (o da linha do dia quando ela o
      tem, senão o do perfil), o mesmo da tela Hoje. O pipeline lê
      `current_protocol` e a meta gravada do dia só no canal Flow
      (`UserContext.flowDayRow`) e entrega os dois, com as três metas que o
      perfil dá agora, a `flowDayBalanceInputs` nas quatro chamadas (contexto
      com e sem linha do dia, tool, reconciliação da prosa).
  - Sem linha do dia em `daily_snapshots`, saem só a linha de comida e a REGRA
    (nenhum "déficit de 2980" de manhã, que o contexto antigo também não tinha).
  - `REGRA: exercício NÃO libera comida nem apaga excedente. …`. Abaixo da meta
    ou na meta exata: `o que o paciente pode comer é só o que está na linha
    "Para COMIDA"` e `mostre meta, consumido e o que resta para comida`. Com
    excedente de comida: `a linha "Para COMIDA" mostra excedente, então não
    resta nada para comida hoje` e `mostre meta, consumido e o excedente` (a
    regra não pede um "resto" que o contexto não tem). O bloco 7700 só é citado
    em recomposição.
  - Os dois números saem de `eatingBalance`/`dayEnergyBalance` sobre a MESMA
    meta impressa no contexto (a do snapshot do dia; sem ela, a do perfil),
    como na tela Hoje (§4a). A coluna `daily_balance` não é usada no Flow: num
    snapshot sem meta gravada ela vale `consumido − 0 − exercício` e não bate
    com a meta impressa.
- **`consulta_progresso` no Flow** devolve `energia_hoje` (`meta_kcal`,
  `consumido_kcal`, `restam_para_comida_kcal` ou `excedente_de_comida_kcal`,
  `exercicio_kcal`, o balanço do dia, `regra`) e não expõe a chave crua
  `daily_balance` em `hoje`. O balanço do dia sai com uma chave por
  significado (§2c): recomposição → `gasto_de_referencia_kcal` +
  `balanco_do_dia_com_exercicio_kcal`; ganho de massa e manutenção →
  `gasto_de_referencia_kcal` + `balanco_do_dia_sem_exercicio_kcal`; protocolo
  não definido → só `balanco_do_dia_com_exercicio_kcal` (como antes). A `regra`
  diz o que a chave é e termina em "Não é o que resta para comer."; sem linha
  do dia não há chave de balanço e a regra não cita nenhuma. O pipeline entrega
  protocolo efetivo, multiplicador, déficit programado e o veredito sobre a
  meta gravada à tool em `ToolContext.flowDayBalance` (só no Flow). Em dia de
  troca de protocolo a tool devolve só `balanco_do_dia_com_exercicio_kcal`
  (o número legado) com a regra de antes, como no protocolo não definido. O
  multiplicador da configuração chega à tool: com
  `calc.ganho_massa_surplus_multiplier` 1,10 e a meta do dia 2980 gravada sob
  ele, `gasto_de_referencia_kcal` 2709 e `balanco_do_dia_sem_exercicio_kcal`
  −2168 (travado no golden; sem o argumento a tool diria 2838 / −2297). No
  WhatsApp o retorno segue `{ progresso, hoje }` com a linha crua.
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
  - **Resposta a uma pergunta do Flow** (`answersFlowQuestion`, chamado pelo
    pipeline depois do predicado, com o histórico já carregado em
    `ctx.recentMessages`): o sistema NÃO responde quando o texto bruto da
    mensagem não tem nenhum `?` **e** a última resposta do Flow no mesmo dia
    termina em pergunta (depois do último `?` dela só há espaço, aspas,
    parêntese, Markdown ou emoji). Nesse caso a mensagem é o paciente
    respondendo, não perguntando, e vai para o modelo. Origem (revisão de
    2026-10-04, 3ª rodada): Flow "Você está 2.439 kcal abaixo da meta de hoje.
    Está conseguindo comer nas refeições principais?" → paciente de ganho de
    massa "Treinei hoje e dá pra comer mais" → lia "O treino não aumenta o que
    você pode comer hoje…" e o modelo nunca via a mensagem. Só a ÚLTIMA
    resposta do Flow conta (se depois da pergunta o Flow disse outra coisa, não
    há pergunta pendente); pergunta do Flow de dia anterior não conta (o
    histórico entrega essa linha datada); mensagem com `?` em qualquer ponto
    continua pergunta e recebe a resposta do sistema — inclusive a frase exata
    do relato. Consequência aceita: a pergunta ditada sem `?` ("treinei hoje
    posso comer mais") logo depois de uma pergunta do Flow também vai para o
    modelo (pendência declarada abaixo).
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
      queimei|gastas|queimadas] [a mais]` (com as duas condições de "de quem
      são as calorias" logo abaixo);
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
  - `comer (essas|as) calorias` SEM número e sem complemento que diga de quem
    são ("do treino", "que gastei", "que queimei", "gastas", "queimadas"), com
    ou sem "a mais": só casa quando o relato da mesma mensagem diz o gasto
    (`gastei|queimei N kcal`). "Treinei e gastei 322 kcal. Posso comer essas
    calorias?" casa; "Treinei hoje. Posso comer essas calorias?", "… essas
    calorias a mais?" e "… as calorias?" não casam — depois de "Um açaí médio
    com granola tem cerca de 500 kcal." apontam para o açaí (revisão de
    2026-10-04, 3ª rodada). Duração ou distância no relato ("treinei 1 hora",
    "corri 10 km") não substituem o gasto. `repor`/`comer de volta as
    calorias` não mudou: o verbo já aponta para o que foi gasto.
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
    afirmação terminada em `.` ou `!`. Falso por regra (acima): número que não
    repete o gasto do relato e "essas calorias" sem número nem gasto dito.
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
  de treino, açaí de 500 kcal; as da 3ª rodada, no mesmo histórico — as quatro
  respostas com "dá pra" sem pontuação depois de "Está conseguindo comer…?"
  vão para o modelo, a frase exata do relato nesse mesmo histórico e as
  perguntas ditadas sem pergunta pendente do Flow seguem com o sistema, e
  "essas calorias"/"as calorias" sem número depois do açaí vão para o modelo;
  treino gravado diferente do digitado; e a fiação
  de `consulta_progresso` — o modelo
  chama a tool num dia sem meta gravada e lê `energia_hoje` com meta e restam,
  sem `daily_balance`), `flow-energy-context.test.ts` e
  `exercise-food-guard.test.ts` (tabelas casa / fora da gramática de propósito
  / não casa, com todas as mensagens citadas na revisão; `answersFlowQuestion`
  isolado).
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
> treino aumenta minha meta?", "posso comer as calorias do treino?"), "essas
> N kcal" que não repete o gasto do relato e "essas calorias"/"as calorias"
> sem número quando o relato não diz o gasto: todas vão para o modelo com o
> contexto corrigido. A lista está em `exercise-food-guard.test.ts`
> (`OUTSIDE_THE_GRAMMAR`), afirmada como falso.

> RC A — cenário mensagem mista (relato do treino + pergunta direta + outro pedido, sintoma, alimento ou segunda pergunta) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A resposta do sistema não entra; quem responde é o modelo, com o contexto
> corrigido.

> RC A — cenário resposta do MODELO com o contexto corrigido NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Não é provada por teste nem por evento. Vale para tudo que fica fora da
> gramática (inclusive as afirmações terminadas em "." ou "!"), para a
> mensagem sem `?` enviada logo depois de uma pergunta do Flow e para a
> pergunta repetida quando a última resposta do Flow é o mesmo texto que o
> sistema daria agora. Só nova rodada no iPhone/staging prova.

> RC A — cenário redação da resposta do sistema e da REGRA NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Texto clínico para o paciente, ainda sem aprovação do Roberto. Inclui a frase
> "Não encontrei treino registrado hoje…", "As N kcal de treino registradas
> hoje…", "Esse é o valor registrado no app.", a linha do balanço com exercício
> em recomposição ("o crédito do bloco 7700 só é calculado no fechamento…") e
> o caso de ganho de massa abaixo da meta.

> RC A — cenário exercício no balanço de ganho_massa/manutenção fora do Flow e da tela Hoje (WhatsApp, bom dia, fechamento, consulta_resumo_periodo) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> No Flow e na tela Hoje passou a valer o §2c (regra dita pelo cliente;
> confirmação pendente), com as pendências RC R1/R2 de lá. A resposta do
> sistema à pergunta direta não mudou: só diz que o gasto "fica à parte"; o
> bloco 7700 só é citado em recomposição e só com treino gravado no dia.

> RC A — cenário `consulta_resumo_periodo` (média de `daily_balance` sem rótulo), "balanço de ontem" e resumo persistente do paciente NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC A — cenário afirmação sem pontuação final ("treinei hoje e posso comer mais") quando o Flow NÃO tinha acabado de perguntar algo NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Sem `?` e sem marca no fim o predicado não separa a pergunta ditada da
> afirmação. O que resta: essa afirmação ainda recebe a resposta do sistema
> quando a última resposta do Flow no dia NÃO termina em pergunta (primeira
> mensagem do dia, Flow tinha afirmado algo, ou a pergunta do Flow é de dia
> anterior). Também "Eu treinei hoje e por isso posso comer mais" e "Treinei
> hoje dá pra comer mais". Quando o Flow tinha acabado de perguntar algo, vai
> para o modelo; com "." ou "!" no fim vai sempre para o modelo. Travado como
> está em `exercise-food-guard.test.ts` (`MUST_MATCH`) e no golden.

> RC A — cenário pergunta ditada sem `?` logo depois de uma pergunta do Flow NÃO coberto nesta PR (pendência da audit 2026-10-04).
> "treinei hoje posso comer mais" enviada quando a última resposta do Flow no
> dia termina em pergunta vai para o modelo (com o contexto corrigido), não
> para o sistema: sem `?` não dá para separá-la da resposta do paciente.
> Travado como está no golden.

## 5. Defesas anti-erro (não remover)

- **Fake-registration detector** (`pipeline.ts`): se o LLM diz "registrado" com
  card mas NÃO chamou `registra_refeicao`/`registra_treino` → re-prompt forçado.
  Sem isso, refeições viram fantasma (card mostra, banco não tem). Eventos:
  `llm.fake_write_detected` / `llm.fake_write_unresolved`.
  - **Turno em que `define_protocolo` ou `define_meta_peso` gravou, ou recusou
    a meta pelo piso** (revisão de 2026-10-04): a resposta fica fora da regra
    genérica "verbo de registro + kcal ou 🔥/💪/📊" só quando as duas coisas
    valem: (1) todo verbo de registro ou correção dela está **ligado ao nome
    da meta ou do protocolo**, pelas regras de palavra do §8b — "Protocolo
    registrado … a meta não foi registrada … 1.746 kcal"; (2) o texto do
    paciente no turno **não** tem palavra de refeição ou treino (se tem, a
    resposta é lida inteira, como antes da isenção). A regra lê palavras, não
    sentido: o que ainda passa em silêncio está declarado, frase por frase,
    nas pendências RC R4 do §8c. Um verbo de registro ou correção que não
    esteja ligado ao nome da meta dispara nesse turno também (com kcal,
    🔥/💪/📊 ou duração de treino em qualquer lugar da resposta, como sempre):
    "Almoço registrado." com o card, "Corrigido … kcal", "Registrei as
    caminhadas de 60 minutos", "Registrei arroz, feijão e frango grelhado. Você
    está em 520 kcal da meta de 1.746.", "Almoço: 520 kcal da meta já
    registradas ✅ 💪". Continuam disparando: o card "Total refeição", a proposta
    imitada ("Vi isso na sua foto … Confirma?"), os bullets com kcal, o "pulei"
    e o cardápio/treino inventado. Sem tool nenhuma, só com tool de leitura, só
    com `cadastra_dados_iniciais`, com a tool em erro ou com `define_meta_peso`
    devolvendo `success:false` sem recusa (dado ausente), nada mudou em relação
    a antes da isenção. O que fica de fora está nas pendências do §8c.
- **Card canônico** substitui alucinação numérica do LLM (`llm.card_replaced`).
- **reconcileBalanceProse** corrige rótulo déficit/superávit + magnitude na prosa.
  No Flow, a frase que cita o balanço do dia do §2c com o número exato não é
  reescrita (§4).
- **Validador numérico / sentiment** loga divergências (`llm.numeric_mismatch`,
  `llm.sentiment_mismatch`).
- **Dedup intra-array** em `registra_refeicao` (itens repetidos somam quantidade).
- **Padrões do dia a dia (regra M2)** em `calcMealMacros`: "leite" e "whey" sem
  tipo saem como leite integral e whey protein em pó, da linha verificada do
  catálogo. Regra, precedência, interruptor e pendências no §9 (confirmação do
  cliente pendente).
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
  - **Edição ou cancelamento depois de gravar sem fechar o pending.** Se a
    tool gravou e o UPDATE `pending → confirmed` falhou, o pending continua
    `pending`. `editRegistration` (`PATCH`) e `cancelRegistration` (`DELETE`)
    procuram as linhas pela chave da proposta atual (`meal_logs` por
    `raw_provider_message_id`; treino: `workout_logs` por chave + tipo); se
    existem, concluem a transição e recusam o pedido com
    `409 registration_already_confirmed` — o pending fica `confirmed`, nunca
    `cancelled`. Sem isso a edição trocava a chave e a confirmação seguinte
    gravava a refeição pela segunda vez; e o cancelamento deixava o pending
    `cancelled` com a refeição gravada, e a proposta seguinte da mesma refeição
    a gravava de novo. Se essa leitura falha, o pedido é recusado
    (`500 registration_lookup_failed`) e o pending não muda. O `PATCH` olha a
    validade antes da guarda (`410`); o `DELETE` não olha a validade.
    - **Código próprio, não `registration_not_pending`.** O iPhone trata
      `registration_not_pending` como "pending inválido": descarta a proposta e
      oferece "Criar nova proposta", que repropõe o rascunho — e, como a
      confirmação do app soma, grava a mesma refeição de novo. Num build que
      não conhece o código (anterior ao commit 9624cd5 do app) ele vira falha
      genérica: a proposta fica na tela, "Tentar novamente" reenvia o mesmo
      pedido (mesma resposta) e o Confirmar recebe `already_confirmed: true`.
      O `PATCH` e o `DELETE` de um pending
      que já está `confirmed` respondem o mesmo código (é o que o "Tentar
      novamente" do app reenvia depois que a guarda fechou o pending, e o que
      acontece quando a resposta do confirm se perdeu). Pending `expired`
      continua em `registration_not_pending`, e o `PATCH` de um `cancelled`
      também; o `DELETE` de um `cancelled` responde `200`.
    - **O que isso garante, e o que não.** Depois da recusa, nenhum botão
      dessa tela (Tentar novamente, Editar, Cancelar, Confirmar) grava de novo
      nem leva a uma segunda proposta: uma linha, 541 kcal nos roteiros da
      revisão (confirm sem resposta ou com falha na transição → `PATCH`
      recusado → `DELETE` recusado → Confirmar). Lado do app lido no código,
      não executado no aparelho. O servidor NÃO impede uma proposta nova: se o
      paciente fechar a tela e registrar a mesma refeição outra vez, ela soma
      (2 linhas, 780) — e o app ainda não diz que o registro já estava salvo
      (pendência abaixo). O pending expirado também segue como pendência
      (`410`). Antes desta regra o `DELETE` respondia
      `registration_not_pending` (pending `confirmed`) ou cancelava (pending
      `pending` com a refeição gravada), e o próprio app oferecia a segunda
      proposta.
    - **Refeição: só proposta do app.** A guarda de refeição vale só para
      proposta com `registration_origin: 'mobile_app'`: a chave dela é o
      `Idempotency-Key` de uma tentativa, então linha sob essa chave só pode
      ser dela. A chave de um pending do WhatsApp é o id da mensagem, que pode
      ter linhas de OUTRA refeição da mesma mensagem (registro expresso +
      pending no mesmo turno); fechar esse pending perderia uma refeição nunca
      gravada. Pending de refeição sem o marcador é editado e cancelado como
      antes desta regra.
    - **Treino: qualquer origem.** A proposta de treino não carrega marcador,
      e a chave + tipo é exatamente a idempotência de `registra_treino`: linha
      sob ela significa que o confirm desse pending não gravaria nada. Vale
      igual para o `PATCH` e para o `DELETE`.
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

  > RC B — cenário cancelar (DELETE) um pending de refeição SEM o marcador cuja escrita já aconteceu NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Com o marcador (proposta do app) e para treino o cancelamento agora é
  > recusado com `409 registration_already_confirmed`. Sem o marcador
  > (WhatsApp, ou app antes desta PR) segue como antes desta PR: o pending vira
  > `cancelled` e a refeição fica gravada.

  > RC B — cenário PATCH ou DELETE simultâneo a um confirm em andamento NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > A guarda lê `meal_logs` antes do UPDATE, sem trava: um confirm que grava
  > entre a leitura e o UPDATE ainda deixa a proposta com chave nova (`PATCH`)
  > ou o pending `cancelled` com a refeição gravada (`DELETE`).

  > RC B — cenário mensagem "já registrado" no iPhone para o código registration_already_confirmed vista no aparelho NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Coberto no código do app em commit separado do mesmo dia (9624cd5): um
  > `409 registration_already_confirmed` ao editar ou cancelar fecha a proposta
  > como confirmada, com a mensagem "Este registro já estava salvo. A alteração
  > não foi aplicada.", sem oferecer nova proposta. Ainda não verificado no
  > aparelho, e nenhum teste de interface do app dirige o 409 (só testes de
  > unidade). Continua aberto: um build anterior a esse commit não conhece o
  > código — mostra "Não foi possível concluir. Tente novamente.", mantém a
  > proposta na tela, "Tentar novamente" reenvia o mesmo `PATCH` ou o mesmo
  > `DELETE` (mesma resposta) e Confirmar responde "Registro confirmado." sem
  > gravar de novo; e, em qualquer build, o servidor só recusa o pedido, não
  > impede uma proposta nova: quem registrar a mesma refeição de novo depois do
  > aviso a grava duas vezes (2 linhas, 780), porque a API não apaga registro
  > confirmado.

  > RC B — cenário pending de refeição sem o marcador cuja escrita já aconteceu, editado pela API NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > A guarda da edição vale só para proposta com `registration_origin`
  > `mobile_app`. Sem o marcador (WhatsApp, ou app antes desta PR) a edição é
  > aceita como antes desta PR: chave nova, e o confirm segue o caminho antigo
  > (substitui em 30 min; depois disso duplica).

  > RC B — cenário pending de treino do WhatsApp com treino do MESMO tipo já gravado pela mesma mensagem, editado ou cancelado pela API NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > A proposta de treino não carrega marcador, então a guarda de treino vale
  > para qualquer origem, por chave + tipo (a idempotência de `registra_treino`):
  > o `PATCH` fecha esse pending sem gravar o segundo treino, e o `DELETE`
  > também o fecha como `confirmed` (`409 registration_already_confirmed`) em
  > vez de cancelar. O confirm direto do mesmo pending já terminava igual
  > (deduplicado).

  > RC B — cenário pending expirado cuja escrita já aconteceu NÃO coberto nesta PR (pendência da audit 2026-10-04).
  > Inalterado: `PATCH` e confirm respondem `410 registration_expired`, que o
  > iPhone trata com "Criar nova proposta" (a refeição seria gravada de novo).
  > Exige a tela aberta 24 h depois de um confirm que falhou na transição. O
  > `DELETE` não olha a validade: enquanto o status ainda é `pending`, ele
  > responde `409 registration_already_confirmed` e fecha como `confirmed`.
  > Depois de um confirm fora da validade o pending já está `expired`, e o
  > `DELETE` responde `409 registration_not_pending`.

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

---

## 8. Metas de composição e pisos (IMC, gordura, peso)

> **Situação das regras desta seção:** ditas pelo cliente (Dr. Roberto) no grupo
> do projeto nas datas indicadas; **implementadas em 2026-10-04 a pedido do
> Eduardo; confirmação do cliente pendente.** Não são decisão nova do cliente.
> Cada uma tem um interruptor de uma linha para voltar ao comportamento anterior.

A meta de composição (`user_profiles.goal_type` / `goal_value`) **não entra** em
meta calórica, balanço, bloco nem card (§1 a §4). Ela aparece em três lugares:
a linha `- Decisão automática: … goal=IMC=…` do contexto do turno (WhatsApp e
Flow, mesma função), o retorno de `define_meta_peso` / `define_protocolo`, e a
pergunta da reavaliação, que repete a meta gravada.

### 8a. Primeira meta automática de IMC (R3) — `calcIMCGoal`

Usada quando o perfil não tem gordura corporal. `normal = imc_limit_recomp` (25),
`passo = imc_goal_step_points` (5).
```
se IMC − 25 ≥ 1:   meta = arredonda(IMC − 5, 1 casa);  se meta − 25 < 1 → meta = 25
senão:             primeiro degrau de imc_goal_steps ABAIXO de 25 com IMC − degrau ≥ 1
                   (23 → 22 → 21); se nenhum, o último degrau (21)
```
- Dito pelo cliente em 26/01/2026 (texto: "caindo de 5 em cinco pontos até
  chegar a faixa da normalidade … até chegar a 25") e no manual 9.4.3.1
  (exemplos 35 → 30, 34 → 29, 31 → 26).
- **Conflito aberto:** em 07/02/2026 ele escreveu uma vez "perder 10 pontos do
  imc". Implementado o passo de 5 (quatro mensagens digitadas e o manual). Com
  passo 10, IMC 32,7 daria 25.
- A margem de 1 ponto e a escada abaixo de 25 são as que já existiam.
- A meta de gordura (`calcBFGoal`) **não mudou**.

| IMC | antes | agora |
|---|---|---|
| 32,7 | 30 | 27,7 |
| 31 | 30 | 26 |
| 34 | 30 | 29 |
| 35 | 30 | 30 |
| 36 | 30 | 31 |
| 45 | 30 | 40 |
| 30,1 | 25 | 25 |
| 27 | 25 | 25 |
| 25,4 | 23 | 23 |
| 25,0 | 23 | 23 |

- Cadeia: antes 32,7 → 30 → 25 → 23 → 22 → 21; agora 32,7 → 27,7 → 25 → 23 → 22 → 21.
- De 15,0 a 30,9 (de 0,1 em 0,1) a meta é idêntica à anterior. O IMC real não é
  arredondado: de 30,95 a 30,99 (mostrado como 31.0) a meta passa de 25 para 26.
- **Onde a regra mora:** na função, não no array. Em execução `imc_goal_steps`
  vem de `global_config` (`calc.imc_goal_steps` = `[30, 25, 23, 22, 21]` em
  staging, lido em 2026-10-04) e não há linha para a chave nova, então vale o
  padrão do código (5). Os degraus de 25 para cima do array não são usados
  enquanto o passo estiver ligado. O 30 veio do fluxo n8n antigo (commit
  63f2aea), não do manual. Nenhuma migration e nenhuma escrita em
  `global_config` foram feitas.
- **Interruptor:** `imc_goal_step_points` = `null` ou `0` devolve a escada
  anterior inteira. Sem deploy: linha `calc.imc_goal_step_points` em
  `global_config` (até 60 s de cache) com o valor `0` ou o JSON `null`
  (`'null'::jsonb`) — NULL de SQL é recusado pela coluna (`value jsonb NOT
  NULL`). A linha não existe hoje: criá-la é escrita em `global_config` e exige
  autorização. No código: o padrão em `packages/core/src/calc-config.ts`
  (`IMC_GOAL_STEP_POINTS`).
- **Só `null` e `0` explícitos desligam a regra.** A linha é lida por
  `imcGoalStepPoints` (`packages/core/src/protocol-router.ts`), como a da
  proteína (§1b):
  - número maior que 0 e até 20 (`IMC_GOAL_STEP_POINTS_SANITY_MAX`, limite de
    digitação — não é limite clínico nem número dito pelo cliente): é o passo
    (10 → IMC 32,7 vira 25);
  - qualquer outro valor — texto (`"5"`, `"0"`, `"cinco"`, vazio), negativo,
    acima de 20, `true`, objeto, chave ausente: vale o padrão do código (5). A
    regra **não** desliga.
  - Antes da segunda revisão de 2026-10-04 uma linha com o texto `"5"` desligava
    a regra em silêncio (IMC 32,7 → 30, sem erro nem log). Sem efeito em
    nenhum banco lido: a linha não existe.
- Código: `packages/core/src/protocol-router.ts` (`calcIMCGoal`,
  `imcGoalStepPoints`), `packages/core/src/calc-config.ts`.
- Testes: `packages/core/tests/protocol-router.test.ts` (exemplos, cadeias,
  varredura 15,0 a 60,0, interruptor, passo 10, valores inválidos da linha) e
  `packages/agent/src/__golden__/audit-10-04-goal-ladder-floors.test.ts` (config
  no formato do banco carregada pelo loader; linha do contexto no WhatsApp e no
  Flow com IMC 32,7; interruptor por linha do banco; linha com o texto `"5"`
  pelo loader real).

### 8b. Meta declarada pelo paciente: pisos (R4)

**Gordura corporal — piso do método: 10%, para os dois sexos.**
- Dito pelo cliente em 28/12/2025 (texto: "não é possível reduzir para menos de
  10% de gordura corporal no nosso sistema") e no manual 9.3 ("limite inferior
  … seguro").
- `define_meta_peso` com `target_bf_percent` abaixo de 10: **não grava**. Devolve
  `success=false, refused=true, goal_saved=false, reason='gordura_abaixo_do_piso'`
  e um texto-base que explica o piso e oferece meta a partir dele. A meta
  anterior fica como estava.
- O teste do piso vem **antes** do ramo "manter" (homem com 8% pedindo 7% era
  gravado como manutenção).
- O piso julga o valor que seria gravado, não o arredondado: 9,96% é recusado.
  O texto e `bf_alvo` mostram o alvo recusado **sem arredondar para cima**
  (9,95 a 9,999 → "9.9%"; antes "10% fica abaixo de 10%").
- Mulher pedindo de 10% a 11,9%: **nada mudou** — aviso ("abaixo do limite
  essencial pra mulher (mínimo 12%)") e a meta é gravada. O 12% é valor do
  código desde 18/06/2026, **não foi dito pelo cliente**; ver pendência.
- `bf_minimo_saudavel` devolvido para homem passa de 5 para 10.

| Caso | antes | agora |
|---|---|---|
| homem 12% pede 7% | "Meta saudável: 7% … Boa meta — vamos focar.", grava 7 | recusa, nada gravado |
| homem 8% pede 7% | "manter", grava 7 | recusa |
| homem 8% pede 5% | "Boa meta — vamos focar.", grava 5 | recusa |
| homem 8% pede 4% | aviso com pergunta, grava 4 | recusa |
| homem 12% ou 15% pede 10% | grava 10 | igual |
| mulher 22% pede 9% | aviso com pergunta, grava 9 | recusa (oferece a partir de 12%) |
| mulher 22% pede 11% | aviso com pergunta, grava 11 | igual |
| homem 12% pede 9,96% | "Meta saudável: 10% …", grava 9,96 | recusa; texto "9.9% fica abaixo de 10%" |

**Peso — IMC alvo abaixo de 18,5 perdendo peso.**
- Dito pelo cliente em 09/06/2026 (texto: "esses valores muito abaixo não
  podemos fazer"; manual 3.5: o agente não pergunta "quer continuar mesmo
  assim"), depois de ter aprovado o aviso com pergunta em 01/06/2026.
- `define_meta_peso` com `target_weight_kg`: **não grava**; devolve
  `refused=true, goal_saved=false, reason='peso_abaixo_do_minimo_saudavel'` e o
  texto com a faixa saudável. Ex.: 55 kg → 48 kg com 170 cm (IMC alvo 16,6):
  antes "… entre 53.5 e 72kg — quer rever?" e gravava 48; agora não grava e
  oferece meta entre 53,5 e 72 kg.
- A recusa é `alvo < peso atual` **e** `alvo / altura² < 18,5`, calculada
  **antes** do ramo "manter" (variação menor que 2% do peso) — qualquer perda,
  por menor que seja. Meta **igual** ao peso atual não é perda e continua
  "manter".
- O piso julga o **IMC calculado**, não o arredondado a uma casa: 18,45 a
  18,499 virava 18,5 e passava como "Ótima meta". No texto e em `imc_alvo` um
  valor abaixo de 18,5 nunca aparece como 18.5 (18,478 → "18.4").
- O **peso mínimo saudável** devolvido e oferecido é arredondado **para cima**
  (0,1 kg), para que o valor oferecido seja ele mesmo aceito. Muda só onde o
  arredondamento antigo ficava abaixo de 18,5 (150 cm: 41,6 → 41,7 kg; 170 cm:
  53,5, igual).
- Ganhando peso para um alvo ainda abaixo de 18,5 (45 → 48 kg): **nada mudou**
  (avisa e grava). Na faixa de IMC calculado 18,45 a 18,499 ganhando peso
  (50 → 53,4 kg, 170 cm) o "Ótima meta — IMC 18.5" virou o aviso de sempre
  ("IMC 18.4, abaixo do saudável … quer rever?"); continua gravada.

| Caso (peso atual → alvo, altura) | antes | agora |
|---|---|---|
| 55 → 48 kg, 170 cm (IMC 16,6) | aviso com pergunta, grava 48 | recusa, oferece 53,5 a 72 kg |
| 54 → 53 kg, 170 cm (IMC 18,34; perde < 2%) | "manter o peso atual", grava 53 | recusa |
| 40 → 39,3 kg, 160 cm (IMC 15,35; perde < 2%) | "manter", grava 39,3 | recusa |
| 52 → 51,5 kg, 170 cm (IMC 17,8; perde < 2%) | "manter", grava 51,5 | recusa |
| 55 → 53,4 kg, 170 cm (IMC 18,478) | "Ótima meta — IMC 18.5", grava 53,4 | recusa, texto "IMC 18.4" |
| 70 → 66,7 kg, 190 cm (IMC 18,476) | "Ótima meta — IMC 18.5", grava 66,7 | recusa, oferece 66,8 a 89,9 kg |
| 55 → 53,5 kg, 170 cm (IMC 18,51) | grava 53,5 | igual |
| 45 → 41,7 kg, 150 cm (IMC 18,53) | grava 41,7 | igual (e é o mínimo oferecido) |
| 52 → 52 kg, 170 cm (igual ao atual) | "manter", grava 52 | igual (pendência) |
| 45 → 48 kg, 170 cm (ganhando) | aviso com pergunta, grava 48 | igual |

**`define_protocolo` nunca perde o protocolo.** Meta recebida abaixo do piso
(gordura < 10 ou IMC < 18,5): grava protocolo, déficit e baseline do ciclo
exatamente como antes e descarta só a meta (grava `null`, como quando a meta é
omitida). O retorno ganha `goal_saved=false`, `goal_refused_reason` e
`goal_message`. Com meta no piso ou acima, o retorno é o de sempre.
- Esta ferramenta **não lê altura nem peso atual**: descarta **qualquer** meta
  de IMC abaixo de 18,5, inclusive de quem está ganhando peso (em
  `define_meta_peso` a recusa é só perdendo). Ver pendência.
- A oferta de gordura é a mesma de `define_meta_peso` para o sexo do perfil
  (homem "a partir de 10%", mulher "a partir de 12%"; antes aqui a mulher lia
  "a partir de 10%"). O sexo é lido **depois** de gravar o protocolo; se a
  leitura falhar ou o sexo não estiver no perfil, a oferta é o piso do método
  (10%).

**Reavaliação no WhatsApp: a recusa chega ao paciente.** Um turno de
reavaliação só com `cadastra_dados_iniciais` / `define_protocolo` é respondido
com o texto fixo "Reavaliação concluída ✅", sem segunda chamada ao modelo. Se
algum resultado traz `goal_saved=false`, o turno **deixa de ser** reavaliação
pura (`isReevalToolTurn`, `packages/agent/src/post-registration-message.ts`): o
modelo redige a resposta com o `goal_message` em mãos. Antes a recusa sumia: o
paciente lia "Reavaliação concluída ✅" e nada sobre a meta. A meta anterior
continua sendo apagada nesse caso (ver pendência). O texto fixo e toda
reavaliação sem recusa continuam byte a byte iguais.

**A resposta fiel à recusa não é "escrita fantasma".** Esse turno termina numa
resposta do modelo que repete as palavras da ferramenta ("Protocolo registrado
… a meta de 7% … não foi registrada") ao lado da meta nova em kcal. O guard de
escrita fantasma (§5) lia isso como refeição registrada sem tool e forçava uma
TERCEIRA chamada ao modelo com "você afirmou ter registrado a refeição/treino
MAS não chamou a tool `registra_refeicao` … Chame a tool AGORA" (reproduzido na
segunda revisão de 2026-10-04 pelo `processMessage` real: 3 chamadas, eventos
`llm.fake_write_detected` e `llm.fake_write_unresolved`). Agora, no turno em
que `define_protocolo` ou `define_meta_peso` **gravou, ou recusou a meta pelo
piso**, a resposta em que todo verbo de registro está ligado ao nome da meta
ou do protocolo (regras de palavra abaixo), num turno em que o texto do
paciente não tem palavra de refeição ou treino, fica fora da regra genérica do
guard: 2 chamadas e o texto chega como o modelo escreveu. Vale
também para a meta ACEITA ("Meta registrada: 75 kg. Vamos focar! 💪" depois de
`define_meta_peso` já disparava o guard antes desta PR) e não depende dos
interruptores do piso.

**A isenção vale por afirmação: nem o texto inteiro, nem toda frase que cita
a meta** (três checagens independentes de 2026-10-04: a primeira sobre o commit
9bc012b, que isentava a resposta toda; a segunda sobre a primeira versão por
frase, que isentava qualquer frase que citasse a meta — 16 de 45 respostas de
escrita fantasma ainda passavam; a terceira sobre a versão seguinte, que
aceitava qualquer particípio depois do nome da meta e cortava a frase nos
dois-pontos antes da lista — 11 + 4 respostas passavam). O que o código faz,
em `packages/agent/src/fake-write-detector.ts` (`outsideGoalSentences` e
`detectFakeWrite`):

1. Só entra aqui a resposta de um turno em que a tool de meta conta (abaixo),
   **sem** o card "Total refeição" e que tem kcal, 🔥/💪/📊 ou duração de
   treino em algum lugar. Fora disso o texto inteiro é lido, como no commit pai
   279ba09.
2. A resposta é cortada em frases: depois de `.`, `!`, `?`, `…` ou `:` seguidos
   de espaço, e a cada quebra de linha ("1.746 kcal" e "118,5 g" não cortam).
3. Uma frase **sai da leitura** só quando tudo isto vale:
   - cita um nome de meta: `protocolo`, `meta`, `objetivo`, `IMC`,
     `gordura corporal` / `% de gordura` / `percentual de gordura`,
     `recomposição`, `ganho de massa` ou `manutenção` ("gordura" sozinha não
     conta: é também macro de refeição);
   - não cita refeição nem treino (café, almoço/almocei, lanche, janta/jantar,
     ceia, refeição, treino, caminhada, corrida, musculação, bike, bicicleta,
     natação, alongamento, yoga, pilates, exercício, cross…) e não tem duração
     com tipo de treino ("40 minutos de força", "1 hora de peso livre");
   - todo verbo de registro ou correção dela está **ligado ao nome da meta**,
     de uma destas duas formas:
     - **particípio logo depois do nome da meta** (`registrado`,
       `re-registrado`, `anotado`, `atualizado`, `corrigido`, `salvo`), **que
       concorda com ele em gênero e número**: feminino depois de `meta`,
       `gordura corporal`, `recomposição` e `manutenção`, masculino depois dos
       outros; plural só depois de `metas`, `protocolos` e `objetivos`. Vale o
       nome que abre o trecho ("Meta de recomposição atualizada" concorda com
       "meta"). "520 kcal da meta já registradas" não está ligado: o plural é
       das kcal (terceira checagem). Única exceção: particípio no plural
       quando o trecho vem logo depois de outro nome de meta e de "e"
       ("Protocolo e meta registrados", "O protocolo e a meta foram
       registrados"); dois nomes de meta na frase sem esse "e" não bastam
       ("520 kcal da meta de recomposição já registradas" dispara). Entre os
       dois só cabem o valor da meta (`de`,
       `do`, `da`, número com ou sem `%`, `kg` ou `kcal`, `kg`, `IMC`, `BF`,
       `peso`, `gordura`, `corporal`, `diária`/`diário`, `recomposição`,
       `manutenção`, `ganho de massa`) e `não`, `já`, `também`, `ainda`,
       `agora`, `foi`, `foram`, `está`, `ficou`: "Protocolo registrado", "Meta
       de 75 kg registrada", "A meta de 7% de gordura corporal não foi
       registrada", "Protocolo de manutenção registrado";
     - **verbo na primeira pessoa seguido do nome da meta** (`registrei`,
       `re-registrei`, `anotei`, `salvei`, `salvamos`, `atualizei`, `corrigi`,
       `troquei`). Entre os dois só cabem `também` ou `já` e `a`, `o`, `as`,
       `os`, `seu(s)`, `sua(s)`, `essa`, `esse`, `esta`, `este`, `nova`,
       `novo`: "Registrei sua meta", "Atualizei o protocolo", "Não registrei
       essa meta";
   - as demais palavras da frase são nomes de meta (os do primeiro item) ou
     estão nesta lista fechada (números e símbolos não são palavras): `peso`,
     `BF`, `kg`, `kcal`, `déficit`, `cadastro`; `a`, `o`, `as`, `os`, `um`,
     `uma`, `seu(s)`, `sua(s)`, `essa`, `esse`, `esta`, `este`, `nova`, `novo`;
     `de`, `do(s)`, `da(s)`, `em`, `no(s)`, `na(s)`, `para`, `pra`, `pro`,
     `por`, `com`, `como`, `e`, `ao`, `à`; `não`, `já`, `também`, `ainda`,
     `agora`, `foi`, `foram`, `está`, `ficou`; `segurança`, `nada`, `mudou`,
     `dia`, `diária`/`diário`, `sucesso`; `pronto`, `perfeito`, `feito`,
     `ótimo`, `certo`, `combinado`, `beleza`, `ok`, `vamos`, `focar`,
     `seguimos`. Nome de comida ou de esporte não cabe numa lista; as palavras
     em volta de uma afirmação de meta cabem. "massa" e "gordura" soltas ficam
     de fora de propósito ("Registrei a meta e a massa: 430 kcal" dispara);
   - não termina em coordenação antes dos dois-pontos (`e:`, `também:`,
     `mais:`, `ainda:`). O corte do passo 2
     separava o verbo da lista que ele rege: "Registrei a meta e também:
     arroz, feijão e frango — 520 kcal 💪" virava uma frase só com palavras da
     lista fechada e outra sem verbo (terceira checagem). "Meta registrada:
     75 kg." e "Meta registrada também." continuam saindo.
4. Se sobrar um verbo de registro ou correção nas frases que ficaram, o guard
   dispara. A kcal ou o emoji não precisam estar nessas frases: já foram
   conferidos na resposta inteira (passo 1).
5. O tipo do retry (registro ou correção) vem das frases que ficaram:
   "Protocolo atualizado: recomposição. Almoço registrado: … 430 kcal" pede
   registro, não `replace=true`.
6. **Se não sobrou verbo nenhum, entra o texto do paciente** (terceira
   checagem). Quando o que o paciente mandou no turno tem uma palavra de
   refeição ou treino — a mesma lista do passo 3: café, almoço/almocei,
   lanche, janta/jantar/jantei, ceia, refeição, treino, caminhada, corrida,
   musculação, bike, bicicleta, natação, alongamento, yoga, pilates,
   exercício, cross… —, **a isenção não vale**: a resposta é lida inteira,
   como no commit pai 279ba09, e o tipo do retry é o que o pai daria. O texto
   do paciente é o que o pipeline tem em texto naquele ponto
   (`patientTurnTextOf`, `packages/agent/src/pipeline.ts`): o que ele digitou,
   a transcrição dos áudios e, no WhatsApp, a análise automática das fotos
   (uma foto de prato entra como "Foto [refeição]: …"; os rótulos de foto
   corporal e de balança não têm palavra da lista, mas a nota livre que a
   visão escreve sobre a foto pode ter). Só o turno atual é lido.

O passo 6 só pode fazer o guard disparar **mais**: o que dispara pelos passos
1 a 5 continua disparando, com o mesmo tipo de retry, com ou sem o texto do
paciente; sem palavra de refeição ou treino nesse texto, nada muda. Em todas
as sondas das três checagens a resposta que passava em silêncio era de um
turno em que o **paciente** relatava a refeição ou o treino junto com a meta
("Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado."). Nesse
turno a tool de meta não explica nada sobre a refeição.

**Consequência assumida:** a resposta fiel, só de meta ("Meta registrada:
75 kg. Vamos focar! 💪"), num turno em que o paciente também relatou a
refeição, dispara como no commit pai — 3ª chamada ao modelo com "chame
registra_refeicao". É o esperado: o paciente relatou uma refeição e nada foi
registrado. O mesmo acontece quando a palavra está no texto do paciente sem
ser relato ("Peso 79 kg, treino 4 vezes por semana, fome moderada…" na
reavaliação): aí a 3ª chamada é custo da regra, declarado no §8c.

Na dúvida a frase **não** sai, e então o custo é o comportamento do commit pai
(uma chamada a mais ao modelo). Isso não torna a isenção completa: ela lê
palavras, não sentido, e o que se sabe que ainda passa em silêncio está
declarado, frase por frase, nas pendências RC R4 do §8c — refeição mostrada
sem verbo próprio ("Frango com arroz — 430 kcal. Meta registrada 💪",
"Registrei a meta do dia: 520 kcal de arroz, feijão e frango.") e particípio
que concorda com a meta numa frase sobre a refeição ("520 kcal da meta
registrada 💪"), as duas só quando o texto do paciente não tem palavra de
refeição ou treino ("Comi 2 fatias de pizza" não tem). As duas
formas do passo 3 vêm das frases que as próprias ferramentas devolvem
("Protocolo registrado. A meta de 7% de gordura corporal não foi registrada…",
"Não registrei essa meta…", "Por segurança, não registrei essa meta e nada
mudou no seu cadastro.", "Meta de 7% registrada."). Varredura travada em
`fake-write-detector.test.ts`: 1.610 mensagens dos dois classificadores de meta
e de `define_protocolo` × 6 molduras = 9.660 respostas fiéis; com a tool de
meta nenhuma dispara, sem ela 6.536 disparam.

A expressão regular da forma do particípio lê cada texto de um jeito só. Na
versão anterior o espaço depois de um número podia ser do número ou do
separador seguinte, e "75 kg" era um trecho ou dois: numa frase com verbo de
registro, nome de meta, N números separados por dois espaços e nenhum
particípio, o tempo dobrava a cada número (3,7 s com 28; terceira checagem,
entrada montada pelo checador, nunca vista em resposta de modelo). Os textos
aceitos são os mesmos (400.000 frases sorteadas com as palavras da regra,
36.823 delas com algum trecho ligado, comparadas entre as duas versões fora do
repositório: nenhuma diferença). Travado em `fake-write-detector.test.ts`: 60
repetições de oito formatos em menos de 100 ms cada.

O que essa regra faz com frases que citam a meta (sem palavra de refeição ou
treino no texto do paciente):

| Frase (com kcal/emoji na resposta) | Resultado |
|---|---|
| "Meta registrada: 75 kg e protocolo atualizado para recomposição." | isenta (dois verbos, os dois ligados à meta) |
| "Registrei o frango e o arroz na sua meta de hoje: 430 kcal 💪" | dispara (o objeto de "registrei" é a comida) |
| "Meta registrada e arroz com frango anotado — 430 kcal." | dispara ("anotado" não está ligado à meta) |
| "Meta de 75 kg registrada, e já deixei anotado o pão com ovo de hoje cedo (310 kcal)." | dispara (idem) |
| "Registrei a meta e o frango com arroz: 430 kcal 💪" | dispara ("frango", "arroz" fora da lista fechada) |
| "Meta registrada: 75 kg. Registrei 40 minutos de força, bom para a meta." | dispara (o objeto de "registrei" é o treino; a frase tem duração + tipo de treino) |
| "Registrado! Faltam 410 kcal para a meta." | dispara (o verbo está numa frase sem nome de meta) |
| "Almoço: 520 kcal da meta já registradas ✅ 💪" | dispara ("registradas" não concorda com "meta": o plural é das kcal) |
| "🔥 520 / 1.746 kcal da meta registradas" | dispara ("registradas" não concorda com "meta") |
| "Almoço: 520 kcal da meta de recomposição já registradas ✅" | dispara (dois nomes de meta, sem "e" entre eles) |
| "Protocolo e meta registrados. 1.746 kcal por dia 💪" | isenta (plural sobre dois nomes de meta ligados por "e") |
| "Registrei a meta e também: arroz, feijão e frango — 520 kcal 💪" | dispara (a frase do verbo termina em coordenação antes dos dois-pontos) |
| "Registrei a meta do dia: 520 kcal de arroz, feijão e frango." | **não dispara** (pendência do §8c: o verbo está ligado a "meta"; a comida vem depois dos dois-pontos, sem verbo próprio) |
| "520 kcal da meta registrada 💪" | **não dispara** (pendência do §8c: o particípio concorda com "meta") |
| "Frango com arroz — 430 kcal. Meta registrada 💪" | **não dispara** (pendência do §8c: a comida não tem verbo próprio) |

As três últimas disparam quando o texto do paciente no turno tem palavra de
refeição ou treino (passo 6).

**Quando a tool de meta conta** (`goalToolRanThisTurn`,
`packages/agent/src/pipeline.ts`): `define_protocolo` ou `define_meta_peso`
sem exceção **e** com `success === true` ou `refused === true` no retorno.
`define_protocolo` com a meta descartada devolve `success:true` +
`goal_saved:false` e conta (o protocolo foi gravado). `define_meta_peso` que
devolve `{success:false, error}` — sexo, gordura atual ou peso/altura ausentes
— **não conta**: nada foi gravado nem recusado, e "Meta registrada … 1.746 kcal
💪" dispara o guard como em qualquer turno sem tool.

| Turno pelo `processMessage` (WhatsApp), homem 80 kg, 12%, recomposição | 279ba09 (pai) | 9bc012b | agora |
|---|---|---|---|
| `define_protocolo` + "Almoço registrado." com o card | 3 chamadas, 2 eventos | 2 chamadas, nenhum evento | 3 chamadas, 2 eventos |
| `define_protocolo` + "Corrigido. … Feijão carioca (180 g): 137 kcal" com o card | 3, 2 eventos (retry de correção) | 2, nenhum | 3, 2 eventos (retry de correção) |
| `define_meta_peso{75 kg}` + "Meta registrada: 75 kg. Registrei as duas caminhadas de 60 minutos cada." | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| `define_meta_peso{7%}` + "Não registrei essa meta: 7% fica abaixo de 10%. Almoço registrado: … 520 kcal." | 3, 2 eventos ¹ | 2, nenhum | 3, 2 eventos |
| `define_meta_peso{15%}` → `success:false` (gordura atual ausente) + "Meta registrada: 15% de gordura corporal. Sua meta diária segue em 1.746 kcal 💪" | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| reavaliação, meta de 7% dentro de `define_protocolo`, "Protocolo registrado. Sua nova meta é 1.746 kcal por dia. … 💪" | não medido | 2, nenhum | 2, nenhum |
| `define_meta_peso{7%}` + só as palavras da recusa da tool + "Sua meta diária segue em 1.746 kcal 💪" | 3, 2 eventos ¹ | 2, nenhum | 2, nenhum |
| `define_meta_peso{75 kg}` + "Meta registrada: 75 kg. Vamos focar! 💪" | 3, 2 eventos | 2, nenhum | 2, nenhum |

¹ No commit pai o piso não existia: a tool gravava a meta de 7% (`success:true`).
A coluna mostra só o comportamento do guard para o mesmo texto.

Colunas "279ba09" e "9bc012b": medidas em cópias dos dois commits, fora do
repositório, com o mesmo banco e modelo falsos do golden (sem relato de
paciente). Coluna "agora": os goldens.

Segunda checagem (2026-10-04), mesma pessoa e mesmo `processMessage`, nos três
modos de tool de meta (`define_meta_peso{75 kg}` aceita, `define_meta_peso{7%}`
recusada pelo piso, `define_protocolo`) — o resultado é o mesmo nos três:

| Resposta do modelo, sem tool de registro no turno | 279ba09 (pai) | 1ª versão por frase | agora |
|---|---|---|---|
| "Meta registrada: 75 kg. Registrei arroz, feijão e frango grelhado. Você está em 520 kcal da meta de 1.746." | 3 chamadas, 2 eventos | 2 chamadas, nenhum evento | 3 chamadas, 2 eventos |
| "Anotei os 40 minutos de futsal. Meta do dia mantida em 1.746 kcal." | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| "Registrei 1 hora de peso livre para a sua meta de 75 kg." | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| "Corrigido: feijão 180 g. Total do dia: 1.433 kcal de 1.843 da meta." | 3, 2 eventos (retry de correção) | 2, nenhum | 3, 2 eventos (retry de correção) |
| "Registrado! Faltam 410 kcal para a meta." | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| "Meta registrada e arroz com frango anotado — 430 kcal." | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| "Registrei o frango e o arroz na sua meta de hoje: 430 kcal 💪" | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| as outras 9 das 16 respostas do achado (lista no golden) | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| "Não registrei: 7% fica abaixo de 10%, o limite seguro. Você continua com 1.746 kcal por dia 💪" (recusa fiel parafraseada, `define_meta_peso{7%}`) | 3, 2 eventos | 3, 2 eventos | 3, 2 eventos (pendência) |
| "Meta registrada: 75 kg e protocolo atualizado para recomposição. 1.746 kcal por dia 💪" | não medido | não medido | 2, nenhum |

Colunas "279ba09" e "1ª versão por frase" desta tabela: medidas pelo segundo
checador em cópias fora do repositório (45 respostas de escrita fantasma por
modo: o pai disparava em 45, a 1ª versão por frase em 29). Coluna "agora": os
goldens; a mesma matriz do checador, refeita sobre esta árvore, dispara nas 45
de 45 por modo, e nas 17 respostas só de meta dispara em 5 (o pai em 16): as
das pendências do §8c.

Terceira checagem (2026-10-04), mesma pessoa, mesmo `processMessage` e os
mesmos três modos de tool de meta — o resultado é o mesmo nos três. Sem relato
de paciente: frase do paciente e respostas são as sondas do checador.

| Paciente → resposta do modelo, sem tool de registro no turno | 279ba09 (pai) | versão da 2ª checagem | agora |
|---|---|---|---|
| "Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado." → "Almoço: 520 kcal da meta já registradas ✅ 💪" | 3 chamadas, 2 eventos | 2 chamadas, nenhum evento | 3 chamadas, 2 eventos |
| mesma frase → as outras 10 respostas do achado de concordância (lista no fixture) | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| mesma frase → "Registrei a meta e também: arroz, feijão e frango — 520 kcal 💪" e as 3 variantes em lista | 3, 2 eventos | 2, nenhum | 3, 2 eventos |
| "Minha meta agora é 75 kg" → as mesmas 11 + 4 respostas | 3, 2 eventos | 2, nenhum | 3, 2 eventos (pela regra da resposta) |
| "Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado." → "Frango com arroz — 430 kcal. Meta registrada 💪" | 3, 2 eventos | 2, nenhum | 3, 2 eventos (pela palavra "Almocei" do paciente) |
| "Minha meta agora é 75 kg" → "Frango com arroz — 430 kcal. Meta registrada 💪" | 3, 2 eventos | 2, nenhum | 2, nenhum (pendência) |
| "Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado." → "Meta registrada: 75 kg. Vamos focar! 💪" | 3, 2 eventos | 2, nenhum | 3, 2 eventos (consequência assumida) |
| "Minha meta agora é 75 kg" → "Meta registrada: 75 kg. Vamos focar! 💪" | 3, 2 eventos | 2, nenhum | 2, nenhum |

Colunas "279ba09" e "versão da 2ª checagem" desta tabela: medidas fora do
repositório, com a sonda do terceiro checador (banco e modelo falsos), numa
cópia do commit pai e numa cópia desta árvore tirada antes da correção. Coluna
"agora": os goldens. A matriz inteira refeita sobre as duas cópias e esta
árvore — as 142 respostas dos dois checadores com a frase de cada sonda, com
"…Almocei arroz, feijão e frango grelhado." e com "Minha meta agora é 75 kg",
mais as 15 dos achados, em 7 modos de tool: 1.323 turnos com tool de meta que
conta e 1.764 sem — deu: nenhum turno que disparava deixou de disparar; os
que já disparavam ficaram byte a byte iguais (mesmo tipo de retry); 189
passaram a disparar; os 1.764 turnos sem tool de meta que conta ficaram byte a
byte iguais. Com palavra de refeição no texto do paciente o guard dispara
exatamente onde o pai disparava (em 16 das 17 respostas só de meta, inclusive).

"2 eventos" = `llm.fake_write_detected` + `llm.fake_write_unresolved`. Quando o
modelo insiste na mesma resposta depois do retry, o texto **chega ao paciente**
("Almoço registrado." incluso): o guard força uma nova chamada e deixa o evento
para a auditoria, não apaga a frase. Isso é igual ao commit pai. Travado em
`packages/agent/src/__golden__/audit-10-04-goal-ladder-floors.test.ts` (dez
turnos de escrita fantasma com a tool de meta, dois de resposta fiel e os
controles da primeira checagem; da segunda, as 16 respostas do achado e a
frase que este doc dizia disparar nos três modos — 51 turnos —, as duas
recusas parafraseadas e duas respostas fiéis de dois verbos nos três modos; da
terceira, nos três modos, as 11 + 4 respostas dos dois achados com a frase do
paciente do achado e com "Minha meta agora é 75 kg", as 45 respostas de
escrita fantasma da segunda checagem com a frase de cada sonda e com a do
achado, as sete respostas das pendências com e sem palavra de refeição no
texto do paciente, os três relatos sem palavra da lista, a resposta fiel num
turno com refeição relatada e o tipo do retry — 420 turnos —, e quatro turnos
avulsos: a reavaliação com "treino" no texto do paciente, a foto de prato, o
áudio e a foto corporal) e em
`packages/agent/src/fake-write-detector.test.ts` (uma entrada por classe de
frase, a varredura, e a prova, sobre 164 respostas — as 157 dos checadores e
as 7 das pendências —, de que o texto do paciente só acrescenta disparos). As
respostas dos checadores estão,
palavra por palavra, em
`packages/agent/src/__golden__/fixtures/audit-10-04-guard-answers.ts`. As
pendências desta isenção estão no §8c.

**O que o modelo lê.** As frases de piso nas descrições de `define_protocolo` e
`define_meta_peso` (e no `.describe` de `target_bf_percent`, que hoje o
`tool-schema.ts` não envia ao modelo) são montadas a partir das duas constantes
(`goalFloorToolTexts`). Com uma constante em `0`, a frase dela some; com as
duas em `0`, as descrições voltam ao texto anterior a esta regra.

- **Interruptores:** `BF_METHOD_FLOOR` (`packages/agent/src/bf-goal-classifier.ts`)
  = `0` desliga a recusa de gordura (o mínimo do homem volta a 5, e o alvo
  volta a ser mostrado arredondado); `IMC_GOAL_FLOOR`
  (`packages/agent/src/weight-goal-classifier.ts`) = `0` desliga a recusa de
  peso e de IMC (o IMC volta a ser julgado arredondado e o peso mínimo volta ao
  arredondamento comum). Cada um tira também as suas frases das descrições das
  ferramentas, e sem recusa não existe `goal_saved=false`, então a reavaliação
  volta ao texto fixo. Vale para qualquer valor: com o piso em `0`,
  `define_protocolo` grava até meta negativa, como antes (`goalBelowFloorReason`
  só olha um piso ligado, `> 0`). É mudança de código (uma linha cada) e exige
  deploy.
- Código: os dois classificadores, `packages/agent/src/tools.ts`
  (`defineMetaPeso`, `defineProtocolo`, `goalBelowFloorReason`,
  `bfGoalOfferFrom`, `goalFloorToolTexts`) e
  `packages/agent/src/post-registration-message.ts` (`isReevalToolTurn`).
- Testes: `bf-goal-classifier.test.ts`, `weight-goal-classifier.test.ts`,
  `post-registration-message.test.ts`; o golden
  `audit-10-04-goal-ladder-floors.test.ts`, que executa as duas ferramentas com
  banco em memória, confere que nada foi escrito e roda o turno de reavaliação
  pelo pipeline real; e o golden `audit-10-04-goal-floor-switch.test.ts`, que
  carrega `tools.ts` com cada piso em `0` e compara as descrições com o texto
  anterior.
- Os textos de recusa são redação nossa, ainda não aprovada pelo cliente.

### 8c. Pendências declaradas

> RC R3 — cenário passo de 10 pontos ("perder 10 pontos do imc", texto de 07/02/2026) NÃO coberto nesta PR (pendência da audit 2026-10-04). Implementado o passo de 5 (26/01/2026 e manual). 32.7 daria 25 com passo 10; é uma troca de valor.

> RC R3 — cenário metas de IMC já gravadas com 30 NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem backfill: seguem no banco e na pergunta da reavaliação.

> RC R3 — cenário IMC de 25,0 a 25,9 (manual: meta 25; código: 23) e normalidade "menor que 25" / "IMC < 24" NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: margem de 1 ponto e alvo 25.

> RC R3 — cenário IMC de 30,95 a 30,99 (mostrado como 31.0) NÃO coberto nesta PR (pendência da audit 2026-10-04). Muda de 25 para 26 (acompanha o valor mostrado); travado em packages/core/tests/protocol-router.test.ts, sem relato de paciente.

> RC R3 — cenário peso e altura reais dos prints C3-03, C2-49 e C2-50 NÃO coberto nesta PR (pendência da audit 2026-10-04). Os prints só trazem o IMC.

> RC R4 — cenário paciente que JÁ está abaixo do piso (gordura ≤ 10% ou IMC < 18,5) seguir em recomposição com déficit NÃO coberto nesta PR (pendência da audit 2026-10-04). Manual 3.5 e 9.3; exige mexer no cadastro do app (RPC e contrato).

> RC R4 — cenário C3-05 (09/02/2026: gordura 12%, IMC 25.7, "Meta de BF definida: 10%" antes de escolher protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R4 — cenário meta em kg que implica gordura abaixo de 10% (homem de 80 kg com 12% pedindo 76 kg) NÃO coberto nesta PR (pendência da audit 2026-10-04). Continua "Ótima meta" e grava.

> RC R4 — cenário metas já gravadas abaixo do piso NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem backfill: seguem no banco e na pergunta da reavaliação.

> RC R4 — cenário piso feminino (mulher pedindo de 10% a 11,9%) NÃO coberto nesta PR (pendência da audit 2026-10-04). O cliente nunca disse piso separado para mulher. O 12% é valor do código: continua aviso e grava (travado no golden). A recusa abaixo de 10% oferece "a partir de 12%" para não contradizer esse aviso.

> RC R4 — cenário meta de peso que ainda deixa o IMC abaixo de 18,5 GANHANDO peso (45 → 48 kg) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: avisa e grava (travado no golden).

> RC R4 — cenário meta de peso IGUAL ao peso atual, ou ganhando menos de 2% do peso, de quem já está abaixo de 18,5 (52 → 52 kg e 52 → 52,5 kg, 170 cm) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: 'maintenance' e grava (52 → 52 kg travado no golden; 52 → 52,5 kg em weight-goal-classifier.test.ts). PERDENDO, qualquer variação é recusada (54 → 53, 52 → 51,5, 40 → 39,3).

> RC R4 — cenário define_protocolo com meta de IMC abaixo de 18,5 de quem está GANHANDO peso (175 cm, 50 kg, ganho_massa, IMC 18) NÃO coberto nesta PR (pendência da audit 2026-10-04). A ferramenta não lê altura nem peso atual: descarta QUALQUER meta de IMC abaixo de 18,5 (o protocolo é gravado). A mesma pessoa em define_meta_peso (55,1 kg, ganhando) tem a meta gravada com aviso (travado no golden).

> RC R4 — cenário meta de peso GANHANDO com IMC bruto de 18,45 a 18,499 (50 → 53,4 kg, 170 cm) NÃO coberto nesta PR (pendência da audit 2026-10-04). Muda: era "Ótima meta — IMC 18.5", agora o aviso "IMC 18.4, abaixo do saudável … quer rever?"; continua gravada. Travado em weight-goal-classifier.test.ts; sem relato de paciente.

> RC R4 — cenário recusa da meta na reavaliação com fotos corporais ainda pendentes, e a redação do modelo nesse turno NÃO coberto nesta PR (pendência da audit 2026-10-04). O golden cobre o turno "não vou mandar fotos": o modelo recebe o goal_message e redige; o que ele escreve não é testado. Com fotos pendentes, o texto fixo "ainda falta foto …" também deixa de sair nesse turno (o modelo redige).

> RC R4 — cenário os dois classificadores executados com o piso em 0 dentro da suíte (o piso é uma constante do módulo; aqui só o que tools.ts importa é trocado) NÃO coberto nesta PR (pendência da audit 2026-10-04). Conferido à mão em 2026-10-04, numa cópia com as duas constantes em 0, contra o commit 55294c4.

> RC R4 — cenário define_protocolo com meta abaixo do piso quando já existe meta gravada NÃO coberto nesta PR (pendência da audit 2026-10-04). A meta anterior é apagada (null), como já acontece quando a meta é omitida; define_meta_peso, ao recusar, não toca na anterior.

> RC R4 — cenário escada automática dar 10% a mulher com até 15% de gordura, e 20% a mulher fora da normalidade (manual de 22/05/2026: ≤ 27%) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R4 — cenário conversa real depois da recusa (o modelo dizer que registrou ou repetir a chamada) e redação da recusa aprovada pelo cliente (manual 3.5.2) NÃO coberto nesta PR (pendência da audit 2026-10-04). Os roteiros de cadastro e reavaliação ficam no banco; não há teste de conversa.

> RC R4 — cenário refeição ou treino mostrados SEM verbo de registro próprio na resposta em que o único verbo é o da meta ("Frango com arroz — 430 kcal. Meta registrada 💪", "Meta registrada. Arroz com frango também. 430 kcal 💪", "Arroz com frango: meta registrada — 430 kcal", "Registrei a meta e 430 kcal 💪", "Registrei a meta do dia: 520 kcal de arroz, feijão e frango.") NÃO coberto nesta PR (pendência da audit 2026-10-04). O verbo é explicado pela tool de meta e nenhum outro sobra: quando o texto do paciente no turno não tem palavra de refeição ou treino ("Minha meta agora é 75 kg"), o guard não dispara (no commit pai 279ba09 disparava, pelo verbo da meta). Com a palavra ("Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.") dispara. Os dois lados estão em fake-write-detector.test.ts e no golden. Sem relato de paciente.

> RC R4 — cenário particípio que concorda com o nome da meta numa frase sobre a refeição ("520 kcal da meta registrada 💪"), e particípio no plural depois de dois nomes de meta ligados por "e" ("520 kcal do protocolo e meta registradas 💪") NÃO coberto nesta PR (pendência da audit 2026-10-04). A concordância com o nome da meta é o único sinal lido: quando o texto do paciente no turno não tem palavra de refeição ou treino ("Minha meta agora é 75 kg"), o guard não dispara (no commit pai 279ba09 disparava). Com a palavra ("Minha meta agora é 75 kg. Almocei arroz, feijão e frango grelhado.") dispara. Os dois lados estão em fake-write-detector.test.ts e no golden. Sem relato de paciente.

> RC R4 — cenário paciente que relata a refeição ou o treino SEM palavra da lista ("Minha meta agora é 75 kg. Comi 2 fatias de pizza.", "Minha meta agora é 75 kg. Joguei 40 minutos de futsal.", "My goal is now 75 kg. I had rice, beans and chicken."), ou que relatou num turno anterior NÃO coberto nesta PR (pendência da audit 2026-10-04). A isenção continua valendo nesse turno: a resposta é lida por frase, com as pendências desta lista (refeição mostrada sem verbo próprio; particípio que concorda com o nome da meta). A lista é a mesma usada na resposta (café, almoço/almocei, lanche, janta/jantar/jantei, ceia, refeição, treino, caminhada, corrida, musculação, bike, bicicleta, natação, alongamento, yoga, pilates, exercício, cross…): "comi", "tomei", nome de comida e nome de esporte não estão nela. Caracterizado em fake-write-detector.test.ts e no golden.

> RC R4 — cenário resposta fiel cujo verbo de registro/correção está numa frase SEM palavra de meta ("Atualizado! Agora são 1.746 kcal por dia 💪", "Registrado! Sua meta agora é 1.746 kcal por dia."), incluída a recusa parafraseada ("Não registrei: 7% fica abaixo de 10%, o limite seguro. Você continua com 1.746 kcal por dia 💪", "Anotado o pedido, mas o percentual de 7% não foi registrado: está abaixo do mínimo de 10% para homens. Você segue com 1.746 kcal por dia 💪") NÃO coberto nesta PR (pendência da audit 2026-10-04). O guard dispara como no commit pai 279ba09: 3ª chamada ao modelo com "chame registra_refeicao" num turno sem refeição. A isenção não foi alargada para esses textos. As duas recusas estão no golden (3 chamadas, 2 eventos); as outras em fake-write-detector.test.ts.

> RC R4 — cenário resposta fiel cuja frase do verbo cita a meta mas tem verbo não ligado ao nome da meta ("Registrei 75 kg como sua nova meta 💪"), particípio que não concorda com o nome da meta ("Meta registrado: 75 kg. 1.746 kcal por dia 💪"), palavra fora da lista fechada ("Meta registrada, Roberto! 1.746 kcal por dia 💪"), palavra de refeição/treino ("Protocolo registrado com 4 treinos por semana: 1.746 kcal por dia 💪") ou coordenação antes dos dois-pontos ("Protocolo registrado e também: 1.746 kcal por dia 💪") NÃO coberto nesta PR (pendência da audit 2026-10-04). O guard dispara como no commit pai 279ba09 (3ª chamada ao modelo). Na dúvida a frase não é isenta. Caracterizado em fake-write-detector.test.ts.

> RC R4 — cenário resposta fiel (só meta ou protocolo) num turno em que o texto do paciente tem palavra de refeição ou treino SEM relatar refeição nem treino ("Peso 79 kg, treino 4 vezes por semana, fome moderada, não vou mandar fotos. Minha meta agora é 7% de gordura") NÃO coberto nesta PR (pendência da audit 2026-10-04). A isenção não vale nesse turno e o guard dispara como no commit pai 279ba09 (3ª chamada ao modelo com "chame registra_refeicao"): a condição lê palavra, não sentido. É o caso de quem informa a frequência de treino junto com o peso e a fome na reavaliação. Travado no golden (3 chamadas, 2 eventos) e em fake-write-detector.test.ts. A frase do paciente é sintética: não há relato.

> RC R4 — cenário retry do guard dirigido à META (define_meta_peso devolve success:false, o modelo afirma "Meta registrada … kcal 💪") NÃO coberto nesta PR (pendência da audit 2026-10-04). O guard dispara e os dois eventos são gravados (golden), mas o retry manda chamar registra_refeicao/registra_treino, não define_meta_peso; se o modelo insiste, o texto chega ao paciente.

> RC R4 — cenário "Meta registrada" SEM kcal, emoji de card ou treino depois de define_meta_peso com success:false ("Meta registrada: 15% de gordura corporal.") NÃO coberto nesta PR (pendência da audit 2026-10-04). O guard só lê afirmação acompanhada de kcal/🔥/💪/📊 ou de duração de treino: esse texto nunca disparou, nem no commit pai.

> RC R4 — cenário paciente que relata com forma conjugada ou diminutivo FORA da lista ("Treinei 40 minutos hoje", "Fui treinar", "Malhei", "Corri", "Caminhei", "Pedalei", "Nadei", "academia", "esteira", "Almoçamos arroz e frango", "Tomei um cafezinho com pão", "lanchinho", "Ceei"), e foto de equipamento cujo rótulo escrito pelo próprio worker ("Foto [equipamentos de treino]") contém "treino" NÃO coberto nesta PR (pendência da audit 2026-10-04). No primeiro caso a palavra não está na lista e a isenção continua valendo: a resposta é lida por frase, com as pendências desta lista ("Fiz um treino de 40 minutos" tem a palavra e desliga a isenção). No segundo a isenção cai por uma palavra do pipeline, não do paciente: a resposta fiel custa a 3ª chamada, como no commit pai 279ba09. Medido pela quarta revisão de 04/10 (lente B); sem golden.

> **Pendência pré-existente, fora desta PR (sem linha RC):** a expressão `TRAINING_EXERCISE_LINE` de `fake-write-detector.ts` fica lenta com uma sequência longa de espaços depois de uma quebra de linha (400 espaços: cerca de 4 s; 800: mais de 30 s), igual no commit pai 279ba09, no HEAD e nesta árvore. Ela roda em toda resposta final sem tool de prescrição, no WhatsApp e no Flow. É entrada patológica, não vista em resposta de modelo. A reescrita candidata muda o veredito em 632 de 200.000 textos sintéticos de plano, então precisa de mudança própria com diferencial (quarta revisão de 04/10, lente B).

---

## 9. Padrões do dia a dia — item assumido quando o paciente não diz o tipo (regra M2)

> **Situação da regra:** regra geral dita pelo cliente em 06/01/2026 (manual 4.2),
> 18/05/2026 e 01/06/2026 (assumir em vez de perguntar); a lista de itens NÃO foi
> confirmada por ele; implementado em 2026-10-04 a pedido do Eduardo; confirmação
> do cliente pendente. Não é decisão nova do cliente.

- 18/05/2026 (texto): "é melhor ele chutar e a pessoa corrigir do q ficar toda
  hora perguntando". 01/06/2026 (texto): "Melhor ele chutar e não ficar
  perguntando". O cliente disse a regra; os itens abaixo ele não disse.

### 9a. A lista (`packages/agent/src/everyday-food-defaults.ts`)

| Quando o item inteiro é | O sistema assume e mostra | Linha do catálogo (verificada) | Fonte | kcal · P · C · G por 100 g |
|---|---|---|---|---|
| "leite" ou "leite integral" | leite integral | "Milk, whole, 3.25% milkfat, with added vitamin D" (id 4492 no staging) | USDA FDC:171265 | 61 · 3,15 · 4,8 · 3,25 |
| "whey" ou "whey protein em pó" | whey protein em pó | "Beverages, Protein powder whey based" (id 6407 no staging) | USDA FDC:173180 | 352 · 78,13 · 6,25 · 1,56 |

- **Gatilho:** o nome INTEIRO do item, sem maiúsculas, sem acento e com espaços
  colapsados, é igual a um nome da lista. É igualdade, nunca "contém": "leite de
  coco", "leite com whey", "café com leite", "whey protein" e "shake de whey"
  não passam pela lista. Parte de nome composto também não.
- **Nenhum número é inventado.** O valor vem da linha verificada do catálogo,
  lida pelo nome exato (`search_food_trgm`, similaridade ≥ 0,9). A lista repete
  kcal, P, C e G só para conferir: se a linha não existir ou tiver valor
  diferente (2 casas), o item segue o cálculo de antes, como se a lista
  estivesse vazia, e fica um `audit_warning`. A fibra vem da linha (leite 0;
  whey 3,1 g por 100 g).
- **O que o paciente vê:** o item sai com o nome assumido (`food_name` = nome
  mostrado), fonte `canonical_fuzzy` e o `food_db_id` da linha. A proposta do
  WhatsApp e a proposta do app imprimem esse nome (travado em teste); a tela do
  iPhone não foi executada depois da mudança (pendência abaixo). Nenhum aviso
  novo vai ao paciente.
- **Uma linha por item do dia a dia.** Dois ou mais itens da mesma chamada que
  resolvem para a mesma entrada ("leite" 200 g e "leite integral" 200 g) voltam
  como UMA linha, na posição do primeiro, com a quantidade somada e os valores
  calculados da mesma linha do catálogo para a soma: "leite integral" 400 g,
  244 kcal · P 12,6 · C 19,2 · G 13. Sem isso a proposta mostrava duas linhas
  iguais (244 kcal) e a dedup do confirm gravava uma (122 kcal). Itens fora da
  lista não são somados (ver pendências). Quando há soma, `calcMealMacros`
  devolve `input_indexes` (para cada linha, as posições dos itens do pedido).

### 9b. Precedência por item, como implementada em `calcMealMacros`

1. nutrição já aprovada num pending (grava o que foi mostrado, sem reler o catálogo);
2. kcal dita pelo paciente (o item mantém o nome digitado);
3. bebida zero/diet/light;
4. correção ATIVA do próprio paciente (com macro próprio: usa direto; sem macro:
   troca o nome e segue — se o nome corrigido for um nome da lista, ele cai no
   padrão do dia a dia);
5. **padrão do dia a dia**;
6. pergunta de preparo (cru/cozido);
7. histórico do paciente (30 dias);
8. nome composto;
9. match direto no catálogo, com as guardas de categoria e proteína;
10. estimativas.

Correção vista uma vez só (`learning`) não bloqueia o padrão. O histórico fica
depois de propósito: ele pode guardar o match errado já confirmado ("leite" =
leite de coco).

**O que NÃO muda:** `matchFood`, a divisão de nome composto, a pergunta de
preparo e as estimativas não consultam a lista; nenhuma linha entra no catálogo.
Meta, balanço de comida, balanço net e bloco têm as mesmas fórmulas; só recebem
o consumido dos registros novos.

### 9c. Caso real e números

- iPhone, staging, 04/10/2026, "1 copo de leite com whey no jantar", 200 g e
  30 g: "leite" saía como "Leite, de coco" (332,3 kcal, 36,7 g de gordura) e
  "whey" ficava sem cálculo (`protein_mismatch`, 0 kcal). Pelo código, proposta
  com item assim não confirma (`422 registration_unresolved_items`); a recusa em
  si não foi capturada no relato. Agora: leite integral 122 kcal + whey protein
  em pó 105,6 kcal = 227,6 kcal · P 29,7 · C 11,5 · G 7,0, nada bloqueado.
- "leite integral" 200 g (achado F23): 224,9 kcal ("Canjica, com leite
  integral") → 122 kcal.
- Números que o cliente já viu (prints do grupo, lidos no mapa de regras da
  audit; os prints não foram relidos): whey 30 g aparecia como 114 kcal nos
  cards de 08/05 e 14/07/2026 e passa a 105,6 quando o item chega como "whey".
  O card de 14/07 trazia o nome "whey protein", que NÃO está na lista (pendência
  abaixo). "leite integral (240 ml) — 146 kcal" continua 146 no card: a linha
  verificada dá 61 × 2,4 = 146,4 kcal e o card mostra kcal inteira.

### 9d. Interruptor de reversão

Esvaziar `EVERYDAY_FOOD_DEFAULTS` em
`packages/agent/src/everyday-food-defaults.ts` (ou tirar uma entrada). Os itens
novos voltam ao cálculo anterior e nada mais é somado numa linha. Não há
migration a desfazer. O teste da lista e os testes do relato (golden e teste do
app, §9e) falham de propósito com a lista vazia e são revertidos junto.

**O que a reversão NÃO desfaz:** nenhum registro é apagado nem recalculado. Por
30 dias (janela do histórico do paciente), quem já registrou com o nome
mostrado continua recebendo o valor desse registro: "leite integral" 200 g sai
com 122 kcal (fonte `history`), e não com os 224,9 kcal que o cálculo anterior
dá a quem não tem o registro. "leite" digitado volta a leite de coco (332,3
kcal) na hora.

### 9e. Testes que travam

- `packages/agent/src/everyday-food-defaults.test.ts` — invariantes de toda entrada.
- `packages/agent/src/__golden__/audit-10-04-app-leite-whey.test.ts` — relato
  exato, catálogo sem as linhas, soma numa linha, precedências, reversão e o que
  ela não desfaz, texto da proposta do WhatsApp.
- `apps/admin/src/lib/mobile-api/registration-service.everyday-defaults.test.ts`
  — propose, edição e confirm pelo serviço do app com a ferramenta real.

### 9f. Pendências declaradas

> RC M2 — cenário frase "1 copo de leite com whey no jantar" passando pelo extrator de texto do app NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A fixture entra com os itens "leite" 200 g e "whey" 30 g, como no relato; os
> nomes que o extrator gravou no pending real não foram lidos. Se ele devolver
> "leite no jantar" ou "copo de leite", o nome não está na lista.

> RC M2 — cenário medida caseira ("1 copo", "1 scoop") sem gramas NÃO coberto nesta PR (pendência da audit 2026-10-04).
> O app continua pedindo as gramas (achado F25).

> RC M2 — cenário item único "leite com whey" (WhatsApp, relatos C6-14 e C6-22) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Continua sem cálculo (`composite_rejected`): falta a receita padrão, que o
> cliente não disse.

> RC M2 — cenário "leite desnatado", "leite semidesnatado", "leite de vaca", "leite de soja" e "whey protein" NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Não estão na lista e seguem o cálculo de antes, com os erros de antes.

> RC M2 — cenário correção aprendida do paciente sobre o nome mostrado ("leite integral" → outro) aplicada ao nome digitado "leite" NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A correção é procurada pelo nome que chegou ("leite"), não pelo mostrado.

> RC M2 — cenário dois itens de mesmo nome FORA da lista do dia a dia na mesma proposta (por exemplo "leite de coco" 100 g duas vezes) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Limite anterior a esta mudança e inalterado: a proposta mostra as duas linhas
> (332,4 kcal) e a dedup do confirm grava uma (166,2 kcal).

> RC M2 — cenário item da lista ao lado de outra linha que sai com o MESMO nome mostrado por outra fonte — kcal dita pelo paciente, correção ativa do paciente com macro próprio ou rótulo aprovado (por exemplo "leite" 200 g e "leite integral" 200 g com 90 kcal) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Vale para QUALQUER linha que saia com o nome mostrado por outra fonte que não
> a linha do catálogo da lista: kcal dita pelo paciente, correção ativa do
> paciente com macro próprio e rótulo aprovado. Só as linhas do padrão do dia a
> dia são somadas numa só. Com kcal dita pelo paciente: a proposta mostra duas
> linhas "leite integral" (122 e 90 kcal) e, no confirm, a dedup lança "conflito
> nutricional entre cópias de leite integral"; nada é gravado. Com correção
> ativa "leite desnatado" → "leite integral" a 35 kcal/100 g, itens "leite"
> 200 g e "leite desnatado" 200 g: duas linhas "leite integral" (122 e 70 kcal,
> 192 no total) e o mesmo conflito no confirm; com gramas diferentes (200 g e
> 150 g) a dedup do confirm soma as duas numa linha de 350 g e 174,5 kcal. Com
> rótulo aprovado: mesmo mecanismo, não executado. Antes da renomeação os nomes
> eram diferentes e os dois eram gravados.

> RC M2 — cenário proposta do app com outro item depois dos dois itens somados (quantity_basis e candidate_id lidos por posição em registration-service.ts) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> A proposta tem uma linha a menos que o pedido; o item seguinte recebe o
> `quantity_basis` e o `candidate_id` do item que foi somado. Kcal, gramas, nomes
> e o dia ficam certos. O cálculo devolve `input_indexes`; o serviço ainda não lê.

> RC M2 — cenário WhatsApp ponta a ponta com "leite" e "leite integral" na mesma mensagem (pending, edição do pending e correção em 30 min da linha somada) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Coberto só no cálculo e nos argumentos do confirm.

> RC M2 — cenário WhatsApp ponta a ponta (o modelo chama registra_refeicao com "leite" e "whey" como itens separados) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Coberto só no cálculo e no texto da proposta; a gravação pela ferramenta real
> está no teste do app, pelo caminho do confirm.

> RC M2 — cenário tela do iPhone mostrando o nome assumido NÃO coberto nesta PR (pendência da audit 2026-10-04).
> O contrato não muda, mas nada foi executado no aparelho depois desta mudança;
> nem a proposta com UMA linha somada no lugar das duas digitadas.

> RC M2 — cenário correção em 30 min no WhatsApp de uma refeição com dois itens de leite (por exemplo "leite" e "leite em pó") NÃO coberto nesta PR (pendência da audit 2026-10-04).
> O nome digitado ("leite") contra o gravado ("leite integral") deixa de ser
> igual e passa a ser "contém": com outro item que contém "leite" o alvo da
> correção fica ambíguo.

> RC M2 — cenário registros e pendings anteriores a esta mudança ("leite" gravado como leite de coco, 332,3 kcal) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Nada é corrigido para trás; backfill exige autorização do Eduardo nomeando
> alvo e valores.

> RC M2 — cenário catálogo de PRODUÇÃO (linhas FDC:171265 e FDC:173180 verificadas, com os mesmos valores do staging) NÃO coberto nesta PR (pendência da audit 2026-10-04).
> Não foi lido. Sem as linhas, ou com valor diferente, a regra não age e o erro
> do relato continua.

> RC M2 — cenário lista de itens aprovada pelo cliente NÃO coberto nesta PR (pendência da audit 2026-10-04).
> O cliente disse a regra geral, não os itens.

### 9g. Para o cliente aprovar (uma linha por item)

| Quando o paciente escreve só | O sistema assume e mostra | Valor por 100 g (kcal · P · C · G) | Exemplo | Aprovo? (sim / não / outro) |
|---|---|---|---|---|
| leite (ou leite integral) | leite integral | 61 · 3,15 · 4,8 · 3,25 (USDA FDC:171265) | 200 ml = 122 kcal, 6,3 g de proteína | |
| whey (ou whey protein em pó) | whey protein em pó | 352 · 78,13 · 6,25 · 1,56 (USDA FDC:173180) | 30 g = 105,6 kcal, 23,4 g de proteína | |

Candidatos NÃO ativos, para ele dizer se entram e com qual item: leite
desnatado, leite semidesnatado, leite de vaca, whey protein, leite com whey
(precisa de receita padrão), café com leite. Os valores de cada um têm de ser
lidos da linha verificada do catálogo antes de ativar.

---

## 10. Cadastro: quem escolhe o objetivo e quem entra direto na recomposição (regra E)

> **Situação da regra:** escrita pelo cliente (Dr. Roberto) nas regras do método
> e dita por ele no grupo do projeto nas datas indicadas; **implementada em
> 2026-10-07 a pedido do Eduardo; confirmação do cliente pendente.** Não é
> decisão nova do cliente. A contradição do corte de IMC (§10c), cada leitura
> natural (§10d) e cada edição feita nos textos dele (§10m) estão marcadas uma a
> uma.

A regra é UMA função pura, `decideSignupEligibility`
(`packages/core/src/protocol-eligibility.ts`).

**Onde ela é aplicada hoje.** Em dois lugares do servidor, pela mesma conta:

- a conferência do cadastro (`POST /api/mobile/v1/onboarding/eligibility`,
  §10l), que responde a decisão com os textos do §10m e **não grava nada**;
- a conclusão do cadastro (`POST /api/mobile/v1/onboarding`, §10o), que na
  **primeira conclusão** recusa o objetivo que a conferência não marcaria
  disponível. Conta que já tem data de conclusão não é conferida.

Fora deles:

- o app publicado não chama a conferência, não lê os campos novos e não trata
  a recusa: nenhuma tela mudou (pendências no §10j);
- a linha `- Decisão automática: …` do contexto do turno (WhatsApp e Flow)
  continua vindo de `resolveProtocol` (`packages/core/src/protocol-router.ts`),
  que não foi tocada (§10h);
- a regra não entra em meta calórica, balanço, bloco nem card (§1 a §4).

A troca de fase não faz parte desta regra: o cliente disse em 02/07/2026 que a
troca de protocolo "teria q ser feita em uma reavaliação"; ela fica para a
reavaliação. O servidor só LÊ o objetivo atual (`GET /api/mobile/v1/protocol`,
§10l).

### 10a. Entradas e cortes

Entram: sexo, altura, peso, gordura corporal (opcional) e musculação por semana.
**Não entram:** sono, alimentação organizada, idade, nível de atividade, fome.

Os cortes são os que já existem na configuração de cálculo
(`packages/core/src/calc-config.ts`). Nenhum número novo foi criado.

| Corte | Chave | Padrão do código |
|---|---|---|
| gordura a partir da qual a pessoa entra direto na recomposição | `bf_limits[sexo].recomp` | homem 20 · mulher 28 |
| gordura até a qual a composição do ganho de massa está cumprida | `bf_limits[sexo].gain` | homem 19 · mulher 27 |
| IMC a partir do qual, sem gordura, a pessoa entra direto na recomposição | `imc_limit_recomp` | 25 |
| musculação mínima por semana para o ganho de massa | `training_min` | 3 |

- Em execução essas chaves vêm de `global_config` (`calc.bf_limits`,
  `calc.imc_limit_recomp`, `calc.training_min`) e a linha substitui o padrão do
  código. Os valores dos bancos não foram lidos (pendência).
- **Linha que não guarda número** (texto como `"25"`, `null`, sexo ausente em
  `calc.bf_limits`): vale o padrão do código para aquele corte, e só para ele.
  A função lê cada corte como valor desconhecido, como `imcGoalStepPoints`
  (§8a). Um erro de digitação na linha não abre a escolha nem derruba a função.
  Não é regra clínica. Um número, qualquer que seja, é obedecido.
- **Texto não é convertido em número**, mesmo quando é diferente do padrão: com
  `calc.imc_limit_recomp = "26"` (texto) o corte continua 25 e 81 kg / 180 cm
  entra direto na recomposição; com `calc.training_min = "4"` (texto) o mínimo
  continua 3 e 3 treinos bastam. Com os números 26 e 4 os dois resultados mudam.
- **Configuração passada como `null`** (fora do tipo declarado; o carregador
  real sempre devolve um objeto): vale o padrão do código inteiro, como quando
  nenhuma configuração é passada. A função não lança.
- O IMC é o de `calcIMC` (`packages/core/src/nutrition.ts`): peso ÷ altura²,
  sem arredondar.

### 10b. A tabela como implementada

| # | Caso | Resultado | Fonte |
|---|---|---|---|
| C0 | gordura informada | decide a gordura; o IMC não é conferido | regra "Regra de Decisão Automática de Protocolo — Quando NÃO perguntar ao usuário" ("IMC ≥ 25 (quando BF não disponível)"), na lista de regras ativas de 01/06/2026; manual 9.4.1 (gordura "padrão-ouro"; IMC "ferramenta substituta temporária"). Leitura natural 1 (§10d) |
| C0 | gordura não informada | decide o IMC | as mesmas |
| C1 | homem com gordura ≥ 20% | recomposição, sem perguntar | mesma regra ("BF ≥ 20% (homens)"; "conduzir automaticamente para o protocolo de Recomposição Corporal, sem oferecer opção de escolha"); regra "Decisão de objetivo - critérios internos antes de deixar o usuário decidir" (3.1); regra "Recomposição - critérios de entrada" (8.2); áudio de 24/01/2026 18:42 |
| C2 | mulher com gordura ≥ 28% | recomposição, sem perguntar | as mesmas ("BF ≥ 28% (mulheres)") |
| C3 | sem gordura e IMC ≥ 25 (o 25,0 exato entra) | recomposição, sem perguntar | as mesmas ("IMC ≥ 25 (quando BF não disponível)"); texto de 01/02/2026 ("o IMC de 25 entra mesmo na recomposiçõa corporal"); texto e áudio de 25/03/2026 ("menor q 25", "Sem o igual") |
| C4 | homem com gordura < 20%, mulher < 28%, ou sem gordura e IMC < 25 | a pessoa escolhe; as três opções são apresentadas | mesma regra, parte "Quando perguntar" ("apresentar as 3 opções"); regra "Pergunta de qual objetivo, se usuário dentro da faixa saudável"; áudio de 24/01/2026 18:42; texto de 15/05/2026 07:24 |
| C5 | em C4, recomposição | disponível | opção 1 da pergunta; áudio de 28/12/2025 16:02 |
| C6 | em C4, manutenção | disponível, também quando o ganho de massa está barrado | opção 3 da pergunta; 3.3; áudio de 28/12/2025 16:02. Leitura natural 2 |
| C7 | em C4, ganho de massa | disponível só com (a) composição — gordura ≤ 19% (homem) / ≤ 27% (mulher) quando informada; sem gordura, nada além do IMC < 25 que C4 já exigiu — e (b) musculação ≥ 3 vezes por semana. Faltando (a) ou (b): barrado, com o motivo | regra "Ganho de massa muscular - Critérios de entrada" (o mesmo texto na tabela de 02/02/2026 e na lista de 01/06/2026); áudio de 28/12/2025 14:07 (musculação pelo menos 3 vezes por semana; na transcrição, "pelo -3 vezes por semana de musculação"). Corte de IMC: contradição do §10c. Leituras naturais 3, 4 e 5 |
| C8 | texto para quem é colocado em recomposição | a função devolve o motivo `composition`; o servidor mostra o aviso de recomposição definida (redação nossa) e, no ganho de massa, a frase de bloqueio 3.4.1 do cliente, adaptada (§10l, §10m) | regra "Bloqueio de ganho de massa para quem está acima do peso"; áudio de 24/01/2026 (conteúdo do aviso) |
| C9 | texto para quem escolhe e tem o ganho barrado | a função devolve `composition` e/ou `training` e os cortes aplicados; o servidor mostra um motivo curto por critério, com o corte (redação nossa, §10m). A frase 3.4.1 **não** é usada aqui: ela termina conduzindo à recomposição, e esta pessoa pode escolher manutenção | não existe frase do cliente para este caso |
| C10 | sono ≥ 6h30 e alimentação organizada | não são lidos: não liberam nem barram | leitura natural 6 |
| C11 | peso muito baixo | nada especial acontece (pendência) | o cliente manda bloquear a perda de gordura (3.5), mas o número não existe em nenhum documento dele |
| C12 | gordura informada de até 10% | nada especial acontece (pendência) | o piso de 10% (§8b) é de redução; não há regra para a entrada |

Para quem é colocado em recomposição (C1 a C3) a função devolve manutenção
`not_offered` ("sem oferecer opção de escolha") e ganho de massa `blocked` com
`composition` sempre entre os motivos ("se o usuário solicitar ganho de massa,
aplicar a frase de bloqueio educada"). `training` entra junto quando a
musculação é menor que o mínimo: é um fato a mais, não um segundo aviso.

Com os cortes padrão (IMC entre parênteses; "três" = recomposição, ganho de
massa e manutenção disponíveis):

| Pessoa | Resultado |
|---|---|
| homem, gordura 20,0% | recomposição sem perguntar |
| homem, gordura 19,99%, 5 treinos | escolhe; ganho barrado por composição |
| homem, gordura 19,0%, 3 treinos | escolhe; três |
| homem, gordura 19,0%, 2 treinos | escolhe; ganho barrado por musculação |
| homem, gordura 19,5%, 2 treinos | escolhe; ganho barrado pelos dois motivos |
| mulher, gordura 28,0% | recomposição sem perguntar |
| mulher, gordura 27,0%, 3 treinos | escolhe; três |
| mulher, gordura 27,5%, 3 treinos | escolhe; ganho barrado por composição |
| sem gordura, 81 kg / 180 cm (25,0) | recomposição sem perguntar |
| sem gordura, 64 kg / 160 cm (25,0; no computador 24,999999999999996) | recomposição sem perguntar |
| sem gordura, 99,96 kg / 200 cm (24,99), 3 treinos | escolhe; três |
| sem gordura, 79,38 kg / 180 cm (24,5), 3 treinos | escolhe; três |
| sem gordura, 79,38 kg / 180 cm (24,5), 2 treinos | escolhe; ganho barrado por musculação |
| sem gordura, 77,76 kg / 180 cm (24,0), 3 treinos | escolhe; três |
| homem, gordura 15%, 84,24 kg / 180 cm (26,0), 3 treinos | escolhe; três (decide a gordura) |
| homem, gordura 22%, 74,52 kg / 180 cm (23,0) | recomposição sem perguntar (decide a gordura) |
| homem, gordura 19,5%, 71,28 kg / 180 cm (22,0), 5 treinos | escolhe; ganho barrado por composição |
| o mesmo corpo sem gordura informada | escolhe; três |

### 10c. Contradição texto × fala posterior: o corte de IMC do ganho de massa sem gordura

- **Texto escrito:** o critério de entrada do ganho diz "IMC ≤ 24 com aparência
  funcional adequada" (regra "Ganho de massa muscular - Critérios de entrada":
  tabela de 02/02/2026 e, sem mudança, lista de regras ativas de 01/06/2026). A
  regra 3.2 diz "IMC ≤ 24 ou aparência funcional adequada".
- **História do número no critério de entrada:** no manual de 27/12/2025 o
  critério dizia "IMC ≤ 25 com aparência funcional adequada" (a 3.2 do mesmo
  manual já dizia "IMC ≤ 24 ou aparência funcional adequada"). Na tabela de
  02/02/2026 passou a "IMC ≤ 24 com aparência funcional adequada"; nesse dia, às
  15:48, o cliente escreveu "aqui eu modifiquei o valor pra que não haja
  interseção" (a mensagem não diz qual valor). É o que existe a favor da leitura
  implementada: o número deste critério já foi 25, e "menor que 25" também não
  tem interseção com a faixa de quem entra direto na recomposição (IMC ≥ 25).
- **Fala posterior:** em 25/03/2026, sobre um print das regras (o print não foi
  relido; o "menor ou igual a 24" só existe neste critério e na 3.2), o cliente
  escreveu (19:42) "Acho q aqui poderia retirar esse menor ou igual do 24 e
  deixar só menor"; perguntado se era menor que 25 ou menor que 24, respondeu
  (19:43)
  "Isso, menor q 25", "Sem o igual", "Q aí o 25 não estaria na faixa da
  normalidade". No áudio das 19:43: "No que tá aí menor = 24 aí você tira o
  igual … menor que 25 na verdade … incluiria o 24 e não o 25 … o 25 estaria
  fora da faixa da normalidade".
- **Do que a conversa daquela noite tratava** (duas frases do cliente, do mesmo
  dia): no áudio das 19:16 ele pede para conferir "se a faixa da normalidade é
  menor do que 25 ou se o 25 já entra … na faixa da normalidade pra poder
  escolher o protocolo"; no texto das 19:42:59, logo depois de propor tirar o
  "menor ou igual do 24", escreve "Pq aí el na daria a opção de manutenção pro
  25 e retiraria esse conflito" (lemos "ele não daria"). O assunto era a faixa
  de quem ESCOLHE o protocolo — se o IMC de 25 fica dentro ou fora da
  normalidade e a opção de manutenção para o 25 (C3 e C4). Nos áudios e nos
  textos do cliente daquela noite, das 19:16 às 19:43, o ganho de massa não é
  citado.
- **Aplicar o "menor que 25" ao critério de ENTRADA do ganho de massa (C7) é
  leitura nossa, não frase do cliente.** Ela se apoia só em que o "menor ou
  igual a 24" não existe em nenhuma outra regra além deste critério e da 3.2.
  **Confirmação do cliente pendente** (pergunta 1 do §10k).
- **Implementado: a fala posterior, lida assim**, um único corte de IMC
  (`imc_limit_recomp`, 25). Sem gordura, IMC ≥ 25 entra direto na recomposição;
  IMC < 25 escolhe, e o ganho de massa depende só da musculação. Não existe
  constante "IMC ≤ 24" no código. **Implementada em 2026-10-07 a pedido do
  Eduardo; confirmação do cliente pendente.**
- O que muda entre os dois lados: sem gordura, IMC acima de 24 e abaixo de 25.
  Exemplo: 79,38 kg / 180 cm (IMC 24,5) com 3 treinos tem o ganho disponível;
  pelo texto escrito estaria barrado.
- Existe uma terceira redação, fora desta regra: a reavaliação da recomposição
  usa "IMC < 24" como entrada na normalidade sem fotos (já citada na pendência
  R3 do §8c).

### 10d. Leituras naturais

Onde o texto do cliente não fecha, a função segue a leitura abaixo. **Cada uma
foi implementada em 2026-10-07 a pedido do Eduardo; confirmação do cliente
pendente.**

1. **A gordura digitada pela pessoa vale como gordura disponível (C0).** No
   método a gordura vem das fotos avaliadas ou de medida confiável; o cadastro
   do app só tem o número digitado. Implementada em 2026-10-07 a pedido do
   Eduardo; confirmação do cliente pendente.
2. **Manutenção continua disponível quando o ganho de massa está barrado (C6).**
   A regra de prioridade máxima dá as três opções a quem está na faixa; a regra
   8.2 ("ausência dos critérios mínimos para ganho de massa muscular") e a frase
   de bloqueio 3.4.1 levariam à recomposição. Em 15/05/2026 o cliente reclamou
   de pessoa dentro da normalidade que não pôde escolher "entre os 3 possiveis".
   Implementada em 2026-10-07 a pedido do Eduardo; confirmação do cliente
   pendente.
3. **Com gordura informada, o IMC não é conferido para o ganho de massa (C7).**
   O critério de entrada diz composição "pelo menos um"; a regra 3.2 diz
   "cumprir todos". Homem com 15% e IMC 26 tem o ganho disponível. Implementada
   em 2026-10-07 a pedido do Eduardo; confirmação do cliente pendente.
4. **Faixa entre os cortes de gordura (C7): homem acima de 19% e abaixo de 20%,
   mulher acima de 27% e abaixo de 28%.** Essas pessoas estão na faixa em que se
   pergunta ("< 20%", "< 28%") e fora do critério de composição do ganho
   ("≤ 19%", "≤ 27%"): escolhem entre recomposição e manutenção, com o ganho de
   massa indisponível. O "pelo menos um" do critério de entrada permitiria
   liberar o ganho pelo IMC (homem com 19,5% e IMC 22); a função **não** faz
   isso, porque com gordura informada decide a gordura (C0). O mesmo corpo sem
   gordura informada tem o ganho disponível. Em 02/02/2026 o cliente escreveu
   "aqui eu modifiquei o valor pra que não haja interseção" (lemos como pensado
   em números inteiros); o app aceita decimais. A favor de barrar: a regra ATIVA
   "Ganho de massa muscular - Critérios de bloqueio do protocolo" (lista de
   01/06/2026) manda "bloquear ou pausar a fase de ganho" com "BF acima dos
   limites de entrada", e os limites de entrada são "≤ 19%" e "≤ 27%". Ela fala
   da fase em andamento, não do cadastro (leitura 6, fonte v). Implementada em
   2026-10-07 a pedido do Eduardo; confirmação do cliente pendente.
5. **Sem gordura, só o IMC conta para a composição do ganho (C7).** A "aparência
   funcional adequada" depende de fotos, que o cadastro do app não tem; não é
   avaliada. Implementada em 2026-10-07 a pedido do Eduardo; confirmação do
   cliente pendente.
6. **Sono e alimentação organizada não barram o ganho de massa (C10).** Cinco
   fontes: (i) o manual de 27/12/2025 exigia "sono médio ≥ 6h30" e "alimentação
   estruturada (não intuitiva solta)"; (ii) o critério de entrada atual (tabela
   de 02/02/2026, igual na lista de 01/06/2026) só tem composição e musculação
   e termina no singular, "Sem esse critério, superávit calórico vira gordura";
   (iii) a regra de coleta de dados da lista de 01/06/2026 ainda chama a
   alimentação estruturada de critério para o ganho; (iv) em 15/05/2026 07:50 o
   cliente escreveu que a pergunta de estruturação alimentar "atrapalhou a
   confirmação do protocolo e as frases q falam sobre o protocolo"; (v) a regra
   ATIVA "Ganho de massa muscular - Critérios de bloqueio do protocolo" (manual
   de 27/12/2025 e, com o mesmo texto, lista de regras ativas de 01/06/2026),
   que vai contra esta leitura: "O agente deve bloquear ou pausar a fase de
   ganho quando ocorrer qualquer um dos itens abaixo: BF acima dos limites de
   entrada / ausência de progressão no treino / alimentação inconsistente /
   histórico recente de perda de controle alimentar". Ela fala de bloquear ou
   pausar uma fase em andamento e não traz medida para o cadastro: não diz como
   medir "alimentação inconsistente" nem "histórico recente de perda de controle
   alimentar" na entrada, e "ausência de progressão no treino" só existe com a
   fase já em curso. Não cita sono. O único item com medida no cadastro, "BF
   acima dos limites de entrada", já é aplicado quando a gordura é informada (C7
   e leitura 4). Bloquear ou pausar a fase em andamento por esses quatro
   critérios fica fora desta regra (pendência no §10j). A conta antiga
   (`resolveProtocol`) continua exigindo sono e alimentação. Implementada em
   2026-10-07 a pedido do Eduardo; confirmação do cliente pendente.

A tabela de referência gordura × IMC da regra de decisão de objetivo (homem
"Normal / Saudável" com IMC 23–26) não é usada como corte: a coluna dela é "IMC
aproximado" e os cortes operacionais estão escritos à parte (3.1).

### 10e. O que a função devolve

Nenhum texto. O suficiente para quem chama escolher o texto (§10m) e conferir o
objetivo enviado:

```
outcome            'assigned'      colocado em recomposição, sem perguntar (C1 a C3)
                   'choice'        a pessoa escolhe (C4)
                   'invalid_input' a regra não consegue ler a entrada; nada é decidido (§10f)
assignedProtocol   'recomposicao'  só quando outcome = 'assigned'
basis              'BF' | 'IMC'    o que decidiu: a gordura informada ou, sem ela, o IMC
imc                número          como calcIMC devolve, sem arredondar
objectives         recomposicao / ganho_massa / manutencao, cada um com
                     status   'available' | 'blocked' | 'not_offered'
                     reasons  [] ou, só em 'blocked', 'composition' e/ou 'training', nessa ordem
limits             bodyFatRecomp, bodyFatGain (do sexo informado), imcRecomp, trainingMin:
                   os cortes aplicados, para o texto que precisar citar um
invalidFields      só em 'invalid_input': os campos com problema
```

| Situação | recomposição | ganho de massa | manutenção |
|---|---|---|---|
| `assigned` | `available` | `blocked` (`composition`; mais `training` se musculação < mínimo) | `not_offered` |
| `choice`, critérios do ganho cumpridos | `available` | `available` | `available` |
| `choice`, algum critério do ganho não cumprido | `available` | `blocked` (`composition` e/ou `training`) | `available` |

### 10f. Entrada inválida

A função devolve `outcome: 'invalid_input'` com `invalidFields` (na ordem
`sex`, `heightCm`, `weightKg`, `bodyFatPercent`, `trainingFrequency`) e **não
decide nada**: nenhum objetivo vem na resposta. É inválido:

- sexo que não é `masculino` nem `feminino`;
- altura ou peso ausente, que não é número, zero ou negativo (o IMC ficaria
  indefinido) — exigidos mesmo quando a gordura decidiria;
- dois números válidos cuja divisão não fecha (altura quase zero): `heightCm` e
  `weightKg`;
- gordura informada que não é um número maior que 0 e menor que 100 (não vira
  "sem gordura");
- musculação ausente, negativa ou que não é número;
- a própria entrada quando não é um objeto (ausente, `null`, um número, um
  texto — fora do tipo declarado): os cinco campos vêm em `invalidFields`,
  porque nenhum pôde ser lido, e a função não lança. Um objeto sem os campos
  (`{}`) continua lido campo a campo: a gordura ausente é "não informada", e
  os campos listados são os outros quatro.

Por quê: "recomposição" seria uma decisão clínica sobre dado que a regra não
consegue ler, e "pode escolher" abriria o ganho de massa sem conferência. O
documento do cliente não tem regra para dado ilegível; a função não inventa uma.

O que **não** é inválido: valor possível de calcular mas implausível (altura
digitada em metros, musculação fracionária ou acima de 7). É comparado como
está; a faixa de digitação fica no contrato do cadastro (100 a 250 cm, 30 a
300 kg, 3 a 60%, inteiro de 0 a 7).

### 10g. Tolerância numérica do IMC

`calcIMC` divide em ponto flutuante: 64 kg com 1,60 m dá 24,999999999999996, e
não 25. Uma comparação direta (`>= 25`) deixaria essa pessoa escolher, contra a
regra (o 25,0 entra na recomposição). A função compara com uma tolerância de
0,000000001 (`SIGNUP_IMC_ROUNDING_TOLERANCE`): IMC a menos disso do corte é
lido como estando no corte.

- **É correção de arredondamento do computador, não número clínico** e não foi
  dito pelo cliente. 80,999 kg / 180 cm (IMC 24,9997) escolhe — na função, que
  decide sobre o valor que recebe. A conferência do servidor arredonda antes
  para o valor que o banco grava (81,00 kg, IMC 25,0) e responde recomposição
  sem perguntar (§10l).
- Vale só para o IMC, que é calculado. A gordura é digitada e é comparada como
  está.
- A tolerância acompanha o corte da configuração.
- `resolveProtocol` continua comparando sem tolerância (pendência).

### 10h. O que NÃO mudou: `resolveProtocol`

`resolveProtocol` segue idêntica e continua sendo a que alimenta a linha
`- Decisão automática: …` (travada pelos goldens de 04/10). A função nova é
usada pela conferência (§10l) e pela conclusão do cadastro (§10o). As duas
contas diferem em quatro pontos, travados no golden desta seção:

| Caso | `resolveProtocol` (antiga, na linha do contexto) | `decideSignupEligibility` (nova, no cadastro do app) |
|---|---|---|
| 64 kg / 160 cm sem gordura | `canChoose=true` (compara sem tolerância) | recomposição sem perguntar |
| dentro da faixa com 2 treinos | `canChoose=false` (tira toda a escolha) | escolhe; só o ganho barrado |
| homem com 19,5% e tudo em ordem | `canChoose=false`, sem motivo listado | escolhe; ganho barrado por composição |
| 17%, 5 treinos, sono de 5h, alimentação não organizada | `canChoose=false` por sono e alimentação | escolhe; três |

Enquanto o Flow ler a linha antiga, ele pode repetir um bloqueio (sono,
alimentação) que o cadastro novo não aplica (pendência).

### 10i. Testes que travam

- `packages/core/tests/protocol-eligibility.test.ts` — forma da saída (objeto
  inteiro em cada resultado), cortes lidos da configuração (outra configuração
  muda cada corte; linha que não guarda número cai no padrão, inclusive texto
  diferente do padrão: `"26"` com 81 kg / 180 cm e `"4"` com 3 treinos),
  tolerância (64 kg / 160 cm; IMC 25,0 em toda altura de 140 a 210 cm; não é
  faixa), musculação 0, 1, 2, 3, 4 e 7, gordura em cada corte por sexo, gordura
  × IMC, entrada inválida campo a campo, entrada que não é objeto e
  configuração `null` (não lança), função pura.
- `packages/agent/src/__golden__/audit-10-07-signup-eligibility.test.ts` — os
  números do cliente, cada caso com a regra de onde vem; os dois casos do
  episódio real de 15/05/2026 como a lista de 01/06/2026 o registra (mulher com
  gordura 25%; mulher sem gordura com IMC 24,9 — peso, altura e musculação não
  constam nos documentos e foram escolhidos no teste); a configuração no formato
  do banco pelo carregador real (`loadCalcConfig`), com texto igual e diferente
  do padrão; entrada inválida; os casos omissos (peso muito baixo, gordura até
  10%); os dois exemplos das casas decimais (a função decide sobre o valor que
  recebe; quem arredonda é o servidor, §10l); as quatro diferenças para
  `resolveProtocol`.
- `packages/core/tests/protocol-router.test.ts`, `sleep-food-criteria.test.ts`
  e os goldens `audit-10-04-*` seguem travando o caminho antigo, sem edição.
- Etapa do servidor (§10l a §10n):
  - `packages/agent/src/__golden__/audit-10-07-protocol-messages.test.ts` —
    cada texto por igualdade exata em pt-BR e en-US; cada texto de entrada e a
    frase de bloqueio refeitos a partir do texto original do cliente com as
    edições do §10m, e só elas; nenhum nome proibido nem emoji, nos dois idiomas
    e nos dois sexos; a projeção de nomes do Flow devolve cada texto sem troca;
    o nome onde se espera; os únicos números dentro das frases do cliente são os
    que ele escreveu; as pendências do §10n.
  - `packages/core/tests/protocol-messages.test.ts` — parágrafos e linhas iguais
    nos dois idiomas, nome ausente, o corte e o mínimo vindos de quem chama.
  - `apps/admin/src/lib/mobile-api/protocol-eligibility-service.test.ts` — o
    arredondamento como o banco grava e os textos de cada resultado.
  - `apps/admin/src/app/api/mobile/v1/onboarding/eligibility/route.test.ts` — os
    números do cliente pela rota, com a função e o carregador reais; inglês;
    chave a mais recusada; **nenhuma escrita** (o banco de teste falha em
    qualquer insert, update, upsert, delete ou rpc); nada em log.
  - `apps/admin/src/lib/mobile-api/onboarding-service.test.ts` e
    `apps/admin/src/app/api/mobile/v1/onboarding/route.test.ts` — a mensagem de
    entrada dos três objetivos na conclusão, igual na repetição do pedido e fora
    do registro de idempotência.
  - `apps/admin/src/lib/mobile-api/protocol-service.test.ts` e
    `apps/admin/src/app/api/mobile/v1/protocol/route.test.ts` — a leitura do
    objetivo, com as metas iguais às de `GET /today` sobre o mesmo banco.
- Recusa na conclusão (§10o):
  - `apps/admin/src/app/api/mobile/v1/onboarding/route.test.ts` — os números do
    cliente pela rota inteira (invólucro, idempotência, conferência, carregador
    e função reais, sobre um banco em memória que reproduz os dois ramos da
    função SQL e o registro de idempotência como a migration dele escreve: o
    pedido que falha depois da reserva fica guardado como `failed`, com o hash,
    e o hash é comparado antes do estado): cada caso da tabela do §10o; a
    função SQL não é chamada na recusa; o pedido chega a ela inteiro; a
    conclusão aceita exatamente o que a conferência marca disponível (grade em
    volta de cada corte, os três objetivos); **o cenário do app publicado** —
    homem com 20,0% pedindo manutenção (e pedindo ganho de massa) recebe 422,
    repete e recebe 422, troca para recomposição e conclui, **tudo com a mesma
    chave**, sem nenhuma linha no registro até a conclusão; a chave que já
    estava presa a outro corpo por uma conclusão que falhou depois da reserva
    (422 primeiro, 409 para outro corpo, conclui com o corpo dela); o mesmo
    pedido enviado duas vezes ao mesmo tempo; a conferência antes das recusas
    da função SQL; novo aceite e repetição sem conferência, mesmo com os cortes
    mudados contra a conta; conta antiga sem data; conta que passou pelo reset;
    leitura do perfil ou da configuração que falha (sem registro de
    idempotência), data de conclusão que não é data, e leitura que dá certo sem
    linha `calc.*` ou com corte que não é número.
  - `apps/admin/src/lib/mobile-api/protocol-eligibility-service.test.ts` — a
    decisão única (`decideOnboardingEligibility`) é a que a conferência
    responde.
  - `apps/admin/src/lib/mobile-api/evaluation-access.test.ts` — conclusão
    recusada pelo objetivo não concede acesso de avaliação; as listas de
    consultas de cada conclusão passaram a incluir as duas leituras da
    conferência, antes da reserva da chave.

### 10j. Pendências declaradas

> RC E — cenário cadastro pelo app publicado (a etapa do objetivo oferece os três objetivos e não chama a conferência) variante uso da conferência pela tela, com o aviso, os motivos e só os objetivos disponíveis NÃO coberta nesta PR (pendência da audit 2026-10-07)
> O servidor já responde a conferência (§10l) e já recusa na gravação (§10o).
> Falta a tela: o app publicado deixa a pessoa tocar em qualquer um dos três.

> RC E — cenário versão do app anterior à etapa do app concluindo o cadastro com objetivo fora da regra variante explicação do motivo na tela e volta à etapa do objetivo (ela mostra só "Revise os dados informados.") NÃO coberta nesta PR (pendência da audit 2026-10-07)
> O servidor responde `422 onboarding_objective_not_eligible`; essa versão trata
> todo 422 da conclusão como dado inválido. A pessoa consegue voltar, tocar em
> outro objetivo e concluir, mas ninguém diz a ela qual: essa versão reenvia com
> a mesma chave de idempotência, e o servidor aceita porque a recusa é decidida
> antes da reserva da chave e não deixa registro (§10o; travado no teste da
> rota com o cenário exato). **Publicar a recusa junto com a versão do app que
> chama a conferência**, não antes.

> RC E — cenário conta antiga marcada como concluída sem data de conclusão que refaz o cadastro pelo app variante manter o protocolo antigo sem conferência NÃO coberta nesta PR (pendência da audit 2026-10-07)
> A coluna da data foi criada sem preencher as contas que já existiam (2 contas
> em staging, pela contagem de 2026-10-05 registrada no acesso de avaliação;
> nenhum banco foi lido nesta etapa). **A contagem de produção não foi feita:
> conferir antes de publicar**, porque para essa conta o resultado muda — antes
> ela concluía com qualquer objetivo. A função SQL já trata essa conta como
> primeira conclusão e regrava o protocolo dela; a conferência segue a função
> SQL. Com objetivo fora da regra ela recebe 422 e o protocolo que tinha fica;
> com objetivo permitido conclui e passa a ter data (travado no teste da rota).

> RC E — cenário primeira conclusão e novo aceite de termos contra a função SQL real do Postgres variante teste com o banco real (os testes usam um banco em memória que reproduz os dois ramos da função; nenhum banco foi lido nem gravado) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC E — cenário recusa do objetivo seguida de novo envio com a mesma chave de idempotência contra as funções reais do registro de idempotência do Postgres variante teste com o banco real (a migration 20260720130537 foi lida, não executada; os testes usam um registro em memória que a segue) NÃO coberta nesta PR (pendência da audit 2026-10-07)
> O que os testes travam: a recusa não chama nenhuma das três funções do
> registro. O que só o banco real confirma: que um registro `failed` responde
> conflito a outro corpo (é o motivo de a conferência rodar antes da reserva).

> RC E — cenário conta que passou pelo reset (perfil vazio e marcada como não concluída, com a data de conclusão mantida) refazendo o cadastro pelo app variante concluir o cadastro de novo, com a conferência do objetivo NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Defeito anterior a esta mudança e igual depois dela
> (`supabase/migrations/20260928150000_bodyflow_reset_keeps_plans.sql`): por ter
> data, a conta não é conferida, e a função SQL responde
> `409 onboarding_already_completed` (travado como está no teste da rota). Se o
> reset passar a esvaziar a data, rever no §10o a nota sobre a leitura fora da
> transação: hoje ela depende de nenhum código apagar uma data de conclusão.

> RC E — cenário cadastro de pessoa com peso muito baixo (desnutrição) variante bloqueio da perda de gordura e condução ao ganho de massa (o número do limite não existe em nenhum documento do cliente) NÃO coberta nesta PR (pendência da audit 2026-10-07)
> A função não faz nada especial: 45 kg / 180 cm (IMC 13,9) sem gordura escolhe
> entre os três (travado no golden). O 18,5 do §8b é piso de META de peso, não
> este número. Redeclara a pendência R4 de 04/10 (§8c). Também sem resposta: a
> pessoa muito magra que não faz musculação 3 vezes por semana.

> RC E — cenário cadastro com gordura informada de até 10% escolhendo recomposição variante piso de redução aplicado na entrada, e piso separado para mulher NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Homem com 8% e mulher com 10% escolhem entre os três (travado no golden).

> RC E — cenário ganho de massa sem gordura informada variante "aparência funcional adequada" (avaliação por fotos, que o cadastro do app não tem) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC E — cenário ganho de massa sem gordura informada com IMC acima de 24 e abaixo de 25 variante barrar o ganho pelo texto escrito "IMC ≤ 24" (critério de entrada, ainda na lista de 01/06/2026) NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Implementada a fala posterior (áudio de 25/03/2026 19:43, "menor que 25"); ver §10c.

> RC E — cenário gordura informada entre os cortes (homem acima de 19% e abaixo de 20%; mulher acima de 27% e abaixo de 28%) variante liberar o ganho de massa pelo IMC ("pelo menos um" do critério de entrada) NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Implementado: escolhe entre recomposição e manutenção, ganho barrado por
> composição. Homem 19,5% com IMC 22: barrado; o mesmo corpo sem gordura
> informada: liberado (travado no golden). Ver §10d, leitura 4.

> RC E — cenário gordura dentro do critério com IMC acima do corte (homem 15% e IMC 26) variante exigir também o IMC para o ganho de massa ("cumprir todos", regra 3.2) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC E — cenário pessoa dentro da faixa barrada no ganho de massa variante condução direta à recomposição, sem a opção de manutenção (regra 8.2 e frase de bloqueio 3.4.1) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC E — cenário sono abaixo de 6h30 ou alimentação não organizada variante barrar o ganho de massa por esses dois critérios (manual de 27/12/2025; regra de coleta de dados da lista de 01/06/2026) NÃO coberta nesta PR (pendência da audit 2026-10-07)
> A função não recebe sono nem alimentação. Ver §10d, leitura 6.

> RC E — cenário fase de ganho de massa em andamento variante bloquear ou pausar a fase pelos quatro critérios da regra "Ganho de massa muscular - Critérios de bloqueio do protocolo" ("BF acima dos limites de entrada", "ausência de progressão no treino", "alimentação inconsistente", "histórico recente de perda de controle alimentar") NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Regra ATIVA do cliente (manual de 27/12/2025; lista de 01/06/2026). Esta
> função só decide a entrada no cadastro e não recebe progressão de treino nem
> histórico alimentar. Ver §10d, leituras 4 e 6, e a pergunta 7 do §10k.

> RC E — cenário gordura digitada pela pessoa (sem fotos e sem medida conferida) variante tratar a gordura digitada como não disponível e decidir pelo IMC NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC E — cenário tabela de referência gordura × IMC da regra de decisão de objetivo (homem "Normal / Saudável" com IMC 23–26) variante usar as faixas da tabela como corte NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC E — cenário linha "Decisão automática" do contexto do Flow e do WhatsApp (resolveProtocol, ainda com sono e alimentação) variante mesma decisão do cadastro novo NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Alinhar mexe nos goldens de 04/10 e no caminho antigo; ver §10h.

> RC E — cenário IMC de 25,0 exato no caminho antigo (64 kg / 1,60 m dá 24,999999999999996; resolveProtocol compara sem tolerância) variante correção da conta antiga NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC E — cenário cortes em execução (linhas calc.bf_limits, calc.imc_limit_recomp e calc.training_min de global_config) variante leitura dos valores nos bancos de teste e de produção NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Nenhum banco foi lido. O golden usa as três linhas de staging registradas em
> 04/10 (20/19, 28/27, 25 e 3). A conferência (§10l) e, agora, a recusa na
> conclusão (§10o) decidem com essas linhas: um valor errado em uma delas passa
> a **recusar ou liberar cadastros**. Conferir antes de publicar. Conferir
> também que as três linhas **existem e guardam número**: só a leitura que
> falha responde 500; tabela sem linha `calc.*`, ou linha com texto no lugar do
> número, decide em silêncio com o padrão do código (§10a, §10o).

> RC E — cenário valor possível de calcular mas implausível (altura digitada em metros, musculação fracionária ou acima de 7) variante faixa de plausibilidade dentro da função NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Fica no contrato do cadastro (100 a 250 cm, 30 a 300 kg, 3 a 60%, inteiro de 0 a 7).

> RC E — cenário contas que já concluíram o cadastro com objetivo fora desta regra variante conferir ou mover essas contas NÃO coberta nesta PR (pendência da audit 2026-10-07)
> A recusa do §10o vale só para a primeira conclusão. Essas contas seguem no
> objetivo que têm e continuam aceitando termos novos (travado no teste da rota).

> RC E — cenário app fechado na tela da mensagem de entrada variante mensagem mostrada de novo na abertura seguinte (só volta a ser lida em Perfil, na E6) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC E — cenário pessoa definida em recomposição que pede ganho de massa variante conversa de bloqueio (na tela, a frase fica num detalhe que ela abre) NÃO coberta nesta PR (pendência da audit 2026-10-07)

Fechadas na etapa do servidor (2026-10-07), e por isso fora da lista acima:

- **Recusa, na gravação, do objetivo fora da regra**: a primeira conclusão do
  cadastro só grava o objetivo que a conferência marca disponível, decidindo
  sobre o valor arredondado como o banco grava (§10o). O que sobrou da
  pendência antiga é a tela (primeira linha da lista).

- **Texto mostrado à pessoa em cada resultado** (redação e tradução): os textos
  existem, travados por igualdade exata (§10m). O que falta é a aprovação, que
  passou para o §10n.
- **Valor com mais de duas casas decimais**: a conferência arredonda altura,
  peso e gordura como o banco grava antes de decidir (§10l). Homem com 19,995%
  → recomposição sem perguntar; 80,999 kg / 180 cm sem gordura → recomposição
  sem perguntar (travados no teste da rota). A função pura segue decidindo sobre
  o valor que recebe (travado no golden do §10i).

### 10k. Para o cliente confirmar

Nenhuma destas perguntas impediu construir a função; cada uma confirma uma
leitura acima ou fecha um caso declarado.

1. Ganho de massa sem gordura informada: IMC até 24 (texto) ou menor que 25?
   A fala de 25/03/2026 ("menor que 25", "sem o igual") tratava da faixa de quem
   escolhe o protocolo; ela vale também para o critério de entrada do ganho de
   massa? Implementado: menor que 25 (leitura nossa, §10c).
2. Homem acima de 19% e abaixo de 20%, mulher acima de 27% e abaixo de 28%:
   pode entrar no ganho de massa quando o IMC está abaixo de 25? Implementado:
   escolhe entre recomposição e manutenção; ganho indisponível.
3. Quem está dentro da faixa e é barrado no ganho pode escolher manutenção
   (implementado) ou vai obrigatoriamente para a recomposição?
4. Com a gordura dentro do critério, o IMC ainda precisa estar abaixo do corte
   para o ganho? Implementado: a gordura basta.
5. Sem fotos, o IMC sozinho basta para o ganho, sem a "aparência funcional
   adequada"? Implementado: basta.
6. A gordura que a pessoa digita vale como gordura conhecida para decidir o
   protocolo? Implementado: vale.
7. Sono de pelo menos 6h30 e alimentação organizada ainda são critério para o
   ganho de massa? Implementado: não barram. A regra ativa "Ganho de massa
   muscular - Critérios de bloqueio do protocolo" ainda manda bloquear ou pausar
   a fase de ganho por "alimentação inconsistente" e "histórico recente de perda
   de controle alimentar": ela vale também na entrada (e medida como?) ou só
   para a fase em andamento?
8. Qual número (IMC e/ou gordura) define peso muito baixo para barrar a perda
   de gordura? E para onde vai a pessoa muito magra que não faz musculação 3
   vezes por semana?
9. Quem chega ao cadastro com gordura de até 10% pode escolher recomposição?
   Existe piso separado para mulher?

### 10l. Onde a regra é aplicada no servidor: a conferência do cadastro

`POST /api/mobile/v1/onboarding/eligibility` (contrato em
`docs/mobile/api-v1.md`, "Conferência de objetivo no cadastro") recebe sexo,
altura, peso, gordura (opcional), musculação por semana e o idioma, e devolve a
decisão desta seção com os textos do §10m. Código:
`apps/admin/src/lib/mobile-api/protocol-eligibility-service.ts`
(`resolveOnboardingEligibility`) e
`apps/admin/src/app/api/mobile/v1/onboarding/eligibility/handler.ts`.

- **Não grava nada.** Nenhuma linha de banco, nenhum registro de idempotência,
  nenhum valor da pessoa em log. A única leitura é a da configuração de cálculo
  (`loadCalcConfig`: as linhas `calc.*` de `global_config`, a mesma leitura que
  o estado do dia faz). Se ela **falha**, a rota responde 500 e **não** decide
  com o padrão do código. Se ela dá certo e não traz nenhuma linha `calc.*`, ou
  traz um corte que não guarda número, vale o padrão do código (§10a): isso não
  é falha, nem aqui nem na conclusão (§10o). Antes dela roda só a autenticação
  comum a todas as rotas da API (que, no primeiro pedido de uma conta, cria o
  registro da conta, sem dado corporal — como em qualquer outra rota).
- **Faixas de entrada: as do cadastro**, pela mesma definição no contrato
  (100 a 250 cm, 30 a 300 kg, 3 a 60%, inteiro de 0 a 7). Chave a mais → 422.
- **A conferência só responde; quem recusa é a conclusão.** Na primeira
  conclusão, `POST /onboarding` só grava o objetivo que esta resposta marca
  `available` (§10o).

**Normalização antes de decidir.** `user_profiles` guarda altura e peso em
`numeric(5,2)` e gordura em `numeric(4,2)`; o contrato não limita as casas
decimais. A conclusão entrega o número ao banco como texto decimal, e o Postgres
arredonda `numeric` com a metade para longe do zero. Antes de chamar a função, o
servidor arredonda altura, peso e gordura a duas casas do mesmo jeito
(`asStoredBodyValue`), sobre o texto decimal do número e nunca em ponto
flutuante: 19,025 é gravado como 19,03, e tanto `Math.round(19.025 × 100) / 100`
quanto `toFixed(2)` dão 19,02; 27,005 é gravado como 27,01 — acima do corte de
27 — e `toFixed(2)` dá 27,00. Assim a resposta da conferência e o perfil gravado
não podem discordar.

| Enviado | Decidido sobre | Pela rota | A função, sem normalizar |
|---|---|---|---|
| homem, gordura 19,995% | 20,00% | recomposição sem perguntar | escolhe; ganho barrado por composição |
| homem, gordura 19,994% | 19,99% | escolhe; ganho barrado por composição | o mesmo |
| sem gordura, 80,999 kg / 180 cm | 81,00 kg (IMC 25,0) | recomposição sem perguntar | escolhe; três |
| sem gordura, 80,994 kg / 180 cm | 80,99 kg (IMC 24,997) | escolhe; três | o mesmo |

- Não é regra clínica nem número do cliente: é o arredondamento do banco,
  reproduzido em código. Nenhum banco foi lido para conferi-lo (pendência no
  §10n).
- A função pura continua decidindo sobre o valor que recebe (§10g; travado no
  golden do §10i). Quem normaliza é quem chama.

**O que a rota devolve.** Os nomes públicos do resultado do §10e:

| Função (§10e) | Rota |
|---|---|
| `outcome` `'assigned'` / `'choice'` | `decision` `"assigned"` / `"choice"` |
| `basis` `'BF'` / `'IMC'` | `basis` `"body_fat"` / `"bmi"` |
| `assignedProtocol` | `objective`: `"recomposicao"` quando `assigned`, senão `null` |
| — | `notice`: o aviso de recomposição definida quando `assigned`, senão `null` |
| `objectives` | `options`, sempre na ordem recomposição, ganho de massa, manutenção, cada uma com `status`, `reasons` e `message` |
| `'composition'` / `'training'` | `"gain_composition"` / `"gain_training"` |
| `limits` | não são devolvidos; o corte aparece dentro do texto do motivo |

Qual texto vai em cada resultado:

| Situação | `notice` | `message` do ganho de massa |
|---|---|---|
| colocada em recomposição (C1 a C3) | aviso de recomposição definida | a frase de bloqueio 3.4.1 adaptada, com "seu percentual de gordura atual" quando decidiu a gordura ou "seu IMC atual" quando decidiu o IMC. Só ela, mesmo quando a musculação também é menor que o mínimo (§10b) |
| escolhe, ganho disponível | `null` | vazio |
| escolhe, ganho barrado por composição | `null` | motivo da gordura, com o corte `bodyFatGain` do sexo |
| escolhe, ganho barrado por musculação | `null` | motivo da musculação, com `trainingMin` e o número informado |
| escolhe, ganho barrado pelos dois | `null` | os dois motivos, nessa ordem |

Recomposição e manutenção nunca trazem texto (`message` vazio).

**Mensagem de entrada na conclusão.** `POST /onboarding` devolve também
`protocol_welcome { protocol, paragraphs }`: o texto de entrada (§10m) do
objetivo GRAVADO, no idioma e com o nome do pedido. É a ordem do cliente (regra
"Gravação do Protocolo Escolhido pelo Usuário": "Somente APÓS confirmação da
gravação, apresentar a frase de boas-vindas do protocolo"): o texto é montado
depois que a função SQL responde. Sai igual em toda repetição do pedido (com a
ressalva dos valores de mais de duas casas decimais, declarada abaixo) e não
fica no registro de idempotência. A função SQL e o leitor do retorno dela não
mudaram.

**Leitura do objetivo atual.** `GET /api/mobile/v1/protocol` devolve o protocolo
do perfil, as metas do dia e a mesma mensagem de entrada. As metas são as da
tela Hoje, lidas do mesmo estado do dia (§4a) e não recalculadas: a meta gravada
na linha de hoje quando o dia já tem uma, senão a calculada do perfil. Só
leitura; não há troca de fase.

### 10m. Textos mostrados à pessoa: o que é do cliente, o que foi editado e o que é redação nossa

> **Confirmação do cliente pendente** para cada edição abaixo, para as três
> redações nossas e para a tradução. Implementado em 2026-10-07 a pedido do
> Eduardo.

Código: `packages/core/src/protocol-messages.ts` (funções puras, sem leitura nem
escrita). Os textos completos, nos dois idiomas, estão no código e travados por
igualdade exata no golden `audit-10-07-protocol-messages`. O golden também
refaz cada texto do cliente a partir do original com as edições desta seção, e
só elas.

Vale para todos os textos:

- nenhum traz o nome do método, o nome do médico, "BodyFlow", "BMR", "TDEE",
  "BF" como sigla nem emoji;
- nenhum número foi colocado dentro de frase do cliente;
- falam em primeira pessoa, como ele escreveu;
- cada função devolve parágrafos; um parágrafo pode ter quebras de linha simples.

**Edições comuns aos três textos de entrada**

- O cabeçalho interno de cada regra (título, "Esta seção descreve…", "Frase …
  de entrada…") não vai para a tela: é instrução para o agente.
- Só formato: os separadores de linha do arquivo exportado viram parágrafos e
  quebras de linha; `{nome}` é preenchido pelo servidor.
- Conta sem nome gravado: o vocativo ("{nome}, ") sai e a frase começa com
  maiúscula; nada mais muda. Na conclusão do cadastro o nome é obrigatório.

**Recomposição corporal** — regra "Recomposição corporal - Introdução e frase de
boas vindas ao protocolo".

1. TROCADO (nome do método): "na fase de recomposição corporal do MPP." →
   "na fase de recomposição corporal."
2. TROCADO (nome do método): "Para o MPP, cada bloco completo representa" →
   "Cada bloco completo representa".
3. CORTADO: "A cada 14 dias, fazemos uma reavaliação rápida para ajustar o
   plano, confirmar que tudo está no ritmo certo e manter o processo confortável
   e eficiente." Por quê: o app não tem reavaliação.
4. TROCADO: "A estratégia, os ajustes e a leitura dos dados ficam comigo." →
   "A estratégia e a leitura dos dados ficam comigo." Por quê: nada no app
   ajusta a meta sozinho.

Mantido: a palavra "método" sozinha, nas duas vezes em que ele a escreveu; os
blocos de 7.700 kcal (a tela de Progresso mostra o bloco); a meta diária.

**Ganho de massa muscular** — regra "Ganho de massa muscular - introdução de
boas vindas ao protocolo".

1. TROCADO (nome do método): "na fase de ganho de massa muscular do MPP." →
   "na fase de ganho de massa muscular."
2. CORTADO, com o emoji: "👉 Se houver qualquer mudança na sua frequência de
   treino — aumento ou redução — isso precisa ser informado." Por quê: no app
   não há onde informar.
3. CORTADO: "A cada 15 dias, fazemos reavaliações para confirmar que: o treino
   está progredindo, as calorias estão adequadas ao seu nível de treino, e a
   gordura segue dentro dos limites do método. Se algo sair do eixo, o plano é
   ajustado antes que vire problema." Por quê: o app não tem reavaliação. O
   "15 dias" dele some com o trecho; não foi trocado por 14.
4. TROCADO: "Eu cuido dos ajustes, dos limites e da estratégia, para garantir"
   → "Eu cuido da estratégia, para garantir". Por quê: não há ajuste, e os
   tetos de gordura e de IMC do ganho existem só como conta que nada aciona.

Mantido, com ressalva declarada (§10n): o parágrafo "Importante: a sua meta
calórica diária está diretamente ligada à frequência semanal de treino que você
informou…". No app a meta de calorias do ganho usa o nível de atividade,
perguntado à parte (§1); a musculação por semana entra na proteína (§1b). Com a
frase do item 2 cortada, o parágrafo alerta para o risco de treinar menos sem
dizer o que fazer. Mantido também: "sem musculação, não é possível prosseguir no
protocolo de ganho" — é a regra dele; ninguém é retirado do ganho sozinho
(pendência do §10j).

**Manutenção** — regra "Manutenção - Frase de boas vindas ao protocolo de
manutenção".

1. TROCADO (nome do método): "na fase de manutenção MPP —" → "na fase de
   manutenção —".
2. CORTADO: "Nesta fase, a gente também faz ajustes pequenos e inteligentes: se
   o peso começar a derivar, a correção é leve (geralmente ±100 kcal), baseada
   em tendência — não em um dia isolado." Por quê: o app não ajusta a meta.
3. CORTADO: "As reavaliações acontecem a cada 14 dias (ou antes, se sua rotina
   mudar, principalmente rotina de treinos), justamente para garantir que você
   continue no controle sem precisar ficar obcecado por números." Por quê: o app
   não tem reavaliação nem onde avisar que a rotina mudou. Com o trecho sai a
   única palavra no masculino ("obcecado").
4. TROCADO: "Eu cuido do monitoramento, dos ajustes e de manter o processo
   estável" → "Eu cuido do monitoramento e de manter o processo estável".

NÃO corrigido, fica como ele escreveu: "porque elas que sustentam sua composição
corporal e evita" (concordância) e as duas linhas que começam em minúscula
("muito abaixo disso…", "muito acima disso…").

**Frase de bloqueio do ganho de massa (3.4.1)** — regra "Bloqueio de ganho de
massa para quem está acima do peso". Usada SÓ para quem é colocado em
recomposição (C1 a C3), que é o caso para o qual ele a escreveu.

1. TROCADO: "seu percentual de gordura/IMC atual o coloca" → "seu percentual de
   gordura atual coloca você" quando decidiu a gordura, "seu IMC atual coloca
   você" quando decidiu o IMC. Por quê: o servidor escreve só o que decidiu, e
   "o coloca" está no masculino.
2. TROCADO, a última frase: "Assim que seus índices estiverem em uma faixa mais
   adequada, eu mesmo irei te conduzir para o protocolo de ganho de massa
   muscular, caso esse ainda seja o seu objetivo." → "O ganho de massa muscular
   não foi negado, apenas adiado: ele volta a ser considerado quando seus
   índices estiverem em uma faixa mais adequada, caso esse ainda seja o seu
   objetivo." Por quê: o app não percebe a mudança de faixa nem conduz ninguém,
   e a regra dele exige que a pessoa saia sabendo que existe um caminho até o
   ganho. "Não foi negado, apenas adiado" são palavras da instrução dele ao
   agente ("o ganho de massa não foi negado, apenas adiado estrategicamente").
   A frase nova ainda promete o que o app não faz (pendência no §10n).

As instruções ao agente da mesma regra não vão para a tela.

**Redações nossas** (não existe frase do cliente):

- Aviso de recomposição definida sem pergunta. Ele deu só o conteúdo, em áudio
  de 24/01/2026: dizer que a pessoa está fora da faixa da normalidade e que está
  sendo enquadrada automaticamente na recomposição. Usa "acima da faixa
  saudável" (palavras dele na regra de decisão), sem "acima do peso" e sem
  flexão de gênero.
  - pt-BR: "Pelos dados que você informou, você está acima da faixa saudável
    neste momento. Por isso, o seu protocolo é definido automaticamente:
    recomposição corporal."
  - en-US: "Based on the data you reported, you are above the healthy range at
    this moment. For that reason, your protocol is set automatically: body
    recomposition."
- Motivo da gordura entre os cortes (pessoa que escolhe, §10d leitura 4). Cita o
  corte de entrada do ganho, lido da decisão (`limits.bodyFatGain`: 19 para
  homem, 27 para mulher no padrão do código); nunca escrito no texto.
  - pt-BR: "O protocolo de ganho de massa muscular exige percentual de gordura
    corporal de até 19%. O percentual que você informou está acima desse
    limite."
  - en-US: "The muscle gain protocol requires a body fat percentage of 19% or
    less. The percentage you reported is above that limit."
- Motivo da musculação abaixo do mínimo (pessoa que escolhe). Montado com
  palavras dele do critério de entrada ("musculação ≥ 3x por semana"; "Sem esse
  critério, superávit calórico vira gordura."). O mínimo é lido da decisão
  (`limits.trainingMin`) e o segundo número é o que a pessoa informou.
  - pt-BR: "O protocolo de ganho de massa muscular exige musculação pelo menos 3
    vezes por semana. Sem esse critério, superávit calórico vira gordura. Você
    informou 2 por semana."
  - en-US: "The muscle gain protocol requires strength training at least 3 times
    a week. Without this criterion, a calorie surplus turns into fat. You
    reported 2 a week."

**Inglês: tradução nossa.** O cliente não escreveu nenhum texto em inglês. Os
três textos de entrada, a frase de bloqueio e as três redações acima foram
traduzidos por nós com os mesmos parágrafos e as mesmas linhas, sem acrescentar
nem suavizar nada, e estão travados por igualdade exata como o português.
"7.700 kcal" vira "7,700 kcal"; "IMC" vira "BMI".

**Para o cliente aprovar** (nenhum item impediu construir):

1. As edições acima nos três textos de entrada e na frase de bloqueio.
2. As três redações nossas.
3. A tradução em inglês.
4. No texto do ganho de massa, o parágrafo que liga a meta de calorias à
   frequência semanal de treino fica como está? E como treinos por semana viram
   nível de atividade?
5. No texto da manutenção, corrigir a concordância ("porque são elas que
   sustentam sua composição corporal e evitam que você perca…")?

### 10n. Pendências declaradas da etapa do servidor (textos, conferência e leitura do objetivo)

> RC B — cenário texto de entrada dos três protocolos variante promessa de reavaliação a cada 14 (ou 15) dias e de ajustes do plano (frases cortadas até a reavaliação existir no app) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC B — cenário texto de entrada do ganho de massa variante avisar mudança de frequência de treino (frase cortada: no app não há onde informar) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC B — cenário texto de entrada do ganho de massa variante meta de calorias ligada à frequência semanal de treino, como o texto diz (no app a meta de calorias usa o nível de atividade; a musculação por semana entra na proteína) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC B — cenário frase de bloqueio do ganho de massa para quem é colocado em recomposição variante promessa de voltar a considerar o ganho quando os índices melhorarem (o app não percebe a mudança de faixa e não tem saída da recomposição) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC B — cenário textos em inglês variante tradução aprovada pelo cliente (ele não escreveu nenhum texto em inglês; a tradução é nossa) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC B — cenário edições nos textos do cliente e redações nossas (aviso de recomposição definida, motivo da gordura entre os cortes, motivo da musculação abaixo do mínimo) variante aprovação do cliente e do Eduardo NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC B — cenário frase de entrega das metas do cliente ("plano inicial … organizado", com água, sono e passos) variante uso depois do cadastro NÃO coberta nesta PR (pendência da audit 2026-10-07)
> A conclusão devolve a mensagem de entrada; as metas continuam vindo de
> `GET /today`, sem a frase dele.

> RC B — cenário conferência do objetivo chamada antes do aceite dos documentos variante recusa no servidor (a ordem das telas é do app; a rota responde a qualquer conta autenticada e não guarda nada) NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC B — cenário app publicado hoje (ignora o campo novo e não chama as duas rotas novas) variante mensagem de entrada, conferência e objetivo no Perfil visíveis na tela NÃO coberta nesta PR (pendência da audit 2026-10-07)

> RC B — cenário valor com mais de duas casas decimais variante conferência do arredondamento contra o banco real (o arredondamento do numeric foi reproduzido em código; nenhum banco foi lido nesta etapa) NÃO coberta nesta PR (pendência da audit 2026-10-07)
> Desde o §10o a recusa na conclusão decide sobre esse mesmo arredondamento.

> RC B — cenário repetição da conclusão do cadastro com altura, peso ou gordura de mais de duas casas decimais variante mesma resposta na repetição (a função SQL compara o valor gravado, arredondado, com o enviado, e a repetição vira 409 onboarding_already_completed; comportamento anterior a esta mudança) NÃO coberta nesta PR (pendência da audit 2026-10-07)

### 10o. Onde a regra é aplicada na gravação: a conclusão do cadastro recusa objetivo fora da regra

`POST /api/mobile/v1/onboarding`, no formato com `document_actions` (contrato em
`docs/mobile/api-v1.md`, "Objetivo fora da regra na conclusão"), recusa na
**primeira conclusão** o objetivo que a conferência do §10l não marcaria
disponível. Assim a regra vale mesmo para um cliente que não chamou a
conferência. Código:
`apps/admin/src/lib/mobile-api/onboarding-eligibility-guard.ts`
(`assertOnboardingObjectiveEligible`), chamado em
`apps/admin/src/app/api/mobile/v1/onboarding/handler.ts` antes da reserva da
chave de idempotência e antes da função SQL.

> **Publicar junto com o app que chama a conferência.** A versão do app
> anterior à etapa do app mostra só "Revise os dados informados." a quem tocar
> em um objetivo fora da regra (pendência no §10j).

**O que é "primeira conclusão".** Lido na função SQL
`complete_mobile_onboarding_atomic`
(`supabase/migrations/20260915150739_bodyflow_server_owned_onboarding.sql`), não
suposto:

- a função lê `onboarding_completed` e `onboarding_completed_at` do perfil
  (linhas 347 a 353) e escolhe o caminho **só pela data**:
  `IF v_existing_completion IS NOT NULL` (linha 468);
- **com data** (linhas 468 a 562): confere que os dados reenviados são iguais
  aos gravados, inclusive o objetivo (linha 492; senão,
  `onboarding_already_completed`), grava só os aceites de documentos e devolve a
  data antiga. Nenhuma coluna do perfil é escrita. É o novo aceite de termos e a
  repetição de um pedido já concluído;
- **sem data** (linhas 564 a 639): grava o perfil, com
  `current_protocol = v_objective` (linha 622) e a data de conclusão (linha
  633). É o único ponto em que o cadastro do app grava o objetivo.

Por isso a conferência roda exatamente quando
`user_profiles.onboarding_completed_at` é lido como vazio. O booleano
`onboarding_completed` não entra, porque a função SQL também não o usa para
escolher o caminho.

**O que é decidido.**

- A resposta da conferência, por construção: as duas passam por
  `decideOnboardingEligibility`
  (`apps/admin/src/lib/mobile-api/protocol-eligibility-service.ts`), que
  arredonda altura, peso e gordura como o banco grava (`asStoredBodyValue`,
  §10l) e chama `decideSignupEligibility`. A configuração vem do mesmo
  `loadCalcConfig`.
- Só segue o objetivo com `status` `available` (§10e). `blocked` (ganho de
  massa barrado) e `not_offered` (manutenção de quem é colocado em
  recomposição) são recusados do mesmo jeito:
  `422 onboarding_objective_not_eligible`.
- Entram os mesmos cinco dados do §10a. Sono, alimentação organizada e os
  outros campos do cadastro não são lidos (C10).
- A recusa não leva dado da pessoa, motivo nem corte, e nada vai para log. O
  app pergunta de novo à conferência e mostra o que ela responder.

Com os cortes padrão, na primeira conclusão:

| Pessoa | Pede | Resultado |
|---|---|---|
| homem, gordura 20,0% | ganho de massa | 422; a função SQL não é chamada |
| homem, gordura 20,0% | manutenção | 422 |
| homem, gordura 20,0% | recomposição | conclui |
| mulher, gordura 27,0%, 3 treinos | ganho de massa | conclui |
| mulher, gordura 27,0%, 2 treinos | ganho de massa | 422 |
| mulher, gordura 27,0%, 2 treinos | manutenção | conclui |
| sem gordura, 64 kg / 160 cm (IMC 25,0) | manutenção | 422 |
| sem gordura, 79,38 kg / 180 cm (IMC 24,5), 3 treinos | ganho de massa | conclui (o corte é "menor que 25", §10c) |
| sem gordura, 81 kg / 180 cm (IMC 25,0), 3 treinos | ganho de massa | 422 |
| homem, gordura 19,995% (gravada como 20,00%) | manutenção | 422 |
| homem, gordura 19,994% (gravada como 19,99%) | manutenção | conclui; a função SQL recebe 19,994, como foi enviado |
| sem gordura, 80,999 kg / 180 cm (gravado como 81,00 kg), 3 treinos | ganho de massa | 422 |
| homem, gordura 15%, 3 treinos, dorme às 02:00, acorda às 07:00, alimentação "nao" | ganho de massa | conclui |

**Quem não passa pela conferência.** Toda conta que já tem data de conclusão. O
servidor lê a data, não carrega `calc.*` e entrega o pedido à função SQL, que se
comporta como antes:

| Conta com data de conclusão | Pedido | Resultado |
|---|---|---|
| em ganho de massa, homem com gordura 25% | novo aceite de termos, mesmos dados | conclui, com a data antiga |
| em manutenção, mulher com gordura 30% | novo aceite de termos | conclui |
| em ganho de massa, sem gordura, 81 kg / 180 cm, sem musculação | novo aceite de termos | conclui |
| mulher com 27% e 3 treinos que concluiu em ganho de massa; depois o mínimo de musculação da configuração sobe para 4 | repetição do mesmo pedido, com a mesma chave | a mesma resposta |
| homem com 19% e 3 treinos que concluiu em ganho de massa; depois o mínimo sobe para 4 | os mesmos dados com outra chave | conclui |
| em recomposição, homem com gordura 25% | envia ganho de massa | `409 onboarding_already_completed`, da função SQL, como antes |

Ninguém é movido: não há migration, correção de dados nem rotina que troque o
objetivo de uma conta existente.

**Falha fechada.** Se a data de conclusão não puder ser lida (erro, exceção,
resposta sem a coluna ou com um valor que não é data nem vazio — número, texto
em branco, texto que não é data) ou se a leitura de `calc.*` **falhar**, a
resposta é `500 data_access_failed`: a função SQL não é chamada e nada é
decidido no lugar da leitura que faltou — nem a recomposição, que a regra
libera para todos. Vale também para a conta já concluída cuja leitura falha.
Nenhum registro de idempotência é criado (a conferência roda antes da reserva
da chave), e o mesmo pedido pode ser reenviado com a mesma chave.

**Leitura que dá certo não é falha, mesmo sem os cortes.** Se `global_config`
não tiver nenhuma linha `calc.*`, o carregador devolve o padrão do código
(`packages/agent/src/calc-config-loader.ts`); se a linha de um corte guardar
algo que não é número, vale o padrão do código para aquele corte (§10a). Nos
dois casos a conclusão **decide** — com 20/19, 28/27, 25 e 3 —, igual à
conferência do §10l, que passa pelo mesmo carregador e pela mesma função. Não é
decisão desta etapa; o que muda com ela é que esse corte agora recusa ou libera
cadastros (pendência dos cortes em execução, §10j).

**Ressalva do cache.** Cada instância guarda as linhas `calc.*` por 60 segundos
(`packages/agent/src/calc-config-loader.ts`). Nos 60 segundos seguintes a uma
edição de um corte, a instância que responde a conferência e a que responde a
conclusão podem decidir com cortes diferentes: a conferência marca disponível e
a conclusão recusa, ou o contrário. Com a mesma configuração as duas nunca
divergem. Não editar cortes enquanto houver cadastro em andamento.

**Ordem dentro do pedido.** Validação do corpo → presença e formato da
`Idempotency-Key` (só o cabeçalho; nada é lido do banco antes) → conferência do
objetivo → reserva da chave no registro de idempotência → leitura do acesso de
avaliação, quando ligado (`docs/mobile/api-v1.md`) → função SQL. O pedido chega
à função SQL **inteiro e sem alteração**: o valor arredondado serve só para
decidir.

**Por que a conferência vem antes da reserva da chave.** O registro de
idempotência não apaga o pedido que falha depois da reserva: a linha fica
guardada como `failed`, com o hash do corpo, e a função de reserva compara o
hash **antes** de olhar o estado
(`supabase/migrations/20260720130537_mobile_api_idempotency.sql`, linhas 144 a
148 e 219; lido, não executado). Se a recusa acontecesse depois da reserva, a
chave ficaria presa ao corpo recusado por 24 horas, e o reenvio com o objetivo
corrigido receberia `409 idempotency_key_conflict`. É exatamente o que o app
publicado faz: ele reaproveita a chave da conclusão depois de um erro
(`OnboardingFlowModel.swift`, `pendingCompletionKey`). Com a conferência antes
da reserva:

| Pedido, sempre com a mesma chave | Resposta | Registro de idempotência |
|---|---|---|
| homem, gordura 20,0%, pede manutenção (ou ganho de massa) | 422 | nenhuma linha |
| o mesmo pedido de novo | 422, decidido de novo | nenhuma linha |
| troca para recomposição | conclui | uma linha, concluída |

Uma conclusão recusada pelo objetivo não grava perfil, aceite de documento,
acesso de avaliação nem registro de idempotência.

O que a ordem muda nas outras respostas, sempre em uma **primeira conclusão com
objetivo fora da regra** (com objetivo permitido, e em toda conta com data de
conclusão, a resposta é a de antes):

- a conferência responde antes de **todas** as recusas da função SQL, não só da
  de conta sem perfil: documento com versão antiga
  (`409 onboarding_requirements_changed`), dados que a função rejeita
  (`422 onboarding_rejected`), documentos indisponíveis (`503`) e conta sem
  perfil (`404`). Nada é gravado em nenhum dos casos;
- responde também antes dos dois `409` da chave (`idempotency_key_conflict` e
  `idempotency_request_in_progress`).

A chave que **já** estava presa a outro corpo — por uma conclusão que falhou
depois da reserva, por exemplo um erro da função SQL — continua respondendo
`409 idempotency_key_conflict` a um corpo diferente. Isso é anterior a esta
mudança e não é causado pela conferência (travado no teste da rota).

**A leitura fica fora da transação da função SQL.** É seguro no sentido que
importa: se outra conclusão da mesma conta for gravada entre a leitura e a
função, a função cai no caminho "com data", que não grava objetivo. O contrário
exigiria apagar uma data de conclusão, o que nenhum código faz.

**O que NÃO mudou.** A função SQL, o registro de idempotência e as migrations;
as 50 rotas e os hashes do BFF; `decideSignupEligibility`; `resolveProtocol`
(§10h); o formato parcial legado do mesmo POST, que não é conclusão, não grava
objetivo e não é conferido; meta calórica, balanço, bloco e card (§1 a §4).

**Custo.** Uma leitura de `user_profiles` (uma coluna) por conclusão. Na
primeira conclusão, também a leitura de `calc.*`, guardada por 60 segundos em
cada instância.

**Casos de borda.**

- Conta antiga marcada como concluída e sem data de conclusão: conferida como
  primeira conclusão, porque é assim que a função SQL a grava. Para ela o
  resultado muda (antes concluía com qualquer objetivo); a contagem de produção
  não foi feita (pendência no §10j).
- Conta sem linha de perfil: só uma data de conclusão LIDA dispensa a
  conferência, então ela roda. Com objetivo permitido, a resposta é a que a
  função SQL já dava (`404 patient_not_found`); nada é gravado nos dois casos.
- Conta que passou pelo reset: fica marcada como não concluída, mas mantém a
  data de conclusão. Por ter data, não é conferida, e a função SQL responde
  `409 onboarding_already_completed`, antes e depois desta mudança. Defeito
  anterior, declarado no §10j.

Testes: §10i.
