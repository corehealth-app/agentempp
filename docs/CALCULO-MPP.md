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
  - **Turno em que `define_protocolo` ou `define_meta_peso` rodou sem erro**
    (revisão de 2026-10-04): a regra genérica "verbo de registro + kcal ou
    🔥/💪/📊" não dispara — "Protocolo registrado … a meta não foi registrada …
    1.746 kcal" fala do protocolo e da meta, não de refeição (§8b). Continuam
    disparando nesse turno: o card "Total refeição", a proposta imitada
    ("Vi isso na sua foto … Confirma?"), os bullets com kcal, o "pulei" e o
    cardápio/treino inventado. Sem tool nenhuma, só com tool de leitura, só com
    `cadastra_dados_iniciais` ou com a tool em erro, nada mudou.
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
que `define_protocolo` ou `define_meta_peso` rodou **sem erro**, a regra
genérica do guard não dispara: 2 chamadas e o texto chega como o modelo
escreveu. Vale também para a meta ACEITA ("Meta registrada: 12% … 💪" depois de
`define_meta_peso` já disparava o guard antes desta PR) e não depende dos
interruptores do piso. Código: `goalToolRanThisTurn` em
`packages/agent/src/pipeline.ts` e `goalToolCalled` em
`packages/agent/src/fake-write-detector.ts`.

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

> RC R3 — cenário passo de 10 pontos ("perder 10 pontos do imc", texto de 07/02/2026) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R3 — cenário metas de IMC já gravadas com 30 NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem backfill.

> RC R3 — cenário IMC de 25,0 a 25,9 (manual: meta 25; código: 23) e normalidade "menor que 25" / "IMC < 24" NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R3 — cenário IMC de 30,95 a 30,99 (mostrado como 31.0) NÃO coberto nesta PR (pendência da audit 2026-10-04). Muda de 25 para 26; sem relato de paciente.

> RC R3 — cenário peso e altura reais dos prints C3-03, C2-49 e C2-50 NÃO coberto nesta PR (pendência da audit 2026-10-04). Os prints só trazem o IMC.

> RC R4 — cenário paciente que JÁ está abaixo do piso (gordura ≤ 10% ou IMC < 18,5) seguir em recomposição com déficit NÃO coberto nesta PR (pendência da audit 2026-10-04). Manual 3.5 e 9.3; exige mexer no cadastro do app.

> RC R4 — cenário C3-05 (09/02/2026: gordura 12%, IMC 25.7, "Meta de BF definida: 10%" antes de escolher protocolo) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R4 — cenário meta em kg que implica gordura abaixo de 10% (homem de 80 kg com 12% pedindo 76 kg) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R4 — cenário metas já gravadas abaixo do piso NÃO coberto nesta PR (pendência da audit 2026-10-04). Sem backfill; seguem na pergunta da reavaliação.

> RC R4 — cenário piso feminino (mulher pedindo de 10% a 11,9%) NÃO coberto nesta PR (pendência da audit 2026-10-04). O cliente nunca disse piso separado para mulher; continua aviso e grava. A recusa abaixo de 10% oferece "a partir de 12%" para não contradizer esse aviso.

> RC R4 — cenário meta de peso que ainda deixa o IMC abaixo de 18,5 GANHANDO peso (45 → 48 kg) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado.

> RC R4 — cenário meta de peso IGUAL ao peso atual, ou ganhando menos de 2% do peso, de quem já está abaixo de 18,5 (52 → 52 kg e 52 → 52,5 kg, 170 cm) NÃO coberto nesta PR (pendência da audit 2026-10-04). Inalterado: "manter" e grava. Perdendo, qualquer variação é recusada (54 → 53, 52 → 51,5, 40 → 39,3).

> RC R4 — cenário define_protocolo com meta de IMC abaixo de 18,5 de quem está GANHANDO peso (175 cm, 50 kg, ganho_massa, IMC 18) NÃO coberto nesta PR (pendência da audit 2026-10-04). A ferramenta não lê altura nem peso atual: descarta qualquer meta de IMC abaixo de 18,5 (o protocolo é gravado). A mesma pessoa em define_meta_peso (55,1 kg, ganhando) tem a meta gravada com aviso.

> RC R4 — cenário meta de peso GANHANDO com IMC bruto de 18,45 a 18,499 (50 → 53,4 kg, 170 cm) NÃO coberto nesta PR (pendência da audit 2026-10-04). Muda: era "Ótima meta — IMC 18.5", agora o aviso "IMC 18.4, abaixo do saudável … quer rever?"; continua gravada. Travado em teste, sem relato de paciente.

> RC R4 — cenário recusa da meta na reavaliação com fotos corporais ainda pendentes, e a redação do modelo nesse turno NÃO coberto nesta PR (pendência da audit 2026-10-04). O golden cobre o turno "não vou mandar fotos": o modelo recebe o goal_message e redige; o que ele escreve não é testado. Com fotos pendentes, o texto fixo "ainda falta foto …" também deixa de sair nesse turno (o modelo redige).

> RC R4 — cenário os dois classificadores executados com o piso em 0 dentro da suíte (o piso é uma constante do módulo; aqui só o que tools.ts importa é trocado) NÃO coberto nesta PR (pendência da audit 2026-10-04). Conferido à mão em 2026-10-04, numa cópia com as duas constantes em 0, contra o commit 55294c4.

> RC R4 — cenário define_protocolo com meta abaixo do piso quando já existe meta gravada NÃO coberto nesta PR (pendência da audit 2026-10-04). A meta anterior é apagada, como quando a meta é omitida.

> RC R4 — cenário escada automática dar 10% a mulher com até 15% de gordura, e 20% a mulher fora da normalidade (manual de 22/05/2026: ≤ 27%) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R4 — cenário conversa real depois da recusa (o modelo dizer que registrou ou repetir a chamada) e redação da recusa aprovada pelo cliente (manual 3.5.2) NÃO coberto nesta PR (pendência da audit 2026-10-04).

> RC R4 — cenário turno em que define_protocolo ou define_meta_peso gravou e o modelo TAMBÉM afirma uma refeição ou treino sem chamar a tool ("Almoço registrado … 521 kcal", sem o card "Total refeição") NÃO coberto nesta PR (pendência da audit 2026-10-04). Nesse turno a regra genérica do guard de escrita fantasma não dispara mais; o card "Total refeição", a proposta imitada, os bullets com kcal e o "pulei" continuam disparando. Sem relato de paciente.

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
