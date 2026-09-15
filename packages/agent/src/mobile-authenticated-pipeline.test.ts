import { describe, expect, it } from 'vitest'
import {
  MOBILE_FLOW_READ_ONLY_TOOLS,
  MOBILE_FLOW_TELEMETRY_INCLUDES_CONTENT,
  mobileFlowSystemPolicy,
  selectPipelineTools,
} from './pipeline.js'

describe('authenticated mobile Flow policy', () => {
  it('exposes only reviewed read-only tools even when the database allows every tool', () => {
    const tools = selectPipelineTools(null, MOBILE_FLOW_READ_ONLY_TOOLS)

    expect(tools.map((tool) => tool.name)).toEqual([
      'consulta_progresso',
      'consulta_metricas',
      'consulta_resumo_periodo',
      'consulta_reavaliacao_protocolo',
    ])
    expect(tools.some((tool) => tool.name.startsWith('registra_'))).toBe(false)
  })

  it('intersects the server channel allowlist with the database allowlist', () => {
    expect(
      selectPipelineTools(
        ['consulta_metricas', 'registra_refeicao'],
        MOBILE_FLOW_READ_ONLY_TOOLS,
      ).map((tool) => tool.name),
    ).toEqual(['consulta_metricas'])
  })

  it('names Performe AI and Flow and denies chat-triggered health mutations', () => {
    expect(mobileFlowSystemPolicy).toContain('Performe AI')
    expect(mobileFlowSystemPolicy).toContain('Flow')
    expect(mobileFlowSystemPolicy).toContain('não autoriza')
    expect(mobileFlowSystemPolicy).toContain('confirmação')
    expect(MOBILE_FLOW_TELEMETRY_INCLUDES_CONTENT).toBe(false)
  })
})
