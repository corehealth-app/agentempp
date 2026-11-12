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
    function setup(mediaEnabled?: () => boolean) {
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
      scope.date = scope.safety.date = '2026-11-06'
      scope.observed_at = scope.safety.observed_at = '2026-11-06T04:00:00.000001Z'
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
      const driver = createConversationIntakeDriver({ ...ports, mediaEnabled }),
        lookup = {
          ownerId: binding.owner_id,
          intakeId: binding.intake_id,
          inputHash: binding.input_hash,
          epoch: binding.epoch,
        }
      return { ports, driver, command, lookup, available }
    }
    for (const path of ['submit', 'read'] as const)
      it(`publishes the actual media lineage only after explicit negotiation on ${path}`, async () => {
        const f = setup(() => true),
          child = f.available.selection.command
        if (!child) throw new Error('Actual SQL selection is missing its child')
        const pending = {
          schema:
            child.kind === 'meal.report'
              ? 'conversation.meal-command-state.v1'
              : 'conversation.workout-command-state.v1',
          status: 'pending',
          owner_id: child.owner_id,
          command_id: child.command_id,
          input_hash: child.input_hash,
          epoch: child.epoch,
          reason: 'writer_reconciliation_required',
        } as const
        for (const domain of Object.values(f.ports.domains))
          for (const fn of Object.values(domain)) vi.mocked(fn).mockResolvedValue(pending)
        const result =
          path === 'read'
            ? await f.driver.read(f.lookup, 'legacy', '1')
            : await f.driver.submit(f.command, f.lookup.epoch, 'legacy', '1')
        expect(result).toMatchObject({
          schema: 'conversation.intake-result.v2',
          status: 'selected',
          intake: f.available.intake,
          selection: {
            media_projection: row.selection.selection.media_projection,
            command: {
              command_id: child.command_id,
              input_hash: child.input_hash,
            },
          },
          result: pending,
        })
        expect(result).not.toHaveProperty('selection.command.input')
        if (result.status !== 'selected') throw new Error('Expected selected typed observation')
        expect(result.result.status).not.toBe('saved')
      })
    for (const stage of ['admitted', 'captured', 'claimed'] as const)
      it(`reports genuine unselected ${stage} media pending on opted-in GET without repairing it`, async () => {
        const f = setup(() => true)
        vi.mocked(f.ports.store.read).mockResolvedValue({
          ...f.available,
          selection: null,
          claimed: stage === 'claimed',
          source_hash: stage === 'admitted' ? null : f.available.source_hash,
        })
        expect(await f.driver.read(f.lookup, 'legacy', '1')).toEqual({
          schema: 'conversation.intake-result.v1',
          status: 'pending',
          lookup: f.lookup,
          intake: f.available.intake,
          reason: stage === 'claimed' ? 'routing_reconciliation_required' : 'intake_pending',
        })
        expect(f.ports.store.read).toHaveBeenCalledTimes(1)
        expect(f.ports.createRouter).not.toHaveBeenCalled()
        for (const fn of [
          f.ports.store.admit,
          f.ports.store.capture,
          f.ports.store.claim,
          f.ports.store.seal,
          f.ports.recovery.read,
          f.ports.recovery.reconcile,
          ...Object.values(f.ports.domains.meal),
          ...Object.values(f.ports.domains.workout),
        ])
          expect(fn).not.toHaveBeenCalled()
      })
    for (const selected of [false, true])
      it(`keeps opted-in disabled media temporary rather than marking a changed original (selected=${selected})`, async () => {
        const f = setup(() => false)
        if (!selected)
          vi.mocked(f.ports.store.read).mockResolvedValue({
            ...f.available,
            selection: null,
            claimed: false,
          })
        for (const path of ['read', 'submit'] as const) {
          const result =
            path === 'read'
              ? await f.driver.read(f.lookup, 'legacy', '1')
              : await f.driver.submit(f.command, f.lookup.epoch, 'legacy', '1')
          expect(result).toMatchObject({
            status: 'held',
            reason: 'media_temporarily_unavailable',
            intake: f.available.intake,
          })
          expect(result).not.toHaveProperty('result')
        }
        expect(f.ports.createRouter).not.toHaveBeenCalled()
        for (const domain of Object.values(f.ports.domains))
          for (const fn of Object.values(domain)) expect(fn).not.toHaveBeenCalled()
      })
    it('does not reuse a disabled GET as a capability grant and observes reenablement only on another read', async () => {
      let enabled = false
      const f = setup(() => enabled)
      vi.mocked(f.ports.store.read).mockResolvedValue({
        ...f.available,
        selection: null,
        claimed: false,
      })
      expect(await f.driver.read(f.lookup, 'legacy', '1')).toMatchObject({
        status: 'held',
        reason: 'media_temporarily_unavailable',
      })
      enabled = true
      expect(await f.driver.read(f.lookup, 'legacy', '1')).toMatchObject({
        status: 'pending',
        reason: 'intake_pending',
      })
      expect(f.ports.store.read).toHaveBeenCalledTimes(2)
      for (const fn of [
        f.ports.store.admit,
        f.ports.store.capture,
        f.ports.store.claim,
        f.ports.store.seal,
        f.ports.recovery.reconcile,
      ])
        expect(fn).not.toHaveBeenCalled()
    })
    it('keeps negotiated media held when the trusted capability is off', async () => {
      const f = setup(() => false)
      expect(await f.driver.submit(f.command, f.lookup.epoch, 'legacy', '1')).toMatchObject({
        schema: 'conversation.intake-result.v1',
        status: 'held',
        reason: 'media_temporarily_unavailable',
      })
    })
    it('does not treat trusted enablement as client negotiation', async () => {
      const f = setup(() => true)
      expect(await f.driver.read(f.lookup)).toMatchObject({
        schema: 'conversation.intake-result.v1',
        status: 'held',
        reason: 'media_projection_required',
      })
    })
    it('routes and seals a fresh processed attachment before exposing its genuine typed observation', async () => {
      const f = setup(() => true),
        binding = f.available.intake,
        selected = f.available.selection,
        child = selected.command
      if (!child) throw new Error('Actual SQL selection is missing its child')
      vi.mocked(f.ports.store.read).mockResolvedValueOnce({ action: 'absent' })
      vi.mocked(f.ports.store.admit).mockResolvedValue({ action: 'admitted', intake: binding })
      vi.mocked(f.ports.store.capture).mockResolvedValue({
        action: 'captured',
        source_hash: selected.source_hash,
        context: {
          schema: 'conversation.intake-source.v1',
          ...binding,
          source_input: f.command.input,
          captured_at: child.admitted_at,
          time_zone: 'UTC',
          local_date: '2026-11-06',
          media: row.source.context.media,
        },
      })
      vi.mocked(f.ports.store.claim).mockResolvedValue({
        action: 'claimed',
        claim_id: row.selection.selection.media_projection.origin.claim_id,
      })
      vi.mocked(f.ports.store.seal).mockResolvedValue({ action: 'sealed', selection: selected })
      vi.mocked(f.ports.createRouter).mockReturnValue({ route: async () => selected.decision })
      const pending = {
        schema:
          child.kind === 'meal.report'
            ? ('conversation.meal-command-state.v1' as const)
            : ('conversation.workout-command-state.v1' as const),
        status: 'pending' as const,
        owner_id: child.owner_id,
        command_id: child.command_id,
        input_hash: child.input_hash,
        epoch: child.epoch,
        reason: 'writer_reconciliation_required',
      }
      for (const domain of Object.values(f.ports.domains))
        for (const fn of Object.values(domain)) vi.mocked(fn).mockResolvedValue(pending)
      expect(await f.driver.submit(f.command, binding.epoch, 'legacy', '1')).toMatchObject({
        schema: 'conversation.intake-result.v2',
        status: 'selected',
        selection: { media_projection: selected.media_projection },
        result: pending,
      })
    })
    it('continues the same original only on POST and never routes again during selected GET replay', async () => {
      const f = setup(() => true),
        selected = f.available.selection,
        binding = f.available.intake,
        child = selected.command
      if (!child) throw new Error('Actual SQL child is required')
      vi.mocked(f.ports.store.read).mockResolvedValue({
        ...f.available,
        selection: null,
        claimed: false,
      })
      expect(await f.driver.read(f.lookup, 'legacy', '1')).toMatchObject({
        status: 'pending',
        reason: 'intake_pending',
      })
      expect(f.ports.store.capture).not.toHaveBeenCalled()
      expect(f.ports.store.claim).not.toHaveBeenCalled()
      vi.mocked(f.ports.store.capture).mockResolvedValue({
        action: 'captured',
        source_hash: selected.source_hash,
        context: {
          schema: 'conversation.intake-source.v1',
          ...binding,
          source_input: f.command.input,
          captured_at: child.admitted_at,
          time_zone: 'UTC',
          local_date: '2026-11-06',
          media: row.source.context.media,
        },
      })
      vi.mocked(f.ports.store.claim).mockResolvedValue({
        action: 'claimed',
        claim_id: row.selection.selection.media_projection.origin.claim_id,
      })
      vi.mocked(f.ports.store.seal).mockImplementation(async () => {
        vi.mocked(f.ports.store.read).mockResolvedValue(f.available)
        return { action: 'sealed', selection: selected }
      })
      const route = vi.fn(async () => selected.decision)
      vi.mocked(f.ports.createRouter).mockReturnValue({ route })
      const pending = {
        schema:
          child.kind === 'meal.report'
            ? ('conversation.meal-command-state.v1' as const)
            : ('conversation.workout-command-state.v1' as const),
        status: 'pending' as const,
        owner_id: child.owner_id,
        command_id: child.command_id,
        input_hash: child.input_hash,
        epoch: child.epoch,
        reason: 'writer_reconciliation_required',
      }
      for (const domain of Object.values(f.ports.domains))
        for (const fn of Object.values(domain)) vi.mocked(fn).mockResolvedValue(pending)
      const result = await f.driver.submit(f.command, binding.epoch, 'legacy', '1')
      expect(result).toMatchObject({
        status: 'selected',
        selection: { media_projection: selected.media_projection },
        result: pending,
      })
      expect(await f.driver.read(f.lookup, 'legacy', '1')).toEqual(result)
      expect(route).toHaveBeenCalledTimes(1)
      expect(f.ports.store.claim).toHaveBeenCalledTimes(1)
      expect(f.ports.store.capture).toHaveBeenCalledTimes(1)
      expect(f.ports.store.admit).not.toHaveBeenCalled()
      expect(f.ports.recovery.reconcile).not.toHaveBeenCalled()
      expect(f.ports.store.capture).toHaveBeenCalledWith(f.command, binding.epoch)
    })
    it('refuses a typed result after the negotiated capability is revoked during its wait', async () => {
      let allowed = true
      const f = setup(() => allowed)
      for (const domain of Object.values(f.ports.domains))
        for (const fn of Object.values(domain))
          vi.mocked(fn).mockImplementation(async () => {
            allowed = false
            throw new Error('Synthetic interruption after capability revocation')
          })
      await expect(f.driver.read(f.lookup, 'legacy', '1')).rejects.toMatchObject({ status: 503 })
    })
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
