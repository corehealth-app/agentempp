-- Replaces ONLY the upgrade block in explicit postddl_mode. No historical sample PASS is emitted.
-- Expected OIDs and canonical pg_proc hashes are from REAL run-r2/16 metadata, never current capture.
DO $postddl_four$DECLARE e jsonb:=(SELECT value FROM pg_temp.c59s17b_expected_four);f jsonb;p record;old13 jsonb;old8 jsonb;actual_acl jsonb;actual_canonical text;mode text;v boolean:=true;core record;public13 record;BEGIN
 FOR f IN SELECT value FROM jsonb_array_elements(e->'functions')LOOP
 SELECT * INTO STRICT p FROM pg_proc WHERE oid=(f->>'oid')::oid;
 mode:=CASE f->>'oid' WHEN '21704' THEN 'without_source_security_config_md5' WHEN '21796' THEN 'without_source_md5' WHEN '22427' THEN 'without_acl_md5' WHEN '22428' THEN 'without_acl_md5' ELSE NULL END;
 actual_canonical:=CASE mode WHEN 'without_source_security_config_md5' THEN md5((to_jsonb(p)-ARRAY['prosrc','prosecdef','proconfig'])::text)
 WHEN 'without_source_md5' THEN md5((to_jsonb(p)-'prosrc')::text) WHEN 'without_acl_md5' THEN md5((to_jsonb(p)-'proacl')::text) ELSE NULL END;
 SELECT coalesce(jsonb_agg(jsonb_build_array(pg_get_userbyid(a.grantor),CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)END,a.privilege_type,a.is_grantable)ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable),'[]'::jsonb)
 INTO actual_acl FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a;
 v:=v AND mode IS NOT NULL AND f#>>'{canonical,mode}'=mode AND actual_canonical=f#>>'{canonical,md5}'AND actual_canonical=f->>mode
 AND p.oid=(f->>'identity')::regprocedure::oid AND p.oid::text=f->>'oid'
 AND pg_get_userbyid(p.proowner)=f#>>'{expected_after,owner}' AND actual_acl=f#>'{expected_after,acl}'
 AND to_jsonb(p.prosecdef)=f#>'{expected_after,security_definer}' AND to_jsonb(p.proconfig)IS NOT DISTINCT FROM f#>'{expected_after,config}'
 AND md5(p.prosrc)=f#>>'{expected_after,source_md5}'
 AND pg_get_expr(p.proargdefaults,0)IS NOT DISTINCT FROM f#>>'{definition,argument_defaults}' AND p.pronargdefaults=(f#>>'{definition,argument_default_count}')::integer;
 IF f->>'oid' IN('22427','22428')THEN v:=v AND NOT has_function_privilege('service_role',p.oid,'EXECUTE');
 ELSE v:=v AND has_function_privilege('service_role',p.oid,'EXECUTE');END IF;
 IF f->>'oid'='21704'THEN old13:=f;ELSIF f->>'oid'='21796'THEN old8:=f;END IF;
 END LOOP;
 PERFORM c59s17b_fixture.ok(v AND old13 IS NOT NULL AND old8 IS NOT NULL,'old_four_OIDs_defaults_signatures_and_allowed_security_ACL_changes_only');
 SELECT * INTO STRICT core FROM pg_proc WHERE oid='private.register_workout_atomic_core(uuid,date,text,integer,integer,text,text,timestamp with time zone,text,integer,numeric,boolean,timestamp with time zone)'::regprocedure;
 SELECT * INTO STRICT public13 FROM pg_proc WHERE oid=(old13->>'oid')::oid;
 -- REST13 above includes the ORIGINAL raw proargdefaults node; comparison is transitive, no node reconstruction.
 PERFORM c59s17b_fixture.ok(md5(core.prosrc)=old13#>>'{definition,source_md5}' AND md5(core.prosrc)='e982fbe59c4f569e58211e646c1eb8d8'AND octet_length(core.prosrc)=4219
 AND core.proargdefaults::text IS NOT DISTINCT FROM public13.proargdefaults::text AND core.pronargdefaults=public13.pronargdefaults
 AND pg_get_expr(core.proargdefaults,0)IS NOT DISTINCT FROM old13#>>'{definition,argument_defaults}',
 'private13_prosrc_and_defaults_byte_exact_old_writer');
 SELECT * INTO STRICT core FROM pg_proc WHERE oid='private.register_workout_strength_core(uuid,uuid,text,text,jsonb,jsonb)'::regprocedure;
 PERFORM c59s17b_fixture.ok(md5(replace(core.prosrc,'private.register_workout_atomic_core(','public.register_workout_atomic('))=old8#>>'{definition,source_md5}'
 AND md5(replace(core.prosrc,'private.register_workout_atomic_core(','public.register_workout_atomic('))='3f67fcd2854a024357f289569ebb0f11'
 AND octet_length(replace(core.prosrc,'private.register_workout_atomic_core(','public.register_workout_atomic('))=19941
 AND length(core.prosrc)-length(replace(core.prosrc,'private.register_workout_atomic_core(',''))=length('private.register_workout_atomic_core('),
 'privateS8_inverse_only_one_callee_change_recovers_exact_old_body');
END $postddl_four$;
