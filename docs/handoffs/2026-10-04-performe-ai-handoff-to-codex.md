# Handoff — Performe AI beta (staging) — 2026-10-04 ~18:40 BRT (Claude Code → Codex)

Produto público: **Performe AI**; agente público: **Flow**; identidade técnica
interna: BodyFlow (não renomear). Responder ao Eduardo **em pt-BR, curto e em
passos**; quando precisar das mãos dele, dizer exatamente "Faça X agora.".

Leia antes de agir: `CLAUDE.md` (raiz), `docs/CALCULO-MPP.md` e este arquivo.

## 1. Regras que continuam valendo (do Eduardo, sem exceção)

- **Só staging e commits locais.** Supabase `xitugspwfxkcluxvrdeg`, Vercel
  Preview. Sem push, PR, merge remoto, tag, Production, TestFlight, App Store
  ou infraestrutura paga nova. Deploy de produção só com autorização explícita.
- **Segredos:** não mostrar `.env`, tokens, senhas, configs privadas, URLs
  assinadas ou dados reais. Não pedir segredo no chat. As contas QA A/B estão
  autorizadas; credenciais só de arquivos locais, sem expor.
- **iPhone:** instalar por cima, preservando dados; nunca desinstalar; manter
  rollback assinado; não contornar bloqueio do Mac ou do iPhone.
- **Não registrar em nome deles:** aceite visual do Eduardo, publicação do
  Roberto, decisão nutricional do Roberto.
- **Uma única fila de Xcode/simulador.** Nunca dois builds ou testes ao mesmo
  tempo. Nunca `CODE_SIGNING_ALLOWED=NO`. Sem `git reset/clean/stash`.
- **CLAUDE.md:** ler `docs/CALCULO-MPP.md` antes de tocar fórmula; comida =
  consumido − meta SEM exercício; bug relatado vira golden com frase, horário e
  valores exatos, ou linha `> RC X — cenário Y NÃO coberto nesta PR (pendência
  da audit AAAA-MM-DD)`; revisão adversarial antes de commitar CRITICAL/HIGH;
  `packages/agent` é compartilhado com o WhatsApp em produção.
- Commits por caminho explícito, com o trailer de coautoria do agente que
  commitar.

## 2. Decisões do Eduardo em 04/10 (valem para a continuação)

1. "consegue finalizar tudo sem depender de mim?" → sim para a parte técnica.
2. "vamos seguir com a forma q vc acha q faça mais sentido": aplicar as
   recomendações do agente sobre as regras ditas pelo Roberto, **só em staging
   e commits locais**, documentando cada uma como "dito pelo cliente em <data>;
   implementado em 2026-10-04 a pedido do Eduardo; confirmação do cliente
   pendente". Nunca inventar número clínico que o Roberto não disse.
3. "não esqueça da otimização dos custos de tokens e velocidade de
   resposta/processamento do Flow".

## 3. Onde está tudo

- Repositório (worktree): `/Users/eduardohenrique/Developer/performe-ai-client-beta-flow-v1`,
  branch `codex/performe-ai-client-beta-flow-v1`.
- Evidências (fora do repo): `B=~/.local/share/performe-ai/final-polish-20261001`
  (derived data em `$B/derived`; suíte completa:
  `$B/flow-final-diagnostic-tools/run-full-ios-final.py <SHA COMPLETO>`).
- **Ferramentas desta sessão, copiadas para lugar permanente:**
  `H=$B/handoff-20261004/`
  - `bff-preview-deploy.sh` — publica o BFF em Preview a partir do HEAD
    (`git archive`), já com `--local-config apps/mobile-bff/vercel.json`
    (região gru1), imprime `PREVIEW_URL` e `REGION`. Rodar com `bash`; exige
    árvore limpa em `packages apps/admin apps/mobile-bff`.
  - `e2e2/m.sh` + `e2e2/scroll` — controle do iPhone pelo Espelhamento (ver §9).
  - `flowperf/` — medição de partida do Flow, mapa dos cortes e o roteiro
    pronto da parte B (`flow-perf-part-b.js`, texto dos pedidos por etapa).
  - `rulemap/` — mapa das regras do Roberto no código, config de cálculo do
    staging lida hoje, resultados das duas rodadas de revisão.
- Auditoria do WhatsApp com áudios (dados privados):
  `~/.local/share/performe-ai/whatsapp-audit-20261004/` (`transcripts/` 491
  arquivos; `verify/audio_*.json`; `merge/build.py` + `merge/assemble.py`
  geram o documento; `merge/merged.json` tem os 527 relatos).
- xcconfig privado atual: `~/.local/share/performe-ai/pre-llm-e2e/Release.staging.e2e-v26.private.xcconfig`
  (3 chaves; não imprimir). O próximo é v27, trocando só o trecho do host.
- Simulador da fila: iOS 27 `CE89BD02-DF61-4214-AD61-2A2A51114022` (reiniciar
  antes de rodada longa). iPhone: UDID `00008110-001649510208401E`, bundle
  `com.performeai.app.dev.k6942zjtv6`.
- Conta QA A no staging: `users.auth_user_id like 'b56095c5%'` (ganho_massa,
  meta 2980 kcal / 144 g, 80,5 kg).

## 4. Commits locais de 04/10 (mais novo primeiro)

- `9624cd5` feat(ios): linha "Balanço do dia" (valor "Déficit de N kcal" /
  "Superávit de N kcal", legenda pelo campo do servidor), "Musculação por
  semana" no cadastro, 409 `registration_already_confirmed` tratado como
  confirmado com a mensagem "Este registro já estava salvo. A alteração não foi
  aplicada.".
- `55294c4` docs(bff): como a região gru1 é obedecida num deploy pela CLI.
- `e57806f` perf(flow): BFF em São Paulo (`apps/mobile-bff/vercel.json`) e
  leituras do serviço do chat em paralelo (12 → 6 idas), linha de tempo por
  turno `[mobile-flow] turn_timing`.
- `cf89221` fix(card): "Restam: 0 kcal", nunca "-0".
- `87821a6` fix(app): achados da 3ª revisão (resposta a pergunta do Flow vai
  ao modelo; cancelar proposta já gravada responde
  `registration_already_confirmed`).
- `ff50a9e` fix(app): Flow nunca diz que treino libera comida; segunda porção
  confirmada no app soma. **Validado no iPhone às 15:20–15:25.**
- `8e5c978` docs(audit): auditoria do grupo de WhatsApp (sem os áudios).

## 5. Estado dos ambientes

- **iPhone:** instalado por cima o build de `ff50a9e`, apontando para o BFF
  Preview `…-2ig5f8mks-…` (ainda em iad1). Rollback assinado em
  `$B/release-gates-v3-21b5ec7/release-staging-derived/…/BodyFlow.app`.
  **O perfil de assinatura venceu em 2026-10-04 18:12 BRT**: o próximo build
  precisa de `-allowProvisioningUpdates` (o `run.sh` dos gates já usa).
- **BFF Preview mais novo:** `…-dpdnrn1xu-…` (sourceHead `e57806f`), função em
  **gru1** confirmada (`x-vercel-id: gru1::gru1::…`). O iPhone ainda NÃO aponta
  para ele.
- **Banco de staging:** nenhuma escrita de configuração foi feita hoje.
  `calc.protein_factors` em cascata 1,6–2,0, `calc.imc_goal_steps`
  `[30,25,23,22,21]`, `calc.xp_rules` na fórmula antiga (detalhe em
  `$H/rulemap/staging-calc-config-20261004.md`).

## 6. Trabalho em andamento no momento da passagem

### 6.1 Regras do Roberto no servidor — COMMITADO em `9bc012b` (18:45)

Conteúdo: "leite" → leite integral e "whey" → whey em pó (linhas verificadas
4492 e 6407 do catálogo); escada de IMC em passos de 5 até 25; recusa de meta
de gordura abaixo de 10% e de perda de peso abaixo de IMC 18,5 (o piso
feminino não foi inventado); proteína 1,5 g/kg só na recomposição; balanço do
dia por protocolo em `/today` e no Flow (versão `bodyflow.daily-state.v3`,
dois campos aditivos). A mensagem do commit lista as diferenças intencionais
no WhatsApp e o que não mudou.

Revisão: duas rodadas adversariais; a segunda sem CRITICAL/HIGH. A última
passada (achados menores) foi aplicada, **mas a verificação independente dela
não rodou** — os agentes pararam no limite semanal da conta. As suítes foram
rodadas à mão na árvore final, todas verdes (core 498, agent 2571, admin
mobile-api 516, inngest 194, mobile-bff 29, typecheck 9/9), e o golden de
trava do WhatsApp está sem edição.

**O que o Codex deve fazer aqui:** uma checagem adversarial curta só da
mudança em código compartilhado dessa última passada — a isenção da guarda de
"escrita-fantasma" quando `define_protocolo` ou `define_meta_peso` rodou sem
erro no turno (`packages/agent/src/fake-write-detector.ts`,
`goalToolRanThisTurn` em `pipeline.ts`): confirmar que um turno sem tool de
escrita, ou só com tool de leitura, ainda dispara a guarda, e que o card
"Total refeição" continua sendo tratado como afirmação de refeição. Lacunas
conhecidas, todas LOW: falta o golden do caso "protocolo nulo" da frase de
balanço (3100 / 2980 / 322); a redação do modelo depois de uma recusa não é
provada por teste.

### 6.2 Suíte completa do iOS em `9624cd5`

Rodando em segundo plano desde ~17:07 (≈ 2 h; às 18:45 tinha 168 testes de UI passados e 2 falhas). Resultado em
`$B/ios27-final-full-suite-9624cd5.{log,json,xcresult}` e `-summary.json`.
Falhas até agora:
- `PerformeVoiceOverNavigationUITests.testVoiceOverReadsFiveTabsInOrder…` —
  falha conhecida e determinística (Hoje tem 62 paradas de VoiceOver para um
  orçamento de 30 s). **Não aumentar o orçamento**: decisão do Eduardo (45 s
  recomendado, ou cortar conteúdo).
- `MealCaptureUITests.testWrittenMealIsReviewedBeforeAnyProposal` — falha NOVA
  ("O item deve ficar confirmado após um único toque", a chave de conferência
  na revisão dos alimentos). O lote do app não tocou essa tela. **Quando a
  suíte terminar, rodar esse teste isolado** (reiniciar o simulador antes); se
  falhar de novo é regressão real e precisa de correção antes de instalar.

## 7. O que falta, em ordem

1. **Conferir 6.1** (as regras já estão commitadas em `9bc012b`; falta só a checagem curta descrita lá).
2. **Flow, parte B — custo e velocidade** (só caminho do Flow; WhatsApp byte a
   byte igual). Roteiro completo em `$H/flowperf/flow-perf-part-b.js` e mapa em
   `$H/flowperf/map.json`:
   - histórico do Flow com 16 linhas em vez de 50 (≈ −3.000 tokens por chamada);
   - contexto do turno sem as instruções que só servem ao WhatsApp (≈ −800);
   - sugestão de plano sem a segunda chamada ao modelo (−8 a −14 s e
     −US$ 0,02–0,035 nesses turnos), reusando o texto fixo que já existe;
   - teto de 2 iterações no código e limites de tempo próprios do Flow;
   - resposta de status em texto simples no app (hoje sai com asteriscos);
   - telemetria por chamada e custo do gerador de plano, só números.
   Antes de cortar: um golden que trave o pedido inteiro do WhatsApp. Depois:
   revisão adversarial em três lentes (qualidade da resposta, WhatsApp idêntico,
   economia medida).
3. **Publicar e instalar:** `bash $H/bff-preview-deploy.sh` (confere
   `REGION=…gru1::gru1…`) → criar xcconfig v27 trocando só o trecho do host →
   gates de Release com `bash` (copiar `$B/release-gates-v3-21b5ec7/run.sh`
   para uma pasta nova, trocar o SHA e o xcconfig) →
   `xcrun devicectl device install app --device 00008110-001649510208401E <BodyFlow.app>`.
4. **Validar no iPhone** (Espelhamento, §9) e conferir no banco:
   - Flow: "Treinei musculacao hoje e gastei 322 kcal. Posso comer 322 kcal a
     mais?" → resposta do sistema com os números do dia;
   - Hoje → Mais detalhes: linha "Balanço do dia" com "Déficit de N kcal" e a
     legenda "Exercício já contado no nível de atividade" (a conta QA é ganho
     de massa: N = consumido − round(2980/1,05) = consumido − 2838);
   - Registrar por texto "1 copo de leite com whey no jantar", 200 g e 30 g →
     "leite integral" 122 kcal e "whey protein em pó" 105,6 kcal;
   - velocidade e custo do Flow antes × depois, pelas mesmas perguntas:
     `select created_at, model_used, prompt_tokens, completion_tokens, cost_usd, latency_ms from messages where provider='mobile_flow' and direction='out' order by created_at desc limit 20`
     (partida: 11 mil tokens de entrada por chamada, US$ 0,035 por resposta,
     14 s na mediana, 4,3 s na resposta sem modelo — `$H/flowperf/baseline-20261004.md`);
   - anotar em `$B/e2e-20261004/ledger.md` (rodada 4).
5. **Documentos:**
   - atualizar `docs/handoffs/2026-10-04-whatsapp-group-audit.md` com os
     áudios: 527 relatos (498 + 29 só em áudio), 67 regras ditas em áudio.
     Gerador: `cd ~/.local/share/performe-ai/whatsapp-audit-20261004 && python3 merge/build.py && python3 merge/assemble.py <repo> <state.json>`
     (o `assemble.py` espera um `state.json` com os textos variáveis:
     `headline_fix`, `second_portion_why`, `three_items_why`, `neg_zero`,
     `retest`, `weigh1`, `weigh2`). Antes de gerar, reconferir o status das
     famílias que os commits de hoje mudaram (proteína, escada de IMC, piso de
     gordura, leite/whey, exercício em ganho/manutenção no app e no Flow,
     "Déficit líquido", segunda porção, Flow × treino);
   - registrar a rodada 3 e a 4 no relatório E2E
     (`docs/handoffs/2026-10-04-performe-ios-e2e-iphone-round-1.md`).
6. **Mensagem para o Roberto** (rascunho no §8) — o Eduardo envia.
7. **Fechamento:** simulador desligado; árvore limpa; lista de pendências
   atualizada neste arquivo.

## 8. Rascunho da mensagem para o Roberto (o Eduardo decide se envia)

> Roberto, ajustamos a versão de teste do app seguindo o que você já tinha
> dito no grupo. Me diz "ok" ou o que mudar em cada ponto:
> 1. Ganho de massa e manutenção: o treino não entra no balanço do dia (já
>    está no nível de atividade). Só na recomposição ele entra.
> 2. Balanço do dia = o que comeu menos o gasto do dia. No ganho de massa,
>    comer exatamente a meta aparece como superávit de 5%.
> 3. Meta de IMC: desce de 5 em 5 pontos até 25 (32,7 → 27,7), sem o degrau
>    fixo de 30. Você chegou a escrever "10 pontos" em 07/02 — vale 5 ou 10?
> 4. Gordura corporal: o sistema não aceita meta abaixo de 10%. Para mulheres
>    você quer um piso maior? Qual?
> 5. Proteína: 1,5 g por kg na recomposição. E no ganho de massa e na
>    manutenção, qual valor?
> 6. "Leite" sem tipo = leite integral; "whey" = whey em pó comum (30 g =
>    106 kcal, 23 g de proteína). Pode ser assim? Quais outros nomes entram?
> 7. No cadastro do app a pergunta ficou "Musculação por semana".
> Ficou como estava, esperando você: a pergunta da água no cadastro; o
> segundo pedaço da mesma comida no WhatsApp (somar ou perguntar?); o bloco de
> 14 dias para ganho e manutenção; o texto da resposta do Flow quando
> perguntam se treino libera comida.

## 9. iPhone pelo Espelhamento

`zsh $H/e2e2/m.sh <comando>`; coordenadas em pixels da captura (2× a janela
de 346×760 pt). Comandos: `tap x y [espera]`, `typetext "…"` (sem acentos),
`shot nome` (salva em `$B/e2e-20261004/`), `scroll <pixels> [espera] [y]`,
`home`. Abrir o app sem passar pela tela inicial:
`xcrun devicectl device process launch --device 00008110-001649510208401E com.performeai.app.dev.k6942zjtv6`.
Pontos úteis: abas Hoje 104,1390 / Plano 224 / Registrar 346 / Progresso 466 /
Perfil 588; "Falar com o Flow" 230,836 depois de `scroll -330`; campo do Flow
300,1258; enviar 604,1192; voltar 80,182; Registrar → "Texto" 346,612 →
"Escrever" 346,1072 → campo 346,1000 → fechar a sugestão do teclado 528,1016
→ "Ler alimentos" 346,1144 → `scroll -500 1.5 1200` → "Calcular refeição"
346,1228 → "Confirmar" 346,1262; fechar a folha 118,800.
Cuidado: capturar só com o app na frente (a tela inicial e outros apps são
pessoais). A câmera não funciona pelo espelhamento.

## 10. Decisões pendentes

Do Eduardo:
- Aceite visual dos textos novos no app (linha "Balanço do dia", "Musculação
  por semana", "Este registro já estava salvo…") depois de instalado.
- Produção do BFF em São Paulo (deploy só com autorização; não conferi a
  tabela de preço da Vercel para gru1).
- Orçamento do teste de VoiceOver (45 s recomendado) ou cortar conteúdo do Hoje.
- Gravação do progresso de exemplo na conta QA A (bloqueada pelo classificador
  de permissão; não contornar), marcador do benchmark, pacote de ilustração.
- Trocar as chaves expostas: a do 21st.dev colada no chat e as que aparecem na
  exportação do WhatsApp (OpenAI, OpenRouter, painel).
- 21st.dev: o conector está cadastrado no Claude Code (escopo do usuário) e só
  aparece em conversa nova; processo combinado: mockup antes de implementar.

Do Roberto: os pontos do §8.

## 11. Deixado de fora de propósito (com o motivo)

- **Segundo pedaço no WhatsApp** (perguntar em vez de substituir): é o caminho
  que mais regrediu e não há como testar WhatsApp ao vivo aqui. Plano em
  `$H/rulemap/map.json`, área `whatsapp-second-portion`.
- **Pergunta da água no cadastro:** a fala mais recente dele (01/06) aprovou
  uma lista que inclui água; não retirar sem ele confirmar.
- **Crédito do bloco, bom dia e `consulta_resumo_periodo` em ganho/manutenção:**
  inalterados; o bloco de 14 dias não está definido.
- **Flow:** gerar o plano em segundo plano (resolveria os turnos de 45–90 s,
  mas muda app e API); mais turnos no modelo menor (sem conjunto de
  avaliação); respostas prontas para "como está meu dia" e "quanto falta de
  proteína" (texto novo ao paciente); cache do histórico; streaming.
- **Ainda abertos da auditoria:** editar/excluir refeição confirmada no app;
  Flow ler o dia de ontem; cadastro do app sem conferência de IMC/gordura e sem
  as três fotos; gasto total devolvido como meta quando não há protocolo; texto
  interno "Peça pro paciente confirmar ou detalhar" chegando ao paciente; nome
  do alimento carregando a frase da refeição; medidas caseiras ("1 copo");
  foto com item que não faz parte (C8-A02); zerar o dia; reavaliação na faixa
  normal sem perguntar o protocolo.
- **Não testado por limite do ambiente:** cadastro novo (só o Eduardo digita a
  senha), refeição por foto e por áudio, rotina/lembretes, Biblioteca sem
  conteúdo publicado, acessibilidade no aparelho.

## 12. Lições desta sessão

- Simulador ligado há muito tempo gera esperas de 60 s ("App animations
  complete notification not received"): `simctl shutdown/boot` antes de rodar.
- Animação contínua em SwiftUI trava o XCTest; animação de camada não.
- Os gates de Release rodam com `bash`, não `zsh`.
- `vercel.json` em `apps/mobile-bff` só vale num deploy pela CLI com
  `--local-config apps/mobile-bff/vercel.json`; a prova é o `x-vercel-id`.
- Revisão adversarial achou defeito real em todas as rodadas de hoje; não
  commitar CRITICAL/HIGH sem ela.

## Atualização — 18:45 BRT

- As regras do Roberto no servidor foram commitadas: `9bc012b`. **A árvore
  está limpa.** HEAD = `9bc012b` mais este documento.
- Os agentes auxiliares do Claude Code pararam no limite semanal da conta
  (volta em 09/10 às 9h). Nada ficou pela metade no repositório.
- Ainda NÃO foi feito: Flow parte B (§7.2), publicar/instalar/validar
  (§7.3–7.4), documentos (§7.5), mensagem ao Roberto (§7.6).
- O BFF Preview `…-dpdnrn1xu-…` (gru1) é do commit `e57806f`: **não** tem as
  regras de `9bc012b`. Publicar de novo antes de instalar.
