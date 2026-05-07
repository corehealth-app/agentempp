# Etapas do Projeto

---

## 1. Dashboard de Interações

**Objetivo macro acordado:** dar visibilidade de SaaS para o negócio, com acesso via login administrativo.

a. Métricas de uso

i. Conversas

– Total de conversas iniciadas

– Conversas por dia

– Conversas ativas vs inativas

– Volume de mensagens (entrada/saída)

– Uso médio por usuário

ii. Assinantes

– Total de usuários cadastrados

– Usuários em trial

– Usuários pagantes

– Churn (cancelamentos)

– Receita estimada (via Stripe)

> Observação da call: o dashboard foi tratado como obrigatório na V1, ainda que simples, para acompanhamento do negócio.
> 

---

### 2. Cálculos

**Objetivo macro acordado:** retirar responsabilidade de cálculo da LLM e torná-los determinísticos, auditáveis e reutilizáveis.

a. Criar servidor de cálculos para consumo do agente

– Endpoints ou ferramentas nomeadas por tipo de cálculo

– Cálculo de metas (ex.: gasto calórico, proteínas, balanço diário)

– Validação de inputs (evitar valores inválidos ou inconsistentes)

– Retorno estruturado para o agente (sem ambiguidade)

– Registro do resultado do cálculo no banco

b. Rotina de fechamento diário

– “Fechar o dia” e congelar resultados

– Abrir novo dia com metas zeradas

– Manter histórico por data (não sobrescrever)

> Observação da call: cálculos são o “coração do produto” e não podem ficar implícitos no prompt.
> 

---

### 3. Banco de Dados

**Objetivo macro acordado:** sustentar histórico, personalização, cobrança e evolução do usuário.

a. Onboarding inicial

– Coleta de dados do usuário (nome, objetivo, parâmetros físicos)

– Associação ao identificador do WhatsApp

– Persistência imediata para uso recorrente

b. Trial e Versão Paga

– Flag de status do usuário (trial / pago / expirado)

– Regras de limitação ou bloqueio por status

– Base preparada para upgrade/downgrade

c. Integrar Stripe (minha conta temporária)

– Checkout ou assinatura recorrente

– Webhooks para atualização de status

– Uso temporário da conta do Luan

– Previsão de migração futura para conta própria do projeto

> Observação da call: foi explicitado cuidado com regras da Stripe e troca futura de titularidade.
> 

---

### 4. Fragmentar Prompt System

**Objetivo macro acordado:** reduzir risco operacional e facilitar manutenção do agente.

a. Aplicar divisão de prompts

– Separar prompt de identidade

– Separar regras fixas (Manual MPP)

– Separar instruções operacionais

– Separar mensagens dinâmicas/contextuais

– Evitar edição manual de “promptão” único

b. Estratégia de estabilidade

– Congelar grandes mudanças na V1

– Planejar refino posterior sem quebrar produção

> Observação da call: mexer demais no prompt agora foi visto como risco de atraso.
> 

---

### 5. Figuras Mascote

**Objetivo macro acordado:** elemento de engajamento e gamificação, sem complexidade excessiva na V1.

a. Lista

– Definição de estágios do mascote

– Imagens estáticas por evolução

– Associação do estágio ao progresso do usuário

– Possibilidade futura de escolha entre 3 “personalidades”

b. Roadmap futuro (fora da V1)

– Animações

– Interações mais ricas

– Stickers dinâmicos

> Observação da call: animação foi explicitamente adiada.
>