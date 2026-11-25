-- Preserve the earlier server's proved questions while the new app rolls out.
-- This bridge cannot write an activity or replace a stored preparation.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE FUNCTION private.conversation_workout_report_without_spoken_suffix(c jsonb,h text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE units jsonb:=private.conversation_workout_units_v2(c);unit jsonb;v text;clause jsonb;rows jsonb;selected jsonb;
 activity jsonb;next jsonb;evidence jsonb:='[]';missing boolean:=false;minutes integer;n text;
BEGIN
 IF jsonb_array_length(units)=0 THEN RETURN private.conversation_workout_question_v2(c,h,'activity');END IF;
 FOR unit IN SELECT value FROM jsonb_array_elements(units) LOOP
  v:=private.conversation_workout_normalize_v2(unit->>'text');
  IF v ~ '\?' OR v ~ '\m(nao|nunca|amanha|ontem|sempre|costumo|faco|fazia|farei|faria|vou|iria|se|sonh[a-z0-9_]*|pai|mae|ele|ela|voce|voces|todos|toda|todo|semanalmente|diariamente)\M' THEN
   RETURN jsonb_build_object('owner_id',c->'owner_id','command_id',c->'command_id','input_hash',c->'input_hash','source_hash',h,'epoch',c->'epoch','status','not_reported','reason','non_performed_or_conflicting_source');END IF;
  clause:=private.conversation_workout_clause_v2(v);
  IF clause IS NULL THEN RETURN private.conversation_workout_question_v2(c,h,'activity');END IF;
  n:=clause->>'name';
  SELECT coalesce(jsonb_agg(x),'[]') INTO rows FROM jsonb_array_elements(c->'catalogue') x
   WHERE private.conversation_workout_normalize_v2(replace(x->>'slug','_',' '))=n OR private.conversation_workout_normalize_v2(x->>'display_name')=n;
  IF clause->>'intensity_label' IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(c->'catalogue') x WHERE
   private.conversation_workout_normalize_v2(replace(x->>'slug','_',' ')) IN(n||' '||(clause->>'intensity_label'),n||' '||(clause->>'intensity'))
   OR private.conversation_workout_normalize_v2(x->>'display_name') IN(n||' '||(clause->>'intensity_label'),n||' '||(clause->>'intensity'))) THEN
   RETURN private.conversation_workout_question_v2(c,h,'activity');END IF;
  selected:=rows->0;
  IF jsonb_array_length(rows)<>1 OR selected->>'slug'='outro' THEN RETURN private.conversation_workout_question_v2(c,h,'activity');END IF;
  minutes:=(clause->>'duration')::integer;
  IF minutes IS NULL THEN missing:=true;CONTINUE;END IF;
  IF minutes<1 OR minutes>1440 THEN RETURN private.conversation_workout_question_v2(c,h,'duration_min');END IF;
  next:=jsonb_build_object('workout_type',selected->'slug','duration_min',minutes,'intensity',clause->'intensity');
  IF activity IS NOT NULL AND activity IS DISTINCT FROM next THEN RETURN private.conversation_workout_question_v2(c,h,'activity');END IF;
  activity:=next;evidence:=evidence||jsonb_build_array(unit);
 END LOOP;
 IF missing OR activity IS NULL THEN RETURN private.conversation_workout_question_v2(c,h,'duration_min');END IF;
 RETURN jsonb_build_object('owner_id',c->'owner_id','command_id',c->'command_id','input_hash',c->'input_hash','source_hash',h,'epoch',c->'epoch','status','ready','activity',activity,'evidence',evidence);
END $$;

REVOKE ALL ON FUNCTION private.conversation_workout_report_without_spoken_suffix(jsonb,text)
 FROM PUBLIC, anon, authenticated, service_role;

DO $patch$
DECLARE
  target regprocedure := to_regprocedure('public.prepare_conversation_workout(uuid,uuid,text,text,uuid,jsonb)');
  definition text;
  prior text := ' IF p_report IS DISTINCT FROM report THEN RETURN ''{"action":"semantic_conflict"}'';END IF;';
  expanded text := $body$ IF p_report IS DISTINCT FROM report THEN
  IF p_report->>'status' IS DISTINCT FROM 'needs_reply'
    OR p_report IS DISTINCT FROM private.conversation_workout_report_without_spoken_suffix(s.context,s.source_hash)
    OR (p.command_id IS NOT NULL AND p.prepared IS DISTINCT FROM p_report) THEN
   RETURN '{"action":"semantic_conflict"}';
  END IF;
  report:=p_report;
 END IF;$body$;
BEGIN
  IF target IS NULL OR (SELECT encode(sha256(convert_to(prosrc, 'UTF8')), 'hex')
    FROM pg_proc WHERE oid = target) IS DISTINCT FROM
    '020ae2d686ef2b741b1dedbbb37c8b772aa30310dc69115f2fa0cc84979eb463' THEN
    RAISE EXCEPTION 'conversation_workout_question_replay_unknown_base';
  END IF;
  definition := pg_get_functiondef(target);
  IF (length(definition) - length(replace(definition, prior, ''))) / length(prior) <> 1 THEN
    RAISE EXCEPTION 'conversation_workout_question_replay_missing_comparison';
  END IF;
  EXECUTE replace(definition, prior, expanded);
END $patch$;

COMMIT;
