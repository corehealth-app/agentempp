# Sub-projeto A — Núcleo de cálculo determinístico + camada de tools

**Data:** 2026-05-21
**Status:** Design aprovado (aguardando review do spec)
**Contexto:** Parte 1 de 4 da refatoração de confiabilidade do Agente MPP.
Sub-projetos seguintes: B (persistir estado derivado), C (ativar ganho/manutenção
em código), D (encolher o prompt). Cada um terá sua própria spec.

---

## Problema

Hoje, na recomposição, os números críticos (meta, card "Restam", bloco 7700) já
são calculados em código e injetados (defesa anti-alucinação). Mas a lógica de
cálculo está **espalhada** (`calc-targets.ts`, `balance-card.ts`,
`progress-calc.ts`, `daily-closer.ts`, `pipeline.ts`) e **parcialmente duplicada**
— a regra de crédito do bloco vive tanto em `progress-calc.ts` (closer) quanto em
`bloco-recompute.ts` (audit), com risco de drift já anotado em `docs/CALCULO-MPP.md`.

Todos os erros caçados na sessão de 2026-05-20/21 caem em dois modos de falha:
1. **A LLM calcula o número** → alucina (card com valores errados antes da injeção).
2. **A LLM precisa lembrar de chamar uma tool** → esquece ou finge (fake-registration).

## Objetivo

Estabelecer uma **fonte única de verdade** para todo número e decisão: um *engine*
puro e testado, alcançado por dois canais (auto-injeção + tools), com renderização
canônica de toda saída numérica. Regra invariável: **a LLM nunca calcula um número,
em nenhum caminho** — ela entende intenção, chama tool de ação, e embrulha em
linguagem os números que o sistema forneceu.

### Critério de sucesso
- Todo número exibido ao paciente (recomposição) vem de uma função pura testada.
- A regra de crédito do bloco existe em **um só lugar** (sem duplicação).
- **Paridade comportamental:** a saída do agente para recomposição é idêntica à
  atual (validada por golden tests sobre conversas reais). Divergências vs. o
  método original são *documentadas, não corrigidas* nesta fase (opção 3).

### Não-objetivos (vão para B/C/D)
- Persistir água/sono/passos, BF% de fotos, agregados semanais → **B**.
- Regras de negócio de ganho de massa e manutenção em código → **C**.
- Encolher o system prompt (hoje ~170K chars) → **D**.

## Decisão de arquitetura: canal híbrido (abordagem 3)

Cada cálculo no canal onde o modo de falha é menor:

| O quê | Canal | Por quê |
|---|---|---|
| Estado diário (balanço, bloco, reavaliação vencida) — crítico + previsível | **Auto-injeção** (sistema computa todo turno) | Não depende da LLM decidir → nunca falta nem inventa. É o padrão do card, generalizado. |
| Registrar refeição/treino — ação | **Tool** (guardada pelo detector fake-registration existente) | Ação é inevitavelmente disparada pela LLM a partir da mensagem; não dá pra auto-injetar. |
| Projeção, comparação semanal — sob demanda | **Tool** | Imprevisível e infinito; calcular só quando pedido. |

Em todos os canais o número sai do **mesmo engine determinístico**; muda só a porta
de entrega. Evolutivo (não rewrite): card já é auto-injeção, `consulta_progresso`
já é tool.

## Componentes

### `@mpp/core/engine/` — puro, sem I/O, 100% testável
- `targets.ts` — meta calórica e de proteína (consolida `calc-targets`).
- `balance.ts` — **dois balanços explícitos**: `comida = consumido − meta` (card
  "Restam/Excedente") e `net = consumido − meta − exercício` (déficit do dia / bloco).
- `bloco.ts` — crédito por dia e recompute acumulado do bloco 7700. **Unifica** a
  regra hoje duplicada em `progress-calc.ts` e `bloco-recompute.ts` numa função única.

Cada função recebe dados já lidos (structs), retorna struct tipado, sem tocar banco.

### `@mpp/core/render/` — renderização canônica
- `renderBalanceCard` (movido de `@mpp/agent/balance-card.ts`).
- Renderers para as demais saídas numéricas (mantém o formato visual canônico).

### `@mpp/agent` — orquestração / I/O
- **Montador de estado (`DailyState`):** a cada turno lê snapshot/perfil/progresso,
  chama o engine, monta os fatos, injeta no contexto + renderiza o card. Formaliza
  o que `pipeline.ts` faz hoje de forma dispersa.
- **Tools:** `registra_refeicao`/`registra_treino` (ação) e
  `consulta_progresso`/projeção/comparação (sob demanda) — todas chamam o engine,
  nunca calculam inline.

## Fluxo de um turno

```
mensagem
  → pipeline lê banco (snapshot, perfil, progresso)
  → engine.computeDailyState()  [puro]
  → injeta fatos + card canônico no contexto
  → LLM lê fatos / decide ação / chama tool de ação
  → tool chama engine (cálculo determinístico) + persiste
  → render canônico substitui qualquer número escrito pela LLM
  → validadores (numeric / sentiment / reconcileBalanceProse — já existem)
  → envia
```

## Estratégia de migração (paridade segura)

1. **Golden tests primeiro.** Capturar a saída atual (card + números) de conversas
   reais (Roberto, Paulo, Luciana) como baseline congelado.
2. **Extração mecânica.** Mover as funções para `@mpp/core/engine` **sem mudar
   lógica**.
3. **Validar paridade.** Golden tests: saída nova `==` baseline. Qualquer diferença
   = bug de migração → corrigir até zerar.
4. **Documentar divergências.** Toda diferença vs. método original encontrada no
   caminho vai para `docs/superpowers/specs/divergencias-recomp.md` — **não
   corrigir nesta fase**.
5. **Unificar bloco.** Substituir as duas implementações por chamadas à função única,
   com teste provando resultado idêntico nos dados reais (incluindo os blocos já
   recalculados em 20/05).

## Tratamento de erro

- Engine puro → erros determinísticos e testáveis.
- Dado faltando (ex.: sem meta) → render já tem fallback ("perfil incompleto").
- Se o engine lançar, **o turno não quebra**: loga `engine.error` em `product_events`
  e a LLM responde sem o card (degradação graciosa) — **nunca com número inventado**.

## Testes

- **Unit** por função pura (expandir os ~100 atuais).
- **Golden/paridade:** conversa real → saída esperada (trava *comportamento*).
- **Property tests** no bloco: valor sempre em [0, 7700); soma de créditos monotônica;
  recompute idempotente.

## Riscos

- **Refactor amplo toca o caminho crítico.** Mitigação: golden tests antes de mexer;
  paridade exigida; sem mudança de comportamento nesta fase.
- **Duplicação bloco → unificação pode mudar valor.** Mitigação: teste comparando
  as duas implementações nos dados reais antes de remover qualquer uma.

## Aberto para fases seguintes
B (estado derivado), C (ganho/manutenção em código), D (encolher prompt) — cada uma
reusa o engine criado aqui.
