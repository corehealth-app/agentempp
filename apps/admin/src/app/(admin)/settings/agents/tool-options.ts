/**
 * A lista de tools do formulário de Sub-agentes.
 *
 * Até 2026-10-05 o formulário tinha uma lista FIXA de 19 nomes, sem
 * `propoe_plano_treino` nem `propoe_plano_dieta` — as duas únicas tools de
 * escrita do Flow. Quem desligasse "Permitir todas" e salvasse qualquer lista
 * tirava do Flow, em silêncio, as sugestões de plano daquele estágio, e a tela
 * não oferecia como marcá-las de volta.
 *
 * Agora a lista vem do registro do próprio motor (os nomes de `ALL_TOOLS` e de
 * `MOBILE_FLOW_TOOLS` em `@mpp/agent`, lidos na página, que é do servidor) e
 * passa por aqui. Este arquivo é puro: não importa o motor, para poder rodar
 * também no formulário (cliente).
 *
 * Como o motor lê `allowed_tools` (packages/agent/src/pipeline.ts,
 * `selectPipelineTools`): `null` ou lista vazia = todas; uma lista com nomes =
 * só elas, cruzadas com o conjunto do canal (para o Flow, `MOBILE_FLOW_TOOLS`).
 */

export interface AgentToolOptions {
  /** Tools que o Flow pode usar, na ordem do conjunto do motor. Vêm primeiro. */
  flow: string[]
  /** O resto do registro: só roda no canal de WhatsApp (encerrado). */
  legacy: string[]
}

export function buildAgentToolOptions(
  registryToolNames: readonly string[],
  flowToolNames: readonly string[],
): AgentToolOptions {
  const registry = [...new Set(registryToolNames)]
  const inRegistry = new Set(registry)
  // Uma tool do Flow que o registro não tem não existe para o motor: fica fora.
  const flow = [...new Set(flowToolNames)].filter((name) => inRegistry.has(name))
  const isFlow = new Set(flow)
  return { flow, legacy: registry.filter((name) => !isFlow.has(name)) }
}

export function allToolNames(options: AgentToolOptions): string[] {
  return [...options.flow, ...options.legacy]
}

/**
 * Nomes salvos que o registro não conhece mais. Não aparecem nas duas listas,
 * mas não são apagados por um salvamento: saem só se a pessoa desmarcar.
 */
export function unknownToolNames(
  options: AgentToolOptions,
  savedTools: readonly string[] | null,
): string[] {
  const known = new Set(allToolNames(options))
  return [...new Set(savedTools ?? [])].filter((name) => !known.has(name))
}

/**
 * "Permitir todas" começa ligado quando o estágio está salvo como "todas":
 * `null` OU lista vazia (para o motor, `[]` também é "todas"). Assim, salvar
 * um estágio com `[]` sem tocar em nada grava `null`, e não os nomes de hoje
 * — que deixariam de fora uma tool criada depois.
 */
export function initialAllowAll(savedTools: readonly string[] | null): boolean {
  return savedTools === null || savedTools.length === 0
}

/**
 * O que fica marcado quando a lista explícita aparece.
 *
 * - Estágio salvo como "todas" (`null` ou vazio): TODAS marcadas. Desligar
 *   "Permitir todas" passa a ser o mesmo conjunto, só que explícito — a pessoa
 *   desmarca o que quer tirar. (Antes, a lista abria vazia.)
 * - Estágio com lista salva: exatamente a lista salva.
 */
export function initialToolSelection(
  options: AgentToolOptions,
  savedTools: readonly string[] | null,
): string[] {
  if (!savedTools || savedTools.length === 0) return allToolNames(options)
  return [...new Set(savedTools)]
}

/** O valor gravado em `agent_configs.allowed_tools`. */
export function allowedToolsForSave(input: {
  allowAll: boolean
  selected: readonly string[]
}): string[] | null {
  if (input.allowAll) return null
  return [...new Set(input.selected)]
}

/** Tools do Flow que uma lista explícita deixa de fora (para o aviso da tela). */
export function missingFlowTools(
  options: AgentToolOptions,
  input: { allowAll: boolean; selected: readonly string[] },
): string[] {
  // Lista vazia = todas, para o motor.
  if (input.allowAll || input.selected.length === 0) return []
  const selected = new Set(input.selected)
  return options.flow.filter((name) => !selected.has(name))
}
