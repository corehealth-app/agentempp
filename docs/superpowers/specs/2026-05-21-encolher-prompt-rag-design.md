# Sub-projeto D — Encolher o prompt (via RAG)

**Data:** 2026-05-21
**Status:** Design aprovado (aguardando review do spec)
**Depende de:** A e C **implementados** (só se remove do prompt a regra cujo código
já está vivo). A base RAG pode ser construída em paralelo.
**Contexto:** Parte 4 de 4 da refatoração de confiabilidade do Agente MPP.

---

## Problema

Cada system prompt tem ~170 mil caracteres, com o método inteiro embutido. Isso é:
- **Caro** (tokens de input em todo turno),
- **Lento** (latência),
- **Propenso a erro** — a LLM "se perde" no meio de regras demais.

## Objetivo

Em vez de enviar o método inteiro todo turno, guardar o método numa base pesquisável
e recuperar **só os trechos relevantes** para cada situação, reduzindo tamanho/custo
sem perder fidelidade.

### Critério de sucesso
- Tamanho do prompt por turno cai significativamente (medir antes/depois).
- Comportamento preservado (golden tests) — encolher não muda as respostas.
- Recuperação traz a seção certa do método para situações conhecidas (eval).

### Infra existente a reusar
- Provider de embeddings: `packages/providers/src/embeddings/openrouter.ts`.
- **pgvector** já em produção (usado no matching de alimentos) — mesmo padrão.
- Tabelas `agent_rules` / `agent_rules_versions` (versionamento já existe).

## Componentes

### 1. Ingestão do método
- Fonte: as ~88 páginas do export Notion (já disponíveis). Quebrar em trechos,
  gerar embeddings, armazenar no pgvector. Versionado via `agent_rules_versions`.
- Reprocessar quando o método mudar (disparar embed após upsert — atenção ao gotcha
  do ecossistema: após inserir fonte de conhecimento, disparar a função de embedding).

### 2. Recuperação por turno
- Dado `current_protocol` + situação (stage) + a mensagem do paciente, recuperar os
  top-K trechos mais relevantes do método.

### 3. Novo formato do prompt
- **Núcleo fixo (pequeno, sempre presente):** persona, regras de segurança /
  anti-alucinação, lista de tools + quando chamar, resumo do protocolo atual.
- **Trechos recuperados:** só as seções relevantes do método para a situação.
- **Fatos injetados (A):** estado/card já calculado.

### 4. Segurança do RAG (ponto crítico)
- Como os **números vivem em código** (A/C), uma falha de recuperação **só afeta a
  prosa, nunca um número**.
- As **regras de segurança ficam sempre no núcleo fixo** — não dependem de busca.
- Pior caso de um "miss" de recuperação: tom/completude da resposta, não cálculo
  errado. É isso que torna o RAG seguro neste contexto.

## Ordem de execução (gating)
1. (Pré-requisito) A e C implementados — as regras de cálculo já garantidas em código.
2. **Corte conservador** (primeiro passo dentro da D): remover do prompt o que virou
   código, validando por golden tests. Ganho imediato e seguro.
3. **RAG**: construir base + recuperação; mover o método behavioral pro RAG; encolher
   o núcleo. Estado final.

## Validação / testes
- **Golden tests de comportamento:** mesma conversa → mesma resposta antes/depois do
  encolhimento.
- **Eval de recuperação:** conjunto de situações conhecidas → a seção certa do método
  é recuperada? (usar a página "Avaliações LLM" do método como base de casos).
- **Métrica de custo:** tokens de input/turno e custo antes/depois (objetivo central).

## Nota de cache
Prompt menor e variável muda a dinâmica do prompt caching (Anthropic): o núcleo fixo
ainda é cacheável; a parte recuperada varia. Medir o efeito líquido no custo — o ganho
de tokens deve superar a perda de cache hit.

## Riscos
- **Recuperação perde uma seção load-bearing de comportamento.** Mitigação: núcleo
  fixo com o essencial; eval de recuperação; código já dono dos números (miss não
  causa erro numérico).
- **Complexidade do RAG vs ganho.** Mitigação: corte conservador primeiro (ganho
  garantido); RAG só depois, medido. Se o RAG não compensar, para no corte conservador.
