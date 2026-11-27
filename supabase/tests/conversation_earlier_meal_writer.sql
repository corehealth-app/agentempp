BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
SET LOCAL timezone='UTC';
SET LOCAL datestyle='ISO,YMD';
\ir fixtures/conversation_meal_atomic_writer_fixture.sql

CREATE FUNCTION pg_temp.earlier_meal_command(u uuid,e uuid,reason text,
  message text DEFAULT 'Ontem comi 100 g de arroz sintetico no almoço.') RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  id uuid:=gen_random_uuid();
  raw jsonb;
  admission jsonb;
  captured jsonb;
  claimed jsonb;
  selected jsonb;
BEGIN
  raw:=jsonb_build_object('intake_protocol','conversation.intake.v1','intake_id',id,
    'meal_type_hint','almoco','source',jsonb_build_object('channel','text',
    'text',message));
  admission:=public.admit_conversation_intake(u,e,raw);
  captured:=public.capture_conversation_intake_source(u,id,admission#>>'{intake,input_hash}',e);
  claimed:=public.claim_conversation_intake_routing(u,id,admission#>>'{intake,input_hash}',e,captured->>'source_hash');
  selected:=public.seal_conversation_intake_routing(u,id,admission#>>'{intake,input_hash}',e,
    captured->>'source_hash',(claimed->>'claim_id')::uuid,
    jsonb_build_object('schema','conversation.intake-routing.v1','kind','meal.report','reason',reason));
  IF selected->>'action' IS DISTINCT FROM 'sealed' OR selected#>>'{selection,command,command_id}' IS NULL THEN
    RAISE EXCEPTION 'test_selection_not_sealed';
  END IF;
  RETURN (selected#>>'{selection,command,command_id}')::uuid;
END $$;

DO $test$
DECLARE
  u uuid:='c3ed0000-0000-4000-8000-000000000091';
  other_owner uuid:='c3ed0000-0000-4000-8000-000000000092';
  e uuid:=gen_random_uuid();
  other_epoch uuid:=gen_random_uuid();
  zone constant text:='America/Sao_Paulo';
  today date:=(clock_timestamp() AT TIME ZONE zone)::date;
  child uuid;
  source jsonb;
  prepared jsonb;
  result jsonb;
  receipt jsonb;
  page jsonb;
  saved private.conversation_meal_effects%ROWTYPE;
  cmd private.conversation_meal_command_ids%ROWTYPE;
  altered_text text;
  refused boolean;
BEGIN
  INSERT INTO public.users(id,email,status,timezone,country,country_confirmed) VALUES
    (u,'meal-date-test@example.invalid','active',zone,'BR',true),
    (other_owner,'meal-date-other@example.invalid','active',zone,'BR',true);
  INSERT INTO private.workout_strength_authority_epochs(user_id,epoch,changed_at)
    VALUES(u,e,clock_timestamp()),(other_owner,other_epoch,clock_timestamp());
  INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target)
    VALUES(u,today,1900,120),(u,today-1,1700,110),(other_owner,today-1,1500,100);

  child:=pg_temp.earlier_meal_command(u,e,'verified_meal_yesterday');
  source:=public.capture_conversation_meal_source(u,child);
  PERFORM pg_temp.writer_ok(source#>>'{context,day,date}'=(today-1)::text
    AND source#>>'{context,day,calories_target}'='1700',
    'yesterday is authoritative and retains its own official goals');
  prepared:=public.prepare_conversation_meal(u,child,pg_temp.writer_resolved(source));
  result:=public.commit_conversation_meal(u,child,prepared->>'resolved_hash');
  receipt:=result->'receipt';
  PERFORM pg_temp.writer_ok(result->>'action'='committed' AND receipt->>'schema'='conversation.meal-effect.v2'
    AND receipt->>'local_date'=(today-1)::text
    AND ((receipt->>'committed_at')::timestamptz AT TIME ZONE zone)::date=today,
    'the receipt separates the occurrence date and the actual save time');
  PERFORM pg_temp.writer_ok((SELECT count(*)=1 AND bool_and((m.consumed_at AT TIME ZONE zone)::date=today-1)
      FROM public.meal_logs m JOIN public.daily_snapshots d ON d.id=m.snapshot_id
      WHERE m.user_id=u AND d.user_id=u AND d.date=today-1)
    AND NOT EXISTS(SELECT 1 FROM public.meal_logs m JOIN public.daily_snapshots d ON d.id=m.snapshot_id
      WHERE (m.user_id=u AND d.date=today) OR m.user_id=other_owner),
    'the food is recorded only on the intended owner and day');
  PERFORM pg_temp.writer_ok(public.commit_conversation_meal(u,child,prepared->>'resolved_hash')
    =jsonb_build_object('action','replay','receipt',receipt),
    'retry returns the same receipt without another write');
  SELECT * INTO STRICT saved FROM private.conversation_meal_effects WHERE user_id=u AND command_id=child;
  SELECT * INTO STRICT cmd FROM private.conversation_meal_command_ids WHERE user_id=u AND command_id=child;
  PERFORM pg_temp.writer_ok(private.conversation_thread_effect_v2(saved,cmd,NULL)=receipt,
    'the thread accepts the actual historical meal with its two clocks');
  page:=public.read_conversation_meal_journal_page_v2(u,e);
  PERFORM pg_temp.writer_ok(page->>'action'='available'
    AND EXISTS(SELECT 1 FROM jsonb_array_elements(page->'items') item
      WHERE item->'receipt'=receipt),
    'the meal journal restores the exact original historical receipt');
  page:=private.capture_mobile_registration_feedback_v3(u,(receipt->>'registration_id')::uuid,'pending_registration');
  PERFORM pg_temp.writer_ok(page#>'{source,command,receipt}'=receipt
    AND page->>'local_date'=(today-1)::text AND page#>>'{snapshot,calories_target}'='1700',
    'feedback reads the same frozen registration and goals for its reported day');

  child:=pg_temp.earlier_meal_command(other_owner,other_epoch,'performed_meal');
  source:=public.capture_conversation_meal_source(other_owner,child);
  PERFORM pg_temp.writer_ok(source#>>'{context,day,date}'=today::text,
    'legacy selections keep their established current-day authority');

  FOREACH altered_text IN ARRAY ARRAY[
    'Comi 100 g de arroz que preparei ontem.',
    'Anteontem comi 100 g de arroz.',
    'Ontem não comi 100 g de arroz.'
  ] LOOP
    child:=pg_temp.earlier_meal_command(other_owner,other_epoch,'verified_meal_yesterday',altered_text);
    refused:=false;
    BEGIN
      PERFORM public.capture_conversation_meal_source(other_owner,child);
    EXCEPTION WHEN serialization_failure THEN refused:=true;
    END;
    PERFORM pg_temp.writer_ok(refused,'a mismatched source cannot authorize yesterday: '||altered_text);
  END LOOP;

  child:=pg_temp.earlier_meal_command(other_owner,other_epoch,'verified_meal_yesterday');
  source:=public.capture_conversation_meal_source(other_owner,child);
  prepared:=public.prepare_conversation_meal(other_owner,child,pg_temp.writer_resolved(source));
  UPDATE public.daily_snapshots SET day_closed=true WHERE user_id=other_owner AND date=today-1;
  PERFORM pg_temp.writer_ok(public.commit_conversation_meal(other_owner,child,prepared->>'resolved_hash')
    ='{"action":"day_closed"}'::jsonb
    AND NOT EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=other_owner),
    'closing the historical day after preparation prevents both a save and a fallback to today');

  child:=pg_temp.earlier_meal_command(other_owner,other_epoch,'verified_meal_yesterday');
  PERFORM pg_temp.writer_ok(public.capture_conversation_meal_source(other_owner,child)
    ='{"action":"day_closed"}'::jsonb,'an already closed day cannot start a historical write');
END $test$;

SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS earlier_meal_writer_assertions FROM meal_writer_assertions;
ROLLBACK;
