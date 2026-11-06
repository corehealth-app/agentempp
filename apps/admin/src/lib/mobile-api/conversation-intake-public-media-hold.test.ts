/** Real local SQL selections, with synthetic service/scope ports only. The
 * old public protocol cannot dispatch or ACK media before negotiation exists. */
import { describe, expect, it, vi } from 'vitest'
import actual from './__fixtures__/conversation-intake-media-actual.json'
import { clinical } from './__fixtures__/feedback-v2-source'
import {
  bindConversationIntake,
  parseConversationIntakeSelection,
} from './conversation-intake-contracts'
import {
  type ConversationIntakeDriverPorts,
  createConversationIntakeDriver,
} from './conversation-intake-driver'
import { readCurrentClinicalState } from './current-clinical-state'

for (const row of actual.cases)
  describe(`public media hold ${row.kind}`, () => {
    function setup() {
      const rawSelection = row.selection.selection,
        binding = rawSelection.intake,
        child = rawSelection.command
      const input = {
        intake_protocol: 'conversation.intake.v1',
        intake_id: binding.intake_id,
        source: child.input.source,
      }
      const command = bindConversationIntake(
        binding.owner_id,
        `cintake1:${binding.intake_id}`,
        input,
      )
      const selection = parseConversationIntakeSelection(command, binding, rawSelection)
      const available = {
        action: 'available' as const,
        intake: binding,
        source_input: command.input,
        source_hash: selection.source_hash,
        claimed: true,
        selection,
      }
      // The persisted selections above are actual PG output. Live scope is a
      // separate current-schema synthetic port, not the older captured profile.
      const scope = clinical()
      scope.user_id = binding.owner_id
      scope.epoch = binding.epoch
      scope.health_state.user_id = binding.owner_id
      const forbidden = () =>
        vi.fn(async () => {
          throw new Error('An old public protocol must not enter a media facade')
        })
      const ports: ConversationIntakeDriverPorts = {
        store: {
          read: vi.fn(async () => available),
          admit: forbidden(),
          capture: forbidden(),
          claim: forbidden(),
          seal: forbidden(),
        },
        recovery: {
          read: vi.fn(async () => ({
            action: 'available' as const,
            intake: binding,
            source_hash: selection.source_hash,
            claim_id: child.input.intake_origin.claim_id,
            lease_anchor_at: binding.admitted_at,
            lease_clock_origin: 'claim' as const,
            result: null,
          })),
          reconcile: forbidden(),
        },
        scope: {
          observeCurrentScope: async () => readCurrentClinicalState(scope, binding.owner_id),
        },
        createRouter: vi.fn(() => {
          throw new Error('An old public protocol must not create a media router')
        }),
        domains: {
          meal: { submit: forbidden(), read: forbidden() },
          workout: { submit: forbidden(), read: forbidden() },
        },
      }
      const driver = createConversationIntakeDriver(ports),
        lookup = {
          ownerId: binding.owner_id,
          intakeId: binding.intake_id,
          inputHash: binding.input_hash,
          epoch: binding.epoch,
        }
      return { ports, driver, command, lookup, available }
    }
    for (const path of ['submit', 'read', 'unknown-submit', 'concurrent-recovery'] as const)
      it(`keeps ${path} held with no typed submission/read`, async () => {
        const f = setup()
        if (path === 'unknown-submit')
          vi.mocked(f.ports.store.read).mockRejectedValueOnce(
            new Error('synthetic interrupted SDK read'),
          )
        if (path === 'concurrent-recovery')
          vi.mocked(f.ports.store.read).mockResolvedValueOnce({ ...f.available, selection: null })
        const result =
          path === 'read'
            ? await f.driver.read(f.lookup)
            : await f.driver.submit(f.command, f.lookup.epoch)
        expect(result).toMatchObject({
          schema: 'conversation.intake-result.v1',
          status: 'held',
          reason: 'media_projection_required',
          intake: f.available.intake,
        })
        expect(result).not.toHaveProperty('result')
        expect(result).not.toHaveProperty('selection')
        expect(f.ports.createRouter).not.toHaveBeenCalled()
        for (const domain of Object.values(f.ports.domains))
          for (const fn of Object.values(domain)) expect(fn).not.toHaveBeenCalled()
        for (const fn of [
          f.ports.store.admit,
          f.ports.store.capture,
          f.ports.store.claim,
          f.ports.store.seal,
          f.ports.recovery.reconcile,
        ])
          expect(fn).not.toHaveBeenCalled()
      })
  })
