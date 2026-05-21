# Sub-projeto B — Persistir estado derivado

**Data:** 2026-05-21
**Status:** Design aprovado (aguardando review do spec)
**Depende de:** Sub-projeto A (motor de cálculo + renderização canônica).
**Contexto:** Parte 2 de 4 da refatoração de confiabilidade do Agente MPP.

---

## Problema

O agente joga fora ou recalcula na hora três tipos de dado, e por isso erra ou
perde informação:
- **Água/sono/passos:** o paciente menciona, mas nada é gravado (colunas
  `water_consumed_ml`, `sleep_hours`, `steps` do snapshot ficam zeradas).
- **BF% das fotos:** a visão estima o percentual de gordura, usa no momento e
  descarta — sem histórico, e a decisão de protocolo pode ficar presa só no IMC.
- **Resumos de semana/mês:** quando o agente compara médias ("proteína subiu de
  110 → 132g"), hoje a LLM calcularia isso de cabeça (risco de inventar número).

## Objetivo

Persistir esses dados derivados para o agente **ler fato pronto** em vez de
recomputar/inventar. Mantém a regra do sub-projeto A: número exibido sai de função
determinística, nunca da cabeça da LLM.

### Critério de sucesso
- Água/sono/passos ficam gravados quando o paciente menciona.
- BF% estimado pela foto fica gravado (marcado como estimativa), disponível para
  tendência e decisão de protocolo, **sem nunca sobrescrever** valor confirmado.
- Resumos semanais/mensais vêm de cálculo determinístico sobre dados salvos.

### Não-objetivos
- Integração com wearable para passos automáticos (futuro, se valer a pena).
- Metas first-class de água/sono/passos (decisão: tratamento **leve** — só captura
  quando mencionado, sem cobrança diária nem linha fixa no card).

## Componentes / decisões

### 1. Água/sono/passos — captura leve
- Tool de captura (nova `registra_metrica_diaria` ou extensão de tool existente):
  quando o paciente menciona água/sono/passos, grava nas colunas existentes do
  `daily_snapshots`.
- Sem meta diária obrigatória e sem linha fixa no card. O engine (A) expõe as metas
  de referência (água 30-40 ml/kg, sono 7-9 h, passos 7-10 mil) apenas quando o
  agente é perguntado ou quer comentar.

### 2. BF% das fotos — estimativa separada, sem sobrescrever o confirmado
- Gravar a estimativa da visão em campo **separado** do confirmado:
  `bf_percent_estimated` + `bf_source` (`'vision'`) + `confidence`.
- Distinto de `body_fat_percent` (confirmado pelo paciente/Roberto). A estimativa
  **nunca sobrescreve** o confirmado.
- A decisão de protocolo (`protocol-router`) pode usar a estimativa **marcada como
  tal**, pedindo confirmação quando o número for crítico para a decisão.
- Preenche o gap (BF% disponível para tendência e roteamento) sem reintroduzir o
  risco original (chute da visão decidir protocolo silenciosamente).

### 3. Agregados semanais/mensais — cálculo sob demanda, sem tabela nova
- Funções puras no engine (A): `computeWeeklyProgress` / `computeMonthlyProgress`,
  que agregam direto dos `daily_snapshots` quando pedido, expostas via tool.
- **Sem tabela materializada:** agregado é barato nesse volume; tabela à parte criaria
  risco de drift (justamente o que se quer evitar). Materializar só se a performance
  algum dia exigir (não exige no volume atual).

## Fluxo

As tools de captura/consulta chamam o engine, persistem o que for o caso, e qualquer
número exibido passa pelo render canônico (A). A montagem de estado diário (A) pode
incluir os agregados quando relevante; senão, ficam sob demanda via tool.

## Migração / dados

- Colunas de água/sono/passos **já existem** no `daily_snapshots` — só passam a ser
  preenchidas.
- BF% estimado: requer migração pequena (colunas `bf_percent_estimated`, `bf_source`,
  `confidence`) — seguir o protocolo de migrations do CLAUDE.md (inventariar, dry-run,
  uma coisa por vez).

## Tratamento de erro

- Captura sem valor claro → não grava (evita lixo); o agente pode pedir esclarecimento.
- BF% estimado ausente/baixa confiança → roteamento de protocolo cai no IMC (como hoje),
  sem quebrar.

## Testes

- Unit dos agregados (semana/mês) com snapshots sintéticos.
- Regra do BF%: estimativa nunca sobrescreve confirmado; `bf_source`/`confidence`
  corretos; roteamento usa a estimativa marcada.
- Captura água/sono/passos: idempotência e validação de tipos/limites.

## Riscos

- **BF% estimado influenciando protocolo.** Mitigação: sempre marcado como estimativa;
  confirmação exigida em decisão crítica; nunca sobrescreve confirmado.
- **Captura ruidosa** (paciente menciona de passagem). Mitigação: tool só grava valor
  explícito; sem inferência agressiva.
