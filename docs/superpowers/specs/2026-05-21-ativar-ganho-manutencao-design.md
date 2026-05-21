# Sub-projeto C — Ativar ganho de massa e manutenção em código

**Data:** 2026-05-21
**Status:** Design aprovado (aguardando review do spec)
**Depende de:** Sub-projeto A (motor de cálculo + renderização canônica).
**Contexto:** Parte 3 de 4 da refatoração de confiabilidade do Agente MPP.

---

## Problema

Dos três protocolos do método, só a **recomposição** tem os cálculos protegidos por
código (motor + card canônico). **Ganho de massa** e **manutenção** têm as regras de
negócio **só no system prompt** — a LLM as segue de cabeça, sujeito ao mesmo risco de
alucinação numérica que se combateu na recomposição. Além disso, o `protocol-router`
**sempre retorna `recomposicao`** — nunca conduz automaticamente para ganho/manutenção
(só varia o flag `canChoose`).

> Realidade operacional: hoje **nenhum paciente** usa ganho/manutenção (todos em
> recomposição). Logo a *implementação* da C não é urgente como a A — a spec fica
> pronta e a construção pode ser ativada quando houver um paciente que vá usar esses
> protocolos.

## Objetivo

Colocar ganho de massa e manutenção no **mesmo padrão de confiabilidade** da
recomposição: números e limites calculados por código determinístico (motor da A),
roteamento automático funcional, card canônico. Mantém a regra: **a LLM não inventa
número nem limite**; o julgamento subjetivo (aderência/fome/energia) continua com a
LLM, recebendo os números prontos.

### Critério de sucesso
- Roteamento de protocolo indica ganho/manutenção quando os critérios do método batem
  (a troca em si segue confirmada — nada muda de protocolo silenciosamente).
- Card/balanço de ganho e manutenção vêm do motor (não da LLM).
- Limites de segurança calculados/checados em código (ver abaixo).
- Decisões de ciclo: os **números** vêm do código; o **julgamento** fica na LLM com
  os números em mãos.

### Não-objetivos
- "Bloco de hipertrofia" (EME) avançado de exibição do ganho — avaliar em fase futura
  se o método exigir.
- Reescrever a persona/linguagem desses protocolos (isso é do prompt; sub-projeto D
  trata o tamanho do prompt).

## Componentes / decisões

### 1. Roteamento automático
- `protocol-router.resolveProtocol` passa a **de fato retornar** `ganho_massa` /
  `manutencao` quando os critérios objetivos batem (hoje retorna sempre
  `recomposicao`). A confirmação/gravação final continua via `define_protocolo`
  (nada troca de protocolo sem critério atendido + confirmação).

### 2. Meta + card no motor
- Metas já corretas (`ganho = TDEE × 1,05`, `manutencao = TDEE`) — consolidadas no
  motor da A.
- Card/balanço de ganho e manutenção renderizados pelo sistema (como o card da
  recomposição), incluindo a visão "Orçamento 14d" já existente.

### 3. Limites de segurança em código (hoje só no prompt)
- **Ganho de massa:** pausar/sinalizar se a gordura subir além do limite (+3 p.p.
  homens / +4 p.p. mulheres), IMC subir além de +1,5, ou velocidade de ganho fora da
  faixa segura (0,25–0,5%/semana). Velocidade exige série temporal de peso (vem dos
  snapshots / estado derivado da B).
- **Manutenção:** ajustes de −100/−150 kcal conforme dias acima da meta (DAM) e
  treinos a menos, com teto e "uma variação por ciclo".

### 4. Princípio número vs julgamento (igual à A)
- Código calcula: metas, limites, velocidade, valores de ajuste, gates de transição.
- LLM julga: aderência, fome, energia, contexto da conversa — usando os números que o
  código forneceu. O código pode oferecer a **decisão candidata** (ex.: "velocidade
  alta → sugerir reduzir superávit"); a LLM confirma/comunica.

## Dependências
- Motor e renderização da **A**.
- Velocidade de ganho e tendências dependem de série de peso/BF — alinhar com o estado
  derivado da **B** (BF% estimado, agregados).

## Fluxo
Igual ao da recomposição (A): estado computado pelo motor → injetado/tool → LLM
comunica → render canônico. A diferença é só qual conjunto de regras o motor aplica,
conforme `current_protocol`.

## Tratamento de erro
- Critérios de roteamento incompletos (faltando peso/BF) → cai no comportamento atual
  (recomposição / pedir dado), sem quebrar.
- Limites sem série temporal suficiente → não dispara pausa; sinaliza "dados
  insuficientes" em vez de chutar.

## Testes
- Unit dos limites (BF +3/+4, IMC +1,5), do cálculo de velocidade de ganho, e dos
  valores de ajuste da manutenção (−100/−150 por DAM/treino).
- Golden contra os exemplos numéricos do método original (páginas de ganho/manutenção).
- Roteamento: casos de fronteira (BF/IMC no limite) retornam o protocolo certo.

## Riscos
- **Construir algo sem usuário atual** → risco de divergir do uso real quando ativar.
  Mitigação: spec pronta agora, implementação adiável; validar com Roberto no momento
  de ativar o primeiro paciente.
- **Velocidade/tendência depende de dados históricos** que talvez não existam no início
  de um ciclo. Mitigação: degradar para "dados insuficientes", nunca chutar.
