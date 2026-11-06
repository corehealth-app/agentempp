/** Synthetic UNIT capsules, not new PostgreSQL/HTTP qualification. Each is a
 * distinct original intake and typed child; they are not successive heads. */

import { threadDescriptor, threadQuestion } from '../__fixtures__/conversation-thread-page'
import { bindConversationCommand } from '../conversation-command-contracts'
import { bindConversationIntake } from '../conversation-intake-contracts'
import { workoutDigest } from '../conversation-workout-contracts'

export function mealOriginPage() {
  const sample = threadDescriptor(),
    owner = sample.parent_binding.owner_id,
    epoch = sample.parent_binding.epoch,
    routing = {
      schema: 'conversation.intake-routing.v1',
      kind: 'meal.report',
      reason: 'performed_meal',
    },
    rows = [0, 1]
      .map((index) => {
        const intakeID = `10000000-0000-4000-8000-00000000009${index}`,
          childID = `10000000-0000-4000-8000-00000000008${index}`,
          admitted = `2026-11-04T12:00:0${index}.000001Z`,
          childAt = `2026-11-04T12:00:0${index}.000002Z`,
          selected = `2026-11-04T12:00:0${index}.000003Z`,
          source = { channel: 'text', text: index === 0 ? 'Comi leite' : 'Comi 200 mL de leite' },
          input = { intake_protocol: 'conversation.intake.v1', intake_id: intakeID, source },
          original = bindConversationIntake(owner, `cintake1:${intakeID}`, input),
          command = {
            command_protocol: 'conversation.command.v1',
            kind: 'meal.report',
            command_id: childID,
            source,
          },
          child = bindConversationCommand(owner, `cmsg1:${childID}`, command),
          binding = {
            owner_id: owner,
            intake_id: intakeID,
            input_hash: original.inputHash,
            epoch,
            admitted_at: admitted,
          },
          childBinding = {
            ...sample.parent_binding,
            command_id: childID,
            input_hash: child.inputHash,
            admitted_at: childAt,
          },
          question =
            index === 0
              ? threadQuestion()
              : {
                  schema: 'conversation.meal-question.v1',
                  question_key: 'f'.repeat(64),
                  revision: 0,
                  kind: 'meal_type',
                  food_name: null,
                  food_index: null,
                  allowed_units: [],
                  quantity_reference: null,
                },
          thread = {
            ...sample,
            thread_id: childID,
            parent_binding: childBinding,
            original_command: command,
            terminal_receipt: {
              ...sample.terminal_receipt,
              command_id: childID,
              input_hash: child.inputHash,
              reason: index === 0 ? 'missing_quantity' : 'meal_type_required',
              food_indexes: index === 0 ? [0] : [],
              sealed_at: `2026-11-04T12:00:0${index}.000009Z`,
            },
            continuation: { revision: 0, question, fulfilled_by: null } as {
              revision: number
              question: unknown
              fulfilled_by: string | null
            } | null,
          }
        return {
          intake: {
            action: 'available',
            intake: binding,
            source_input: input,
            source_hash: 'a'.repeat(64),
            claimed: true,
            selection: {
              schema: 'conversation.intake-selection.v1',
              intake: binding,
              source_hash: 'a'.repeat(64),
              decision_hash: workoutDigest(routing),
              decision: routing,
              selected_at: selected,
              command: {
                kind: 'meal.report',
                owner_id: owner,
                command_id: childID,
                input_hash: child.inputHash,
                epoch,
                admitted_at: childAt,
                input: command,
              },
            },
          },
          thread,
          item: {
            kind: 'intake',
            event_id: `intake/${intakeID}`,
            at: admitted,
            intake_id: intakeID,
          },
          report: {
            kind: 'report',
            event_id: `command/${childID}`,
            at: childAt,
            thread_id: childID,
            status: 'not_recorded',
            receipt: null,
            feedback_ref: null,
          },
        }
      })
      .reverse()
  return {
    action: 'available',
    schema: 'conversation.journal-page-private.v3',
    owner_id: owner,
    epoch,
    observed_at: '2026-11-04T12:02:00.000002Z',
    intakes: rows.map((r) => r.intake),
    workouts: [],
    meal_page: {
      action: 'available',
      schema: 'conversation.journal-page-private.v2',
      owner_id: owner,
      epoch,
      observed_at: '2026-11-04T12:02:00.000002Z',
      threads: rows.map((r) => r.thread).sort((a, b) => a.thread_id.localeCompare(b.thread_id)),
      items: rows.map((r) => r.report),
      has_more: false,
      next_cursor: null,
    },
    items: rows.map((r) => r.item),
    has_more: false,
    next_cursor: null as { at: string; id: string } | null,
  }
}
