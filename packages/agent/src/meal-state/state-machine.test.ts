/**
 * Tests — state machine MealState (audit 06-26 Layer 2.2 + Layer 2.4
 * property-based via fast-check).
 *
 * 2 partes:
 *  - Hardcoded examples (transições conhecidas válidas/inválidas)
 *  - Property-based (fast-check): invariantes da máquina
 */
import fc from 'fast-check'
import { describe, expect, it } from 'vitest'
import {
  assertValidTransition,
  isTerminal,
  listValidTransitions,
  TERMINAL_STATES,
} from './state-machine.js'
import type { MealState } from './types.js'

const ALL_STATES: MealState[] = [
  'PROPOSED',
  'CONFIRMED',
  'REGISTERED',
  'CORRECTED',
  'RECLASSIFIED',
  'CANCELLED',
  'EDITED',
  'EXPIRED',
  'SKIPPED',
]

describe('assertValidTransition — exemplos canônicos', () => {
  // Caminhos felizes
  it.each([
    ['PROPOSED', 'CONFIRMED'],
    ['PROPOSED', 'EDITED'],
    ['PROPOSED', 'CANCELLED'],
    ['PROPOSED', 'EXPIRED'],
    ['CONFIRMED', 'CORRECTED'],
    ['CONFIRMED', 'RECLASSIFIED'],
    ['CONFIRMED', 'PROPOSED'], // rollback de erro
    ['REGISTERED', 'CORRECTED'],
    ['REGISTERED', 'RECLASSIFIED'],
    ['CANCELLED', 'PROPOSED'], // Layer 3 recovery (audit 06-26)
  ] as const)('%s → %s = OK', (prev, next) => {
    const r = assertValidTransition(prev, next)
    expect(r.ok).toBe(true)
  })

  // Transições inválidas (warn — não bloqueia)
  it.each([
    ['PROPOSED', 'CORRECTED'], // sem passar por CONFIRMED
    ['PROPOSED', 'RECLASSIFIED'],
    ['REGISTERED', 'CANCELLED'], // sem pending pra cancelar
    ['CANCELLED', 'CONFIRMED'], // pular PROPOSED — bug pizza-race original
  ] as const)('%s → %s = INVALID (warn)', (prev, next) => {
    const r = assertValidTransition(prev, next)
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.severity).toBe('warn')
    }
  })

  // Transições saindo de estado terminal (error severity)
  it.each([
    ['EXPIRED', 'CONFIRMED'],
    ['SKIPPED', 'CORRECTED'],
    ['EDITED', 'CANCELLED'],
  ] as const)('%s → %s = INVALID (error — terminal source)', (prev, next) => {
    const r = assertValidTransition(prev, next)
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.severity).toBe('error')
    }
  })
})

describe('isTerminal', () => {
  it.each(TERMINAL_STATES.map((s) => [s] as const))('%s → terminal', (s) => {
    expect(isTerminal(s)).toBe(true)
  })

  it('PROPOSED/CONFIRMED/etc NÃO são terminais', () => {
    expect(isTerminal('PROPOSED')).toBe(false)
    expect(isTerminal('CONFIRMED')).toBe(false)
    expect(isTerminal('REGISTERED')).toBe(false)
    expect(isTerminal('CORRECTED')).toBe(false)
    expect(isTerminal('CANCELLED')).toBe(false)
  })
})

// ── Layer 2.4: property-based tests com fast-check ────────────────────────
describe('property-based invariants (fast-check)', () => {
  const arbState = fc.constantFrom<MealState>(...ALL_STATES)

  it('transição é reflexiva apenas em CORRECTED/RECLASSIFIED (estados re-entrantes)', () => {
    fc.assert(
      fc.property(arbState, (s) => {
        const r = assertValidTransition(s, s)
        if (s === 'CORRECTED' || s === 'RECLASSIFIED') {
          expect(r.ok).toBe(true)
        } else {
          expect(r.ok).toBe(false)
        }
      }),
    )
  })

  it('estado TERMINAL nunca tem transição saindo (saída = error)', () => {
    fc.assert(
      fc.property(
        fc.constantFrom<MealState>(...TERMINAL_STATES),
        arbState,
        (terminal, next) => {
          const r = assertValidTransition(terminal, next)
          expect(r.ok).toBe(false)
          if (!r.ok) expect(r.severity).toBe('error')
        },
      ),
    )
  })

  it('toda transição válida está em listValidTransitions()', () => {
    const valid = new Set(listValidTransitions().map((t) => `${t.from}→${t.to}`))
    fc.assert(
      fc.property(arbState, arbState, (prev, next) => {
        const r = assertValidTransition(prev, next)
        const key = `${prev}→${next}`
        expect(r.ok).toBe(valid.has(key))
      }),
    )
  })

  it('toda transição inválida tem reason não-vazio', () => {
    fc.assert(
      fc.property(arbState, arbState, (prev, next) => {
        const r = assertValidTransition(prev, next)
        if (!r.ok) {
          expect(r.reason.length).toBeGreaterThan(0)
          expect(['warn', 'error']).toContain(r.severity)
        }
      }),
    )
  })

  it('CANCELLED só transita pra PROPOSED (Layer 3 recovery — caso bug pizza-race)', () => {
    fc.assert(
      fc.property(arbState, (next) => {
        const r = assertValidTransition('CANCELLED', next)
        if (next === 'PROPOSED') {
          expect(r.ok).toBe(true)
        } else {
          expect(r.ok).toBe(false)
        }
      }),
    )
  })

  it('PROPOSED é ponto de entrada — qualquer não-PROPOSED → PROPOSED é inválido (exceto CONFIRMED→PROPOSED rollback e CANCELLED→PROPOSED recovery)', () => {
    fc.assert(
      fc.property(arbState, (prev) => {
        const r = assertValidTransition(prev, 'PROPOSED')
        const allowed = prev === 'CONFIRMED' || prev === 'CANCELLED'
        expect(r.ok).toBe(allowed)
      }),
    )
  })

  // ── Review MED 3 (audit 06-26): invariantes semânticos adicionais ───────
  it('REGISTERED só vai pra CORRECTED/RECLASSIFIED (express path nunca volta pra PROPOSED/CONFIRMED)', () => {
    fc.assert(
      fc.property(arbState, (next) => {
        const r = assertValidTransition('REGISTERED', next)
        const allowed = next === 'CORRECTED' || next === 'RECLASSIFIED'
        expect(r.ok).toBe(allowed)
      }),
    )
  })

  it('CORRECTED é re-entrante (idempotência): pra todo target T, CORRECTED→T válido ⇒ CORRECTED→CORRECTED→T também válido', () => {
    fc.assert(
      fc.property(arbState, (target) => {
        const direct = assertValidTransition('CORRECTED', target)
        if (direct.ok) {
          const indirect1 = assertValidTransition('CORRECTED', 'CORRECTED')
          expect(indirect1.ok).toBe(true)
          const indirect2 = assertValidTransition('CORRECTED', target)
          expect(indirect2.ok).toBe(true)
        }
      }),
    )
  })

  it('CONFIRMED→REGISTERED é INVÁLIDA — REGISTERED é express-only (sem pending prévio)', () => {
    const r = assertValidTransition('CONFIRMED', 'REGISTERED')
    expect(r.ok).toBe(false)
    if (!r.ok) {
      expect(r.severity).toBe('warn')
    }
  })
})
