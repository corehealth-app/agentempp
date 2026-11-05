-- Run after the before-DDL fixture and exact concrete migration, in rollback.
DO $legacy_energy$
DECLARE x record;u uuid;s uuid;last_day date;period text;packet jsonb;before_state jsonb;
BEGIN
 FOR x IN SELECT * FROM workout_legacy_energy_original ORDER BY (kind='unknown') DESC LOOP
  u:=(x.q->>'user')::uuid;s:=(x.q->>'snapshot')::uuid;last_day:=(clock_timestamp() AT TIME ZONE (x.q->>'zone'))::date;
  PERFORM m3b_cycle_test.ok((SELECT exercise_energy_complete=(x.kind='known_zero') FROM public.daily_snapshots WHERE id=s)
   AND (SELECT xp_total=20 AND deficit_block=400 FROM public.user_progress WHERE user_id=u),'legacy '||x.kind||' backfill keeps original ledger/XP');
  UPDATE public.workout_logs SET estimated_kcal=0 WHERE user_id=u;
  PERFORM m3b_cycle_test.ok((SELECT exercise_energy_complete AND exercise_calories=0 FROM public.daily_snapshots WHERE id=s),'legacy '||x.kind||' physical known-zero repair is complete');
  FOREACH period IN ARRAY ARRAY['semana','mes'] LOOP
   before_state:=m3b_cycle_test.original_state(u);
   packet:=private.get_mobile_clinical_flow_period_at(u,period,last_day-CASE WHEN period='semana' THEN 6 ELSE 29 END,last_day,NULL);
   PERFORM m3b_cycle_test.ok(packet#>'{rows,0,balance_proven}'=to_jsonb(x.kind='known_zero')
    AND packet#>'{rows,0,daily_balance}'=CASE WHEN x.kind='known_zero' THEN '-400'::jsonb ELSE 'null'::jsonb END
    AND packet#>'{rows,0,calories_consumed}'='1600'::jsonb AND packet#>'{rows,0,protein_g}'='100'::jsonb,'pre-DDL '||x.kind||' preserves correct Flow '||period||' proof after repair0');
   PERFORM m3b_cycle_test.ok(before_state=m3b_cycle_test.original_state(u),'legacy '||x.kind||' period is read only '||period);
  END LOOP;
  PERFORM m3b_cycle_test.ok((SELECT count(*)=CASE WHEN x.kind='unknown' THEN 1 ELSE 0 END FROM private.mobile_clinical_unknown_exercise_evidence WHERE snapshot_id=s AND user_id=u),'only proven unavailable historical evidence receives immutable witness');
  PERFORM m3b_cycle_test.ok(public.get_mobile_clinical_day_close_receipt(u,x.k)=x.r AND m3b_cycle_test.close_apply(x.q,x.c,x.k,x.e)=x.r
   AND (SELECT xp_total=20 AND deficit_block=400 FROM public.user_progress WHERE user_id=u),'legacy '||x.kind||' original receipt/ledger remain exact after repair0');
  IF x.kind='unknown' THEN
   PERFORM m3b_cycle_test.throws(format('DELETE FROM private.mobile_clinical_unknown_exercise_evidence WHERE snapshot_id=%L',s),'55000','unavailable historical witness cannot be erased while parent exists');
   PERFORM m3b_cycle_test.throws(format('UPDATE private.mobile_clinical_unknown_exercise_evidence SET user_id=user_id WHERE snapshot_id=%L',s),'55000','unavailable historical witness cannot be rewritten');
   PERFORM public.reset_user_conversation_atomic(u,true);
   PERFORM m3b_cycle_test.ok(NOT EXISTS(SELECT 1 FROM private.mobile_clinical_unknown_exercise_evidence WHERE user_id=u)
    AND public.get_mobile_clinical_day_close_receipt(u,x.k)=x.r,'owned reset cascades witness while preserving original receipt');
  END IF;
 END LOOP;
END $legacy_energy$;
DO $$ DECLARE actor text;BEGIN
 FOREACH actor IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM m3b_cycle_test.ok(NOT has_table_privilege(actor,'private.mobile_clinical_unknown_exercise_evidence','SELECT,INSERT,UPDATE,DELETE'),'historical unavailable witness has no direct '||actor||' grants');
 END LOOP;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
