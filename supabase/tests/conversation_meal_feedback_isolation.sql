BEGIN ISOLATION LEVEL REPEATABLE READ;
\ir fixtures/conversation_meal_feedback_fixture.sql
DO $isolation$
DECLARE statement text;code text;id text:='c3f00000-0000-4000-8000-000000000099';
BEGIN
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
 FOREACH statement IN ARRAY ARRAY[
  format('SELECT public.read_conversation_meal_feedback_source(%L,%L)',id,id),
  format('SELECT public.read_conversation_meal_feedback_v2(%L,%L)',id,id),
  format('SELECT public.commit_conversation_meal_feedback_v2(%L,%L,NULL,NULL)',id,id)] LOOP
  code:=NULL;BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE;END;
  PERFORM pg_temp.writer_ok(code='22023','READ COMMITTED required '||statement);
 END LOOP;
END $isolation$;
SELECT count(*) AS conversation_feedback_isolation_assertions FROM meal_writer_assertions;
ROLLBACK;
