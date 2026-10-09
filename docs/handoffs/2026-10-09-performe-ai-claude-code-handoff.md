# Performe AI — continuação no Claude Code (2026-10-09)

## 1. Situação e objetivo

Continuar no mesmo Mac e checkout, sem repetir grupos locais já encerrados. Eduardo autorizou pausar o Codex ao entregar este handoff. A meta continua sendo **entregar o app completo e funcional para Roberto testar**, incluindo os protocolos, o refinamento iOS e o tutorial guiado. **Roberto ainda NÃO está liberado para testar o candidato final.**

O último commit técnico é `0b9986f37e913f7f6e7e9149a15f9b1c9ea29fb1`. O commit seguinte deste handoff altera somente documentação. O HEAD final, a pausa e a verificação da transferência ficam em `SESSION-STATE.json` no pacote externo abaixo, evitando um hash autorreferente neste documento. Android continua adiado para a entrega final; não iniciar Android nesta operação. Pagamentos, HealthKit/Health Connect, ranking e gamificação avançada não entram automaticamente no refinamento iOS.

### Caminhos exatos

| Nome usado aqui | Caminho absoluto |
|---|---|
| R — checkout | `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1` |
| B — evidências da operação | `/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001` |
| E — evidências recentes | `/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3` |
| H — handoff anterior | `/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/handoff-20261004/codex-handoff-20261007` |
| M — plano dos protocolos | `/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/handoff-20261004/method-backlog` |
| T — pacote desta transferência | `/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/claude-code-handoff-20261009` |

Host verificado: `MacBook-Air-de-Eduardo.local`, Darwin, usuário `eduardohenrique`, **LOCAL_DEVELOPMENT**. `CODEX_HOME` estava indefinido; efetivo `/Users/eduardohenrique/.codex`. Branch `codex/performe-ai-client-beta-flow-v1`. Checkout limpo no início da transferência. Este filesystem não representa uma publicação no staging ou na produção. Revalidar o estado antes de alterar algo.

## 2. Leitura e precedência

1. Ler integralmente `R/CLAUDE.md`, este documento e `T/SESSION-STATE.json`.
2. Ler `H/HANDOFF.md` e `H/e3-brief.js` para as regras e o contexto histórico. **A seção 4 antiga mandando começar E3 já foi superada**: o cadastro E3 e o Perfil “Seu objetivo” já existem. Não reiniciar esse trabalho.
3. Ler `H/CODEX-CHECKPOINT-ATUAL-20261008.md`, principalmente §§32–35 e os complementos mais recentes; `E/codex-e3-ledger-20261007.md` preserva a cronologia.
4. Para os protocolos, ler `M/plan-v1.json`, `M/decisions-v1.md`, `E/codex-protocolos-execucao-20261008.json` e `H/PROPOSTA-44-RECONCILIADA-20261008.md`/`.json`. O registro de execução indica evidências; “NOT_YET_VERIFIED” não significa que o recurso inexiste.
5. Antes de fórmulas, ler `R/docs/CALCULO-MPP.md` e os testes correspondentes. Antes de C11 nativo, ler o README/plano/manifesto e a revisão R4 indicados na seção 5.

O pacote T guarda cópias de referência, o candidato privado R4 e um manifesto com hashes. As referências originais permanecem no Mac. `python3 T/verification/verify-handoff.py` confere o pacote e os pins, sem executar código de produto. Não usar handoffs antigos como fila atual: seus HEADs, estados de testes e builds em andamento são registros históricos.

## 3. Limites e autorizações que continuam valendo

- **Somente commits locais**, com caminhos explícitos; nunca `git add -A`. Sem push, PR, merge remoto, tags ou publicação nesta continuação sem OK específico de Eduardo. A política global de autonomia não revoga essa restrição específica desta operação.
- Nada de `scripts/deploy.sh`: publica a produção antiga e sincroniza inclusive funções de WhatsApp. Não executar.
- **Produção antiga proibida**, inclusive leitura sem autorização nomeando o alvo: Supabase `xuxehkhdvjivitduarvb`, Vercel `agentempp` / `agentempp.vercel.app`.
- Staging existente: Supabase `xitugspwfxkcluxvrdeg`, BFF e worker em Vercel Preview. Escrita, migration ou publicação exigem OK específico. A autorização anterior foi para **ler seis regras de linguagem e três configurações de cálculo**, não para alterar o projeto. Essas leituras já foram realizadas; `E/codex-staging-authorized-read-success-20261008.json` registra o resultado histórico.
- Uma operação pesada por vez; **um xcodebuild por vez**. Não contornar assinatura com `CODE_SIGNING_ALLOWED=NO`. Verificar recursos antes de build grande, sem loop de espera por métricas perfeitas. No último levantamento havia aproximadamente 11 GiB livres; reavaliar antes dos próximos bundles grandes.
- Não criar infraestrutura paga, dependências, branch ou worktree novo apenas por conveniência. Reutilizar este checkout; um único escritor. Revisores trabalham somente em leitura ou candidatos privados fora do checkout.
- Não usar reset/clean/stash/checkout/restore para descartar trabalho; preservar patches, REDs, manifests, logs e clusters fechados. Não remover worktrees de outras tarefas.
- **Todo bug relatado vira teste com o cenário exato**. Não usar erro de import/compilação como RED causal, não enfraquecer assertions, pular testes, elevar timeout ou repetir até ficar verde.
- Revisão adversarial independente antes de **cada commit**; corrigir críticos/altos/médios antes de commitar. Rodapé do próprio agente, sem se passar pelo autor anterior.
- As 22 linhas `> RC E` em `docs/CALCULO-MPP.md` §10 e `packages/agent/src/__golden__/audit-10-07-signup-eligibility.test.ts` permanecem idênticas e na mesma ordem. Não ocultar pendências clínicas.
- Nunca guardar/exibir secrets, `.env`, senhas, tokens, URLs assinadas ou chat pessoal em relatórios/commits. Não pedir credenciais no chat. Respeitar a regra vigente do handoff anterior para entrada de senha no aparelho; autorizações de mirroring e credenciais não equivalem a autorização de publicação.
- iPhone: instalação por cima do staging existente, nunca desinstalação; não contornar bloqueio do aparelho/Mac. Não registrar ações editoriais ou aceites em nome de Eduardo/Roberto.
- Produto público: **Performe AI / Flow**. BodyFlow é identidade técnica interna; MPP é o método. Não renomear internamente nem mostrar esses nomes internos ao usuário.
- WhatsApp está encerrado como produto; código legado permanece no motor compartilhado. Não acionar/evoluir/apagar. **Avisar Eduardo antes de uma alteração afetar comportamento compartilhado/WhatsApp**. M5 teve opt-in mobile e preservou defaults legados; o aviso correspondente já foi dado. Este handoff não altera WhatsApp.
- Falar com Eduardo em português, curto e direto. Executar o que já está autorizado; perguntar somente por decisão material, acesso ausente ou aprovação específica realmente necessária.

## 4. Trabalho fechado localmente — conservar e não refazer

| Grupo | Estado e evidência |
|---|---|
| Base E1/E2/E4 + E3 iOS + Perfil | Elegibilidade e objetivo no cadastro, mensagem de entrada e leitura no Perfil já implementados. Handoff antigo e ledger mostram a história; não começar novamente pela E3. Publicação/QA final são gates distintos. |
| C1–C9 | Existem nove grupos locais com verificação parcial no registro de 63 pacotes. C1 `e50f984`, C2 `81e3e68`, C5 base `89848c5`; consultar evidências por pacote, sem declarar protocolos completos. C3/C4, cartões C6, resposta C7 e prompts C9 preservados. |
| C5, fases privadas | MAX/perdas/corrupções, bridge, cache, ACL/writer, scan-lock/performance, CAS, complements do handler, histórico de 50, geração/reset e erros reais de RPC já encerrados no escopo local. Não repetir a antiga lista `codex-c5-integrated-remaining-matrix-20261009.md`: ela foi superada pelos receipts finais e §§28–32 do checkpoint. **Seletor público continua inerte**; GoTrue/Next/app/staging integrados ainda não comprovados. |
| C8 — capacidades do Flow | `ea1de9a1f8c3200cc84733ad4ff873a1adf7385a`: 1.259 testes focados PASS, revisão 0C/H/M. Seis famílias atuais anunciadas; cinco indisponíveis permanecem OFF. Modelo real/copy/staging não inferidos. |
| Tutorial guiado / Seu objetivo | `7f9eb174acc0ef099b064b1b156a485851754148`: 106 testes declarados PASS, matriz nova de 16 PASS, 3 métodos UI/6 aberturas reais (4 PT/EN + 2 vazio/offline), revisão 0C/H/M. Tutorial inicial e replay já são produto, não só documentação. Quatro capturas foram inspecionadas pelo Codex; aceite visual humano e matriz final permanecem pendentes. |
| M5 — fechamento/inatividade | `b38ea21ac5ea5c69976dd0ac6ca3e66545c7d6dc`: REDs exatos Tokyo→Honolulu e descoberta vazia/streak; focused 74, agent 4.771, admin 1.770, parity worker 34 PASS. 13 cenários PostgreSQL reais, locks/relógio/ACL. Revisões 0C/H/M; cluster PID51944 fechado e quatro tabelas zeradas. Defaults legados e fórmulas preservados. Snapshot preparatório continua fora da transação final, limitação registrada. |
| C11 — backend refeições confirmadas | `0b9986f37e913f7f6e7e9149a15f9b1c9ea29fb1`: 21 caminhos explícitos, GET/PATCH/DELETE + RPC transacional. Admin **1.888/1.888**, BFF **30/30**, typechecks, Biome focado, build Next, rotas/imports/superfície **51** PASS; revisão final R3 0C/H/M. SQL real funcional/concor­rência/ACL/arredondamento e closeout concluídos. **Só backend local**: C11 completo, staging e iOS não estão verificados. |

Não somar contagens históricas como “total final”. Admin 1.877, BFF 29/30 e freezes dizendo build em andamento são anteriores à correção final; a evidência atual é 1.888 e 30/30. Comentários herdados “SOURCE ONLY/NOT RUN” em testes não substituem o recibo atual de execução do backend.

### Evidências atuais C5

Em E, os agregados finais são `c5-cas-final-evidence-20261009.json`, `c5-handler-final-evidence-20261009.json`, `c5-history50-final-evidence-20261009.json`, `c5-generation-reset-final-evidence-20261009.json` e `c5-rpc-error-final-evidence-20261009.json`. O último cobre SQLSTATE 23514/40001/P0001; o primeiro caso salvo não foi repetido. Estado original de 34 famílias/catálogo/duas mensagens/A1-B0 restaurado e runtime próprio encerrado. Nunca adotar um snapshot parcial histórico como nova baseline.

### Evidências atuais C11 backend

- `E/c11-confirmed-meal-backend-implementation-report-20261009.md`: relatório completo de escopo, testes e limites.
- `E/c11-backend-post-review-commit-closeout-20261009.json`: commit, 21 paths e revisão.
- `E/c11-backend-final-gates-20261009.json`: SHA256 `323cc8473150c4db3869d9a5bf5af78d1a8d09993d5b03c2b52cc172fe4ad9f5`.
- `E/c11-backend-final-source-freeze-r3-20261009.json`: SHA256 `6e011799ccc19fefdd713ebfef7fffebd7945f96b7cf3ed0fef0c85750aa9538`; **21 fontes + 30 evidências MATCH**.
- `E/c11-backend-root-independent-r3-20261009/REVIEW.json`: SHA256 `f6c8a782b0c95ebfc86370f9a3993cb8c1c078138c94da3e14bbf7c7abed1f0e`; 0C/H/M.
- `E/c11-bff-final-green-test-20261009.log`: SHA256 `552d8d08aad213899cebd2281666123c548e4f50b5b829b086cf24492f3f14be`.
- `E/c11-review-findings-exact-red-r2-20261009.json`: 18 total, 12 PASS/6 assertion FAIL; `c11-review-findings-green-20261009.json`: 18 PASS. Calendário do grupo inteiro e identidade do recibo fresco corrigidos; não repetir RED fechado.
- `E/c11-bff-nft-addition-proof-20261009.json`: causa do contador 5.303→5.410 comprovada antes da atualização do teste; 50 rotas originais preservadas, 107 referências da nova rota e só um novo target físico. Guards de worker/admin/catálogo intactos.
- `E/c11-m5-postgres17-20261009/c11-runtime-closeout-20261009.json`: SHA256 `014165d046ecd558d3984e5018c82746ec8dd5a85734ab4d6fe67a85b81f4290`.

Último PostgreSQL próprio: PID68613, porta55490, TCP desligado, socket `/private/tmp/performe-c11-m5-a0_ru_ez`; **CLOSED**, pg_ctl status3, PID/socket/postmaster.pid ausentes. Oito tabelas zeradas, data e evidências preservadas. Não reiniciar apenas para gerar o handoff. Engine cache em `E/c5-portable-postgres17-20261009/engine/bin`; data em `E/c11-m5-postgres17-20261009/data`. Auth.users FK e auth.jwt eram stand-ins explícitos: não é prova de GoTrue/PostgREST, cadeia completa de migrations, cloud ou iPhone.

## 5. Próximo passo exato: C11 nativo R4

### Candidato já preparado

Pasta original: `E/c11-ios-candidate-r4-20261009` (cópia byte a byte em `T/candidate/c11-ios-r4`).

- `manifest.json`: SHA256 **5c800aa6bc4270382e04aac20bdbc4b094e4f76459328458c691bc56b0712654**.
- `FREEZE.sha256`: SHA256 **a87d4ca91dcb30a11f9c5759851800230b47dbd0289d64f906fb7b93b7b8b53a**.
- 16 assets + 40 inputs + manifesto/freeze = **58 pins conferidos**. `SOURCE-PINS.sha256` preserva os inputs.
- Revisão `E/c11-ios-independent-r4-20261009/REVIEW.json`, SHA256 **d06e8f40cb7da394ad33c9dd1f4978cd622c6f8f3d09d379061a867bc8c89fd7**, e `REVIEW.md`: **SOURCE_OK_FOR_NATIVE_TDD**, 0C/H/M/L. Não é COMMIT_OK nem aceite final.
- Seis fontes: MealRecordModels, MobileMealRecordRepository, MealRecordEditDraft, MealRecordModel, MealRecordSessionCapability e MealRecordDetailView.
- Wiring: Idempotency, Prompt14SessionOwner, AppShellView e AppDependencies; usar o **delta `WIRING.patch` conferido contra o checkout**, nunca sobrescrever os quatro arquivos completos por cópias de uma base antiga.
- `Tests/MealRecordCandidateTests.swift`: **27 declarações NÃO EXECUTADAS/NÃO COMPILADAS**, ainda fora do target. Prefixo das 24 R3 preservado, incluindo as 17 R2. README/manifesto de autoria dizendo “revisão pendente” é histórico: o parecer externo R4 acima já existe, mas o runtime nativo continua pendente.

### Regressões da R4 que o runtime precisa comprovar

1. Após excluir um irmão e sobreviver o anchor, reabertura explícita carrega GET fresco e permite nova operação. Render/getter/GET não cria automaticamente uma mutação/chave; recibo e histórico anteriores permanecem.
2. Input170.001g rejeitado422 conserva o formulário, permite correção explícita e só muda a chave quando muda o comando. Unknown/timeout/in-progress conserva body/key e retry da mesma operação.
3. GETV1→V2/revisão, mantendo170.001 ou170.0010, não libera novo envio: comparação dos **campos/items** exclui `expected_version`. Correção explícita170.00 permite nova chave com versão oficialV2.
4. HTTP409 `MEAL_GROUP_LIMIT_EXCEEDED` é `.groupLimitChanged` privado, exige GET bem-sucedido + revisão explícita. GET falho não libera comando. HTTP422 com o mesmo código é `.groupLimitExceeded` e permite corrigir input. Copy PT/EN distinta; nenhum campo público novo.
5. Sessão A→B→A, sequência e ownership impedem publicação tardia; nenhum retry automático de mutação. PATCH de um anchor, irmãos somente leitura, DELETE finito≤30, quantidade/rótulo/NULL oficiais preservados. Não reconstruir kcal antigo como novo override do usuário.

### Ordem operacional autorizada

1. Revalidar HEAD limpo, hashes e revisão R4. Não reexecutar backends/SQL/C5 fechados sem uma alteração nova que crie risco concreto.
2. Mapear os arquivos/targets atuais. Registrar os 27 testes e preparar **scaffold compilável legítimo** para APIs/enum novos; observar RED por assertion na regressão exata contra baseline legítima. Erro de ausência de enum/import/API não conta como reprodução.
3. Aplicar o delta mínimo R4 depois do RED. Executar GREEN nativo e testes vizinhos relevantes de registro pendente, histórico, Today, sessão/ABA, idempotência e transporte. Registrar o que realmente compilou/rodou, sem converter 27 declarações em “27 testes PASS” por leitura de fonte.
4. Conferir DTO com backend, replay/snapshot oficial, apresentação e cópias PT/EN, teclado/estados de erro. Fazer revisão independente do **diff integrado exato** antes do commit local.
5. Prosseguir pelo plano integral da seção 6. C11 nativo sozinho não encerra a entrega.

### Contrato público já fechado no servidor

GET `/api/mobile/v1/meal-records/[id]`, fonte `R/apps/admin/src/lib/mobile-api/confirmed-meal-read.ts`, SHA256 **ea98fb26aa84b880d1982551b4258af2fad6d7db3f22963dae54c2c93acdeed2**.

Campos externos: `record_id, scope, expected_version, item_ids, items, local_date, timezone, day_closed, editable, edit_block_reason`. Campos por item: `id, food_name, quantity_g, kcal, protein_g, carbs_g, fat_g, consumed_at, meal_type, source`. Nulls são fatos oficiais, não converter em zero; sem mídia/raw/owner/user_kcal reconstruído. Versão opaca é produzida pelo servidor sobre contexto/snapshot/grupo completo.

Resposta200 de PATCH/DELETE: `data:{record_id,operation,removed_item_ids,new_item_ids,next_record_id,snapshot:{id,date,calories_consumed,protein_g,carbs_g,fat_g,daily_balance}}`, com `operation` updated/deleted, next_record_id/daily_balance nullable; `meta.api_version/request_id`. Não acrescentar método/status/owner ao envelope. Replay concluído vem do ledger antes de verificar contexto fresco e conserva recibo original; não comparar replay com versão atual. Após sucesso, usar recibo persistido e GET de recuperação, nunca repetir mutação bem-sucedida.

Grupo oficial não nulo usa marcador/owner/snapshot exatos; legado sem marcador usa somente o anchor. Limite30, calendário de **todos** os itens e snapshot atual. Quantidade-only mantém reconciliação oficial/proveniência; alimento/preparo/kcal explícito segue calculadora existente e país oficial confirmado. Pode registrar product_events fora da RPC, limitação documentada. RPC faz CAS/locks/mutação finita/totais/ledger em uma transação; não mexer nas rotas de registro pendente ou no histórico para simular sucesso.

### Comandos nativos existentes, um de cada vez

Usar apenas os helpers atuais para BFT/TWB, com **tag nova**, conferindo antes que log e xcresult não existem; `ios-twb.sh` remove o bundle da tag indicada. Não reutilizar tag e apagar evidência.

    zsh /Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/ios-bft.sh <tag-nova>
    zsh /Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/ios-twb.sh <tag-nova> <spec-real-do-target> [...]

Projeto `R/apps/ios/BodyFlow/BodyFlow.xcodeproj`, scheme BodyFlow, Swift6 strict concurrency. Simulador iPhone18Pro/iOS27 `CE89BD02-DF61-4214-AD61-2A2A51114022`, DerivedData `B/derived`, SourcePackages cacheados. Helpers preservam assinatura e preflight dos produtos. Conferir `pgrep -x xcodebuild`, não `pgrep -f`. Observação de saída/exit e xcresult obrigatória; sem retry cego. A bateria integral usa `B/flow-final-diagnostic-tools/run-full-ios-final.py <SHA-COMPLETO>` com BFT correspondente, somente após integração do candidato final.

## 6. Escopo que ainda precisa ser encerrado antes de Roberto

### Protocolos: 63 pacotes / 89 regras

O plano completo é obrigatório. Registro atual: nove primeiros pacotes com trabalho local parcial, C11 backend parcial, **53 outros NOT_YET_VERIFIED**. Não apresentar isso como percentual de conclusão nem como 53 recursos ausentes: confrontar código, testes e dados em cada pacote. Nenhum “protocolo pronto” baseado apenas em metas/calorias de entrada.

Lacunas verificadas nas auditorias recentes incluem C10 (porções/quantidade ausente), C11 nativo, C34 (plano alimentar confirmado e compras), C35 (execução/erros comuns/esforço/progressão no treino), C37 (cardápio semanal), C48 (sono/passos), C49 (histórico de peso/medidas) e C51 (níveis/mensagens de conquistas). Ler cada pacote/depêndencia antes de implementar; não inventar dados, gráficos, recompensas ou capacidade inexistente.

C5 ainda precisa integração/ativação real dos consumidores e comprovação integral das 13 famílias com GoTrue/Next/app, mantendo as provas locais já encerradas. Não ligar seletor público ou publicar SQL privado apenas porque contagens locais passaram. C7/C6 e outros consumidores dependem desse trabalho.

**Troca de fase somente dentro da reavaliação de 14 dias (C21/C22/C23)**, nunca no Perfil/base. As 12 decisões de M/decisions-v1.md são obrigatórias: C28 só avisa e leva à reavaliação; C29 não muda calorias sozinho; sete gatilhos C30 OFF; orçamento C4 em ganho/manutenção oculto; recomposição→manutenção recusada/oculta até C31 confirmado; body photos C24/C55 não solicitadas sem avaliador definido; projeção de nomes públicos e espelhos BFF em todos os consumidores.

### Regras clínicas ainda sem resposta

Roberto **não respondeu às 44 perguntas**. Eduardo autorizou continuar com proposta conservadora baseada em evidência, distinguindo proposta técnica de decisão clínica. `H/PROPOSTA-44-RECONCILIADA-20261008.md/json` tem 44 recomendações provisórias, 179 cenários por item +7 cruzados **PLANEJADOS**, não executados nem aprovados clinicamente. `PROPOSTA-EVIDENCIAS-PROTOCOLOS-20261008.md` é pesquisa histórica, não resposta do médico.

Construir/testar mecanismos e manter OFF/oculto o que depende da decisão. Não preencher questionário como se Roberto tivesse respondido; não inventar thresholds/fórmulas/condutas clínicas. Reconsultar fontes oficiais se for tomar uma nova decisão médica baseada em evidência. Nenhuma ação editorial/aceite humano pode ser feita pelo agente. Isso é uma restrição real da entrega, não motivo para parar partes técnicas independentes.

### Refinamento aprovado e tutorial

Preservar Warm Performance, logo Signal Spark e navegação **Hoje · Plano · Registrar · Progresso · Perfil**, logo central em Registrar abrindo registro existente. TabView/AppRouter/stacks independentes, safeAreaInset e APIs públicas, área44pt, VoiceOver/Large Content Viewer. Não introduzir navegação concorrente nem perder formulários/posição ao alternar abas.

Conferir implementação existente contra o plano aprovado: Flow A→digitarB→respostaA sem apagarB; identidades de leitura/envio/sessão; retry com mesma chave; pending imediato/reciboPOST/reconciliação por IDs; falhaGET após sucesso só repete leitura; refresh Hoje deduplicado, snapshot visível, tarefas independentes paralelas. Preservar caches/isolamento/respostas longas.

Design system único: superfícies semânticas/componentes compartilhados, conteúdo opaco e vidro concentrado em navegação/controles. iOS26+ Liquid Glass nativo, fallback material e opaco conforme acessibilidade/energia/temperatura; mínimo iOS18 preservado em compilação. Política central para Reduce Motion/Transparency/contraste/diferenciação sem cor. Sem dependências novas, sons, partículas ou parallax contínuo.

Logo com idle/press/active/processing/success/error; proposta pronta significa “Pronto para revisar”, só confirmação persistida significa “Registro confirmado”; coordenador por sessão/operação, um feedback tátil por resultado. Launch Screen estática teal profundo, primeiro quadro consistente, sem duração mínima; animação em runtime e Reduce Motion imediato. Indicador só após150ms, cancelável; skeletons próprios Hoje/Plano/Progresso/Biblioteca e dados preservados em refresh. Motion140/220/até400ms sem atrasar operação nem inventar porcentagens internas.

Jornadas Hoje, Flow, registro/importação, Plano/Progresso, Rotina, Biblioteca/Perfil e auth/onboarding continuam na auditoria final. Comida=`consumido−meta` sem exercício; déficit/bloco=`consumido−meta−exercício`. Não alterar fórmulas. Revisão versus confirmação clara; teclado acessível; rascunhos preservados/ocultos corretamente; rotina futura/elegibilidade/conflito; peso80kg/data exata na UI.

O tutorial inicial já existe e pode ser revisto pelo Perfil. Quando novas capacidades forem concluídas, atualizar o tutorial para mostrar **o que o app realmente oferece**, com opção de pular/rever, sem prometer funcionalidades OFF. Preservar a extensão Seu objetivo e seus testes; não reimplementar do zero.

Texto original do anexo de design, copiado byte a byte, está em `T/reference/anexo-design-original.txt`. O plano explícito posterior de Eduardo prevalece sobre sugestões opcionais antigas do anexo, inclusive proibindo sons/dependências/efeitos contínuos nesta entrega. `T/reference/operacao-segunda-entrega-original.txt` preserva o pedido operacional anterior; seus HEADs/ordem de testes são históricos e o pedido posterior ampliou os protocolos exigidos antes de Roberto testar.

## 7. Gates finais e distribuição

- Suíte iOS completa após integrar todas as mudanças; falhas anteriores separadas. Última bateria integral conhecida teve 240 PASS/4 FAIL, aproximadamente194min, antes de correções focadas posteriores. Não é validação integral final. Helpers e receipts antigos explicam cada falha; não repetir avaliações causais já encerradas nem declarar falha histórica como regressão nova.
- Scanner de marca/localização novamente, build Release, análise nativa, assinatura, smoke físico. Scanner histórico de 21/25 testes não substitui execução do candidato final.
- PT/EN, claro/escuro, compacto/ProMax, orientação suportada, teclado, Dynamic Type até Accessibility XXXL, VoiceOver, Reduce Motion/Transparency/contraste; carregado/vazio/loading/offline/erro/retry/stale.
- Navegação com cinco históricos, sheets, deep links de lembretes, logout/restauração, QA A→B→A e nenhum conteúdo da conta anterior; proposta/confirmado e formulário em erros/cancelamento; dieta, foto, áudio, PDF e Biblioteca. Notificação foi observada funcionando pelo Eduardo; não alterar Não Perturbe para reabrir essa questão sem necessidade.
- Performance antes/depois no mesmo dispositivo/config/dados: abertura/primeira tela útil, 50 mensagens/resposta longa, Biblioteca, navegação/sheets; Instruments App Launch/SwiftUI/Animation Hitches/Time Profiler/Allocations. Regressão reproduzível bloqueia o efeito responsável. Runtimes locais26.5/27; iOS18 é compatibilidade compilada/fallback determinístico, não validação física inexistente.
- Build anterior assinado `B/release-gates-v3-95dca3a` deve ser preservado para retorno. Último build físico conhecido 4dd de08/10 antecede novos commits. Perfil conhecido expirava **2026-10-12T13:28:22Z**; revalidar/renovar antes da instalação futura.
- Fluxo editorial real da Biblioteca: Roberto envia para revisão, Eduardo (nutrition_admin/revisor independente) revisa de verdade e Roberto publica; depois o agente verifica audit e app, PT/EN/isolamento/persistência/rascunhos ocultos. Decisão nutricional necessária, aceite visual de Eduardo e instalação/distribuição para Roberto continuam gates próprios. Não registrar ações/aceites em nome deles, nem inventar um terceiro revisor. Concluir partes técnicas; pedir somente a decisão humana concreta que realmente faltar.
- Eduardo informou Apple aprovada. Isso não comprova App Store Connect, assinatura nova, upload, TestFlight ou funcionalidade. Handoff antigo menciona intenção de TestFlight interno; os limites específicos de publicação exigem confirmar o OK atual do candidato/alvo antes de publicar.
- Último staging conhecido `0db4741`/preview `ap8ccfy5l`, rollback `dme8ur037`, é **histórico do handoff**, não consulta ao vivo em09/10. Se autorizado, verificar antes de promoção. BFF e app compatíveis devem avançar juntos; nunca publicar servidor que novo cliente exige antes do app compatível.

## 8. Encerramento desta transferência e relatório futuro

Nesta transferência: somente documentação/pacote local; fontes de produto preservadas; nenhum teste/build de produto repetido, nenhum novo runtime, nenhuma escrita cloud, push, merge, deploy ou instalação. Nenhum ambiente pago criado, adotado ou encerrado nesta transferência; clusters próprios anteriores já fechados. Outros worktrees não foram removidos. Deploy não é necessário para entregar documentos.

`T/SESSION-STATE.json` registra HEAD inicial técnico, HEAD final documental, revisão independente, git limpo, hashes, check de processos próprios e **status real da pausa**. Todas as lanes anteriores terminaram. Claude Code deve iniciar só depois da pausa; não abrir Codex e Claude escrevendo neste checkout ao mesmo tempo.

**REGRESSION STATUS do produto: PARTIALLY VERIFIED. PRODUCTION STATUS: NOT DEPLOYED. RobertoReady: false.** Handoff pronto significa contexto transferível, não app concluído.

No encerramento do produto, o relatório solicitado tem 15 itens: 1 Resumo executivo; 2 Auditoria; 3 UX/UI; 4 Splash/abertura; 5 Loading; 6 Logo central; 7 Motion; 8 Identidade visual; 9 Performance; 10 User friendly; 11 Acessibilidade; 12 Novas ideias realmente implementadas; 13 Testes; 14 Pendências reais e motivos; 15 Status final sustentado por evidência. Acrescentar os estados operacionais da política global: host/repo/branch/HEADs, baseline, tests/TC/lint/build/QA/review, commit/push/integração/deploy/health/rollback, regressão/produção/cleanup/custos/riscos. Não inventar campos nem declarar concluído enquanto gates necessários permanecerem abertos.
