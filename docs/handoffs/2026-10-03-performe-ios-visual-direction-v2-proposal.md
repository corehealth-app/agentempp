# Performe AI iOS — segunda rejeição visual (03/10) e proposta de direção visual v2

**USER VISUAL ACCEPTANCE: REJECTED (03/10/2026, candidato `606d5d6` no iPhone).** Eduardo: "ainda está muito simples, sem efeitos, sem transição, não está suave, muito monocromático; poderia ter mais cores, gráficos; usar como inspiração os apps de Saúde & Fitness mais populares do Mobbin (animados, coloridos)". Pediu plano e análise.

Esta proposta **não executa nada**; é o plano para decisão. Mobbin devolve 403 ao navegador desta sessão; a análise usa os apps que lideram essa categoria por popularidade (Apple Fitness, Strava, MyFitnessPal, Yazio, Lifesum, Headspace, Calm, Oura, WHOOP, Noom, Zero, Gentler Streak, Flo, Nike Run Club, Peloton).

## 1. Por que o app parece simples e monocromático (diagnóstico no código)

| Causa | Evidência | Efeito percebido |
|---|---|---|
| **Uma cor só trabalha.** A paleta B2 tem teal, creme, carvão, coral e dourado, mas o app renderiza quase tudo em teal sobre creme; coral (`accentCoral`) e dourado (`achievement`) aparecem em pouquíssimos pontos | `DesignSystem/BodyFlowColor.swift` (21 papéis, 2 acentos quase sem consumidor) | "Monocromático" |
| **Dado = texto.** Calorias, proteína, hidratação, bloco e progresso são números em linhas; o único elemento gráfico é o anel de comida adicionado em `81543c6` | `Features/Today/*Section.swift`, `Features/Progress/ProgressComponents.swift` | "Sem gráficos" |
| **Superfícies planas por contrato.** A spec de 17/09 proíbe sombra/brilho/gradiente contínuo e limita motion a 200 ms (conteúdo) / 250 ms (disclosure), "sem loop decorativo" | `docs/superpowers/specs/2026-09-17-…-refinement-design.md` §130, §150 | "Sem efeitos, sem transição" |
| **Transições nativas só.** Push/sheet do sistema; troca de aba com fade+6 pt; nenhuma transição "hero" card→detalhe; nenhuma celebração ao concluir | `App/AppShellView.swift`, nenhum `navigationTransition`/`phaseAnimator`/`symbolEffect` no app | "Não está suave" |
| **Loading sem vida.** Shimmer removido hoje porque reiniciava em aba oculta e travava o XCTest (62 esperas) | `606d5d6` | Placeholders parados |

Conclusão: o resultado é fiel à direção **"Warm Performance" contida** que foi aprovada em 19/09 — a direção é que não corresponde ao que Eduardo quer agora. Mudar o resultado exige **mudar a direção**, não só adicionar efeitos.

## 2. O que os apps de referência fazem (padrões, não cópias)

**Visto no Mobbin pelo Chrome de Eduardo (03/10, conta sem Pro — só a primeira fileira de telas de cada app).** Os 15 mais populares em Saúde & Fitness: Headspace, How We Feel, stoic., Lifesum, Withings Health Mate, Strava, Hims, Gentler Streak, Apple Fitness, Apple Health, AllTrails, Ahead, Open, MyFitnessPal, Nike Run Club. Observações diretas:

- **Apple Fitness (Resumo):** fundo escuro; cartão "Activity Ring" com anel grosso vermelho e "46/250 CAL" ao lado; cartões pequenos de passos/distância com **mini-gráfico de barras por hora** em azul; semana como 7 anéis pequenos; calendário de anéis; detalhe do dia com anel grande + barras por hora.
- **Lifesum (Diário):** marca verde; cartão "Daily intake 340 / 1947 kcal" com **barra de progresso + três barras de macro** (carbo azul, proteína rosa, gordura roxa) cada uma com "x / meta g"; detalhe do alimento com **três anéis percentuais** (25 % / 7 % / 68 %) coloridos; "Food rating" com ✓/✗ coloridos; ilustração grande do alimento; botões verdes cheios.
- **MyFitnessPal (Hoje):** fundo azul claro; **linha de 7 dias** com check nos dias registrados; cartão Calorias "963 cal / 2.930 — 1.967 left" com barra azul; cartão Macros com **barras verde/roxa/amarela** e "x g / meta"; Diário por refeição com ícone + "Log"; entrada de alimento com **anel segmentado** por macro (782 cal) e barras "Percent of daily goals"; grade de ações rápidas com **ícones coloridos em bolhas** (azul, rosa, roxo, verde) e linhas Água (gota azul) / Peso (verde).

Padrões comuns a todos: uma cor por macro/métrica; número oficial grande + meta pequena + barra/anel; ícones com cor de domínio; fundo claro com um cartão forte; ação principal em botão cheio. Nada disso exige dados que o Performe AI não tenha (`calories_consumed/target`, `protein_g/target`, `carbs_g`, `fat_g`, `water_consumed_ml`, `exercise_calories`, dias com registro).

1. **Uma cor por métrica** (Apple Fitness: vermelho/verde/azul; Yazio/Lifesum: calorias, proteína, carbo, gordura cada um com sua cor; Oura: sono/prontidão/atividade). O olho aprende a cor antes de ler o número.
2. **Anéis e barras como linguagem principal** (Fitness, MyFitnessPal, Zero, WHOOP). O número oficial fica dentro ou ao lado do anel; o anel "varre" com mola quando o dado chega.
3. **Cartão-herói com gradiente** no topo da tela principal (Strava, Headspace, Calm, Gentler Streak): a única superfície com cor de fundo intensa; o resto é claro.
4. **Gráficos de tendência simples** (Strava, Oura, WHOOP, Flo): barras dos últimos 7/14 dias, linha de peso, faixa de sequência. Sem projeções.
5. **Números que contam** até o valor e **celebrações curtas** (Fitness ao fechar anel, Duolingo, Strava ao salvar): ≤ 1,5 s, finitas.
6. **Transição "hero"** do cartão para o detalhe (iOS 18 `navigationTransition(.zoom)`), ícone da aba que "pula" ao selecionar (`symbolEffect(.bounce)`).
7. **Modo escuro com brilho** suave nos anéis (Oura, WHOOP).
8. **Ilustração/personagem** (Headspace, Gentler Streak, Noom) — exige assets aprovados; o Performe AI tem o mascote como placeholder.

## 3. Proposta — blocos, esforço e o que cada um entrega

### E. Cor por domínio (fundação) — ~4 h
- Tokens **adicionais** (nada removido; testes de RGB travados só ganham casos): `energy` (coral quente, o `accentCoral` ganha papel), `protein` (teal/aqua), `hydration` (azul novo), `exercise` (dourado), `block` (dourado escuro/âmbar), `progress` (violeta), cada um com par claro/escuro e versão "wash" de fundo, contraste ≥ 4,5:1 verificado.
- Ícones por domínio (`BodyFlowSymbol`) com a cor do domínio em todo lugar: Hoje, Registrar (refeição/treino/hidratação/peso), Plano, Progresso, Histórico, trilha.
- Botões por papel ficam teal (marca); cor de domínio é para dado e contexto, não para ação.

### F. Hoje "vivo" — ~8 h
- **Cartão-herói Energia** com gradiente teal→aqua (ou escuro→teal no dark), anel grande **consumido ÷ meta** (sem exercício, CALCULO §3), número "Restam" contando até o valor, meta e consumido ao lado.
- **Macros em barras coloridas** proteína (com meta), carboidrato e gordura (já vêm no snapshot: `protein_g`, `carbs_g`, `fat_g`).
- **Hidratação** em anel azul com "onda" de preenchimento (`Shape` animada finita ao receber dado).
- **Bloco 7.700** como barra segmentada dourada (consumido − meta − exercício acumulado; só percentual oficial).
- **Trilha do dia** com nós coloridos pelo domínio e linha que "acende" até o nó alcançado.
- Registros do dia com ícone colorido por tipo de refeição.

### H. Motion v2 — ~8 h
- Transição **zoom** cartão→detalhe (Energia→detalhe, Bloco→detalhe, conteúdo da Biblioteca→leitura).
- Ícone da aba com `symbolEffect(.bounce)` na seleção; troca de aba com deslize lateral curto + fade (250–300 ms).
- **Celebração** finita (≤ 1,5 s, `phaseAnimator`): confirmar refeição, rotina "Tomado", concluir o tour, fechar o bloco. Partículas na cor do domínio; nada contínuo.
- Anéis/barras varrem com mola (600 ms) ao receber dado; números contam (`numericText`).
- Balões do Flow entram deslizando; indicador "Flow está escrevendo" animado **enquanto a resposta está em curso** (finito por natureza).
- Splash: fundo `MeshGradient` (iOS 18) que se move por 3 s e para; marca respira (já existe).
- **Regra aprendida hoje:** nenhuma animação de placeholder/decoração que reinicie sozinha (trava o XCTest); tudo finito e disparado por evento.

### G. Gráficos com dados reais (Swift Charts, framework do sistema, sem dependência) — ~10 h (BFF + iOS)
- **Novo endpoint BFF** `GET /mobile/v1/trends?days=14` lendo `daily_snapshots` (calorias consumidas × meta, exercício, proteína, água, `deficit_accumulated`, `xp_earned`, dia fechado) e histórico de peso. Hoje `/progress` devolve só o estado atual e `/weight` só grava — sem isso não há série para desenhar. Exige deploy Preview no staging (sem produção).
- Progresso: **peso ao longo do tempo** (linha com área suave), **14 dias de calorias × meta** (barras coloridas: abaixo/acima), **bloco acumulado** (área dourada até 7.700), **sequência** em faixa de dias.
- Hoje: mini-sparkline de 7 dias no cartão Energia.
- Verdade de capacidade mantida: dias sem registro ficam vazios, nada é estimado ou projetado; sem "score".

### I. Opcional — ilustração/personagem (depende de assets aprovados)
Estados ilustrados do Flow/mascote por cor (Headspace/Gentler Streak). Sem asset aprovado não entra; fica como decisão de marca.

## 4. O que precisa da decisão de Eduardo (conflitos com a autoridade vigente)

| Item | Travado em | Mudança proposta |
|---|---|---|
| Motion ≤ 200/250 ms, sem loop decorativo | spec 17/09 §150; `BodyFlowComponentPolicyTests` (durações 0/0,20/0,25) | Novas faixas: 250–300 ms navegação, 600 ms varredura de dado, ≤ 1,5 s celebração, sempre finitas e removidas sob Reduce Motion |
| "Evitar gradiente contínuo; sombra nunca como fronteira; sem brilho" | spec 17/09 §130 | Gradiente só no cartão-herói e na splash; brilho suave só nos anéis em modo escuro; sombra continua fora |
| Paleta B2 (5 cores) | spec 19/09; `BodyFlowSemanticColorTests` | Extensão aditiva com 6 cores de domínio (claro/escuro); os 5 originais intocados |
| "Sem gráficos/ranges" nos testes de Progresso (`PremiumConvergence`, Prompt14) | contratos de teste que proíbem chips 7D/4W e "Performance Score" | Gráficos de **dados reais** com janela fixa (14 dias); continuam proibidos score e projeção. Contratos atualizados na mesma PR, com a decisão registrada no corpo do commit |
| Endpoint novo no BFF | handoff: "sem infraestrutura paga nova" | Preview no projeto existente, sem custo novo; sem produção |

Se Eduardo aprovar, registro um **adendo de direção visual v2** na spec de 19/09 ("Warm Performance → Warm Performance Vivo") e cada bloco atualiza código + teste + doc juntos.

## 5. Ordem, checkpoints e prazo

| Passo | Conteúdo | Esforço | Gate |
|---|---|---|---|
| 1 | E + F (cor por domínio, Hoje vivo) | ~12 h | focados → integral → Release → **instalar e aceite parcial** |
| 2 | H (motion v2) | ~8 h | idem → **instalar e aceite** |
| 3 | G (endpoint + gráficos) | ~10 h | BFF gates + Preview → iOS → integral → Release → **instalar e aceite final** |

Total ≈ 30 h de execução + ~2 h de integral/gates por checkpoint ≈ **4–5 dias úteis**, com 3 instalações para Eduardo avaliar. Revisão adversarial antes de cada commit com mudança de contrato.

## 6. Riscos
- **Perfil de assinatura** expira 04/10 21:12 UTC; cada instalação a partir daí depende de reassinar (automático com a conta Apple logada no Xcode; mais simples com a conta paga aprovada).
- **XCTest e animação:** toda animação nova é finita e disparada por evento; a integral é o detector (esperas de idle = regressão).
- **Verdade dos dados:** gráficos só com o que existe em `daily_snapshots`/peso; contas novas mostram dias vazios, não exemplos.
- **Performance:** Swift Charts e gradientes são leves; partículas limitadas (≤ 40 elementos, 1,5 s). Par de benchmark do Flow reexecutado no checkpoint 2.
- **Referência direta ao Mobbin:** se Eduardo abrir a página no Chrome dele e nomear 3–5 apps/telas preferidas, calibro cor e composição por essas telas em vez de pela memória de catálogo.

## 7. Status
`USER VISUAL ACCEPTANCE: REJECTED (606d5d6)` · `VISUAL DIRECTION V2: PROPOSED, AWAITING EDUARDO` · `PRODUCTION STATUS: NOT DEPLOYED`.
