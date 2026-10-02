# Performe AI iOS — feedback visual de Eduardo (02/10) e proposta de melhorias

**USER VISUAL ACCEPTANCE: REJECTED (02/10/2026, candidato `05f4f7c` no iPhone).** Itens apontados por Eduardo: (1) tela de carregamento inicial "horrível, genérica, sem transição"; (2) sem transição ao tocar nos botões, não está suave; (3) o tutorial deveria ser guiado, apontando cada botão e explicando a trilha. Pediu estudo de apps famosos e sugestões.

## O que o app faz hoje (verificado no código e em frames do simulador)

| Ponto | Hoje | Onde |
|---|---|---|
| Abertura | Launch screen estática (teal + símbolo) → `SplashView` com símbolo, "Performe AI" e **spinner "Carregando"** → cross-fade 220 ms → Hoje com **skeleton de retângulos sem movimento** → conteúdo aparece de uma vez | `Features/Auth/SplashView.swift:65`, `BodyFlowLoading.swift:63`, `AppRootView.swift:35-44` |
| Botão primário | Ao pressionar só a borda passa de 1 para 2 pt; **sem escala/opacidade** | `BodyFlowButtonStyle.swift:31-34` |
| Rows/cards e botão central | Escala 0,98 + opacidade 140 ms (ok) | `BodyFlowRowButtonStyle.swift:14-29`, `PerformeBrandAction.swift:87-117` |
| Troca de aba | Conteúdo troca sem transição; só o realce da barra anima | `PerformeTabBar.swift:48-63` |
| Hápticas | Só em resultados (sucesso/erro) em 5 telas; **nenhuma no toque** | `BodyFlowHaptics.swift` |
| Tutorial | Folha paginada com texto por área; não aponta controles reais | `Features/Tutorial/GuidedTutorialView.swift` |

## O que os apps de referência fazem

- **Duolingo** — trilha visual (path) como tela principal; o personagem aponta o próximo passo; cada toque tem háptica leve e micro-animação; celebração curta ao concluir. Onboarding "aprende fazendo": o primeiro passo real é guiado dentro da tela, não num slideshow.
- **Noom** — "curso do dia" como trilha de cards; coach em chat; o app explica cada área na primeira visita (dica contextual), não tudo de uma vez.
- **MyFitnessPal** — botão "+" central para registrar; dicas em balão (coach marks) ancoradas no diário na primeira abertura; metas calculadas aparecem com transição, não de uma vez.
- **Strava** — leva direto à primeira ação (gravar atividade) e deixa o resto para depois; abertura com marca em movimento curto e sem spinner.
- **Headspace / Calm** — abertura "respirando": logo que cresce suave e dá lugar ao conteúdo; loading com forma do conteúdo e brilho sutil (shimmer); toques com molas curtas.
- **Apple Fitness / Health** — anéis e números que "contam" até o valor quando os dados chegam; transições nativas entre abas; feedback háptico em ações principais.
- **Yazio / Lifesum** — anel de calorias restantes animado ao carregar; skeleton com shimmer; cards que entram com leve deslocamento.

Guias que valem seguir: [Apple HIG — Launching](https://developer.apple.com/design/human-interface-guidelines/launching) (a launch screen deve virar a primeira tela sem "splash de logo" demorado), [coach marks: um elemento por vez, 1 frase, "2 de 6", pular sempre visível, contextual](https://screensdesign.com/articles/mobile-app-tooltip-coach-mark-examples/), [spotlight UI em onboarding](https://appstorys.com/blog-Coach-Marks-Spotlight-UI-Onboarding), [exemplos de onboarding fitness](https://screensdesign.com/articles/fitness-app-onboarding-examples/), [onboarding de apps conhecidos](https://uxcam.com/blog/10-apps-with-great-user-onboarding/).

## Proposta (prioridade e esforço)

### A. Abertura "viva" — ~4 h
1. **Sem spinner.** O símbolo da marca entra com escala 0,9→1 e leve brilho (400 ms, mola), "Performe AI" surge abaixo; sem texto "Carregando".
2. **Símbolo viaja para o cabeçalho** do Hoje (já existe `matchedGeometryEffect` "signal-spark-launch"; hoje ele é mascarado pelo spinner e pelo corte).
3. **Skeleton com shimmer** sutil (1,2 s, desligado em Reduce Motion / baixo consumo) e cards que entram com 8 pt de deslocamento + fade, em cascata de 40 ms.
4. **Números "contam"** (Restam para comida, proteína, hidratação) em 500 ms quando o dado chega; valores oficiais intocados, só a apresentação.
5. Meta: do toque no ícone ao Hoje utilizável em < 1,2 s na rede boa; nada bloqueia a restauração de sessão.

### B. Toque e navegação suaves — ~3 h
1. **Todo botão** (`BodyFlowButtonStyle`) com escala 0,97 + opacidade 0,9 ao pressionar, mola 140 ms.
2. **Háptica leve** (`.impact(.light)`) nos toques principais: Registrar central, Falar com o Flow, Enviar, Confirmar; `.selection` ao trocar de aba. Resultados mantêm sucesso/erro.
3. **Troca de aba com cross-fade** de 220 ms do conteúdo (barra já anima o realce); push/sheet com as transições nativas preservadas.
4. **Botão central** com "pulso" de 1 ciclo ao receber confirmação (já tem estados; falta o movimento).
Tudo respeita Reduce Motion (vira instantâneo) e os alvos de 44 pt.

### C. Tutorial guiado por "coach marks" — ~8 h
1. **Overlay escurecido com recorte** (spotlight) sobre o controle real: Falar com o Flow → Biblioteca → Registrar central → aba Plano → aba Progresso → aba Perfil (6 passos; "2 de 6"; "Pular" sempre visível; 1 frase por balão).
2. **Ancorado na geometria real** dos botões (anchor preferences), sem coordenadas fixas; reposiciona em Dynamic Type e Pro Max.
3. **Contextual:** na primeira vez que abrir Registrar, 1 balão em "Refeição"; na primeira vez no Flow, 1 balão no campo de mensagem. Máximo 3 dicas por sessão.
4. **Trilha:** um passo mostra como a jornada funciona — registrar → Hoje atualiza (Restam para comida) → Bloco 7.700 kcal → Progresso — com um mini-diagrama de 4 nós dentro do balão.
5. **VoiceOver**: o overlay vira leitura sequencial dos mesmos balões (sem recorte), e a folha atual "Conhecer o app" fica como texto completo no Perfil.
6. Mesmo estado por conta já implementado (oferecido 1×, "Agora não", replay).

### D. Opcional, depois do beta — ~6 h
- Anel de "Restam para comida" animado no Hoje (estilo Yazio/Fitness), com o mesmo número oficial.
- Trilha do dia visual no Hoje (nós concluídos/pendentes), inspirada em Duolingo/Noom, sem gamificação nova além do XP/bloco que já existem.

## Regras mantidas
Sem dependências novas; sem partículas/parallax contínuo; Reduce Motion/Transparency/Increase Contrast respeitados; fórmulas e valores oficiais intocados; WhatsApp/API/banco intocados; cada bloco com testes focados, revisão independente, integral e Release antes de instalar por cima no iPhone.

## Ordem sugerida
B (3 h) → A (4 h) → C (8 h) → integral + Release + instalação + novo aceite de Eduardo. Total ≈ 2 dias úteis de execução, com os gates.
