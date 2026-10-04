# Auditoria do grupo de WhatsApp do projeto — o que foi realmente resolvido (2026-10-04)

Performe AI é o produto público e Flow o agente público; BodyFlow é a
identidade técnica interna preservada.

Pedido do Eduardo (04/10): analisar toda a exportação do grupo "Projeto
BodyFlow" (cliente + desenvolvedores), refazer os testes e dizer se cada erro
relatado quando o agente rodava no WhatsApp foi **realmente** resolvido.

## Resultado em uma frase

Dos 498 relatos de erro do grupo, **159 estão resolvidos com evidência no
código atual, 79 não se aplicam mais ou são operacionais, 125 continuam
abertos, 125 só um teste real decide e 5 dependem de uma regra que o Roberto
precisa confirmar.** Sete testes reais no iPhone confirmaram quatro defeitos
abertos no app.

## Como foi feito

- Material: `_chat.txt` com 5.908 mensagens de 23/12/2025 a 27/09/2026, 666
  imagens, 489 áudios, 8 PDFs e planilhas.
- Extração: a conversa foi dividida em dez trechos e lida por inteiro; cada
  relato de erro virou um registro com data, quem relatou, as frases e os
  números exatos dos prints. Total: 497 relatos de erro (498 nas famílias, um
  conta em duas) e 177 pedidos de funcionalidade.
- Verificação: os relatos foram agrupados em 213 famílias e cada família foi
  conferida contra o código atual, a regra em `docs/CALCULO-MPP.md` e os testes
  (rodados, não só lidos). Um "corrigido" dito no grupo não conta como prova.
- Dados da extração e da verificação (fora do repositório, com as frases dos
  prints): `~/.local/share/performe-ai/whatsapp-audit-20261004/`.

### Limites desta auditoria

- **Áudios não ouvidos.** Não há ferramenta de transcrição nesta máquina. 64
  relatos dependem em parte de áudio e várias respostas dos desenvolvedores
  existem só em áudio.
- **Sem acesso a produção.** Regras do agente gravadas no banco
  (`agent_rules`, prompts ativos, fatores de proteína, probabilidade de áudio)
  não foram lidas. Os testes SQL de `supabase/tests` exigem banco e não rodaram.
- **Testes reais só pelo app.** Não há chave de LLM nem chave de serviço local,
  então o agente do WhatsApp não foi exercitado ao vivo; os testes reais foram
  feitos no iPhone, conta QA A, staging.
- **Fotos não testadas ao vivo.** O espelhamento não tem câmera e a galeria do
  aparelho é pessoal. As 22 queixas de leitura de foto ficam como "precisa de
  teste real".
- A exportação contém senhas e chaves de API em texto aberto (OpenAI,
  OpenRouter, painel). Nenhuma foi copiada. Recomenda-se trocar essas chaves.

## Números por área (em relatos)

| Área | Resolvido, teste exato | Resolvido, teste de variante | Resolvido, sem teste | Não se aplica | Operacional | Precisa teste real | Divergência de regra | Aberto | Sem evidência | Total |
|---|---|---|---|---|---|---|---|---|---|---|
| Cadastro | 1 | 7 | 2 | 2 | 0 | 39 | 0 | 27 | 0 | 78 |
| Refeições (foto, texto, áudio) | 4 | 4 | 1 | 7 | 0 | 22 | 0 | 19 | 0 | 57 |
| Tom, persona e diversos | 2 | 10 | 0 | 11 | 0 | 28 | 0 | 19 | 3 | 73 |
| Metas, treino e planos | 5 | 17 | 9 | 1 | 0 | 11 | 2 | 20 | 0 | 65 |
| Bloco 7.700 e card do dia | 2 | 31 | 6 | 13 | 0 | 12 | 3 | 6 | 2 | 75 |
| Infraestrutura e lembretes | 0 | 5 | 9 | 33 | 10 | 11 | 0 | 13 | 0 | 81 |
| Duplicidade, correção e base de alimentos | 25 | 18 | 1 | 2 | 0 | 2 | 0 | 21 | 0 | 69 |
| **Total** | **39** | **92** | **28** | **69** | **10** | **125** | **5** | **125** | **5** | **498** |

Leitura: só 39 relatos têm teste com o cenário exato do print. Os 92 de
"variante" são a dívida descrita no CLAUDE.md (teste cobre a regra, não o caso
relatado).

## Testes reais no iPhone (04/10, conta QA A, staging, build 21b5ec7)

| # | Queixa do grupo | Teste | Resultado |
|---|---|---|---|
| 1 | Exercício somado ao "Restam" / liberando comida (a confusão nº 1) | Flow: "Treinei musculação hoje e gastei 322 kcal. Posso comer 322 kcal a mais?" | **FALHOU.** Resposta: "Sim! Sua meta já considera esse gasto… tecnicamente você tem espaço pra comer um pouco mais". A tela Hoje está certa (restam 2.678, exercício fora); o texto do Flow contradiz a regra |
| 2 | Segunda porção não entra na soma / correção substitui | Registrar duas vezes "150 g de frango grelhado no almoço" | **FALHOU.** As duas propostas ficaram "confirmadas" e o app mostrou "Refeição confirmada", mas `meal_logs` tem uma linha só: o dia soma 541 kcal em vez de 780 |
| 3 | Leite com whey lido errado todo dia | Texto "1 copo de leite com whey no jantar", 200 g e 30 g | **FALHOU.** "leite" casou com leite de coco (332,3 kcal, 36,7 g de gordura; o certo é cerca de 122 kcal) e "whey" ficou sem cálculo ("valor encontrado não bate") |
| 4 | Balanço de ontem não vem / vem errado | Flow: "Qual foi meu balanço de ontem? Mostre consumido, meta, exercício e a conta" | **FALHOU.** "O sistema não trouxe dados dos dias anteriores." O banco tem ontem 2.007 kcal, meta 2.980, exercício 380. A ferramenta do Flow só lê dias fechados e devolve médias, não o dia |
| 5 | Tipo de refeição errado | Mesmo texto do teste 3, enviado ao meio-dia com "no jantar" | PASSOU: tipo "Jantar" |
| 6 | Metas e consumo informados errados | Flow: "Quanto de proteína ainda falta hoje?" | PASSOU: 11 g consumidos, meta 144 g, faltam 133 g (igual ao banco) |
| 7 | Dieta/cardápio não gerado | Flow: "Sugira um cardápio completo para hoje" | PASSOU após a correção de hoje: 2.884 kcal, 152,3 g de proteína |

Outros achados vistos nesses testes:
- O nome do alimento guarda a frase da refeição: "frango grelhado no almoco"
  aparece assim no Hoje.
- "1 copo" de leite não é convertido; o app pede gramas.
- O texto interno "Peça pro paciente confirmar ou detalhar" chega ao paciente.

## O que pesa mais, em ordem

1. **Flow diz que treino libera comida** (teste 1). Regra nº 1 do projeto.
2. **App confirma a segunda porção e não soma** (teste 2). Dado perdido com
   mensagem de sucesso. Não existe editar nem excluir refeição confirmada no
   app nem na API.
3. **Base de alimentos** (teste 3 e 21 relatos abertos): nomes do dia a dia
   resolvem para a linha errada ou para zero. Precisa de decisão do Roberto
   sobre o catálogo e de o cálculo não dividir gramas igualmente em pratos
   compostos.
4. **Cadastro no app aceita qualquer objetivo** sem conferir IMC ou gordura e
   não tem a etapa das três fotos (27 relatos abertos no tema).
5. **Sem protocolo gravado, o código devolve o gasto total como meta do dia**
   (3.059 em vez de 1.843, como nos prints).
6. **Flow não lê o dia de ontem** (teste 4).
7. **Ganho de massa e manutenção:** bloco desabilitado, mas comer abaixo da
   meta é creditado como déficit e o app mostra o card.
8. **Correção depois de 30 minutos** soma de novo ou é recusada; o teste que
   deveria travar isso é réplica da regra, não chama o código real.

## Decisões que são do Roberto

- IMC acima de 30: o código mira 30; no grupo ele falou em reduzir 5 ou 10 pontos.
- Exercício no balanço de ganho de massa e manutenção: ele disse que não entra; o documento e o código subtraem.
- Bom dia com excedente acima de 100 kcal diz "acima da meta" e não cita o déficit creditado no bloco (casos 332→832 e 397→897).
- Água e estruturação alimentar continuam obrigatórias no cadastro; ele disse que não fazem parte.
- Quais nomes do dia a dia viram apelidos auditados do catálogo.

## Tabelas completas

### Open: the defect can still happen — 56 families, 125 reports

| Area | Sev. | Reports | Channel | Family | What is still wrong or unproven |
|---|---|---|---|---|---|
| Cadastro | alta | 7 (C2-05, C2-18, C2-20, C2-21, C2-27, C2-53…) | — | Protocolo definido sem as 3 fotos corporais (não pede fotos, segue após a 1ª foto, define antes das fotos) | No app o protocolo é sempre definido sem fotos; no WhatsApp pedir e esperar frente/lado/costas antes do protocolo depende só do modelo. Nenhum teste cobre o cadastro. |
| Cadastro | alta | 4 (C1-11, C1-14, C2-07, C2-61) | — | Fim do cadastro sem entregar as metas (calorias, proteína e primeira meta de gordura corporal) | O 'ponto crítico' do C1-14 (informar sozinho a primeira meta de gordura corporal) não existe no app; no WhatsApp a entrega única e completa das metas depende do modelo. Observação não reportada: calcBFGoal não distingue sexo (mulher com 25–30% recebe meta 20%). |
| Cadastro | alta | 2 (C1-09, C2-28) | — | Acima do limite (gordura ≥ 20%/28% ou IMC ≥ 25) o cadastro ainda oferece escolha de protocolo | No app, um homem com 24% de gordura pode escolher 'Ganho de massa' e o servidor aceita; no WhatsApp a recomposição obrigatória depende do modelo obedecer ao contexto. Nenhum teste cobre a gravação. |
| Cadastro | alta | 2 (C5-67, C6-61) | — | Paciente dentro da normalidade (ou magro) não pode escolher entre os 3 protocolos e cai em recomposição | No WhatsApp um paciente magro e sedentário continua indo para recomposição com déficit, e qualquer impedimento de ganho tira também a opção de manutenção. Se o modelo oferece os três protocolos quando canChoose=true só teste real mostra. |
| Refeições (foto, texto, áudio) | alta | 7 (C5-27, C6-47, C6-59, C7-25, C7-53, C7-59…) | ambos | Leite com whey lido como achocolatado todo dia; agente não aprende com as correções ('café de sempre') | No WhatsApp o erro volta a cada nome novo da visão e a cada 30 dias sem correção; no app nada é aprendido. Se o último uso do WhatsApp foi em 18/07, as correções do Roberto já estão fora da janela (não verificado no banco). |
| Refeições (foto, texto, áudio) | alta | 4 (C1-32, C6-20, C8-39, C8-58) | whatsapp | Tipo de refeição errado (café virou jantar, 21h virou lanche, foto à noite virou café, almoço virou jantar) | Nenhum dos prints (7:48 → jantar; 21h → lanche; foto à noite → café) é fixture; o caminho de foto depende só do prompt e 'café da manhã' com acento não é reconhecido como tipo explícito. |
| Refeições (foto, texto, áudio) | alta | 2 (C7-55, C8-48) | whatsapp | Foto + texto complementar em mensagens seguidas: só uma parte é registrada | 'Mais 2 ovos cozidos' não tem fixture e o complemento que chega depois da proposta da foto não tem proteção determinística; os goldens da Luciana testam cópias da lógica, não a função real. |
| Refeições (foto, texto, áudio) | alta | 2 (C7-02, C9-21) | ambos | Calorias/macros errados de um item (fallback genérico de 150 kcal/100 g, histórico contaminado, match errado na base) | Pendência aberta e documentada no próprio repositório (RC F23/F25, auditoria de 04/10): alimentos comuns ainda saem com valor errado ou genérico; o conteúdo real do food_db não foi verificado aqui. |
| Refeições (foto, texto, áudio) | alta | 1 (C7-56) | ambos | Correção aprendida aplicada contra o texto explícito do paciente (leite com café virou leite com whey) | A frase de 27/05 não tem teste e o remapeamento contra texto explícito continua possível enquanto houver correção ativa nos últimos 30 dias. |
| Refeições (foto, texto, áudio) | alta | 1 (C8-53) | whatsapp | Duas fotos da mesma refeição: a segunda é ignorada depois de uma pergunta intermediária | Com pergunta intermediária nada impede o LLM de remontar só o prato: não há bloqueio nem reenvio, e no caminho com botões nem o alerta de auditoria é gravado. |
| Refeições (foto, texto, áudio) | alta | 1 (C9-35) | ambos | Proposta confirmada com 3 itens, registro gravado só com 1 | No app e em foto sem legenda, uma proposta confirmada ainda pode gravar menos itens do que mostrou; não há teste de confirmação pelo app com item repetido no mesmo dia. |
| Tom, persona e diversos | alta | 1 (C4-13) | ambos | Regra de elegibilidade de protocolo (IMC menor que 25, sem o igual, para sair da recomposição) | No app um paciente com IMC 25 (ou 32) pode escolher Manutenção ou Ganho de massa; no WhatsApp nada determinístico impede o LLM de oferecer e gravar Manutenção com IMC 25,0, e falta teste com o valor exato. |
| Metas, treino e planos | alta | 7 (C1-04, C1-16, C1-21, C1-22, C2-46, C3-17…) | — | Projeção até a meta: peso-alvo, kg a perder e prazo/data pela regra dos 7.700 kcal (com gordura corporal ou via IMC) | Falta a função determinística (peso-alvo, kg a perder, dias e data) para meta de gordura e de IMC, e a entrega junto da primeira meta. Hoje o prazo ou não é informado ou sai de 'ritmo seguro por semana' — o mesmo tipo de estimativa que o Roberto rejeitou em C1-16. |
| Metas, treino e planos | alta | 4 (C1-12, C2-09, C6-10, C6-12) | — | Agente informa o TDEE como meta enquanto protocolo e déficit ainda não estão gravados (metas pedidas ou anunciadas no meio do cadastro) | No cadastro conversacional do WhatsApp, entre gravar peso/altura/atividade e chamar define_protocolo, a camada determinística continua chamando o TDEE de 'meta do dia' — o mesmo número dos quatro relatos. Evitar a fala errada depende de o LLM chamar define_protocolo antes de dizer o número. Roberto… |
| Metas, treino e planos | alta | 4 (C2-33, C3-37, C3-38, C5-17) | — | Meta de proteína: fator g/kg errado, zerado ou diferente do pedido (regra final: 1,5 g/kg fixo na recomposição) | A regra de 1,5 g/kg só está garantida no default do código. Em qualquer ambiente montado pelas migrações — e no staging medido em 01/10/2026 — a meta volta a 1,8–2,0 g/kg. Em produção depende de uma linha editada à mão, sem migração nem teste (os cards de junho com 149 g para ~99 kg indicam 1,5 lá)… |
| Metas, treino e planos | alta | 2 (C6-28, C6-30) | — | Foto do app de exercício: usar as kcal mostradas na foto e somar todos os exercícios | Sem teste para estimated_kcal_from_image (uso do valor da foto e descarte fora de 10–300%) e sem fixture do print de 08/05. Dois exercícios do mesmo tipo na mesma foto/mensagem perdem o segundo por desenho da idempotência. Se a foto não for lida como app de treino, o valor cai na fórmula, que para… |
| Metas, treino e planos | alta | 2 (C2-34, C6-62) | — | Plano alimentar entregue sem perguntar número de refeições e o que o usuário costuma comer | Não existe etapa determinística de perguntas antes da dieta; se houver regra, está só no prompt gravado no banco (fora do repositório). As observações do C6-62 seguem possíveis: plano com total 10% acima da meta (1.275 contra 1.159) é aceito pela tolerância de ±15%. |
| Metas, treino e planos | alta | 1 (C3-05) | — | Meta de redução de gordura imposta a quem já está na faixa normal, antes de escolher o protocolo | O código continua gerando meta de redução (10%) para quem tem 12% de gordura antes de o protocolo ser escolhido. A meta deveria depender do protocolo escolhido e da decisão explícita do usuário. O mesmo ocorre no caminho de IMC: IMC 24,8 recebe meta 23 (C6-67). |
| Bloco 7.700 e card do dia | alta | 3 (C5-29, C5-31, C5-35) | — | Agente troca o déficit de ontem pelo acumulado do bloco e não mostra a conta (977; 1.629) | Não há fonte determinística para 'balanço de ontem' no chat nem para explicar a conta; o bom dia não tem trava de magnitude. consulta_resumo_periodo devolve avgNetBalance (saldo contra a meta, sem os 500) descrito como 'média do déficit do dia' (tools.ts L3203; packages/core/src/engine/aggregates.t… |
| Bloco 7.700 e card do dia | alta | 2 (C7-28, C7-45) | — | Bom dia com saldo do bloco errado (5.254 → 5.029; 756 + 479 → 2.958) | A frase do C7-28 passaria hoje sem correção se a IA a escrevesse de novo: falta golden com essa frase e padrão para 'saldo de N kcal no bloco de 7.700'. O bom dia continua sendo texto da IA; o número do bloco só é corrigido quando a frase casa com os dois padrões existentes. |
| Bloco 7.700 e card do dia | alta | 0 () | — | Ganho de massa/manutenção: bloco desabilitado, mas comer abaixo da meta é creditado como déficit | Para ganho de massa e manutenção, comer abaixo da meta e treinar enchem um bloco de 7.700 que o próprio contrato marca como desabilitado; o app mostra esse bloco e o bom dia pode chamar o dia de 'déficit'. Nenhum teste cobre protocolo não-recomposição abaixo da meta. |
| Infraestrutura e lembretes | alta | 3 (C3-09, C3-49, C5-01) | ambos | Limite de iterações do agente ('Agent stopped due to max iterations.') | A mensagem técnica não volta, mas a condição que a gerava (limite de iterações atingido) hoje deixa o paciente do WhatsApp sem texto nenhum e gera erro 502 no app. O comentário do teste registra que o Flow de staging roda com max_tool_iterations = 2, o que torna o esgotamento mais provável. Sem tes… |
| Infraestrutura e lembretes | alta | 1 (C1-29) | ambos | Texto interno enviado ao paciente (marcação de chamada de ferramenta / raciocínio do agente) | Não há guarda que impeça marcação de ferramenta, JSON ou narração interna de chegar ao paciente, nem teste que trave isso. O aviso 'Peça pro paciente confirmar ou detalhar' continua indo ao paciente no app e no WhatsApp (tools.ts:1624/1654 repassam `calc.user_warnings`). |
| Duplicidade, correção e base de alimentos | alta | 7 (C6-08, C6-14, C6-16, C6-22, C6-38, C6-55…) | ambos | Alimento com 0 kcal 'sem match' | O item exato de C6-14/C6-22 ('leite com whey') continua sem cálculo no catálogo verificado, e a regra pedida pelo Roberto (estimar em vez de perguntar) não vale para compostos, 'whey', preparo ambíguo e produtos com código. A diferença para os prints é que o item não entra mais como 0 kcal: a propo… |
| Duplicidade, correção e base de alimentos | alta | 3 (C6-34, C6-43, C9-32) | ambos | Valor absurdo ainda reproduzível (achocolatado 760 kcal, mix de folhas 120 kcal, calabresa) | Os três valores dos relatos saem iguais ou piores hoje na simulação. A associação específica com 'pizza de calabresa' não acontece mais, mas a calabresa continua com carboidrato alto e proteína baixa. Outros valores absurdos na mesma simulação: 'coca-cola' 250 ml → 375 kcal com 17,5 g de proteína;… |
| Duplicidade, correção e base de alimentos | alta | 2 (C6-73, C6-72) | ambos | Remover item de refeição já registrada / desfazer registro duplicado | Não há caminho para tirar um item ou uma refeição já gravada: no WhatsApp o item removido fica (ou a operação é bloqueada pedindo 'confirmação explícita' que nenhum código trata); no app não existe editar/excluir refeição confirmada. Quando o total está errado por duplicata (C6-72), o agente não te… |
| Duplicidade, correção e base de alimentos | alta | 2 (C6-24, C8-56) | ambos | Correção feita mais de 30 min depois do registro (soma de novo ou é recusada) | No cenário exato do print 'replace soma tudo' (correção uma hora depois) o código atual ou soma de novo (quando o LLM não marca replace) ou recusa a correção (quando marca). Nenhum teste usa os tempos e valores do print (1.292 → 1.562). Não existe forma de corrigir uma refeição depois de 30 min, ne… |
| Duplicidade, correção e base de alimentos | alta | 2 (C8-49, C8-55) | whatsapp | Depois de 'Editar', registra versão antiga ou só o item novo | Sem tratamento determinístico: se depois do Editar o paciente manda só o item novo com quantidade ("150 ml de suco de uva integral") e o LLM chama a tool só com ele, grava direto e os itens em edição se perdem (C8-49: 83 kcal em vez de 416); se o texto tem uma quantidade por item e o LLM reenvia gr… |
| Duplicidade, correção e base de alimentos | alta | 2 (C9-13, C9-08) | ambos | Frango: retirar a pele ou trocar o preparo dá valor incoerente | Com o catálogo verificado o teste do caso 'sem pele' não se sustenta: a versão sem pele sai mais calórica que a versão sem menção. O frango frito no feminino cai na estimativa de frango simples e fica abaixo do assado. |
| Duplicidade, correção e base de alimentos | alta | 1 (C6-42) | whatsapp | 'Adicionei X' re-lista a refeição inteira e soma tudo de novo | O resultado depende de o LLM mandar só o item novo; a camada determinística não segura a re-listagem (e o gatilho 'adicionei' ainda desliga a dedup por nome+gramas). No app o problema não existe nesse formato: adicionar um item é uma nova proposta só com ele. |
| Duplicidade, correção e base de alimentos | alta | 1 (C8-37) | whatsapp | Kcal informada pelo paciente ignorada ("rap 10 : 70 calorias") | O teste cobre a frase curta, não a mensagem real de três itens; com ela o valor informado é atribuído ao alimento errado. No app o contrato aceita user_kcal por item (registration-service.ts:86-100); não verifiquei a tela. |
| Duplicidade, correção e base de alimentos | alta | 1 (C8-35) | ambos | Segunda porção do mesmo alimento não entra na soma | No WhatsApp o caso está coberto quando o paciente escreve 'segunda fatia', 'mais um' etc.; sem essa frase (segunda foto do mesmo alimento em 30 min) vira correção e substitui. No app não há texto de intenção: repetir o mesmo alimento com as mesmas gramas nunca soma (substitui em 30 min, é descartad… |
| Cadastro | media | 4 (C1-08, C2-15, C2-25, C2-55) | — | Pergunta do nível de atividade sem as faixas de frequência (ou com faixas erradas) | As referências de cada nível não estão fixadas em lugar nenhum: faltam na tela do app e dependem do modelo no WhatsApp. |
| Cadastro | media | 2 (C3-46, C7-52) | — | Gordura corporal muda a cada cadastro com as mesmas fotos e tende a sair para cima (pedido: assumir o menor valor da faixa) | Pedido do Roberto de 27/05 não implementado no código. O prompt de visão pode estar sobrescrito no banco (gemini.ts:519, cfg.prompts.body) — não verificado. |
| Cadastro | media | 2 (C3-26, C6-58) | — | Perguntas que o Roberto disse não fazerem parte do cadastro continuam no fluxo (consumo de água; estruturação alimentar) | As duas perguntas são feitas de propósito hoje. Um comentário de código atribui ao Roberto, em 01/06/2026, o pedido de botões para água e alimentação organizada (onboarding-button.ts:2-5), o que sugere decisão posterior — comentário não é prova: confirmar com ele se a retirada da água (21/02) e a q… |
| Cadastro | media | 1 (C3-01) | — | Margens de entrada dos protocolos sem interseção (ganho só com BF ≤ 19%/27% e IMC ≤ 24) | A margem 'IMC ≤ 24' da tabela corrigida em 02/02 não está no código: quem tem IMC entre 24 e 25 sem BF pode escolher ganho de massa. Os valores de borda (19, 20, 24, 25) não têm teste. No app nenhuma dessas margens é aplicada (ver família da escolha de protocolo). |
| Cadastro | media | 1 (C4-15) | — | Agente não informa a previsão de tempo para atingir a meta (avaliação inicial e reavaliações) | Pedido de 26/03 sem tratamento em código: nem a avaliação inicial nem a reavaliação informam, por conta própria, quando a meta da normalidade deve ser atingida. |
| Refeições (foto, texto, áudio) | media | 1 (C8-19) | whatsapp | Refeição por texto com gramas gravada direto, sem o botão de confirmar | Se a expectativa é ver 'Confirma?' sempre, o WhatsApp continua gravando direto todo texto com gramas; é decisão de produto pendente, não falha de execução. |
| Tom, persona e diversos | media | 3 (C9-03, C9-16, C9-33) | whatsapp | Comentário pós-treino manda aumentar duração/intensidade e chama o treino de "sessão mais curta" | O prompt atual ainda induz 'da próxima, faça mais' e nada bloqueia; falta o elogio genérico pedido pelo Roberto. |
| Tom, persona e diversos | media | 2 (C6-57, C8-02) | ambos | Comentário de educação alimentar/engajamento não vem após o registro | No app, para onde o produto está indo, não há comentário de educação nem de engajamento após refeição ou treino; no WhatsApp o comentário pode faltar em silêncio. |
| Tom, persona e diversos | media | 2 (C9-02, C9-15) | whatsapp | Frase "Boa escolha pra refeição prática…" em almoço completo | O código não tem tratamento para frase que não combina com a refeição e não foi possível verificar no banco se a frase ainda está ativa. |
| Tom, persona e diversos | media | 1 (C6-04) | ambos | Estimativa de gordura corporal por foto (valor fechado, não usa o menor da faixa, não reflete a queda) | O código faz o contrário do pedido (média em vez do menor valor, número fechado em vez de faixa) e não considera a evolução; a resposta do Eduardo foi em áudio não ouvido, então a regra combinada é desconhecida. |
| Tom, persona e diversos | media | 1 (C9-36) | whatsapp | Comentário no estilo antigo, fora do banco de frases combinado (elogio + "Da próxima, reduz…") | Para alimento sem frase no banco o agente ainda escreve comentário próprio no formato antigo; o teste cobre só o descarte da frase moralizante, não a origem do texto. |
| Bloco 7.700 e card do dia | media | 1 (C8-52) | — | Bom dia sem os valores do bloco em andamento e sem os blocos de 14 dias (manutenção/ganho de massa) | Bloco de 14 dias no bom dia: sem implementação. Valor do bloco de 7.700 no bom dia: não é garantido, depende de a IA usar a linha. |
| Infraestrutura e lembretes | media | 3 (C5-41, C6-35, C7-34) | whatsapp | Mensagem automática cobra refeição que já foi registrada ('o café passou batido') | A frase falsa ainda pode sair para quem tem lembrete de intervalo ligado (não consegui verificar no banco quem tem). O pulo do engajamento não tem teste. No app esta família não se aplica da mesma forma: a notificação local tem texto fixo ('Lembrete de refeição — Toque para ver o que está programad… |
| Infraestrutura e lembretes | media | 3 (C8-38, C8-47, C8-57) | whatsapp | Lembrete de fechamento dispara com refeição aguardando confirmação, antes do jantar ou com registro de 0 kcal | Os três cenários ainda podem acontecer; nenhum tem teste. No app não existe este lembrete (o servidor só envia por WhatsApp; para paciente sem número o envio falha e nada é marcado). |
| Infraestrutura e lembretes | media | 2 (C8-13, C8-24) | ambos | Reavaliação de 14 dias no agente atual: não disparou no dia esperado / pediu de novo no dia seguinte | Paciente que registra o café cedo ou não toma café pode ficar sem o pedido de reavaliação indefinidamente; sem teste. No app o pedido do WhatsApp não chega (engagement-sender.ts:55 exige número); existe lembrete local na data de `next_reevaluation` (LocalReminderPlanner.swift:170-189; teste Swift '… |
| Infraestrutura e lembretes | media | 1 (C7-12) | whatsapp | Primeira mensagem do dia enviada como áudio | Se a chave não estiver em 0 no banco de produção (não verificável aqui) e a credencial de voz estiver ativa, cerca de 1 em cada 4 mensagens da manhã sai em áudio, sem o balanço escrito. O padrão do código contraria a decisão. |
| Cadastro | baixa | 2 (C1-45, C2-31) | — | Termo 'onboarding' visível ao usuário e pedido de autorização para salvar | A palavra 'onboarding' ainda chega ao paciente nos dois canais (texto fixo no app; modelo no WhatsApp). O pedido de confirmação antes de salvar no WhatsApp depende do modelo e não tem teste. |
| Tom, persona e diversos | baixa | 2 (C1-27, C1-47) | ambos | Termo técnico "onboarding" exposto ao paciente | A palavra continua em textos fixos do app e, no WhatsApp, só o prompt (não verificável aqui) poderia evitá-la. |
| Tom, persona e diversos | baixa | 2 (C6-64, C8-20) | ambos | Sigla "BF" em vez de "gordura corporal" | A frase exata do print ('BF estimado em 22%' / 'BF ≤ 19%') é texto livre do LLM alimentado com 'BF' no contexto e nenhum teste a impede; há ainda um template fixo com a sigla. |
| Tom, persona e diversos | baixa | 1 (C2-17) | ambos | Pergunta de frequência usa "treinar/treinos" em vez de "musculação" | O app pergunta treinos genéricos para um campo que significa musculação, e no WhatsApp nada garante a palavra 'musculação'. |
| Tom, persona e diversos | baixa | 1 (C3-02) | whatsapp | Justificativa "IMC acima do limite para ganho de massa" no fechamento do cadastro | O motivo passado ao LLM continua dizendo 'para ganho de massa'; a frase final é livre, então pode voltar igual ao print. |
| Tom, persona e diversos | baixa | 1 (C6-36) | whatsapp | Avisos de "sem match"/estimativa mostrados ao paciente | O jargão 'sem match' saiu, mas o paciente continua vendo um aviso de valor estimado, agora por decisão de código que contraria o pedido de 10/05; precisa de decisão do Roberto. |
| Tom, persona e diversos | baixa | 1 (C8-30) | whatsapp | Separar a frase de educação da de engajamento e seguir a ordem registro, card, educação, engajamento | Não há mensagem de engajamento separada da educacional, e o card vai depois do comentário, ao contrário da ordem que o relato atribui ao Roberto em 12/06 (confirmar com ele). |
| Tom, persona e diversos | baixa | 1 (C7-38) | whatsapp | Painel: paciente pausada some da lista de conversas e não dá para retomar | Uma paciente pausada há mais de um ou dois dias continua sem aparecer na lista nem no filtro de pausadas; só é alcançável por endereço direto. |

### Rule divergence: needs Roberto — 4 families, 5 reports

| Area | Sev. | Reports | Channel | Family | What is still wrong or unproven |
|---|---|---|---|---|---|
| Metas, treino e planos | alta | 1 (C3-03) | — | Degrau intermediário de IMC 30 para quem está acima de 30 (regra de reduzir 5 ou 10 pontos até a normalidade) | O código implementa a versão antiga do manual (alvo fixo em IMC 30), que o Roberto disse ter retirado. Existem duas versões da regra do cliente (5 pontos no manual exportado; 10 pontos na fala de 07/02) e o código não segue nenhuma. Precisa da decisão do cliente e, depois, código + teste + doc. |
| Metas, treino e planos | alta | 1 (C4-05) | — | Exercício no balanço de ganho de massa e manutenção (cliente: não entra; doc e código: entra) | A regra de 09/03 para ganho de massa e manutenção não está no doc nem no código; o doc (revisão 23/07) só registra decisões do Roberto sobre recomposição. packages/core/src/engine/protocols.ts:4-6 diz que hoje nenhum paciente usa esses protocolos. Precisa da decisão do cliente antes de ligar ganho/… |
| Bloco 7.700 e card do dia | alta | 3 (C7-27, C7-40, C7-41) | — | Déficit do dia comunicado sem os 500 embutidos na meta (332 em vez de 832; 397 em vez de 897) | Nos dois dias reclamados (excedente de comida acima de 100 kcal com treino) o bom dia segue outra regra: fala do excedente e proíbe 'déficit', em vez do déficit real definido pelo Roberto. Dia com refeição pulada confirmada ('user_skipped', como o 19/05 no teste de paridade) nunca recebe 'FECHOU OK… |
| Bloco 7.700 e card do dia | alta | 0 () | — | App mostra 'Déficit líquido' = saldo contra a meta (−332), não o déficit real do dia (832) | No app o mesmo dia aparece como 'Déficit líquido −332 kcal' enquanto o bloco sobe 832. Falta decidir entre renomear a linha (é saldo contra a meta) ou expor o déficit real no contrato do app. |

### Needs a real run — 46 families, 125 reports

| Area | Sev. | Reports | Channel | Family | What is still wrong or unproven |
|---|---|---|---|---|---|
| Cadastro | alta | 5 (C3-06, C3-25, C3-27, C3-45, C3-47) | — | Gordura acima do limite classificada como 'normal' ou 'Aceitável', com contradição na mesma conversa | Nada impede o modelo de voltar a dizer 'aceitável/normal' na análise das fotos e 'acima do limite' no resumo; sem teste do texto; valores 22% e 23% não têm teste próprio. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi… |
| Cadastro | alta | 3 (C1-30, C2-04, C3-04) | — | Cadastro trava, não conclui ou só continua quando o usuário manda 'ok' | No WhatsApp a continuação depende do modelo terminar cada fala com a próxima pergunta; sem teste. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Responder até a última pergunta ('Durmo às 22:30 e acord… |
| Cadastro | alta | 2 (C3-36, C6-11) | — | Foto corporal sem resposta ou 'não consegui analisar' durante o cadastro | Não dá para provar por código que uma foto nítida é sempre lida nem o tempo de resposta; sem teste do cadastro com fotos em sequência. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. No pedido de fotos,… |
| Cadastro | alta | 2 (C2-51, C5-53) | — | Perguntas e mensagens repetidas em sequência (loop) | Sem teste do cadastro por WhatsApp; a repetição só aparece em execução real. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Fazer o cadastro respondendo 'Leve' ao nível de atividade, 'Moderada' à fome… |
| Cadastro | alta | 1 (C2-24) | — | Peso '101' interpretado como pontos de XP | Comportamento do modelo; sem teste com a resposta '101'. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Quando o agente perguntar 'Qual seu peso atual em kg?', responder apenas '101'. → 'Registrei 101… |
| Cadastro | alta | 1 (C2-43) | — | Perguntas que definem o déficit com opções inventadas e pergunta inexistente (comprometimento de 1 a 10) | O questionário do manual tinha 5 perguntas; o código só guarda fome e estruturação alimentar (o déficit sai só da fome). No WhatsApp o enunciado e as opções exibidas dependem do modelo; no app o título é 'Fome ao longo do dia', não a frase do manual. Teste: Preparação: zerar o número de teste em Ad… |
| Refeições (foto, texto, áudio) | alta | 8 (C7-48, C7-62, C7-68, C8-03, C8-05, C8-12…) | ambos | Itens da foto identificados errado, inventados ou faltando | O acerto da visão em prato real não é provado por nenhum teste; Roberto relatou melhora em 12/06 e novo erro em 06/07 (couve-flor no lugar de torta de frango). Teste: As duas fotos do almoço de 30/05 (prato: risoto com queijo ralado e fraldinha assada; salada: alface, tomate cereja, milho e molho)… |
| Refeições (foto, texto, áudio) | alta | 2 (C6-13, C8-27) | ambos | Foto nítida não reconhecida no pipeline atual (agente pede para descrever) | Nenhum teste usa foto real; docs/handoffs/2026-10-04-performe-ios-e2e-iphone-round-1.md declara refeição por foto NÃO executada na rodada 1 do iPhone. Teste: No app (Registrar > Refeição > Tirar foto) e no WhatsApp de homologação: foto nítida do café do print de 06/05 — pão francês com ovo mexido,… |
| Refeições (foto, texto, áudio) | alta | 1 (C7-49) | ambos | Quantidade dos alimentos da foto superestimada | O viés para cima relatado 'desde o começo' nunca foi medido e o redutor de 10–20% sugerido não foi implementado. Teste: Pesar na balança e fotografar 5 pratos (ex.: 100 g de arroz branco cozido, 120 g de frango grelhado, 30 g de farofa, 1 pão francês de 50 g, 200 ml de leite). → Erro por item dentr… |
| Refeições (foto, texto, áudio) | alta | 1 (C6-32) | whatsapp | Quantidade dobrada em refeição por texto (1 sanduíche virou 2) | No WhatsApp a porção dobrada pode voltar a aparecer na proposta; nenhum teste usa a frase do sanduíche. Teste: Texto: '1 sanduíche de pão bola com frango empanado grelhado na air fryer com milho e tomate'. → Proposta com um pão bola (≈ 50 g), frango ≈ 120 g, milho e tomate em porção de recheio, tot… |
| Metas, treino e planos | alta | 4 (C1-38, C1-OBS-03, C1-OBS-05, C4-22) | — | Agente escreve números que não vêm do cálculo salvo (metas genéricas 2.400 kcal/150 g, meta do cadastro diferente da meta do balanço, duas… | Não há substituição determinística de meta dita em prosa fora do card. O validador não captura número com ponto de milhar nem a forma 'Meta calórica diária: X'. A classificação do IMC ('38,8 = Sobrepeso') não tem função no código; é rótulo do LLM. Só um cadastro real mostra se o plano inicial sai c… |
| Metas, treino e planos | alta | 2 (C8-10, C8-23) | — | Dois exercícios na mesma mensagem de texto e só o primeiro é registrado | Nenhum teste reproduz 'fiz 45 min de musculação e 19 min de bicicleta' gerando dois registros, e a proposta por botão não comporta dois treinos. Teste: WhatsApp, uma única mensagem de texto: 'fiz 45 min de musculação e 19 min de bicicleta' (repetir com 'fiz 40 min de musculação e 18 min de bike').… |
| Metas, treino e planos | alta | 1 (C1-23) | — | Agente contesta a meta calculada ('déficit muito agressivo') e negocia outra meta com o usuário | Comportamento de texto do LLM, sem guarda nem teste. Metas baixas continuam saindo do cálculo (ex.: 980 kcal da Raphaela em C6-67), que é a situação em que o modelo tende a contestar. Teste: Cadastro: mulher, 41 anos, 158 cm, 67,8 kg, sem fotos, fome moderada, recomposição. → O agente informa 1.059… |
| Metas, treino e planos | alta | 1 (C4-07) | — | Sugestões que priorizam fechar a proteína e estouram a meta calórica | Nenhuma guarda impede o LLM de sugerir refeições que somem acima do 'Restam' para fechar a proteína, nem de pedir ajuste em refeição já comida; as mensagens de engajamento também são do LLM. Sem teste. Teste: Recomposição com meta 1.923 kcal e proteína 190,8 g; dia com 1.247 kcal e 89 g registrados… |
| Metas, treino e planos | alta | 1 (C6-07) | — | Resposta sobre hábito alimentar (para montar o plano) tratada como refeição consumida | Sem guarda e sem teste com a troca exata ('o que você costuma comer no café da manhã?' → 'Leite com whey, ovo mexido com queijo sem óleo, pão francês e geleia de morango'). Teste: Pedir um plano alimentar; quando o agente perguntar 'o que você costuma comer no café da manhã?', responder 'Leite com… |
| Bloco 7.700 e card do dia | alta | 8 (C2-39, C3-15, C3-19, C3-32, C3-33, C4-03…) | — | Primeira mensagem do dia sem o balanço de ontem, sem o bloco ou com erro de ferramenta | Só um envio real mostra se a primeira mensagem do dia traz o balanço de ontem e o bloco. Se o paciente escrever antes do bom dia, o agente não tem de onde tirar o balanço de ontem. Teste: Fechar um dia completo (3+ refeições, dentro da meta, com treino) e esperar a primeira mensagem do dia seguinte… |
| Bloco 7.700 e card do dia | alta | 3 (C5-63, C8-14, C8-15) | — | Bloco de 7.700 fechado sem aviso nem celebração | A celebração depende da IA e, em dia com excedente de comida acima de 100 kcal (caso exato do C8-15), o prompt se contradiz e a guarda pode apagar o aviso. C5-63 é do fluxo n8n antigo. Teste: Roberto: bloco 7.397, fechar o dia com 1.831/1.843 e 597 de exercício. Luciana: bloco 7.282, fechar com 1.3… |
| Infraestrutura e lembretes | alta | 1 (C7-51) | ambos | 'Não consegui abrir a foto' — foto não analisada no agente atual | Só uma foto real mostra se o modelo de visão configurado hoje (config no banco, não visível no repositório) devolve algo que o parser lê. Sem teste que fixe a leitura de resposta em bloco de código. Teste: Enviar 3 fotos reais de refeição (JPEG do celular, HEIC e uma foto pesada >5 MB) pelo WhatsAp… |
| Infraestrutura e lembretes | alta | 1 (C6-09) | whatsapp | Meta errada na mensagem proativa (2.500 kcal / 160 g em vez da meta do paciente) | Só a observação de mensagens reais prova que a meta citada é a do paciente. A observação lateral do relato ('8h' numa mensagem que chegou 7:17) hoje usa a hora local (:777). Teste: Comparar, em 10 mensagens da manhã de pacientes diferentes, a meta de kcal e proteína citada com a meta exibida no car… |
| Duplicidade, correção e base de alimentos | alta | 2 (C7-01, C7-05) | whatsapp | Mensagens em sequência (≈1 min) antes da resposta viram refeições separadas ou perdem item | No caso da Erika (foto 06:32, texto 06:33 com itens de nome diferente) o texto vira um segundo turno; o desfecho depende do LLM: unir, criar um pending só com o texto (cancelando o da foto) ou registrar dois. No caso da Amanda, '+ creatina...' e 'Acrescente uma fina fatia de melão' + foto também de… |
| Cadastro | media | 4 (C1-07, C1-44, C1-46, C2-13) | — | Estimativa de gordura pelas fotos sem valor único e claro (um % por foto, dois valores, origem do número) | Nada garante que o paciente receba um número só nem que o número dito seja o agregado salvo; não há teste do texto. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Chegar ao pedido de fotos e enviar fre… |
| Cadastro | media | 4 (C2-02, C2-06, C2-45, C6-63) | — | Frase explicativa padrão de entrada no protocolo não é enviada | Envio da frase completa (meta diária de calorias, blocos de 7.700 kcal, reavaliação a cada 14 dias) depende do modelo; no app não há equivalente da explicação do protocolo. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar '… |
| Cadastro | media | 3 (C1-18, C2-52, C3-44) | — | Várias perguntas na mesma mensagem e resposta atribuída à pergunta errada | Sem regra em código para 'uma pergunta por mensagem' nem teste; a bronca 'você disse Sim mas eu perguntei…' é comportamento do modelo. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Responder '187' à a… |
| Cadastro | media | 3 (C2-57, C5-02, C5-16) | — | Marcador '{nome}' enviado sem substituir nas mensagens finais do cadastro | No WhatsApp o marcador pode voltar a vazar: nenhuma proteção em código e o texto atual da regra no banco não foi verificado. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Concluir o cadastro até as me… |
| Cadastro | media | 1 (C6-06) | — | Déficit de 500 kcal anunciado antes de perguntar o grau de fome | No WhatsApp a ordem pergunta-da-fome → déficit depende do modelo; se ele chamar define_protocolo antes, o sistema calcula com 500 e o número é anunciado. Explicação do Roberto em áudio não ouvida. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_convers… |
| Refeições (foto, texto, áudio) | media | 9 (C7-13, C7-15, C7-17, C7-18, C7-35, C7-69…) | whatsapp | Perguntas em excesso antes de registrar a foto (tipo do alimento, quantidade, qual refeição, molho) | Nenhum teste reproduz os prints do Paulo e a instrução de confirmar itens de baixa confiança conflita com 'é melhor chutar e a pessoa corrigir'. Teste: No perfil do Paulo, sem legenda: foto de café com leite + pão integral com requeijão; foto de almoço com carne escura ao molho, arroz, feijão e doi… |
| Refeições (foto, texto, áudio) | media | 1 (C7-04) | ambos | Agente não consegue ler os números da tabela nutricional da foto e pede para digitar | Nenhum teste lê uma foto de rótulo de verdade; se o OCR falhar o paciente ainda recebe o pedido para digitar os números. Teste: Foto próxima da tabela nutricional de um iogurte com porção de 170 g, com a legenda 'comi 85 g' (no app: foto + ajustar a quantidade para 85 g e ligar 'usar rótulo'). → Pr… |
| Tom, persona e diversos | media | 9 (C5-08, C5-19, C5-20, C5-28, C5-46, C6-51…) | ambos | Abreviações, gírias e anglicismos no texto livre (prot, veggies, boostou, beast, streak, matchou, NEAT, P/C) | Tom e vocabulário dependem do modelo, da temperatura e das regras do banco; sem guarda determinística nem teste que reprove 'prot', 'streak', 'matchou' ou 'NEAT'. Teste: WhatsApp e Flow do app, em pt-BR: (1) registrar '75 minutos de caminhada'; (2) registrar um almoço com arroz, feijão e costelinha… |
| Tom, persona e diversos | media | 4 (C8-17, C8-18, C8-29, C8-31) | whatsapp | Comentário de educação vago ou incoerente (não nomeia o item, sugere troca que não combina) | Nomear o alimento e sugerir troca coerente dependem de o modelo obedecer; os quatro casos do print não têm teste. Teste: WhatsApp, registrar e confirmar: (1) '200 g de frozen iogurte, 20 g de chocolate amargo em gota, 20 ml de calda de chocolate' no jantar; (2) almoço 'frango assado 170g, arroz bra… |
| Tom, persona e diversos | media | 3 (C3-23, C3-39, C3-42) | ambos | Raciocínio interno e marcação de tool call enviados ao paciente | Se o modelo configurado no banco (agent_configs, não versionado no repo) voltar a escrever o raciocínio ou '<tool_call>' como texto, isso vai direto ao paciente; não há guarda determinística nem teste. Teste: Primeira mensagem do dia: 'Oi'. Depois: 'Vou te enviar meu café da manhã' e em seguida 'Le… |
| Tom, persona e diversos | media | 3 (C1-24, C2-56, C4-19) | whatsapp | Rótulos e bastidores internos mostrados ao paciente ("Análise Interna", "mensagens que preciso enviar", "Reforço dopaminérgico") | No WhatsApp depende só do prompt do banco e do modelo; nada no código impede o LLM de rotular um bloco como interno ou de anunciar o que vai enviar. Teste: No WhatsApp, usuário novo: completar o cadastro até a definição do protocolo (perfil do print: homem, IMC acima de 25, musculação 5x/semana) e,… |
| Tom, persona e diversos | media | 2 (C5-56, C5-66) | ambos | Agente se perde no dia da semana | Onde o dia não é informado o modelo pode inventá-lo, e onde é informado nada confere o que ele escreveu. Teste: Numa segunda-feira (fuso do paciente): registrar o almoço, depois perguntar 'que dia é hoje?' no WhatsApp e no Flow; observar também a mensagem automática da tarde. → Nenhuma menção a out… |
| Tom, persona e diversos | media | 2 (C6-02, C6-03) | ambos | Agente muda para inglês ao saber que o paciente mora nos EUA e não volta ao português | Não há guarda que impeça o LLM de trocar de idioma ou de pedir peso em libras; o pedido 'fale em português' depende de o modelo obedecer e chamar a tool. Teste: WhatsApp, usuário novo com DDI brasileiro: responder 'Não, em Orlando, nos EUA' à pergunta de país. Se vier inglês, enviar 'fale em portug… |
| Metas, treino e planos | media | 1 (C1-40) | — | Fotos dos aparelhos da academia não são lidas na montagem do treino | A leitura depende do modelo de visão; não há teste nem confirmação do cliente (o print de 15/01 era da versão n8n). Teste: Durante a montagem do treino, enviar 2 ou 3 fotos de aparelhos (ex.: leg press, halteres, polia). → O agente lista os equipamentos identificados nas fotos e pergunta se faltou… |
| Bloco 7.700 e card do dia | media | 1 (C2-08) | — | Entrada na recomposição sem explicar o bloco de 7.700 kcal | Só lendo as regras no banco ou fazendo um cadastro real dá para confirmar. Não consultei o banco. Teste: Concluir um cadastro que caia em recomposição, no WhatsApp e no app. → A mensagem de entrada explica a meta diária e o bloco de 7.700 kcal (≈1 kg de gordura). |
| Infraestrutura e lembretes | media | 7 (C1-01, C2-22, C7-09, C7-11, C7-16, C7-50…) | ambos | Custo de IA por mensagem (manual inteiro a cada turno, crédito acabando em horas) | Nenhum teste ou alerta fixa um teto de custo por turno, por paciente ou por mês; o audit só informa. O limitador de escopo/uso pedido em C7-11 não existe no WhatsApp (git grep budget/cost_cap/rate limit = só limites de geração de dieta/treino). O custo real por usuário/mês só sai de dados de produç… |
| Infraestrutura e lembretes | media | 2 (C2-41, C6-65) | ambos | Demora para responder | Nada no código garante tempo de resposta; só medição real. C6-65 é ambíguo no próprio relato (8 min pode ser demora da paciente). Teste: Medir 20 turnos reais por canal (texto curto, refeição por texto, foto) do envio até a resposta visível. → Mediana e p95 dentro da meta combinada (ex.: texto <= 2… |
| Cadastro | baixa | 4 (C2-01, C2-16, C2-26, C2-42) | — | Perguntas fora do roteiro no cadastro (atividades praticadas + frequência; quantas refeições por dia) | Roteiro do WhatsApp fica no banco e não pôde ser lido; sem teste. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Fazer o cadastro inteiro. → Não aparecem 'Quais atividades físicas você pratica hoje e c… |
| Cadastro | baixa | 3 (C1-28, C2-12, C2-23) | — | Falta de padrão na forma das perguntas (numeração 'Pergunta 1 de 11', sono em horas, data em formato ISO pedida duas vezes) | Formato e repetição das perguntas no WhatsApp dependem do modelo. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Responder '07/07/1981' à data de nascimento e 'Durmo às 10:30 e acordo 5h' ao sono. → Da… |
| Cadastro | baixa | 3 (C2-47, C2-48, C2-54) | — | Boas-vindas padrão do método e lista de funções não enviadas no início | No WhatsApp depende do modelo e do texto da regra no banco; sem teste. Teste: Preparação: zerar o número de teste em Admin > Mensagens > Resetar conversa (reset_user_conversation_atomic) e mandar 'Oi' pelo WhatsApp. Responder 'Roberto' quando o agente perguntar o nome. → 'Perfeito, Roberto! Seja mu… |
| Tom, persona e diversos | baixa | 1 (C1-OBS-04) | ambos | Markdown bruto no WhatsApp (tabelas com barras, "---" solto) | Sem filtro de saída: tabela em Markdown ou '---' escritos pelo LLM chegam crus; não foi possível confirmar aqui como o WhatsApp exibe o '**' das mensagens fixas. Teste: WhatsApp: pedir 'me mostra minhas metas e macros de hoje numa tabela'. Flow do app: mesma pergunta. → Sem linhas '/ Macro / Quanti… |
| Tom, persona e diversos | baixa | 1 (C1-OBS-06) | whatsapp | Mensagens repetidas ou quase idênticas em sequência | Nada determinístico impede o LLM de repetir a mesma pergunta em parágrafos seguidos, que o humanizador envia como mensagens separadas. Teste: WhatsApp, usuário novo: fazer o cadastro completo respondendo uma pergunta por vez (incluindo 'Musculação 5 x por semana e 20 minutos de bicicleta 4 x por se… |
| Tom, persona e diversos | baixa | 1 (C4-20) | ambos | Saudação fora de hora ("Boa tarde" às 21:45) | Só o prompt orienta a saudação; o LLM pode repetir 'Boa tarde' à noite ou soltar uma saudação no fim da resposta. Teste: WhatsApp e Flow do app, às 21:45 no fuso do paciente: enviar 'Oi' e depois registrar o jantar. → Saudação compatível com a noite ('Boa noite') ou nenhuma; nenhuma saudação solta… |
| Tom, persona e diversos | baixa | 1 (C9-37) | ambos | Conversa com padrão de resposta de bot ("Entendi isso pro seu… Confirma?") — pedido de conversa mais natural no app | Só uma conversa real mostra se o Flow soa natural; hoje o estilo escolhido pelo paciente não altera o tom do chat, e no WhatsApp o padrão reclamado permanece. Teste: Flow do app, com cada estilo (Focus, Impulse, Zen): 'almocei arroz, feijão e frango, como estou hoje?' e 'o que posso jantar?'. → Res… |
| Tom, persona e diversos | baixa | 1 (C1-15) | ambos | Agente adianta as metas seguintes de gordura corporal ao falar da primeira | Nada impede o LLM de falar dos degraus seguintes (18%, 15–18%) ao explicar a primeira meta. Teste: WhatsApp e Flow, homem com 23–25% de gordura corporal em Recomposição: 'qual é a minha meta de gordura corporal?'. → Fala só da meta atual (20%); não menciona 18%, 'checkpoint' nem 'meta final 15–18%'. |
| Metas, treino e planos | baixa | 1 (C1-39) | — | Montagem do treino: várias perguntas enviadas de uma vez | Comportamento do LLM; a instrução do caminho de foto de equipamentos contradiz 'uma pergunta por vez'. Teste: Pedir 'monta um treino pra mim' e responder às perguntas. → Uma pergunta por mensagem (dias por semana, local/equipamentos, limitações, nível), sem lista de oito perguntas. |

### No evidence found — 2 families, 5 reports

| Area | Sev. | Reports | Channel | Family | What is still wrong or unproven |
|---|---|---|---|---|---|
| Bloco 7.700 e card do dia | alta | 2 (C5-54, C7-54) | — | Dia de excedente e o bloco (queixa em áudio não ouvido) | É preciso ouvir os áudios para saber se o pedido era 'o excedente deve descontar do bloco' (o que o código faz hoje) ou outra coisa. Achado à parte: o caminho diário e o recálculo divergem quando um dia ruim é maior que o bloco parcial de quem já tem bloco completo. Probe: bloco 300 com 1 bloco com… |
| Tom, persona e diversos | media | 3 (C3-35, C4-14, C8-11) | whatsapp | Relatos feitos só em áudio (conteúdo desconhecido) | Sem o conteúdo dos áudios não é possível dizer o que foi reclamado nem se foi resolvido. |

### Resolved, not applicable or operational — 105 families, 238 reports

| Area | Status | Reports | Family |
|---|---|---|---|
| Cadastro | NAO_SE_APLICA | 1 (C1-26) | Agente pede o número de WhatsApp com DDD para criar o perfil |
| Cadastro | NAO_SE_APLICA | 1 (C4-24) | Opções duplicadas 'Sedentario' e 'Sedentário' no banco do Notion |
| Cadastro | RESOLVIDO_SEM_TESTE | 2 (C5-15, C6-01) | Paciente já cadastrado é devolvido ao cadastro inicial |
| Cadastro | RESOLVIDO_TESTE_EXATO | 1 (C9-07) | Reavaliação não pergunta quantas vezes o paciente está fazendo atividade física |
| Cadastro | RESOLVIDO_TESTE_VARIANTE | 2 (C1-06, C1-33) | Nome informado vira 'encontrei seu registro' / teste não recomeça do zero |
| Cadastro | RESOLVIDO_TESTE_VARIANTE | 2 (C2-58, C2-60) | IMC exatamente 25,0 tratado como recomposição obrigatória |
| Cadastro | RESOLVIDO_TESTE_VARIANTE | 1 (C9-06) | Reavaliação: fotos enviadas uma a uma não acumulam (pede de novo as já recebidas) |
| Cadastro | RESOLVIDO_TESTE_VARIANTE | 1 (C8-43) | Reavaliação não pergunta o peso ou percentual de gordura que a pessoa quer atingir |
| Cadastro | RESOLVIDO_TESTE_VARIANTE | 1 (C2-29) | Opções de objetivo erradas ('Perda de Peso' não existe no método) |
| Refeições (foto, texto, áudio) | NAO_SE_APLICA | 5 (C1-25, C1-34, C3-10, C3-11, C3-16) | Foto da refeição não lida ou sem resposta no fluxo n8n (max iterations, formato de imagem) |
| Refeições (foto, texto, áudio) | NAO_SE_APLICA | 1 (C2-36) | Agente pergunta se deve registrar a refeição no diário (n8n) |
| Refeições (foto, texto, áudio) | NAO_SE_APLICA | 1 (C5-11) | Áudio do paciente não reconhecido (n8n) |
| Refeições (foto, texto, áudio) | RESOLVIDO_SEM_TESTE | 1 (C6-74) | Agente responde em áudio quando o paciente manda áudio |
| Refeições (foto, texto, áudio) | RESOLVIDO_TESTE_EXATO | 3 (C7-03, C9-25, C9-28) | Rótulo/tabela nutricional legível ignorado: valor genérico do banco usado no lugar |
| Refeições (foto, texto, áudio) | RESOLVIDO_TESTE_EXATO | 1 (C9-26) | Complemento de uma refeição já registrada vira outra refeição (leite em pó adicionado ao iogurte registrado como Almoço) |
| Refeições (foto, texto, áudio) | RESOLVIDO_TESTE_VARIANTE | 3 (C2-35, C3-20, C3-31) | Formato da resposta da refeição: sem detalhe por item, lista repetida, xícara em vez de gramas (n8n) |
| Refeições (foto, texto, áudio) | RESOLVIDO_TESTE_VARIANTE | 1 (C8-40) | Resposta à pergunta sobre a foto tratada como 'pulei': refeição não registrada |
| Tom, persona e diversos | NAO_SE_APLICA | 7 (C1-02, C1-42, C3-13, C4-01, C4-17…) | Inconsistência geral e trocas de modelo/temperatura (era n8n) |
| Tom, persona e diversos | NAO_SE_APLICA | 1 (C3-07) | Tabela de referência no Notion misturando IMC e gordura corporal |
| Tom, persona e diversos | NAO_SE_APLICA | 1 (C3-08) | Fechamento diário sem prompt / zerar as calorias à noite |
| Tom, persona e diversos | NAO_SE_APLICA | 1 (C9-38) | Atraso na entrega do app (não é erro de comportamento) |
| Tom, persona e diversos | NAO_SE_APLICA | 1 (C1-19) | Pergunta de alimentação com o termo "consistente" |
| Tom, persona e diversos | RESOLVIDO_TESTE_EXATO | 1 (C8-32) | Comentário manda reduzir alimento que não estava na refeição (manteiga/óleo) |
| Tom, persona e diversos | RESOLVIDO_TESTE_EXATO | 1 (C9-18) | Registro às 23:19 cai no dia seguinte (card como se fosse dia novo) |
| Tom, persona e diversos | RESOLVIDO_TESTE_VARIANTE | 3 (C4-02, C4-08, C6-29) | Mensagens demais por registro e sugestão/pergunta da próxima refeição sem pedir |
| Tom, persona e diversos | RESOLVIDO_TESTE_VARIANTE | 2 (C4-23, C5-36) | Data da próxima reavaliação vazia ou com ano errado |
| Tom, persona e diversos | RESOLVIDO_TESTE_VARIANTE | 2 (C5-33, C5-58) | Sequência de dias (ofensiva) não conta ou retrocede |
| Tom, persona e diversos | RESOLVIDO_TESTE_VARIANTE | 2 (C9-09, C9-10) | Mesma frase do whey em todo café da manhã (sem variação) |
| Tom, persona e diversos | RESOLVIDO_TESTE_VARIANTE | 1 (C5-25) | Rótulos em inglês na mensagem de progresso (Streak, Badges, Level) |
| Metas, treino e planos | NAO_SE_APLICA | 1 (C5-07) | Reclamação geral: prescrição de treino e de dieta ainda não ajustadas; ninguém chegou aos 14 dias |
| Metas, treino e planos | RESOLVIDO_SEM_TESTE | 7 (C1-03, C1-13, C1-20, C2-10, C2-11…) | Meta de recomposição calculada com fator de atividade/TDEE em vez de BMR × 1,2 − déficit (fórmula no prompt, era n8n) |
| Metas, treino e planos | RESOLVIDO_SEM_TESTE | 2 (C2-30, C2-44) | Déficit da recomposição (400/500/600) definido pelo agente a partir da fome, não escolhido pelo usuário nem por outros critérios |
| Metas, treino e planos | RESOLVIDO_TESTE_EXATO | 5 (C8-09, C8-42, C8-50, C8-59, C9-05) | Mensagem de treino enviada uma vez é tratada como duplicada ('veio duplicado', 'recebi as duas mensagens', exercício em dobro) |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 3 (C2-19, C2-49, C6-05) | Primeira meta no mesmo parâmetro da avaliação (gordura corporal quando há fotos; IMC quando não há) |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 2 (C2-03, C2-37) | Exercício liberando mais comida ou mexendo na meta de calorias do dia |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 2 (C4-05, C4-06) | Balanço do dia e fechamento na recomposição (consumido − (BMR × 1,2 + exercício); campos do fechamento vazios) |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 2 (C1-31, C1-35) | Sugestões das próximas refeições despejadas logo depois de registrar uma refeição |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 2 (C7-29, C7-30) | Reavaliação de 14 dias não disparada e fora do roteiro do manual (peso, 3 fotos, fome) |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 1 (C2-50) | Primeira meta de IMC com redução ínfima (IMC 30,1 → meta 30,0) |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 1 (C6-67) | IMC informado como 23 para usuária com IMC 24,8 |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 1 (C4-21) | Meta de manutenção calculada com fator 1,2 em vez do fator de atividade do usuário |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 1 (C4-16) | Balanço do dia somando calorias 'do dia anterior' |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 1 (C6-27) | Agente diz 'substitui anterior' no primeiro exercício do dia |
| Metas, treino e planos | RESOLVIDO_TESTE_VARIANTE | 1 (C5-55) | Dieta semanal acima da meta de calorias no fim de semana e sem detalhar os dias |
| Bloco 7.700 e card do dia | NAO_SE_APLICA | 5 (C5-24, C5-43, C5-48, C5-51, C5-59) | Fechamento do dia salvo com dado errado ou não creditado (última refeição fora, correção ignorada, dia duplicado, bloco parado) |
| Bloco 7.700 e card do dia | NAO_SE_APLICA | 5 (C1-OBS-01, C5-06, C5-10, C5-12, C5-13) | Consumo do dia não zera na virada do dia e soma dias anteriores |
| Bloco 7.700 e card do dia | NAO_SE_APLICA | 2 (C5-04, C5-21) | Bloco com valores de outro usuário ou sem origem (USER-ID fixo no n8n) |
| Bloco 7.700 e card do dia | NAO_SE_APLICA | 1 (C1-OBS-02) | Resumo do dia com café 'não registrou ainda' e almoço em faixa de kcal |
| Bloco 7.700 e card do dia | RESOLVIDO_SEM_TESTE | 6 (C1-41, C5-26, C6-19, C7-31, C7-36…) | Card perde refeições ou zera no mesmo dia (após treino, após nova refeição, após reset) |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_EXATO | 1 (C7-42) | Déficit do dia ou bloco declarado 'fechado' antes de o dia fechar |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_EXATO | 1 (C7-24) | Bloco diferente em dois cards do mesmo dia (3.000 → 3.794) |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 6 (C5-30, C5-34, C5-39, C5-45, C6-37…) | Bloco 7.700 sem o déficit programado (os '500') e/ou sem o exercício no crédito do dia |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 5 (C2-38, C3-14, C3-21, C3-40, C3-43) | Fórmula do balanço do dia narrada pelo agente (ingestão − exercício; meta − consumo + gasto) |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 4 (C5-44, C6-17, C6-25, C6-26) | Rótulo e formato do card: 'Saldo −X (déficit)', texto corrido, linha de Exercício ausente |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 4 (C5-03, C7-47, C7-66, C8-06) | Mensagem cortada no meio dos números ou tudo em um balão só |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 3 (C1-36, C1-43, C6-40) | Formato da avaliação da refeição (kcal, proteína, carbo e gordura por item, total, comentário) |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 2 (C6-18, C7-33) | 'Restam'/'Saldo' somando o exercício (comida misturada com o bloco) |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 2 (C6-68, C6-69) | Dia sem registro (ou dia do cadastro) creditando a meta inteira no bloco |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 2 (C8-26, C9-01) | Dia incompleto (refeição faltando depois do lembrete) creditou o bloco |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 2 (C6-39, C6-71) | Bloco zerado ou inconsistente (0 / 7.700 depois de correções) |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 1 (C7-58) | Confirmação de refeição com todos os itens em 0 kcal |
| Bloco 7.700 e card do dia | RESOLVIDO_TESTE_VARIANTE | 0 () | App (BFF + iOS): 'Restam para comida' sem exercício e bloco gravado, com exercício só no crédito |
| Infraestrutura e lembretes | NAO_SE_APLICA | 10 (C1-05, C1-10, C1-17, C1-37, C2-40…) | Agente travado ou sem resposta na era n8n (queda do servidor, API da Meta, 'Cliente não cadastrado') |
| Infraestrutura e lembretes | NAO_SE_APLICA | 5 (C3-22, C3-24, C3-28, C3-29, C3-30) | Agente anuncia erro técnico interno ao paciente ('erro ao checar avanço', 'painel de verificação') |
| Infraestrutura e lembretes | NAO_SE_APLICA | 5 (C4-09, C4-11, C4-12, C5-60, C5-61) | Frequência e pertinência das mensagens automáticas (cobra treino sem saber o dia, lanche que o paciente não faz, três cobranças seguidas, sugestão se… |
| Infraestrutura e lembretes | NAO_SE_APLICA | 4 (C3-34, C5-23, C5-32, C5-40) | Primeira mensagem do dia sem o balanço de ontem (pergunta do sono, cobrança de treino) e automáticas que não chegavam — n8n |
| Infraestrutura e lembretes | NAO_SE_APLICA | 2 (C3-12, C3-18) | Timeout ao baixar a foto no n8n (nó GPT-4O / envia.click) |
| Infraestrutura e lembretes | NAO_SE_APLICA | 2 (C3-41, C3-48) | Reset de conversa pelo formulário web do n8n / comando reset_chat |
| Infraestrutura e lembretes | NAO_SE_APLICA | 2 (C5-05, C5-22) | Reavaliação de 14 dias pedida em toda resposta (n8n com perfil fixo de outro usuário) |
| Infraestrutura e lembretes | NAO_SE_APLICA | 2 (C5-42, C5-65) | Mensagem automática afirma sono que o paciente não informou (n8n) |
| Infraestrutura e lembretes | NAO_SE_APLICA | 1 (C2-59) | Mesma resposta enviada duas vezes (n8n) |
| Infraestrutura e lembretes | OPERACIONAL | 6 (C6-50, C7-08, C7-10, C7-44, C7-46…) | Crédito ou limite da chave do OpenRouter esgotado ('Tive um problema agora', mensagens perdidas) |
| Infraestrutura e lembretes | OPERACIONAL | 2 (C6-75, C7-57) | Agente fora do ar por mudança feita direto em produção (troca de modelo, desenvolvedor mexendo) |
| Infraestrutura e lembretes | OPERACIONAL | 1 (C6-49) | Inngest perde o registro das funções após deploy (agente mudo por horas) |
| Infraestrutura e lembretes | OPERACIONAL | 1 (C8-22) | Botão de confirmar não aparece para um paciente (liberação paciente a paciente) |
| Infraestrutura e lembretes | RESOLVIDO_SEM_TESTE | 3 (C5-47, C5-50, C7-07) | Mensagens automáticas fora do horário local do paciente (almoço às 10h, jantar às 17h30, 'Boa madrugada' às 03:07) |
| Infraestrutura e lembretes | RESOLVIDO_SEM_TESTE | 2 (C8-45, C8-46) | Lembrete de fechamento lista cada alimento como se fosse uma refeição separada |
| Infraestrutura e lembretes | RESOLVIDO_SEM_TESTE | 2 (C6-41, C6-54) | Mensagens automáticas em inglês e termo 'streak' |
| Infraestrutura e lembretes | RESOLVIDO_SEM_TESTE | 1 (C7-19) | Sequência de dias conta dias sem nenhuma mensagem do paciente |
| Infraestrutura e lembretes | RESOLVIDO_SEM_TESTE | 1 (C7-20) | 'Bom dia' de engajamento repetido no mesmo dia |
| Infraestrutura e lembretes | RESOLVIDO_TESTE_VARIANTE | 4 (C7-26, C7-60, C8-44, C9-17) | Lembrete de fechamento cobra refeição que foi enviada fora do horário (classificação pelo relógio) |
| Infraestrutura e lembretes | RESOLVIDO_TESTE_VARIANTE | 1 (C5-38) | Virada do dia no fuso errado (refeição das 23:36 de Nova York lançada no dia seguinte) |
| Duplicidade, correção e base de alimentos | NAO_SE_APLICA | 2 (C5-18, C5-57) | Relatos do agente legado (n8n/Notion, abril de 2026) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_SEM_TESTE | 1 (C7-67) | Segunda foto descrita como o item da primeira e somada duas vezes |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 5 (C8-16, C9-04, C9-24, C9-31, C7-06) | Valores divergem entre prévia, proposta e registro |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 4 (C6-33, C6-48, C6-53, C6-70) | Correção feita logo após o registro (até 30 min) soma em vez de substituir |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 3 (C6-15, C6-31, C6-76) | Unidades inadequadas (pó em ml; líquido e ovo em gramas) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 2 (C9-30, C9-14) | Troca de um item re-registra a refeição inteira (itens duplicados) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 2 (C9-11, C6-45) | Refeição nova tratada como correção da anterior |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 2 (C9-20, C9-23) | Mesmo alimento com valores diferentes entre perfis (arroz 150 g = 70 kcal) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 2 (C9-22, C9-34) | Sorvete 120 g = 78 kcal / Nutella 20 g = 30 kcal |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 1 (C9-27) | Correção de kcal de um item apaga outras refeições do dia |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 1 (C6-77) | Itens repetidos na mesma chamada (jantar registrado em dobro) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 1 (C9-19) | Trocar frito por grelhado mantém os mesmos valores |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 1 (C7-39) | 'Corrigido' sem atualizar consumido e restam |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_EXATO | 1 (C7-65) | Confirmação pedida duas vezes (texto livre e depois botão) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 4 (C8-08, C8-41, C8-51, C8-54) | Mensagem única tratada como duplicada / quantidades dobradas |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 3 (C6-21, C7-22, C7-61) | Substituição mexe no dia anterior ou derruba o total do dia |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 3 (C7-21, C7-23, C6-44) | Match errado por semelhança de nome (uva verde→chá verde, carne desfiada→esfiha, arroz refogado 45 kcal) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 2 (C7-37, C9-29) | Foto + texto/legenda da mesma refeição contados em dobro |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 2 (C8-28, C8-33) | Correção de identidade ignorada (ovo cozido volta como frito, feijão preto como carioca) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 1 (C7-63) | Sem pedido de confirmação depois de editar |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 1 (C6-23) | Rótulo da refeição errado (café da manhã registrado como jantar) |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 1 (C7-32) | Falso alerta de treino duplicado |
| Duplicidade, correção e base de alimentos | RESOLVIDO_TESTE_VARIANTE | 1 (C8-25) | Frango à milanesa menos calórico que frango assado |
