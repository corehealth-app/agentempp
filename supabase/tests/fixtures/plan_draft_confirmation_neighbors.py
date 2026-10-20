"""Definitions only: real locks, successful clocks, late replay and nutrition.

The caller owns exclusive fixtures and teardown. Only fixture deadlines commit;
the candidate DDL and every confirmation effect stay in B and are rolled back.
"""
def run_confirmation_neighbors(config, actor_api, owned_expression):
    import datetime,json,time
    from pathlib import Path
    need=actor_api['require'];lit=actor_api['literal'];create=actor_api['_create_registered_actor']
    output=Path(config['output_dir']);output.mkdir(mode=0o700,exist_ok=False)
    need(config.get('root_reviewed') is True and config['user']=='c5_local_admin'
        and config['database']=='c5_reset_default_20261009' and config['port']==55489
        and config['socket']=='/private/tmp/performe-c5-osecmg7_'
        and isinstance(config.get('confirmation_overlay_sql'),str),'closed_plan_neighbors_target')
    actors=[];result={'status':'RUNNING','cases':[]};limit=time.monotonic()+90
    owners=['c59d2b00-0000-4000-8000-000000000001','c59d2b00-0000-4000-8000-000000000002']
    def q(actor,sql,label):
        need(time.monotonic()<limit,'bounded_plan_neighbors_deadline')
        return actor.query(sql,label,timeout=min(12,max(.1,limit-time.monotonic())))
    def instant(s):
        return datetime.datetime.strptime(s,'%Y-%m-%dT%H:%M:%S'+('.%f' if '.' in s else '')+'%z')
    def begin(actor):
        actor.begin();actor.statement("SET LOCAL search_path=pg_catalog,public,private,pg_temp;"
            "SET LOCAL request.jwt.claims='{\"role\":\"service_role\"}';")
    def wait_for_expiry(a,until):
        while True:
            clock=q(a,'clock_timestamp()','database_expiry_clock')
            if instant(clock)>instant(until):return clock
            time.sleep(.04)
    try:
        a=create('PLAN-NEIGHBOR-A',config,output,actors)
        b=create('PLAN-NEIGHBOR-B',config,output,actors)
        ids=[]
        for actor in actors:
            identity=q(actor,"jsonb_build_object('pid',pg_backend_pid(),'session',session_user,'db',current_database(),"
                "'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),"
                "'port',current_setting('port')::integer,'listen',current_setting('listen_addresses'))",'identity')
            need(identity['session']==config['user'] and identity['db']==config['database']
                and identity['data']==config['expected_data_directory'] and identity['socket']==config['socket']
                and identity['port']==55489 and identity['listen']=='','native_plan_neighbors_identity')
            ids.append(identity['pid'])
            actor.statement("SET statement_timeout='15s';SET lock_timeout='12s';"
                "SET idle_in_transaction_session_timeout='20s';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        need(ids[0]!=ids[1],'distinct_native_plan_neighbors_backends');result['identities']=ids
        b.statement("CREATE FUNCTION pg_temp.plan_neighbor_confirm(u uuid,d uuid,v integer,x timestamptz,k text) RETURNS jsonb "
            "LANGUAGE plpgsql AS $caught$ DECLARE answer jsonb; BEGIN "
            "BEGIN answer:=public.confirm_plan_draft_atomic(u,d,v,x,k);"
            "RETURN jsonb_build_object('outcome','confirmed','result',answer);"
            "EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('outcome','error','sqlstate',SQLSTATE,'message',SQLERRM);"
            "END; END $caught$;")
        for index,owner in enumerate(owners):
            draft=q(a,"(SELECT id FROM public.plan_drafts WHERE user_id="+lit(owner)+"::uuid)",'real_draft_'+str(index))
            need(isinstance(draft,str),'one_real_neighbor_draft')
            # Overlay and actor startup precede the short deadline, avoiding setup timing flakes.
            begin(b);b.statement(config['confirmation_overlay_sql'])
            begin(a)
            if index==0:
                a.statement("UPDATE public.plan_drafts SET expires_at=clock_timestamp()+interval '6 seconds' WHERE id="+lit(draft)+"::uuid;")
                until=q(a,"(SELECT expires_at FROM public.plan_drafts WHERE id="+lit(draft)+"::uuid)",'draft_deadline')
            else:
                a.statement("UPDATE public.prescriptions SET valid_until=clock_timestamp()+interval '4 seconds' WHERE user_id="
                    +lit(owner)+"::uuid AND generated_by='professional';")
                until=q(a,"(SELECT valid_until FROM public.prescriptions WHERE user_id="+lit(owner)+"::uuid)",'professional_deadline')
            a.finish(True)
            before=q(a,owned_expression,'before_wait_'+str(index))
            if index==1:
                professional=next(t for t in before['prescriptions'] if t['user_id']==owner)
                prepared=next(t for t in before['drafts'] if t['id']==draft)
                need(professional['generated_by']=='professional'
                    and instant(professional['valid_until'])==instant(until)
                    and prepared['base_latest_prescription_id']==professional['id']
                    and prepared['domain']=='nutrition' and prepared['status']=='ready_for_review'
                    and instant(prepared['expires_at'])>instant(until),'exact_professional_base_and_deadline')
            begin(a)
            need(q(a,"(SELECT id FROM public.users WHERE id="+lit(owner)+"::uuid FOR UPDATE)",'owner_lock')==owner,'exact_neighbor_owner_lock')
            ticket=b.send('pg_temp.plan_neighbor_confirm('+lit(owner)+'::uuid,'+lit(draft)+'::uuid,1,NULL,'
                +lit('plan-neighbor-confirm-'+str(index))+')','waited_confirmation_'+str(index))
            blocked=None
            while time.monotonic()<limit:
                a.statement('RESET ROLE;SELECT pg_stat_clear_snapshot();')
                diag=q(a,"jsonb_build_object('clock',clock_timestamp(),'blockers',pg_blocking_pids("+str(ids[1])+"),"
                    "'blocker_xid',(SELECT backend_xid::text FROM pg_stat_activity WHERE pid="+str(ids[0])+"),"
                    "'wait',(SELECT jsonb_build_object('state',state,'type',wait_event_type,'app',application_name)"
                    " FROM pg_stat_activity WHERE pid="+str(ids[1])+"),"
                    "'xids',(SELECT coalesce(jsonb_agg(transactionid::text),'[]'::jsonb) FROM pg_locks WHERE pid="
                    +str(ids[1])+" AND NOT granted AND locktype='transactionid'))",'actual_neighbor_block')
                if ids[0] in diag['blockers']:
                    need(diag['wait']=={'state':'active','type':'Lock','app':'c59s7-PLAN-NEIGHBOR-B'}
                        and diag['blocker_xid'] in diag['xids'] and instant(diag['clock'])<instant(until),
                        'real_neighbor_block_before_expiry')
                    blocked=diag;break
                need(instant(diag['clock'])<instant(until),'neighbor_deadline_crossed_before_block')
                time.sleep(.02)
            need(blocked is not None,'native_neighbor_block_observed')
            if index==0:
                lower=q(a,'clock_timestamp()','positive_release_lower')
                need((instant(until)-instant(lower)).total_seconds()>2,'positive_timing_margin_not_available')
            else:
                lower=wait_for_expiry(a,until)
            a.finish(True)
            wire=b.receive(ticket,timeout=12)
            case={'name':'training_success_and_late_replay' if index==0 else 'professional_expires_during_wait',
                'owner':owner,'draft':draft,'deadline':until,'block':blocked,'release_lower':lower,'actual':wire}
            result['cases'].append(case)
            need(wire.get('outcome')=='confirmed' and wire['result'].get('status')=='confirmed'
                and wire['result'].get('already_confirmed') is False,'neighbor_confirmation_must_succeed')
            after_clock=q(b,'clock_timestamp()','after_confirmation_clock')
            persisted=q(b,owned_expression,'successful_confirmation_state')
            row=next(t for t in persisted['drafts'] if t['id']==draft)
            plan_id=wire['result']['confirmed_plan_id']
            table='plans' if index==0 else 'prescriptions'
            plan=next(t for t in persisted[table] if t['id']==plan_id)
            need(row['status']=='confirmed' and row['confirmed_plan_id']==plan_id
                and row['user_id']==owner and plan['user_id']==owner
                and instant(lower)<=instant(row['resolved_at'])<=instant(after_clock)
                and instant(lower)<=instant(plan['generated_at'])<=instant(after_clock) and plan['valid_until'] is None,
                'successful_clocks_must_follow_observed_wait')
            if index==0:
                need(instant(after_clock)<instant(until) and plan['active'] is True
                    and len(persisted['plans'])==1,'positive_confirmation_before_expiry')
                expired_clock=wait_for_expiry(a,until)
                replay=q(b,'pg_temp.plan_neighbor_confirm('+lit(owner)+'::uuid,'+lit(draft)
                    +'::uuid,9,clock_timestamp()+interval \'42 days\','+lit('plan-neighbor-new-replay-key')+')','replay_after_expiry')
                expected=dict(wire['result']);expected['already_confirmed']=True
                need(replay=={'outcome':'confirmed','result':expected},'late_replay_returns_original_dto')
                need(q(b,owned_expression,'late_replay_raw_state')==persisted,'late_replay_never_renews_or_mutates')
                case.update(replay=replay,replay_clock=expired_clock,raw_replay_unchanged=True)
            else:
                original=next(t for t in before['prescriptions'] if t['user_id']==owner)
                need(instant(after_clock)>instant(lower)>instant(until)
                    and len(persisted['prescriptions'])==2 and not persisted['plans']
                    and next(t for t in persisted['prescriptions'] if t['id']==original['id'])==original
                    and plan['generated_by']=='flow_draft','expired_professional_preserved_with_one_new_prescription')
                case['professional_row_unchanged']=True
            b.finish(False)
            need(q(a,owned_expression,'neighbor_rollback_later_state')==before,'neighbor_rollback_restores_exact_state')
            case.update(clock_after=after_clock,requirement_passed=True,waiter_rollback_verified=True)
        result['retained_owned_state']=q(a,owned_expression,'retained_state_for_teardown')
        result['status']='REQUIREMENTS_PASS'
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
            'readers_stopped':all(v['readers_stopped'] for v in closed),'exit_codes_zero':all(v.get('exit_code')==0 for v in closed)}
        (output/'RESULT.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    need(result['cleanup']['actors_reaped'] and result['cleanup']['readers_stopped']
        and result['cleanup']['exit_codes_zero'],'all_neighbor_actors_closed')
    return result
