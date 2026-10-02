# Performe AI — refinamento final iOS

> Ledger cronológico. Ponto atual de continuação em 02/10/2026: [handoff para Claude Code](2026-10-02-performe-ios-claude-code-handoff.md). Estados “pendente” nas entradas antigas podem ter sido resolvidos nas posteriores.

## Escopo e controle da execução

- Pedido: implementar o plano aprovado de refinamento final do beta iOS.
- Host verificado: `MacBook-Air-de-Eduardo.local`, macOS/Darwin arm64; `LOCAL_DEVELOPMENT`.
- Checkout: `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`.
- Branch: `codex/performe-ai-client-beta-flow-v1`.
- HEAD inicial: `5d9429f9648c0906e1c9a13ebd1bbe0c6c467103`, árvore inicialmente limpa.
- Reutilizar staging. Commits locais; sem push, merge, Production, TestFlight ou App Store.
- API, banco, fórmulas nutricionais e WhatsApp fora das alterações.
- Nenhuma infraestrutura paga nova. Dois worktrees locais isolam escritores concorrentes; arquivar após integração e verificação.
- Resource gate inicial: PASS para uma única lane Xcode; 16 GiB RAM, 33% livre, 94 GiB de disco livre. Nenhum build Xcode concorrente.

## Evidências em andamento

Diretório privado de execução: `~/.local/share/performe-ai/final-polish-20261001/`.

### Baseline

A primeira execução (`baseline.xcresult`) usou equivocadamente `CODE_SIGNING_ALLOWED=NO` no simulador. Não serve como baseline de performance:

- Rendering XCTest: 34/34 passaram.
- Swift Testing: 1.485 testes, 14 issues. Revisão independente separou 13 falhas ligadas à ausência de entitlement de Keychain (`-34018`, `errSecMissingEntitlement`) e uma race preexistente em `SessionLifecycleCoordinatorTests.logoutMarkerBoundarySerializesSwitch` (`sessionSuperseded` versus `missingSession`, store mock).
- Performance UI: abertura executou; os outros três cenários não chegaram à tela necessária para medir.
- A repetição deve usar assinatura padrão `Sign to Run Locally`, sem modificar team ou entitlements.

### RED antes das correções

- Flow: `flow-red-unit.xcresult`, oito cenários; sete falharam pelos comportamentos esperados (13 assertions), retry/idempotência já passou.
- Flow UI: `flow-red-ui.xcresult`, outbox inexistente enquanto aguardava resposta. Login/fixture funcionou com assinatura padrão.
- Hoje: atualização manual repetida caracterizada por duplicação de chamada; confirmação que supersede leitura anterior já protegida.
- Peso 80 kg/data: texto oficial presente, mas identificador do contêiner mascarava os identificadores dos filhos na árvore de acessibilidade.
- Rotina criada após horário: ocorrência nula caracterizada no contrato e apresentação da UI.

### Revisão independente preliminar

Revisão de navegação/componentes identificou, antes do commit:

1. Segundo callback Confirm ignorado pelo modelo podia celebrar o receipt antigo. O feedback deve deduplicar identidade persistente além do token local.
2. Falha antiga da proposta podia contaminar captura nova. A projeção deve consultar somente o subsistema correspondente ao intent aceito.
3. Splash com overlay não acomodava landscape/AXXXL. Conteúdo precisa participar do layout e poder rolar.

Os achados recebem testes próprios e nova revisão após os gates.

## Plano de verificação restante

1. Baseline de performance assinado concluído: `/tmp/performe-journey-performance-before.xcresult`, 4/4 benchmarks. Abertura 0,825 s; scroll Biblioteca 5,912 s/46.965 kB; Flow 50 mensagens 6,036 s/45.107 kB; resposta longa 6,021 s/47.876 kB. Cinco iterações, mesmo simulador 26.5. App anterior assinado preservado em `baseline-sim/BodyFlow.app`.
2. GREEN focado de Flow/Hoje, componentes, navegação e registro.
3. Integração no checkout principal; revisão independente dos diffs graves.
4. UI em PT/EN, claro/escuro, tamanhos compactos/Pro Max, teclado, Dynamic Type e adaptações de acessibilidade.
5. Instruments e comparação no mesmo simulador/configuração/dados; investigar piora reproduzível.
6. Suíte iOS completa, scanner de marca/localização, Release, análise nativa, assinatura e smoke no iPhone de staging.
7. Commits locais, documentação final de 15 itens e arquivamento seguro dos worktrees auxiliares.

## Limites da entrega ao cliente

Continuam separados: fluxo editorial real da Biblioteca, decisão nutricional pendente, aceite visual de Eduardo e instalação para Roberto. Nenhuma ação editorial ou aceite é registrado em nome deles.

## Integração em andamento

- Flow integrado após GREEN de 30 testes em cinco suítes e quatro testes de UI, com revisão independente (dois P2 identificados, corrigidos e retestados; nenhum HIGH/CRITICAL). Evidências `flow-green-unit` e `flow-green-ui`.
- Primeira verificação de componentes: 32 testes de modelo/política/router e três renderings passaram. A UI da barra customizada é publicada como `Other` com cinco botões SwiftUI; os seletores dos testes agora usam seu ID estável `navigation.tab-bar`, preservando as assertions de destinos, seleção e toque. Regressão integrada pendente.
- Revisão Hoje confirmou preservação de snapshot/revisão e valores oficiais. Dois P2 adicionais em tratamento: consulta duplicada do coach durante atualização concorrente e skeleton de Progresso que ocultava peso oficial já recebido.
- RED de teclado: numberPad de hidratação sem ação acessível `keyboard.done`; fix será compartilhado nos campos UIKit de registro.
- Todos os indicadores indeterminados das jornadas agora usam o componente compartilhado com atraso cancelável de 150 ms; o indicador de etapas reais do onboarding permanece determinado.

### Verificações adicionais

- `integrated-render-red.xcresult`: 39 testes de apresentação/registro passaram; quatro renderings passaram (incluindo alinhamento do símbolo estático/runtime); RED confirmou que skeleton ocultava 80 kg enquanto `/progress` aguardava. Correção preserva qualquer resposta independente de perfil; GREEN pendente. Probe landscape AX em diagnóstico separado.
- `scanner-tests.log`: 21/21 testes do scanner novamente passaram, sem substituir scan do bundle Release.
- Teclado UIKit: `/tmp/performe-journey-keyboard-green2.xcresult`, 1/1 UI com hidratação 500, peso 80, duração 47; nenhum valor perdido ao fechar teclado.
- `/tmp/performe-journey-unit-green.xcresult`: 127 testes / sete suítes passaram após RED de refresh simultâneo com quatro issues.
- Revisão transversal preservou os filtros e recuperações acessíveis existentes da Biblioteca, seções de Perfil e foco/consentimentos de Auth/Onboarding. Encontrou dois P2 no Plano: lista fixa de até 20 rascunhos e teclado numérico de descanso sem conclusão explícita. Correções e testes em andamento.
- Flow ACK: `flow-ack-red-suite.xcresult` reproduziu cinco issues em 20 testes. `flow-ack-green-full.xcresult` passou 31 unitários em cinco suítes e dois UI. POST B é permitido enquanto GET de A aguarda; revisão independente adicional não encontrou HIGH/CRITICAL/MEDIUM. O teste específico do instante ACK → Enviar é determinístico no modelo, ainda sem fixture UI com GET suspenso.

### Integração e novas regressões

- `integrated-focused.xcresult`: os dois UI de marca passaram (proposta pronta versus confirmação, erro/retry/nova sheet). Quatro renderings passaram; dois probes de conteúdo rolável seguem em diagnóstico.
- O teste da barra encontrou 15 elementos com trait Button: cinco controles e seus filhos herdando o trait. A correção ignora filhos na árvore acessível e mantém label/seleção/Large Content Viewer nos cinco controles; GREEN pendente.
- O teste de entrada no Flow revelou que `isHittable` podia ser verdadeiro com parte do controle sob a barra flutuante. O helper agora exige que o controle esteja completamente acima da barra antes do toque, mantendo a assertion de destino.
- Splash em viewport curto/AXXXL exibiu quadro teal vazio: o espaço simétrico de centralização era maior que a tela. `ViewThatFits` agora escolhe scroll com marca e descrição visíveis quando a composição simétrica não cabe; GREEN pendente.
- Progresso agora preserva o peso oficial recebido independentemente enquanto o endpoint de progresso espera. A prova de apresentação está sendo repetida com o host nativo de teste corrigido.
- Parse Swift de 77 arquivos alterados: PASS; não substitui build/testes.

### Integração: evidências adicionais

- Plano: `/tmp/performe-plan-red.xcresult` confirmou quatro REDs (Done numérico e 20 rascunhos em loaded/empty/offline AX5). `/tmp/performe-plan-green-focused.xcresult` passou teclado e loaded, 2/2; empty/offline aguardam a suíte ROOT. O teclado preservou 60, fechou com alvo de 44 pt e manteve Salvar habilitado, sem persistir.
- `integrated-third-focused.xcresult`: 39 testes Today + Session Lifecycle passaram. O teste preexistente de logout foi tornado determinístico bloqueando a gravação da substituição: exige `missingSession` antes e `sessionSuperseded` após. Nenhuma mudança de autenticação de produção.
- Hoje durante invalidação: `integrated-second-focused2` caracterizou quatro issues (duas chamadas extras de conteúdo/coach). A guarda do coordenador agora também reconhece a leitura de Hoje em andamento; GREEN na terceira rodada.
- UI de hierarquia de Hoje passou na segunda rodada, incluindo protocolo no disclosure e consumo/meta oficiais visíveis.
- Privacidade visual: terceira rodada confirmou pixels da conta A no primeiro quadro neutro após logout. A raiz agora desativa transição e geometria compartilhada enquanto existe owner anterior divergente, invalidado ou em teardown. Quarta rodada: teste visual de logout PASS. Variante A→B acrescentada para a próxima execução.
- Barra: a árvore do Large Content Viewer reexpunha elementos visuais como ações. `accessibilityRepresentation` publica um botão semântico por destino, preservando a prévia visual. Quarta rodada: cinco ações, ordem, targets e navegação PASS.
- Flow: o teste integrado mostrou compositor sob a barra (894 pt versus início da barra em 848,7 pt). O inset agora é aplicado em cada tela real dentro da pilha, incluindo destinos; nova verificação em andamento.
- Título de rascunho AX5: RED mediu 37,7 pt pintados versus 99,7 pt do título completo. O componente compartilhado permite crescimento vertical; GREEN pendente.
- O probe manual de acessibilidade dos testes de rendering retorna vazio até para um ScrollView com um único Text. Isso invalida a prova por esse helper para conteúdo rolável; os cenários de peso enquanto progresso espera e Splash landscape serão portados para o runner de UI real, mantendo os critérios e sem ignorar falhas do produto.

Status desta nota: execução em andamento. Nenhuma alegação de validação final ou distribuição.

### Quinta rodada e provas reais de UI

- `integrated-fifth-focused.xcresult`: PASS, sete renderings e três UI. Privacidade após logout e A→B, centro estático/runtime, contraste da Splash, seis estados da marca, cinco ações em largura compacta, título completo AX5, ordem/destino da barra, compositor A/B e teclado, conteúdo em PT/EN AXXXL.
- `real-ui-proofs2.xcresult`: dois UI PASS. Peso oficial de 80 kg e data visíveis enquanto a leitura independente de Progresso fica suspensa; descrição completa da Splash alcançável em landscape AXXXL. O primeiro build desta fixture encontrou um case de enum faltante no repositório demo, corrigido antes da execução.
- Os probes manuais de ScrollView foram substituídos pelas duas provas no runner real; o helper de rendering foi restaurado ao original. A prova de controle demonstrou que a enumeração manual não enxergava nem um Text simples rolável. Nenhum cenário do produto foi ignorado.
- Revisão independente de AppRoot/privacidade, loading e política visual: sem achados HIGH/CRITICAL/MEDIUM. Revisão visual de navegação, compositor e título: sem novo bloqueador; screenshots exportados e lidos.
- O revisor do Flow identificou preservação insuficiente de um ACK já reconciliado quando uma leitura posterior retorna snapshot atrasado/vazio. Regressão adicional preparada antes da correção; gate de commit permanece aberto.
- `integrated-full.xcresult`: suíte completa iniciada com assinatura padrão; resultado ainda pendente. Scanner unitário repetido: 21/21 PASS.

### Gates adicionais preparados durante a suíte

- Swift Testing integral: 1.517 testes / 130 suítes PASS; renderings integrais PASS. Os UI ainda estão em execução.
- A exceção geométrica de contraste da UITabBar antiga foi removida do audit de convergência. A nova barra será avaliada pelo gate reforçado em execução focada posterior; falhas sem elemento continuarão exigindo inspeção dos attachments.
- Provas UI de persistência entre abas preparadas: Plano com 20 rascunhos e descanso 60 sem salvar; Flow com 50 mensagens, rascunho B e âncora de leitura. A ausência de Concluir no teclado do Flow deverá ser caracterizada antes da correção.
- Configuração privada do Release: conferida presença dos identificadores de staging esperados e ausência do ref de produção; nenhum valor secreto registrado. Build anterior do iPhone preservado, assinatura verificada, bundle `com.performeai.app.dev.k6942zjtv6`, mínimo iOS 18.

### Achados da suíte integral em andamento

- Commit local `a0988a7`: deduplicação das leituras de Hoje e preservação de snapshot, com regressões determinísticas e revisão independente. Sem push.
- O cenário Plano / 20 rascunhos / offline / AXXXL falhou na exposição do ID de retry. Correção preparada: limite semântico explícito no ScreenStateView embutido, preservando o botão filho. Ainda aguarda GREEN.
- Auditoria de convergência encontrou contraste em `tab.plano` no Hoje e texto cortado em `tab.hoje` no estado vazio inglês AXXXL escuro. Investigação aberta; essas falhas não serão ignoradas nem tratadas como aceite.
- Novos testes determinísticos Flow caracterizam ACK reconciliado seguido de GET atrasado, horizonte de 50 mensagens, 51 ACKs, outbox confirmado fora da janela e mudança de conversa sem cache. Testes integrados; patch de produção aguarda RED e revisão final.

### Correção da instrumentação de desempenho

- Os três benchmarks de rolagem existentes utilizavam `XCTMemoryMetric()` sem aplicação. Essa API mede o processo corrente do runner XCTest; seus picos de 45–48 MB no baseline e 87–91 MB durante a suíte integral não são medidas de memória do Performe AI. Não constituem uma regressão comprovada do app.
- A nova comparação utilizará `XCTMemoryMetric(application: app)` nos mesmos cinco ciclos, com o mesmo bundle de testes contra os builds antes/depois congelados. As séries antigas serão mantidas e rotuladas como memória do runner. Capturas Allocations devem selecionar o processo BodyFlow.
- Referência da API: https://developer.apple.com/documentation/xctest/xctmemorymetric/init(application:) ; confirmada também nos headers do SDK local.
- Na suíte integral, antes da repetição pareada: abertura 0,780 s; rolagens Flow50 6,729 s, resposta longa 5,797 s e Biblioteca 5,248 s. Esses tempos incluem gestos XCTest e não equivalem a FPS ou tempo nativo de interação.
- O teste Reduce Motion procurava a data de atualização antes de abrir os detalhes, contrariando a divulgação secundária aprovada. Os testes de Hoje foram ajustados para abrir os detalhes e manter a verificação do valor; nenhuma assertion do dado foi removida.

### Resultado integral e correções da revisão

- `integrated-full.xcresult`: 1.517 Swift Testing / 130 suítes PASS; 41 renderings XCTest PASS; 184 UI executados, 175 PASS e nove falhas. Três são apresentação/acessibilidade (retry embutido e dois audits da barra); seis são expectativas que precisavam seguir a navegação/disclosure aprovados. A lista completa permanece no xcresult.
- Gaps de 903/950 s na suíte Flow coincidem com suspensão do host, comprovada pelo `pmset` em `host-sleep-during-full.txt`. Não são tempo de operação do app. A comparação de desempenho exigirá host acordado; assertion de idle sleep limitada ao processo de testes, sem mudança persistente de preferências.
- `review-followups-red-ui`: 24 testes determinísticos Flow executados antes do patch, com 24 issues que caracterizam a perda/reordenação/evicção das respostas. Patch final integrado após aprovação independente estática; GREEN pendente.
- O teste UI de Flow com 50 mensagens confirmou ausência de Concluir para o rascunho B. Adicionada toolbar pública de teclado e descarte interativo por rolagem; GREEN pendente.
- O retry do Plano com 20 rascunhos/offline/AXXXL passou na repetição após `.contain`.
- Captura real mostrou colisão de ícones/rótulos da barra em AXXXL; a representação acessível não explica sozinha o problema. Ajuste de navegação em tratamento, com Large Content Viewer preservado e conteúdo das telas mantendo Dynamic Type.
- A matriz Premium usava apenas `-AppleInterfaceStyle`, mas uma captura solicitada escura estava clara. O helper passa a controlar a aparência pública do XCTest, restaurá-la no teardown e conferir o tema efetivo no Hoje; não serão alegadas provas escuras com screenshots claros.

### Fechamento dos incrementos de integridade e navegação

- `review-followups-green.xcresult`: 1.525 Swift Testing / 130 suítes PASS, incluindo os 24 cenários de concorrência do Flow. O roundtrip de 50 mensagens, rascunho B, Concluir e mesma posição de leitura passou (66,6 s). Esta rodada ainda falhou em rendering/UI de alvos da barra, setup de entrada por colagem e auditoria AX; não é regressão integral verde.
- O setup de 4.000 caracteres por UIPasteboard/CmdV não produziu o valor exato, embora o foco estivesse confirmado. Os logs registram permissões de colagem entre runner/app. Voltou à entrada nativa `typeText`, conservando assertions exatas de 4.000/4.001 e todos os critérios da UI; repetição em andamento.
- `navigation-hit-frame.xcresult`: cinco renderings e a UI de ordem/seleção/destino/áreas mínimas passaram. Dynamic Type limitado à barra, com conteúdo das telas sem limite. Permanecem os alertas de auditoria sobre Dynamic Type e contraste do botão Registrar; nenhum foi ignorado.
- Prova com tamanho de texto 11 ativado no sistema do simulador: o HUD nativo de Large Content Viewer exibiu `Progress` completo (`lcv-hold-tab.progresso.png`). Ao soltar, a aba não abriu. O novo teste preserva este RED; mover o modificador antes/depois da representação e remover a representação não resolveu a ação. Correção do vínculo nativo em desenvolvimento; configuração original do simulador (texto 3) deverá ser restaurada após a prova.
- Revisões independentes finais dos fontes de Flow, Hoje, Progresso, Rotina, privacidade de AppRoot e loading: nenhum novo bloqueador P2+ encontrado. Hash do FlowChatModel revisado: `bec34d1319b8461ac18f1605dbd82fc920daebe0fc95e842aec7188e340e74b4`. A navegação mantém seu gate próprio aberto.
- `testThemeLocaleMatrixAndSupportedRotations` passou com verificação do tema efetivo após uso da API pública de aparência do XCTest. Aparência original é restaurada no teardown.
- A API de snapshot interativo XcodeBuildMCP retornou uma raiz sem alvos apesar de screenshot válido. XCTest UI segue funcional; a preparação de Instruments foi adaptada para workloads XCTest existentes, com apps/bundle de testes pareados, sem depender de coordenadas ou seletores inventados.

### Navegação nativa acessível e isolamento da decoração

- `flow-native-limit.xcresult`: 2/2 UI PASS, entrada nativa de 4.000/4.001 caracteres e controles completos em AXXXL. O setup por colagem foi substituído após caracterização da permissão entre processos; limites e assertions foram preservados.
- `navigation-container-semantics`: cinco ações, ordem, seleção, destinos, alvos mínimos e pressão longa/release PASS. A trait `.isTabBar` no contêiner reexpunha filhos decorativos como botões; foi removida. O ramo visual ganhou representação acessível vazia e a semântica ficou nos controles nativos.
- `navigation-drag-and-border-red`: arrastar Progress → Register antes de soltar não ativava o destino. A implementação passou a usar uma interação pública `UILargeContentViewerInteraction` no contêiner dos cinco UIButton; SwiftUI continua responsável pela aparência, marca e animação.
- `navigation-shared-dedup-red`: dois testes caracterizaram duplicação em callbacks invertidos/repetidos. `navigation-shared-dedup-green`: nove testes nativos e o cross-drag UI passaram após consumo único por pressão. Revisão independente não encontrou novo P1/P2.
- O probe de rendering em processo retorna AX frame zero para UIButton com window e bounds válidos. O teste passou a medir bounds nativos nesse host; a UI externa conserva contagem, ordem, alvos de 44 pt, contenção na tela, centro e destino. Nenhum critério de toque foi dispensado.
- Tamanho de texto global restaurado de 11 para 3 via Device Hub. `navigation-centered-audit`: cross-drag PASS nessa configuração com AX5 no app. `navigation-final-accessibility`: pressão longa e release PASS (25,3 s); capturas `lcv-default-system-tab.progresso.png` e `lcv-default-system-tab.registrar.png` mostram os HUDs completos. Revisão visual independente confirmou os dois.
- A borda experimental do tile não alterou o alerta de contraste e foi removida. A representação vazia apenas da decoração eliminou os alertas correspondentes; nenhuma exceção nova de Dynamic Type ou contraste da barra foi mantida.
- Alertas posteriores em conteúdo rolável eram medidos sob a barra ou no desfoque superior. O retry revelado tem contraste medido de 9,65:1. A auditoria agora mantém cada finding pendente, revela o mesmo nó por scroll e exige nova auditoria de contraste com frame inteiro visível. Repetir `.all` alterava o layout/posição; a segunda passagem usa apenas `.contrast`. Erros visíveis persistentes, perda de identidade e impossibilidade de revelar continuam falhando.
- Quatro famílias de estado passaram em um UITest (vazio/offline/erro/indisponível). A auditoria loaded encontrou timeout do instrumento durante a recuperação; esse resultado foi preservado como falha. Otimização de consultas do teste e fechamento em lote estão em validação, sem alterar cores nem ignorar permanentemente findings.
- Patch aditivo de workload Instruments integrado: cinco ciclos entre as cinco abas, somente IDs presentes nos dois builds. Os quatro benchmarks existentes permanecem separados desse workload. Scripts privados de congelamento/pareamento passaram revisão estática e selfcheck; capturas reais continuam pendentes.

### Revisão adversarial adicional: replay antigo e auditoria em rolagem

- `flow-old-retry-red.xcresult`: 25 testes/uma suíte, sete issues somente no novo cenário parametrizado com janelas de 40 e 50 mensagens. Um POST A com timeout local, GET mais recente e replay idempotente antigo seguido de GET offline colocava o ACK no fim; na janela cheia removia uma mensagem recente. A correção reutiliza a ordenação oficial já existente antes de truncar os dois caminhos. GREEN e revisão independente adicional em andamento.
- `navigation-audit-after-callback`: a retenção de findings fora do callback encerrou esta execução sem timeout. Falha residual no mesmo nó “407 kcal”, já aprovado no centro, ao voltar à borda. Revisão independente confirmou contraste de pixels ~14,79:1 e card parcialmente sob a barra. A área conservadora de avaliação usa margem de 64 pt nos dois extremos; essa margem não representa uma dimensão universal do blur do sistema. Cada nó segue obrigado a passar exposto.
- `navigation-audit-clear-viewport`: falha de alcance do teste após 327 s; nó “Exercício excluído” estava a y−1618,7 após outra passagem no fim da tela, além dos quatro gestos permitidos. O alcance passou ao mesmo limite de 24 gestos usado no helper existente; continuam obrigatórios progresso real, identidade original, frame inteiro visível e nova auditoria. Não houve alteração de cores nem exceção por rótulo.

- `flow-old-retry-green-and-navigation`: 29 testes/duas suítes Swift PASS, incluindo os dois novos casos; revisão independente adicional confirmou o hash `cc3c48f288f362e203943cf431978048aa6a4ae6736eae2982a985aafd0d9cac`. Flow core/testes/strings versionados localmente em `0423f2e`. A parte UI da mesma rodada passou Hoje e Registrar, mas parou no limite real de rolagem do Plano; não é uma rodada integral verde.
- O texto final do Plano ficou integralmente visível em y785,17–804,50 e não podia ser centralizado além do fim da rolagem. O harness agora permite auditar a posição final somente se o frame inteiro estiver exposto, exige ausência de finding para esse mesmo ID e frame idêntico após a passagem. Recorrência de alerta na posição validada ou no centro segue bloqueadora. Revisão independente aprovou esse delta; execução em andamento.
- Commits locais adicionais: `fa2b763` (hierarquia oficial e refresh de Hoje, com recortes dos testes de disclosure) e `2e27691` (adoção de loading compartilhado em Biblioteca/Perfil/Mascot). Nenhum push ou distribuição.

### Preferências reais do simulador e barreira de controle

- Device Hub / iPhone17ProMax iOS26.5: estados originais observados Light, texto3, Reduce Motion/Increase Contrast/Reduce Transparency/VoiceOver desligados. Reduce Transparency isoladamente e Increase Contrast isoladamente ativaram superfície opaca com contorno na barra; capturas privadas em `os-accessibility-smoke/`. Ambos foram restaurados para off.
- VoiceOver foi ativado; o aviso inicial de gestos foi reconhecido e o foco apareceu no título Hoje. Antes de ativar Registrar, CUA informou que o Mac bloqueou e não conseguiu desbloquear automaticamente. Pergunta assíncrona enviada ao usuário. **VoiceOver do simulador permanece ON; restaurar OFF e conferir o estado original antes dos testes/performance.** Não foi alterado VoiceOver do Mac/iPhone físico. O smoke VoiceOver está incompleto.
- `navigation-audit-scroll-limit`: quatro famílias de estado PASS em38,1s; loaded sofreu novamente erro de execução Apple−56 em passagem de contraste, sem concluir. A ferramenta ganhou recuperação estrita: uma tentativa extra por método, só domínio/código exatos, todos os findings das duas tentativas preservados, segunda API obrigatoriamente concluída e regras de contraste/posição intactas. Delta aprovado por revisão independente; novo run ainda pendente.
- `dd89cfa` versiona o peso oficial independente visível e as fixtures/regressões exatas de peso80kg/data e rotina após o horário. Sem alteração nutricional/API.

### Código versionado e Release preparado durante o bloqueio do Mac

- Revisões independentes finais de Plano, Registro, Flow/UI e navegação não encontraram P1/P2 adicional. Commits locais: `23b17e2` navegação/Flow UI, `9485254` Plano, `d880e6e` Registro. Nenhum push, merge ou backend/WhatsApp alterado.
- O Release detectou conversão de closure não-Sendable no componente da marca. O tipo de `action` passou a `@MainActor`, alinhado ao controle UIKit; revisão independente aprovada, aviso eliminado no novo build. Nenhum caller atual fornece essa closure.
- `release-gates-mainactor-20261001`: Release sim PASS39,838s, scanner sem falhas/leaks e assinatura estrita PASS. Analyze PASS7,891s, zero erros/warnings. Release staging PASS35,499s, assinatura/team/bundle verificados; build-for-testing PASS9,974s. Fonte app/projeto estável, hash54dc672165151040c4490d4ab75cf356d47694d65c738cab760b9a5c0773dd41.
- O log Release contém linha contraditória do executor SwiftCompile com exit0; xcresult confirma succeeded/errorCount0 e somente await preexistente. Objeto/executável recompilados e assinatura conferidos. Causa interna não determinada; não ocultar a observação.
- `.xctestrun` real gerado usa FormatVersion1, com BodyFlowTests e BodyFlowUITests. Scripts privados preparados para FormatVersion2 requerem adaptação estrita ao formato real antes da comparação; nenhuma medição nova executada.
- `c0068e3` preserva os três harnesses em commit preparatório. Build-for-testing e revisão estática passaram; audit com recuperação, regressão completa e performance permanecem sem execução nesta configuração final.
- Mac continuava bloqueado na última tentativa CUA. VoiceOver do simulador permanece ON e precisa ser restaurado; demais preferências já restauradas. Nenhuma alteração de acessibilidade foi aplicada no Mac ou iPhone físico. Candidato assinado não instalado; rollback anterior preservado.
- Relatório provisório de15itens: `2026-10-01-performe-ios-final-polish-report.md`. Gates de entrega humana/editorial não alterados. Sem recurso pago novo, sem claim de conclusão.

- Tentativa independente no compacto iPhone17e/iOS26.5: `compact-navigation-smoke.xcresult` FAIL18,34s. Hierarquia/cinco ações/ordem/alvos/centro passaram; toque sintetizado não abriu Registrar. Captura simctl posterior terminou em código60 `Timeout waiting for screen surfaces`. Não concluir causa produto ou bloqueio do host sem nova evidência; repetir este cenário após desbloqueio antes de correção. Nenhuma assertion foi enfraquecida. Pro Max/VO não alterados.

- Parser privado FormatVersion1/2: RED contra plist real antigo, dry-run novo PASS sem criar pair,53 verificações de arquivo PASS e revisão independente aprovada. Nenhum trace/benchmark executado.
- Contraprova compacta de acesso ao Flow PASS15,434s, incluindo teclado, digitação e resposta local. Não há indisponibilidade geral de interação; a falha da barra precisa de causa raiz. Comparação de árvores indica sibling inferior também no Pro Max previamente aprovado; overlap sozinho não prova interceptação. Testes L/AXXXL explícitos e probe temporário público de hit testing preparados antes de qualquer fix.
- Compacto estava Shutdown após XCTest; a captura posterior com timeout não demonstra causa do host. ROOT bootou explicitamente C8 para diagnóstico e leitura do container. A restauração para Shutdown fica pendente ao terminar essa lane. Pro Max continua Booted/VO ON aguardando mãos do usuário.


## Navegação compacta — caracterização adicional

- A falha isolada `compact-navigation-smoke.xcresult` foi preservada. A contraprova de Flow mostrou que XCTest continuava conseguindo interagir com o app sob Mac bloqueado.
- Instrumentação temporária opt-in observou os callbacks nativos; `compact-navigation-hit-probe.xcresult` passou L e AXXXL. Cada cenário recebeu um único beginPress, finishTouch e performActivation, com seleção Registrar cerca de 30 ms depois. Não houve caminho LCV. Nenhuma amostra window.hitTest foi emitida; não há prova de interceptação.
- A revisão independente comparou árvores: mesmo frame da ação Registrar e mesmo sibling inferior no FAIL e PASS L. Isso não sustenta uma correção de geometria.
- Instrumentação removida integralmente; fontes do produto voltaram ao commit. `compact-navigation-no-probe-repeat.xcresult`: 10 execuções PASS (cinco L e cinco AXXXL), 92,456 s. São duas variantes, não dez testes exclusivos.
- A cobertura preserva o método original sem categoria e adiciona variantes L/AXXXL, com as mesmas assertions e um único toque. Revisão independente aprovou a cobertura. O método original passou em 8,818 s na rodada `compact-navigation-default-and-audits`, ainda em execução para os audits.
- Causa da falha isolada permanece indeterminada. Não foi aplicado ajuste de produto especulativo nem aumentado timeout.
- CUA confirmou Mac bloqueado. Isso impede completar/restaurar VoiceOver manual no simulador canônico 26.5; não impede os testes XCTest do compacto. Nenhuma preferência do Mac foi alterada.


## Gate de acessibilidade compacto aprovado

`compact-navigation-default-and-audits.xcresult`, iPhone 17e / iOS 26.5: 3/3 PASS em 287,901 s. Cenário original de Registrar: 8,818 s; audit loaded das cinco abas: 240,625 s; quatro famílias de estado em um teste: 38,458 s. A recuperação de erro -56 não foi usada. A aprovação cobre este dispositivo/runtime/configuração; não substitui VoiceOver, nova integral ou matriz restante. Cobertura de tamanho padrão/L/AXXXL commitada localmente em b4f483a, com revisão independente, sem mudança funcional no produto.


## Ressalva da revisão visual ao PASS compacto

A revisão independente dos attachments encontrou um gap no harness de reexposição, não um novo defeito de cor: a descrição de erro estava em y333,0/h249,3; Library fixo em y265,7/h84,0 terminava349,7, cobrindo 16,7 pt do texto. O viewport usado no teste considerava somente NavigationBar.maxY101 e precisa considerar os atalhos fixos dos estados sem snapshot. O PASS automático de 3/3 não fecha essa prova; correção do harness com cenário geométrico exato e nova auditoria são necessários.

Os screenshots de empty/offline/error mostraram tema efetivo light apesar do pedido dark:true. Portanto a rodada não comprova contraste dark; a matriz separada verifica o valor efetivo do tema. Três findings preexistentes de Perfil (Notificações da demonstração/Ativadas, Dynamic Type/clipping) foram tratados pelas exceções já documentadas; não houve exceção nova da barra.


## Matriz compacta e diagnóstico de tema — 02/10/2026

- `compact-final-matrix.xcresult`: 14/15 PASS. Cinco abas, dois gestos LCV, Splash landscape AX, Flow 4.000/4.001 normal/AX, Flow50 e rascunho/âncora entre abas, cancelamento local, três cenários Plano20, onboarding EN/AX, controles de Registro e peso80/data passaram. Falhou somente a matriz de tema: esperado dark, valor real light. Não aprovar dark por argumento de lançamento.
- `audit-pinned-viewport-red-theme-diagnostic.xcresult`: controle loaded PASS; RED exato do viewport falhou101 versus357,7. Diagnóstico de tema confirmou XCTest getter rawValue2/dark com app light.
- `audit-pinned-viewport-green-cli-theme.xcresult`: dois testes geométricos GREEN; diagnóstico dark ainda FAIL mesmo após `simctl ui appearance dark`, sem helper de aparência.
- Abertura direta por simctl, fora do XCTest, também permaneceu clara. O build baseline anterior foi instalado sobre o app sintético do simulador e mostrou o mesmo comportamento no mesmo estado. Imagens `compact-dark-direct-loaded.png` e `compact-dark-baseline-loaded.png` preservadas. Isso não atribui causa ao refinamento nem prova a causa do ambiente.
- App candidato de Debug reinstalado e aparência original light restaurada, confirmada por simctl. Nenhuma alteração no iPhone físico. Diagnósticos temporários retirados do fonte; a matriz original continua exigindo o tema real.
- Novo teste nativo de VoiceOver via API pública iOS27 integrado após revisão estática independente; ainda sem execução. Compatibilidade18–26: apenas o novo serviço indisponível causa skip explícito; o gate27 exige2PASS/0SKIP. Sem hooks de ativação no produto.
- Aviso SwiftUI `Invalid frame dimension (negative or non-finite)` observado em campos Flow/Plano e Onboarding. Revisão read-only não identificou aritmética inválida no fonte; sem stack e sem falha visual associada, causa e preexistência permanecem indeterminadas.

## Auditoria de exposição e VoiceOver — 02/10/2026

- A primeira execução `audit-pinned-viewport-native-green` passou os dois testes geométricos e falhou ao expor o texto offline: os 24 gestos alternavam posições por overshoot. Revisão independente aprovou experimentar exclusivamente `.slow` e pausa final de 0,1 s, mantendo identidade, margens, limites e auditoria posterior.
- `audit-pinned-viewport-slow-green`: quatro famílias de estado passaram a auditoria nativa em 51,334 s; sem recuperação do erro Apple -56. Capturas e hierarquias preservadas para revisão visual independente. O tema efetivo continua sendo um gate separado.
- `ios27-voiceover-focus-qualification` falhou em 57,032 s no reconhecimento do anúncio, antes do gesto de ativação. O transcript real percorreu as cinco abas: `selecionado Today Botão`, `Plan Botão`, `Register Botão`, `Progress Botão`, `Profile Botão`. O parser do teste exigia separadores inexistentes no anúncio. Correção do harness e cenário determinístico em preparação; a falha não evidencia ausência dos botões na navegação VoiceOver.
- Teardown da tentativa VoiceOver executou restauração e não reportou falha. O simulador canônico 26.5 ainda exige restauração manual de VoiceOver; a interface do Mac segue bloqueada para CUA. O simulador 27 será usado nos dois lados da nova comparação, sem misturar métricas históricas de 26.5.
- Patch de observação de condições do runner integrado após revisão independente e 38 selfchecks sintéticos. A compilação do runner passou nesta execução de auditoria. Nenhuma medição pareada foi feita ainda.

## Fechamento do diagnóstico VoiceOver e incremento Flow — 02/10/2026

- Parser: `ios27-voiceover-parser-red` teve duas falhas e um PASS, incluindo a fala exata `selecionado Today Botão`. A correção revisada exige rótulo inteiro + papel nativo e preserva negativos. Na execução seguinte os três testes do parser passaram.
- `ios27-voiceover-green`: 3 PASS/2 FAIL em 112,041 s. A leitura e a ordem forward/backward passaram; o gesto `doubleTap` aplicado na coordenada de outra aba não abriu o destino focado. Esse resultado não foi dispensado como aprovação de ativação.
- Calibração independente em botão SwiftUI comum: `ios27-flow-green-voiceover-calibration-qualified`. Imediatamente antes do gesto, Library continuava focado, VoiceOver estava ligado e o ponto (137,83;593) estava dentro de Chat with Flow e fora do frame Library. Depois, Library=false e Flow=true; VoiceOver continuou ligado. O XCTest ativou o destino da coordenada nesse experimento. O header público de `XCUIVoiceOverService` oferece navegação/leitura, sem ação activate. A hipótese de usar esse toque como garantia de ativação por foco foi, portanto, refutada no harness; não se atribuiu defeito ao produto ou SDK.
- O script integral de diagnóstico está preservado em `VoiceOverActivationCalibration.swift` no diretório privado, junto dos dois xcresults de calibração. Revisão independente aprovou delimitar a cobertura permanente a foco, ordem, rótulos, papel e seleção. Ativação por VoiceOver permanece gate manual explícito, sem substituir a garantia por um toque normal ou ocultar a falha original.
- Novo achado P3 da revisão: histórico vazio + primeiro POST falho/cancelado + reentrada com GET pendente e outbox preservado não mostrava indicador incremental. Teste determinístico parametrizado falhou em ambos os casos antes da mudança. A correção de uma linha inclui outbox no predicado de reconciliação; 30 testes em duas suítes passaram em 0,044 s. A outbox e a chave foram preservadas, sem POST adicional. Revisão ROOT independente da autoria do patch, commit local `f7bae16`. Nenhuma mudança de contrato, backend, regra nutricional ou WhatsApp.
- `ios27-theme-qualification` passou PT/EN, claro/escuro efetivo e rotações em 48,788 s. A nova auditoria compacta tem pixels dark comprovados após o reboot; a matriz compacta de tema ainda será repetida antes do fechamento.

## Candidato integrado para regressão final

- Código do aplicativo: `f7bae16`; testes e auditoria: `b8d7b1e`. O predicado de loading é a única diferença de produto desde o artefato Release anterior. Novo hash dos 308 arquivos de produto/projeto: `9d30c57d4c5189913b52baba5c9cdcf4574238608d930c2e0d9156387fa0fa31`. Novo Release será necessário após essa mudança.
- `ios27-voiceover-focus-and-speech-final`: 4/4 PASS, 55,283 s, nenhum skip; 1 nativo de foco/leitura/ordem/seleção + 3 parser. Restauração não reportou falhas. Revisão independente final aprovou escopo e preservação da calibração; ativação manual permanece aberta.
- `compact-theme-final`: PT/EN, claro/escuro efetivo e rotações PASS, 41,385 s. O teste original foi preservado; a falha anterior não se repetiu depois de boot novo. Não se atribuiu causa definitiva ao lock ou SDK.
- Scanner: nova execução 21/21 PASS em 3,213 s.
- `ios27-final-full-suite` iniciada sobre `b8d7b1e`, sem filtros, uma lane, timeout máximo de 600 s por teste. Resource gate PASS: 43% livre no memory_pressure e 72 GiB de disco. Não há builds, outros testes ou UI concorrentes nessa lane.
- Compacto C8 restaurado a Light/categoria Large/contraste desativado e desligado, como estava antes desta rodada. O 27 permanece ligado para a suíte; o canônico 26.5 continua com a restauração manual de VoiceOver pendente por bloqueio do Mac.

## 2026-10-02 — integral iOS 27 interrompida para diagnosticar três falhas

- Candidato `b8d7b1e`: Swift Testing **1.527 testes / 130 suítes PASS** e XCTest de modelos/rendering **51 PASS**. UI: **47 PASS, 3 FAIL** antes da interrupção deliberada com SIGINT; um quarto resultado é `Testing was canceled` em `PlanDraftUITests.testFlowProposalOpensTheReviewAndConfirmsNothingByItself`, não falha funcional demonstrada. Bundle `ios27-final-full-suite.xcresult` preservado, execução incompleta; não é regressão integral aprovada.
- Falha Flow original mantida: `testPendingOutboxAppearsBeforeReplyAndKeepsNewComposerOnLocalCancel`, assert de ausência da barra após digitar B. Gravação mostra barra real e acessório Concluído, sem teclas QWERTY naquele quadro. Dois probes focados reproduziram o FAIL.
- Probe temporário de geometria pública confirmou sequência iOS 27: `willChange end=(0,498,402,376)` → `willChange end=(0,792,402,82)` → **`didHide end=(0,792,402,82)`**. O observer tratava todo `didHide` como ausência de teclado, embora ainda houvesse 82pt ocupados pelo acessório. Ao concluir a edição, `willChange` e `didHide` reportam `(0,874,402,0)`. Evidência: `ios27-keyboard-hide-frame-events.log`, PID49368; nenhum conteúdo digitado registrado no probe.
- Probe removido antes da correção. `BodyFlowKeyboardObserverTests` agora caracteriza deterministicamente a sequência 376→82→didHide82→0→didHide0; RED em execução. O UI original ganhou apenas verificação adicional de Concluído → barra retorna e B permanece.
- MealCapture: `testUnrecognizedTextSaysSoAndStartsOver` e `testWrittenMealIsReviewedBeforeAnyProposal` falharam após tap em Ler alimentos com teclado abrindo; modelo/fixture não mudaram desde `5d9429f`. Hierarquias finais mantêm texto focado, sem review/failure; evento sintetizado usou centro `(201,673.4801)`, enquanto posição final do botão ficou `y325.4–391.7`. Vídeo mostra transição de sheet/teclado, mas não prova que o ponto estava fora do botão no instante DOWN. Patch proposto independentemente mantém teclado aberto, exige geometria estável e botão integralmente exposto antes de **um único toque**, preservando todos os asserts; aplicado somente no harness, GREEN ainda pendente.
- Revisão independente final estática `5d9429f..b8d7b1e`: sem novo P1/P2/P3 concreto em navegação, sessão, feedback, superfícies e launch. Não substitui o gate do teclado, performance nem aparelho físico.
- WhatsApp, API, banco e regras nutricionais sem alterações.

## 2026-10-02 — teclado GREEN e baseline puro compilado

- `keyboard-accessory-red.log`: regressão unitária exata FAIL único na linha31, 0,663s. A finalização do Xcode parou por mais de dois minutos após todos os testes terminarem, sem app desse destino ativo; SIGINT não encerrou, então o processo da tarefa foi finalizado com TERM. O bundle RED não possui Info.plist final; **evidência RED é o log**, não um xcresult legível. Probes UI anteriores também falharam e possuem bundles preservados.
- Correção mínima: `keyboardDidHideNotification` usa o mesmo cálculo público do endFrame usado no `willChangeFrame`. Sem logger/probe no produto. `keyboard-accessory-and-meal-green.xcresult`: **5 PASS, 0 FAIL, 0 SKIP**, exit0. Unitário0,003s; Flow123,277s (inclui onboarding); Meal AX83,130s; xyz22,313s; refeição escrita145,685s.
- UI Flow conserva B após cancelamento, não possui barra com teclado/acessório, e após Concluído exige teclado ausente, barra restaurada e B intacto. Captura `flow-keyboard-green-attachments/79A484B3-B730-417F-AD58-A577DCCF4A3A.png` revisada: teclado/compositor sem a barra.
- Revisão independente aprovou a correção para commit, com limitação do RED documentada. Commit local **`ebf64a905fce3b329faa5d12fc5287db0dc81ed2`**; sem push.
- MealCapture: os attachments de ambos registram botão325,4–391,7 e teclado590. O helper inicialmente encontrou a barra da raiz; como a ordem AX não identifica a sheet, sua consulta foi endurecida para a barra que contém `sheet.fechar`, sem fallback. Os resultados anteriores permanecem válidos porque o botão também estava abaixo do header real (até167,3). Nova qualificação dos dois casos em `meal-sheet-header-final` em execução; sem mudança de produto MealCapture.
- Baseline puro **`5d9429f`**: build-for-testing PASS, errorCount0,24 warnings do snapshot antigo; assinatura estrita PASS, bundle `com.bodyflow.app`, mínimo18, SDK27, plugin de testes original presente. Os **440 blobs continuam idênticos ao Git após o build**. ExecutávelSHA256 `9acc335a90143a9f8e9e0b48d0f536b7f2a11462ba67ebc33ced4fe2432edb98`. Evidência `baseline-pure-5d9429f-verified.json`.
- Preparação dos gates Release atualizada antes de qualquer execução: fonte app/projeto308 arquivos, hash `2db39df1c27b13d5e6050652b4ae66576b4b4ef51ba2c3d6000d92439ef293f0`, HEAD `ebf64a9`. Preparação anterior preservada em arquivos `initial-preparation-*`; gates ainda não executados.
- RESOURCE GATE: PASS, serial,74GiB livres/28% memória livre no preflight. Nenhuma infraestrutura nova.
- CUA confirmou novamente Mac bloqueado; automação visual/restore VoiceOver26.5/QA físico permanecem dependentes de desbloqueio. Não há bypass de autenticação.

### MealCapture — consulta final da sheet aprovada

`meal-sheet-header-final.xcresult`:2/2 UI PASS,0 skips; xyz23,837s e refeição escrita139,112s. Os dois attachments registram explicitamente o header da sheet `(8,115.4444,386,51.8507)`, detect `(31.0448,325.408,339.9104,66.2537)` e teclado `(0,590,402,226)`. A consulta é única pelo botão `sheet.fechar`, sem depender da ordem das navigation bars e sem fechar o teclado. Todos os asserts originais permanecem. Testes commitados localmente após revisão do patch e da evidência. A suíte integral final ainda precisa executar no candidato corrigido.

## 2026-10-02 — gates de build finais e início das medições

Fonte de produto `ebf64a9`, testes/harness `7b66fdd` (16 commits locais desde a referência). `release-gates-final-20261002/manifest.json` agora está **BUILT_AND_VERIFIED_NOT_INSTALLED**:

- Release simulador:PASS45,243s;0 erros,1 aviso preexistente de await sem operação async em SessionLifecycleCoordinator. Assinatura estrita, identidade/minOS18 conferidos.
- Analyze:PASS3,444s;0 erros,0 avisos/analyzer findings.
- Release staging:PASS38,965s; assinatura/team/bundle/Keychain groups compatíveis com o rollback. ExecutávelSHA256 `12ac6180e5b92d153503b26c512d924521368e29cdb96de389abe34ad26e52aa`; perfil válido até2026-10-04T21:12:24Z. Não instalado.
- Build-for-testing:PASS4,497s,0 erros/avisos.
- Scanner do novo bundle:PASS;844 chaves/1.688 valores;0 falhas e sem modificação de assets históricos. Os21 testes do scanner já haviam passado nesta rodada.
-308 fontes app/projeto inalteradas ao longo dos gates; hash `2db39df1c27b13d5e6050652b4ae66576b4b4ef51ba2c3d6000d92439ef293f0`.

Par real congelado em `performance-pair-ios27`: before é o build puro5d verificado; after é o candidato atual. Mesmo runner e bundle UI, mesmo simulador iPhone18Pro/iOS27.0. Execuções standalone antes/depois iniciadas sequencialmente com snapshots públicos anteriores/posteriores. Cinco amostras por cenário e memória do app; resultados ainda em coleta, sem conclusão de melhora/regressão. Não usar os números históricos26.5 para essa comparação.

## 2026-10-02 — comparação standalone real e primeiro Instruments

- `performance-pair-ios27`: before e after terminaram exit 0, 4/4 métodos PASS por lado, 13 métricas com cinco amostras cada. Comparador de condições: `MATCHED_RECORDED_CONDITIONS`; mesmo runner, apps congelados, iPhone 18 Pro/iOS27, VO OFF e demais condições registradas equivalentes.
- Médias dos clocks: Flow50 −0,060%; resposta longa +0,086%; Biblioteca +6,565% e launch nativo +3,849%. Faixas dos dois últimos se sobrepõem, sem equivalência ou causalidade demonstrada. Pico de memória do app: Flow50 +258,8672 kB/+0,245%; longa −2,187%; Biblioteca −4,086%. São resultados de um par, não aprovação automática de performance. Repetir os sinais de piora e examinar Instruments antes de concluir.
- `before-app-launch-all-processes-01`: tentativa real com limite90s ficou incompleta, interrompida pelo watchdog105s antes do método terminar. Evidência preservada; não conta como benchmark aprovado. Filhos encerrados (`lane_children_stopped=true`). A duração do executor será ajustada simetricamente, sem alterar workloads/apps/runner/assertions.

- Interface do Mac voltou a responder via CUA. No Xcode27, o app disponível é Device Hub (`com.apple.dt.Devices`), não o antigo Simulator.app. Simulador canônico iPhone17ProMax/26.5 selecionado: VoiceOver foi restaurado ON→OFF pela UI pública. Árvore AX completa posterior confirma OFF; Light/texto3/ReduceMotionOFF/IncreaseContrastOFF/ReduceTransparencyOFF preservados. Esse gate de restauração não permanece bloqueado. Ativação real VO e smoke físico continuam distintos.
- Override diagnóstico `--duration-seconds` 60..900 revisado independentemente; checks de boundary59/60/240/900/901 PASS. Wrapper corrigido para encaminhar zero explicitamente ao parser. App Launch repetido com240s/attempt02 igualmente nos dois lados, nenhum workload/app/runner alterado.

## 2026-10-02 — recuperação parcial do Instruments

- App Launch attempt02 teve workload PASS, mas recorder não finalizou em30s; TERM posterior exit1 e trace incompleto, exportfalha `Document Missing Template Error`. Probe natural10s sem XCTest continuou aguardando>90s; amostra mostrou espera DTXConnectionServices. Reinício apenas do CE89 sem erase não resolveu o probe AppLaunch. Log nativo reportou erro de consulta CPU (`deviceinfo Code=15`), sem causa atribuída.
- Probe TimeProfiler produziu trace legível; recebeuTERM na janela de finalização, então não foi usado como benchmark nem como prova de término espontâneo. Executor foi ajustado após revisão independente: sucesso pode finalizar porSIGINT por até120s; falha conserva cleanup30s; sinais registrados, TERM desqualifica mesmoexit0. Selfchecks normal/forced/defaultcleanup PASS.
- Par real TimeProfiler attempt01: before/after XCTestexit0, recorderexit0, `forced=false`; fingerprints dos apps instalados coincidem com os congelados. Both `captured_pending_table_and_process_review`. Before PID58750, finalização28,384s; after finalização22,878s. Exports de tabelas nativas e comparação de condições em revisão independente. TOC sozinho não é aprovação.
- O catálogo bruto do trace de simulador inclui processos do host; metadados de target continuam apontando CE89. A análise deve filtrar estritamente PIDsBodyFlow/ranges do workload, sem confundir runner/sistema/host com custo do app.

## 2026-10-02 — scratch de profiling e harness de condições

- RESOURCE GATE: BLOCKED temporariamente para novas capturas ao observar11GiB livres. Inventário identificou arquivos `.ktrace` no temp do usuário criados exatamente durante os runs Instruments da tarefa; traces finais ocupavam256MiB. AppLaunchattempt01/02 deixaram raw31,4/27,2GB, ambos fechados no `lsof`; probes ainda tinham handles abertos e foram preservados.
- Limpeza estritamente dos dois raw fechados: timestamps de nascimento até5s do início dos captures, tamanho/owner/path validados, captures `incomplete_or_failed` e filhos encerrados, ausência de handles revalidada. Manifesto e hash apenas dos primeiros64KiB (não do arquivo completo) preservados em `closed-instruments-scratch-cleanup.json`; logs/traces/amostras permanecem. Removidos58.584.479.232bytes; existência negativa verificada. Disco voltou68GiB; nenhum outro temp/cache foi removido.
- TimeProfiler real continha amostrasRunningBodyFlow:9692/9623; janela de workload4,147/4,044s CPU amostrada. Não é comparação aprovada: orientation0 em todas as fases após reboot; guard estrito rejeitou, simbolicação parcial. Sem atribuição a fonte, ganho ou piora causal.
- Harness configura agora portrait pela API pública e verifica getter antes dos snapshots; não substituiunknown nem relaxa comparador. Adicionado benchmark de Hoje utilizável: clock observadoXCTest desde launch até fixture731kcal+Atualizar habilitado/hittable e frames integralmente expostos, cinco amostras; não é TTIDnativo. Ambos os deltas tiveram revisão independente, build-for-testing PASS.
- Novo par congelado `performance-pair-ios27-v2`, apps byte-idênticos ao par1, novo runner compartilhado. Cinco cenários after→before; condição orientation1 já observada no setup/workload-start do primeiro cenário. Novo grupo `standalone-v2` exige os cinco métodos; guards anteriores preservados. Resultados em execução.
- Opções públicas preparadas para AppLaunch reduzem contextSwitchSampling/recordWaitingThreads parafalse, mantendo os demais defaultsfalse. JSON/hash registrados pelo executor; review estático e validação posterior dos eventos nativos de launch são necessários. A redução de volume ainda precisa ser demonstrada; não equivale a aprovação do template.
- Mac voltou a bloquear durante a tentativa de fechar o Instruments aberto pela tarefa. Não foi contornado. Probes com handles abertos e smoke físico continuam pendentes; isso não bloqueia os testes XCTest autorizados.

## 2026-10-02 — cinco benchmarks locais aprovados em execução invertida

- `performance-pair-ios27-v2`: candidato5/5 PASS (after05:12:28–05:17:14UTC); baseline puro5/5 PASS (before05:17:14–05:21:52UTC), zero falhas, exit0. Novo Hoje utilizável41,762s/41,700s são durações dos métodos, não métricas de latência; médias oficiais serão extraídas separadamente.
- Comparador inicialmente rejeitou ordem temporalinvertida por supor before→after. RED reproduzido dos próprios logs/snapshots e preservado em `conditions-order-red.txt`. Correção aceita intervalos disjuntos nas duas ordens, rejeita overlap e reversão interna e registra executionOrder. Oito casos determinísticos PASS; paroriginal4 e parv2invertido5 retornam MATCHED_RECORDED_CONDITIONS. Guards deunknown,VO,power,thermal,bracketing e igualdade não foram relaxados. Revisão independente do delta solicitada.
- Commit local `038c1b7210cde27d9ad31eead032e28cfc62a4fb`: dois arquivos somente do harness, 65linhas adicionadas/1removida; revisão independente prévia dos patches, build-for-testing e 5/5 em ambos os apps. Produto permanece `ebf64a9`, Release assinado existente válido para as mesmas fontes. Total17commits desde5d; nenhum push.


### 02/10/2026 05:32 UTC — v2 standalone e limite do App Launch

- HEAD `038c1b7`, 17 commits locais. Produto continua `ebf64a9`. Harness v2 fixa/asserta portrait antes das condições e adiciona Hoje utilizável observado. Independente revisou antes do commit.
- Par v2 after→before: 5/5 PASS por lado, 14 métricas × 5 amostras, condições equivalentes. Biblioteca −1,148% (piora inicial não repetida); lançamento +54,234 ms/+2,287%, mediana +18,45 ms; pico Flow50 +144,1552 kB/+0,137%; Hoje observado +29,262 ms/+0,513%. Intervalos sobrepostos não estabelecem causalidade. Warning de frame inválido recorre no after; não ocultado.
- Comparador de condições inicialmente recusou a ordem inversa. RED preservado e ajuste mínimo aceita ambas as ordens não sobrepostas, sem relaxar guards. Oito casos de limite e os dois pares reais PASS; revisão independente.
- App Launch v2 before: XCTest exit0; recorder PID62180 recebeu SIGINT e excedeu120s, então TERM/exit1. Captura inválida, não aprovada. Opções públicas reduzidas não resolveram a finalização nem o volume de scratch. Não repetir o template sem nova hipótese/evidência.
- Scratch desse capture chegou a48.790.378.264 bytes, mantido aberto pelo DTServiceHub56862, filho da instância Instruments criada pela tarefa. Nenhum recorder/xcodebuild ativo; os seis handles ktrace pertenciam às capturas da tarefa. Encerrou-se apenas esse helper após validar identidade; GUI e outros helpers não alterados. Manifesto `stopped-task-profiler-helper.json`.
- Após confirmar ausência de handles, removidos somente três raws App Launch inválidos, total58.755.621.952 bytes. Traces/logs/probes/metadados preservados. Manifesto `closed-instruments-scratch-cleanup-v2.json`. Espaço voltou a68GiB. Mac bloqueado impediu interação visual; nenhuma tentativa de contornar bloqueio.
- Próximo gate Instruments: SwiftUI v2 iniciado serialmente. Não executar exports pesados/builds/QA simultâneos.


### 02/10/2026 05:38 UTC — templates incompatíveis e identidade de captura

- SwiftUI e Animation Hitches v2 recusados imediatamente pelo recorder: `Hitches is not supported on this platform.` Não houve workload válido; logs/traces preservados, nenhum desses gates aprovado no simulador.
- Time Profiler v2 tentativa01: XCTest PASS e recorder finalizou normalmente/exit0, mas guard de identidade rejeitou PID residual63625, deixado pelo XCTest interrompido do template anterior. O log mostra `Terminate com.bodyflow.app:63625` antes do launch; bundle desse PID já removido. O novo PID63915 tinha os dois hashes esperados do baseline. `postfailure-identity-check.json` preserva a distinção. Captura continua rejeitada; guard não relaxado.
- Tentativa02 começou sem processo residual. Baseline passou teste, finalização e identidades; candidato passou teste e está finalizando. Comparação nativa só após leitura real de tabelas e PIDs.


### 02/10/2026 05:47 UTC — Time Profiler qualificado / Allocations capturado

- Time Profiler v2 tentativa02: PIDs64311/64625, ambos XCTest/recorder exit0, sem force. Condições MATCHED, portrait1. Exports reais `time-profile`, filtrados por processo e PID de thread, somente Running/peso1ms. Janela UTC do workload:4.138/3.781 amostras =4,138/3,781s de CPU amostrada; Main Thread3,923/3,559s. Observação do par, sem aprovação global ou atribuição causal. Leaf frames sem simbolicação; pais reais preservados. Revisão independente recalculou valores e aprovou limites.
- Allocations v2: modo attach no PID BodyFlow novo, antes do primeiro swipe; mesmos workloads e apps congelados. Ambos testes PASS/recorder0/sem force/identidades conferidas. Capturas prontas para leitura das tabelas e comparação das condições. Não confundir bytes de alocações com pico de memória física.
- Preparado diagnóstico limitado LLDB do aviso de frame usando símbolo público verificado `_os_log_fault_impl`, callback com limite80frames/8hits/60s/1MiB e PID exato. Não executado ainda; não muda produto/testes e seus timings não são benchmark.


### 02/10/2026 05:54 UTC — limites de Allocations, diagnóstico LLDB e integral iniciada

- Allocations: Statistics exportado nos dois lados (763.255/855.189 bytes;3.745/4.137 categorias), escopo do único PID anexado65200/65858; condições MATCHED. Tabela agrega trace inteiro e não tem timestamps de linha. Não calcula delta da janela comum, pico físico nem leak. Próxima análise possível é selecionar a janela na GUI do Instruments quando o Mac estiver acessível. Revisão independente aprovou inventário/limites.
- LLDB diagnóstico01: PID66776/binários exatos; attach pausado fez assert de contagem40 expirar antes do compositor, testeexit65. Não é evidência nova de falha funcional; diagnóstico inválido. O comando sugerido `--function` foi rejeitado; help oficial confirmou `--python-function`, corrigido no plano. Callback0hits; debugger desligado.
- Diagnóstico02: PID67015/binários exatos, attach com execução contínua. Símbolo `_os_log_fault_impl` resolvido na imagem runtime27; callback armado e lido. Um fault às05:51:20.734Z teve stackNSPredicate/XCTAutomationSupport, não o warning alvo. Formato C não disponível, causa não estabelecida. Callback encerrado/breakpoint desabilitado/debugger detached às05:52:16Z. Teste terminouPASS/exit0 às05:53:00Z, sem usar timings como benchmark.
- Consulta nativa confirmou o warning alvo às05:51:33.714Z, categoriaSwiftUI, no mesmoPID e após foco do compositor. Portanto não houve captura da stack desse warning nem correção; ele permanece aberto sem supressão. O tool MCP exibiu o UUID de seu default26.5 no recibo do attach, mas PID/caminho/binários e lookup da imagem27 confirmaram o alvo realCE89. Defaults não alterados.
- Integral corrigida iniciada às05:53:25.912Z emHEAD038c1b7, sem filtros/skips, runnercongelado, máximo600s por teste. Resourcepreflight50GiB livres/54% memória livre; nenhum debugger/recorder/export concorrente. Bundle `ios27-final-full-suite-038c1b7.xcresult`, execução em andamento.


### 02/10/2026 06:02 UTC — evidência já existente do warning

Export JSON limitado ao evento exato PID67015/05:51:33.714Z revelou backtrace com UUIDs e imageOffsets. Leitura do registro existente, sem nova captura. A análise offline foi delegada; ainda não atribui causa. Mantém a distinção: LLDB não capturou o aviso; o log nativo preservou stack não simbolicada. Revisão documental pediu precisão nos gates/TYPECHECK/LINT/NEW FAILURES; ajustes incorporados. Manifesto original das ferramentas revalidado e preservado, novo manifesto para adições/cópias corrigidas.


### 02/10/2026 06:15 UTC — stack offline e proteção dos worktrees

- Análise offline concluída e revisada independentemente: 59 frames = 56 de frameworks/OS, dois entrypoints genéricos do produto e um UUID/offset zero. Imagens verificadas por UUID/segmentos; entrypoints por atos no binário congelado. Sem geometria ou linha causal; nenhum novo runtime/debugger/cache grande. Relatório, JSON e parser preservados em performance-tools-v2.
- Revalidados os dois worktrees auxiliares anexados: zero commits exclusivos/staged/ignored. archive_worktree recusou ambos com “This worktree is protected by a pinned task or workspace.” Nenhum snapshot/arquivamento/removal foi concluído. CLEANUP STATUS: BLOCKED nesse escopo; não contornar proteção nem apagar variantes. Worktree ROOT e outros worktrees preservados.


### 02/10/2026 07:00 UTC — preparação dos gates complementares

- Integral 038c1b7 continua sem filtros, com 52 XCTest de modelos/rendering e 1.527 Swift Testing/130 suítes PASS. Inventário estático: 198 métodos/23 classes no target UI, incluindo três parsers e cinco benchmarks; não equivale a conclusão da execução. Cinco benchmarks existentes já passaram nesta integral; suas métricas não são misturadas ao par controlado v2.
- Revisão de cobertura identificou duas medições quantitativas faltantes: navegação e apresentação de sheet. Patches aditivos revisados independentemente em navigation-sheet-benchmark-preparation; cinco métodos anteriores intactos. Dois métodos novos, cinco amostras por lado, apps v2 byte-idênticos e novo runner comum. Fonte ainda não aplicada nem compilada/executada, preservando a integral corrente.
- Warning repetiu em Flow, Plano e onboarding na integral. Comparação estática estreita: toolbar de teclado foi adicionada em Flow/Plano; BodyDataStepView e sua toolbar já eram idênticos ao baseline. MealCapture usa o mesmo campo sem toolbar e não apresentou aviso nos três casos concluídos. Associação, não causa comprovada.
- Preparada e revisada checagem isolada do mesmo teste FreshUserCompletesOnboarding no baseline puro e runner v2 congelados. Valida hashes/PID, um método, log nativo exato e limpeza. Caso visita BodyData, mas não focaliza explicitamente seu campo numérico; ausência não refuta a hipótese. Script/guia em warning-check-preparation, ainda não executados.
- Simbolicação limitada pelo módulo SwiftUICore carregado pode reutilizar a stack existente: UUID exato, endereço carregado atual de __TEXT mais offset validado. Plano preservado, sem attach durante a integral. Consulta não prova dimensão/view causadora e deverá parar se só houver imagem/offset sem símbolo útil.


### 02/10/2026 07:25 UTC — integral detectou contrato antigo no teste de escala

- `testAuthenticatedBrandLayoutAcrossContentSizes` falhou em Prompt14AccessibilityUITests.swift:436: AccessibilityXL e AccessibilityXXL produziram68,33333333333337pt, enquanto o teste exigia crescimento estrito. Integral continua para coletar o restante; não será registrada como GREEN.
- Inspeção e revisão independente confirmaram que23b17e2 trocou o alvo brand.product-name pelo botão tab.registrar mantendo o crescimento exigido para o cabeçalho antigo. A barra tem limite visual `.xxxLarge`, já documentado; conteúdo mantém sua própria escala e LCV é gate separado. Nenhuma correção de produto autorizada pela evidência atual.
- Preparando patch somente de teste que verifica crescimento antes do limite, estabilidade acima, escala do conteúdo atéAX5, cinco controles/min44/viewport/Library push. Não aplicar enquanto a integral estiver ativa. Após focado e os benchmarks novos, repetir integral final completa com200 métodos declarados.


### 02/10/2026 07:40 UTC — conclusão integral e correção do contrato de teste

- Integral 038c1b7 finalizou com exit65: 52 XCTest +1.527 Swift Testing +197 UI PASS e um UI FAIL (contrato antigo da escala). Resumo oficial:1.776 PASS/1 FAIL/0skip; a contagem por configuração inclui invocações parametrizadas adicionais e não deve substituir totalTestCount1.777. Resultado preservado, sem alegação de GREEN.
- Patch somente em Prompt14AccessibilityUITests e dois benchmarks aditivos em PremiumPerformanceUITests aplicado após a integral e revisado independentemente. Categorias UIKit públicas; navegação cresce atéXXXL regular e permanece limitada nas três categorias AX, enquanto o conteúdo segue crescendo; cinco controles,44pt,viewport e Biblioteca preservados. Build-for-testing PASS,4,802s,zero warning no log. Focado em execução.
- Checagem isolada do onboarding no baseline puro: um caso PASS/exit0,PID78501 e binários confirmados, um warning exato no XCTest, nenhum processo residual. O parser da coleta nativa falhou no formato do timezone; evidência original preservada para reanálise offline, sem repetir o teste. Não extrapolar para causa do warning do Flow.
- Leitura devicectl: iPhone físico13ProMax pareado e disponível; instalação ainda não realizada.


### 02/10/2026 07:50 UTC — escala GREEN e diagnóstico do benchmark adicional

- Escala da marca:1PASS/0FAIL/0skip,143,454s,6 capturas: L, XXL, XXXL, AccessibilityXL, AccessibilityXXL e AccessibilityXXXL. Revisão independente dos resultados e fonte aplicada concluída; sem alegar revisão nova de pixels.
- Nav/sheet rodada1: Navigation falhou antes de medir porque o helper exigia today.refresh abaixo do header; o botão pertence ao toolbar. Sheet PASS,n5. Patch corrigiu posição mantendo44pt/usabilidade e foi revisado. Rodada2 ainda falhou na contenção estrita do botão no header, também antes de medir; Sheet PASS novamente. Ambos pares preservados como falhos, sem before nem deltas aprovados.
- Diagnóstico isolado, assertivas intactas: header y62/h54; refresh y61,666666666666664/h45,00000000000001/w45. Diferença de um pixel no topo a3x. Window/remaining/bar também capturados junto à árvore e imagem. Próxima correção limitada ao arredondamento documentado, em revisão; não ampliar timeout nem remover44pt.
- Suplemento nativo confirma Fault do onboarding baseline PID78501/UUID do before,07:36:20.671208UTC. Parser4/4PASS após normalização do offset; originais preservados. Lookup do primeiro frame do aviso Flow no mesmo módulo UUID resolve _FrameLayout.init(...)+400, sem dimensão/view/linha causal. Debugger desacoplado, app/parsers de logs encerrados e defaults26restaurados antes do novo benchmark.


### 02/10/2026 08:03 UTC — novo par de performance concluído e integral final iniciada

- Par navigation-sheets-v3:2PASS/0FAIL/0skip por lado; cinco amostras oficiais por métrica. Mesmos apps congelados do v2, novo runner comum; oito snapshots por lado, MATCHED_RECORDED_CONDITIONS. After07:53:14–07:57:01, before07:57:01–08:01:23UTC.
- Ciclo das cinco abas:18,7293376494→14,0782285972s(−24,833%). Sheet de refeição:2,6595815056→2,605758239s(−2,024%). São tempos observados por XCTest, incluem gesto/idle/AX, não animação/FPS/TTID. Sem agregação aos cinco cenários prévios nem atribuição causal com um único par. Métricas/JSONs preservados em navigation-sheet-metrics-v3.
- Revisões independentes dos patches concluídas; brand focused1PASS/0skip e os dois benchmarks passaram. Commit local3e9dde8d54194999adeb067ed6ab9901016909d7, somente dois arquivos UITests,18commits locais. Produto308arquivos revalidado byte-idêntico ao build Release ebf64a9. Sem push/merge/deploy.
- Seis imagens do focused exportadas sem edição. ROOT inspecionou L e AccessibilityXXXL: rótulos da barra legíveis, card731inteiro e conteúdo ampliado; isso não é aceite físico.
- RESOURCE GATE:PASS:49GiB livres/39%memoryfree/10CPUs. Swap20.066,5MiB é uma amostra, sem tendência medida; não gerou bloqueio artificial. Nenhum workload concorrente.
- Integral final sem filtros em HEAD3e9dde8 iniciada08:03:18.189310UTC,200métodosUI previstos, resultado/log ios27-final-full-suite-3e9dde8. Ainda sem conclusão.


### 02/10/2026 08:20 UTC — integral interrompida após nova falha de geometria

- 3e9:52XCTest+1.527Swift+26UI PASS. Flow testAXCancelActionContainsItsWholeNativeLabelWhilePending falhou antes de enviar, na superfície do campo: maxY622,6667 > keyboard.minY590+1. Fonte/test/helper idênticos038→3e9. Send reportouframe24/630,6667/354/149,333 nas duasrodadas. Não é evidência de truncamento novo do label nem autorização para tolerar32pt.
- ROOT interrompeu somente xcodebuild82179 viaSIGINT08:19:37UTC após verificar comando/resultbundle exatos. Exit75, fim08:19:38; resumo oficial1.605PASS/2FAIL: umFAILdegeometria e testEmptyStateStartsAtReadableContentAtAXXXXL cancelado porROOT. Não considerar integral aprovada.
- Capturas do caso exportadas: filtro *.png não encontrou o anexo nativo porque seu nome sugerido termina em .send; exportar o caso exato sem filtro recuperou a imagem. PASS038 mostra acessórioDone, semQWERTY; FAIL3e9 mostra regiãoverde semlabel/desenhosemteclado/Done, apesar deAXmin590. ROOT+revisão independente concordam quepixels/AX divergem; causa aindaaberta.
- Caso exato semqualquermudança de fonte/config/build em execução isolada, flow-ax-keyboard-exact-unchanged. Probe adicional somente de diagnóstico preparado independentemente se necessário. Instalação bloqueada até fechar gate.


### 02/10/2026 — diagnóstico isolado e fixture temporal

- Isolado sem mudança de fonte/configuração/build terminou08:31:28UTC/exit65. A contenção teclado/campo/Send passou; Cancel falhou após espera60s de quiescência. Esse atraso começou antes de enviar; não atribuído ao spinner nem ao SDK.
- Vídeo local extraído por AVAssetImageGenerator, sem alteração dos pixels:312,385s mostraSending/Cancelwaiting;334,8867s mostraQA_REPLY_VISIBLE/campo vazio/Senddisabled. A consultaCancel foi feita em362s; fixturependingCancellation completa em30s. Evidência distingue defeito temporal da fixture de defeito de cancelamento do produto. Preparação de regressão determinística da fixture em curso.
- Macbloqueado confirmado pela ferramentaCUA. Não houve desbloqueio/bypass; inspeção e instalação físicas continuampendentes. Diagnóstico de contençãoAX/pixels continuaaberto; nenhuma assertiva flexibilizada.
- Preflight privado de artefatos falhou por exigir keychain-access-groups explícitos. Nenhuma conexão/instalação realizada. Revisor está verificando ausência/default/order com documentação pública antes de corrigir o helper. Não representa nova falha da assinatura.


### 02/10/2026 08:47 UTC — prova de transição AX e fixture cancelável

- Probe temporário133,85s/exit0: após foco,35teclas/minY590; antes da contenção, o mesmo nó publica minY918/maxY1144/nonhittable e cerca de1sdepois retorna minY590/maxY816/hittable. Campo/Send se mantiveram em posições coerentes na leitura final. Queries sequenciais não atômicas; instrumentação afeta timing e esse PASS não substitui regressão sem probe. Patch removido após extração.
- Fixture30s caracterizada com relógio virtual:RED5PASS/1FAIL, sem skips. Espera de pendingCancellation alterada somente no DEBUG para não ter deadline e terminar por cancelamento da task; cenários comuns continuam2s. GREEN6PASS/0FAIL/0skip. Revisão independente do desenho concluída; revisão do difffinal em curso, sem commit ainda.
- Preflight local corrigido e revisado: ausência de keychain-access-groups é válida e comparada nos dois artefatos; grupos explícitos preservam ordem. Oito testes offline passaram e execução integral dohelper ROOT passou. Assinaturas, identidade, device do perfil, validade e bytehash dos artefatos conferidos; nenhuma conexão/instalação no iPhone. Artefato Release existente preservado.


### 02/10/2026 08:54 UTC — fixture integrada localmente

- Seis testes de preview GREEN e2UIvizinhos PASS/zero skips; cenário de Cancel/reabrir117,221s e preservação B após Cancel aprovados. Revisão independente do diff real sem bloqueadores. Commit6978f65251e7a0fe7eef723147bf9c72a1ed7b20,19commitslocais,sempush/merge.
- Somente fonteDEBUG+testes; artefatoReleasecongelado permanece o anterior e nãofoiinstalado. Hashintegraldaárvore308arquivoséhistórico até3e9, nãoreapresentarcomohashatual apósestaediçãoDEBUG. GateAXcomreadiness e integral aindaabertos.


### 02/10/2026 09:01 UTC — readiness Flow aprovado no cenário após QA

- Caracterização puraRED0PASS/3FAIL → GREEN3PASS/0FAIL; tecladooffscreen918, stalecomposer622,667vskeyboard590, overlapSend520vsDone500 todos rejeitados. Guardvalidageometrias eaguarda amostrasidênticas250ms/expectativa8s; rereadfinalobrigatório. Assertivasantigasbyte-idênticas; sócasoAXapósQAusahelper.
- UIexata semprobePASS124,858s/zero skips, fixturependingatéCancel. RasterCancelwaitinginteiroconferidoROOT; geometrysettledSendmax452/Done500/keyboard590. Revisãoindependentedohelperantescommit591d72772f784b7bc12ffe6dfe97f07bd6161304,20commitslocais. SemalterarprodutoRelease.
- Achadoprétypingpersisteaberto: doisrasters/tuplascomprovamSenddisabled520/Done500interseção47×20pt. Campo64+padding32 ebotão149,33mantêmtamanho; blocosemove68pt apósQA. Inferênciaanteriorplaceholder132ptfoirefutada; nãoécausa. ExtensãoAXdoancestor nãoémedidaGeometryReader. PreparandocasoUIvazioeprobegeométricotemporárioparacaracterizarsemfontefixespeculativa.

### Campo vazio do Flow: caracterização da fronteira do teclado

- `flow-empty-keyboard-exact-characterization.xcresult`: 0 PASS/1 FAIL, sem digitação; raster confirma Send sobre Done em inglês/AccessibilityXXXL. O último snapshot AX tem window/header/Done inválidos e não é usado sozinho como prova de causa.
- `flow-empty-keyboard-layout-probe-measurements.json`: 15 eventos do PID90281. No último par, viewport e compositor terminam em532pt, enquanto o teclado notificado começa498pt; o compositor mantém277,333pt e cabe na proposta final416pt. Há overflow transitório22,667pt antes do estado final, distinto da sobreposição persistente. A origem da diferença34pt na contabilidade ancestral não foi atribuída ao SDK, home indicator ou ao Mac bloqueado.
- A instrumentação temporária foi preservada em `flow-final-diagnostic-tools` e removida antes das tentativas de correção. `flow-empty-keyboard-inset-candidate.xcresult`: 0 PASS/1 FAIL; mover o dock inteiro para safeAreaInset não resolveu. Patch rejeitado preservado, produto revertido à composição anterior.
- Correção residual em verificação: UIKeyboardLayoutGuide público, `usesBottomSafeArea=false`, `followsUndockedKeyboard=false`; observador ocupa viewport externo e somente o conteúdo interno recebe a interseção residual. Sem padding constante ou aplicação repetida da altura completa do teclado. Foco, texto, fórmulas de scroll e modelos permanecem iguais.
- RED geométrico: `flow-keyboard-clearance-red2`, 4 PASS/4 FAIL; a primeira tentativa falhou por ambiguidade CGFloat.nan no teste, corrigida antes do RED comportamental. RED de entrega: `flow-keyboard-delivery-red`, 1 PASS/4 FAIL; scheduler determinístico comprova descarte de amostras antigas/invalidadas e deduplicação. GREEN candidato e cenário UI estão em execução; não representam aprovação antecipada.

### Correção residual por notificação: primeiro GREEN e revisão

- O candidato com UIKeyboardLayoutGuide foi rejeitado. Primeira rodada: 12PASS/2FAIL (CGRect.infinite e UI). Após tratar CGRect.infinite explicitamente, `guide-probe3` teve13unitPASS/1UIFAIL. Seu log nativo completo prova, no mesmo run, bounds locais416, guide final(0,416,0,0), notificação localy382/height376 e window.safeAreaInsets.bottom34. Não há atribuição de causa geral ao SDK.
- Tentativa mínima no AppShell com Color.clear height0 também foi rejeitada: raster ao vivo mantém o overlap; `flow-keyboard-zero-inset-candidate` foi interrompido com SIGINT no PID94120, exit75. Não é um teste concluído/aprovado. AppShell voltou exatamente ao HEAD; tentativas/probes ficaram preservados fora do produto.
- A implementação atual observa willChangeFrame e didHide, conserva a referência de coordenadas original, reconverte em cada layout e aplica apenas a interseção residual ao conteúdo. O UIView observador tem dimensões explícitas do viewport externo, separado do padding. Medidas pendentes são invalidadas por nova amostra, mudança de owner, janela ou desmontagem.
- `flow-keyboard-notification-candidate`: **14PASS/0FAIL/0skip**, sem probe. Send termina486, Done começa500; campo/controles inteiros e hittable. A captura foi inspecionada. O warning Invalid frame dimension permanece no resumo e não foi suprimido.
- Revisão independente exigiu associação da notificação ao UIScreen, compatível com o mínimo18: [willChangeFrame](https://developer.apple.com/documentation/uikit/uiresponder/keyboardwillchangeframenotification) e [didHide](https://developer.apple.com/documentation/uikit/uiresponder/keyboarddidhidenotification). `flow-keyboard-screen-red`:8PASS/2FAIL para origem ausente e frame de A interpretado como B. A proteção foi aplicada no recebimento e na reconversão; os testes usam identidades sintéticas e não equivalem a um monitor externo físico.
- `flow-keyboard-final-focused`:15 testes determinísticos e oito UI em execução. Fonte final congelada durante a execução, sem probes. Revisão final e commit aguardam evidência. Qualquer Release anterior não inclui este diff.

### Flow — resultado da rodada focada final em 2026-10-02 09:59:25 UTC

`flow-keyboard-final-focused`: 21 PASS / 2 FAIL / zero skips, exit65, fontes preservadas durante a execução. Geometria/origem de tela/entrega assíncrona: 15/15 PASS. Seis cenários UI passaram, incluindo campo vazio, cancelamento AX, A/B, leitura entre abas e proposta. O teste com 4.001 caracteres mostrou overflow real no raster (campo acima da navegação e aviso atrás do teclado); o teste de resposta recebida durante leitura histórica perdeu a visibilidade da âncora `qa-seed-35`. Correções e revisão independente pendentes antes de commit. Integral e Release final ainda bloqueados por esses gates.

### Flow — compositor limitado e gesto de leitura

- Raster AX confirmou overflow com 4.001 caracteres. Policy de altura teve RED1PASS/4FAIL antes da implementação. Um único ScrollView persistente contém proposta, divisor, campo, ação e aviso; altura natural limitada ao viewport menos a obstrução residual. Sem cópia do TextField, troca de identidade ou mudança de scrolllogic do histórico.
- O helper UI agora procura a superfície completa acima de Done, e cobre também o aviso inteiro, foco e os4.001 caracteres preservados; não aceita apenas hittability parcial.
- A revisão offline do teste de leitura mostrou âncora35 imóvel quando a resposta chegou e deslocamento posterior à liberação do gesto rápido. A integral038 já tinha grande deslocamento após o gesto. Foi alterada somente a velocidade do gesto para slow, mantendo trajetória, hold3s, fixture2s, identidade35 e todas as assertions. Isso requer nova qualificação visual, sem atribuir bug ao SDK.
- `flow-composer-dock-focused`: os20unitários passaram; oito testes UI em execução. Nenhum commit/Release deste diff ainda.
- CUA confirmou novamente Mac bloqueado; inspeção GUI de Allocations e smoke físico seguem pendentes de desbloqueio manual já solicitado.

### 2026-10-02 10:22:52 UTC — dock: 24 PASS / 4 FAIL

`flow-composer-dock-focused`:20unitários e quatroUI passaram (AXcancel, AX4001 com aviso integral/foco, vazioAX e navegação histórica). Quatro testes normais não iniciaram o envio/proposta. O vídeo de PendingOutbox e o evento nativo mostram Send próximo a(356,758) antes da subida do teclado e próximo a(356,430) ao final; a síntese de toque atravessa a animação. A árvore pósfalha não era coetânea ao toque. Não há ainda atribuição a callback/gesture handling; diagnóstico isolado acrescenta somente o readiness de teclado existente antes do toque em PendingOutbox. Sem mudança de produto nessa contraprova e sem enfraquecer assertions.


### 2026-10-02 10:44–10:46 UTC — readiness normal e sonda limitada

- `flow-dock-send-readiness-characterization`: 1 PASS / 0 FAIL / 0 skip; o cenário A → B → cancelar → Concluído preservou o rascunho B, a outbox e o aviso de que a operação remota pode continuar. Produto idêntico à rodada 24/4; acrescentada somente a precondição de geometria estável antes de Enviar. Duração nativa 963,008 s, com repetidas esperas de 60 s por idle: aprovação funcional isolada, sem aprovação de desempenho ou da integral com limite de 600 s.
- `flow-dock-layout-churn-probe`: sonda DEBUG temporária e teste preservando a sessão QA; 1 PASS, 17,878 s, sem as esperas de 60 s. Treze eventos, uma atribuição da altura natural (78,33333333333333 pt), mudanças de viewport/residual durante teclado; não atingiu o teto de 30 eventos. Não reproduziu churn natural nesta janela. Contexto diferente (sessão já preparada) e instrumentação impedem inferir melhora de performance ou causa da espera anterior.
- Sonda e teste temporário retirados byte-exatamente, evidência preservada fora do repositório em `flow-final-diagnostic-tools/dock-probe-restoration.json`. Nenhuma quantização ou alteração especulativa de produto aplicada.
- Harness compartilha o readiness existente entre Flow e proposta de Plano, sem alterar assertivas, textos, fixtures, gestos ou limites de 8 s/250 ms. Rodada focada atual em `flow-dock-shared-readiness-focused`; resultado ainda pendente no momento desta anotação.


### 2026-10-02 10:58–11:02 UTC — dock integrado após revisão e GREEN

- `flow-dock-shared-readiness-focused`: **9 PASS / 0 FAIL / 0 skip**, exit0, fontes estáveis; seis UI e três casos determinísticos de readiness. UI: cancelar/reabrir124,035s; 50mensagens80,607s; resposta durante leitura25,084s; retry28,054s; A/B28,730s; proposta20,330s. Não houve aviso de espera de animação de60s nessa execução. Isso não identifica a causa do run963s nem substitui benchmark.
- Os seis cenários preservam suas assertivas. Raster de `qa-seed-35` permanece legível depois da resposta; posiçãoY130,394→285,728 após gesto nativo169,083 e redução do viewport676,333→624. O rascunhoB continua no campo com teclado após cancelamento; Done retorna a barra. Capturas exportadas em `flow-dock-shared-readiness-focused-attachments` e inspecionadas.
- Produto validado no focado anterior por20unitários e quatroUI AX/histórico; junto ao foco atual cobre os casos que tinham falhado. Scanner unitário repetido:21PASS/0FAIL/0skip. O warning nativo de frame continua preservado (seis ocorrências no resumo atual), sem causa atribuída ou supressão.
- Revisão independente atualizada (incluindo revisão separada das partes propostas pelo primeiro revisor), hashes revalidados antes do commit; nenhum achado concretoP1/P2/P3. Manifesto `flow-final-diagnostic-tools/performe-flow-dock-current-review-manifest.json`.
- Commit local **5b123d08fbe81f78a8d0cfc781c1a6f303411a19**, oito arquivos de produto/testes; **21 commits locais** desde5d9429f. Sem push/merge/distribuição. Source310arquivos do produto, hashe384da4ec10fcb2319df65272323db42054a079d18a49fbe38010c2cc85f0913.
- Novo grupo Release/analyze/build-for-testing iniciado em `release-gates-flow-dock-5b123d0`, reaproveitando derivados locais. ResourcegatePASS para uma execuçãojobs2:46GiB livres/43%memória livre; swap21.245,44MiB é leitura única, não tendência. Build-for-testing toca somente mtime de FlowChatView para guardar a linha real de compiladorDebug, sem mudar bytes. Smoke físico continua dependente de acesso ao Mac; `getApp(Instruments)` ainda retornou Macbloqueado.


### 2026-10-02 — builds do dock e escopo do scanner

- Release simulador PASS 39,481 s; Analyze PASS 3,286 s (zero warnings/findings); Release staging PASS 34,188 s; build-for-testing Debug PASS 7,467 s (zero warnings). As assinaturas estritas, bundle/team, Keychain e perfil do aparelho foram revalidados; rollback preservado. `release-gates-flow-dock-5b123d0/manifest.json` e `physical-artifacts-readonly-preflight-5b123d0.json` registram os resultados. Nenhuma instalação.
- Cada Release registra um warning antigo de `await` em SessionLifecycleCoordinator. O texto nativo “command failed with exit code 0 but produced no further output” também aparece nos dois logs anteriores; o resumo oficial do Xcode desta rodada indica succeeded/zero erros. Não foi ocultado nem contado como uma nova falha de compilação.
- Scanner do simulador PASS: 844 chaves, 1.688 valores, zero falhas/leaks. A chamada adicional ao staging resultou em **UNEXPECTED_BUNDLE_IDENTIFIER**, pois o contrato atual fixa `com.bodyflow.app`; staging assinado tem `com.performeai.app.dev.k6942zjtv6`. O gate continua aberto até tratamento explícito do identificador esperado. A contagem 15/16 de assets não é falha: o scanner já permite omitir appiconset não selecionado. Assets.car antigo/novo do staging byte-idênticos, e PerformeAIAppIconV1 continua declarado como principal.
- O novo par `performance-pair-ios27-flow-dock` foi preparado com baseline/runner v2 congelados e app Debug do commit 5b123d0; dois workloads, ordem before → after. A execução serial está em andamento. Não reutilizar os números do candidato antigo como performance do dock novo.


### 2026-10-02 — par Flow com runner v2 não qualificou o candidato

`performance-pair-ios27-flow-dock`: baseline2PASS; candidato1PASS/1FAIL. O cenário de50mensagens falhou no setup, exchange0, sem detectar pending/completed; resposta longa passou. A execução termina exit65 e não produz comparação aceita. O runner v2 congelado só verificava Enviar habilitado, sem readiness geométrico. Preservados ambos os xcresults, apps/runner, snapshots de condições e vídeo/eventos de falha. Diagnóstico e ajuste do setup compartilhado estão em andamento; métricas/gestos/carga/fixture permanecem protegidos. Não chamar isso de regressão medida de desempenho.


### 2026-10-02 11:41–11:44 UTC — identidade explícita do scanner

- RED oficial: 2 PASS / 2 FAIL / zero skips; falhas esperadas ao pedir staging explícito pela API/CLI, mantendo recusa pelo default e por identidade divergente.
- GREEN: **25 PASS / zero FAIL / zero skips**. `--expected-bundle-id` compara igualdade exata e registra o esperado, mantendo default `com.bodyflow.app`; nenhuma inspeção de assets, localização, leaks ou fixtures foi removida. A fixture CLI usa uma cópia do scanner na raiz sintética, invocada pelo caminho canônico.
- Scans dos dois artefatos reais, com seus IDs explícitos: PASS, 844 chaves / 1.688 valores / zero falhas. JSON FAIL original preservado. Revisão independente dos hashes antes do commit local **306ecbf442c704acd7b8103bc648c75d839f157c**; 22 commits locais desde o início. Somente scanner/testes, sem mudança de binário iOS, API ou WhatsApp.
- Readiness do benchmark: RED oficial `benchmark-keyboard-accessory-red` terminou 11:43:31 UTC com 7 PASS / 2 FAIL / zero skips. A ausência de Done é rejeitada pelo contrato atual; o baseline puro não possui esse acessório. O GREEN permitirá essa ausência apenas por opção explícita do benchmark, continuando a verificar Done quando presente. Nenhuma janela de medição será alterada; ambos os lados exigirão o mesmo novo runner.


### 2026-10-02 — transferência para Claude Code a pedido de Eduardo

- Eduardo solicitou preservação de todo o contexto por limite de tokens e acrescentou **tutorial inicial guiado** como última implementação funcional. Tutorial ainda não implementado; especificação própria registrada. Integral final/Release/smoke devem incluir a feature, evitando validar candidato final antes dela.
- Último commit técnico306ecbf, produto5b123d0; 22 commits locais. Único diff técnico aberto: RED de readiness do benchmark em FlowChatUITests.swift (7 PASS/2 FAIL). GREEN preparado e validado por `git apply --check`, não aplicado nem executado; patch preservado com hash.
- Novo preparador/analisador de benchmark preservados junto ao runbook. Sem novo build, teste, captura Instruments, chamada de backend ou instalação durante o handoff. Produto e métricas medidos não foram alterados.
- Patches, manifestos, revisão de cobertura e anexos originais copiados byte a byte de /tmp/attachments para `~/.local/share/performe-ai/final-polish-20261001/claude-code-handoff-20261002`, com inventário SHA-256; helpers também em flow-final-diagnostic-tools para os comandos do runbook. A primeira tentativa de inventário encontrou diretório no glob e parou antes de copiar; repetição restringiu a arquivos regulares, sem perda/substituição.
- Skill context-save usada como estrutura; launcher gstack-skill-start não está no caminho esperado de Claude. Registro manual em docs é suficiente para esta retomada; eventual reparo `gstack-upgrade`/setup é separado e não bloqueia o handoff. Nenhuma memória global foi alterada.
- Revisão independente dos documentos e validação de links/hashes/diff antes do checkpoint documental. Gates de produção/clientes continuam abertos conforme relatório.

- Fechamento de runtime da passagem: iOS27 da tarefa restaurado a Shutdown em02/10 12:06:20 UTC, exit0, sem job Xcode/Instruments/UI runner ativo.26.5 permaneceu Booted, compacto Shutdown; app no26.5 e iPhone físico intocados. Manifesto `claude-code-handoff-20261002/simulator-closeout.json`.
