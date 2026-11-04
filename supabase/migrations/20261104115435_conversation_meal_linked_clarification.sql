-- Private linked continuation. Parent report/source/model/negative remain immutable.
-- Dormant: no HTTP/native activation. This file requires real-PG qualification.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_user<>'postgres' OR to_regclass('private.conversation_meal_decisions') IS NULL
  OR to_regprocedure('private.commit_conversation_meal_at(uuid,uuid,text,timestamptz)') IS NULL THEN
  RAISE EXCEPTION 'continuation_requires_current_substrate' USING ERRCODE='55000';END IF;
END $$;
-- Exact protocol pairs; neither old admission nor an old DTO is broadened.
ALTER TABLE private.conversation_meal_command_ids DROP CONSTRAINT conversation_meal_command_ids_command_protocol_check,
 DROP CONSTRAINT conversation_meal_command_ids_kind_check,
 ADD CONSTRAINT conversation_meal_command_protocol_pair CHECK(
  (command_protocol='conversation.command.v1' AND kind='meal.report') OR
  (command_protocol='conversation.clarification.v1' AND kind='meal.clarify'));
-- Permanent link has no source text, serving, clinical state or model body.
CREATE TABLE private.conversation_meal_reply_ids(
 user_id uuid NOT NULL,reply_id uuid NOT NULL,parent_command_id uuid NOT NULL,
 parent_input_hash text NOT NULL CHECK(parent_input_hash ~ '^[a-f0-9]{64}$'),
 parent_decision_hash text NOT NULL CHECK(parent_decision_hash ~ '^[a-f0-9]{64}$'),
 PRIMARY KEY(user_id,reply_id),
 FOREIGN KEY(user_id,reply_id) REFERENCES private.conversation_meal_command_ids ON DELETE CASCADE,
 FOREIGN KEY(user_id,parent_command_id) REFERENCES private.conversation_meal_command_ids ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_continuation_heads(
 user_id uuid NOT NULL,parent_command_id uuid NOT NULL,revision integer NOT NULL CHECK(revision BETWEEN 0 AND 31),
 question jsonb,answers jsonb NOT NULL CHECK(jsonb_typeof(answers)='array' AND jsonb_array_length(answers)<=31),fulfilled_by uuid,
 PRIMARY KEY(user_id,parent_command_id),
 FOREIGN KEY(user_id,parent_command_id) REFERENCES private.conversation_meal_source_captures ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_replies(
 user_id uuid NOT NULL,reply_id uuid NOT NULL,question jsonb NOT NULL,
 PRIMARY KEY(user_id,reply_id),
 FOREIGN KEY(user_id,reply_id) REFERENCES private.conversation_meal_source_captures ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_continuation_preparations(
 user_id uuid NOT NULL,reply_id uuid NOT NULL,next_question jsonb,
 PRIMARY KEY(user_id,reply_id),FOREIGN KEY(user_id,reply_id) REFERENCES private.conversation_meal_resolved ON DELETE CASCADE
);
CREATE TABLE private.conversation_meal_fulfillments(
 user_id uuid NOT NULL,parent_command_id uuid NOT NULL,reply_id uuid NOT NULL,
 PRIMARY KEY(user_id,parent_command_id),UNIQUE(user_id,reply_id),
 FOREIGN KEY(user_id,parent_command_id) REFERENCES private.conversation_meal_source_captures ON DELETE CASCADE,
 FOREIGN KEY(user_id,reply_id) REFERENCES private.conversation_meal_effects ON DELETE CASCADE
);
ALTER TABLE private.conversation_meal_reply_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_continuation_heads ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_continuation_preparations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.conversation_meal_fulfillments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.conversation_meal_reply_ids,private.conversation_meal_continuation_heads,private.conversation_meal_replies,
 private.conversation_meal_continuation_preparations,private.conversation_meal_fulfillments FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER immutable_conversation_meal_reply_id BEFORE UPDATE ON private.conversation_meal_reply_ids FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TRIGGER immutable_conversation_meal_reply BEFORE UPDATE ON private.conversation_meal_replies FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TRIGGER immutable_conversation_meal_continuation_preparation BEFORE UPDATE ON private.conversation_meal_continuation_preparations FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();
CREATE TRIGGER immutable_conversation_meal_fulfillment BEFORE UPDATE ON private.conversation_meal_fulfillments FOR EACH ROW EXECUTE FUNCTION private.conversation_command_immutable();

CREATE FUNCTION private.conversation_continuation_hash(v jsonb) RETURNS text
LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
 SELECT encode(sha256(convert_to(private.conversation_command_canonical(v),'UTF8')),'hex');
$$;
CREATE FUNCTION private.assert_conversation_meal_reply(v jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE a jsonb:=v->'answer';n numeric;
BEGIN
 PERFORM private.conversation_meal_keys(v,ARRAY['schema','expected_revision','question_key','answer']);
 IF v->>'schema' IS DISTINCT FROM 'conversation.meal-clarification.v1' OR
  jsonb_typeof(v->'question_key') IS DISTINCT FROM 'string' OR NOT(v->>'question_key' COLLATE "C" ~ '^[a-f0-9]{64}$')
  OR octet_length(v::text)>16384 THEN RAISE EXCEPTION 'invalid_conversation_meal_reply' USING ERRCODE='22023';END IF;
 PERFORM private.conversation_semantic_uint(v->'expected_revision',2147483647);
 IF a->>'kind'='quantity' THEN
  PERFORM private.conversation_meal_keys(a,ARRAY['kind','food_index','amount','unit']);
  PERFORM private.conversation_semantic_uint(a->'food_index',29);
  IF jsonb_typeof(a->'amount') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'invalid_conversation_meal_reply' USING ERRCODE='22023';END IF;
  n:=(a->>'amount')::numeric;
  IF n<=0 OR n>9999 OR a->>'unit' IS NULL OR a->>'unit' NOT IN('g','kg','mL','L','unit','scoop','caneca') THEN
   RAISE EXCEPTION 'invalid_conversation_meal_reply' USING ERRCODE='22023';END IF;
 ELSIF a->>'kind'='meal_type' THEN
  PERFORM private.conversation_meal_keys(a,ARRAY['kind','meal_type']);
  IF a->>'meal_type' IS NULL OR a->>'meal_type' NOT IN('cafe','almoco','lanche','jantar','ceia','outro') THEN
   RAISE EXCEPTION 'invalid_conversation_meal_reply' USING ERRCODE='22023';END IF;
 ELSE RAISE EXCEPTION 'invalid_conversation_meal_reply' USING ERRCODE='22023';END IF;
END $$;
CREATE FUNCTION private.conversation_continuation_slice(value text,start_at integer,end_at integer) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
DECLARE ch text;pos integer:=0;result text:='';width integer;
BEGIN
 IF NOT private.conversation_utf16_boundary(value,start_at) OR NOT private.conversation_utf16_boundary(value,end_at) OR end_at<=start_at THEN RETURN NULL;END IF;
 FOR ch IN SELECT regexp_split_to_table(value,'') LOOP
  width:=CASE WHEN ascii(ch)>65535 THEN 2 ELSE 1 END;
  IF pos>=start_at AND pos<end_at THEN result:=result||ch;END IF;pos:=pos+width;
 END LOOP;RETURN result;
END $$;
CREATE FUNCTION private.conversation_continuation_food_name(source jsonb,food jsonb) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT private.conversation_continuation_slice(private.conversation_semantic_text(source,food#>>'{name,unit}'),
  (food#>>'{name,start}')::numeric::integer,(food#>>'{name,end}')::numeric::integer);
$$;
-- Mirrors ONLY the existing whole-name app display references. No fuzzy name,
-- brand, compound, inferred serving, product-label or business-target default.
-- Generated from the installed Node Unicode 17.0 Diacritic property;
-- equivalence is tested against the actual mobileQuantityDisplay export.
CREATE FUNCTION private.conversation_continuation_normalize(food_name text) RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
DECLARE ch text;result text:='';point integer;BEGIN
 FOR ch IN SELECT regexp_split_to_table(normalize(food_name,NFD),'') LOOP
  point:=ascii(ch);
  IF point <@ '{[94,95),[96,97),[168,169),[175,176),[180,181),[183,185),[688,847),[848,856),[861,867),[884,886),[890,891),[900,902),[1155,1160),[1369,1370),[1425,1470),[1471,1472),[1473,1475),[1476,1478),[1479,1480),[1611,1619),[1623,1625),[1759,1761),[1765,1767),[1770,1773),[1840,1867),[1958,1969),[2027,2038),[2072,2074),[2200,2208),[2249,2259),[2275,2303),[2364,2365),[2381,2382),[2385,2389),[2417,2418),[2492,2493),[2509,2510),[2620,2621),[2637,2638),[2748,2749),[2765,2766),[2813,2816),[2876,2877),[2893,2894),[2901,2902),[3021,3022),[3132,3133),[3149,3150),[3260,3261),[3277,3278),[3387,3389),[3405,3406),[3530,3531),[3642,3643),[3655,3661),[3662,3663),[3770,3771),[3784,3789),[3864,3866),[3893,3894),[3895,3896),[3897,3898),[3902,3904),[3970,3973),[3974,3976),[4038,4039),[4151,4152),[4153,4155),[4195,4197),[4201,4206),[4231,4238),[4239,4240),[4250,4252),[4957,4960),[5908,5910),[5940,5941),[6089,6100),[6109,6110),[6457,6460),[6752,6753),[6773,6781),[6783,6784),[6832,6847),[6849,6860),[6863,6878),[6880,6892),[6964,6965),[6980,6981),[7019,7028),[7082,7084),[7142,7143),[7154,7156),[7222,7224),[7288,7294),[7376,7401),[7405,7406),[7412,7413),[7415,7418),[7468,7531),[7579,7615),[7620,7632),[7669,7680),[8125,8126),[8127,8130),[8141,8144),[8157,8160),[8173,8176),[8189,8191),[11503,11506),[11823,11824),[12330,12336),[12441,12445),[12540,12541),[42607,42608),[42620,42622),[42623,42624),[42652,42654),[42736,42738),[42752,42786),[42888,42891),[42993,42994),[43000,43002),[43014,43015),[43052,43053),[43204,43205),[43232,43250),[43307,43311),[43347,43348),[43443,43444),[43456,43457),[43493,43494),[43643,43646),[43711,43715),[43766,43767),[43867,43872),[43881,43884),[44012,44014),[64286,64287),[65056,65072),[65342,65343),[65344,65345),[65392,65393),[65438,65440),[65507,65508),[66272,66273),[67456,67462),[67463,67505),[67506,67515),[68152,68155),[68159,68160),[68325,68327),[68898,68904),[68942,68943),[68969,68974),[69370,69371),[69373,69376),[69446,69457),[69506,69510),[69702,69703),[69744,69745),[69817,69819),[69939,69941),[70003,70004),[70080,70081),[70090,70093),[70197,70199),[70377,70379),[70459,70461),[70477,70478),[70502,70509),[70512,70517),[70606,70609),[70610,70612),[70625,70627),[70722,70723),[70726,70727),[70850,70852),[71103,71105),[71231,71232),[71350,71352),[71467,71468),[71737,71739),[71997,71999),[72003,72004),[72160,72161),[72244,72245),[72263,72264),[72345,72346),[72767,72768),[73026,73027),[73028,73030),[73111,73112),[73177,73178),[73537,73539),[73562,73563),[78919,78934),[90415,90416),[92912,92917),[92976,92983),[93547,93549),[94095,94112),[94192,94194),[110576,110580),[110581,110588),[110589,110591),[118528,118574),[118576,118599),[119143,119146),[119149,119155),[119163,119171),[119173,119180),[119210,119214),[122928,122990),[123184,123191),[123566,123567),[123628,123632),[124398,124400),[125136,125143),[125252,125255),[125256,125259)}'::int4multirange THEN CONTINUE;END IF;
  IF point=ANY(ARRAY[9,10,11,12,13,32,160,5760,8192,8193,8194,8195,8196,8197,8198,8199,8200,8201,8202,8232,8233,8239,8287,12288,65279]) THEN ch:=' ';END IF;
  result:=result||lower(ch);
 END LOOP;RETURN btrim(regexp_replace(result,' +',' ','g'));
END $$;
CREATE FUNCTION private.conversation_continuation_quantity_reference(food_name text) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE name text:=private.conversation_continuation_normalize(food_name);unit text;grams numeric;ref text;
BEGIN
 name:=btrim(name);
 CASE
 WHEN name IN('leite','leite integral') THEN unit:='mL';grams:=1.03;ref:='fao-infoods-v2-whole-milk-tb';
 WHEN name IN('cafe coado','cafe preparado','cafe expresso','cafe espresso') THEN unit:='mL';grams:=1;ref:='fao-infoods-v2-coffee-fndds4-1';
 WHEN name IN('cha preparado','cha liquido') THEN unit:='mL';grams:=1;ref:='fao-infoods-v2-tea-fndds4-1';
 WHEN name='agua' THEN unit:='mL';grams:=1;ref:='fao-infoods-v2-water-cg';
 WHEN name='suco de laranja' THEN unit:='mL';grams:=1.038;ref:='fao-infoods-v2-orange-juice-sw';
 WHEN name IN('whey','whey protein','whey protein em po') THEN unit:='scoop';grams:=30;ref:='app-household-whey-scoop-v1';
 WHEN name IN('pao de queijo','paes de queijo','pao de queijo com requeijao') THEN unit:='unit';grams:=30;ref:='app-household-cheese-bread-unit-v1';
 WHEN name IN('ovo','ovos','ovo de galinha','ovos de galinha') THEN unit:='unit';grams:=50;ref:='app-household-egg-unit-v1';
 WHEN name IN('pao frances','paes franceses','paozinho') THEN unit:='unit';grams:=50;ref:='app-household-french-bread-unit-v1';
 WHEN name IN('banana','bananas') THEN unit:='unit';grams:=100;ref:='app-household-banana-unit-v1';
 WHEN name IN('maca','macas') THEN unit:='unit';grams:=150;ref:='app-household-apple-unit-v1';
 ELSE RETURN NULL;END CASE;
 RETURN jsonb_build_object('unit',unit,'grams_per_unit',grams,'reference_id',ref,'estimated',true);
END $$;
CREATE FUNCTION private.conversation_continuation_question(parent jsonb,revision integer,answers jsonb,kind text,food_index integer) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE food jsonb;name text;ref jsonb;units jsonb:='[]';binding jsonb;question jsonb;
BEGIN
 IF revision NOT BETWEEN 0 AND 30 OR kind IS NULL OR kind NOT IN('quantity','meal_type') THEN RETURN NULL;END IF;
 IF kind='quantity' THEN
  SELECT x INTO food FROM jsonb_array_elements(parent#>'{semantic,result,foods}') x WHERE (x->>'index')::numeric=food_index;
  IF food IS NULL OR food->'name'='null'::jsonb OR food->'quantity'<>'null'::jsonb OR food->'unit'<>'null'::jsonb
   OR food->'visual_index'<>'null'::jsonb OR EXISTS(SELECT 1 FROM jsonb_array_elements(answers) x
    WHERE x#>>'{answer,kind}'='quantity' AND (x#>>'{answer,food_index}')::numeric=food_index) THEN RETURN NULL;END IF;
  name:=private.conversation_continuation_food_name(parent#>'{source,context}',food);
  IF NOT private.conversation_command_text_valid(to_jsonb(name),160) THEN RETURN NULL;END IF;
  ref:=private.conversation_continuation_quantity_reference(name);units:='["g","kg"]';
  IF ref->>'unit'='mL' THEN units:=units||'["mL","L"]'::jsonb;
   IF ref->>'reference_id'='fao-infoods-v2-whole-milk-tb' THEN units:=units||'"caneca"'::jsonb;END IF;
  ELSIF ref IS NOT NULL THEN units:=units||jsonb_build_array(ref->>'unit');END IF;
 ELSE
  IF food_index IS NOT NULL OR parent#>>'{source,context,source_input,meal_type}' IS NOT NULL OR
   EXISTS(SELECT 1 FROM jsonb_array_elements(answers) x WHERE x#>>'{answer,kind}'='meal_type') THEN RETURN NULL;END IF;
 END IF;
 binding:=jsonb_build_object('schema','conversation.meal-question-binding.v1','owner_id',parent#>'{binding,owner_id}',
  'parent_command_id',parent#>'{binding,command_id}','parent_input_hash',parent#>'{binding,input_hash}','epoch',parent#>'{binding,epoch}',
  'parent_decision_hash',parent#>'{decision,decision_hash}','parent_source_hash',parent#>'{source,source_hash}',
  'parent_result_hash',parent#>'{semantic,result_hash}','revision',revision,'kind',kind,'food_index',food_index,
  'food_name',name,'allowed_units',units,'quantity_reference',ref,'answer_chain_hash',private.conversation_continuation_hash(answers));
 RETURN jsonb_build_object('schema','conversation.meal-question.v1','question_key',private.conversation_continuation_hash(binding),
  'revision',revision,'kind',kind,'food_index',food_index,'food_name',name,'allowed_units',units,'quantity_reference',ref);
END $$;

CREATE FUNCTION private.conversation_continuation_parent(p_user uuid,p_parent uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;s private.conversation_meal_source_captures%ROWTYPE;
 d private.conversation_meal_decisions%ROWTYPE;a private.conversation_meal_semantic_attempts%ROWTYPE;r private.conversation_meal_semantic_results%ROWTYPE;raw jsonb;
BEGIN
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_parent;
 IF c.command_protocol IS DISTINCT FROM 'conversation.command.v1' OR c.kind IS DISTINCT FROM 'meal.report' THEN RETURN NULL;END IF;
 SELECT source_input INTO raw FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_parent;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user AND command_id=p_parent;
 SELECT * INTO d FROM private.conversation_meal_decisions WHERE user_id=p_user AND command_id=p_parent;
 SELECT * INTO a FROM private.conversation_meal_semantic_attempts WHERE user_id=p_user AND command_id=p_parent AND attempt_id=d.attempt_id;
 SELECT * INTO r FROM private.conversation_meal_semantic_results WHERE user_id=p_user AND command_id=p_parent AND attempt_id=d.attempt_id;
 IF NOT private.conversation_meal_stored_source_valid(c,raw,s) OR NOT private.conversation_meal_decision_valid(d,c,s,a,r)
  OR d.decision->>'reason' IS NULL OR d.decision->>'reason' NOT IN('missing_quantity','meal_type_required')
  OR r.result->>'decision' IS DISTINCT FROM 'reported_meal' OR jsonb_array_length(r.result->'foods') NOT BETWEEN 1 AND 30
  OR EXISTS(SELECT 1 FROM private.conversation_meal_resolved WHERE user_id=p_user AND command_id=p_parent)
  OR EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=p_parent) THEN RETURN NULL;END IF;
 RETURN jsonb_build_object('binding',private.conversation_meal_command_binding(c),
  'source',jsonb_build_object('source_hash',s.source_hash,'captured_at',s.captured_at,'context',s.context),
  'semantic',jsonb_build_object('interpreter_version',a.interpreter_version,'attempt_id',a.attempt_id,'result_hash',r.result_hash,'result',r.result),
  'decision',private.conversation_meal_decision_receipt(d));
END $$;
CREATE FUNCTION private.conversation_continuation_head(p_user uuid,p_parent uuid,parent jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE h private.conversation_meal_continuation_heads%ROWTYPE;q jsonb;answers jsonb:='[]';index integer;kind text;
BEGIN
 SELECT * INTO h FROM private.conversation_meal_continuation_heads WHERE user_id=p_user AND parent_command_id=p_parent;
 IF FOUND THEN RETURN jsonb_build_object('revision',h.revision,'question',h.question,'answers_hash',private.conversation_continuation_hash(h.answers),'answers',h.answers,'fulfilled_by',h.fulfilled_by);END IF;
 IF parent#>>'{decision,reason}'='missing_quantity' AND jsonb_array_length(parent#>'{decision,food_indexes}')=1 THEN
  kind:='quantity';index:=(parent#>>'{decision,food_indexes,0}')::numeric::integer;
 ELSIF parent#>>'{decision,reason}'='meal_type_required' THEN kind:='meal_type';ELSE RETURN NULL;END IF;
 q:=private.conversation_continuation_question(parent,0,answers,kind,index);
 IF q IS NULL THEN RETURN NULL;END IF;
 RETURN jsonb_build_object('revision',0,'question',q,'answers_hash',private.conversation_continuation_hash(answers),'answers',answers,'fulfilled_by',NULL);
END $$;
CREATE FUNCTION private.lock_conversation_continuation(p_user uuid,p_parent uuid,p_epoch uuid,p_hash text) RETURNS text
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;c private.conversation_meal_command_ids%ROWTYPE;
BEGIN
 gate:=private.lock_conversation_meal(p_user,p_parent);IF gate<>'current' THEN RETURN gate;END IF;
 SELECT * INTO STRICT c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_parent;
 IF p_epoch IS DISTINCT FROM c.epoch THEN RETURN 'stale_epoch';END IF;
 IF p_hash IS DISTINCT FROM c.input_hash THEN RETURN 'input_conflict';END IF;
 RETURN 'current';
END $$;
CREATE FUNCTION private.conversation_continuation_fulfillment(p_user uuid,p_parent uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('parent_binding',private.conversation_meal_command_binding(p),'child_binding',private.conversation_meal_command_binding(c),'receipt',fx.receipt)
 FROM private.conversation_meal_fulfillments f
 JOIN private.conversation_meal_command_ids p ON p.user_id=f.user_id AND p.command_id=f.parent_command_id
 JOIN private.conversation_meal_command_ids c ON c.user_id=f.user_id AND c.command_id=f.reply_id
 JOIN private.conversation_meal_effects fx ON fx.user_id=f.user_id AND fx.command_id=f.reply_id
 WHERE f.user_id=p_user AND f.parent_command_id=p_parent;
$$;
CREATE FUNCTION private.conversation_continuation_reply(p_user uuid,p_parent uuid,p_reply uuid,p_hash text,head jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE id private.conversation_meal_reply_ids%ROWTYPE;c private.conversation_meal_command_ids%ROWTYPE;s private.conversation_meal_source_captures%ROWTYPE;
 q private.conversation_meal_replies%ROWTYPE;r private.conversation_meal_resolved%ROWTYPE;fx private.conversation_meal_effects%ROWTYPE;meta private.conversation_meal_continuation_preparations%ROWTYPE;body jsonb;state text;
BEGIN
 SELECT * INTO id FROM private.conversation_meal_reply_ids WHERE user_id=p_user AND reply_id=p_reply;
 SELECT * INTO c FROM private.conversation_meal_command_ids WHERE user_id=p_user AND command_id=p_reply;
 SELECT source_input INTO body FROM private.conversation_meal_command_sources WHERE user_id=p_user AND command_id=p_reply;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user AND command_id=p_reply;
 SELECT * INTO q FROM private.conversation_meal_replies WHERE user_id=p_user AND reply_id=p_reply;
 IF id.parent_command_id IS DISTINCT FROM p_parent OR c.command_protocol IS DISTINCT FROM 'conversation.clarification.v1' OR c.kind IS DISTINCT FROM 'meal.clarify'
  OR c.input_hash IS DISTINCT FROM p_hash OR body IS NULL OR s.command_id IS NULL OR q.reply_id IS NULL OR c.invalidated_at IS NOT NULL
  OR c.input_hash IS DISTINCT FROM private.conversation_continuation_hash(body) OR s.source_hash IS DISTINCT FROM private.conversation_continuation_hash(s.context)
  OR s.context->>'schema' IS DISTINCT FROM 'conversation.meal-continuation-source.v1'
  OR s.context->>'owner_id' IS DISTINCT FROM p_user::text OR s.context->>'command_id' IS DISTINCT FROM p_reply::text
  OR s.context->>'input_hash' IS DISTINCT FROM c.input_hash OR s.context->>'epoch' IS DISTINCT FROM c.epoch::text
  OR s.context->'source_input' IS DISTINCT FROM body OR s.context#>>'{parent,command_id}' IS DISTINCT FROM p_parent::text
  OR body->'question_key' IS DISTINCT FROM q.question->'question_key' OR body->'expected_revision' IS DISTINCT FROM q.question->'revision' THEN RETURN NULL;END IF;
 SELECT * INTO r FROM private.conversation_meal_resolved WHERE user_id=p_user AND command_id=p_reply;
 SELECT * INTO meta FROM private.conversation_meal_continuation_preparations WHERE user_id=p_user AND reply_id=p_reply;
 SELECT * INTO fx FROM private.conversation_meal_effects WHERE user_id=p_user AND command_id=p_reply;
 IF r.command_id IS NOT NULL AND (r.resolved_hash IS DISTINCT FROM private.conversation_continuation_hash(r.resolved) OR meta.reply_id IS NULL) THEN RETURN NULL;END IF;
 IF fx.command_id IS NOT NULL AND (r.command_id IS NULL OR fx.receipt->>'schema' IS DISTINCT FROM 'conversation.meal-continuation-effect.v1'
  OR fx.receipt->>'owner_id' IS DISTINCT FROM p_user::text OR fx.receipt->>'command_id' IS DISTINCT FROM p_reply::text
  OR fx.receipt->>'input_hash' IS DISTINCT FROM c.input_hash OR fx.receipt->>'epoch' IS DISTINCT FROM c.epoch::text
  OR fx.receipt->>'parent_command_id' IS DISTINCT FROM p_parent::text) THEN RETURN NULL;END IF;
 state:=CASE WHEN fx.command_id IS NOT NULL THEN 'saved' WHEN head->'fulfilled_by'<>'null'::jsonb THEN 'superseded'
  WHEN r.resolved->>'status'='needs_reply' THEN 'awaiting_reply'
  WHEN (head->>'revision')::integer>(body->>'expected_revision')::numeric::integer THEN 'superseded'
  WHEN r.command_id IS NOT NULL THEN 'prepared' ELSE 'admitted' END;
 RETURN jsonb_build_object('binding',private.conversation_meal_command_binding(c),'body',body,
  'source',jsonb_build_object('source_hash',s.source_hash,'captured_at',s.captured_at,'context',s.context),
  'preparation',CASE WHEN r.command_id IS NULL THEN NULL ELSE jsonb_build_object('prepared_hash',r.resolved_hash,'prepared_at',r.prepared_at,'preparation',r.resolved,'next_question',meta.next_question) END,
  'receipt',fx.receipt,'state',state);
END $$;
-- Purely server-owned observation seam; no public argument accepts a clock.
-- Callers already hold the owner/epoch/parent lane. Upgrade the owner NOWAIT
-- before locking media, preserving the existing user -> media lock order.
CREATE FUNCTION private.conversation_continuation_original_current_at(p_user uuid,parent jsonb,p_observed timestamptz) RETURNS boolean
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE original jsonb:=parent#>'{source,context}';raw jsonb:=parent#>'{source,context,source_input}';zone text;
 m public.media_assets%ROWTYPE;media jsonb;units jsonb:='[]';evidence jsonb:='{}';caption text;transcript text;observed timestamptz;
BEGIN
 IF original IS NULL OR original->>'owner_id' IS DISTINCT FROM p_user::text THEN RETURN false;END IF;
 SELECT u.timezone INTO zone FROM public.users u WHERE u.id=p_user AND u.status='active' FOR UPDATE NOWAIT;
 IF NOT FOUND OR zone IS DISTINCT FROM original#>>'{owner,timezone}' THEN RETURN false;END IF;
 observed:=coalesce(p_observed,clock_timestamp());
 IF (observed AT TIME ZONE zone)::date IS DISTINCT FROM (original#>>'{day,date}')::date THEN RETURN false;END IF;
 -- This fence precedes any fresh clinical/catalog/day capture. Never adopt a
 -- later media transcript, context or processing result as an original witness.
 IF raw#>>'{source,channel}'='text' THEN
  RETURN coalesce(original->'media'='null'::jsonb AND original->'source_units'='["command_text"]'::jsonb AND original->'source_evidence'='{}'::jsonb,false);
 END IF;
 IF raw#>>'{source,channel}' IS DISTINCT FROM 'media' THEN RETURN false;END IF;
 SELECT * INTO m FROM public.media_assets WHERE id=(raw#>>'{source,media_asset_id}')::uuid AND user_id=p_user FOR SHARE NOWAIT;
 IF NOT FOUND OR m.status<>'processed' OR m.kind NOT IN('meal_photo','audio_note') OR m.processed_at IS NULL OR m.deleted_at IS NOT NULL
  OR octet_length(coalesce(m.processing_result,'null')::text)>1048576 THEN RETURN false;END IF;
 caption:=coalesce(raw#>>'{source,caption}',m.context_text);
 IF caption IS NOT NULL AND btrim(caption)<>'' THEN units:=units||jsonb_build_array('media_caption');END IF;
 IF m.kind='audio_note' THEN
  transcript:=m.processing_result->>'text';
  IF transcript IS NULL OR btrim(transcript)='' THEN RETURN false;END IF;
  units:=units||jsonb_build_array('media_transcript');
 ELSE
  IF jsonb_typeof(m.processing_result->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(m.processing_result->'items') NOT BETWEEN 1 AND 30 THEN RETURN false;END IF;
  units:=units||jsonb_build_array('vision_items');
 END IF;
 media:=jsonb_build_object('asset_id',m.id,'kind',m.kind,'status',m.status,'processed_at',m.processed_at,'updated_at',m.updated_at,
  'processing_result',m.processing_result,'context_text',m.context_text);
 evidence:=jsonb_build_object('caption',caption,'transcript',transcript);
 RETURN original->'media' IS NOT DISTINCT FROM media AND original->'source_units' IS NOT DISTINCT FROM units
  AND original->'source_evidence' IS NOT DISTINCT FROM evidence;
END $$;
CREATE FUNCTION private.conversation_continuation_original_current(p_user uuid,parent jsonb) RETURNS boolean
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
BEGIN RETURN private.conversation_continuation_original_current_at(p_user,parent,NULL);END $$;
CREATE FUNCTION private.conversation_continuation_grams(answer jsonb,question jsonb) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog SET extra_float_digits=3 AS $$
DECLARE factor double precision;grams double precision;unit text:=answer->>'unit';amount numeric;value double precision;
BEGIN
 IF answer->>'kind' IS DISTINCT FROM 'quantity' OR answer->'food_index' IS DISTINCT FROM question->'food_index'
  OR jsonb_typeof(answer->'amount') IS DISTINCT FROM 'number' OR NOT coalesce(question->'allowed_units' @> jsonb_build_array(unit),false) THEN RETURN NULL;END IF;
 amount:=(answer->>'amount')::numeric;IF amount<=0 OR amount>9999 THEN RETURN NULL;END IF;
 factor:=CASE unit WHEN 'g' THEN 1 WHEN 'kg' THEN 1000 WHEN 'mL' THEN (question#>>'{quantity_reference,grams_per_unit}')::double precision
  WHEN 'L' THEN 1000*(question#>>'{quantity_reference,grams_per_unit}')::double precision
  WHEN 'caneca' THEN 200*(question#>>'{quantity_reference,grams_per_unit}')::double precision
  ELSE (question#>>'{quantity_reference,grams_per_unit}')::double precision END;
 -- Explicit mass remains explicit. Only reference conversions use the existing
 -- positive Math.round(value * factor * 1e6) / 1e6 rule from the contract.
 IF unit='g' THEN RETURN amount;END IF;
 IF unit='kg' THEN
  -- A shortest JSON decimal may denote a subnormal JS number whose direct
  -- PostgreSQL float input conversion underflows. Reconstruct its integer
  -- binary64 subnormal units before the ordinary float64 multiplication.
  IF amount<2.2250738585072014e-308 THEN
   value:=round(amount*power(2::numeric,1074))::double precision/power(2::double precision,52)/power(2::double precision,1022);
  ELSE value:=amount::double precision;END IF;
  grams:=value*1000;
  IF grams<=0 OR grams>9999 THEN RETURN NULL;END IF;
  RETURN to_jsonb(grams)::text::numeric;
 END IF;
 -- Every approved reference factor is far below 1e6, so these amounts always
 -- round to zero; avoid parsing a subnormal without altering tie behavior.
 IF amount<1e-300 THEN RETURN NULL;END IF;
 grams:=floor((answer->>'amount')::double precision*factor*1000000+0.5)/1000000;
 IF grams IS NULL OR grams<=0 OR grams>9999 THEN RETURN NULL;END IF;
 RETURN to_jsonb(grams)::text::numeric;
END $$;
CREATE FUNCTION public.read_conversation_meal_continuation(p_user_id uuid,p_parent_command_id uuid,p_expected_epoch uuid,p_parent_input_hash text,
 p_reply_id uuid DEFAULT NULL,p_reply_input_hash text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE c private.conversation_meal_command_ids%ROWTYPE;epoch uuid;parent jsonb;head jsonb;reply jsonb;fulfillment jsonb;
BEGIN
 PERFORM private.assert_trusted_backend();
 IF p_user_id IS NULL OR p_parent_command_id IS NULL OR (p_reply_id IS NULL)<>(p_reply_input_hash IS NULL)
  OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'invalid_conversation_continuation_read' USING ERRCODE='22023';END IF;
 SELECT x.* INTO c FROM private.conversation_meal_command_ids x JOIN public.users u ON u.id=x.user_id AND u.status='active'
  WHERE x.user_id=p_user_id AND x.command_id=p_parent_command_id;
 IF NOT FOUND THEN RETURN '{"action":"absent"}'::jsonb;END IF;
 SELECT e.epoch INTO epoch FROM private.workout_strength_authority_epochs e WHERE user_id=p_user_id;
 IF c.invalidated_at IS NOT NULL OR c.epoch IS DISTINCT FROM epoch OR c.epoch IS DISTINCT FROM p_expected_epoch THEN RETURN '{"action":"stale_epoch"}'::jsonb;END IF;
 IF c.input_hash IS DISTINCT FROM p_parent_input_hash THEN RETURN '{"action":"input_conflict"}'::jsonb;END IF;
 parent:=private.conversation_continuation_parent(p_user_id,p_parent_command_id);IF parent IS NULL THEN RETURN '{"action":"ineligible"}'::jsonb;END IF;
 head:=private.conversation_continuation_head(p_user_id,p_parent_command_id,parent);IF head IS NULL THEN RETURN '{"action":"ineligible"}'::jsonb;END IF;
 fulfillment:=private.conversation_continuation_fulfillment(p_user_id,p_parent_command_id);
 IF (head->'fulfilled_by'<>'null'::jsonb)<>(fulfillment IS NOT NULL) THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
 IF p_reply_id IS NOT NULL THEN
  reply:=private.conversation_continuation_reply(p_user_id,p_parent_command_id,p_reply_id,p_reply_input_hash,head);
  IF reply IS NULL THEN RETURN '{"action":"reply_conflict"}'::jsonb;END IF;
 END IF;
 RETURN jsonb_build_object('action','available','parent',parent,'head',head,'reply',reply,'fulfillment',fulfillment,
  'observed_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
END $$;
CREATE FUNCTION public.admit_conversation_meal_reply(p_user_id uuid,p_parent_command_id uuid,p_expected_epoch uuid,p_parent_input_hash text,
 p_parent_decision_hash text,p_reply_id uuid,p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;parent jsonb;head jsonb;question jsonb;body_hash text;child private.conversation_meal_command_ids%ROWTYPE;
 link private.conversation_meal_reply_ids%ROWTYPE;source private.conversation_meal_source_captures%ROWTYPE;existing jsonb;authority jsonb;context jsonb;chain jsonb;clock timestamptz;old_child boolean;
BEGIN
 gate:=private.lock_conversation_continuation(p_user_id,p_parent_command_id,p_expected_epoch,p_parent_input_hash);
 IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 IF p_reply_id IS NULL OR p_reply_id=p_parent_command_id THEN RAISE EXCEPTION 'invalid_conversation_meal_reply' USING ERRCODE='22023';END IF;
 -- Permanent child identity, including its original epoch, precedes any replay.
 SELECT * INTO child FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND command_id=p_reply_id FOR UPDATE;
 old_child:=FOUND;
 IF old_child AND (child.invalidated_at IS NOT NULL OR child.epoch IS DISTINCT FROM p_expected_epoch) THEN RETURN '{"action":"stale_epoch"}'::jsonb;END IF;
 PERFORM private.assert_conversation_meal_reply(p_input);body_hash:=private.conversation_continuation_hash(p_input);
 IF old_child THEN
  SELECT * INTO link FROM private.conversation_meal_reply_ids WHERE user_id=p_user_id AND reply_id=p_reply_id;
  IF child.input_hash IS DISTINCT FROM body_hash OR link.parent_command_id IS DISTINCT FROM p_parent_command_id
   OR link.parent_input_hash IS DISTINCT FROM p_parent_input_hash OR link.parent_decision_hash IS DISTINCT FROM p_parent_decision_hash THEN
   RETURN '{"action":"input_conflict"}'::jsonb;END IF;
  SELECT source_input INTO existing FROM private.conversation_meal_command_sources WHERE user_id=p_user_id AND command_id=p_reply_id;
  IF existing IS DISTINCT FROM p_input THEN RETURN '{"action":"input_conflict"}'::jsonb;END IF;
  SELECT * INTO source FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_reply_id;
  SELECT r.question INTO question FROM private.conversation_meal_replies r WHERE user_id=p_user_id AND reply_id=p_reply_id;
  IF source.command_id IS NULL OR question IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
  RETURN jsonb_build_object('action','replay','parent_binding',(SELECT private.conversation_meal_command_binding(c) FROM private.conversation_meal_command_ids c WHERE user_id=p_user_id AND command_id=p_parent_command_id),
   'child_binding',private.conversation_meal_command_binding(child),'question',question,
   'source',jsonb_build_object('source_hash',source.source_hash,'captured_at',source.captured_at,'context',source.context));
 END IF;
 parent:=private.conversation_continuation_parent(p_user_id,p_parent_command_id);IF parent IS NULL THEN RETURN '{"action":"ineligible"}'::jsonb;END IF;
 IF parent#>>'{decision,decision_hash}' IS DISTINCT FROM p_parent_decision_hash THEN RETURN '{"action":"decision_conflict"}'::jsonb;END IF;
 head:=private.conversation_continuation_head(p_user_id,p_parent_command_id,parent);IF head IS NULL THEN RETURN '{"action":"ineligible"}'::jsonb;END IF;
 question:=head->'question';
 IF head->'fulfilled_by'<>'null'::jsonb OR question='null'::jsonb OR p_input->'expected_revision' IS DISTINCT FROM head->'revision'
  OR p_input->'question_key' IS DISTINCT FROM question->'question_key' OR p_input#>>'{answer,kind}' IS DISTINCT FROM question->>'kind'
  OR (question->>'kind'='quantity' AND private.conversation_continuation_grams(p_input->'answer',question) IS NULL) THEN
  RETURN '{"action":"question_conflict"}'::jsonb;END IF;
 clock:=clock_timestamp();
 IF (SELECT count(*) FROM private.conversation_meal_command_ids WHERE user_id=p_user_id AND epoch=p_expected_epoch AND admitted_at>=clock-interval '60 seconds')>=10 THEN
  RETURN '{"action":"rate_limited"}'::jsonb;END IF;
 IF NOT private.conversation_continuation_original_current(p_user_id,parent) THEN RETURN '{"action":"question_conflict"}'::jsonb;END IF;
 authority:=private.conversation_meal_source_at(p_user_id,p_parent_command_id,NULL);
 IF (authority#>>'{day,day_closed}')::boolean OR authority#>'{day,date}' IS DISTINCT FROM parent#>'{source,context,day,date}'
  OR authority#>'{owner,timezone}' IS DISTINCT FROM parent#>'{source,context,owner,timezone}' THEN RETURN '{"action":"question_conflict"}'::jsonb;END IF;
 chain:=(head->'answers')||jsonb_build_array(jsonb_build_object('reply_id',p_reply_id,'reply_input_hash',body_hash,'question_key',p_input->'question_key','answer',p_input->'answer'));
 context:=jsonb_build_object('schema','conversation.meal-continuation-source.v1','owner_id',p_user_id,'command_id',p_reply_id,'input_hash',body_hash,'epoch',p_expected_epoch,
  'source_input',p_input,'parent',jsonb_build_object('command_id',p_parent_command_id,'input_hash',p_parent_input_hash,'source_hash',parent#>'{source,source_hash}',
   'attempt_id',parent#>'{semantic,attempt_id}','result_hash',parent#>'{semantic,result_hash}','decision_hash',parent#>'{decision,decision_hash}'),
  'answer_chain_hash',private.conversation_continuation_hash(chain),'answer_chain',chain,
  'authority',jsonb_build_object('source_hash',private.conversation_continuation_hash(authority),'context',authority));
 clock:=clock_timestamp();
 IF (clock AT TIME ZONE (authority#>>'{owner,timezone}'))::date IS DISTINCT FROM (authority#>>'{day,date}')::date THEN RETURN '{"action":"question_conflict"}'::jsonb;END IF;
 INSERT INTO private.conversation_meal_command_ids(user_id,command_id,input_hash,command_protocol,kind,epoch,admitted_at)
  VALUES(p_user_id,p_reply_id,body_hash,'conversation.clarification.v1','meal.clarify',p_expected_epoch,clock) RETURNING * INTO child;
 INSERT INTO private.conversation_meal_reply_ids VALUES(p_user_id,p_reply_id,p_parent_command_id,p_parent_input_hash,p_parent_decision_hash);
 INSERT INTO private.conversation_meal_command_sources VALUES(p_user_id,p_reply_id,p_input);
 INSERT INTO private.conversation_meal_source_captures VALUES(p_user_id,p_reply_id,private.conversation_continuation_hash(context),context,clock) RETURNING * INTO source;
 INSERT INTO private.conversation_meal_replies VALUES(p_user_id,p_reply_id,question);
 INSERT INTO private.conversation_meal_continuation_heads VALUES(p_user_id,p_parent_command_id,(head->>'revision')::integer,question,head->'answers',NULL) ON CONFLICT DO NOTHING;
 RETURN jsonb_build_object('action','admitted','parent_binding',parent->'binding','child_binding',private.conversation_meal_command_binding(child),'question',question,
  'source',jsonb_build_object('source_hash',source.source_hash,'captured_at',source.captured_at,'context',source.context));
END $$;
CREATE FUNCTION private.conversation_continuation_source_current(p_user uuid,p_reply uuid) RETURNS boolean
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE s private.conversation_meal_source_captures%ROWTYPE;fresh jsonb;parent uuid;original jsonb;
BEGIN
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user AND command_id=p_reply;
 IF s.command_id IS NULL OR s.context->>'schema' IS DISTINCT FROM 'conversation.meal-continuation-source.v1'
  OR s.source_hash IS DISTINCT FROM private.conversation_continuation_hash(s.context) THEN RETURN false;END IF;
 parent:=(s.context#>>'{parent,command_id}')::uuid;
 original:=private.conversation_continuation_parent(p_user,parent);
 IF original IS NULL OR NOT private.conversation_continuation_original_current(p_user,original) THEN RETURN false;END IF;
 fresh:=private.conversation_meal_source_at(p_user,parent,NULL);
 RETURN fresh IS NOT DISTINCT FROM s.context#>'{authority,context}'
  AND private.conversation_continuation_hash(fresh) IS NOT DISTINCT FROM s.context#>>'{authority,source_hash}';
END $$;
CREATE FUNCTION public.read_conversation_meal_continuation_nutrition_source(p_user_id uuid,p_reply_id uuid,p_kind text,p_food_name text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;s private.conversation_meal_source_captures%ROWTYPE;n private.conversation_meal_nutrition_sources%ROWTYPE;lookup text;rows jsonb;
BEGIN
 gate:=private.lock_conversation_meal(p_user_id,p_reply_id);IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 IF NOT EXISTS(SELECT 1 FROM private.conversation_meal_reply_ids WHERE user_id=p_user_id AND reply_id=p_reply_id) THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
 IF p_kind IS NULL OR p_kind NOT IN('trusted_recent','exact_median') OR (p_kind='trusted_recent' AND p_food_name IS NOT NULL)
  OR (p_kind='exact_median' AND NOT private.conversation_command_text_valid(to_jsonb(p_food_name),250)) THEN
  RAISE EXCEPTION 'invalid_conversation_nutrition_lookup' USING ERRCODE='22023';END IF;
 IF EXISTS(SELECT 1 FROM private.conversation_meal_resolved WHERE user_id=p_user_id AND command_id=p_reply_id) THEN RETURN '{"action":"sealed"}'::jsonb;END IF;
 SELECT * INTO s FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_reply_id;
 IF NOT FOUND THEN RETURN '{"action":"source_required"}'::jsonb;END IF;
 IF NOT private.conversation_continuation_source_current(p_user_id,p_reply_id) THEN RETURN '{"action":"source_conflict"}'::jsonb;END IF;
 lookup:=encode(sha256(convert_to(jsonb_build_object('kind',p_kind,'food_name',p_food_name)::text,'UTF8')),'hex');
 SELECT * INTO n FROM private.conversation_meal_nutrition_sources WHERE user_id=p_user_id AND command_id=p_reply_id AND lookup_key=lookup;
 IF NOT FOUND THEN
  IF (SELECT count(*) FROM private.conversation_meal_nutrition_sources WHERE user_id=p_user_id AND command_id=p_reply_id)>=64 THEN RAISE EXCEPTION 'conversation_nutrition_lookup_limit' USING ERRCODE='54000';END IF;
  rows:=private.conversation_meal_nutrition_rows(p_user_id,p_kind,p_food_name,s.captured_at);
  IF octet_length(rows::text)+(SELECT coalesce(sum(octet_length(x.rows::text)),0) FROM private.conversation_meal_nutrition_sources x WHERE user_id=p_user_id AND command_id=p_reply_id)>2097152 THEN RAISE EXCEPTION 'conversation_nutrition_source_too_large' USING ERRCODE='54000';END IF;
  INSERT INTO private.conversation_meal_nutrition_sources VALUES(p_user_id,p_reply_id,lookup,gen_random_uuid(),p_kind,p_food_name,
   private.conversation_continuation_hash(jsonb_build_object('kind',p_kind,'food_name',p_food_name,'as_of',s.captured_at,'rows',rows)),rows) RETURNING * INTO n;
  gate:='captured';
 ELSE gate:='replay';END IF;
 RETURN jsonb_build_object('action',gate,'owner_id',p_user_id,'command_id',p_reply_id,'source_receipt_id',n.source_receipt_id,
  'source_receipt_hash',n.result_hash,'as_of',s.captured_at,'rows',n.rows);
END $$;
CREATE FUNCTION private.assert_conversation_continuation_materialization(m jsonb,parent jsonb) RETURNS integer
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE item jsonb;g jsonb;pos jsonb;food jsonb;n integer:=0;gi integer:=0;index integer;covered integer[]:='{}';inputs integer[]:='{}';
BEGIN
 PERFORM private.conversation_meal_keys(m,ARRAY['schema','status','input_hash','source_hash','attempt_id','inputs','source_groups','nutrition_label']);
 IF m->>'schema' IS DISTINCT FROM 'conversation.meal-materialization.v1' OR m->>'status' IS DISTINCT FROM 'materialized'
  OR m->'input_hash' IS DISTINCT FROM parent#>'{binding,input_hash}' OR m->'source_hash' IS DISTINCT FROM parent#>'{source,source_hash}'
  OR m->'attempt_id' IS DISTINCT FROM parent#>'{semantic,attempt_id}' OR m->'nutrition_label' IS DISTINCT FROM 'null'::jsonb
  OR jsonb_typeof(m->'inputs') IS DISTINCT FROM 'array' OR jsonb_array_length(m->'inputs') NOT BETWEEN 1 AND 30
  OR jsonb_typeof(m->'source_groups') IS DISTINCT FROM 'array' OR jsonb_array_length(m->'source_groups') NOT BETWEEN 1 AND 30 THEN
  RAISE EXCEPTION 'invalid_conversation_continuation_materialization' USING ERRCODE='22023';END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(m->'inputs') LOOP
  PERFORM private.conversation_meal_keys(item,ARRAY['input_index','calculation_input','candidate','source_group_index']);
  PERFORM private.conversation_meal_keys(item->'calculation_input',ARRAY['food_name','quantity_g']);
  IF item->'input_index' IS DISTINCT FROM to_jsonb(n) OR NOT private.conversation_command_text_valid(item#>'{calculation_input,food_name}',160)
   OR jsonb_typeof(item#>'{calculation_input,quantity_g}') IS DISTINCT FROM 'number'
   OR (item#>>'{calculation_input,quantity_g}')::numeric<=0 OR (item#>>'{calculation_input,quantity_g}')::numeric>9999 THEN RAISE EXCEPTION 'invalid_conversation_continuation_materialization' USING ERRCODE='22023';END IF;
  index:=private.conversation_semantic_uint(item->'source_group_index',29)::integer;
  IF index>=jsonb_array_length(m->'source_groups') OR item#>'{candidate,name}' IS DISTINCT FROM item#>'{calculation_input,food_name}'
   OR item#>'{candidate,quantity_g}' IS DISTINCT FROM item#>'{calculation_input,quantity_g}' THEN RAISE EXCEPTION 'invalid_conversation_continuation_materialization' USING ERRCODE='22023';END IF;
  -- Candidate is a retained private hint, never nutrition/semantic authority.
  IF jsonb_typeof(item->'candidate') IS DISTINCT FROM 'object' OR NOT(item->'candidate' ?& ARRAY['candidate_id','name','quantity_g','quantity_basis','count','unit_label','confidence','needs_review','review_reason'])
   OR (item->'candidate')-ARRAY['candidate_id','name','quantity_g','quantity_basis','count','unit_label','confidence','needs_review','review_reason','quantity_display']<>'{}'::jsonb
   OR NOT private.conversation_command_text_valid(item#>'{candidate,candidate_id}',250)
   OR item#>>'{candidate,quantity_basis}' IS NULL OR item#>>'{candidate,quantity_basis}' NOT IN('stated','portion_reference','visual_estimate')
   OR jsonb_typeof(item#>'{candidate,count}') NOT IN('number','null') OR (item#>>'{candidate,count}')::numeric<=0
   OR (item#>'{candidate,unit_label}'<>'null'::jsonb AND NOT private.conversation_command_text_valid(item#>'{candidate,unit_label}',40))
   OR jsonb_typeof(item#>'{candidate,confidence}') NOT IN('number','null') OR (item#>>'{candidate,confidence}')::numeric NOT BETWEEN 0 AND 1
   OR jsonb_typeof(item#>'{candidate,needs_review}') IS DISTINCT FROM 'boolean'
   OR (item#>'{candidate,review_reason}'<>'null'::jsonb AND item#>>'{candidate,review_reason}' NOT IN('low_confidence','estimated_quantity','missing_quantity','ambiguous')) THEN
   RAISE EXCEPTION 'invalid_conversation_continuation_materialization' USING ERRCODE='22023';END IF;
  IF item->'candidate' ? 'quantity_display' THEN
   PERFORM private.conversation_meal_keys(item#>'{candidate,quantity_display}',ARRAY['unit','grams_per_unit','reference_id','estimated']);
   IF item#>>'{candidate,quantity_display,unit}' IS NULL OR item#>>'{candidate,quantity_display,unit}' NOT IN('mL','unit','scoop')
    OR jsonb_typeof(item#>'{candidate,quantity_display,grams_per_unit}') IS DISTINCT FROM 'number' OR (item#>>'{candidate,quantity_display,grams_per_unit}')::numeric<=0
    OR NOT private.conversation_command_text_valid(item#>'{candidate,quantity_display,reference_id}',200)
    OR item#>'{candidate,quantity_display,estimated}' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'invalid_conversation_continuation_materialization' USING ERRCODE='22023';END IF;
  END IF;
  n:=n+1;
 END LOOP;
 FOR g IN SELECT value FROM jsonb_array_elements(m->'source_groups') LOOP
  PERFORM private.conversation_meal_keys(g,ARRAY['group_index','interpretation_food_indexes','input_indexes','rule','source_positions']);
  IF g->'group_index' IS DISTINCT FROM to_jsonb(gi) OR g->>'rule' IS NULL OR g->>'rule' NOT IN('literal','mobile_household','milk_whey_cup','milk_whey_total','prepared_dish','visual')
   OR jsonb_typeof(g->'interpretation_food_indexes') IS DISTINCT FROM 'array' OR jsonb_array_length(g->'interpretation_food_indexes') NOT BETWEEN 1 AND 30
   OR jsonb_typeof(g->'input_indexes') IS DISTINCT FROM 'array' OR jsonb_array_length(g->'input_indexes') NOT BETWEEN 1 AND 30
   OR jsonb_typeof(g->'source_positions') IS DISTINCT FROM 'array' OR jsonb_array_length(g->'source_positions')<>jsonb_array_length(g->'interpretation_food_indexes') THEN
   RAISE EXCEPTION 'invalid_conversation_continuation_materialization' USING ERRCODE='22023';END IF;
  FOR pos IN SELECT value FROM jsonb_array_elements(g->'source_positions') LOOP
   PERFORM private.conversation_meal_keys(pos,ARRAY['food_index','unit','name','quantity','unit_ref','visual_index']);
   index:=private.conversation_semantic_uint(pos->'food_index',29)::integer;
   SELECT x INTO food FROM jsonb_array_elements(parent#>'{semantic,result,foods}') x WHERE (x->>'index')::numeric=index;
   IF food IS NULL OR index=ANY(covered) OR NOT(g->'interpretation_food_indexes' @> jsonb_build_array(index))
    OR pos->'name' IS DISTINCT FROM food->'name' OR pos->'quantity' IS DISTINCT FROM food->'quantity'
    OR pos->'unit_ref' IS DISTINCT FROM food->'unit' OR pos->'visual_index' IS DISTINCT FROM food->'visual_index'
    OR pos->>'unit' IS DISTINCT FROM coalesce(food#>>'{name,unit}',CASE WHEN food->'visual_index'<>'null'::jsonb THEN 'vision_items' ELSE food#>>'{quantity,unit}' END) THEN
    RAISE EXCEPTION 'invalid_conversation_continuation_source_positions' USING ERRCODE='22023';END IF;
   covered:=array_append(covered,index);
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(g->'input_indexes') LOOP
   index:=private.conversation_semantic_uint(item,29)::integer;
   IF index>=n OR index=ANY(inputs) OR m#>ARRAY['inputs',index::text,'source_group_index'] IS DISTINCT FROM to_jsonb(gi) THEN
    RAISE EXCEPTION 'invalid_conversation_continuation_input_coverage' USING ERRCODE='22023';END IF;
   inputs:=array_append(inputs,index);
  END LOOP;gi:=gi+1;
 END LOOP;
 IF (SELECT array_agg(x ORDER BY x) FROM unnest(covered) x) IS DISTINCT FROM ARRAY(SELECT generate_series(0,jsonb_array_length(parent#>'{semantic,result,foods}')-1))
  OR (SELECT array_agg(x ORDER BY x) FROM unnest(inputs) x) IS DISTINCT FROM ARRAY(SELECT generate_series(0,n-1)) THEN
  RAISE EXCEPTION 'invalid_conversation_continuation_input_coverage' USING ERRCODE='22023';END IF;
 RETURN n;
END $$;
CREATE FUNCTION public.prepare_conversation_meal_continuation(p_user_id uuid,p_parent_command_id uuid,p_expected_epoch uuid,p_parent_input_hash text,
 p_reply_id uuid,p_reply_input_hash text,p_preparation jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;parent jsonb;head jsonb;reply jsonb;next_question jsonb;stored jsonb;h text;r private.conversation_meal_resolved%ROWTYPE;meta private.conversation_meal_continuation_preparations%ROWTYPE;
BEGIN
 gate:=private.lock_conversation_continuation(p_user_id,p_parent_command_id,p_expected_epoch,p_parent_input_hash);
 IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 parent:=private.conversation_continuation_parent(p_user_id,p_parent_command_id);IF parent IS NULL THEN RETURN '{"action":"ineligible"}'::jsonb;END IF;
 head:=private.conversation_continuation_head(p_user_id,p_parent_command_id,parent);
 reply:=private.conversation_continuation_reply(p_user_id,p_parent_command_id,p_reply_id,p_reply_input_hash,head);
 IF reply IS NULL THEN RETURN '{"action":"input_conflict"}'::jsonb;END IF;
 SELECT * INTO r FROM private.conversation_meal_resolved WHERE user_id=p_user_id AND command_id=p_reply_id;
 IF FOUND THEN
  IF p_preparation IS DISTINCT FROM r.resolved THEN RETURN '{"action":"prepared_conflict"}'::jsonb;END IF;
  SELECT * INTO STRICT meta FROM private.conversation_meal_continuation_preparations WHERE user_id=p_user_id AND reply_id=p_reply_id;
  RETURN jsonb_build_object('action','replay','parent_binding',parent->'binding','child_binding',reply->'binding',
   'stored',jsonb_build_object('prepared_hash',r.resolved_hash,'prepared_at',r.prepared_at,'preparation',r.resolved,'next_question',meta.next_question),'head',head);
 END IF;
 IF head IS NULL OR head->'fulfilled_by'<>'null'::jsonb OR head->'revision' IS DISTINCT FROM reply#>'{body,expected_revision}'
  OR head#>'{question,question_key}' IS DISTINCT FROM reply#>'{body,question_key}' THEN RETURN '{"action":"question_conflict"}'::jsonb;END IF;
 IF NOT private.conversation_continuation_source_current(p_user_id,p_reply_id) THEN RETURN '{"action":"source_conflict"}'::jsonb;END IF;
 IF (reply#>>'{source,context,authority,context,day,day_closed}')::boolean THEN RETURN '{"action":"day_closed"}'::jsonb;END IF;
 PERFORM private.assert_conversation_continuation_preparation(p_preparation,parent,reply);
 IF p_preparation->>'status'='ready' AND NOT private.conversation_meal_nutrition_current(p_user_id,p_reply_id,p_preparation#>'{meal,source_receipts}') THEN
  RETURN '{"action":"source_conflict"}'::jsonb;END IF;
 IF p_preparation->>'status'='needs_reply' THEN
  next_question:=private.conversation_continuation_question(parent,(head->>'revision')::integer+1,reply#>'{source,context,answer_chain}',
   p_preparation#>>'{next_need,kind}',(p_preparation#>>'{next_need,food_index}')::numeric::integer);
 END IF;
 h:=private.conversation_continuation_hash(p_preparation);
 INSERT INTO private.conversation_meal_resolved VALUES(p_user_id,p_reply_id,h,p_preparation,clock_timestamp()) RETURNING * INTO r;
 INSERT INTO private.conversation_meal_continuation_preparations VALUES(p_user_id,p_reply_id,next_question);
 IF next_question IS NOT NULL THEN
  UPDATE private.conversation_meal_continuation_heads SET revision=revision+1,question=next_question,answers=reply#>'{source,context,answer_chain}'
   WHERE user_id=p_user_id AND parent_command_id=p_parent_command_id;
 END IF;
 head:=private.conversation_continuation_head(p_user_id,p_parent_command_id,parent);
 IF NOT private.conversation_continuation_original_current(p_user_id,parent) THEN
  RAISE EXCEPTION 'conversation_original_source_changed_before_preparation' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('action','prepared','parent_binding',parent->'binding','child_binding',reply->'binding',
  'stored',jsonb_build_object('prepared_hash',h,'prepared_at',r.prepared_at,'preparation',r.resolved,'next_question',next_question),'head',head);
END $$;
CREATE FUNCTION private.assert_conversation_continuation_preparation(v jsonb,parent jsonb,reply jsonb) RETURNS void
LANGUAGE plpgsql STABLE SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE common text[]:=ARRAY['schema','status','input_hash','source_hash','parent_ref','answer_chain_hash','quantity_witnesses','materialization'];
 source jsonb:=reply#>'{source,context}';chain jsonb:=reply#>'{source,context,answer_chain}';link jsonb;q jsonb;w jsonb;item jsonb;food jsonb;
 witnesses uuid[]:='{}';seen integer[];index integer;count_inputs integer;grams numeric;projection jsonb;authority jsonb;meal_type text;
BEGIN
 IF v->>'status'='ready' THEN PERFORM private.conversation_meal_keys(v,common||ARRAY['meal']);
 ELSIF v->>'status'='needs_reply' THEN PERFORM private.conversation_meal_keys(v,common||ARRAY['next_need']);
 ELSE RAISE EXCEPTION 'invalid_conversation_continuation_preparation' USING ERRCODE='22023';END IF;
 IF v->>'schema' IS DISTINCT FROM 'conversation.meal-continuation-preparation.v1' OR v->'input_hash' IS DISTINCT FROM reply#>'{binding,input_hash}'
  OR v->'source_hash' IS DISTINCT FROM reply#>'{source,source_hash}' OR v->'parent_ref' IS DISTINCT FROM source->'parent'
  OR v->'answer_chain_hash' IS DISTINCT FROM source->'answer_chain_hash' OR octet_length(v::text)>262144
  OR jsonb_typeof(v->'quantity_witnesses') IS DISTINCT FROM 'array' OR jsonb_array_length(v->'quantity_witnesses')>30 THEN
  RAISE EXCEPTION 'invalid_conversation_continuation_preparation' USING ERRCODE='22023';END IF;
 IF v#>>'{materialization,status}'='materialized' THEN count_inputs:=private.assert_conversation_continuation_materialization(v->'materialization',parent);
 ELSIF v->>'status'='needs_reply' THEN
  PERFORM private.conversation_meal_keys(v->'materialization',ARRAY['status','reason','food_indexes']);
  IF v#>>'{materialization,status}' IS DISTINCT FROM 'clarification_required' OR v#>>'{materialization,reason}' IS DISTINCT FROM 'missing_quantity'
   OR v#>>'{next_need,kind}' IS DISTINCT FROM 'quantity' OR v#>'{materialization,food_indexes}' IS DISTINCT FROM jsonb_build_array(v#>'{next_need,food_index}') THEN
   RAISE EXCEPTION 'invalid_conversation_continuation_preparation' USING ERRCODE='22023';END IF;
 ELSE RAISE EXCEPTION 'invalid_conversation_continuation_preparation' USING ERRCODE='22023';END IF;
 FOR w IN SELECT value FROM jsonb_array_elements(v->'quantity_witnesses') LOOP
  PERFORM private.conversation_meal_keys(w,ARRAY['reply_id','food_index','amount','unit','quantity_g','quantity_basis','quantity_display','input_indexes']);
  SELECT x INTO link FROM jsonb_array_elements(chain) x WHERE x->'reply_id'=w->'reply_id' AND x#>>'{answer,kind}'='quantity';
  IF link IS NULL OR (w->>'reply_id')::uuid=ANY(witnesses) OR w->'food_index' IS DISTINCT FROM link#>'{answer,food_index}'
   OR w->'amount' IS DISTINCT FROM link#>'{answer,amount}' OR w->'unit' IS DISTINCT FROM link#>'{answer,unit}' THEN
   RAISE EXCEPTION 'invalid_conversation_continuation_quantity_witness' USING ERRCODE='22023';END IF;
  SELECT question INTO q FROM private.conversation_meal_replies WHERE user_id=(reply#>>'{binding,owner_id}')::uuid AND reply_id=(w->>'reply_id')::uuid;
  grams:=private.conversation_continuation_grams(link->'answer',q);
  IF grams IS NULL OR w->'quantity_g' IS DISTINCT FROM to_jsonb(grams)
   OR w->>'quantity_basis' IS DISTINCT FROM (CASE WHEN w->>'unit' IN('g','kg') THEN 'stated' ELSE 'portion_reference' END)
   OR w->'quantity_display' IS DISTINCT FROM (CASE WHEN w->>'unit' IN('g','kg') THEN 'null'::jsonb ELSE q->'quantity_reference' END)
   OR jsonb_typeof(w->'input_indexes') IS DISTINCT FROM 'array' OR jsonb_array_length(w->'input_indexes')>30
   OR (count_inputs IS NOT NULL AND jsonb_array_length(w->'input_indexes')=0)
   OR (count_inputs IS NULL AND jsonb_array_length(w->'input_indexes')<>0) THEN
   RAISE EXCEPTION 'invalid_conversation_continuation_quantity_witness' USING ERRCODE='22023';END IF;
  witnesses:=array_append(witnesses,(w->>'reply_id')::uuid);seen:='{}';
  FOR item IN SELECT value FROM jsonb_array_elements(w->'input_indexes') LOOP
   index:=private.conversation_semantic_uint(item,29)::integer;
   IF index=ANY(seen) THEN RAISE EXCEPTION 'invalid_conversation_continuation_quantity_witness' USING ERRCODE='22023';END IF;seen:=array_append(seen,index);
   IF count_inputs IS NOT NULL AND (index>=count_inputs OR
    (v#>>ARRAY['materialization','inputs',index::text,'calculation_input','quantity_g'])::numeric IS DISTINCT FROM grams
    OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v#>'{materialization,source_groups}') g
     WHERE g->'interpretation_food_indexes' @> jsonb_build_array(w->'food_index') AND g->'input_indexes' @> jsonb_build_array(index))) THEN
    RAISE EXCEPTION 'invalid_conversation_continuation_quantity_witness' USING ERRCODE='22023';END IF;
  END LOOP;
 END LOOP;
 IF cardinality(witnesses)<>(SELECT count(*) FROM jsonb_array_elements(chain) x WHERE x#>>'{answer,kind}'='quantity') THEN
  RAISE EXCEPTION 'incomplete_conversation_continuation_quantity_witnesses' USING ERRCODE='22023';END IF;
 IF v->>'status'='needs_reply' THEN
  PERFORM private.conversation_meal_keys(v->'next_need',ARRAY['kind','food_index']);
  q:=private.conversation_continuation_question(parent,(reply#>>'{body,expected_revision}')::numeric::integer+1,chain,v#>>'{next_need,kind}',(v#>>'{next_need,food_index}')::numeric::integer);
  IF q IS NULL OR (q->>'kind'='meal_type' AND count_inputs IS NULL) THEN RAISE EXCEPTION 'invalid_conversation_continuation_next_question' USING ERRCODE='22023';END IF;
  RETURN;
 END IF;
 PERFORM private.conversation_meal_keys(v->'meal',ARRAY['meal_type','items','totals','preparation_annotations','source_receipts']);
 SELECT x#>>'{answer,meal_type}' INTO meal_type FROM jsonb_array_elements(chain) x WHERE x#>>'{answer,kind}'='meal_type';
 IF meal_type IS NOT NULL AND v#>>'{meal,meal_type}' IS DISTINCT FROM meal_type THEN RAISE EXCEPTION 'conversation_continuation_meal_type_conflict' USING ERRCODE='22023';END IF;
 -- This is a local validation projection ONLY. No v1 proof, source or provider
 -- result is persisted for a child, and no old writer is called with it.
 authority:=source#>'{authority,context}'||jsonb_build_object('command_id',reply#>'{binding,command_id}','input_hash',reply#>'{binding,input_hash}');
 projection:=(v->'meal')||jsonb_build_object('schema','conversation.meal-resolved.v1','input_hash',v->'input_hash','source_hash',v->'source_hash',
  'semantic_proof',jsonb_build_object('schema','conversation.meal-semantic.v1','decision','consumed_meal','input_hash',v->'input_hash','source_hash',v->'source_hash',
   'complete_source',true,'source_units',authority->'source_units','input_count',count_inputs));
 PERFORM private.assert_conversation_resolved_meal(projection,authority,v->>'source_hash');
END $$;


CREATE FUNCTION public.commit_conversation_meal_continuation(p_user_id uuid,p_parent_command_id uuid,p_expected_epoch uuid,p_parent_input_hash text,
 p_reply_id uuid,p_reply_input_hash text,p_prepared_hash text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog SET timezone='UTC' SET datestyle='ISO,YMD' AS $$
DECLARE gate text;parent jsonb;head jsonb;reply jsonb;fulfillment jsonb;meal jsonb;fresh jsonb;
 p_user uuid:=p_user_id;p_command uuid:=p_reply_id;s private.conversation_meal_source_captures%ROWTYPE;r private.conversation_meal_resolved%ROWTYPE;
 clock timestamptz;day date;zone text;registration uuid:=gen_random_uuid();provider text;
 proposal jsonb;atomic_items jsonb;registered jsonb;logs jsonb;log_ids jsonb;snapshot jsonb;original jsonb;feedback jsonb;receipt jsonb;effect_hash text;item jsonb;matched jsonb;used text[]:='{}';
BEGIN
 gate:=private.lock_conversation_continuation(p_user_id,p_parent_command_id,p_expected_epoch,p_parent_input_hash);
 IF gate<>'current' THEN RETURN jsonb_build_object('action',gate);END IF;
 parent:=private.conversation_continuation_parent(p_user_id,p_parent_command_id);IF parent IS NULL THEN RETURN '{"action":"event_conflict"}'::jsonb;END IF;
 head:=private.conversation_continuation_head(p_user_id,p_parent_command_id,parent);
 reply:=private.conversation_continuation_reply(p_user_id,p_parent_command_id,p_reply_id,p_reply_input_hash,head);
 IF reply IS NULL THEN RETURN '{"action":"input_conflict"}'::jsonb;END IF;
 fulfillment:=private.conversation_continuation_fulfillment(p_user_id,p_parent_command_id);
 IF fulfillment IS NOT NULL THEN
  IF fulfillment#>>'{child_binding,command_id}' IS DISTINCT FROM p_reply_id::text THEN RETURN '{"action":"question_conflict"}'::jsonb;END IF;
  RETURN jsonb_build_object('action','replay','fulfillment',fulfillment);
 END IF;
 IF head IS NULL OR head->'fulfilled_by'<>'null'::jsonb OR head->'revision' IS DISTINCT FROM reply#>'{body,expected_revision}'
  OR head#>'{question,question_key}' IS DISTINCT FROM reply#>'{body,question_key}' THEN RETURN '{"action":"question_conflict"}'::jsonb;END IF;
 SELECT * INTO r FROM private.conversation_meal_resolved WHERE user_id=p_user_id AND command_id=p_reply_id;
 IF NOT FOUND OR r.resolved->>'status'<>'ready' THEN RETURN '{"action":"prepared_required"}'::jsonb;END IF;
 IF p_prepared_hash IS DISTINCT FROM r.resolved_hash THEN RETURN '{"action":"prepared_conflict"}'::jsonb;END IF;
 IF NOT private.conversation_continuation_source_current(p_user_id,p_reply_id) THEN RETURN '{"action":"source_conflict"}'::jsonb;END IF;
 SELECT * INTO STRICT s FROM private.conversation_meal_source_captures WHERE user_id=p_user_id AND command_id=p_reply_id;
 fresh:=s.context#>'{authority,context}';meal:=r.resolved->'meal';
 IF (fresh#>>'{day,day_closed}')::boolean THEN RETURN '{"action":"day_closed"}'::jsonb;END IF;
 PERFORM private.assert_conversation_continuation_preparation(r.resolved,parent,reply);
 IF NOT private.conversation_meal_nutrition_current(p_user_id,p_reply_id,meal->'source_receipts') THEN RETURN '{"action":"source_conflict"}'::jsonb;END IF;
 clock:=clock_timestamp();zone:=fresh#>>'{owner,timezone}';day:=(fresh#>>'{day,date}')::date;
 IF (clock AT TIME ZONE zone)::date IS DISTINCT FROM day THEN RETURN '{"action":"source_conflict"}'::jsonb;END IF;
 -- A parent has one fulfillment group, irrespective of replay/reply UUID.
 provider:='conversation.clarification/'||p_user::text||'/'||p_parent_command_id::text;
 IF EXISTS(SELECT 1 FROM public.meal_logs WHERE user_id=p_user AND raw_provider_message_id=provider) THEN RAISE EXCEPTION 'conversation_unjournaled_domain_effect' USING ERRCODE='40001'; END IF;
 SELECT jsonb_agg(jsonb_build_object('name',x->'name','food_db_id',x->'food_db_id','nutrition_source',x->'nutrition_source','quantity_g',x->'quantity_g',
  'kcal',x->'kcal','protein_g',x->'protein_g','carbs_g',x->'carbs_g','fat_g',x->'fat_g','display_qty',x->'display_qty','display_unit',x->'display_unit','quantity_basis',x->'quantity_basis') ORDER BY n),
  jsonb_agg(jsonb_build_object('food_name',x->'name','food_db_id',x->'food_db_id','source',x->'nutrition_source','quantity_g',x->'quantity_g',
  'kcal',x->'kcal','protein_g',x->'protein_g','carbs_g',x->'carbs_g','fat_g',x->'fat_g','confidence',x->'confidence') ORDER BY n)
 INTO proposal,atomic_items FROM jsonb_array_elements(meal->'items') WITH ORDINALITY a(x,n);
 proposal:=jsonb_build_object('kind','meal','mealType',meal->'meal_type','registration_origin','mobile_app','items',proposal,'totals',meal->'totals',
  'source_provider_message_id',provider,'source_timestamp',to_char(clock AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'source_timezone',zone,'source_local_date',day,
  'replace',false,'express_eligible',false,'command_protocol','conversation.clarification.v1','command_id',p_command,
  'preparation_annotations',meal->'preparation_annotations');
 INSERT INTO public.pending_registrations(id,user_id,status,proposal,created_at,expires_at,resolved_at) VALUES(registration,p_user,'confirmed',proposal,clock,clock,clock);
 registered:=public.register_meal_atomic(p_user,day,(meal->>'meal_type')::public.meal_type_enum,atomic_items,false,NULL,clock,provider,
  (fresh#>>'{day,calories_target}')::integer,(fresh#>>'{day,protein_target}')::numeric);
 IF (registered->>'inserted_count')::integer IS DISTINCT FROM jsonb_array_length(atomic_items) OR (registered->>'replaced_count')::integer IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'conversation_meal_partial_domain_effect' USING ERRCODE='40001'; END IF;
 -- Pin the new command group's creation clock too; transaction-start now()
 -- must not let a later append enter an earlier frozen history window.
 UPDATE public.meal_logs SET created_at=clock WHERE user_id=p_user AND raw_provider_message_id=provider;
 SELECT jsonb_agg(to_jsonb(m) ORDER BY m.id),jsonb_agg(to_jsonb(m.id) ORDER BY m.id) INTO logs,log_ids FROM public.meal_logs m WHERE user_id=p_user AND raw_provider_message_id=provider;
 IF jsonb_array_length(logs) IS DISTINCT FROM jsonb_array_length(atomic_items) THEN RAISE EXCEPTION 'conversation_meal_group_changed' USING ERRCODE='40001'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(atomic_items) LOOP
  SELECT x INTO matched FROM jsonb_array_elements(logs) x WHERE NOT(x->>'id'=ANY(used)) AND x->>'food_name'=item->>'food_name'
   AND x->'food_db_id'=item->'food_db_id' AND x->>'source'=item->>'source' AND x->'quantity_g'=to_jsonb(round((item->>'quantity_g')::numeric,2))
   AND x->'kcal'=to_jsonb(round((item->>'kcal')::numeric,2)) AND x->'protein_g'=to_jsonb(round((item->>'protein_g')::numeric,2))
   AND x->'carbs_g'=to_jsonb(round((item->>'carbs_g')::numeric,2)) AND x->'fat_g'=to_jsonb(round((item->>'fat_g')::numeric,2))
   AND x->'confidence'=coalesce(to_jsonb(round((item->>'confidence')::numeric,2)),'null')
   AND (x->>'consumed_at')::timestamptz=clock AND x->>'meal_type'=meal->>'meal_type'
   AND (x->>'snapshot_id')::uuid=(registered->>'snapshot_id')::uuid;
  IF matched IS NULL THEN RAISE EXCEPTION 'conversation_meal_saved_facts_changed' USING ERRCODE='40001'; END IF;
  used:=array_append(used,matched->>'id');
 END LOOP;
 SELECT to_jsonb(d) INTO STRICT snapshot FROM public.daily_snapshots d WHERE id=(registered->>'snapshot_id')::uuid AND user_id=p_user AND date=day;
 IF snapshot->'calories_target' IS DISTINCT FROM fresh#>'{day,calories_target}' OR snapshot->'protein_target' IS DISTINCT FROM fresh#>'{day,protein_target}' THEN RAISE EXCEPTION 'conversation_meal_official_targets_changed' USING ERRCODE='40001'; END IF;
 original:=jsonb_build_object('confirmed',jsonb_build_object('id',registration,'user_id',p_user,'status','confirmed','proposal',proposal),'logs',logs,'snapshot',snapshot);
 effect_hash:=encode(sha256(convert_to(private.conversation_command_canonical(original),'UTF8')),'hex');
 receipt:=jsonb_build_object('schema','conversation.meal-continuation-effect.v1','owner_id',p_user,'command_id',p_command,'input_hash',reply#>'{binding,input_hash}',
  'parent_command_id',p_parent_command_id,'parent_input_hash',p_parent_input_hash,'parent_decision_hash',parent#>'{decision,decision_hash}','epoch',p_expected_epoch,
  'registration_id',registration,'provider_key',provider,'meal_type',meal->'meal_type','local_date',day,'timezone',zone,
  'consumed_at',proposal->'source_timestamp','log_ids',log_ids,'effect_version','cmeal1:'||effect_hash);
 -- Optional enrichment cannot turn an already valid factual write into a
 -- retryable domain error. Never recapture this original source on later retry.
 BEGIN feedback:=private.capture_mobile_registration_feedback_v2(p_user,registration);
  IF feedback IS NOT NULL AND (feedback->'confirmed' IS DISTINCT FROM original->'confirmed' OR feedback->'logs' IS DISTINCT FROM logs OR feedback->'snapshot' IS DISTINCT FROM snapshot) THEN feedback:=NULL; END IF;
 EXCEPTION WHEN OTHERS THEN feedback:=NULL; END;
 IF (clock_timestamp() AT TIME ZONE zone)::date IS DISTINCT FROM day THEN RAISE EXCEPTION 'conversation_meal_clock_changed_before_completion' USING ERRCODE='40001'; END IF;
 INSERT INTO private.conversation_meal_effects VALUES(p_user,p_command,receipt,original,feedback,clock);
 INSERT INTO private.conversation_meal_fulfillments VALUES(p_user_id,p_parent_command_id,p_reply_id);
 UPDATE private.conversation_meal_continuation_heads SET revision=revision+1,question=NULL,answers=s.context->'answer_chain',fulfilled_by=p_reply_id
  WHERE user_id=p_user_id AND parent_command_id=p_parent_command_id;
 IF (clock_timestamp() AT TIME ZONE zone)::date IS DISTINCT FROM day THEN RAISE EXCEPTION 'conversation_meal_clock_changed_before_completion' USING ERRCODE='40001';END IF;
 fulfillment:=private.conversation_continuation_fulfillment(p_user_id,p_parent_command_id);
 IF fulfillment IS NULL THEN RAISE EXCEPTION 'conversation_meal_fulfillment_missing' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('action','committed','fulfillment',fulfillment);
END $$;

-- Scope the protocol fence to an actual proven registry identity only. Legacy
-- pending proposals without such linkage retain their existing behavior.
-- Narrow boolean capability for an INVOKER trigger, following the established
-- protected pending seam. No private-table grants or raw protocol lookup API.
CREATE FUNCTION private.conversation_pending_protocol_conflicts(p_user uuid,p_command uuid,p_protocol text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids c WHERE c.user_id=p_user AND c.command_id=p_command AND c.command_protocol IS DISTINCT FROM p_protocol);
$$;
CREATE FUNCTION private.fence_conversation_pending_protocol() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE command uuid;
BEGIN
 IF NEW.proposal->>'command_protocol' IS NULL OR NEW.proposal->>'command_protocol' NOT IN('conversation.command.v1','conversation.clarification.v1') THEN RETURN NEW;END IF;
 IF NEW.proposal->>'command_id' IS NULL OR NOT(NEW.proposal->>'command_id' ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') THEN RETURN NEW;END IF;
 command:=(NEW.proposal->>'command_id')::uuid;
 IF private.conversation_pending_protocol_conflicts(NEW.user_id,command,NEW.proposal->>'command_protocol') THEN
  RAISE EXCEPTION 'conversation_pending_protocol_conflict' USING ERRCODE='40001';END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER conversation_pending_protocol BEFORE INSERT ON public.pending_registrations
 FOR EACH ROW EXECUTE FUNCTION private.fence_conversation_pending_protocol();

-- The v1 page remains an exact v1/report projection in both event arms. New
-- linked replies are recovered through their own explicitly versioned reader.
CREATE OR REPLACE FUNCTION private.conversation_meal_journal_events(p_user uuid,p_epoch uuid)
RETURNS TABLE(at timestamptz,event_id text,command_id uuid,operation_id uuid)
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT c.admitted_at,'command/'||c.command_id::text,c.command_id,NULL::uuid
 FROM private.conversation_meal_command_ids c WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL
 AND c.command_protocol='conversation.command.v1' AND c.kind='meal.report'
 UNION ALL
 SELECT op.applied_at,'edit/'||c.command_id::text||'/'||op.operation_id::text,c.command_id,op.operation_id
 FROM private.conversation_meal_edit_operations op JOIN private.conversation_meal_command_ids c ON c.user_id=op.user_id AND c.command_id=op.command_id
 WHERE c.user_id=p_user AND c.epoch=p_epoch AND c.invalidated_at IS NULL
 AND c.command_protocol='conversation.command.v1' AND c.kind='meal.report';
$$;
CREATE FUNCTION private.guard_conversation_continuation_delete() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE owner uuid:=(to_jsonb(OLD)->>'user_id')::uuid;id uuid;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.users u WHERE u.id=owner) THEN RETURN OLD;END IF;
 IF TG_TABLE_NAME='conversation_meal_reply_ids' THEN RAISE EXCEPTION 'conversation_reply_identity_permanent' USING ERRCODE='22023';END IF;
 id:=coalesce((to_jsonb(OLD)->>'reply_id')::uuid,(to_jsonb(OLD)->>'parent_command_id')::uuid);
 IF NOT EXISTS(SELECT 1 FROM private.conversation_meal_source_captures WHERE user_id=owner AND command_id=id) THEN RETURN OLD;END IF;
 IF TG_TABLE_NAME='conversation_meal_continuation_preparations' AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_resolved WHERE user_id=owner AND command_id=id) THEN RETURN OLD;END IF;
 IF TG_TABLE_NAME='conversation_meal_fulfillments' AND (NOT EXISTS(SELECT 1 FROM private.conversation_meal_effects WHERE user_id=owner AND command_id=id)
  OR NOT EXISTS(SELECT 1 FROM private.conversation_meal_source_captures WHERE user_id=owner AND command_id=(to_jsonb(OLD)->>'parent_command_id')::uuid)) THEN RETURN OLD;END IF;
 RAISE EXCEPTION 'conversation_continuation_immutable' USING ERRCODE='22023';
END $$;
CREATE TRIGGER retain_conversation_meal_reply_id BEFORE DELETE ON private.conversation_meal_reply_ids FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_continuation_delete();
CREATE TRIGGER retain_conversation_meal_head BEFORE DELETE ON private.conversation_meal_continuation_heads FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_continuation_delete();
CREATE TRIGGER retain_conversation_meal_reply BEFORE DELETE ON private.conversation_meal_replies FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_continuation_delete();
CREATE TRIGGER retain_conversation_meal_continuation_preparation BEFORE DELETE ON private.conversation_meal_continuation_preparations FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_continuation_delete();
CREATE TRIGGER retain_conversation_meal_fulfillment BEFORE DELETE ON private.conversation_meal_fulfillments FOR EACH ROW EXECUTE FUNCTION private.guard_conversation_continuation_delete();
DO $$ DECLARE f record;BEGIN
 FOR f IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE (n.nspname='private' AND (p.proname LIKE 'conversation_continuation_%' OR p.proname IN('assert_conversation_meal_reply',
  'lock_conversation_continuation','assert_conversation_continuation_materialization','assert_conversation_continuation_preparation',
  'fence_conversation_pending_protocol','guard_conversation_continuation_delete','conversation_pending_protocol_conflicts'))) OR (n.nspname='public' AND p.proname IN(
  'read_conversation_meal_continuation','admit_conversation_meal_reply','read_conversation_meal_continuation_nutrition_source',
  'prepare_conversation_meal_continuation','commit_conversation_meal_continuation')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION private.conversation_pending_protocol_conflicts(uuid,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text),
 public.admit_conversation_meal_reply(uuid,uuid,uuid,text,text,uuid,jsonb),
 public.read_conversation_meal_continuation_nutrition_source(uuid,uuid,text,text),
 public.prepare_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text,jsonb),
 public.commit_conversation_meal_continuation(uuid,uuid,uuid,text,uuid,text,text) TO service_role;
COMMIT;
