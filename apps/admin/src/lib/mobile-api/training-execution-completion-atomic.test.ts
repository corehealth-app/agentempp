import { describe, expect, it, vi } from 'vitest'
import golden from './testing/training-completion-pg-golden.json'
import { createTrainingExecutionCompletionBackend } from './training-execution-completion-backend'
import { bindTrainingExecutionCompletion } from './training-execution-completion-contracts'

// The external RPC is the boundary double. All command, source, preparation,
// effect and linked completion decoders below are the real production code.
function setup() {
  const g = structuredClone(golden),
    bound = bindTrainingExecutionCompletion(
      g.begin.scope.owner_id,
      `tfinish1:${g.command.operation_id}`,
      g.command,
    ),
    packet = {
      status: 'saved',
      source: g.source,
      preparation: g.preparation,
      effect: g.effect,
      completion: g.completed,
    },
    rpc = vi.fn(async (_name: string, _args: Readonly<Record<string, unknown>>) => ({
      data: packet as unknown,
      error: null,
    })),
    check = vi.fn(async () => true),
    backend = createTrainingExecutionCompletionBackend(
      { rpc },
      {
        owner_id: bound.ownerId,
        auth_user_id: g.begin.scope.auth_user_id,
        auth_session_id: '139d0000-0000-4000-8000-000000000005',
        checkCurrentScope: check,
      },
    )
  return { g, bound, packet, rpc, check, backend }
}

describe('bounded original-login training completion transaction', () => {
  it('proves the existing workout effect and exact linked completion with one domain round trip', async () => {
    const h = setup(),
      result = await h.backend.submitAtomic(h.bound)
    expect(result).toMatchObject({ status: 'saved', effect: h.g.effect, completion: h.g.completed })
    expect(h.rpc.mock.calls).toEqual([
      [
        'submit_training_execution_completion_authenticated',
        {
          p_user_id: h.bound.ownerId,
          p_auth_user_id: h.g.begin.scope.auth_user_id,
          p_auth_session_id: '139d0000-0000-4000-8000-000000000005',
          p_command: h.g.command,
        },
      ],
    ])
    expect(h.check).toHaveBeenCalledTimes(2)
  })
  it.each([
    'source',
    'preparation',
    'effect',
    'completion',
  ] as const)('never accepts a changed %s as a completed registration', async (field) => {
    const h = setup()
    h.packet[field] = {} as never
    await expect(h.backend.submitAtomic(h.bound)).rejects.toThrow()
  })
  it('refuses a same-shaped different official workout receipt', async () => {
    const h = setup()
    h.packet.completion.completion.receipt.workout.workout_id = h.g.command.session_id
    await expect(h.backend.submitAtomic(h.bound)).rejects.toThrow()
  })
  it('does not send when the original scope is unavailable', async () => {
    const h = setup()
    h.check.mockResolvedValue(false)
    await expect(h.backend.submitAtomic(h.bound)).rejects.toThrow()
    expect(h.rpc).not.toHaveBeenCalled()
  })
  it('does not publish a completion after the post-transaction scope changes', async () => {
    const h = setup()
    h.check.mockResolvedValueOnce(true).mockResolvedValue(false)
    await expect(h.backend.submitAtomic(h.bound)).rejects.toThrow()
  })
  it('an unknown transport outcome is not retried or treated as an acknowledgement', async () => {
    const h = setup()
    h.rpc.mockRejectedValue(new Error('Lost response after possible commit'))
    await expect(h.backend.submitAtomic(h.bound)).rejects.toThrow()
    expect(h.rpc).toHaveBeenCalledTimes(1)
  })
})
