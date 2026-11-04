import { bindConversationCommand } from '../conversation-command-contracts'
import { writerBinding, writerEpoch, writerOwner, writerReceipt } from './conversation-meal-writer'
export const threadReplyId = '10000000-0000-4000-8000-000000000041'
export function threadDescriptor() {
  const original = {
    command_protocol: 'conversation.command.v1',
    command_id: writerBinding().command_id,
    kind: 'meal.report',
    meal_type: 'almoco',
    source: { channel: 'text', text: 'Comi leite' },
  }
  const bound = bindConversationCommand(writerOwner, `cmsg1:${original.command_id}`, original)
  return {
    schema: 'conversation.meal-thread.v1',
    thread_id: bound.commandId,
    parent_binding: { ...writerBinding(), input_hash: bound.inputHash },
    original_command: original,
    terminal_receipt: {
      schema: 'conversation.meal-decision-public.v1',
      status: 'not_recorded',
      owner_id: writerOwner,
      command_id: bound.commandId,
      input_hash: bound.inputHash,
      epoch: writerEpoch,
      reason: 'missing_quantity',
      food_indexes: [0],
      decision_hash: 'd'.repeat(64),
      sealed_at: '2026-11-04T12:00:00.000009Z',
    },
    continuation: { revision: 1, question: null, fulfilled_by: threadReplyId },
  }
}
export function threadQuestion() {
  return {
    schema: 'conversation.meal-question.v1',
    question_key: 'e'.repeat(64),
    revision: 0,
    kind: 'quantity',
    food_index: 0,
    food_name: 'leite',
    allowed_units: ['g', 'kg', 'mL', 'L', 'caneca'],
    quantity_reference: {
      unit: 'mL',
      grams_per_unit: 1.03,
      reference_id: 'fao-infoods-v2-whole-milk-tb',
      estimated: true,
    },
  }
}
export function threadChild() {
  return {
    ...writerBinding(),
    command_id: threadReplyId,
    input_hash: 'f'.repeat(64),
    command_protocol: 'conversation.clarification.v1',
    kind: 'meal.clarify',
    admitted_at: '2026-11-04T12:00:01.000001Z',
  }
}
export function threadReply() {
  const q = threadQuestion()
  return {
    event_id: `reply/${threadDescriptor().thread_id}/${threadReplyId}`,
    at: threadChild().admitted_at,
    kind: 'reply',
    thread_id: threadDescriptor().thread_id,
    child_binding: threadChild(),
    body: {
      schema: 'conversation.meal-clarification.v1',
      expected_revision: 0,
      question_key: q.question_key,
      answer: { kind: 'quantity', food_index: 0, amount: 200, unit: 'mL' },
    },
    question: q,
  }
}
export function threadResult() {
  return {
    event_id: `reply-result/${threadDescriptor().thread_id}/${threadReplyId}`,
    at: '2026-11-04T12:00:02.000001Z',
    kind: 'reply_result',
    thread_id: threadDescriptor().thread_id,
    child_binding: threadChild(),
    prepared_hash: 'a'.repeat(64),
    status: 'prepared',
    next_question: null,
  }
}
export function threadFulfillment() {
  const p = threadDescriptor(),
    c = threadChild()
  return {
    event_id: `fulfillment/${p.thread_id}/${threadReplyId}`,
    at: '2026-11-04T12:00:03.000001Z',
    kind: 'fulfillment',
    thread_id: p.thread_id,
    child_binding: c,
    receipt: {
      ...writerReceipt(),
      schema: 'conversation.meal-continuation-effect.v1',
      command_id: c.command_id,
      input_hash: c.input_hash,
      parent_command_id: p.thread_id,
      parent_input_hash: p.parent_binding.input_hash,
      parent_decision_hash: p.terminal_receipt.decision_hash,
      epoch: writerEpoch,
      registration_id: c.command_id,
      provider_key: `conversation.clarification/${writerOwner}/${p.thread_id}`,
      consumed_at: '2026-11-04T12:00:03.000001Z',
    },
    feedback_ref: null,
  }
}
export function threadReport() {
  const p = threadDescriptor()
  return {
    event_id: `command/${p.thread_id}`,
    at: p.parent_binding.admitted_at,
    kind: 'report',
    thread_id: p.thread_id,
    status: 'not_recorded',
    receipt: null,
    feedback_ref: null,
  }
}
export function threadPage() {
  return {
    action: 'available',
    schema: 'conversation.journal-page-private.v2',
    owner_id: writerOwner,
    epoch: writerEpoch,
    observed_at: '2026-11-04T12:02:00.000002Z',
    threads: [threadDescriptor()],
    items: [threadFulfillment(), threadResult(), threadReply(), threadReport()],
    has_more: false,
    next_cursor: null,
  }
}
export function threadQuery() {
  return { ownerId: writerOwner, epoch: writerEpoch, limit: 10, cursor: null }
}

export function threadSavedReport(
  command: ReturnType<typeof import('./conversation-journal').journalCommand>,
) {
  if (!command.receipt) throw new Error('Synthetic saved receipt required')
  return {
    descriptor: {
      schema: 'conversation.meal-thread.v1',
      thread_id: command.command.command_id,
      parent_binding: command.command,
      original_command: command.source_input,
      terminal_receipt: null,
      continuation: null,
    },
    event: {
      event_id: command.event_id,
      at: command.at,
      kind: 'report',
      thread_id: command.command.command_id,
      status: 'registered',
      receipt: command.receipt,
      feedback_ref: {
        schema: 'registration.feedback.v2',
        registration_id: command.receipt.registration_id,
      },
    },
  }
}

export function threadEdit() {
  const f = threadFulfillment(),
    c = threadChild(),
    operation = '10000000-0000-4000-8000-000000000080',
    added = '10000000-0000-4000-8000-000000000081'
  return {
    event_id: `edit/${c.command_id}/${operation}`,
    at: '2026-11-04T12:00:04.123456Z',
    kind: 'edit',
    thread_id: f.thread_id,
    effect_binding: c,
    receipt: {
      schema: 'conversation.meal-edit-effect-public.v1',
      owner_id: c.owner_id,
      command_id: c.command_id,
      operation_id: operation,
      input_hash: 'c'.repeat(64),
      kind: 'saved',
      revision: 1,
      applied_at: '2026-11-04T12:00:04.123456+00:00',
      undo_expires_at: '2026-11-04T12:05:04.123456+00:00',
      target_operation_id: null,
      removed_item_ids: [f.receipt.log_ids[0]],
      new_item_ids: [added],
      next_record_id: added,
    },
  }
}
export function threadGoldenPage() {
  return { ...threadPage(), items: [threadEdit(), ...threadPage().items] }
}
