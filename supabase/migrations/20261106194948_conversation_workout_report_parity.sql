-- Independent SQL proof for the grammar already accepted by the TypeScript
-- workout resolver. Historical guards, payloads, receipts and formulas stay literal.
BEGIN;

SET LOCAL lock_timeout='5s';
DO $preflight$
DECLARE sig text;pin text;
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_workout_preparations') IS NULL
 OR to_regprocedure('private.conversation_intake_media_projection(uuid,jsonb,boolean,boolean)') IS NULL
 OR to_regprocedure('private.conversation_workout_report_v2(jsonb,text)') IS NOT NULL
 OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='private.conversation_workout_preparations'::regclass AND attname='report_version' AND NOT attisdropped) THEN
  RAISE EXCEPTION 'workout_report_parity_unknown_substrate';END IF;
 FOR sig,pin IN SELECT * FROM (VALUES
 ('private.conversation_workout_report(jsonb,text)','351e658cde4fda82fca90f59af83a657550c23d07b4d348d25b6835fc8a5b938'),
 ('public.prepare_conversation_workout(uuid,uuid,text,text,uuid,jsonb)','15afca023c412a2bff84370b8f2b7fd18cc21c72ee88d8bdb6019c63aefb413b'),
 ('public.commit_conversation_workout(uuid,uuid,text,text,uuid,text,jsonb)','8e6945fcb81b4b7d9a281827f313985bff399801ec104ccbc8bd5d15ff2c92ad')
 ) p(signature,hash) LOOP
  IF to_regprocedure(sig) IS NULL OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure(sig)) IS DISTINCT FROM pin THEN
   RAISE EXCEPTION 'workout_report_parity_unknown_body:%',sig;END IF;
 END LOOP;
END $preflight$;

-- Constant legacy default preserves every old row. Only the trusted SQL prepare
-- explicitly chooses version2 for a new immutable preparation. No public flag.
ALTER TABLE private.conversation_workout_preparations
 ADD COLUMN report_version smallint NOT NULL DEFAULT 1
 CONSTRAINT conversation_workout_report_version CHECK(report_version IN(1,2));

-- Existing ECMAScript Diacritic/whitespace policy, Unicode 17.0; native PG NFD/lower.
-- Non-PT/EN case/NFD differences are characterized separately, not aliased away.
-- Keep long-s/ligatures distinct: unaccent transliteration would grant extra aliases.
CREATE FUNCTION private.conversation_workout_normalize_v2(v text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT lower(btrim(regexp_replace(regexp_replace(normalize(v,NFD),U&'[\0060\00a8\00af\00b4\00b7-\00b8\02b0-\034e\0350-\0357\035d-\0362\0374-\0375\037a\0384-\0385\0483-\0487\0559\0591-\05bd\05bf\05c1-\05c2\05c4-\05c5\05c7\064b-\0652\0657-\0658\06df-\06e0\06e5-\06e6\06ea-\06ec\0730-\074a\07a6-\07b0\07eb-\07f5\0818-\0819\0898-\089f\08c9-\08d2\08e3-\08fe\093c\094d\0951-\0954\0971\09bc\09cd\0a3c\0a4d\0abc\0acd\0afd-\0aff\0b3c\0b4d\0b55\0bcd\0c3c\0c4d\0cbc\0ccd\0d3b-\0d3c\0d4d\0dca\0e3a\0e47-\0e4c\0e4e\0eba\0ec8-\0ecc\0f18-\0f19\0f35\0f37\0f39\0f3e-\0f3f\0f82-\0f84\0f86-\0f87\0fc6\1037\1039-\103a\1063-\1064\1069-\106d\1087-\108d\108f\109a-\109b\135d-\135f\1714-\1715\1734\17c9-\17d3\17dd\1939-\193b\1a60\1a75-\1a7c\1a7f\1ab0-\1abe\1ac1-\1acb\1acf-\1add\1ae0-\1aeb\1b34\1b44\1b6b-\1b73\1baa-\1bab\1be6\1bf2-\1bf3\1c36-\1c37\1c78-\1c7d\1cd0-\1ce8\1ced\1cf4\1cf7-\1cf9\1d2c-\1d6a\1d9b-\1dbe\1dc4-\1dcf\1df5-\1dff\1fbd\1fbf-\1fc1\1fcd-\1fcf\1fdd-\1fdf\1fed-\1fef\1ffd-\1ffe\2cef-\2cf1\2e2f\302a-\302f\3099-\309c\30fc\a66f\a67c-\a67d\a67f\a69c-\a69d\a6f0-\a6f1\a700-\a721\a788-\a78a\a7f1\a7f8-\a7f9\a806\a82c\a8c4\a8e0-\a8f1\a92b-\a92e\a953\a9b3\a9c0\a9e5\aa7b-\aa7d\aabf-\aac2\aaf6\ab5b-\ab5f\ab69-\ab6b\abec-\abed\fb1e\fe20-\fe2f\ff3e\ff40\ff70\ff9e-\ff9f\ffe3\+0102e0\+010780-\+010785\+010787-\+0107b0\+0107b2-\+0107ba\+010a38-\+010a3a\+010a3f\+010ae5-\+010ae6\+010d22-\+010d27\+010d4e\+010d69-\+010d6d\+010efa\+010efd-\+010eff\+010f46-\+010f50\+010f82-\+010f85\+011046\+011070\+0110b9-\+0110ba\+011133-\+011134\+011173\+0111c0\+0111ca-\+0111cc\+011235-\+011236\+0112e9-\+0112ea\+01133b-\+01133c\+01134d\+011366-\+01136c\+011370-\+011374\+0113ce-\+0113d0\+0113d2-\+0113d3\+0113e1-\+0113e2\+011442\+011446\+0114c2-\+0114c3\+0115bf-\+0115c0\+01163f\+0116b6-\+0116b7\+01172b\+011839-\+01183a\+01193d-\+01193e\+011943\+0119e0\+011a34\+011a47\+011a99\+011c3f\+011d42\+011d44-\+011d45\+011d97\+011dd9\+011f41-\+011f42\+011f5a\+013447-\+013455\+01612f\+016af0-\+016af4\+016b30-\+016b36\+016d6b-\+016d6c\+016f8f-\+016f9f\+016ff0-\+016ff1\+01aff0-\+01aff3\+01aff5-\+01affb\+01affd-\+01affe\+01cf00-\+01cf2d\+01cf30-\+01cf46\+01d167-\+01d169\+01d16d-\+01d172\+01d17b-\+01d182\+01d185-\+01d18b\+01d1aa-\+01d1ad\+01e030-\+01e06d\+01e130-\+01e136\+01e2ae\+01e2ec-\+01e2ef\+01e5ee-\+01e5ef\+01e8d0-\+01e8d6\+01e944-\+01e946\+01e948-\+01e94a\005e]','','g'),U&'[\0009-\000d\0020\00a0\1680\2000-\200a\2028-\2029\202f\205f\3000\feff]+',' ','g')));
$$;

-- Preserve T44's independent original source units: v2 caption and context are
-- separate, and audio transcript is an additional independent assertion.
CREATE FUNCTION private.conversation_workout_units_v2(c jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE src jsonb:=c->'source_input';units jsonb:='[]';v text;
BEGIN
 IF src#>>'{source,channel}'='text' THEN
  RETURN jsonb_build_array(jsonb_build_object('unit','command_text','text',src#>>'{source,text}'));
 END IF;
 v:=CASE WHEN c->>'schema'='conversation.workout-source.v2' THEN src#>>'{source,caption}' ELSE coalesce(src#>>'{source,caption}',c#>>'{media,context_text}') END;
 IF v !~ U&'^[\0009-\000d\0020\00a0\1680\2000-\200a\2028-\2029\202f\205f\3000\feff]*$' THEN units:=units||jsonb_build_array(jsonb_build_object('unit','media_caption','text',v));END IF;
 IF c->>'schema'='conversation.workout-source.v2' AND (c#>>'{media,context_text}') !~ U&'^[\0009-\000d\0020\00a0\1680\2000-\200a\2028-\2029\202f\205f\3000\feff]*$' THEN
  units:=units||jsonb_build_array(jsonb_build_object('unit','media_context','text',c#>>'{media,context_text}'));END IF;
 IF c#>>'{media,kind}'='audio_note' THEN
  units:=units||jsonb_build_array(jsonb_build_object('unit','media_transcript','text',c#>>'{media,processing_result,text}'));END IF;
 RETURN units;
END $$;

CREATE FUNCTION private.conversation_workout_duration_v2(v text) RETURNS integer
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE parts text[];fraction text;scale integer;extra integer;total numeric;
BEGIN
 IF v='meia hora' THEN RETURN 30;END IF;
 parts:=regexp_match(v,'^([0-9]{1,4}) *(?:minutos?|min)$');
 IF parts IS NOT NULL THEN RETURN parts[1]::integer;END IF;
 parts:=regexp_match(v,'^([0-9]{1,2})(?:[.,]([0-9]{1,2}))? *(?:horas?|h)(?: *(?:e +)?([0-9]{1,2}) *(?:minutos?|min)?)?$');
 IF parts IS NULL THEN RETURN NULL;END IF;
 fraction:=coalesce(parts[2],'');scale:=CASE length(fraction) WHEN 0 THEN 1 WHEN 1 THEN 10 ELSE 100 END;
 extra:=coalesce(parts[3],'0')::integer;
 total:=(parts[1]::numeric*scale+coalesce(nullif(fraction,''),'0')::numeric)*60/scale+extra;
 IF extra>=60 OR total<>trunc(total) THEN RETURN NULL;END IF;
 RETURN total::integer;
END $$;

CREATE FUNCTION private.conversation_workout_clause_v2(original text) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE v text:=btrim(regexp_replace(original,'[.!]$',''));parts text[];prefix text[];suffix text[];
 name text;duration text;label text;embedded text[];intensity text;
 duration_pattern text:='(?:[0-9]{1,4} *(?:minutos?|min)|[0-9]{1,2}(?:[.,][0-9]{1,2})? *(?:horas?|h)(?: *(?:e +)?[0-9]{1,2} *(?:minutos?|min)?)?|meia hora)';
 intensity_pattern text:='(?: em ritmo| com intensidade)? (leve|moderad[oa]|alt[oa])$';
BEGIN
 IF left(v,5)='hoje ' THEN v:=substr(v,6);END IF;
 IF right(v,5)=' hoje' THEN v:=left(v,length(v)-5);END IF;
 parts:=regexp_match(v,intensity_pattern);label:=parts[1];
 IF parts IS NOT NULL THEN v:=regexp_replace(v,intensity_pattern,'');END IF;
 parts:=regexp_match(v,'^(?:eu )?(caminhei|corri|pedalei|nadei)(?: +|(?=[0-9])|$)(.*)$');
 IF parts IS NOT NULL THEN
  name:=CASE parts[1] WHEN 'caminhei' THEN 'caminhada' WHEN 'corri' THEN 'corrida' WHEN 'pedalei' THEN 'bicicleta' ELSE 'natacao' END;
  duration:=regexp_replace(parts[2],'^(?:por|durante) ','');
  IF duration<>'' AND NOT(duration ~ ('^'||duration_pattern||'$')) THEN RETURN NULL;END IF;
 ELSE
  parts:=regexp_match(v,'^(?:eu )?(?:fiz|realizei|pratiquei|treinei) (.+)$');
  IF parts IS NULL THEN RETURN NULL;END IF;
  prefix:=regexp_match(parts[1],'^('||duration_pattern||') de ([[:alpha:] _-]+)$');
  suffix:=regexp_match(parts[1],'^([[:alpha:] _-]+?) (?:por |durante |de )?('||duration_pattern||')$');
  name:=regexp_replace(coalesce(prefix[2],suffix[1],parts[1]),'^(?:um|uma) ','');
  duration:=coalesce(prefix[1],suffix[2]);
  IF NOT(name ~ '^[[:alpha:] _-]+$') THEN RETURN NULL;END IF;
  embedded:=regexp_match(name,intensity_pattern);
  IF embedded IS NOT NULL AND label IS NOT NULL THEN RETURN NULL;END IF;
  label:=coalesce(label,embedded[1]);
  IF embedded IS NOT NULL THEN name:=regexp_replace(name,intensity_pattern,'');END IF;
 END IF;
 intensity:=CASE WHEN label IS NULL THEN NULL WHEN label='leve' THEN 'leve' WHEN left(label,7)='moderad' THEN 'moderada' ELSE 'alta' END;
 RETURN jsonb_build_object('name',name,'duration',private.conversation_workout_duration_v2(duration),'intensity',intensity,'intensity_label',label);
END $$;

CREATE FUNCTION private.conversation_workout_question_v2(c jsonb,h text,field text) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('owner_id',c->'owner_id','command_id',c->'command_id','input_hash',c->'input_hash','source_hash',h,'epoch',c->'epoch',
 'status','needs_reply','question',jsonb_build_object('key',encode(sha256(convert_to(private.conversation_command_canonical(jsonb_build_object('source_hash',h,'field',field)),'UTF8')),'hex'),
 'field',field,'text',CASE WHEN field='duration_min' THEN 'Quantos minutos durou essa atividade?' ELSE 'Qual atividade você realizou e por quantos minutos?' END));
$$;

CREATE FUNCTION private.conversation_workout_report_v2(c jsonb,h text) RETURNS jsonb
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

CREATE FUNCTION private.conversation_workout_report_version(c jsonb,h text,version smallint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
BEGIN
 IF version=1 THEN RETURN private.conversation_workout_report(c,h);END IF;
 IF version=2 THEN RETURN private.conversation_workout_report_v2(c,h);END IF;
 RAISE EXCEPTION 'workout_report_version_unproved' USING ERRCODE='22023';
END $$;

-- Change only the three exact preparation hooks and the commit proof call.
-- All source/day/owner/epoch locks, formulas and historical receipt replay stay.
DO $patch$
DECLARE body text;old text;replacement text;
BEGIN
 body:=pg_get_functiondef('public.prepare_conversation_workout(uuid,uuid,text,text,uuid,jsonb)'::regprocedure);
 old:=$old$ report:=private.conversation_workout_report(s.context,s.source_hash);
 IF p_report IS DISTINCT FROM report THEN RETURN '{"action":"semantic_conflict"}';END IF;
 SELECT * INTO p FROM private.conversation_workout_preparations WHERE user_id=p_user_id AND command_id=p_command_id;
 IF FOUND THEN RETURN jsonb_build_object('action','replay','prepared_hash',p.prepared_hash,'prepared',p.prepared);END IF;$old$;
 replacement:=$new$ SELECT * INTO p FROM private.conversation_workout_preparations WHERE user_id=p_user_id AND command_id=p_command_id;
 report:=private.conversation_workout_report_version(s.context,s.source_hash,CASE WHEN p.command_id IS NULL THEN 2::smallint ELSE p.report_version END);
 IF p_report IS DISTINCT FROM report THEN RETURN '{"action":"semantic_conflict"}';END IF;
 IF p.command_id IS NOT NULL THEN RETURN jsonb_build_object('action','replay','prepared_hash',p.prepared_hash,'prepared',p.prepared);END IF;$new$;
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'workout_report_prepare_hook';END IF;
 body:=replace(body,old,replacement);
 old:=' INSERT INTO private.conversation_workout_preparations VALUES(p_user_id,p_command_id,h,prepared,clock_timestamp());';
 replacement:=' INSERT INTO private.conversation_workout_preparations(user_id,command_id,prepared_hash,prepared,prepared_at,report_version) VALUES(p_user_id,p_command_id,h,prepared,clock_timestamp(),2);';
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'workout_report_prepare_insert_hook';END IF;
 EXECUTE replace(body,old,replacement);
 body:=pg_get_functiondef('public.commit_conversation_workout(uuid,uuid,text,text,uuid,text,jsonb)'::regprocedure);
 old:=' IF private.conversation_workout_report(s.context,s.source_hash) IS DISTINCT FROM';
 replacement:=' IF private.conversation_workout_report_version(s.context,s.source_hash,p.report_version) IS DISTINCT FROM';
 IF (length(body)-length(replace(body,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'workout_report_commit_hook';END IF;
 EXECUTE replace(body,old,replacement);
END $patch$;

REVOKE ALL ON FUNCTION private.conversation_workout_normalize_v2(text),private.conversation_workout_units_v2(jsonb),private.conversation_workout_duration_v2(text),
 private.conversation_workout_clause_v2(text),private.conversation_workout_question_v2(jsonb,text,text),
 private.conversation_workout_report_v2(jsonb,text),private.conversation_workout_report_version(jsonb,text,smallint)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
