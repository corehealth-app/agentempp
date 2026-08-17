# Briefing de Produto, Marca, Comunicação e UX — Agente MPP

Data: 2026-07-06
Escopo: produto atual no repositório `/root/agentempp`, documentação local e código disponível.
Uso previsto: base para definir comunicação, naming, identidade visual, público, posicionamento e UX/UI de um futuro app mobile/nativo.

## Como Ler Este Documento

Este arquivo separa três tipos de informação:

- **Evidência do produto atual:** o que aparece em docs, código, rotas, migrations e arquitetura.
- **Interpretação estratégica:** leitura de produto feita a partir das evidências.
- **Recomendação:** caminhos possíveis para marca, comunicação e app. Não é pesquisa de mercado validada.

O documento não inventa dados de mercado, tamanho de audiência, receita, CAC, LTV, churn, NPS ou persona validada. Quando algo depende de decisão de negócio, está marcado como decisão pendente.

## Resumo Executivo

O Agente MPP é, hoje, um **coach nutricional conversacional via WhatsApp** para o método **Muscular Power Plant (MPP)**, ligado à CoreHealth e ao Dr. Roberto Menescal. O paciente registra refeições, treinos e dados corporais por texto, áudio ou foto; o sistema calcula metas, calorias, proteína, exercício e progresso em código; e o agente devolve orientação em linguagem natural.

A proposta central não é "mais um contador de calorias". O valor do produto está na combinação de:

- **Baixa fricção:** o paciente registra no WhatsApp, sem aprender uma interface nova.
- **Acompanhamento contínuo:** lembretes, fechamento diário, reavaliação quinzenal e mensagens de engajamento.
- **Método com regra:** o LLM conversa, mas os números vêm de motor determinístico.
- **Progresso tangível:** o "Bloco 7700" transforma déficit acumulado em um marcador visual de perda de gordura.
- **Operação assistida:** existe um painel admin para acompanhar conversas, pacientes, prompts, auditorias, crons, configurações e crescimento.

Para comunicação e identidade, o território mais forte é: **acompanhamento nutricional diário, humano e preciso, que transforma rotina em progresso real**.

## Fonte Factual Consultada

Fontes principais dentro do repo:

- `package.json`: descrição do projeto como "Agente MPP - Coach nutricional via WhatsApp (CoreHealth)".
- `docs/CONTEXT.md`: cliente, produto, decisões ADR, infraestrutura e glossário.
- `docs/PLATAFORMA-AGENTE-MPP.md`: visão de produto, arquitetura, funcionalidades, banco, motor de cálculo e painel admin.
- `docs/AGENTE-MPP-REFERENCIA-INTEGRACAO.md`: resumo executivo, fluxo de mensagem, stack, workspaces e integrações.
- `docs/CALCULO-MPP.md`: regras canônicas de cálculo, card, bloco 7700 e defesas anti-erro.
- `docs/audits/2026-07-02-full-platform-audit.md`: inventário técnico e achados de plataforma.
- `apps/admin/src/app/**`: rotas e superfícies reais do painel administrativo.
- `apps/admin/src/components/sidebar.tsx` e `command-palette.tsx`: navegação admin atual.
- `apps/admin/src/app/globals.css` e `tailwind.config.ts`: linguagem visual atual do admin.
- `packages/agent/src/**`, `packages/core/src/**`, `packages/inngest-functions/src/functions/**`: pipeline do agente, reavaliação, registros, cálculo, crons e workers.
- `supabase/migrations/**`: schema, tabelas, enums, RLS, crons e dados operacionais.

Limitação importante: este briefing não consulta pesquisa externa de mercado, entrevistas com pacientes, analytics de produto, funil comercial ou métricas comportamentais consolidadas. Qualquer definição de público deve ser validada com dados reais.

## Produto Atual

### Nome Atual

Nome usado no projeto:

- **Agente MPP**
- Produto relacionado à **CoreHealth**
- Método: **Muscular Power Plant (MPP)**
- Persona/método ligado ao **Dr. Roberto Menescal**

O nome atual é funcional e técnico. Ele comunica que há um agente, mas ainda não resolve sozinho uma marca de consumo se o objetivo for um app mobile ou uma comunicação mais ampla.

### Categoria Atual

Categoria comprovada pelo repo:

- Coach nutricional via WhatsApp.
- Agente conversacional multimodal.
- Plataforma operacional com painel admin.
- Sistema de acompanhamento nutricional e treino com cálculo determinístico.

Categoria estratégica recomendada:

- **Acompanhamento nutricional inteligente e diário.**
- **Coach de recomposição corporal com baixa fricção.**
- **Sistema de progresso corporal guiado por método.**

Evitar posicionar apenas como "chatbot", porque isso reduz o produto à interface. O diferencial está no método, no cálculo, no fechamento diário, no acompanhamento e na operação.

### Promessa Funcional

O produto ajuda o paciente a:

- Registrar refeições por texto, áudio ou foto.
- Registrar treinos e exercícios.
- Receber um balanço diário com calorias, proteína, exercício e bloco 7700.
- Entender quanto ainda pode comer ou se excedeu a meta.
- Não perder refeições importantes por esquecimento.
- Fazer reavaliações periódicas com peso, fotos e perguntas do protocolo.
- Ajustar metas e protocolo ao longo do tempo.
- Receber orientação em linguagem natural, sem operar planilhas ou apps complexos.

### Promessa Emocional

O produto oferece:

- Clareza em vez de confusão.
- Presença diária em vez de plano esquecido.
- Correção sem bronca.
- Progresso visível em vez de ansiedade solta.
- Método em vez de improviso.
- Compromisso leve, mas constante.

Uma frase possível:

> Um acompanhamento que não esquece de você e não deixa seus números no achismo.

## O Que o Produto Faz Hoje

### Experiência do Paciente

A experiência principal do paciente acontece no WhatsApp.

Funcionalidades comprovadas:

- Onboarding conversacional.
- Botões e listas interativas do WhatsApp para respostas discretas.
- Registro de refeições por texto.
- Registro de refeições por áudio com transcrição.
- Registro de refeições por foto com análise visual.
- Leitura de rótulos nutricionais por imagem.
- Registro de treino e exercício.
- Card de balanço depois de registros.
- Lembretes de refeição faltante.
- Fechamento diário.
- Reavaliação a cada 14 dias.
- Pedido de peso, fotos de frente/lado/costas e perguntas por protocolo.
- Possibilidade de seguir sem fotos quando o paciente declara isso.
- Mensagens de engajamento.
- Dieta/lista de compras sob demanda.
- Plano de treino semanal sob demanda e entrega diária por cron.
- Voz/TTS em mensagens específicas, conforme configuração.

### Experiência Admin/Operação

O admin atual é um app Next.js hospedado na Vercel.

Áreas comprovadas pela navegação:

- Hoje/dashboard.
- Conversas.
- Pacientes.
- Crescimento.
- Regras/prompts.
- Playground.
- Sub-agentes.
- Tools.
- Avaliações LLM.
- Auditoria.
- Configurações globais.
- Cálculos.
- Fórmulas.
- Banco de alimentos.
- API Keys.
- Stripe.
- Crons.
- Admins.
- Tutorial.

Isso indica que o produto não é só um bot. Existe uma camada operacional para monitorar, configurar, auditar e evoluir o agente.

## Tese de Produto

A tese mais forte do produto é:

> O paciente não precisa virar especialista em nutrição ou tracking. Ele precisa de um sistema que acompanhe, calcule, lembre, corrija e transforme escolhas diárias em progresso corporal visível.

Essa tese deve orientar comunicação, UX, marca e app nativo.

### O LLM Não É o Produto Inteiro

Um princípio central documentado é:

> O LLM conversa, interpreta linguagem natural e escolhe ferramentas; o sistema é dono dos números e da gravação.

Isso é um ativo de confiança. Na comunicação, pode virar:

- "IA para conversar, método para calcular."
- "Conversa natural, números auditáveis."
- "Sem chute nos seus resultados."

Tomar cuidado para não prometer precisão absoluta em fotos e calorias, porque o próprio sistema tem fluxos de confirmação, baixa confiança e correção.

## Método e Regras do Produto

### Protocolos

Protocolos presentes no domínio:

- Recomposição.
- Ganho de massa.
- Manutenção.

Pelo código e docs, recomposição aparece como o protocolo principal em uso e mais detalhado.

### Meta Calórica

Regra documentada para recomposição:

- Meta = `BMR x 1.2 - design_deficit`.
- O TDEE é informativo na recomposição.
- A atividade física não aumenta o quanto o paciente "pode comer".

### Dois Balanços

O produto diferencia:

- **Balanço de comida:** consumido - meta. É o que aparece como "Restam" ou "Excedente".
- **Balanço net/déficit:** consumido - meta - exercício. Alimenta o Bloco 7700.

Essa distinção deve ser traduzida com cuidado na UX. É um ponto onde comunicação errada pode gerar confusão e perda de confiança.

### Bloco 7700

O "Bloco 7700" é um marcador de progresso:

- 7700 kcal representam 1 kg de gordura.
- O bloco acumula déficit líquido.
- Dias bons somam.
- Dias ruins podem descontar.
- Dias incompletos com gap aberto não creditam.

O Bloco 7700 é um dos elementos mais próprios do produto. Ele pode virar pilar de marca, gamificação e visual.

## Diferenciais

Diferenciais comprovados ou diretamente derivados do produto atual:

- WhatsApp como interface principal.
- Registro multimodal: texto, áudio, foto.
- Vision para refeições, rótulos, fotos de corpo, balança e equipamentos.
- STT para áudio.
- Motor determinístico para cálculo.
- Card canônico renderizado pelo sistema.
- Auditoria contra alucinação numérica.
- Ferramentas determinísticas para gravação.
- Bloco 7700 como gamificação de gordura.
- Reavaliação quinzenal.
- Lembretes de refeição faltante.
- Painel admin com operação, prompts, tools, crons e auditorias.
- Configuração de cálculo e prompts em runtime.
- Integrações com WhatsApp Cloud API, Supabase, Inngest, Vercel, Stripe e provedores de IA.

## Público

### Público Primário Provável

Interpretação estratégica a validar:

- Adultos que querem recomposição corporal, perda de gordura ou melhora de forma física.
- Pessoas que já usam WhatsApp intensamente.
- Pessoas que têm dificuldade de manter registro em apps de dieta.
- Pessoas que querem orientação diária sem precisar marcar consulta toda hora.
- Pacientes que se beneficiam de cobrança leve e presença constante.
- Alunos/pacientes de um método ou profissional que já confiam na autoridade do Roberto/CoreHealth.

### Personas Iniciais Recomendadas

#### 1. O Paciente Que Quer Resultado Sem Virar Nutricionista

Necessidade:

- Saber o que fazer hoje.
- Registrar sem atrito.
- Receber correção simples.
- Não estudar tabela nutricional.

Mensagem:

- "Você manda o que comeu. O sistema calcula e te mostra o caminho."

#### 2. A Pessoa Ocupada Que Esquece de Registrar

Necessidade:

- Acompanhamento que lembra.
- Registro rápido por áudio/foto.
- Fechamento diário claro.

Mensagem:

- "Seu acompanhamento cabe na rotina que você já tem."

#### 3. O Paciente Que Treina Mas Não Vê Progresso

Necessidade:

- Conectar treino, comida, proteína e déficit.
- Ver progresso além da balança.
- Ajustar a estratégia a cada ciclo.

Mensagem:

- "Treino, comida e progresso no mesmo sistema."

#### 4. A Operação/Equipe Profissional

Necessidade:

- Monitorar conversas.
- Ajustar prompts e regras.
- Ver quem precisa de atenção.
- Reduzir trabalho manual.

Mensagem:

- "Uma camada operacional para escalar acompanhamento sem perder controle."

### Públicos a Evitar ou Tratar com Cuidado

Por prudência de produto e comunicação:

- Pessoas com transtorno alimentar ativo ou alto risco psicológico.
- Pacientes que precisam de conduta médica/nutricional intensiva.
- Atletas/bodybuilders que exigem precisão extrema de preparo competitivo.
- Usuários que não querem conversar com WhatsApp ou IA.
- Pessoas que buscam solução milagrosa, rápida ou sem esforço.

Não é recomendável comunicar promessa de cura, diagnóstico, tratamento médico ou perda de peso garantida.

## Jobs To Be Done

Jobs principais:

- "Quando eu como, quero registrar rápido para saber se continuo dentro da meta."
- "Quando treino, quero que isso conte para meu progresso sem virar desculpa para comer mais."
- "Quando esqueço uma refeição, quero que alguém me lembre antes de perder o controle do dia."
- "Quando erro ou mando informação incompleta, quero conseguir corrigir sem confusão."
- "Quando fecho o dia, quero entender se avancei ou regredi."
- "A cada ciclo, quero saber se meu corpo está respondendo."
- "Como operador, quero enxergar onde o agente errou ou onde o paciente precisa de atenção."

## Posicionamento

### Território Principal

**Acompanhamento nutricional diário, inteligente e humano, guiado por método.**

### Territórios Secundários

- Recomposição corporal.
- Progresso por consistência.
- Registro sem fricção.
- Coach via WhatsApp.
- Método com dados.
- Nutrição operacionalizada.

### O Que Não Deve Ser o Posicionamento Central

- "Um app de calorias."
- "Uma IA que sabe tudo."
- "Um personal trainer virtual."
- "Um substituto de médico/nutricionista."
- "Uma dieta milagrosa."

## Comunicação

### Voz da Marca

A voz recomendada:

- Clara.
- Direta.
- Humana.
- Técnica quando precisa.
- Sem bronca.
- Sem oba-oba.
- Sem prometer milagre.
- Com energia de treinador, mas sem agressividade.

### Tom do Agente

O tom do agente deve combinar:

- Precisão.
- Calma.
- Incentivo.
- Responsabilidade.
- Praticidade.

Evitar:

- Julgamento moral sobre comida.
- Vergonha corporal.
- Linguagem médica sem respaldo.
- Termos excessivamente técnicos no WhatsApp.
- Excesso de piada quando o paciente está frustrado.
- Frases genéricas de IA que parecem automáticas.

### Frases de Direção

Boas direções:

- "Registra do jeito que der. Eu organizo os números."
- "Sem radicalismo: consistência, proteína e déficit real."
- "O dia não precisa ser perfeito. Precisa ficar claro."
- "Seu progresso não depende de adivinhar. Depende de registrar e ajustar."
- "Foto, áudio ou texto: o importante é não deixar o dia no escuro."

Evitar:

- "Perca X kg em Y dias."
- "Nunca mais erre a dieta."
- "A IA mais precisa do mercado."
- "Coma qualquer coisa e emagreça."
- "Substitui seu nutricionista."

### Mensagem Curta de Produto

Opções:

- **Um coach nutricional no WhatsApp que registra, calcula e te acompanha todos os dias.**
- **Acompanhamento de recomposição corporal com registro por foto, áudio ou texto.**
- **Você manda sua rotina. O MPP transforma em meta, balanço e progresso.**
- **Nutrição com método, conversa natural e números calculados pelo sistema.**

### Explicação em 30 Segundos

O Agente MPP é um acompanhamento nutricional via WhatsApp. O paciente manda refeições e treinos por foto, áudio ou texto; o sistema calcula calorias, proteína, exercício e progresso no Bloco 7700; e o agente orienta o próximo passo. A IA conversa, mas os números são calculados por regras do método, com auditoria e operação por painel admin.

### Explicação Para Landing Page

Registre sua alimentação e seus treinos no WhatsApp, sem preencher app nem planilha. O MPP entende foto, áudio e texto, calcula seu balanço diário e mostra quanto você avançou no Bloco 7700. A cada dia, você sabe o que falta, o que excedeu e como ajustar a rotina sem radicalismo.

## Naming

### Observação Sobre o Nome Atual

"Agente MPP" funciona bem para uso interno e técnico. Para um produto de consumo, pode soar genérico porque "agente" descreve tecnologia, não benefício. "MPP" tem valor se o público já reconhece o método ou o Roberto. Se o público for frio, MPP precisa de explicação.

### Decisão Central de Naming

Antes de escolher o nome, definir:

- A marca principal será **Roberto/Método MPP** ou **CoreHealth**?
- O produto será vendido como **coach pessoal**, **programa de recomposição** ou **plataforma para clínicas/profissionais**?
- O app nativo será extensão do WhatsApp ou produto principal?
- O nome deve parecer mais científico, humano, fitness ou premium?

### Território 1 — Método Primeiro

Bom quando a autoridade do Roberto/MPP é central.

Opções:

- **MPP Coach**
- **Método MPP**
- **MPP Diário**
- **MPP Progress**
- **MPP Core**
- **MPP Companion**
- **MPP 7700**

Forças:

- Preserva equity do método.
- Ajuda a conectar conteúdo, protocolo e app.
- Parece proprietário.

Riscos:

- Precisa explicar o que é MPP para público novo.
- Pode soar interno se a sigla não tiver narrativa.

Recomendação se escolher esse território:

- Usar `MPP Coach` como nome de produto e "Método Muscular Power Plant" como explicação.

### Território 2 — Progresso Primeiro

Bom quando a comunicação quer vender resultado e clareza.

Opções:

- **Bloco**
- **Bloco 7700**
- **Ritmo**
- **Marco**
- **Linha**
- **Saldo**
- **Composição**
- **Trilha**

Forças:

- Mais memorável e visual.
- Aproxima marca da gamificação.
- Pode virar linguagem própria do app.

Riscos:

- "Bloco 7700" exige explicação.
- Alguns nomes são genéricos demais sem qualificador.

Recomendação se escolher esse território:

- `Bloco 7700` é forte como feature proprietária, mas talvez não como nome principal para público leigo. Melhor como pilar visual dentro de uma marca maior.

### Território 3 — Companhia/Coach Primeiro

Bom quando o produto quer parecer próximo e cotidiano.

Opções:

- **CoreCoach**
- **Core Daily**
- **Compasso**
- **Pulso**
- **Núcleo**
- **Base**
- **Prumo**
- **Rota**

Forças:

- Mais amplo que nutrição.
- Funciona melhor para app mobile.
- Dá margem para treino, saúde e evolução.

Riscos:

- Pode perder a autoridade específica do MPP.
- Alguns nomes precisam checagem de marca/domínio.

Recomendação se escolher esse território:

- Se CoreHealth for a marca-mãe, `CoreCoach MPP` ou `CoreCoach` com "powered by MPP" pode equilibrar empresa e método.

### Shortlist Recomendada

Sem pesquisa jurídica ou de domínio, a shortlist estratégica inicial seria:

1. **MPP Coach**
   Mais direto, preserva método e explica a função.

2. **CoreCoach MPP**
   Bom se CoreHealth será marca guarda-chuva.

3. **MPP Diário**
   Enfatiza rotina, hábito e acompanhamento constante.

4. **Bloco 7700**
   Forte como subproduto, campanha ou mecânica visual, mas precisa de educação.

5. **Método MPP**
   Melhor para programa/método do que para app.

## Arquitetura de Marca

### Opção A — Marca-Mãe CoreHealth

Estrutura:

- CoreHealth = empresa.
- CoreCoach = produto.
- MPP = método/protocolo.
- Bloco 7700 = mecânica de progresso.

Boa para:

- Escalar além do Roberto.
- Criar novos produtos no futuro.
- Ter marca institucional mais ampla.

Risco:

- Pode diluir a força pessoal do Roberto se ela for o principal canal de aquisição.

### Opção B — Marca-Mãe MPP

Estrutura:

- MPP = marca principal.
- MPP Coach = produto.
- Dr. Roberto = autoridade.
- Bloco 7700 = mecânica de progresso.

Boa para:

- Produto fortemente ancorado em método proprietário.
- Comunidade em torno do Roberto.
- Comunicação mais direta com pacientes atuais.

Risco:

- Mais difícil separar produto de figura pessoal.

### Opção C — Produto Independente

Estrutura:

- Nome novo = produto.
- MPP/CoreHealth = "por trás".
- Roberto = autoridade/mentor.

Boa para:

- Lançamento D2C amplo.
- App mobile com identidade própria.

Risco:

- Custa mais para construir confiança do zero.

## Identidade Visual

### Linguagem Atual

O admin usa:

- Fontes: Inter para texto, Outfit para display.
- Paleta: cream, ink, moss.
- Visual: cards claros, bordas suaves, estética operacional premium.

Isso serve bem para painel admin: calmo, confiável e legível.

### Direção Recomendada Para Produto/Paciente

A identidade do paciente deve equilibrar:

- Precisão técnica.
- Calor humano.
- Energia de progresso físico.
- Sensação de rotina possível.

Não deve parecer:

- Hospital/clínica fria demais.
- App genérico de dieta.
- Marca agressiva de academia.
- Dashboard financeiro.
- Chatbot experimental.

### Paleta Recomendada

Base possível:

- **Ink:** texto forte, confiança e legibilidade.
- **Cream/off-white:** fundo humano, menos clínico que branco puro.
- **Moss/green:** progresso, saúde, consistência.
- **Accent energético:** coral, lime ou amber para alertas positivos, CTAs e conquistas.

Usar o moss atual como ponte entre admin e paciente. Para o app mobile, adicionar um acento mais vivo para não ficar sério demais.

### Tipografia

Manter Inter/Outfit é coerente:

- Inter: legibilidade em dados, cards, listas e chat.
- Outfit: marca, títulos e momentos de conquista.

Cuidados:

- Evitar títulos gigantes dentro de telas operacionais.
- Usar números tabulares para kcal, proteína, blocos e metas.
- Em mobile, priorizar escaneabilidade.

### Iconografia

Ícones devem representar ações reais:

- Câmera para foto.
- Microfone para áudio.
- Prato/refeição.
- Haltere/atividade.
- Balança.
- Gráfico/progresso.
- Check/confirmar.
- Editar/corrigir.

Evitar ilustrações abstratas demais. O produto depende de confiança nos dados.

### Fotografia e Imagem

Direção recomendada:

- Pessoas reais em rotina comum.
- Refeições reais, não pratos perfeitos de banco de imagem.
- Treino acessível, não estética extrema.
- Progresso corporal tratado com privacidade e respeito.

Evitar:

- Antes/depois apelativo.
- Corpos irreais.
- Fotos escuras ou genéricas.
- Imagem que prometa resultado rápido.

## UX/UI Para App Mobile/Nativo

### Premissa

O produto hoje é WhatsApp-first. Um app nativo não deve simplesmente copiar o chat. Ele deve virar a **camada visual de acompanhamento**, enquanto o WhatsApp continua sendo excelente para entrada rápida e conversa.

Estratégia recomendada:

- WhatsApp = captura, conversa, lembrete.
- App = visão clara do dia, progresso, histórico, ajustes, reavaliação e confiança.

### Home Recomendada: "Hoje"

A primeira tela deve responder:

- Quanto eu já consumi?
- Quanto falta ou excedeu?
- Bati proteína?
- Treinei?
- Meu bloco avançou?
- Tem alguma pendência?
- Qual é a próxima ação simples?

Componentes:

- Card de balanço do dia.
- Barra/círculo do Bloco 7700.
- Meta de proteína.
- Linha de exercício.
- Refeições registradas.
- CTA rápido para registrar.
- Aviso de gap, se houver.

### Navegação Principal

Tabs recomendadas:

- **Hoje**
- **Registrar**
- **Progresso**
- **Plano**
- **Coach**

Alternativa se quiser app mais enxuto:

- Hoje
- Registrar
- Progresso
- Perfil

### Tela Registrar

Deve ser muito rápida:

- Foto.
- Áudio.
- Texto.
- Treino.
- Peso.
- Fotos de reavaliação.

Princípio: o usuário não deve escolher 10 campos antes de registrar. Primeiro captura; depois confirma.

### Fluxo de Refeição

Fluxo ideal:

1. Usuário toca em câmera, microfone ou texto.
2. Sistema interpreta.
3. Mostra proposta: itens, quantidades, kcal e macros.
4. Usuário confirma ou edita.
5. App mostra card atualizado.

Estados necessários:

- Analisando.
- Baixa confiança.
- Precisa confirmar item.
- Registrado.
- Já estava registrado.
- Erro recuperável.
- Correção manual.

### Fluxo de Treino

Entrada rápida:

- Tipo de treino.
- Duração.
- Intensidade, se necessário.
- Calorias estimadas.

UX importante:

- Explicar que treino acelera o Bloco 7700, mas não aumenta "Restam" de comida.

### Fluxo de Reavaliação

Reavaliação quinzenal deve parecer um mini-checkup:

- Peso atual.
- Fotos: frente, lado, costas.
- Pergunta específica do protocolo.
- Frequência de treino/atividade.
- Confirmação de meta.

Estados:

- Pendente.
- Fotos parciais.
- Sem fotos autorizado.
- Em análise.
- Reavaliado.
- Ajuste de meta/protocolo.

UX sensível:

- Fotos corporais exigem privacidade explícita.
- Mostrar quais fotos já foram recebidas.
- Não pedir de novo o que já foi enviado.
- Permitir "seguir sem fotos".

### Tela Progresso

Conteúdo recomendado:

- Bloco 7700 atual.
- Blocos concluídos.
- Peso ao longo do tempo.
- BF estimado/confirmado quando houver.
- Proteína média.
- Dias completos/incompletos.
- Streak.
- Badges/conquistas.
- Reavaliações anteriores.

Cuidado:

- Não transformar tudo em ranking ou punição.
- Dias incompletos devem ser explicados como dado insuficiente, não fracasso.

### Tela Plano

Conteúdo:

- Protocolo atual.
- Meta calórica.
- Proteína.
- Déficit programado.
- Treino/plano semanal, se gerado.
- Dieta/lista de compras, se gerada.
- Próxima reavaliação.

Essa tela é a "fonte de verdade" do paciente.

### Tela Coach

Pode ser:

- Chat dentro do app.
- Atalho para WhatsApp.
- Histórico resumido.

Decisão pendente:

- O app vai substituir WhatsApp no longo prazo ou complementar?

Recomendação:

- No MVP mobile, complementar. Não matar o WhatsApp cedo, porque baixa fricção é diferencial comprovado.

## Princípios de UX

### 1. Captura Antes de Formulário

O usuário deve conseguir mandar foto, áudio ou texto rapidamente. Campos estruturados entram só quando ajudam a confirmar.

### 2. Todo Número Tem Fonte

Quando mostrar kcal, proteína, exercício ou bloco, permitir entender de onde veio:

- Refeições.
- Treinos.
- Meta.
- Cálculo do protocolo.

### 3. Ambiguidade Pede Confirmação

Se a foto ou texto não estiver claro, o app/agente deve perguntar uma coisa específica, não pedir "manda de novo" genericamente.

### 4. Correção Deve Ser Fácil

O paciente precisa corrigir:

- Alimento.
- Quantidade.
- Refeição.
- Kcal informada por rótulo/paciente.
- Treino duplicado.
- Refeição pulada.

### 5. Progresso Não Pode Virar Culpa

O design deve evitar linguagem de fracasso. Um dia incompleto é um dia sem dado suficiente. Um excedente é um sinal de ajuste.

### 6. WhatsApp e App Precisam Concordar

Se o WhatsApp mostra um card, o app deve mostrar o mesmo estado. Divergência entre chat e app destruiria confiança.

## Jornada do Usuário

### Jornada 1 — Onboarding

Objetivo:

- Coletar dados mínimos para calcular metas e protocolo.

Dados citados no produto:

- Sexo.
- Data de nascimento.
- Altura.
- Peso.
- BF%.
- Nível de atividade.
- Água.
- Fome.
- Sono.
- Organização alimentar.
- Frequência de treino.
- Protocolo/meta.

Princípio:

- Fazer perguntas uma por vez.
- Usar botões/listas quando possível.
- Explicar por que os dados importam só quando necessário.

### Jornada 2 — Dia Normal

1. Paciente registra comida/treino.
2. Sistema interpreta.
3. Sistema grava por ferramenta determinística.
4. Card de balanço é renderizado.
5. Lembretes aparecem se há gap.
6. Fechamento diário atualiza progresso.

### Jornada 3 — Correção

1. Paciente percebe erro.
2. Diz "não era isso", "corrige", "tem X kcal", "foi uma sessão só".
3. Sistema detecta correção.
4. Corrige sem duplicar ou apagar indevidamente.
5. Recalcula card.

Essa jornada é crítica porque os relatos recentes mostram que confiança cai quando há duplicidade ou erro calórico.

### Jornada 4 — Reavaliação

1. Daily closer marca reavaliação vencida.
2. Engagement matinal dispara script.
3. Paciente envia peso, fotos e respostas.
4. Sistema usa dados para recalcular/confirmar metas.
5. Paciente recebe nova orientação.

### Jornada 5 — Operação Admin

1. Operador acompanha dashboard.
2. Vê pacientes/conversas.
3. Investiga erros no audit.
4. Ajusta prompts/configurações.
5. Monitora crons e integrações.
6. Usa crescimento/Stripe quando aplicável.

## Conteúdo e Marketing

### Pilares de Conteúdo

1. **Registro sem fricção**
   - Foto, áudio ou texto.
   - Menos app, mais rotina.

2. **Progresso visível**
   - Bloco 7700.
   - Proteína.
   - Fechamento diário.

3. **Método**
   - Regras claras.
   - Recomposição.
   - Reavaliação quinzenal.

4. **Correção sem culpa**
   - Ajuste no mesmo dia.
   - Aprender com dados.

5. **Autoridade**
   - Dr. Roberto / MPP / CoreHealth, conforme decisão de marca.

6. **Operação inteligente**
   - Para B2B ou equipe: painel, auditoria, prompts, crons.

### Claims Seguros

Claims mais seguros:

- "Registre refeições por foto, áudio ou texto."
- "Veja seu balanço diário de calorias e proteína."
- "Acompanhe seu progresso no Bloco 7700."
- "Receba lembretes quando o dia fica incompleto."
- "Reavalie sua evolução em ciclos."
- "Números calculados pelo sistema, não chutados pela IA."

Claims a validar juridicamente/clinicamente antes de usar:

- Promessas de perda de peso.
- Percentuais de eficácia.
- Diagnóstico nutricional.
- Tratamento de obesidade, compulsão, diabetes ou condições clínicas.
- Garantias de resultado.

## Produto Mobile: MVP Recomendado

### MVP 1 — Companion App

Objetivo:

- Dar ao paciente visão clara do que o WhatsApp já registra.

Funcionalidades:

- Login.
- Tela Hoje.
- Histórico de refeições/treinos.
- Progresso Bloco 7700.
- Próxima reavaliação.
- Perfil/metas.
- Atalho para WhatsApp.

Baixo risco porque não muda o fluxo principal de registro.

### MVP 2 — Registro Nativo

Adicionar:

- Foto no app.
- Áudio no app.
- Texto no app.
- Confirmação/edição de proposta.
- Push notifications.

Risco:

- Pode duplicar canais se WhatsApp e app não tiverem idempotência forte.

### MVP 3 — Coach In-App

Adicionar:

- Chat nativo.
- Histórico completo.
- Push conversacional.

Risco:

- Maior complexidade, porque passa a concorrer com WhatsApp.

Recomendação:

- Começar com Companion App e evoluir para registro nativo só depois de garantir consistência entre canais.

## Métricas de Produto

Métricas recomendadas:

- Usuários ativos diários.
- Dias com pelo menos 1 registro.
- Refeições registradas por dia.
- Percentual de dias completos.
- Percentual de dias incompletos por gap.
- Resposta a lembretes de gap.
- Confirmação de pending registrations.
- Correções por usuário.
- Taxa de duplicidade detectada.
- Erros de cálculo/caloria reportados.
- Reavaliações iniciadas.
- Reavaliações concluídas.
- Fotos de reavaliação completas.
- Blocos 7700 concluídos.
- Streak médio.
- Retenção por semana.
- Tempo até primeiro registro.
- Tempo até primeiro card.
- Custo de IA por usuário.
- Mensagens por usuário por dia.

Para marca e UX, as mais importantes no início:

- Tempo até o usuário entender o card.
- Frequência de registro.
- Confiança nos números.
- Conclusão de reavaliação.
- Retenção do hábito.

## Riscos de Produto

### Confiança Numérica

Se o sistema erra calorias, duplica registros ou contradiz o card, o paciente perde confiança rapidamente. Isso é um risco central do produto.

Mitigação de comunicação:

- Não prometer perfeição.
- Mostrar confirmação antes de gravar quando houver incerteza.
- Dar correção fácil.

### Excesso de Mensagens

Lembretes e engajamento podem ajudar, mas também podem cansar.

Mitigação:

- Frequência adaptativa.
- Silenciar/pausar fácil.
- Mensagens com motivo claro.

### Sensibilidade Corporal

Fotos e peso podem gerar ansiedade.

Mitigação:

- Linguagem respeitosa.
- Privacidade explícita.
- Permitir seguir sem fotos.
- Evitar ranking corporal.

### Dependência do WhatsApp

WhatsApp é vantagem de fricção, mas limita UI, visualização histórica e controle de experiência.

Mitigação:

- App companion.
- Resumo visual.
- Dados consistentes entre canais.

### Marca Técnica Demais

"Agente MPP" pode soar interno.

Mitigação:

- Definir arquitetura de marca.
- Separar nome técnico, nome de produto e nome da mecânica.

## Decisões Pendentes

Perguntas que precisam ser respondidas antes de fechar comunicação e identidade:

1. A marca principal será Roberto, MPP, CoreHealth ou uma marca nova?
2. O produto será vendido direto ao paciente, via profissional/clínica ou ambos?
3. O app mobile será companion do WhatsApp ou canal principal?
4. O público inicial é recomposição geral, pacientes do Roberto ou operação B2B?
5. Qual grau de associação explícita com saúde/medicina/nutrição é permitido?
6. O nome "Muscular Power Plant" deve aparecer para o paciente final ou ficar como método interno?
7. O Bloco 7700 será uma feature explicada desde o onboarding ou introduzida depois?
8. O tom deve ser mais "coach Roberto" ou mais "produto CoreHealth"?
9. Quais promessas comerciais são juridicamente aceitáveis?
10. Quais dados reais de pacientes podem ser usados em comunicação, se houver consentimento?

## Recomendações Práticas

### Para Naming

Escolher uma das três arquiteturas:

- **MPP Coach** se a força principal for método/Roberto.
- **CoreCoach MPP** se a CoreHealth será marca-mãe.
- **Nome novo + powered by MPP** se o objetivo for escalar para público frio.

Não recomendo abandonar MPP totalmente neste momento, porque o método é um ativo real do produto.

### Para Comunicação

Usar como mensagem central:

> Acompanhamento nutricional diário por WhatsApp, com registro por foto, áudio ou texto e progresso calculado pelo método MPP.

Versão mais emocional:

> Você vive sua rotina. O MPP organiza os números, lembra do que falta e mostra seu progresso.

### Para Identidade Visual

Manter a base:

- Cream.
- Ink.
- Moss.
- Inter.
- Outfit.

Adicionar:

- Um acento mais energético para paciente.
- Visualização forte do Bloco 7700.
- Ícones claros.
- Fotos reais e acessíveis.

### Para App Mobile

Começar pelo companion app:

- Hoje.
- Registrar.
- Progresso.
- Plano.
- Coach/WhatsApp.

Não começar por um app que substitui o WhatsApp inteiro. O produto atual tem vantagem justamente na captura conversacional.

## Proposta de Estrutura Para Um App Nativo

### Tela 1 — Hoje

Conteúdo:

- Saudação curta.
- Card de balanço.
- Próxima ação.
- Refeições do dia.
- Treino do dia.
- Barra do Bloco 7700.
- Pendências.

CTA principal:

- Registrar.

CTAs secundários:

- Corrigir.
- Marcar pulei.
- Ver plano.

### Tela 2 — Registrar

Entrada:

- Foto.
- Áudio.
- Texto.
- Treino.
- Peso.

Resultado:

- Proposta interpretada.
- Confirmar.
- Editar.

### Tela 3 — Progresso

Conteúdo:

- Bloco 7700.
- Peso.
- BF.
- Proteína média.
- Dias completos.
- Streaks/badges.
- Reavaliações.

### Tela 4 — Plano

Conteúdo:

- Protocolo.
- Meta calórica.
- Proteína.
- Déficit.
- Treino.
- Dieta/lista.
- Próxima reavaliação.

### Tela 5 — Coach

Conteúdo:

- Chat ou link para WhatsApp.
- Resumos.
- Perguntas frequentes.
- Histórico recente.

## Glossário de Produto

**Agente MPP:** produto atual; coach nutricional conversacional via WhatsApp.

**CoreHealth:** cliente/organização ligada ao projeto.

**MPP:** Muscular Power Plant, método do Dr. Roberto Menescal.

**Bloco 7700:** unidade de progresso baseada em 7700 kcal de déficit líquido, associada a 1 kg de gordura.

**Card de balanço:** resposta canônica com consumido, restam/excedente, proteína, exercício e bloco.

**Recomposição:** protocolo principal descrito nas regras atuais, com meta baseada em BMR x 1.2 menos déficit programado.

**Daily closer:** rotina de fechamento do dia.

**Gap de refeição:** refeição esperada ausente; pode gerar lembrete e impedir crédito do bloco se continuar aberta no fechamento.

**Reavaliação:** ciclo quinzenal de atualização de peso, fotos e perguntas do protocolo.

**Pending registration:** proposta de refeição/treino aguardando confirmação.

## Próximos Passos Recomendados

1. Decidir arquitetura de marca: MPP-first, CoreHealth-first ou marca nova.
2. Escolher shortlist de 3 nomes e fazer checagem jurídica/domínio.
3. Definir público inicial com base comercial real.
4. Fazer 5 a 10 entrevistas rápidas com pacientes/operadores.
5. Validar se "Bloco 7700" é entendido ou precisa de outro nome visual.
6. Criar manifesto de voz e tom para WhatsApp, app e landing page.
7. Produzir moodboard com 2 ou 3 direções visuais.
8. Prototipar o app companion em baixa fidelidade.
9. Testar entendimento do card de balanço com usuários reais.
10. Definir claims permitidos com revisão jurídica/saúde.
