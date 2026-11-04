import { bindConversationCommand } from '../conversation-command-contracts'
import { readCurrentClinicalState } from '../current-clinical-state'
import { editReceipt } from './conversation-meal-edit'
import {
  writerBinding,
  writerCommand,
  writerEpoch,
  writerReceipt,
} from './conversation-meal-writer'
import { auth, clinical } from './feedback-v2-source'

export function journalAuth() {
  return structuredClone(auth)
}
export function journalClinical(at = '2026-11-04T12:03:00.000001Z') {
  const value = clinical()
  return structuredClone(
    readCurrentClinicalState(
      {
        ...value,
        epoch: writerEpoch,
        observed_at: at,
        date: '2026-11-04',
        safety: { ...value.safety, date: '2026-11-04', observed_at: at },
      },
      auth.userId,
    ),
  )
}
export function journalDecision() {
  const b = writerBinding()
  const indexes: number[] = []
  return {
    schema: 'conversation.meal-decision.v1',
    status: 'not_recorded',
    reason: 'future',
    food_indexes: indexes,
    owner_id: b.owner_id,
    command_id: b.command_id,
    epoch: b.epoch,
    input_hash: b.input_hash,
    source_hash: 'b'.repeat(64),
    attempt_id: '10000000-0000-4000-8000-000000000080',
    semantic_result_hash: 'c'.repeat(64),
    decision_hash: 'd'.repeat(64),
    sealed_at: '2026-11-04T12:01:00.000004Z',
  }
}
export function journalCommand(status = 'pending') {
  return {
    event_id: `command/${writerCommand().commandId}`,
    at: writerBinding().admitted_at,
    kind: 'command',
    command: writerBinding(),
    source_input: writerCommand().command,
    status,
    receipt: status === 'registered' ? writerReceipt() : null,
    decision: status === 'not_recorded' ? journalDecision() : null,
  }
}
export function anotherJournalCommand(id: string, at: string, status = 'pending') {
  const source = { ...writerCommand().command, command_id: id },
    command = bindConversationCommand(writerCommand().ownerId, `cmsg1:${id}`, source),
    raw = journalCommand(status)
  return {
    ...raw,
    event_id: `command/${id}`,
    at,
    source_input: source,
    command: { ...writerBinding(), command_id: id, input_hash: command.inputHash, admitted_at: at },
    receipt:
      status === 'registered'
        ? {
            ...writerReceipt(),
            command_id: id,
            input_hash: command.inputHash,
            provider_key: `conversation.meal/${command.ownerId}/${id}`,
            registration_id: id,
            log_ids: [id],
          }
        : null,
    decision:
      status === 'not_recorded'
        ? { ...journalDecision(), command_id: id, input_hash: command.inputHash, attempt_id: id }
        : null,
  }
}
export function journalEdit() {
  const r = editReceipt('e'.repeat(64))
  return {
    event_id: `edit/${r.command_id}/${r.operation_id}`,
    at: '2026-11-04T12:01:00.123456Z',
    kind: 'edit',
    command: writerBinding(),
    receipt: r,
  }
}
export function journalPage(items: unknown[] = [journalCommand()]) {
  return {
    action: 'available',
    owner_id: writerCommand().ownerId,
    epoch: writerEpoch,
    items,
    has_more: false,
    next_cursor: null,
  }
}
export function journalQuery() {
  return { ownerId: writerCommand().ownerId, epoch: writerEpoch, limit: 10, cursor: null }
}
export function journalFixturePage() {
  const terminal = anotherJournalCommand(
    '10000000-0000-4000-8000-000000000009',
    '2026-11-04T12:00:00.000003Z',
    'not_recorded',
  )
  if (!terminal.decision) throw new Error('Required synthetic decision absent')
  terminal.decision.reason = 'nutrition_unresolved'
  terminal.decision.food_indexes = [0]
  return journalPage([
    journalEdit(),
    terminal,
    anotherJournalCommand('10000000-0000-4000-8000-000000000008', '2026-11-04T12:00:00.000002Z'),
    journalCommand('registered'),
  ])
}
