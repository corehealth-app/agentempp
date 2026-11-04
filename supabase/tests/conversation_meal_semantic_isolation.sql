BEGIN ISOLATION LEVEL REPEATABLE READ;
\ir fixtures/conversation_meal_semantic_fixture.sql
CREATE FUNCTION pg_temp.semantic_isolation() RETURNS void LANGUAGE plpgsql AS $$
DECLARE statement text;code text;id text:='c3a40000-0000-4000-8000-000000000099';version text:='conversation.meal-interpreter.v1';
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH statement IN ARRAY ARRAY[format('SELECT public.start_conversation_meal_semantic_attempt(%L,%L,%L,NULL)',id,id,version),format('SELECT public.read_conversation_meal_semantic_attempt(%L,%L,%L)',id,id,version),
  format('SELECT public.commit_conversation_meal_semantic_result(%L,%L,%L,%L,NULL)',id,id,version,id),format('SELECT public.mark_conversation_meal_semantic_unknown(%L,%L,%L,%L,NULL)',id,id,version,id),format('SELECT public.read_conversation_meal_prepared(%L,%L)',id,id)] LOOP
  code:=NULL;BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
  PERFORM pg_temp.writer_ok(code='22023',current_setting('transaction_isolation')||' refuses semantic/recovery '||statement);END LOOP;
END $$;
SELECT pg_temp.semantic_isolation();SELECT count(*) AS semantic_isolation_assertions FROM meal_writer_assertions;
COMMIT;
BEGIN ISOLATION LEVEL SERIALIZABLE;
CREATE TEMP TABLE meal_writer_assertions(label text PRIMARY KEY) ON COMMIT DROP;
SELECT pg_temp.semantic_isolation();SELECT count(*) AS semantic_isolation_assertions FROM meal_writer_assertions;
ROLLBACK;
