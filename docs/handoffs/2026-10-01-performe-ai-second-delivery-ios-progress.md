# Performe AI — segunda entrega iOS, progresso em 2026-10-01

## Escopo e estado

- Continuação da operação definida em `2026-09-30-performe-ai-beta-handoff-to-codex.md` e no addendum de escopo da segunda entrega.
- Checkout local no Mac, branch `codex/performe-ai-client-beta-flow-v1`. HEAD inicial `dc5854f4731396631501668d98e9bcf2e7c5ba53`; HEAD local atual antes deste registro: `98c9956bc098f57968b05f5076aeb3a9cfd621f2`.
- Commits locais desta continuação: `1c054e9` e `cb0982f` (escopo), `b5df45d` (rótulos iOS), `98c9956` (sessão preservada no teste Flow). Sem push, PR, merge, TestFlight, loja ou Production.
- Nenhum arquivo de `packages/agent` ou integração WhatsApp foi alterado. Impacto no WhatsApp: nenhum identificado.

## Evidência funcional e privacidade

- Rascunho de dieta do Flow gerado anteriormente continua em **Para revisar** no iPhone: 3.102 kcal e 207,9 g de proteína versus metas 3.361 kcal e 186,1 g. Revisão abriu; o plano não foi confirmado nem ativado.
- Câmera física: foto sintética de refeição capturada pelo usuário, enviada e processada no Supabase staging `xitugspwfxkcluxvrdeg`. O app apresentou revisão dos alimentos e exigiu confirmação dos itens estimados. Consulta somente leitura confirmou bucket `meal-photos` privado, objeto presente, ativo processado, 1.178.984 bytes, retenção até 2026-10-30. Não houve novo `meal_logs` nem `pending_registrations` após essa foto.
- Uma gravação de 1:05 permanece parada na tela local do iPhone. Seu conteúdo não foi confirmado pelo usuário; **não foi enviada**. O espelhamento ficou indisponível porque o Mac está bloqueado. Aguardar confirmação de que contém apenas a frase sintética de QA, ou descartá-la e gravar outra.
- A conexão Supabase staging funciona para `list_migrations` e SQL somente leitura. `get_project` retorna `NotFound` para o ref da branch, comportamento já registrado anteriormente; não é evidência de falta de acesso. Não usar o projeto Body Flow de produção como substituto.
- BFF Preview atual respondeu 401 `missing_access_token` em `/api/mobile/v1/me` sem token. Isto prova disponibilidade básica, não smoke autenticado.

## Correções e gates locais

- O iOS agora exibe o objetivo conhecido `ganho_massa` com rótulo localizado em Hoje e `full_body` como **Corpo inteiro** na revisão de plano. Ambos foram reproduzidos e cobertos por testes exatos antes da correção. Commit `b5df45d`.
- O helper de UI Flow preserva o estado autenticado mesmo com argumento adicional de movimento reduzido. O teste exato falhou antes e passou isoladamente depois; commit `98c9956`.
- No HEAD `98c9956`: 34 XCTest + 1.472 Swift Testing passaram; Release staging compilou; `codesign --verify --deep --strict` passou; `xcodebuild analyze` passou; scanner de marca sem erro e 26 testes do scanner passaram. Bundle, URL Preview, ref staging, chave publicável configurada, equipe e iPhone provisionado foram conferidos sem imprimir valores secretos. O perfil expira em 2026-10-04. O build **não foi instalado** sobre o app físico, para preservar a gravação local pendente.
- Um patch **não commitado** em `FlowChatPreviewSupport.swift` e `FlowChatUITests.swift` adiciona cenário de QA com resposta cancelável de 30 s para dois testes de cancelamento. Os 4 testes unitários da fixture passaram, mas dois testes de UI ficaram presos no onboarding do simulador antes de alcançar o cancelamento. Não considerar o patch validado nem commitá-lo sem QA de UI.

## Regressão UI, classificação atual

- Execução monolítica no Pro Max: 13 casos passaram, 2 falharam em seleção de Perfil e fechamento de sheet; ambos passaram isoladamente depois. O teste de cadastro ficou sem progresso no campo de senha por mais de 8 minutos, e a execução foi encerrada.
- `Prompt14AccessibilityUITests` no Pro Max: 12/13 passaram. `testAccessibilityXXXLEvidence` falhou exatamente na exigência de que `library.selection.all` esteja totalmente acima do viewport (`maxY 148,3` > `viewport.minY 116`). Categoria e primeiro cartão passaram nas verificações de visibilidade. O mesmo teste passou no iPhone 17 no HEAD `98c9956`. O handoff exige autorização específica do Eduardo antes de alterar essa premissa; pergunta enviada, resposta pendente.
- Lote por classes: `PlanDraftUITests` 4/4; `MealCaptureUITests` 3/3; `Prompt13RegistrationUITests` 22/22; `PremiumRegistrationUITests` 3/3; `LocalRemindersUITests` 4/4; `PremiumAuthOnboardingUITests` 3/3; `PremiumContentProfileUITests` 4/4; `PremiumConvergenceUITests` 4/4.
- `FlowChatUITests` 11/12: o botão `flow.cancel` existia após envio, mas desapareceu durante snapshot AX/tap porque a fixture respondia em 2 s. O patch não commitado torna somente os cenários de cancelamento mais longos; UI ainda não verificada.
- `Prompt13TodayUITests`: runner saiu antes de iniciar qualquer teste (0 executados). `PremiumCoreSurfacesUITests`: 6/9, com três falhas ao localizar abas após troca de tema/idioma; exigem repetição isolada antes de atribuição ao app.
- `PremiumPerformanceUITests`: runner registrou `Timed out while loading Accessibility`; Xcode permaneceu sem progresso por mais de 50 minutos. O processo de teste foi encerrado. Tentativa posterior de UI focada no Pro Max e no iPhone 17 também ficou presa no onboarding. O Mac foi observado bloqueado depois; não está comprovado quando o bloqueio começou ou se explica todas as falhas.
- **REGRESSION STATUS: PARTIALLY VERIFIED.** A suíte UI canônica completa do HEAD final não passou.

## Próxima retomada

1. Usuário desbloquear o Mac e confirmar o conteúdo da gravação local ou autorizar descartá-la. Até então, não enviar áudio.
2. Finalizar áudio físico, plano sintético por foto, smoke integrado QA A/B, instalação do Release atual por cima do app de QA e teste do novo rótulo no iPhone. Não confirmar o rascunho de dieta só para provar o fluxo.
3. Repetir UI focada do patch de cancelamento em simulador responsivo. Só após aprovação, revisar diff e fazer commit local. Repetir gates relevantes no HEAD final.
4. Aguardar decisão específica sobre o teste AXXXL. Se autorizada, corrigir a premissa sem enfraquecer visibilidade/sobreposição e validar em dois tamanhos de aparelho.
5. Executar regressão UI restante de modo confiável; classificar as falhas de Perfil, sheet e CoreSurfaces com evidência isolada. Biblioteca editorial vem depois dos fluxos principais; Roberto publica, Eduardo faz aceite visual final.

Produção não foi alterada. Nenhum novo ambiente pago foi criado. O Preview e a branch staging preexistentes continuam necessários ao beta; sua remoção depende de verificação posterior de uso e estado no provedor.

## Atualização de 2026-10-01, 08:52–09:27 BRT

- Eduardo autorizou corrigir a premissa AXXXL. O teste `testAccessibilityXXXLEvidence` foi ajustado para exigir que o seletor anterior termine antes da categoria e que o texto anterior fique fora do viewport visível. Categoria e primeiro cartão continuam exigidos por inteiro, clicáveis e sem sobreposição com as barras. O caso passou no Pro Max e no iPhone 17. Commit local `bcd7d91`.
- A fixture de cancelamento do Flow ganhou um cenário de resposta pendente por 30 segundos, só em DEBUG, sem mudar o tempo dos demais cenários. Os dois testes UI exatos de cancelamento passaram no Pro Max. Commit local `8096d3e`.
- No HEAD `bcd7d91`, a suíte unitária passou: 34 XCTest e 1.472 Swift Testing, zero falhas. A regressão UI canônica completa ainda não passou no HEAD final.
- O build Release staging já assinado foi instalado **por cima** no iPhone físico, sem apagar o app. A sessão QA A permaneceu. Hoje exibiu `Ganho de massa`; a revisão de treino exibiu `Corpo inteiro`. A sugestão de dieta continuou em `Para revisar`, abriu e mostrou meta de 3.361 kcal e 186,1 g de proteína; não foi confirmada.
- A gravação local anterior de 1:05 não reapareceu após reabrir o app; nada foi enviado. Eduardo confirmou que ela continha apenas a frase sintética. Foi solicitado que gravasse novamente a mesma frase e deixasse a tela parada antes de `Usar gravação`. Não classificar áudio físico como verificado até observar upload, transcrição e revisão.
- Sem push, PR, merge, TestFlight, loja ou Production. Arquivos `packages/agent` e integração WhatsApp continuam sem alteração nesta rodada; impacto no WhatsApp: nenhum identificado. Nenhum recurso pago novo foi criado.
- `Prompt13TodayUITests` passou 11/11 no HEAD atual. Os três casos de `PremiumCoreSurfacesUITests` que haviam falhado no lote longo (`testProgressMissingValuesAreNotZeroAndNoRangeSelector`, `testPlanThemeAndLocaleMatrix`, `testProgressThemeAndLocaleMatrix`) passaram isolados. Isto classifica a falha anterior como dependente da execução em lote, sem provar a suíte canônica integral.
- `PremiumPerformanceUITests` teve 2 casos aprovados antes do limite de 240 s do lote; os 2 restantes passaram juntos em uma segunda execução. Quatro casos passaram no total, mas a classe não terminou em um único lote.
- Ao iniciar gravação via espelhamento, o macOS exibiu literalmente `O microfone do iPhone não está disponível pelo Mac.` A gravação de 19 segundos foi parada, sem upload, porque a presença da frase não podia ser garantida. Eduardo foi orientado a usar o microfone físico do iPhone para uma nova gravação sintética e deixar a tela antes de `Usar gravação`.
- O lote `FlowChatUITests` passou 10 casos sem falhas antes de atingir o limite de 600 s durante a matriz visual escura. A matriz escura passou em lote separado e a clara passou isoladamente após o limite do lote conjunto. Assim, os 12 casos da classe passaram no HEAD atual, distribuídos em três execuções; a classe não terminou em uma única execução.
