# Performe AI: continuação no Claude Code

> Checkpoint solicitado por Eduardo em 02/10/2026 porque os tokens desta sessão estão acabando. A implementação **não está encerrada**. Este documento é o ponto de entrada atual; os ledgers anteriores são históricos e contêm pendências posteriormente resolvidas. Não reiniciar pela pendência 1 do handoff de setembro.

## 1. Primeiro minuto da retomada

1. Trabalhar em `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1` e identificar novamente host, Git e processos.
2. Ler `CLAUDE.md`, instruções globais/aplicáveis, este documento e o relatório de 15 itens `docs/handoffs/2026-10-01-performe-ios-final-polish-report.md`.
3. Preservar o diff **RED** em `apps/ios/BodyFlow/BodyFlowUITests/FlowChatUITests.swift`. Não descartar, esconder em stash nem commitar como correção concluída.
4. Continuar pelo GREEN do readiness do benchmark (seção 6), que está preparado, **não aplicado nem executado**.
5. Concluir focados e benchmark atuais, implementar o **tutorial inicial guiado** pedido por último (seção 12) e só então executar integral final, Release e smoke do candidato completo, evitando duplicar esses gates caros.

Não há necessidade de pedir novamente autorização para testes, correções do escopo, commits locais ou instalação por cima do staging já autorizada. Há gates humanos específicos ao final. O checkpoint não autoriza push ou produção.

## 2. Autoridade, limites e preferências

- Idioma: pt-BR; comunicações objetivas. Eduardo prefere execução autônoma. Perguntar somente por informação/decisão/acesso realmente indispensável.
- **Somente commits locais. Sem push, PR, merge remoto, tag, Production, TestFlight, App Store ou infraestrutura paga nova.** Essa restrição específica prevalece sobre a política global de pipeline autônomo.
- Cada bug relatado deve ter teste com o cenário exato. Revisão independente antes de commit de correção grave. Não obter verde enfraquecendo assertions, pulando casos ou suprimindo erros.
- Preservar dados, sessões, consentimentos, rotas, fórmulas nutricionais, caches e limites de memória. Sem dependências novas.
- Rodada de refinamento desde `5d9429f`: iOS e ferramentas de teste. **WhatsApp, API, banco e regras nutricionais não foram alterados nesta rodada.** Mudança futura em `packages/agent` pode afetar WhatsApp; avisar antes e respeitar o limite do escopo.
- Uma única lane de Xcode/simulador/Instruments/controle de interface. Não executar dois builds/testes em paralelo. Revisores podem trabalhar somente em leitura ou produzir patches privados; um escritor por worktree.
- Não mostrar `.env`, tokens, senhas, configs privadas, URLs assinadas ou dados reais. QA A/B estão autorizadas; obter credenciais de arquivos locais sem expô-las. Não pedir segredos no chat.
- Instalar o app de staging **por cima**, preservando dados. Nunca desinstalar para facilitar QA. Manter rollback assinado.
- Não registrar aceite visual de Eduardo, submissão/publicação de Roberto ou decisões nutricionais em nome deles.
- Não contornar bloqueio do Mac/iPhone. Autorização de uso não substitui o desbloqueio físico necessário.

## 3. Estado Git, host e artefatos

| Item | Valor no corte |
|---|---|
| Host | `MacBook-Air-de-Eduardo.local`, Darwin 25.6.0 arm64, usuário `eduardohenrique`; LOCAL_DEVELOPMENT |
| HOME / CODEX_HOME | `/Users/eduardohenrique`; CODEX_HOME não definido, efetivo `~/.codex` |
| Checkout | `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1` |
| Branch | `codex/performe-ai-client-beta-flow-v1` |
| Remote | `https://github.com/corehealth-app/agentempp.git`; nenhuma operação remota nesta passagem |
| Início do refinamento | `5d9429f9648c0906e1c9a13ebd1bbe0c6c467103` |
| Último commit técnico | `306ecbf442c704acd7b8103bc648c75d839f157c`, 22 commits locais desde o início |
| Produto iOS assinado | `5b123d08fbe81f78a8d0cfc781c1a6f303411a19` |
| Diff aberto | RED de readiness em `FlowChatUITests.swift`: 91 inserções / 2 remoções; sem mudança de produto |
| Documentos desta passagem | Handoff, especificação do tutorial, prompt de retomada, relatório e ledger; eventual commit posterior é documental, não novo produto |
| Evidências privadas | `/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001` |
| Pacote de transferência | Diretório `claude-code-handoff-20261002` dentro das evidências; inventário/hash, patches e helpers preservados |

O Git é a autoridade para o HEAD atual depois do checkpoint documental. Não reutilizar o SHA técnico como se fosse o HEAD após novos commits. Não tratar a árvore modificada como descartável.

Xcode `27A266a`, SDK 27, deployment target iOS 18. Runtimes disponíveis 26.5 e 27.0; **sem execução no iOS 18**. Último resource gate pesado: 46 GiB livres / 43% memória livre; swap 21.245 MiB era amostra única, não tendência. Reavaliar espaço/recursos antes de nova integral; não bloquear Git por oscilação transitória.

## 4. Contexto anterior já resolvido ou delimitado

Ler os apêndices finais, não só o cabeçalho antigo, de `docs/handoffs/2026-10-01-performe-ai-second-delivery-ios-progress.md`.

- A pendência original do gerador de dieta foi tratada em `dc5854f`: **uma** nova tentativa somente no Flow com motivo da recusa; sem preencher nutrientes no código ou relaxar travas. O rascunho abriu no iPhone; revisão não equivale a confirmar/ativar plano.
- Segunda entrega passou por captura física de foto/áudio, recuperação da importação por foto, isolamento QA A/B, correções de rótulos, peso oficial/data e ocorrências de rotina. Há evidências e limites no progresso histórico; não repetir chamadas LLM pagas só para recuperar contexto.
- Atualização após confirmação de refeição foi caracterizada com os valores exatos e depois observada com refeição sintética distinta. Deduplicação de alimento/quantidade existente foi preservada.
- Eduardo declarou: **“a notificação esta funcionando, podemos ir para a proxima task”**. Teste encerrado por decisão dele; não reabrir Não Perturbe nem criar outra fixture. Isso é aceite funcional humano dessa notificação, não aceite visual global ou nova prova independente de entrega/tap.
- Biblioteca: preflight verificou zero publicações, rascunhos ocultos no iPhone. O fluxo real Roberto → revisão de Eduardo → publicação de Roberto segue pendente. Há seis conteúdos por idioma, PT/EN, em rascunho; não são conteúdo publicado.
- A decisão sobre metas de **novas sugestões** após mudanças de peso continua de produto. Não mudar fórmulas ou reinterpretar metas nesta tarefa.
- Instalação anterior no iPhone de Eduardo não equivale a distribuição para Roberto. O novo refinamento ainda não foi instalado.

## 5. Plano aprovado e implementação existente

Identidade **Warm Performance**, logo **Signal Spark** aprovada e nomes públicos **Performe AI / Flow**; identidade técnica interna BodyFlow preservada.

| Grupo | Implementação / invariantes | Situação |
|---|---|---|
| Integridade Flow | A enviado/B digitado preservado; identidades de leitura/tentativa/sessão; descarte de resultados antigos; chave de idempotência no retry; outbox imediata; POST oficial preservado; reconciliação por ID; falha GET repete leitura, não POST | Implementado, RED/GREEN/revisões e focados; integral atual pendente |
| Hoje | Atualizações simultâneas deduplicadas, snapshot visível, indicador no controle, consultas independentes em paralelo, invalidação após confirmação | Implementado e focados aprovados |
| Componentes | Superfícies semânticas, botões/campos/cards/estados/loading/skeletons compartilhados no design system existente; política central de motion/transparência/contraste/energia/térmica | Implementado e focados aprovados |
| Navegação | `TabView`, `AppRouter`, cinco paths; `AppTab.displayOrder = Hoje, Plano, Registrar, Progresso, Perfil`; valores internos/IDs preservados; barra via inset/API pública | Implementado; cinco paths determinísticos, UI cobre cenários específicos, não alegar teste exaustivo de todo histórico |
| Logo | Registrar central abre registro; `PerformeBrandAction` com idle/press/active/processing/success/error; sessão/operação visível; receipts deduplicados; proposta “Pronto para revisar”, confirmação “Registro confirmado” | Implementado e focados; tato físico pendente |
| Abertura | Launch estática teal profundo alinhada com SwiftUI; sem duração mínima; estados de sessão/onboarding preservados; privacidade no primeiro quadro após logout/A→B; Reduce Motion | Implementado; smoke físico final pendente |
| Loading | Atraso cancelável de 150 ms, skeletons Hoje/Plano/Progresso/Biblioteca, dados antigos visíveis em refresh; nenhum percentual interno inventado | Implementado e focados |
| Jornadas | Hoje prioriza Restam/Excedente para comida; detalhes técnicos secundários; Flow/compositor/scroll; revisão antes de confirmação; teclado Done; Plano 20 rascunhos; peso 80 kg/data; rotina sem ocorrência elegível; Biblioteca/Perfil/auth | Implementado, com limites de cobertura documentados |
| Performance / polish | Pares controlados, Instruments, matriz visual/AX, scanner, Release/Analyze/assinatura | Parcial; próximos gates abaixo |
| Tutorial inicial guiado | Pedido adicional de Eduardo em 02/10 | **Não implementado**; executar como último grupo de produto |

Manter vidro concentrado na navegação/controles flutuantes; leitura e métricas opacas. Liquid Glass nativo iOS 26+, material anterior, opaco quando política exigir. Motion 140/220/até 400 ms, sem atrasar operações. Sem sons, partículas ou parallax contínuo. Busca já usa `.searchable` nativo; não criar wrapper concorrente só para preencher checklist.

### Commits do refinamento, em ordem

```text
a0988a7 Hoje: deduplicação e snapshot
1e970f7 superfícies adaptativas e feedback
e672153 abertura e limpeza visual da conta anterior
0423f2e Flow: rascunhos/ACK/histórico/retry
fa2b763 hierarquia oficial de Hoje e refresh
2e27691 loading compartilhado Biblioteca/Perfil
dd89cfa peso independente e rotina no horário exato
23b17e2 navegação central acessível e drafts Flow
9485254 rascunhos longos de Plano e recuperação acessível
d880e6e feedback somente para resultados confirmados
c0068e3 recovery AX limitado e métricas pareadas
b4f483a navegação nos tamanhos de texto
f7bae16 histórico vazio/outbox não confirmada
b8d7b1e exposição no audit e evidência VoiceOver
ebf64a9 barra oculta também para acessório do teclado
7b66fdd geometria da sheet de refeição antes do toque
038c1b7 Hoje utilizável observado e orientação do benchmark
3e9dde8 contrato de escala e benchmarks navegação/sheet
6978f65 fixture de cancelamento pendente até cancelar
591d727 readiness geométrico do teclado Flow
5b123d0 compositor Flow contido no viewport seguro
306ecbf scanner com bundle staging explicitamente esperado
```

### Mapa de fontes

Prefixo `apps/ios/BodyFlow/BodyFlow/`:

- `App/AppTab.swift`, `App/AppRouter.swift`, `App/AppShellView.swift`, raiz de sessão: navegação/pilhas/isolamento.
- `DesignSystem/Components/PerformeBrandAction.swift`, componentes de navegação/loading e `BodyFlowVisualPolicy.swift`: identidade e acessibilidade adaptativa.
- `Features/FlowChat/FlowChatView.swift`, `FlowKeyboardClearance.swift`, `FlowComposerViewportPolicy.swift`: compositor e fronteira do teclado.
- `Features/Today/TodayViewModel.swift`, `TodayRootView.swift`; `Features/Plan/PlanRootView.swift`; `Features/Profile/ProfileRootView.swift`; `Features/Onboarding/`: jornadas e pontos de integração do tutorial.
- `BodyFlowTests` e `BodyFlowUITests`, paralelos à pasta do app: testes. `FlowChatUITests.swift` contém o helper compartilhado de readiness, também usado por `PlanDraftUITests`.

## 6. Ponto exato de parada: RED aberto do benchmark

### Problema comprovado

O par `performance-pair-ios27-flow-dock` reaproveitou o runner v2 antigo. Baseline: **2 PASS**. Candidato: **1 PASS / 1 FAIL**, exit 65. Flow 50 falhou no setup da primeira troca, antes de coletar o cenário completo. Resposta longa passou, mas o par **não é comparação aceita**.

O tap nativo ocorreu perto de `(356,758)` enquanto o teclado se movia; vídeo mostra teclado software depois e Send reposicionado. A árvore posterior não era coetânea ao toque. Evidência favorece falta de sincronização do setup; não demonstra callback quebrado nem regressão de tempo medida.

No benchmark o baseline `5d9429f` não possui o acessório Done. O helper atual exige Done por padrão, correto para os testes atuais, mas deve permitir ausência **somente quando explicitamente solicitado pelo benchmark**. Se Done existir, todas as verificações continuam obrigatórias.

### Estado preciso

- RED já aplicado na árvore: helper recebe `done: CGRect?` e flag, mas ainda rejeita ausência; seis novos casos mais três existentes.
- `benchmark-keyboard-accessory-red.{json,log,xcresult}`: **7 PASS / 2 FAIL / 0 skips**, terminou 02/10 11:43:31 UTC; hashes de fontes estáveis.
- Falhas esperadas: `testExplicitBenchmarkPolicyAllowsMissingAccessoryAfterFullStableInterval` e `testOptionalAccessoryAppearingResetsTheStableInterval`.
- O retângulo 44×44 centrado no tap é uma fixture geométrica construída; não alegar que foi um frame AX capturado no instante do toque.
- GREEN preparado: `performe-benchmark-readiness-green.patch`, SHA-256 `12eba81cad112fecb5c943c288092a1f87716530fc59818f84c211bb24d59fb9`.
- GREEN mantém default `requiresKeyboardAccessory: true`; única opção `false` no setup de `PremiumPerformanceUITests.appendFiveLocalExchanges`, antes do Send, fora da medição. Mantém expectativa 8 s, estabilidade 250 ms, reread final, métricas, fixtures, cinco amostras, gestos e assertions.
- GREEN não aplicado nem testado. Revisão do autor do patch não substitui revisão independente do diff final.

### Próximos comandos, após conferir estado

Os caminhos abaixo pressupõem o mesmo Mac. Se o host mudou, localizar artefatos antes de executar; o Git não contém as evidências privadas.

```sh
cd /Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1
git status --short
git diff -- apps/ios/BodyFlow/BodyFlowUITests/FlowChatUITests.swift
git apply --check /Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/claude-code-handoff-20261002/performe-benchmark-readiness-green.patch
git apply /Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/claude-code-handoff-20261002/performe-benchmark-readiness-green.patch
python3 /Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/flow-final-diagnostic-tools/run-flow-keyboard-gate.py benchmark-keyboard-accessory-green BodyFlowUITests/FlowComposerKeyboardReadinessTests
```

O wrapper recusa sobrescrever resultados. Bootar o simulador 27 explicitamente se estiver desligado. Antes de iniciar, verificar ausência de outra lane Xcode/Instruments. Acrescentar um cenário normal de Flow que exige Done e, no novo par, qualificar o caminho opcional nos **dois** apps. Revisar independentemente, conferir diff e commitar somente os caminhos aprovados.

Hashes esperados após aplicar GREEN, antes de outras alterações:

- `FlowChatUITests.swift`: `47526fbd17094e032fc4c7fc4fcf16d3a19c59dea2680259193ac7f8fcf00bbb`.
- `PremiumPerformanceUITests.swift`: `552e790fb5f69d8c8505a8c65613412008ba8733698b82bcd4a585f045e18555`.

## 7. Benchmark novo, integral e ordem da conclusão

1. Aprovar/commitar o GREEN acima. **Nenhuma alteração de produto necessária para esse ajuste do runner.**
2. Fazer `build-for-testing` Debug autêntico do runner atualizado, mesmo Xcode/SDK/min18/assinatura padrão. Guardar log completo e `.xctestrun`; não reaproveitar runner v2.
3. Os helpers `performe-flow-dock-stable-keyboard-pair.py` e `performe-analyze-flow-dock-stable-keyboard-pair.py`, seus manifestos e instruções estão no pacote privado do handoff e foram copiados juntos também para `flow-final-diagnostic-tools/`, destino usado nos comandos do runbook. Preparados/checados sintaticamente, **não executados**. Ler o README e revisar antes de usar.
4. Preparar `performance-pair-ios27-flow-dock-stable-keyboard`: apps **byte-idênticos aos do par falho**, um único runner novo nos dois lados; ordem before→after; mesmos dois testes, oito métricas por lado, cinco amostras por métrica, condições v2 correspondentes. Helpers exigem HEAD integral, fontes iOS sem diff, log real de compilação e preservação dos fingerprints.
5. Não misturar before antigo com after novo, não reaproveitar só o caso longo aprovado do par falho e não desabilitar validações com `python -O`. Preservar par falho/logs/frames. Comparar condições, identidades, amostras e workload antes dos números.
6. Investigar apenas piora reproduzível/achado concreto. Corrigir causa com cenário exato e nova revisão, sem laço de ensaios especulativos.
7. Encerrar focados, review e comparação atual; implementar tutorial como último grupo funcional antes de iniciar a integral/Release/smoke finais. Qualquer mudança de produto invalida a alegação de que o app assinado antigo contém o resultado final. Recompilar candidato e repetir gates impactados.
8. Executar a **suíte completa sem filtros**, já com o tutorial integrado, após build-for-testing atual e fontes congeladas. O script existente `flow-final-diagnostic-tools/run-full-ios-final.py <HEAD completo>` usa iOS27, serial, timeout 600 s por teste, hashes e resultados exclusivos por SHA. Não elevar timeout para mascarar quiescência sem evidência.
9. Repetir scanner/unitários, scan real dos bundles, Release sim/staging, Analyze, assinatura, review final, smoke físico e polish de alinhamento/teclado/transições. O tutorial precisa dos próprios focados e comparação de abertura/primeira tela; o benchmark Flow atual sozinho não valida a nova feature.
10. Finalizar relatório de 15 itens, commits locais e cleanup seguro. Manter gates editoriais/cliente explícitos.

Não executar novamente o script de Release dentro de uma pasta de resultados já concluída: ele deliberadamente recusa sobrescrita. Reutilizar derived/SourcePackages quando seguro, criar **somente pasta de evidências local** para o novo conjunto. Nunca usar `CODE_SIGNING_ALLOWED=NO` no simulador: o primeiro baseline perdeu entitlements de Keychain (-34018), invalidando parte dos testes.

## 8. Evidências atuais: o que passou e o que não passou

Todos os caminhos desta seção são relativos ao diretório privado `final-polish-20261001`.

| Evidência | Resultado e limite |
|---|---|
| Flow/Hoje iniciais | RED antes da correção; GREEN e revisões no ledger; ACK/retry/isolation não são pendências reiniciadas |
| `flow-composer-dock-focused` | 20 unitários + 4 UI AX/histórico PASS; 4 UI normais FAIL no toque durante movimento do teclado; rodada como conjunto não aprovada |
| `flow-dock-shared-readiness-focused` | **9 PASS / 0 FAIL / 0 skip**: 6 UI (cancelar/reabrir, 50 mensagens, resposta durante leitura, retry, A/B, proposta Plano) + 3 readiness; sem avisos de idle 60 s nessa rodada |
| `flow-dock-send-readiness-characterization` | 1 PASS, **963,008 s** com esperas de quiescência; prova funcional isolada, não performance ou integral aprovada |
| `flow-dock-layout-churn-probe` | 13 eventos, uma atribuição de altura natural; contexto diferente não demonstra melhora/causa; sonda removida byte a byte |
| `flow-final-diagnostic-tools/performe-flow-dock-current-review*` | Revisão independente e hashes do produto `5b123d0`; sem P1/P2/P3 concretos; partes do próprio revisor tiveram segunda revisão |
| Integral `038c1b7` | **1.776 PASS / 1 FAIL / zero skips**; contrato antigo de escala da barra, corrigido e aprovado no focado; não converter integral em PASS |
| Integral `3e9dde8` | Interrompida: **1.605 PASS / 2 FAIL** (geometria + caso cancelado); anteriores não cobrem o produto atual completo |
| `benchmark-keyboard-accessory-red` | **7 PASS / 2 FAIL / 0 skip**, etapa aberta deliberada |
| `scanner-staging-identity-green.log` | **25 PASS / 0 FAIL / 0 skip**; são testes Node, não procurar xcresult/resumo XCTest inexistente |
| `release-gates-flow-dock-5b123d0/manifest.json` | Release sim 39,481 s; Analyze 3,286 s; Release staging 34,188 s; build-for-testing 7,467 s; todos PASS |
| Scans `release-{sim,staging}-surface-scan-explicit-identity.json` no grupo Release | Ambos PASS: 844 chaves, 1.688 valores, 0 falhas/leaks |
| `physical-artifacts-readonly-preflight-5b123d0.json` | Assinatura, perfil/UDID, identidade e rollback validados; **não instalação** |

Scanner: o staging falhava por `UNEXPECTED_BUNDLE_IDENTIFIER`, não pela contagem 15/16 de assets. Agora `--expected-bundle-id` compara igualdade exata; default permanece `com.bodyflow.app`. Os 21 casos anteriores foram mantidos e quatro adicionados. Não remover essa proteção. Assets.car do staging antigo/novo byte-idênticos; PerformeAIAppIconV1 principal preservado.

Analyze e Debug atuais sem warnings; Releases com warning antigo de `await` em `SessionLifecycleCoordinator`. Logs Xcode têm mensagem peculiar de comando exit 0 sem further output também presente antes; resultados oficiais de build têm zero erros. Não confundir com uma falha nova nem apagar logs.

### Regressão geométrica recente

`5b123d0` usa observador UIKit no viewport original, identidade de UIScreen/window e key window, reconversão de frame em layout, apenas overlap residual de teclado docked/full-width; entrega assíncrona deduplicada por revisão, identidade de owner e closures fracas; descarte em mudança de sessão/window/dismantle. Scroll do compositor é único e persistente, contém proposta/campo/Send/aviso, respeita espaço disponível e preserva foco/binding. Limite 4.000/4.001 intacto. Não substituir por offset arbitrário.

Capturas inspecionadas em `flow-dock-shared-readiness-focused-attachments`: `5BC27961-F3D7-46CA-9F1A-15975E19F3D2.png` (âncora 35 legível) e `4BD5D0A6-954C-4219-B723-E1ECEF7A102B.png` (B preservado). A UI AX 4.001 mantém aviso completo, Send e foco acessíveis.

## 9. Performance e acessibilidade: limites que não podem desaparecer

- Par standalone v2: 5/5 por lado, 14 métricas × 5 amostras, 20 snapshots de condições equivalentes. Baseline `5d9429f`, produto candidato **antigo `ebf64a9`**. Nav/sheet v3: 2/2 por lado, mesmos apps do v2, outro runner comum.
- Médias v2: Flow50 5,417645→5,417658 s; longo 5,325460→5,308712; Biblioteca 5,306946→5,246010; launch nativo 2,371417→2,425651; Hoje observado 5,704076→5,733338. Pico Flow +144,1552 kB/+0,137%. Valores históricos, não métricas finais do compositor novo.
- V3: ciclo cinco abas 18,7293376494→14,0782285972 s; sheet refeição 2,6595815056→2,6057582390 s. Observação de um par, sem causalidade ou reprodutibilidade geral. XCTest observado inclui idle/AX, não TTID/FPS/duração de animação.
- App Launch: três tentativas inválidas por finalização do recorder. Não há trace aprovado; não repetir captura descontrolada (raws chegaram a dezenas de GB). Limpezas anteriores estritas foram documentadas; traces/metadados preservados.
- SwiftUI / Animation Hitches: recorder recusou simulador (`Hitches is not supported on this platform.`). Gate físico distinto.
- Time Profiler: par qualificado, PIDs 64311/64625, CPU amostrada 4,138→3,781 s; símbolos parciais limitam causa.
- Allocations: capturado e exportado, PIDs 65200/65858; Statistics agrega trace completo sem timestamp por linha. Seleção de janela comum na GUI permanece pendente. Não inferir leak/retention comparável ou pico físico dessa tabela.
- **`Invalid frame dimension (negative or non-finite)` continua sem causa/impacto estabelecidos.** No Flow apareceu no candidato ao focar compositor; stack nativa de 59 frames majoritariamente frameworks, sem linha causal. LLDB não capturou o alvo. Ocorrência no onboarding do baseline prova apenas ocorrência anterior naquele fluxo. Não chamar de bug comprovado do SDK, preexistência comprovada no Flow ou warning resolvido.
- Matriz PT/EN, light/dark, rotação, compacto26.5/27 e escalas passou nos focados documentados; não é evidência física final do novo candidato.
- VO27: 4/4 (1 UI foco/leitura/ordem/seleção + 3 parser), zero skips. Double-tap por coordenada foi refutado como prova de ativação por foco; **gesto real manual ainda pendente**. Audit tem exceções preexistentes explicitadas, não “zero findings”.
- Reduce Transparency/Increase Contrast foram exercitados e restaurados; VO26.5 OFF confirmado. Não modificar preferências do Mac/iPhone automaticamente; pedido anterior sobre DND foi encerrado pela decisão do usuário.

## 10. Instalação, acesso e dispositivos

### Artefatos atuais

- Candidato assinado: `/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/release-gates-flow-dock-5b123d0/artifacts/release-staging/BodyFlow.app`.
- Bundle staging `com.performeai.app.dev.k6942zjtv6`; team `K6942ZJTV6`; mínimo18; fonte produto5b123d0. Hash agregado das 310 fontes: `e384da4ec10fcb2319df65272323db42054a079d18a49fbe38010c2cc85f0913`.
- **Perfil expira em 04/10/2026 21:12:24 UTC.** Revalidar na retomada. Renovação normal de assinatura pode ser necessária; não instalar binário expirado nem alegar validação com perfil antigo.
- Config privada 0600: `/Users/eduardohenrique/.local/share/performe-ai/pre-llm-e2e/Release.staging.e2e-v23.private.xcconfig`. Ler só em processo seguro, não imprimir.
- Rollback: `/Users/eduardohenrique/.local/share/performe-ai/pre-llm-e2e/flow-target-staging-derived/Build/Products/Release-iphoneos/BodyFlow.app`; executável SHA-256 `e71d8d522190cb35f7bf16a9576db263f3659a86b056575705cae2b745447b02`.
- Supabase staging `xitugspwfxkcluxvrdeg`; **produção intocável `xuxehkhdvjivitduarvb`**. Não usar URL Preview histórica como configuração atual: obter configuração validada do candidato sem vazar credenciais. Não tocar deployment `dfik0mb7c`.
- Contas sintéticas: arquivos `/Users/eduardohenrique/.local/share/performe-ai/qa-ab/qa-a.env` e `qa-b.env`; senhas não pertencem a relatórios/prompts. Auth ID e ID de domínio são distintos.

### Dispositivos

| Dispositivo | Identidade / estado a preservar |
|---|---|
| Lane iOS27 | `CE89BD02-DF61-4214-AD61-2A2A51114022`, iPhone18Pro; originalmente Shutdown; restaurado a Shutdown em02/10 12:06:20 UTC, manifesto `simulator-closeout.json` |
| Canônico26.5 | `44AFCC15-85B3-4823-801E-2837718B9266`, iPhone17ProMax; originalmente Booted; VO OFF/Light/texto Large restaurados; app BodyFlow estava ativo no corte, não foi encerrado por este handoff |
| Compacto26.5 | `C8F43960-7D04-48E5-9AE0-1051E25548EE`, iPhone17e; Shutdown restaurado |
| Simulador pessoal | iPhone17Pro `27291590-659D-4A29-8F45-CA5CA2D154F9`; não sobrescrever |
| iPhone físico | iPhone13ProMax / iPhone14,3 / iOS27.2; UDID `00008110-001649510208401E`; CoreDevice `EE36D674-87E2-5CB4-8C91-7AD0E2340E0B` |

As ferramentas MCP podem ter default no26.5: usar destino explícito27 no CLI. Não há xcodebuild/xctrace/runner de UI em andamento no corte. Disponibilidade do iPhone deve ser verificada novamente, sem presumir conexão por evidência antiga.

Última inspeção CUA reportou Mac bloqueado e necessidade de desbloqueio manual; já havia pedido pendente ao usuário. `listApps()` funcionar não prova desbloqueio. Claude Code pode ter outras ferramentas disponíveis, mas não deve contornar proteção. Testes CLI independentes podem continuar. Para câmera/microfone real, não inventar captura pelo espelhamento: usar as possibilidades reais do dispositivo e pedir ação humana apenas quando indispensável.

Smoke do candidato final: abertura/restore/logout/onboarding; QA A→B→A sem conteúdo antigo; cinco abas/estado/sheets; teclado e B durante A; cancel/retry; proposta versus confirmação; peso80/data; rotina após horário; deep link de lembrete; Biblioteca sem rascunhos; VO real/tato; tutorial e replay. Usar dados sintéticos, sem nova confirmação de dieta apenas para provar UI.

## 11. Cleanup, recursos e preservação

- Nenhuma infraestrutura paga temporária criada; custo recorrente **novo** de infraestrutura zero. Staging/Previews preexistentes **KEPT** para beta; custo exato não reestimado. Não excluí-los por concluir Git.
- ROOT deve continuar, pois trabalho/gates/tutoriais ainda pendem.
- Dois worktrees auxiliares: `~/.codex/worktrees/performe-flow-polish/performe-ai-client-beta-flow-v1` e `~/.codex/worktrees/performe-journey-polish/performe-ai-client-beta-flow-v1`. Arquivamento recusado por proteção de task/workspace fixado. Inventário não encontrou commits exclusivos; há variantes locais preservadas. **Sem snapshot de archive nem remoção realizados. Não contornar proteção com rm/worktree remove --force.**
- Não executar limpeza global, prune, reset, clean, stash-drop ou apagar traces/resultados válidos. Os patches que estavam em `/tmp` foram copiados para o pacote privado com hashes.
- Encerramento desta passagem: simulador27 restaurado a Shutdown, exit0, sem xcodebuild/xctrace/UI runner ativo. Estados26.5 Booted e compacto Shutdown preservados. Manifesto privado `claude-code-handoff-20261002/simulator-closeout.json`; dispositivo físico intocado.

## 12. Pedido novo: tutorial inicial guiado

Pedido literal de Eduardo: **“quero tb que ao final adicione um tutorial inicial guiado para o usuário entender tudo que é possivel ser feito no app atualmente”**.

É escopo autorizado para a continuação, **não trabalho já implementado**. Requisitos detalhados/proposta de implementação em `docs/handoffs/2026-10-02-performe-ios-guided-tutorial-scope.md`. O Claude deve completar o código, testes e QA; este handoff não substitui essa entrega.

Princípios: explicar capacidades realmente disponíveis, a partir da UI/capabilities; após autenticação/onboarding existente; tutorial opcional e retomável pelo Perfil; não alterar consentimentos ou sequência clínica; usar componentes atuais; não executar registros/publicações/envios reais para demonstrar; preservar navegação/formulário e isolamento de contas. Rascunho/proposta não é registro confirmado, e cancelar espera do Flow não garante cancelamento no servidor. Biblioteca pode estar vazia enquanto conteúdo não foi publicado.

Detalhes de apresentação/quantidade de passos são proposta técnica, não um novo design aprovado pelo usuário. Resolver com bom julgamento, validar com o código e preservar o aceite visual humano final. Não bloquear esperando aprovação para começar o trabalho já autorizado.

## 13. Entrega ao cliente continua com gates próprios

1. Fluxo editorial real: Roberto submete, Eduardo revisa independentemente, Roberto publica; depois validar conteúdo publicado/salvar/remover/concluir/persistência/PT-EN/isolamento.
2. Decisão nutricional pendente sobre metas de novas sugestões. Não inventar regra.
3. Aceite visual explícito de Eduardo do candidato final, incluindo tutorial.
4. Canal real e instalação para Roberto; sem TestFlight/App Store nesta autorização. O fato de existir um app assinado ou instalado no iPhone de Eduardo não fecha esse gate.

## 14. Relatório final e fontes a consultar sob demanda

Relatório solicitado no anexo: **1 Resumo executivo; 2 Auditoria; 3 UX/UI; 4 Splash e abertura; 5 Loading; 6 Logo central; 7 Motion; 8 Identidade visual; 9 Performance; 10 User friendly; 11 Acessibilidade; 12 Novas ideias; 13 Testes; 14 Pontos pendentes; 15 Status final.** Incluir tutorial onde pertinente e estados operacionais reais exigidos pela política global.

Documentos complementares:

- `docs/handoffs/2026-10-01-performe-ios-final-polish-implementation.md`: ledger cronológico completo, inclusive tentativas falhas e posterior resolução.
- `docs/handoffs/2026-10-01-performe-ios-final-polish-report.md`: relatório provisório em 15 itens; tabela de métricas e limites.
- `docs/handoffs/2026-10-01-performe-ai-second-delivery-ios-progress.md`: evolução anterior até notificação/Biblioteca; ler atualizações finais.
- `docs/handoffs/2026-09-30-performe-ai-second-delivery-ios-scope-addendum.md`: escopo anterior.
- `docs/handoffs/2026-09-30-performe-ai-beta-handoff-to-codex.md`: contexto histórico, IDs/URLs/estado não necessariamente atuais.
- Anexo original de design: `/Users/eduardohenrique/.codex/attachments/9dfc1e2f-6917-44b4-96df-8c6e7179d34f/Texto colado.txt`; cópia no pacote privado do handoff. O plano aprovado posterior restringe as ideias amplas do anexo (sem partículas/parallax/dependências etc.).
- Plano aprovado: o resumo da seção5 + requisitos de validação e ordem deste documento preservam suas obrigações. Comparar também testes/diff/reviews; não ler todo o histórico antes do próximo passo pequeno.

### Estado de encerramento desta sessão

**Handoff pronto não significa app concluído.** `REGRESSION STATUS: PARTIALLY VERIFIED`. `PRODUCTION STATUS: NOT DEPLOYED`. `IOS INTEGRATION STATUS: IMPLEMENTED / PARTIALLY VERIFIED` para refinamento existente; tutorial pendente. `USER VISUAL ACCEPTANCE: PENDING`. `ROBERTO BETA CANDIDATE STATUS: NOT READY FOR CLIENT ACCEPTANCE`.

Não houve push, merge, deployment de produção, instalação do candidato atual ou infraestrutura paga nova nesta passagem. Revisões históricas qualificam seus diffs; patch GREEN e tutorial ainda precisam de sua própria revisão e evidência. Continuar do ponto exato sem recomeçar a operação nem prometer conclusão antes dos gates.
