BEGIN;
\ir fixtures/mobile_registration_feedback_v2_contract.sql
DO $test$
DECLARE r record;policy jsonb;
BEGIN
 FOR r IN SELECT * FROM feedback_v2_contract_cases LOOP
  PERFORM private.assert_registration_feedback_v2_shape(r.payload,(r.payload->>'registration_id')::uuid,r.payload#>>'{registration,kind}');
 END LOOP;
 FOR r IN SELECT * FROM feedback_v2_policy_cases LOOP
  policy:=private.mobile_registration_feedback_v2_policy(r.context);
  ASSERT policy=r.expected, 'v2 clinical policy parity failed: '||r.label;
 END LOOP;
 FOR r IN SELECT * FROM feedback_v2_quantity_cases LOOP
  ASSERT private.mobile_feedback_v2_quantity(r.food_name,r.mass,r.basis)=r.expected,'v2 quantity parity failed: '||r.food_name||'/'||r.mass;
 END LOOP;
END $test$;
SELECT (SELECT count(*) FROM feedback_v2_contract_cases) AS contract_cases,(SELECT count(*) FROM feedback_v2_policy_cases) AS policy_cases;

CREATE TEMP TABLE invalid_feedback_cases(label text PRIMARY KEY,payload jsonb) ON COMMIT DROP;
DO $bad$
DECLARE f jsonb;w jsonb;i jsonb;k text;
BEGIN
 SELECT payload INTO f FROM feedback_v2_contract_cases WHERE label='milk_whey/pt-BR/false/recomposicao';
 SELECT payload INTO w FROM feedback_v2_contract_cases WHERE label='activity_walking/pt-BR/false/recomposicao';
 FOREACH k IN ARRAY ARRAY['schema','registration_id','local_date','locale','assistant','registration','day','block','guidance','education'] LOOP
  INSERT INTO invalid_feedback_cases VALUES('missing root '||k,f-k);
 END LOOP;
 INSERT INTO invalid_feedback_cases VALUES
 ('root private field',f||'{"clinical":{}}'),
 ('wrong assistant',jsonb_set(f,'{assistant}','"Roberto nutricionista"')),
 ('wrong schema',jsonb_set(f,'{schema}','"registration.feedback.v3"')),
 ('wrong language',jsonb_set(f,'{locale}','"fr"')),
 ('invalid date',jsonb_set(f,'{local_date}','"2026-02-30"')),
 ('missing item ID',jsonb_set(f,'{registration,items,0}',(f#>'{registration,items,0}')-'log_id')),
 ('duplicate item ID',jsonb_set(f,'{registration,items,1,log_id}',f#>'{registration,items,0,log_id}')),
 ('unknown nutrient',jsonb_set(f,'{registration,totals}',(f#>'{registration,totals}')||'{"cholesterol":10}')),
 ('negative nutrient',jsonb_set(f,'{registration,items,0,protein_g}','-1')),
 ('string nutrient',jsonb_set(f,'{registration,items,0,kcal}','"126"')),
 ('unresolved source',jsonb_set(f,'{registration,items,0,nutrition_source}','"unknown"')),
 ('empty name',jsonb_set(f,'{registration,items,0,food_name}','" "')),
 ('mass exceeds limit',jsonb_set(f,'{registration,items,0,quantity_g}','10000')),
 ('nonpositive quantity',jsonb_set(f,'{registration,items,0,quantity,value}','0')),
 ('unsupported unit',jsonb_set(f,'{registration,items,0,quantity,unit}','"glass"')),
 ('quantity mass mismatch',jsonb_set(f,'{registration,items,0,quantity,value}','99')),
 ('quantity flag not Boolean',jsonb_set(f,'{registration,items,0,quantity,estimated}','1')),
 ('duration limit',jsonb_set(w,'{registration,duration_min}','1441')),
 ('zero duration',jsonb_set(w,'{registration,duration_min}','0')),
 ('nested private day',jsonb_set(f,'{day}',(f->'day')||'{"health":"private"}')),
 ('percentage without target',jsonb_set(f,'{day,targets,protein_g}','null')),
 ('wrong percentage',jsonb_set(f,'{day,protein_percentage}','99')),
 ('double food budget',jsonb_set(f,'{day,food_excess_kcal}','10')),
 ('unavailable day guidance',jsonb_set(f,'{guidance}','"unavailable"')),
 ('paused day targets',jsonb_set(f,'{guidance}','"paused"')),
 ('available block missing day',jsonb_set(f,'{day}','null')),
 ('fractional completed blocks',jsonb_set(f,'{block,completed_blocks}','2.5')),
 ('fabricated total block',jsonb_set(f,'{block,total_credited_kcal}','99999')),
 ('wrong block target',jsonb_set(f,'{block,target_kcal}','7701')),
 ('unavailable block carries numbers',jsonb_set(f,'{block,status}','"unavailable"')),
 ('unknown block state',jsonb_set(f,'{block}','{"status":"pending"}')),
 ('education text tampered',jsonb_set(f,'{education,text}','"Sou humano e garanto perda de peso"')),
 ('education catalog tampered',jsonb_set(f,'{education,provenance,catalog_version}','"registration.education.v2"')),
 ('education template tampered',jsonb_set(f,'{education,provenance,template_id}','"meal_protein"')),
 ('education extra field',jsonb_set(f,'{education}',(f->'education')||'{"prompt":"private"}')),
 ('quantity no reference',jsonb_set(jsonb_set(jsonb_set(f,'{registration,items,0,quantity,unit}','"mL"'),'{registration,items,0,quantity,estimated}','true'),'{registration,items,0,quantity,reference_id}','null'));
END $bad$;
DO $reject$
DECLARE r record;code text;
BEGIN
 FOR r IN SELECT * FROM invalid_feedback_cases LOOP
  code:=NULL;
  BEGIN PERFORM private.assert_registration_feedback_v2_shape(r.payload,(r.payload->>'registration_id')::uuid,r.payload#>>'{registration,kind}');
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
  ASSERT left(code,2)='22','v2 bad shape accepted or unrelated error: '||r.label||'/'||coalesce(code,'accepted');
 END LOOP;
END $reject$;
SELECT count(*) AS rejected_shapes FROM invalid_feedback_cases;
ROLLBACK;
