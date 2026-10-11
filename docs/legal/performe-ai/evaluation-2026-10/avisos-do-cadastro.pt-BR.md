# Avaliação fechada Performe AI — avisos do cadastro

> **Não são os Termos de uso nem a Política de privacidade definitivos, e não
> passaram por advogado.** São quatro avisos curtos da avaliação fechada, escritos
> só com fatos conferidos no código em 04/10/2026. Não fecham nenhuma pendência
> de `checklist-decisoes.md` nem do `../legal-decision-register.md`.

## Situação

- **Aprovados pelo Eduardo em 04/10/2026** (texto lido no chat; contato "sem
  e-mail", por escolha dele: os participantes sabem como falar com a equipe).
- **Publicados no staging em 04/10/2026** (Supabase `xitugspwfxkcluxvrdeg`),
  conjunto `evaluation-2026-10-a`, idioma `pt-BR`, no lugar do conjunto de teste
  `qa-e2e-v1`, que foi arquivado na mesma transação. Produção não foi tocada:
  os avisos são linhas de dados, não há migration nem seed.
- Substituem os textos de teste que diziam "nenhum dado real de paciente é
  tratado neste ambiente", o que deixaria de ser verdade com avaliadores reais.

| Chave | Título no app | Caixa | Versão | SHA-256 do texto |
|---|---|---|---|---|
| `evaluation_1_terms_notice` | Termos de uso | Aceitar | 04.10.2026 | `651d00d2e037bf1efdf4d17fcd5dfd9658668841cc0fd0d1af024c60f9f7934a` |
| `evaluation_2_privacy_notice` | Política de privacidade | Confirmar ciência | 04.10.2026 | `fe251dafd1cbf11709bc24b1a494e64bd3a9b786fb83ed9900584ba565b6dd5d` |
| `evaluation_3_health_ai_notice` | Saúde e inteligência artificial | Confirmar ciência | 04.10.2026 | `e528f295fe5a8f262bca982db13ce2f47c764394b26252d5935bee66d42d755e` |
| `evaluation_4_sensitive_data_consent` | Dados sensíveis de saúde | Consentir | 04.10.2026 | `7d54069bac1a066df96ffa524d8f5d3685140b2f6e84ca7612a72021c45d8ca0` |

O `content_hash` gravado no banco é esse mesmo SHA-256; o aceite de cada pessoa
fica ligado a ele (`user_onboarding_legal_actions`), com dia e hora.

## Regras para mexer

- Texto, chave, versão e hash são imutáveis no banco. Correção é uma versão
  nova sob a mesma chave (por exemplo `04.10.2026-2`); todos aceitam de novo na
  próxima abertura do app.
- Arquivar o conjunto não devolve o anterior: o cadastro passa a responder 503
  para todos. Voltar atrás é publicar outro conjunto.
- Contas que já tinham concluído o cadastro marcam os quatro avisos de novo na
  próxima abertura a frio; os dados não mudam.
- Só existe conjunto em `pt-BR`. Conta com `users.locale = 'en-US'` não conclui
  o cadastro (o app cria toda conta em `pt-BR`).
- Uma frase só entra se for verdade hoje e tiver prova no código. Se o que ela
  afirma mudar (exclusão a pedido, destino dos dados ao fim da avaliação, acesso
  da equipe), o texto muda antes de valer.

## Os quatro textos, como publicados

### 1. Termos de uso — caixa "Aceitar"

> Esta é uma versão de avaliação do Performe AI. Pode ter erros, ficar fora do ar ou mudar. Estes quatro avisos também são provisórios: ainda não são os Termos de uso nem a Política de privacidade definitivos.
>
> O que você informa nesta versão fica guardado de verdade. No app não dá para excluir a conta, e ainda não há um jeito pronto de apagar seus dados a pedido. Não há garantia de que sejam apagados, nem ao fim da avaliação do app: isso ainda não foi decidido.
>
> O acesso é liberado pela equipe do app e pode ter data para acabar. Depois disso, você não vê mais seus registros no app, mas eles continuam guardados.

### 2. Política de privacidade — caixa "Confirmar ciência"

> O app guarda em servidores de outras empresas o que você informa. Isso inclui e-mail, nome, data de nascimento, dados do corpo, refeições, treinos, planos de dieta e treino, fotos, áudios e a conversa com o Flow.
>
> Textos, fotos, áudios e documentos seus são enviados a serviços de inteligência artificial de outras empresas, que podem estar fora do Brasil. As mensagens ao Flow levam junto dados seus, como nome, peso, altura, metas, registros e a conversa recente. O app não define quanto tempo essas empresas guardam isso nem se usam para treinar seus sistemas.
>
> A equipe do app e as ferramentas de inteligência artificial que ela usa podem ver o que fica guardado, inclusive as conversas.
>
> Dúvidas: fale com a equipe do app.

### 3. Saúde e inteligência artificial — caixa "Confirmar ciência"

> O Flow é um assistente de inteligência artificial. Não é médico nem nutricionista, pode errar e não substitui atendimento médico. Nenhum profissional de saúde revisa o que ele responde ou sugere antes de você ver.
>
> Quando você registra uma refeição por foto, áudio ou texto, a inteligência artificial ajuda a identificar alimentos e quantidades. Ela pode se enganar: revise a lista antes de salvar.
>
> Calorias, proteína e gasto do treino são estimativas. As metas não consideram doenças, gravidez nem remédios.
>
> O app não serve para emergências: não chama socorro nem avisa ninguém. Não mude remédios nem tratamento por causa de uma resposta do Flow.

### 4. Dados sensíveis de saúde — caixa "Consentir"

> Ao consentir, você autoriza o app a guardar e usar, sem data para terminar, seus dados de saúde e do corpo, como peso, altura, percentual de gordura, alimentação e treinos. Vale também para fotos, áudios, documentos e conversas com o Flow.
>
> Esses dados servem para calcular suas metas e os totais do dia, identificar o que você comeu, ler seus planos e gerar as respostas e sugestões do Flow. Para isso, dados de todos esses tipos vão para serviços de inteligência artificial de outras empresas. A equipe do app também pode vê-los para encontrar e corrigir erros.
>
> Depois do cadastro, o app não tem opção para retirar este consentimento. Se mudar de ideia, pare de usar e avise a equipe do app; isso não apaga o que já foi guardado.

## Em que cada frase se apoia

Levantado em 04/10/2026. Linhas de `packages/agent/src/pipeline.ts` podem ter mudado depois.

### 1. Termos de uso

- **"Esta é uma versão de avaliação do Performe AI."** — Descrição simples da avaliação (o dono confirma). Não afirma nada sobre o código.
- **"Pode ter erros, ficar fora do ar ou mudar."** — Descrição simples da avaliação (o dono confirma). Exemplo verificado de falha possível: no banco da avaliação só há configuração ativa do Flow para um objetivo (consulta desta sessão: agent_configs -> ganho_massa active 1; recomposicao archived 2).
- **"Estes quatro avisos também são provisórios: ainda não são os Termos de uso nem a Política de privacidade definitivos."** — Descrição dos próprios avisos (o dono confirma). Dita uma vez, para os quatro, porque os cartões aparecem com os títulos 'Termos de uso' e 'Política de privacidade' (mudança ainda NÃO commitada: apps/ios/BodyFlow/BodyFlow/Features/Onboarding/OnboardingViewSupport.swift:37-67 e Localizable.xcstrings, chaves onboarding.legal.title.*) e a tela de revisão os lista como 'Documentos oficiais' (OnboardingCompletionView.swift:56; já no HEAD). Mesma grafia dos títulos do app.
- **"O que você informa nesta versão fica guardado de verdade."** — Cadastro, registros, conversa, fotos e áudios são gravados no servidor (fatos verificados). Substitui a frase do texto de teste que dizia que nenhum dado real é tratado.
- **"No app não dá para excluir a conta, e ainda não há um jeito pronto de apagar seus dados a pedido."** — Sem exclusão no app: apps/admin/src/app/api/mobile/v1/me/route.ts:10-19 (só GET e PATCH); busca por deleteAccount|excluir conta no app iOS = 0. Sem procedimento pronto a pedido (lido nesta sessão): o registro de aceite recusa DELETE (supabase/migrations/20260915150739_bodyflow_server_owned_onboarding.sql:186-211; staging: gatilho user_onboarding_legal_actions_immutable ativo, FK user_id ON DELETE CASCADE, media_assets ON DELETE RESTRICT); 'apagar paciente' exige master_admin e 'redefinir' exige operations_admin ou master_admin (apps/admin/src/app/(admin)/messages/actions.ts:168 e 213; apps/admin/src/lib/admin-rbac.ts:11 e 30-33) e o ambiente da avaliação só tem content_editor 1 e nutrition_admin 1 (select role, count(*) from admin_users); nenhum código apaga o login (auth.admin: só listUsers). A frase diz que não há caminho pronto; não diz que é impossível nem promete apagar.
- **"Não há garantia de que sejam apagados, nem ao fim da avaliação do app: isso ainda não foi decidido."** — Conversa, cadastro, registros, planos importados e cópias de respostas não têm rotina que apague (chat-01, data-05, media-09). Fotos e áudios recebem data de 30 dias, mas a limpeza não foi comprovada neste ambiente (media-04, 'partly': o conjunto 'media-staging' só tem o processamento de mídia, packages/inngest-functions/src/index.ts:57-73; depende de variável do servidor que não li). Por isso 'não há garantia', e não 'nada apaga' nem 'não há data'. Não existe rotina de fim de avaliação. 'Ainda não foi decidido' vem do enunciado deste trabalho e do checklist do projeto (pendência F7), que não são prova: o dono confirma; se ele decidir antes de publicar, a frase muda.
- **"O acesso é liberado pela equipe do app e pode ter data para acabar."** — O único código que grava liberação de acesso é o webhook de cobrança, e a cobrança no app está desligada (apps/admin/src/app/api/webhooks/revenuecat/handler.ts:148; apps/admin/src/lib/mobile-api/entitlement-service.ts:50-54). Staging: liberações ativas todas com source=manual; 3 válidas hoje, todas com data final (até 2026-10-27). 'Pode ter' porque a coluna access_expires_at aceita ficar vazia (information_schema: is_nullable YES).
- **"Depois disso, você não vê mais seus registros no app, mas eles continuam guardados."** — Sem acesso ativo, toda rota fora de conta, perfil, cadastro, estilo do Flow e preferências responde 402 (apps/admin/src/lib/mobile-api/entitlement-service.ts:6-22 e 58-69; apps/admin/src/lib/mobile-api/route.ts:74). Nenhum código apaga dados quando o acesso vence.

### 2. Política de privacidade

- **"O app guarda em servidores de outras empresas o que você informa."** — Banco de dados, login e arquivos ficam em serviço de outra empresa, a Supabase (third-09; a região é 'partly' e não é citada). A conclusão histórica “Nada disso fica salvo no celular (local-01)” não vale para o candidato iOS A4 de 11/10/2026, ainda não publicado: o cadastro em andamento mantém um rascunho em `Library/Application Support/performe-sign-up-draft/draft.json`. A escrita é atômica, usa proteção completa de arquivo e exclui a pasta do backup; os aceites e o objetivo são retirados da cópia. Código: `OnboardingDeviceDraftStore.swift`. A proteção efetiva com o aparelho bloqueado exige validação no iPhone; o simulador não a prova. Esta atualização corrige a evidência técnica, sem alterar os quatro textos publicados acima nem registrar um novo aceite.
- **"Isso inclui e-mail, nome, data de nascimento, dados do corpo, refeições, treinos, planos de dieta e treino, fotos, áudios e a conversa com o Flow."** — 'Isso inclui' marca que a lista não é completa. E-mail (data-01); nome, data de nascimento completa e dados do corpo: sexo, altura, peso e percentual de gordura (data-02; apps/admin/src/lib/mobile-api/contracts.ts:70-92, relido); refeições, treinos e planos (data-04); fotos, áudios e documentos de plano (media-02, media-07, media-09); conversa (chat-01).
- **"Textos, fotos, áudios e documentos seus são enviados a serviços de inteligência artificial de outras empresas, que podem estar fora do Brasil."** — Envio verificado: mensagens ao Flow (third-01), texto de refeição (third-03), foto (third-04), áudio (third-05), plano importado (third-06); relido em packages/inngest-functions/src/functions/media-asset-processing.ts:362-393 e plan-document-processing.ts:310-352. 'Podem estar fora do Brasil' fica como possibilidade: o código prova só os endereços chamados (packages/providers/src/llm/openrouter.ts:87; vision/gemini.ts:510; stt/groq.ts:33), não o país (third-11, 'partly').
- **"As mensagens ao Flow levam junto dados seus, como nome, peso, altura, metas, registros e a conversa recente."** — packages/agent/src/pipeline.ts (arquivo com edição NÃO commitada; as linhas mudam): no HEAD, 707 (histórico da conversa + mensagem atual vão ao modelo), 2492 (até 50 linhas lidas), 3197-3202 (Nome, Sexo, Idade, Altura, Peso, BF%), 3252 (consumido hoje), 3314 (sequência e blocos), 3331 (orçamento de 14 dias); na árvore de trabalho o histórico enviado ao Flow é cortado para a sessão atual mais as linhas recentes anteriores (mobileFlowPromptHistory). Consultas: packages/agent/src/tools.ts:3555-3584 (médias de 7 ou 30 dias). Sugestão de cardápio: packages/agent/src/tools/plan-proposal-tools.ts:400-411 (alimentos dos últimos 30 dias). 'Como' marca lista não completa. E-mail e telefone não vão (third-02).
- **"O app não define quanto tempo essas empresas guardam isso nem se usam para treinar seus sistemas."** — O pedido enviado leva só modelo, mensagens, temperatura, limite de texto, ferramentas e formato (packages/providers/src/llm/openrouter.ts:160-168); busca por data_collection|zdr|allow_fallbacks|extra_body|provider: { nos pacotes de IA e na API do app = nenhuma ocorrência (refeita nesta sessão). O que as contas nesses fornecedores permitem não é visível no repositório (third-12, 'not_verifiable'): por isso a frase diz o que o app não define e não afirma prazo nem uso.
- **"A equipe do app e as ferramentas de inteligência artificial que ela usa podem ver o que fica guardado, inclusive as conversas."** — Painel administrativo lê o texto das conversas e o perfil com a chave de serviço (apps/admin/src/app/(admin)/messages/page.tsx:59-68 e 191-194; acesso a qualquer papel de administrador: layout.tsx:21-34). Staging: 2 contas em admin_users. Ferramentas: a conexão usada nesta própria sessão entra como 'postgres', com leitura de messages, user_profiles e media_assets e sem a trava por linha (consulta: current_user, has_table_privilege, rolbypassrls). Verdadeiro hoje; se o dono cortar esse acesso antes de entrarem dados reais, o trecho das ferramentas sai.
- **"Dúvidas: fale com a equipe do app."** — Owner statement needed: nenhum contato existe no código nem nos textos do app (busca por 'piperhub' só retorna docs/legal). O dono confirma que cada participante sabe como falar com a equipe e que alguém responde.

### 3. Saúde e inteligência artificial

- **"O Flow é um assistente de inteligência artificial."** — Respostas geradas por modelo de IA (account-08); o app o apresenta como 'Assistente de IA do Performe AI' (Localizable.xcstrings:2499).
- **"Não é médico nem nutricionista, pode errar e não substitui atendimento médico."** — account-08; o app já diz 'não substitui avaliação médica' (Localizable.xcstrings:2451). Não promete que o Flow nunca diagnostica: isso é só instrução ao modelo, sem filtro (account-10).
- **"Nenhum profissional de saúde revisa o que ele responde ou sugere antes de você ver."** — A resposta sai do modelo direto para a pessoa, sem etapa de revisão nem filtro (account-08, account-10); nas sugestões o app diz 'Este plano não foi revisado por um profissional' (account-12; Localizable.xcstrings:2858 e 2874). 'Antes de você ver' limita a frase ao que o código garante, já que o cartão 2 diz que a equipe pode ler as conversas depois.
- **"Quando você registra uma refeição por foto, áudio ou texto, a inteligência artificial ajuda a identificar alimentos e quantidades."** — IA lê texto, foto e áudio de refeição (account-04). 'Ajuda' porque no texto a regra fixa lê primeiro e a IA só entra no trecho restante (apps/admin/src/lib/mobile-api/meal-draft-service.ts:128-152, relido).
- **"Ela pode se enganar: revise a lista antes de salvar."** — Refeição e treino só são gravados depois de a pessoa revisar e confirmar; toda quantidade vinda de foto é marcada como estimativa (account-06). O app usa as mesmas palavras: 'Você revisa os alimentos e as quantidades antes de qualquer cálculo.' (Localizable.xcstrings:3074).
- **"Calorias, proteína e gasto do treino são estimativas."** — Metas por equações populacionais (account-01), gasto de treino por tabela (account-03), alimento por tabela, por semelhança de nome ou média (account-05).
- **"As metas não consideram doenças, gravidez nem remédios."** — O cadastro não pergunta doenças, gravidez nem remédios (account-19; apps/admin/src/lib/mobile-api/contracts.ts:70-92, relido), então as contas não os consideram (account-01, ressalva).
- **"O app não serve para emergências: não chama socorro nem avisa ninguém."** — Não existe recurso nem instrução de emergência no código, nos textos do app nem nas regras ativas do banco (account-11). A frase diz só essa ausência.
- **"Não mude remédios nem tratamento por causa de uma resposta do Flow."** — É um conselho, não um fato. Coerente com account-10: o Flow é instruído a não propor medicamentos nem doses, sem garantia de que toda resposta siga a instrução.

### 4. Dados sensíveis de saúde

- **"Ao consentir, você autoriza o app a guardar e usar, sem data para terminar, seus dados de saúde e do corpo, como peso, altura, percentual de gordura, alimentação e treinos."** — Diz o que é consentido, com dados que o app de fato guarda (data-02, data-04); 'como' marca que a lista não é completa (o cadastro também guarda sexo, data de nascimento, nível de atividade, fome e horários de sono: apps/admin/src/lib/mobile-api/contracts.ts:70-92). 'O app', e não um nome de empresa: nenhuma pessoa jurídica é citada. 'Sem data para terminar' descreve a autorização: o registro do consentimento não pode ser alterado nem apagado (data-03), não há rota de retirada e nada o encerra; não afirma por quanto tempo cada arquivo fica. Manter este cartão como consentimento é decisão do dono; o texto não declara base legal.
- **"Vale também para fotos, áudios, documentos e conversas com o Flow."** — Fotos e áudios (media-02, media-07), documento de plano em foto ou PDF, guardado sem prazo e lido por IA (media-09, third-06; packages/inngest-functions/src/functions/plan-document-processing.ts:310-352), conversa (chat-01).
- **"Esses dados servem para calcular suas metas e os totais do dia, identificar o que você comeu, ler seus planos e gerar as respostas e sugestões do Flow."** — Metas por fórmula (account-01); consumo e balanço do dia (account-02); leitura de refeição (account-04); leitura de plano importado (account-13); respostas (account-08, third-01) e sugestões de cardápio e treino (account-12; packages/agent/src/tools/plan-proposal-tools.ts:380-437). 'Totais do dia' no lugar de 'progresso': no banco da avaliação nenhum dia está fechado (daily_snapshots: 13 linhas, 0 fechadas), então sequência e bloco não andam lá.
- **"Para isso, dados de todos esses tipos vão para serviços de inteligência artificial de outras empresas."** — Peso, altura, gordura, consumo e treino do dia vão com as mensagens ao Flow (third-01; pipeline.ts, HEAD 3197-3202 e 3252); foto (third-04), áudio (third-05), documento (third-06) e conversa vão para leitura ou resposta. 'Todos esses tipos' substitui 'parte deles'.
- **"A equipe do app também pode vê-los para encontrar e corrigir erros."** — Capacidade verificada: painel lê conversas e perfil com a chave de serviço (apps/admin/src/app/(admin)/messages/page.tsx:59-68 e 191-194) e tem marcação de revisão de mensagens (messages/actions.ts:125-134; colunas review_flag e review_note em messages). Que esse é o uso na avaliação: o dono confirma.
- **"Depois do cadastro, o app não tem opção para retirar este consentimento."** — Na tela a caixa liga e desliga (ConsentStepView.swift:114-117); depois de concluído o cadastro não há rota de retirada (busca por revoke|withdraw|revog em apps/admin/src/lib/mobile-api e apps/admin/src/app/api/mobile, sem testes = 0) e o registro recusa UPDATE e DELETE (data-03).
- **"Se mudar de ideia, pare de usar e avise a equipe do app; isso não apaga o que já foi guardado."** — Parar de usar ou sair da conta não apaga nada (local-03, account-16); não há exclusão pronta a pedido (ver cartão 1; account-17 'partly'). 'Avise a equipe do app' é owner statement needed: o dono confirma que a pessoa sabe como falar com a equipe. A frase não promete retirada nem exclusão.

## O que ficou de fora de propósito

- Nomes dos fornecedores (OpenRouter, Groq, Supabase, Vercel, Inngest, Anthropic, Google): verificados no código, mas não dizem nada a um leigo, o modelo é configuração que muda sem mexer no código e a lista não é definitiva.
- Prazo de 30 dias para fotos e áudios (fatos media-03 e media-04): a data é marcada, mas não há prova de que a rotina que apaga está ligada no ambiente da avaliação. O texto diz só que não há garantia.
- Região dos servidores: só o endereço do banco foi conferido (third-09), e a região do servidor do app depende da versão publicada (third-10). Nada foi afirmado.
- 'Com o seu nome' e 'que podem estar fora do Brasil' no cartão 4: ficam só no cartão 2, lido logo antes, para não repetir. Se você quiser o consentimento completo sozinho, a frase do cartão 4 passa a ser: 'Para isso, dados de todos esses tipos vão, com o seu nome, para serviços de inteligência artificial de outras empresas, que podem estar fora do Brasil.' (o cartão 4 iria a cerca de 780 caracteres).
- 'Sem consentir, o cadastro não é concluído.': tirada. O selo 'Obrigatório' já aparece no cartão, e a frase só era exata para conta nova.
- Contas que já existem: no banco da avaliação há 3 contas com aceite dos textos de teste e acesso ativo (só contagens; não vi de quem são). Quem entrar numa delas verá os avisos novos sobre dados já guardados. Decisão sua antes de publicar: os três começam em contas novas, ou o cartão 4 ganha 'Vale também para o que esta conta já tem guardado.'
- 'Ainda não há uma empresa definida como responsável pelo Performe AI.': verdadeiro pelos documentos do projeto, mas documento não é prova, e publicar essa frase é decisão sua. O cartão 4 fala em 'o app', sem empresa.
- Cartão 3, por que revisar: 'Depois de salvo, o registro não pode ser corrigido nem apagado no app.' Verdadeiro (fato health-flow-account-07) e o app já avisa na própria tela. Fora por tamanho.
- Cartão 3, o que fazer na emergência: 'Se passar mal, procure atendimento médico.' É conselho, não fato. Fora por tamanho; o cartão já diz que o app não chama socorro nem avisa ninguém.
- 'Ao aceitar, você confirma que quer usar o app sabendo disso.' (cartão 1) e 'Você pode parar quando quiser': cortadas por tamanho. O cartão 4 já diz 'pare de usar'.
- Remoção de localização das fotos (media-01), o que o app não coleta (localização, contatos, app Saúde, anúncios; local-04, third-13, third-15) e lembretes só locais (local-02): verdadeiro, fora por tamanho. A remoção não vale para áudio de arquivo nem PDF (media-08).
- Preço ou gratuidade (health-flow-account-18), duração da avaliação, número de participantes e data de início: são planos ou decisões suas, não fatos do código.
- Exclusão ou exportação a pedido, prazo de guarda e destino dos dados ao fim: nada foi prometido. O texto diz que não há caminho pronto e que não foi decidido.
- Base legal, nome de lei, direitos, encarregado, empresa responsável, foro e limitação de responsabilidade: fora, conforme os limites dos documentos do próprio projeto. Os quatro textos não passaram por advogado e não fecham nenhuma pendência jurídica do projeto.
- A instrução dada ao Flow (não diagnosticar, não indicar remédio nem dose; health-flow-account-10): é instrução ao modelo, sem filtro; citá-la soaria como garantia.
- Medicamentos e suplementos da rotina (health-flow-account-14): esta versão do app não tem tela para cadastrar esses itens.
- Registro do aceite (data-03): fica gravado com aviso, versão, idioma, dia e hora, e o sistema não deixa apagar. Fora por tamanho. Frase pronta para o cartão 1: 'Fica registrado o que você marcou em cada aviso, com o dia e a hora.'
- Detalhes técnicos: cópias das respostas guardadas pelo servidor (data-05), registros técnicos (chat-02, third-16), código interno da conta enviado junto às chamadas (third-02), fila de processamento (third-08). As frases gerais não os contradizem.
- Ponto de produto, não de aviso: no banco da avaliação só há configuração ativa do Flow para 'ganho de massa' (agent_configs: ganho_massa active 1; recomposicao archived 2). Pela leitura do código, quem escolher outro objetivo recebe erro ao conversar. O aviso não diz que o Flow responde sempre.
- Ponto de produto, não de aviso: nenhum dia está fechado no banco da avaliação (daily_snapshots: 13 linhas, 0 fechadas), então sequência e bloco não andam lá. Por isso o cartão 4 diz 'os totais do dia', e não 'seu progresso'.
- Idade mínima (health-flow-account-19): o app não verifica idade; nada foi dito.
- Qualquer menção ao médico, ao programa ou a fórmulas aprovadas: fora. O cartão 3 diz que nenhum profissional de saúde revisa as respostas antes de a pessoa ver.
- Condições de conduta ('use a conta só para você', 'não informe dados de outras pessoas'): dependem de você; fora.
- 'Se um aviso mudar, o app mostra a nova versão e pede de novo': verdadeiro pelo código (apps/admin/src/lib/mobile-api/supabase-onboarding.ts:481-483 e 544-549), fora por tamanho.
- Aviso de foto e áudio no momento do uso: estes cartões informam no cadastro e não substituem um aviso na hora de fotografar ou gravar.
- Textos do app em volta dos cartões (fora do corpo; este trabalho não altera o app): a tela de revisão chama os quatro de 'Documentos oficiais' e o cabeçalho diz 'Leia cada documento e registre a ação indicada para continuar.'; os títulos 'Termos de uso', 'Política de privacidade' e 'Dados sensíveis de saúde' dependem de mudança ainda NÃO commitada (OnboardingViewSupport.swift, ConsentStepView.swift, Localizable.xcstrings); no HEAD o cartão mostra a chave crua. Sugestão para o build entregue: 'Avisos da avaliação', 'Leia cada aviso e marque a opção indicada para continuar.' e 'Dados de saúde'.
- Versão mostrada sob cada cartão: não faz parte do corpo. Recomendação: '1' nos quatro (lê-se 'Versão 1'; uma correção vira 'Versão 2'). O banco só aceita letras, números, ponto, hífen e sublinhado (supabase/migrations/20260915150739_bodyflow_server_owned_onboarding.sql:40-41).
- Idioma: texto só em português do Brasil. No banco da avaliação só há conjunto publicado em pt-BR; com o app em inglês o cadastro não conclui.
- Tamanho: os quatro corpos somam 2725 caracteres e 472 palavras, cerca de dois minutos de leitura calma, acima do rascunho (2.188). Cartões 1 (617) e 3 (649) ficam dentro de 650; cartões 2 (727) e 4 (732) passam de 650 e ficam abaixo do máximo de 900. Se quiser encurtar sem perder verdade, cortar nesta ordem: (1) o parágrafo do acesso no cartão 1 (cerca de 150 caracteres); (2) 'Calorias, proteína e gasto do treino são estimativas.' no cartão 3; (3) 'e os totais do dia' no cartão 4; (4) o trecho das ferramentas no cartão 2, só se o acesso delas for cortado.

## O que depende do dono

- Contato. 'Dúvidas: fale com a equipe do app.' (cartão 2) e 'avise a equipe do app' (cartão 4): não existe nenhum contato no código nem nos textos do app. Você confirma que cada um dos três sabe como falar com a equipe e que alguém responde durante a avaliação. Se houver um canal que você garante ler, a frase passa a ser 'Dúvidas: escreva para ...'. Sem essa confirmação, não publicar.
- Uso pela equipe. 'A equipe do app também pode vê-los para encontrar e corrigir erros.' (cartão 4) e 'as ferramentas de inteligência artificial que ela usa' (cartão 2): o código e o banco provam que a equipe e as ferramentas conseguem ler; que a leitura é para isso, e quem são as duas contas administrativas do ambiente da avaliação, só você confirma. Se você cortar o acesso das ferramentas ao banco antes de entrarem dados reais, o cartão 2 fica 'A equipe do app pode ver o que fica guardado, inclusive as conversas.'
- Frases que valem enquanto você não decidir (cartão 1): 'ainda não há um jeito pronto de apagar seus dados a pedido' e 'isso ainda não foi decidido' (destino dos dados ao fim). São verdade hoje. Se você definir e testar uma exclusão a pedido, ou decidir o que será feito com os dados, o texto muda antes de publicar.
