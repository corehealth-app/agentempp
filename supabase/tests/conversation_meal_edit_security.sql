BEGIN;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $access$
DECLARE signature text;table_name text;did_fail boolean;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
 'public.read_conversation_meal_edit_state(uuid,uuid)',
 'public.read_conversation_meal_edit_operation(uuid,uuid,uuid,jsonb)',
 'public.commit_conversation_meal_item_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text)',
 'public.undo_conversation_meal_item_edit(uuid,uuid,uuid,jsonb,jsonb,text)',
 'public.undo_conversation_meal_registration(uuid,uuid,uuid,jsonb,jsonb,text)'] LOOP
  IF has_function_privilege('anon',signature,'EXECUTE') OR has_function_privilege('authenticated',signature,'EXECUTE') OR NOT has_function_privilege('service_role',signature,'EXECUTE') THEN RAISE EXCEPTION 'edit_acl_failed:%',signature;END IF;
 END LOOP;
 FOREACH table_name IN ARRAY ARRAY['conversation_meal_edit_ids','conversation_meal_edit_operations','conversation_meal_edit_heads'] LOOP
  IF NOT(SELECT relrowsecurity FROM pg_class WHERE oid=('private.'||table_name)::regclass) OR
   has_table_privilege('service_role','private.'||table_name,'SELECT,INSERT,UPDATE,DELETE') OR
   has_table_privilege('authenticated','private.'||table_name,'SELECT,INSERT,UPDATE,DELETE') OR
   has_table_privilege('anon','private.'||table_name,'SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'edit_rls_grants_failed:%',table_name;END IF;
 END LOOP;
 IF has_function_privilege('service_role','private.apply_conversation_meal_edit(uuid,uuid,uuid,jsonb,jsonb,jsonb,text,jsonb,text,text)','EXECUTE') OR
  has_function_privilege('service_role','private.conversation_meal_edit_state(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'private_edit_helper_exposed';END IF;
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);did_fail:=false;
 BEGIN PERFORM public.undo_conversation_meal_registration(NULL,NULL,NULL,NULL,NULL,NULL);EXCEPTION WHEN insufficient_privilege THEN did_fail:=true;END;
 IF NOT did_fail THEN RAISE EXCEPTION 'edit_untrusted_jwt_accepted';END IF;
 RAISE NOTICE 'EDIT_SECURITY_PASS:ACL_RLS_private_helpers_untrusted_JWT';
END $access$;
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.read_conversation_meal_edit_state('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003'); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='invalid_conversation_meal_edit_read';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:read_conversation_meal_edit_state';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:REPEATABLE READ:read_conversation_meal_edit_state';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.read_conversation_meal_edit_operation('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003','c3ec0000-0000-4000-8000-000000000004',NULL); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='invalid_conversation_meal_edit_read';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:read_conversation_meal_edit_operation';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:REPEATABLE READ:read_conversation_meal_edit_operation';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.commit_conversation_meal_item_edit('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003','c3ec0000-0000-4000-8000-000000000004',NULL,NULL,NULL,NULL,NULL,NULL); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_command_requires_read_committed';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:commit_conversation_meal_item_edit';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:REPEATABLE READ:commit_conversation_meal_item_edit';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.undo_conversation_meal_item_edit('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003','c3ec0000-0000-4000-8000-000000000004',NULL,NULL,NULL); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_command_requires_read_committed';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:undo_conversation_meal_item_edit';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:REPEATABLE READ:undo_conversation_meal_item_edit';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.undo_conversation_meal_registration('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003','c3ec0000-0000-4000-8000-000000000004',NULL,NULL,NULL); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_command_requires_read_committed';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:undo_conversation_meal_registration';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:REPEATABLE READ:undo_conversation_meal_registration';END $$;
ROLLBACK;

BEGIN ISOLATION LEVEL SERIALIZABLE;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.read_conversation_meal_edit_state('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003'); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='invalid_conversation_meal_edit_read';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:read_conversation_meal_edit_state';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:SERIALIZABLE:read_conversation_meal_edit_state';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.read_conversation_meal_edit_operation('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003','c3ec0000-0000-4000-8000-000000000004',NULL); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='invalid_conversation_meal_edit_read';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:read_conversation_meal_edit_operation';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:SERIALIZABLE:read_conversation_meal_edit_operation';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.commit_conversation_meal_item_edit('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003','c3ec0000-0000-4000-8000-000000000004',NULL,NULL,NULL,NULL,NULL,NULL); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_command_requires_read_committed';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:commit_conversation_meal_item_edit';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:SERIALIZABLE:commit_conversation_meal_item_edit';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.undo_conversation_meal_item_edit('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003','c3ec0000-0000-4000-8000-000000000004',NULL,NULL,NULL); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_command_requires_read_committed';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:undo_conversation_meal_item_edit';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:SERIALIZABLE:undo_conversation_meal_item_edit';END $$;
DO $$ DECLARE refused boolean:=false;BEGIN BEGIN PERFORM public.undo_conversation_meal_registration('c3ec0000-0000-4000-8000-000000000001','c3ec0000-0000-4000-8000-000000000003','c3ec0000-0000-4000-8000-000000000004',NULL,NULL,NULL); EXCEPTION WHEN invalid_parameter_value THEN refused:=SQLERRM='conversation_command_requires_read_committed';END;IF NOT refused THEN RAISE EXCEPTION 'edit_isolation_failed:undo_conversation_meal_registration';END IF; RAISE NOTICE 'EDIT_SECURITY_PASS:SERIALIZABLE:undo_conversation_meal_registration';END $$;
ROLLBACK;
