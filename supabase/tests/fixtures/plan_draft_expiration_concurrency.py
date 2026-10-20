"""Definitions only; real confirmation, two bounded row-lock waits, no provider.
The independent oracle requires PD410 and 22023 after expiry; collecting a real
confirmation instead records a failing requirement. The lifecycle caller owns
setup/teardown and may classify exactly those two failures as a causal RED.
"""
def run_expiration_cases(config, actor_api, owned_expression):
    import datetime,json,time
    from pathlib import Path
    need=actor_api['require'];lit=actor_api['literal'];create=actor_api['_create_registered_actor']
    output=Path(config['output_dir']);output.mkdir(mode=0o700,exist_ok=False)
    need(config.get('root_reviewed') is True and config['user']=='c5_local_admin'
        and config['database']=='c5_reset_default_20261009' and config['port']==55489
        and config['socket']=='/private/tmp/performe-c5-osecmg7_','closed_plan_ttl_target')
    actors=[];result={'status':'RUNNING','cases':[]};limit=time.monotonic()+60
    owners=['c59d2700-0000-4000-8000-000000000001','c59d2700-0000-4000-8000-000000000002']
    def q(actor,sql,label):
        need(time.monotonic()<limit,'bounded_plan_ttl_deadline')
        return actor.query(sql,label,timeout=min(12,max(.1,limit-time.monotonic())))
    def instant(s):
        # PostgreSQL JSON trims trailing zeroes; macOS Python3.9 fromisoformat
        # rejects five fractional digits. strptime accepts the actual 0-6 digits.
        return datetime.datetime.strptime(s,'%Y-%m-%dT%H:%M:%S'+('.%f' if '.' in s else '')+'%z')
    def begin(actor):
        actor.begin();actor.statement("SET LOCAL ROLE postgres;SET LOCAL search_path=pg_catalog;"
            "SET LOCAL request.jwt.claims='{\"role\":\"service_role\"}';")
    try:
        a=create('PLAN-TTL-A',config,output,actors);b=create('PLAN-TTL-B',config,output,actors)
        ids=[]
        for actor in actors:
            identity=q(actor,"jsonb_build_object('pid',pg_backend_pid(),'session',session_user,'db',current_database(),"
                "'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),"
                "'port',current_setting('port')::integer,'listen',current_setting('listen_addresses'))",'identity')
            need(identity['session']==config['user'] and identity['db']==config['database']
                and identity['data']==config['expected_data_directory'] and identity['socket']==config['socket']
                and identity['port']==55489 and identity['listen']=='','native_plan_ttl_identity')
            ids.append(identity['pid'])
            actor.statement("SET statement_timeout='15s';SET lock_timeout='12s';"
                "SET idle_in_transaction_session_timeout='20s';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        need(ids[0]!=ids[1],'distinct_native_plan_ttl_backends');result['identities']=ids
        # Only a temporary exception adapter; the product RPC and tables are unmodified.
        b.statement("CREATE FUNCTION pg_temp.plan_ttl_confirm(u uuid,d uuid,v timestamptz,k text) RETURNS jsonb "
            "LANGUAGE plpgsql AS $caught$ DECLARE answer jsonb; BEGIN "
            "BEGIN answer:=public.confirm_plan_draft_atomic(u,d,1,v,k);"
            "RETURN jsonb_build_object('outcome','confirmed','result',answer);"
            "EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('outcome','error','sqlstate',SQLSTATE,'message',SQLERRM);"
            "END; END $caught$;")
        for index,owner in enumerate(owners):
            draft=q(a,"(SELECT id FROM public.plan_drafts WHERE user_id="+lit(owner)+"::uuid)",'draft_'+str(index))
            need(isinstance(draft,str),'one_real_created_draft')
            if index==0:
                # Commit the prepared deadline BEFORE B starts; never change it while B waits.
                begin(a);a.statement("UPDATE public.plan_drafts SET expires_at=clock_timestamp()+interval '4 seconds' "
                    "WHERE id="+lit(draft)+"::uuid;")
                until=q(a,"(SELECT expires_at FROM public.plan_drafts WHERE id="+lit(draft)+"::uuid)",'prepared_draft_deadline')
                a.finish(True)
            else:
                until=q(a,"clock_timestamp()+interval '4 seconds'",'prepared_plan_deadline')
            before=q(a,owned_expression,'before_wait_'+str(index))
            begin(a);locked=q(a,"(SELECT id FROM public.users WHERE id="+lit(owner)+"::uuid FOR UPDATE)",'owner_lock')
            need(locked==owner,'exact_owner_row_lock')
            begin(b)
            # The temporary adapter belongs to this local session. The real
            # SECURITY DEFINER RPC still executes as postgres and validates claims.
            b.statement('RESET ROLE;')
            if config.get('confirmation_overlay_sql') is not None:
                b.statement(config['confirmation_overlay_sql'])
            valid='NULL' if index==0 else lit(until)+'::timestamptz'
            ticket=b.send('pg_temp.plan_ttl_confirm('+lit(owner)+'::uuid,'+lit(draft)+'::uuid,'+valid+','
                +lit('plan-ttl-confirm-'+str(index))+')','waited_confirmation_'+str(index))
            blocked=None
            while time.monotonic()<limit:
                a.statement('RESET ROLE;SELECT pg_stat_clear_snapshot();')
                diag=q(a,"jsonb_build_object('clock',clock_timestamp(),'blockers',pg_blocking_pids("+str(ids[1])+"),"
                    "'blocker_xid',(SELECT backend_xid::text FROM pg_stat_activity WHERE pid="+str(ids[0])+"),"
                    "'wait',(SELECT jsonb_build_object('state',state,'type',wait_event_type,'app',application_name)"
                    " FROM pg_stat_activity WHERE pid="+str(ids[1])+"),"
                    "'xids',(SELECT coalesce(jsonb_agg(transactionid::text),'[]'::jsonb) FROM pg_locks "
                    "WHERE pid="+str(ids[1])+" AND NOT granted AND locktype='transactionid'))",'actual_plan_ttl_block')
                if ids[0] in diag['blockers']:
                    need(diag['wait']=={'state':'active','type':'Lock','app':'c59s7-PLAN-TTL-B'}
                        and diag['blocker_xid'] in diag['xids'] and instant(diag['clock'])<instant(until),
                        'real_owner_block_before_expiry')
                    blocked=diag;break
                need(instant(diag['clock'])<instant(until),'deadline_crossed_before_observed_block')
                time.sleep(.02)
            need(blocked is not None,'native_block_observed')
            while True:
                release=q(a,'clock_timestamp()','release_clock')
                if instant(release)>instant(until):break
                time.sleep(.04)
            a.finish(True)
            wire=b.receive(ticket,timeout=12)
            after_clock=q(b,'clock_timestamp()','clock_after_real_confirmation')
            need(instant(after_clock)>instant(release)>instant(until),'database_time_passed_deadline')
            expected={'outcome':'error','sqlstate':'PD410' if index==0 else '22023',
                'message':'plan_draft_expired' if index==0 else 'invalid plan draft confirmation'}
            passed=wire==expected
            if passed:
                need(q(b,owned_expression,'failed_confirmation_later_state')==before,'expiry_has_no_side_effects')
            else:
                need(wire.get('outcome')=='confirmed' and wire['result'].get('status')=='confirmed'
                    and wire['result'].get('already_confirmed') is False,'causal_failure_is_real_confirmation')
                plan_id=wire['result']['confirmed_plan_id']
                persisted=q(b,"jsonb_build_object('draft',(SELECT to_jsonb(t) FROM public.plan_drafts t WHERE id="
                    +lit(draft)+"::uuid),'plans',(SELECT jsonb_agg(to_jsonb(t)) FROM public.training_plans t "
                    "WHERE user_id="+lit(owner)+"::uuid))",'real_confirmation_effect')
                need(persisted['draft']['confirmed_plan_id']==plan_id and persisted['draft']['status']=='confirmed'
                    and len(persisted['plans'])==1 and persisted['plans'][0]['id']==plan_id
                    and persisted['plans'][0]['active'] is True,'real_plan_and_terminal_draft_after_wait')
            b.finish(False)
            need(q(a,owned_expression,'rollback_later_state')==before,'waiter_rollback_restores_exact_owner_state')
            result['cases'].append({'name':'draft_expires_during_wait' if index==0 else 'plan_validity_expires_during_wait',
                'owner':owner,'draft':draft,'deadline':until,'block':blocked,'release_lower':release,
                'clock_after':after_clock,'expected':expected,'actual':wire,'requirement_passed':passed,
                'waiter_rollback_verified':True})
        result['retained_owned_state']=q(a,owned_expression,'retained_owned_state_for_teardown')
        result['failed_requirements']=sum(not c['requirement_passed'] for c in result['cases'])
        result['status']='REQUIREMENTS_PASS' if result['failed_requirements']==0 else 'REQUIREMENTS_FAIL_CAUSAL'
    except BaseException as exc:
        result['status']='SETUP_OR_EXECUTION_FAILURE'
        result['failure']={'type':type(exc).__name__,'label':str(exc) if isinstance(exc,(RuntimeError,TimeoutError)) else None}
        raise
    finally:
        closed=[]
        for actor in actors:
            try:closed.append(actor.close())
            except BaseException as exc:closed.append({'actor':actor.name,'error':type(exc).__name__,'reaped':False,'readers_stopped':False})
        result['cleanup']={'actors':closed,'actors_reaped':all(v['reaped'] for v in closed),
            'readers_stopped':all(v['readers_stopped'] for v in closed),
            'exit_codes_zero':all(v.get('exit_code')==0 for v in closed)}
        (output/'RESULT.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    need(result['cleanup']['actors_reaped'] and result['cleanup']['readers_stopped']
        and result['cleanup']['exit_codes_zero'],'all_plan_ttl_actors_closed')
    return result
