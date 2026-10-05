import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { ALL_TOOLS, MOBILE_FLOW_TOOLS, selectPipelineTools } from '@mpp/agent'
import { describe, expect, it } from 'vitest'
import {
  allowedToolsForSave,
  allToolNames,
  buildAgentToolOptions,
  initialAllowAll,
  initialToolSelection,
  missingFlowTools,
  unknownToolNames,
} from './tool-options'

const PLAN_TOOLS = ['propoe_plano_treino', 'propoe_plano_dieta']

// A lista, como a página a monta: do registro do motor.
const options = buildAgentToolOptions(
  ALL_TOOLS.map((tool) => tool.name),
  MOBILE_FLOW_TOOLS,
)

/** O que o Flow recebe do motor quando `allowed_tools` vale `saved`. */
function flowToolsWith(saved: string[] | null): string[] {
  return selectPipelineTools(saved, MOBILE_FLOW_TOOLS).map((tool) => tool.name)
}

describe('lista de tools do formulário de Sub-agentes', () => {
  it('traz as duas tools de sugestão de plano do Flow (a lista fixa antiga não trazia)', () => {
    for (const tool of PLAN_TOOLS) {
      expect(options.flow, tool).toContain(tool)
      expect(allToolNames(options), tool).toContain(tool)
    }
  })

  it('mostra primeiro o conjunto do Flow do motor, depois o resto como legado', () => {
    expect(options.flow).toEqual([...MOBILE_FLOW_TOOLS])
    expect(allToolNames(options).slice(0, options.flow.length)).toEqual(options.flow)
    expect(options.legacy).toEqual(
      ALL_TOOLS.map((tool) => tool.name).filter(
        (name) => !(MOBILE_FLOW_TOOLS as readonly string[]).includes(name),
      ),
    )
    expect(options.legacy).toContain('pausar_agente')
  })

  it('cobre o registro inteiro do motor, sem repetir nem inventar nome', () => {
    const names = allToolNames(options)
    expect(new Set(names).size).toBe(names.length)
    expect([...names].sort()).toEqual(ALL_TOOLS.map((tool) => tool.name).sort())
  })
})

describe('salvar nunca tira do Flow uma tool que a pessoa não desmarcou', () => {
  it('"todas" → lista explícita → salvar: as sugestões de plano continuam', () => {
    // Estágio salvo como "todas" (allowed_tools = NULL).
    const selected = initialToolSelection(options, null)
    // A pessoa desliga "Permitir todas" e salva sem desmarcar nada.
    const saved = allowedToolsForSave({ allowAll: false, selected })

    expect(saved).not.toBeNull()
    for (const tool of PLAN_TOOLS) expect(saved, tool).toContain(tool)
    // E o motor entrega ao Flow exatamente o que entregava com "todas".
    expect(flowToolsWith(saved)).toEqual(flowToolsWith(null))
    expect(flowToolsWith(saved)).toEqual(expect.arrayContaining(PLAN_TOOLS))
    expect(missingFlowTools(options, { allowAll: false, selected })).toEqual([])
  })

  it('desmarcar uma tool legada não mexe nas do Flow', () => {
    const selected = initialToolSelection(options, null).filter((name) => name !== 'gera_dieta')
    const saved = allowedToolsForSave({ allowAll: false, selected })
    expect(saved).not.toContain('gera_dieta')
    expect(flowToolsWith(saved)).toEqual(flowToolsWith(null))
  })

  it('manter "Permitir todas" continua gravando NULL', () => {
    const selected = initialToolSelection(options, null)
    expect(allowedToolsForSave({ allowAll: true, selected })).toBeNull()
  })

  it('lista salva com [] vale "todas" para o motor e abre toda marcada', () => {
    expect(initialToolSelection(options, [])).toEqual(allToolNames(options))
    expect(flowToolsWith([])).toEqual(flowToolsWith(null))
  })

  it('"Permitir todas" começa ligado para null e para [], e desligado para uma lista com nomes', () => {
    expect(initialAllowAll(null)).toBe(true)
    expect(initialAllowAll([])).toBe(true)
    expect(initialAllowAll(['consulta_progresso'])).toBe(false)
  })

  it.each([
    ['null', null],
    ['[]', [] as string[]],
  ])('estágio salvo como %s: salvar sem tocar em nada grava NULL', (_label, saved) => {
    // O formulário abre assim…
    const allowAll = initialAllowAll(saved)
    const selected = initialToolSelection(options, saved)
    // …e, sem a pessoa mexer, grava isto. (Antes, [] abria com o botão
    // desligado e gravava os nomes de hoje, deixando de fora uma tool criada
    // depois.)
    expect(allowedToolsForSave({ allowAll, selected })).toBeNull()
    expect(missingFlowTools(options, { allowAll, selected })).toEqual([])
  })

  it('uma lista com nomes continua explícita ao salvar sem tocar', () => {
    const saved = ['consulta_progresso', 'propoe_plano_treino']
    expect(
      allowedToolsForSave({
        allowAll: initialAllowAll(saved),
        selected: initialToolSelection(options, saved),
      }),
    ).toEqual(saved)
  })

  it('o formulário usa essa regra para o estado inicial do botão', () => {
    const form = readFileSync(fileURLToPath(new URL('./form.tsx', import.meta.url)), 'utf8')
    expect(form).toContain('useState(() => initialAllowAll(props.allowedTools))')
    expect(form).not.toContain('props.allowedTools === null')
  })

  it('reproduz o defeito antigo e mostra que agora ele fica visível', () => {
    // O que o formulário antigo gravava: nomes da lista fixa, sem as propoe_*.
    const savedByOldForm = ['consulta_progresso', 'registra_refeicao']
    expect(flowToolsWith(savedByOldForm)).toEqual(['consulta_progresso'])

    // A lista salva abre como está (nada é marcado por conta própria)...
    const selected = initialToolSelection(options, savedByOldForm)
    expect(selected).toEqual(savedByOldForm)
    // ...e a tela avisa o que o Flow está sem, com as caixas para marcar de volta.
    expect(missingFlowTools(options, { allowAll: false, selected })).toEqual(
      options.flow.filter((name) => name !== 'consulta_progresso'),
    )
    expect(missingFlowTools(options, { allowAll: false, selected })).toEqual(
      expect.arrayContaining(PLAN_TOOLS),
    )

    // Marcando de volta, o Flow recupera as sugestões de plano.
    const fixed = allowedToolsForSave({ allowAll: false, selected: [...selected, ...PLAN_TOOLS] })
    expect(flowToolsWith(fixed)).toEqual(expect.arrayContaining(PLAN_TOOLS))
  })

  it('não apaga por conta própria um nome salvo que o registro não conhece', () => {
    const saved = ['consulta_progresso', 'tool_antiga_removida']
    expect(unknownToolNames(options, saved)).toEqual(['tool_antiga_removida'])
    const selected = initialToolSelection(options, saved)
    expect(allowedToolsForSave({ allowAll: false, selected })).toEqual(saved)
  })
})
