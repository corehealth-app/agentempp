# Performe AI — refinamento final iOS

**RELATÓRIO ATUALIZADO EM 03/10/2026 (continuação no Claude Code), sem aceite de cliente.** Em 02/10 Eduardo **rejeitou o aceite visual** do candidato `05f4f7c` no iPhone (abertura genérica e sem transição; toques sem suavidade; tutorial em texto em vez de guiado apontando os controles e explicando a trilha) e aprovou os quatro blocos da proposta ([`2026-10-02-performe-ios-visual-feedback-proposal.md`](2026-10-02-performe-ios-visual-feedback-proposal.md)). Novo candidato `606d5d6`: abertura viva (nome entra, marca respira 3 ciclos, linha "Carregando" só após 1,2 s), toques com mola/escala/háptica nos botões, linhas e abas, tour spotlight sobre os controles reais (8 etapas + trilha do dia, replay no Perfil, uma dica contextual no Registrar), anel de comida e trilha do dia no Hoje (`81543c6`), e placeholders estáticos após o shimmer provar-se causa de 62 travas de idle do XCTest (`606d5d6`). **Suíte integral 1.849/1.849 PASS, zero skips** (iOS 27); Release sim/staging, Analyze, assinatura e scanner dos dois bundles PASS. Pendentes: instalar por cima no iPhone e novo aceite visual de Eduardo, smoke físico, VoiceOver/tato reais, fluxo editorial da Biblioteca e canal de distribuição para Roberto.

## 1. RESUMO EXECUTIVO

**Atualização 02/10 (Claude Code):** o readiness do benchmark foi concluído (RED 7/2 → GREEN 10/10), o novo par Flow foi executado e analisado, o **tutorial inicial guiado** foi implementado e o candidato completo passou na integral **1.827/1.827, zero skips** e nos gates de Release. O texto abaixo desta nota é o histórico anterior a essa atualização.

Refinamento implementado localmente: Registrar central, abertura coerente com a marca, loading compartilhado, hierarquia de Hoje, acessibilidade e preservação de sessões/edições. Correções de Flow, teclado e captura têm cenários exatos, focados aprovados e revisão independente.

Builds, assinaturas e scanner passaram. Os pares controlados passaram: **standalone v2, 5/5 por lado; navegação/sheet v3, 2/2 por lado**, com condições registradas equivalentes. A integral anterior terminou com **1.776 PASS / 1 FAIL**; o contrato incorreto do teste de escala foi corrigido e passou no focado. **A nova integral foi interrompida após falha no Flow. Fixture, sincronização e compositor receberam correções, focados e revisão independente; Release/análise/assinatura atuais passaram. A integral final, o novo par Flow, performance nativa pendente, QA físico e aceite visual continuam abertos. O tutorial novo deverá integrar o candidato antes desses gates finais.**

Escopo desta rodada: iOS. **WhatsApp, API, banco e fórmulas nutricionais não foram alterados.** Nenhum ambiente pago novo. O candidato staging final não foi instalado nem distribuído.

## 2. AUDITORIA

Foram examinados contratos, fontes, diffs, testes e imagens, com revisão independente antes das correções graves. As regressões cobrem ACK/outbox, retry idempotente antigo em janelas de 40/50 mensagens, confirmação repetida, isolamento de sessão, leitura/edição entre abas e estados de recuperação.

O P3 de histórico vazio com outbox não confirmada recebeu RED nos dois casos, correção mínima e **30 testes/duas suítes GREEN**, commit `f7bae16`. A integral revelou depois o caso de acessório do teclado corrigido em `ebf64a9`; a evidência está resumida na seção 13. A revisão estática não substitui a integral ou o aparelho físico.

Cronologia completa: [ledger de implementação](/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1/docs/handoffs/2026-10-01-performe-ios-final-polish-implementation.md). Logs, xcresults e capturas ficam em `/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/` (diretório de evidências citado abaixo).

## 3. UX/UI

Ordem aprovada: **Hoje → Plano → Registrar → Progresso → Perfil**. O asset existente abre Registrar. `TabView`, IDs, rotas e cinco pilhas foram preservados; inset por tela/destino e controle UIKit compartilhado mantêm toque, acessibilidade e Large Content Viewer sem ações duplicadas.

Hoje prioriza alimentação restante, mantém consumo/meta e recolhe detalhes técnicos. O fixture de 731 restantes e 17 de excesso preserva ambos os valores oficiais. Plano usa um único scroll; Progresso mostra peso oficial disponível enquanto outra leitura aguarda.

Uma falha isolada de toque em Registrar no compacto permanece sem causa atribuída: a mesma fonte passou o diagnóstico, dez repetições L/AXXXL e o cenário original. Não houve correção especulativa.

## 4. SPLASH E ABERTURA

LaunchScreen e Splash compartilham teal profundo e símbolo negativo central. Layout adaptável e scroll acomodam viewport curto sem espera artificial. Renderings e UI landscape AXXXL passaram; abertura do Release final no iPhone físico permanece pendente. As evidências locais cobrem relançamento deslogado, Hoje sintético, restauração de sessão e estados offline/erro/stale. Warm resume, condições reais de cache/rede e a sequência visual completa ícone → Splash → Hoje ainda precisam de observação no smoke. Primeira instalação física não foi exercitada; a instalação autorizada deve preservar os dados do staging existente.

## 5. LOADING

Indicador com atraso visual cancelável de 150 ms, skeletons estáticos e respeito a Reduce Motion. Operações não são postergadas; onboarding mantém progresso determinado. O Flow considera outbox durante reconciliação, incluindo histórico oficial vazio. Evidência: `BodyFlowLoading.swift`, testes de apresentação e regressão `f7bae16`.

## 6. LOGO CENTRAL

Asset aprovado com seis estados: `idle`, `press`, `active`, `processing`, `success`, `error`. O coordenador acompanha sessão/operação visível e deduplica receipts; rascunho não é confirmação. Estados, dimensões e resultados passaram em focados. O teste de escala passou nas seis categorias de L a `AccessibilityXXXL`: crescimento antes do cap da barra, estabilidade acima dele e conteúdo continuando a crescer. Tato e percepção no aparelho permanecem pendentes.

## 7. MOTION

Tokens de 140 ms para interação, 220 ms para conteúdo e 400 ms para marca; política elimina as animações previstas sob Reduce Motion. Sem partículas ou sons novos. Logout/troca de conta interrompem transições capazes de mostrar pixels da sessão anterior, com regressões visuais aprovadas. Isso não constitui medição de fluidez/FPS.

## 8. IDENTIDADE VISUAL

Cores semânticas, marca existente e componentes compartilhados. Glass restrito às superfícies compatíveis; fallback público para iOS 18. Reduce Transparency, Increase Contrast, baixo consumo e estado térmico governam a política.

Capturas reais preservadas: [coleção visual revisada do simulador](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/final-visual-review/index.md) e [Flow com rascunho B e teclado](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/flow-keyboard-green-attachments/79A484B3-B730-417F-AD58-A577DCCF4A3A.png). As seis [capturas do teste de escala](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/brand-cap-focused-attachments/manifest.json) também foram preservadas; a inspeção de L e `AccessibilityXXXL` encontrou rótulos legíveis e o card de 731 kcal inteiro. Dados sintéticos; não representam aceite visual do Release físico.

PT/EN, claro/escuro efetivo e rotações passaram no iOS 27 em 48,788 s e no compacto 26.5 em 41,385 s. A falha anterior de tema, também observada no baseline, está preservada sem causa definitiva atribuída. SDK 27 e mínimo 18 mantidos; **runtime iOS 18 indisponível, sem execução nessa versão**.

## 9. PERFORMANCE

**Par `performance-pair-ios27-flow-dock-stable-keyboard` (02/10):** mesmos apps congelados do par falho (antes `c6ac3457…`, depois `4d29e8c9…`) e runner novo comum compilado de `791303b` (log real de compilação). Ordem antes→depois, condições `MATCHED_RECORDED_CONDITIONS`, 2/2 PASS por lado, 8 métricas × 5 amostras, workload 40→50 mensagens verificado nos dois lados.
- Resposta longa (clock XCTest): 5,334 → 5,394 s, faixas sobrepostas. Memória absoluta/pico menor no depois (−1,7%); sem atribuição causal.
- Flow 50 (clock XCTest): 5,450 → **238,537 s** no depois, causado por esperas de 60 s do XCTest (“App animations complete notification not received”). **Caracterização:** com o mesmo produto, a reexecução com sonda temporária deu 5,468 s e, com fontes restaurados byte a byte, 5,488 s, ambos sem nenhuma espera; a integral final também não teve nenhuma. **Comparação Flow 50 deste par NÃO ACEITA** (estol de quiescência não reproduzível, não atribuído ao produto). Evidência: `flow-dock-stable-keyboard-pair-characterization.json`. Warning `Invalid frame dimension` apareceu de novo só no depois, sem causa atribuída.

**Atualização do produto5b123d0:** o par `performance-pair-ios27-flow-dock` terminou baseline2PASS/candidato1PASS1FAIL no setup do Flow50, exit65. Sem comparação aceita. O runner v2 tocou durante movimento do teclado. Novo par preparado exige os mesmos apps e um runner atualizado comum; nada foi medido nesse futuro par. Os números abaixo são históricos do produto anterior.

**Duas comparações controladas concluídas; sem aprovação global de performance.** Mesmo iPhone 18 Pro/iOS 27, apps congelados e execução after→before. Cada par usa um runner comum aos dois lados, cinco amostras por métrica e `MATCHED_RECORDED_CONDITIONS`. V2 tem 14 métricas e 20 snapshots por lado; navegação/sheet v3 tem duas métricas e oito snapshots por lado. Portrait=1 e VoiceOver OFF; snapshots não constituem monitoramento contínuo nem prova dos traits de toda janela. Não agregar amostras entre runners, pares ou ao histórico 26.5.

| Par / média | Before | After | Variação |
|---|---:|---:|---:|
| V2 — Flow 50, gesto XCTest | 5,417645 s | 5,417658 s | +0,000% |
| V2 — Flow longo, gesto XCTest | 5,325460 s | 5,308712 s | −0,314% |
| V2 — Biblioteca, gesto XCTest | 5,306946 s | 5,246010 s | −1,148% |
| V2 — lançamento nativo | 2,371417 s | 2,425651 s | +2,287% |
| V2 — Hoje utilizável observado | 5,704076 s | 5,733338 s | +0,513% |
| V3 — ciclo completo das cinco abas | 18,7293376494 s | 14,0782285972 s | −24,833% |
| V3 — apresentação da sheet de refeição | 2,6595815056 s | 2,6057582390 s | −2,024% |

Hoje utilizável exige fixture oficial de 731 kcal inteira entre cabeçalho/barra e Atualizar habilitado/hittable. Os clocks observados incluem entrada, espera por idle e consultas de acessibilidade do XCTest; Hoje inclui também launch. **Não medem TTID nativo, FPS ou duração de animação.** Navegação mede um ciclo, não cinco tempos individuais; a sheet de refeição não representa todas as sheets. As reduções v3 são observações de um par, sem atribuição causal ou reprodutibilidade demonstrada. O helper consulta a barra nativa no before e a customizada no after; a diferença de estrutura também participa do custo das consultas. PASS valida execução/asserts/coleta, não um limite automático de regressão configurado.

Pico físico do app no v2: Flow 50 **+144,1552 kB/+0,137%**, Flow longo −1,660%, Biblioteca −4,212%. A piora de tempo da Biblioteca no primeiro par não se repetiu. Launch e pico Flow 50 ficaram maiores nos dois pares, com magnitudes variáveis e faixas v2 sobrepostas: sinais preservados, sem atribuição causal.

Baseline puro `5d9429f`: 440 blobs exportados pelo Git, build/assinatura PASS. Candidato com produto `ebf64a9`; `038c1b7` e `3e9dde8` alteram somente harness. V3 reutiliza apps byte-idênticos ao v2. As duas primeiras tentativas nav/sheet falharam antes de medir navegação por contrato de toolbar; evidência mostrou um pixel de arredondamento a 3x. Correção do harness limitou a tolerância de contenção do header a um pixel derivado da escala, preservando alvos/usabilidade; pares anteriores continuam inválidos. Evidências: [standalone v2](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/performance-tools-v2/performe-paired-performance-v2-findings.md) e [métricas/condições nav/sheet v3](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/navigation-sheet-metrics-v3/analysis.json). A [revisão independente v3](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/performance-tools-v2/performe-navigation-sheet-v3-findings.md) confirma os limites: warning `AVAudioSession_iOS.mm:978` sobre chamada na main thread em MealSheet nos dois lados; `Invalid frame dimension` ausente nesses dois cenários, sem alegação global de ausência de warnings.

**Ferramentas nativas:**

- **App Launch:** três tentativas controladas inválidas. Na última, XCTest passou, mas recorder não finalizou após SIGINT/120 s; TERM/exit 1. Sem trace aprovado ou nova tentativa planejada. Evidência: `performance-pair-ios27-v2/traces/before-app-launch-all-processes-01/capture.json`; o sufixo 01 é local ao novo par.
- **SwiftUI / Animation Hitches:** recorder recusou o simulador com `Hitches is not supported on this platform.` Gates não aprovados.
- **Time Profiler v2 tentativa 02:** XCTest/recorder exit 0, sem término forçado, identidades e condições verificadas. PIDs 64311/64625: 4,138/3,781 s de CPU amostrada na janela do workload; tabelas reais e cálculo revisados independentemente. Leaf frames sem símbolos limitam atribuição. Pares anteriores rejeitados por orientation=0 ou PID residual permanecem rejeitados.
- **Allocations:** capturas, identidades, condições e tabelas reais verificadas nos PIDs 65200/65858. Statistics agrega o trace inteiro sem timestamps por linha. Comparação de retenção na mesma janela continua aberta; sem inferir pico físico ou leak. Próximo passo possível: selecionar a janela na GUI quando o Mac estiver acessível.

**Warning de dimensão:** no par Flow 50, ocorreu somente no candidato, ao focar o compositor antes da medição. O evento nativo PID 67015/05:51:33.714 UTC preserva 59 frames: 56 de frameworks/OS, dois entrypoints genéricos do app e um UUID/offset zero. Atlas/binários confirmaram identidades; lookup posterior em módulo de UUID idêntico resolveu `_FrameLayout.init(width:height:alignment:) +400`, sem dimensão, view ou linha causal. Isso não prova bug do SDK. LLDB não capturou a stack alvo: o fault capturado era NSPredicate/XCTAutomationSupport; a primeira tentativa pausada expirou e permanece inválida. Debugger encerrado, sem mudança de produto.

Separadamente, onboarding no baseline puro passou e produziu o mesmo Fault nativo (PID 78501/07:36:20.671208 UTC), com hashes/UUID verificados. A falha original do parser de timezone foi preservada; correção offline passou quatro testes e considerou os caminhos diferentes de container. Demonstra ocorrência anterior naquele fluxo, não preexistência da ocorrência específica do Flow. **Causa/impacto permanecem abertos, sem supressão.** [Stack e limites](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/performance-tools-v2/performe-native-warning-stack-analysis.md), [simbolicação](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/performance-tools-v2/performe-native-warning-symbolication-review.md) e [contraprova de onboarding](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/performance-tools-v2/performe-baseline-onboarding-warning-supplement.md).

## 10. USER FRIENDLY

Preservados filtros/recuperação da Biblioteca, grupos do Perfil e consentimentos/foco de Auth/Onboarding. Busca permanece no primitivo nativo `.searchable`, sem biblioteca paralela. Os focados verificam 20 rascunhos, título completo AXXXL, descanso 60 não salvo e posição de leitura entre abas; Flow 50 com texto B não enviado e retorno à âncora; limite nativo de 4.000/4.001 caracteres.

MealCapture mantém revisão antes de proposta e recuperação para texto não reconhecido. A correção de sincronização do harness preserva teclado aberto e exige geometria real estável antes de um único toque; produto e fixture não mudaram.

## 11. ACESSIBILIDADE

Cinco ações, ordem/seleção/destinos e alvos mínimos passaram nos focados. Large Content Viewer permite pressionar, arrastar e soltar na aba final; cancelamento/deduplicação foram testados e o HUD foi inspecionado. O limite de Dynamic Type pertence somente à barra; telas mantêm escala acessível. Reduce Transparency ON e Increase Contrast ON foram exercitados e restaurados.

Audit compacto: loaded das cinco abas PASS 240,625 s; quatro famílias de estado corrigidas PASS 51,334 s, sem recuperação Apple −56. Cada contraste adiado exige revelar a mesma identidade e passar nova auditoria com exposição integral; sem nova exceção para a barra. Existem exceções preexistentes documentadas, incluindo três findings conhecidos de Perfil: PASS não significa ausência de findings.

VoiceOver 27: **4/4 PASS em 55,283 s, zero skips — 1 UI de foco/leitura/ordem/seleção + 3 parser**. A calibração refutou doubleTap por coordenada como prova de ativação do foco; **ativação por gesto real permanece manual**. Não houve teste físico de VoiceOver ou tato.

**Restauração concluída:** canônico 26.5 com VoiceOver OFF confirmado pela árvore AX pública; Light/texto 3/Reduce Motion OFF/Increase Contrast OFF/Reduce Transparency OFF preservados. Nenhuma preferência de VoiceOver do Mac/iPhone físico foi alterada. O lock posterior do Mac não desfaz essa evidência.

## 12. NOVAS IDEIAS

**Tutorial inicial guiado — implementado (`90e1585`).** Especificação: [tutorial](2026-10-02-performe-ios-guided-tutorial-scope.md).
- Oferecido uma vez na primeira entrada elegível após login/onboarding (consentimentos intocados); nunca sobre uma sheet ou lembrete em abertura; não muda aba/pilha/rascunho; nada é enviado, registrado ou solicitado.
- Oito etapas na ordem da barra: boas-vindas, Hoje (Restam para comida sem exercício; Déficit líquido com exercício), Flow, Plano, Registrar, Progresso, Rotina e Biblioteca, Perfil. Linhas condicionadas às capacidades reais da sessão (foto/áudio, rascunhos/importação, lembretes, sair da conta).
- Estado por conta neste iPhone (`pai.tutorial.v1.<hash>`, sem id nem dado de saúde): não oferecido / “Agora não” / concluído; fechar nunca conta como concluir; lembrete que fecha o tour não é resposta. Perfil → “Conhecer o app” revê tudo ou vai direto a uma área.
- AX: posição em texto, título como header com foco do VoiceOver após a transição, rolagem ao topo por etapa, alvos 44 pt, ações empilhadas em AXXXL, Reduce Motion. PT/EN, claro/escuro conferidos em captura.
- Revisão independente: 0 CRITICAL/HIGH; seis MEDIUM e os LOW relevantes corrigidos antes do commit. A seção do Perfil ficou sem cabeçalho porque o título “Ajuda” acionou a auditoria de Dynamic Type (sem ampliar exceções).
- **Não coberto nesta rodada:** logout/expiração durante o tour e A→B→A pelo shell real (smoke físico com QA A/B); gesto real de VoiceOver.

## 13. TESTES

| Solicitado | Implementação/teste | Evidência / limite |
|---|---|---|
| Navegação e cinco históricos | Cinco paths determinísticos; UI de estado/scroll/form entre abas | Focados PASS, incluindo Plano 60 e Flow 50/B; não constitui E2E de cada histórico. Nova integral, deep links e QA A→B→A no candidato físico pendentes |
| Marca, abertura e loading | Seis estados, sessão, Splash AX, atraso 150 ms | Focados PASS; escala 1/1 em seis categorias; tato/abertura físicos pendentes |
| Hoje e Progresso | Valores oficiais, coalescência, peso independente | Today/Session 39 PASS e UI; fórmulas preservadas |
| Flow | ACK/outbox/retry 40/50, loading de reentrada | Regressões PASS; P3 GREEN 30 testes/duas suítes |
| Teclado/acessório | EndFrame no didHide; B preservado | RED log → GREEN conjunto 5/5; revisão antes de `ebf64a9` |
| MealCapture | Toque único após geometria estável da sheet | Header específico 2/2 PASS; `7b66fdd`, somente harness |
| Temas/AX/localização | Matriz, audit, VO delimitado | Seções 8/11; scanner atualizado 25/25 PASS; ativação VO manual pendente |
| Performance | Apps congelados e runner comum por par | V2 5/5 e nav/sheet v3 2/2 por lado qualificam produto anterior. Par do dock atual inválido por setup; novo runner GREEN preparado, sem execução |
| Build/assinatura | Release sim/staging, Analyze, build-for-testing | Quatro gates PASS; candidato não instalado |

**Integrais, sem somar repetições como casos exclusivos:**

- **`606d5d6` (candidato com polish A–D e placeholders estáticos): 1.849 PASS / 0 FAIL / 0 skips**, 03/10 15:12–17:14 UTC, fontes estáveis. 13 esperas "App animations complete notification not received" (60 s cada), todas em `FlowChatUITests` (7 em `testLocalResponseAndExplicitRetryPreserveNativeContract`, 5 no limite de 4.000, 1 no compositor AX) — nenhuma falha; pendência de diagnóstico (05f4f7c teve 0; 90e1585 teve 9 e passou). Esta é a integral de referência.
- `81543c6` (polish A–D com shimmer por `TimelineView(.animation)`): 1.840/1.849, 62 esperas de idle e 9 FAIL por timeout. Sonda com o shimmer desligado: 0 esperas, 3/3 nos testes que travavam → causa confirmada. Variante finita (duas passagens via `withAnimation`) ainda travou 6× nos testes do Flow/Plano. Decisão: placeholders sem shimmer nem pulso; respiração da splash limitada a 3 ciclos. Rodada de verificação: 60/60 (política, matriz de render, tour, Plano, Flow AX e 4.000).
- `05f4f7c` (candidato anterior, com tutorial em texto): 1.827 PASS / 0 FAIL / 0 skips, 02/10 17:48–19:33 UTC. Rejeitado no aceite visual de Eduardo (ver cabeçalho).
- `90e1585`: 1.826/1.827; único FAIL em `BodyFlowUITests.testFlowChatIsReachableAndReturnsExplicitLocalSimulation` — toque em Enviar durante o movimento do teclado (árvore mostra texto ainda no campo). Corrigido em `05f4f7c` com o mesmo gate de readiness dos demais testes do Flow; cenário exato 3/3. Sem mudança de produto.
- Readiness do benchmark (`791303b`): RED 7 PASS/2 FAIL → GREEN 9/9 → 10/10 com o caso de Done que desaparece; cenários normais do Flow e benchmark 3/3; revisão independente sem bloqueios.
- Tutorial: unitários 1.538 PASS (inclui `GuidedTutorialTests`); `GuidedTutorialUITests` 5/5 (inclui AXXXL); `PremiumConvergenceUITests` teve 4 falhas numa rodada focada (contraste em Hoje na borda da rolagem, foco de teclado no onboarding, timeout de consulta AX) e 4/4 isoladas; a integral final passou inteira.
- **Release do candidato (`release-gates-polish-606d5d6`):** Release sim 63 s, Analyze PASS (0 warnings), Release staging 64 s, assinatura estrita sim/staging PASS, scan dos dois bundles PASS (0 falhas), testes do scanner 25/25; único aviso de compilação é o preexistente `SessionLifecycleCoordinator.swift:210`. Perfil staging expira em 04/10/2026 21:12:24 UTC. (`release-gates-tutorial-05f4f7c` idem para o candidato anterior.)

- `b8d7b1e`, histórica interrompida: 1.527 Swift Testing/130 suítes, 51 XCTest e 47 UI PASS; três UI FAIL e um Plano cancelado. Focados posteriores não a tornam aprovada.
- `038c1b7`, concluída: resumo oficial **1.776 PASS / 1 FAIL / zero skips** — 52 XCTest, 1.527 Swift Testing e 197 UI PASS. O único FAIL exigia crescimento do antigo cabeçalho acima do cap da nova barra. Revisão confirmou defeito do contrato do teste; produto intacto.
- Correção do teste: **1 PASS / zero FAIL / zero skips**, 143,454 s. Seis categorias reais: L, XXL, XXXL, AccessibilityXL, AccessibilityXXL e AccessibilityXXXL. Exige crescimento até XXXL, estabilidade acima, conteúdo ampliado, cinco ações, 44 pontos, contenção e push da Biblioteca. [Resumo focado](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/brand-cap-focused-summary.json); revisão independente concluída.
- **`3e9dde8`: integral iniciada 08:03:18 UTC e interrompida por SIGINT 08:19:37 UTC, exit 75.** Foram 52 XCTest + 1.527 Swift Testing + 26 UI PASS; resumo oficial 1.605 PASS/2 FAIL, sendo uma falha real da assertiva de geometria e um caso cancelado pela interrupção. No Flow AXXXL, superfície do campo terminou em 622,667 pt e teclado AX começou em 590 pt. Produto/teste idênticos à rodada038; as capturas mostram acessório Done na aprovação e renderização incompleta na falha. Causa em investigação, sem flexibilizar assertivas; a instalação permanece bloqueada por este gate.

**Repetição isolada inalterada:** terminou 08:31:28 UTC, exit 65. A contenção do teclado passou, mas a consulta a Cancel falhou após esperas de 60 s por quiescência do XCTest. A gravação confirma Cancel visível em 312,385 s e resposta `QA_REPLY_VISIBLE` em 334,887 s; a fixture de 30 s terminou antes da consulta em 362 s. Esse FAIL não demonstra defeito de cancelamento do produto. A causa da divergência AX/pixels na integral continua aberta, assim como a origem das esperas por animação. Mac bloqueado confirmado pelo controle de interface; relação causal não estabelecida. [Manifesto diagnóstico](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/flow-exact-ax-diagnostic-findings.json).

**Fixture determinística de cancelamento (`6978f65`):** RED 5 PASS/1 FAIL; GREEN 6 PASS/zero FAIL/zero skips, com avanço virtual de 30/60 s e cancelamento da espera real sem resposta no histórico. Dois testes UI vizinhos também passaram (cancelar/reabrir sem reenviar e preservar B ao cancelar A). Revisão independente do diff real antes do commit. Somente DEBUG; o cenário AX exato e a integral continuam gates separados.

**Readiness do teclado (`591d727`):** três casos determinísticos RED → 3/3 GREEN; depois, o cenário UI AX exato passou em 124,858 s, sem probe, com as assertivas originais e a fixture cancelável. O gate exige frames válidos/visíveis, ausência de sobreposição com Done e mesma geometria por amostras separadas por pelo menos 250 ms; expectativa de 8 s, sem garantia de teto rígido para consultas AX. Isso corrige a sincronização da verificação; não prova causa do comportamento transitório do teclado nem encerra o achado de sobreposição do campo vazio. Revisão independente antes do commit.

**Campo vazio, sem digitar:** RED visual e teste exato preservados. Dock safeAreaInset não resolveu (0/1); inset vazio de altura zero foi interrompido (exit75) após raster confirmar o mesmo overlap. O candidato com UIKeyboardLayoutGuide falhou: final guide vazio, apesar de notificação local indicar34pt de interseção. Após correção do cálculo de CGRect.infinite, 13 unitários passaram, mas o UI continuou reprovado; isso não é GREEN do produto. Todos os candidatos rejeitados/probes foram retirados e preservados fora do app.

**Correção local por notificação:** `flow-keyboard-notification-candidate` passou **14/14, zero skips**, sem probe. O campo vazio permaneceu com placeholder e Enviar desabilitado; Send passou a terminar486pt, acima de Done500pt, com todos os controles hittable. Captura real conferida. A revisão acrescentou proteção contra origem de tela diferente/ausente: RED8PASS/2FAIL e implementação de associação ao UIScreen. Rodada final focada (`flow-keyboard-final-focused`, 09:52:27–09:59:25 UTC) concluiu 21 PASS/2 FAIL/zero skips: todos os 15 unitários passaram, seis UI passaram; o raster confirmou overflow do campo/aviso em AXXXL com 4.001 caracteres, e a âncora histórica `qa-seed-35` deixou de estar hittable após resposta local. Os gates focados posteriores e o commit estão registrados a seguir; não inferir aprovação integral desse resultado histórico. O warning nativo de frame continua registrado, sem causa atribuída por este GREEN.

**Dock final (`5b123d0`):** o limite de altura teve RED1PASS/4FAIL antes da implementação; o novo produto passou20unitários, AXCancel, AX4.001 com aviso inteiro/foco, vazioAX e histórico explícito. QuatroUI normais inicialmente falharam; vídeo/evento nativo mostraram toque durante deslocamento do teclado. O readiness compartilhado preserva todas as assertions e passou **9/9** (seisUI e três testes puros), sem60s idle nessa rodada. A contraprova anterior963,008s permanece registrada, sem causa ou alegação de ganho. Sonda temporária removida:13eventos/uma atribuição natural, sem churn observado nessa janela. Revisão independente/hashes antes do commit. Capturas finais confirmam B preservado e âncora35 visível; integral/performance atuais continuam gates separados; Release/análise/assinatura do dock passaram posteriormente.

**Regressões exatas:** teclado 376 → 82 → didHide82 → 0 → didHide0: RED único 0,663 s em `keyboard-accessory-red.log`; xcresult RED incompleto por travamento da finalização, log preservado. GREEN `keyboard-accessory-and-meal-green.xcresult`: 5/5, sem skips, incluindo Concluído → teclado ausente → barra restaurada → B intacto. `meal-sheet-header-final.xcresult`: 2/2 em 23,837/139,112 s, header por `sheet.fechar`, sem fallback ou asserts removidos.

**Builds anteriores:** [manifesto assinado](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/release-gates-final-20261002/manifest.json), `BUILT_AND_VERIFIED_NOT_INSTALLED`: Release sim 45,243 s; Analyze 3,444 s; Release staging 38,965 s; build-for-testing 4,497 s. Zero erros; cada Release com um aviso preexistente, Analyze sem findings. Scanner: 844 chaves/1.688 valores, zero falhas; assinaturas/team/bundle/Keychain conferidos. Até `3e9dde8`, os 308 arquivos de fontes/projeto do app foram revalidados byte-idênticos às fontes usadas no Release assinado. Depois, `6978f65` alterou uma fonte inteiramente `#if DEBUG`; a árvore atual completa não tem o hash antigo. O código compilado em Release não foi alterado por essa correção de fixture. Harness adicional compilado e executado antes do commit `3e9dde8`; nenhum novo build de produto é inferido dessas execuções.


**Builds atuais (`5b123d0`):** [manifesto do dock](/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/release-gates-flow-dock-5b123d0/manifest.json): Release sim 39,481 s, Analyze 3,286 s, Release staging 34,188 s e build-for-testing 7,467 s, todos aprovados. Analyze/Debug sem warnings; cada Release mantém o warning antigo de `await`. As 310 fontes do produto ficaram estáveis, assinatura estrita/team/Keychain/perfil do iPhone e rollback revalidados. Scanner `306ecbf`: RED 2/2 → GREEN 25/25; os dois bundles reais passaram com identidade esperada explícita, 844 chaves/1.688 valores/zero falhas. O scanner continua recusando ID divergente ou staging sem opção explícita. Nenhuma instalação foi realizada.

## 14. PONTOS PENDENTES

- **Físico/entrega:** instalar o candidato `606d5d6` por cima do staging no iPhone (rollback `05f4f7c`/`79dfe83` preservados) e colher o **novo aceite visual de Eduardo** (abertura, toques, tour spotlight, trilha); depois o smoke: abertura/restore/logout/onboarding, QA A→B→A, cinco abas/sheets, teclado e B durante A, cancel/retry, proposta × confirmação, peso 80/data, rotina após o horário, lembrete, Biblioteca sem rascunhos, VoiceOver real/tato, tutorial (oferta, “Agora não”, replay e áreas). Perfil expira em 04/10 21:12 UTC; a conta Apple Developer paga (em aprovação) resolve a assinatura para distribuição.
- **Distribuição para Roberto:** TestFlight ou Ad Hoc depois da aprovação da conta Apple Developer e de autorização explícita de Eduardo (fora do escopo atual).
- **Performance nativa:** App Launch/Hitches/Allocations continuam com os limites da seção 9; Flow 50 do par atual não aceito (estol não reproduzível). Par de benchmark não reexecutado após o polish `81543c6`/`606d5d6`.
- **Esperas de idle no Flow:** 13 em `FlowChatUITests` na integral de `606d5d6` (passou). Diagnosticar o que segue animando na tela do Flow (única animação contínua conhecida no app é o mascote, pré-existente).
- **Humanos/editoriais:** decisão nutricional de produto; Roberto submete artigos, Eduardo revisa, Roberto publica e então validar Biblioteca publicada. Seis rascunhos PT + seis EN não equivalem a publicação. Notificação foi aceita anteriormente pelo usuário, sem nova prova independente nesta rodada.
- **Fechamento:** simulador27 restaurado a Shutdown no handoff (12:06:20 UTC); voltar a conferir/restaurar após os futuros testes. VO26.5 já restaurado. Arquivamento de ambos os auxiliares foi recusado: “This worktree is protected by a pinned task or workspace.” Inventário sem commits exclusivos/arquivos ignorados; estados preservados, sem snapshot de arquivamento ou remoção, proteção não contornada. Caminhos: `/Users/eduardohenrique/.codex/worktrees/performe-flow-polish/performe-ai-client-beta-flow-v1` e `/Users/eduardohenrique/.codex/worktrees/performe-journey-polish/performe-ai-client-beta-flow-v1`. Evidências diagnósticas preservadas.

## 15. STATUS FINAL

**STATUS: CANDIDATO COMPLETO VERIFICADO EM SIMULADOR; ENTREGA AO CLIENTE NÃO CONCLUÍDA.** Produto `606d5d6` (polish A–D após rejeição visual de 02/10), integral 1.849/1.849, Release/Analyze/assinatura/scanner PASS. Instalação física e novo aceite visual de Eduardo pendentes; sem aceite editorial.

| Campo | Situação |
|---|---|
| Host | MacBook-Air-de-Eduardo.local / LOCAL_DEVELOPMENT |
| Branch / HEAD | `codex/performe-ai-client-beta-flow-v1` / `606d5d6` (mais commit documental) |
| Commits desta continuação | `791303b` runner, `90e1585` tutorial, `05f4f7c` teste, `eaee1e6` docs, `81543c6` polish A–D, `606d5d6` placeholders estáticos; locais; push NÃO; merge remoto NÃO |
| Testes | Integral `606d5d6` 1.849 PASS / 0 FAIL / 0 skips (13 esperas de idle no Flow, sem falha); par Flow: resposta longa comparável, Flow 50 não aceito |
| NEW FAILURES INTRODUCED | Nenhuma na integral final |
| Resource gate | PASS (≈55 GiB livres, 43% memória livre no início dos jobs pesados) |
| Deployment | NÃO (nem produção nem staging nesta rodada) |
| Rollback | Artefatos assinados `05f4f7c` e `79dfe83` (instalado no iPhone) preservados |
| REGRESSION STATUS | **VERIFIED** (simulador iOS 27, suíte integral); físico pendente |
| PRODUCTION STATUS | **NOT DEPLOYED** |
| Cleanup | Simulador 27 a restaurar para Shutdown no fechamento; worktrees auxiliares protegidos mantidos |
| COST / ENVIRONMENT CLOSEOUT | Nenhum recurso pago novo; staging preexistente KEPT; conta Apple Developer (US$ 99/ano) contratada por Eduardo fora desta automação |

`IOS INTEGRATION STATUS: IMPLEMENTED / VERIFIED IN SIMULATOR, PHYSICAL PENDING` · `REBRAND STATUS: IMPLEMENTED / FINAL VISUAL GATE OPEN` · `ROBERTO BETA CANDIDATE STATUS: NOT READY FOR CLIENT ACCEPTANCE` · `USER VISUAL ACCEPTANCE: REJECTED 2026-10-02 (05f4f7c) → PENDING (606d5d6)`.
