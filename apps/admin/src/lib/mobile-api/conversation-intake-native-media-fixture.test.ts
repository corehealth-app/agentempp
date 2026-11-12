/** Cross-language codec specimens from existing synthetic PostgreSQL rollback
 * selections/effects. Controlled read-only ports do not establish live HTTP,
 * provider, native capture or connected persistence acceptance. */
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { describe, expect, it } from 'vitest'
import actual from './__fixtures__/conversation-intake-media-actual.json'
import { clinical, auth as originalAuth } from './__fixtures__/feedback-v2-source'
import { bindConversationCommand } from './conversation-command-contracts'
import {
  bindConversationIntake,
  parseConversationIntakeSelection,
} from './conversation-intake-contracts'
import {
  type ConversationIntakeDriverPorts,
  createConversationIntakeDriver,
} from './conversation-intake-driver'
import { projectSavedConversationMealCommandResult } from './conversation-meal-command-result'
import { readCurrentClinicalState } from './current-clinical-state'

const specimens = JSON.parse(
  readFileSync(
    new URL(
      '../../../../ios/BodyFlow/BodyFlowTests/Fixtures/ConversationIntakeMediaFixtures.json',
      import.meta.url,
    ),
    'utf8',
  ),
)

describe('native media codec specimens preserve the actual SQL parent/effect facts', () => {
  it('pins the complete actual SQL fixture and exact case inventory', () => {
    expect(specimens.source_sha256).toBe(
      createHash('sha256')
        .update(
          readFileSync(
            new URL('./__fixtures__/conversation-intake-media-actual.json', import.meta.url),
          ),
        )
        .digest('hex'),
    )
    expect(specimens.cases.map((x: { label: string }) => x.label).sort()).toEqual(
      actual.cases.map((x) => x.kind).sort(),
    )
  })
  for (const row of actual.cases)
    it(row.kind, async () => {
      const specimen = specimens.cases.find((x: { label: string }) => x.label === row.kind)
      if (!specimen) throw new Error('Missing native codec specimen')
      const selected = row.selection.selection,
        child = selected.command,
        b = selected.intake
      const command = bindConversationIntake(b.owner_id, `cintake1:${b.intake_id}`, specimen.input)
      const validatedSelection = parseConversationIntakeSelection(command, b, selected)
      expect(command.inputHash).toBe(b.input_hash)
      expect(specimen.binding).toEqual(b)
      expect(specimen.input.source).toEqual(child.input.source)
      const result = specimen.response.result
      if (row.kind === 'meal_photo') {
        const auth = {
          ...originalAuth,
          userId: b.owner_id,
          patient: { ...originalAuth.patient, id: b.owner_id },
        }
        expect(result).toEqual(
          projectSavedConversationMealCommandResult({
            auth,
            command: bindConversationCommand(b.owner_id, `cmsg1:${child.command_id}`, child.input),
            expectedEpoch: b.epoch,
            serverBinding: {
              owner_id: b.owner_id,
              command_id: child.command_id,
              input_hash: child.input_hash,
              epoch: b.epoch,
              admitted_at: child.admitted_at,
              kind: child.kind,
              command_protocol: 'conversation.command.v1',
            },
            receipt: row.effect?.receipt,
            feedback: null,
          }),
        )
      } else if (row.effect?.receipt && 'activity' in row.effect.receipt) {
        const receipt = row.effect.receipt
        expect(result).toEqual({
          schema: 'conversation.workout-command-result.v1',
          status: 'saved',
          owner_id: b.owner_id,
          command_id: child.command_id,
          input_hash: child.input_hash,
          epoch: b.epoch,
          registration: Object.fromEntries(
            [
              'provenance',
              'registration_id',
              'workout_id',
              'performed_at',
              'local_date',
              'time_zone',
              'committed_at',
              'effect_version',
            ].map((k) => [k, receipt[k as keyof typeof receipt]]),
          ),
          activity: { kind: 'workout', log_id: receipt.workout_id, ...receipt.activity },
          feedback: null,
        })
      } else {
        const prepared = row.prepared
        if (!prepared || !('status' in prepared))
          throw new Error('Missing actual unperformed preparation')
        expect(result.status).toBe(
          prepared.status === 'needs_reply' ? 'needs_reply' : 'not_recorded',
        )
        if ('question' in prepared) expect(result.question).toEqual(prepared.question)
        if ('reason' in prepared) expect(result.reason).toBe(prepared.reason)
      }
      const now = clinical()
      now.user_id = b.owner_id
      now.health_state.user_id = b.owner_id
      now.epoch = b.epoch
      now.date = now.safety.date = '2026-11-06'
      now.observed_at = now.safety.observed_at = '2026-11-06T04:00:00.000001Z'
      const noWrite = async () => {
        throw new Error('Codec fixture must not write, route or capture')
      }
      const ports: ConversationIntakeDriverPorts = {
        mediaEnabled: () => true,
        store: {
          read: async () => ({
            action: 'available',
            intake: b,
            source_input: command.input,
            source_hash: selected.source_hash,
            claimed: true,
            selection: validatedSelection,
          }),
          admit: noWrite,
          capture: noWrite,
          claim: noWrite,
          seal: noWrite,
        },
        recovery: { read: noWrite, reconcile: noWrite },
        scope: { observeCurrentScope: async () => readCurrentClinicalState(now, b.owner_id) },
        createRouter: () => {
          throw new Error('Persisted codec selection never routes')
        },
        domains: {
          meal: { read: async () => result, submit: noWrite },
          workout: { read: async () => result, submit: noWrite },
        },
      }
      expect(
        await createConversationIntakeDriver(ports).read(
          { ownerId: b.owner_id, intakeId: b.intake_id, inputHash: b.input_hash, epoch: b.epoch },
          'legacy',
          '1',
        ),
      ).toEqual(specimen.response)
    })
})
