BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_edit_fixture.sql

DO $test$
DECLARE
  u uuid:='c3ed0000-0000-4000-8000-000000000081';
  a uuid:='c3ed0000-0000-4000-8000-000000000082';
  id uuid:='c3ed0000-0000-4000-8000-000000000083';
  cmd private.conversation_meal_command_ids%ROWTYPE;
  original private.conversation_meal_effects%ROWTYPE;
  earlier private.conversation_meal_effects%ROWTYPE;
  changed private.conversation_meal_effects%ROWTYPE;
  expected jsonb;
  earlier_stamp timestamptz;
  earlier_clock text;
  earlier_day date;
  own_zone text;
BEGIN
  PERFORM pg_temp.edit_seed(u,a,id,NULL,'America/Sao_Paulo');
  SELECT * INTO STRICT cmd FROM private.conversation_meal_command_ids
    WHERE user_id=u AND command_id=id;
  SELECT * INTO STRICT original FROM private.conversation_meal_effects
    WHERE user_id=u AND command_id=id;
  PERFORM pg_temp.writer_ok(private.conversation_thread_effect_v2(original,cmd,NULL)=original.receipt,
    'existing same-day receipts are still valid in the Flow thread');
  PERFORM pg_temp.writer_ok(private.conversation_meal_journal_receipt(original.receipt,false)=original.receipt,
    'existing journal shape is unchanged');

  -- Construct a sealed historical effect in memory to exercise the reader
  -- independently of the write path and preserve the real original effect.
  earlier:=original;
  own_zone:=original.receipt->>'timezone';
  earlier_day:=(cmd.admitted_at AT TIME ZONE own_zone)::date - 1;
  earlier_stamp:=(earlier_day + TIME '21:15') AT TIME ZONE own_zone;
  earlier_clock:=to_char(earlier_stamp AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
  earlier.original_facts:=jsonb_set(earlier.original_facts,'{logs,0,consumed_at}',to_jsonb(earlier_stamp));
  earlier.original_facts:=jsonb_set(earlier.original_facts,'{snapshot,date}',to_jsonb(earlier_day));
  earlier.original_facts:=jsonb_set(earlier.original_facts,'{confirmed,proposal,source_local_date}',to_jsonb(earlier_day));
  earlier.original_facts:=jsonb_set(earlier.original_facts,'{confirmed,proposal,source_timestamp}',to_jsonb(earlier_clock));
  earlier.receipt:=earlier.receipt||jsonb_build_object(
    'schema','conversation.meal-effect.v2',
    'consumed_at',earlier_clock,
    'committed_at',original.receipt->>'consumed_at',
    'local_date',earlier_day,
    'effect_version','cmeal1:'||encode(sha256(convert_to(private.conversation_command_canonical(earlier.original_facts),'UTF8')),'hex'));
  expected:=earlier.receipt;

  PERFORM pg_temp.writer_ok(private.conversation_thread_effect_v2(earlier,cmd,NULL)=expected,
    'earlier civil day survives reconciliation with the actual commit time');
  PERFORM pg_temp.writer_ok(private.conversation_meal_journal_receipt(expected,false)=expected,
    'the journal retains the exact commit clock for a previous-day receipt');
  changed:=earlier;
  changed.receipt:=jsonb_set(expected,'{committed_at}',to_jsonb(earlier_clock));
  PERFORM pg_temp.writer_ok(private.conversation_thread_effect_v2(changed,cmd,NULL) IS NULL,
    'a previous-day timestamp cannot stand in for the actual commit');
  changed:=earlier;
  changed.receipt:=expected-'committed_at';
  PERFORM pg_temp.writer_ok(private.conversation_thread_effect_v2(changed,cmd,NULL) IS NULL,
    'a previous-day receipt requires its independently verified commit time');
  changed:=earlier;
  changed.receipt:=jsonb_set(expected,'{local_date}',original.receipt->'local_date');
  PERFORM pg_temp.writer_ok(private.conversation_thread_effect_v2(changed,cmd,NULL) IS NULL,
    'a receipt cannot mislabel the civil day');
  cmd.admitted_at:=earlier_stamp-INTERVAL '1 minute';
  PERFORM pg_temp.writer_ok(private.conversation_thread_effect_v2(earlier,cmd,NULL) IS NULL,
    'crossing midnight while processing cannot turn the original day into a reported prior day');
END $test$;

SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS earlier_meal_receipt_assertions FROM meal_writer_assertions;
ROLLBACK;
