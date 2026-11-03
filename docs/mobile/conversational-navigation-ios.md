# Base nativa das quatro abas conversacionais

Este incremento prepara a navegação Flow / Alimentação / Treino / Jornada para QA local. Não ativa o journal de comandos, registro ao enviar, timeline durável, captura nova, execução por exercício, compartilhamento ou recursos sociais. Essas partes de T3–T6 continuam separadas.

## Admissão e versão existente

A apresentação candidata exige simultaneamente build Debug, modo demo, identidade não real e o argumento explícito `--ui-testing-conversational-navigation`. Pode ser exercitada com os argumentos demo já existentes, por exemplo `--ui-testing --ui-testing-prompt14-loaded`. Release, conta real e inicialização sem o argumento continuam com as cinco abas existentes. Não há configuração técnica nova na interface do produto nem alteração de capability no servidor.

`AppTab` mantém os valores `today`, `register`, `plan`, `progress` e `profile`, a ordem legada e seus IDs de acessibilidade. Somente a apresentação opt-in mostra quatro entradas: `today` como Flow, `plan` como Alimentação, `register` como Treino e `progress` como Jornada. O antigo Perfil continua sendo uma tela real acessível pelo botão de perfil; não é uma quinta entrada visível da barra candidata.

## Rotas e telas preservadas

`AppRoute.tab` mantém sua identidade lógica original. `AppNavigationLayout.presentationHost` escolhe o host visual: um push com origem conserva a pilha ativa; sem origem, histórico de atividade vai a Treino e histórico alimentar a Alimentação. Um detalhe de plano aberto em Treino permanece em Treino. O antigo seletor misto Registrar tem entrada explícita `legacyRoot(.register)` e, sem origem, pertence ao Flow, evitando selecionar Treino para uma refeição. Apresentar o sheet de uma refeição não altera a aba.

`AppRouter.openLegacyTab` preserva entradas equivalentes para as cinco raízes antigas. O menu Mais abre o resumo real do dia, o seletor real de registros, todos os planos, a Biblioteca e o Histórico. Links filhos de Perfil, Biblioteca, rotina e histórico continuam carregando suas rotas antigas e conservam a origem ativa. A reavaliação existente permanece na Jornada/Progresso com a mesma capability e as mesmas guardas clínicas; não se fabrica uma nova reavaliação no demo.

Não havia handler de URL ou persistência da aba selecionada no código inspecionado; este incremento não inventa um novo parser de links. O inbox de notificações com dono/validade continua abrindo a rota real de rotina, e o shell continua sendo recriado pela identidade do dono em `AppRootView`. Ao encerrar o shell, o router descarta suas pilhas e sheet; os leitores e o dono mantêm sua invalidação existente.

O tour spotlight antigo depende das cinco abas e dos controles de Hoje. O candidato não o oferece nem mostra o replay correspondente no Perfil; o modo legado mantém seu tutorial. Um tutorial da nova navegação precisa de sua própria qualificação antes de ativação.

## Dados e envio

Alimentação e Treino projetam somente as respectivas partes do `PlanSnapshot` oficial já suportado, preservando valores, campos ausentes e estados de leitura. Todos os planos e rascunhos continuam acessíveis na tela original. Não há alternância Dia/Semana, marcação de execução, carga editável ou saldo novo neste incremento.

O candidato Flow permite consultar o histórico existente, mas não oferece compositor/envio. `ReadOnlyFlowChatRepository` preserva o escopo e a leitura e recusa todo envio ou retry antes de alcançar o provider antigo. A falta do journal não autoriza fallback ao writer do agente legado, nem produz recibo de sucesso simulado. O Flow existente do modo legado mantém seu comportamento.

## Próxima integração

O importador do demo atual é indisponível. Antes de ampliar essa capability no candidato, o callback de sucesso de importação precisa conservar a origem ativa: o fluxo legado ainda substitui a pilha `.plan`. Isso não impede o candidato de navegação com Flow somente leitura, mas não qualifica importação bem-sucedida a partir de Flow/Treino. QA conectado, tutorial novo, performance, regressão nativa integral, dispositivo físico e TestFlight continuam pendentes.
