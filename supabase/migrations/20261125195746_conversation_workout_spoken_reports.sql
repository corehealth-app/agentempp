-- Accept whole completed reports with common Brazilian Portuguese phrasing.
-- Keep original evidence, the legacy parser, and all authorization checks.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $patch$
DECLARE
  target regprocedure := to_regprocedure('private.conversation_workout_report_v2(jsonb,text)');
  definition text;
  prior text := '  clause:=private.conversation_workout_clause_v2(v);';
  expanded text := $body$  clause:=private.conversation_workout_clause_v2(v);
  IF clause IS NULL OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(c->'catalogue') x WHERE
   private.conversation_workout_normalize_v2(replace(x->>'slug','_',' '))=clause->>'name'
   OR private.conversation_workout_normalize_v2(x->>'display_name')=clause->>'name') THEN
   clause:=coalesce(private.conversation_workout_clause_v2(regexp_replace(regexp_replace(regexp_replace(v,
    '[.!]$',''),
    ' (?:no (?:inicio|meio|fim) d[ao] (?:manha|tarde|noite|dia)|as (?:[1-9]|1[0-2]) da (?:manha|tarde|noite))$',''),
    ' em intensidade (leve|moderad[oa]|alt[oa])$',' com intensidade \1')),clause);
  END IF;$body$;
BEGIN
  IF target IS NULL OR (SELECT encode(sha256(convert_to(prosrc, 'UTF8')), 'hex')
    FROM pg_proc WHERE oid = target) IS DISTINCT FROM
    '4b28e9cb31d23b87c16903645ba2e7c740fa3c4ae0d81387391eb39684f9c255' THEN
    RAISE EXCEPTION 'conversation_workout_spoken_reports_unknown_base';
  END IF;
  definition := pg_get_functiondef(target);
  IF (length(definition) - length(replace(definition, prior, ''))) / length(prior) <> 1 THEN
    RAISE EXCEPTION 'conversation_workout_spoken_reports_missing_clause';
  END IF;
  EXECUTE replace(definition, prior, expanded);
END $patch$;

COMMIT;
