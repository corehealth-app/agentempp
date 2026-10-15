#!/usr/bin/env python3
"""S14 real C5 reset/capture/answer/delete races; import inert, no PG lifecycle/DDL.
Root calls run(config) only after source review and owned setup commit.
The immutable S7 Actor is loaded only at run time, never its run/main.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import types

ACTOR_SHA='c14570d9059fbd56f4aa7efeeefeb9e0030b275c9b221a0890d1d484d1db1a5f'
CASE_IDS=['reset-capture-commit','reset-capture-rollback','capture-reset-commit','capture-reset-rollback',
    'reset-answer-commit','reset-answer-rollback','answer-reset-commit','answer-reset-rollback',
    'delete-capture-commit','delete-capture-rollback','capture-delete-commit','capture-delete-rollback','no-life-reset-advisory']
X='private.workout_strength_'
NEG={'status':'forbidden','reason':'stale_lifecycle'}
CAPTURE_NEG={'legacy_result':None,'strength':NEG}


def require(value,label):
    if value is not True:
        raise RuntimeError('C59S14_DRIVER:'+label)


def lit(value):
    return "'"+str(value).replace("'","''")+"'"


def reset(owner):
    return 'public.reset_user_conversation_atomic('+lit(owner)+'::uuid,true)'


def capture(p):
    return 'c59s14_fixture.capture('+','.join(lit(p[k]) for k in ['ownerID','lifecycleKey','pendingKey','pendingRaw'])+')'


def answer(p):
    return 'c59s14_fixture.answer('+lit(json.dumps(p))+'::jsonb)'


def attempt(expression):
    return 'c59s14_fixture.attempt('+lit('SELECT '+expression)+')'


def wait_block(observer,blocker,waiter,deadline):
    limit=min(deadline,time.monotonic()+6)
    while time.monotonic()<limit:
        observer.statement('SELECT pg_stat_clear_snapshot();')
        if observer.query(str(blocker)+'=ANY(pg_blocking_pids('+str(waiter)+'))','actual_blocker') is True:
            return
    raise TimeoutError('C59S14_DRIVER:no_actual_blocker')


def check_capture(r,p):
    require(isinstance(r,dict) and set(r)=={'legacy_result','strength'},'actual_capture_envelope')
    require(isinstance(r['legacy_result'],dict) and r['legacy_result']['inserted'] is True,'legacy_writer_inserted')
    strength=r['strength']
    require(strength['status']=='committed' and strength['binding']['ownerID']==p['ownerID']
        and strength['binding']['lifecycleKey']==p['lifecycleKey'] and strength['binding']['operationKey']==p['pendingKey']
        and strength['binding']['originalOperationType']==p['pendingRaw']
        and strength['binding']['workoutLogID']==r['legacy_result']['workout_log_id']
        and strength['fact']['anchor']['workoutLogID']==strength['binding']['workoutLogID']
        and strength['fact']['classification']['status']=='unrecognized' and strength['fact']['revision']==0,'real_new_owned_capture_fact')
    return strength['binding']['workoutLogID']


def check_answer(r,p):
    require(isinstance(r,dict) and set(r)=={'status','receipt'} and r['status']=='accepted','actual_S9_answer_accepted')
    receipt=r['receipt']
    require(set(receipt)=={'ownerID','workoutLogID','questionKey','answer','operationKey','acceptedAt'}
        and all(receipt[k]==p[v] for k,v in [('ownerID','ownerID'),('workoutLogID','workoutLogID'),('questionKey','questionKey'),('operationKey','answerKey')])
        and receipt['answer']=='yes' and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z',receipt['acceptedAt']) is not None,'actual_S9_owned_receipt')


def reset_state(before,after,p):
    require(after['user']['id']==p['ownerID'] and after['user']['wpp']==before['user']['wpp']
        and after['user']['flow_phrase_cursor_revision']==0,'reset_keeps_identity_and_resets_cursor')
    life=after[X+'lifecycles']
    require(len(life)==1 and life[0]['closed_at'] is not None
        and re.fullmatch(r'reset_user_conversation:[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',life[0]['close_operation_key']) is not None
        and life[0]['opened_at']==before[X+'lifecycles'][0]['opened_at'],'actual_lifecycle_closed')
    require(after['workout_logs']==[] and after['daily_snapshots']==[] and after[X+'facts']==[],'no_late_workout_fact_partial_snapshot')
    require(after[X+'commands']==before[X+'commands'] and after[X+'calendar_scopes']==before[X+'calendar_scopes'],'closed_commands_scopes_preserved')
    tombstones=[dict(row,live_workout_log_id=None) for row in before[X+'operations']]
    stable=lambda row:(row['operation_kind'],row['operation_key'],row['original_operation_type'] or '')
    require(sorted(after[X+'operations'],key=stable)==sorted(tombstones,key=stable),'exact_original_UUID_keys_receipts_tombstones')


def run(config):
    output=Path(config['output_dir']);output.mkdir(parents=True,exist_ok=False)
    result={'executed':False,'failure':None,'cases':[],
        'cleanup':{'complete':False,'actors_reaped':False,'readers_stopped':False,'actors':[]}}
    actors=[];deadline=time.monotonic()+240
    def query(actor,expression,label):
        require(time.monotonic()<deadline,'bounded_deadline')
        return actor.query(expression,label)
    def state(actor,owner,label):
        return query(actor,'c59s14_fixture.state('+lit(owner)+'::uuid)',label)
    try:
        require(config.get('root_reviewed') is True,'root_review_required')
        path=Path(config['driver_path']).resolve(strict=True)
        require(hashlib.sha256(path.read_bytes()).hexdigest()==config['driver_sha256'],'driver_pin')
        actor_path=Path(config['actor_module']).resolve(strict=True);source=actor_path.read_bytes()
        require(actor_path==path.parent/'workout_strength_commands_concurrency.py'
            and config.get('actor_sha256')==ACTOR_SHA and hashlib.sha256(source).hexdigest()==ACTOR_SHA,'actor_pin_relative_path')
        require(config.get('user')=='c5_local_admin' and config.get('database')=='c5_reset_default_20261009'
            and config.get('port')==55489 and config.get('socket')=='/private/tmp/performe-c5-osecmg7_'
            and config.get('expected_data_directory')=='/Users/eduardohenrique/.local/share/performe-ai/final-polish-20261001/e3/c5-portable-postgres17-20261009/data','exact_owned_C5')
        require(Path(config['psql']).is_absolute() and hashlib.sha256(Path(config['psql']).read_bytes()).hexdigest()==config['psql_sha256'],'psql_pin')
        require(config.get('expected_case_ids')==CASE_IDS,'ordered_case_pin')
        base=types.ModuleType('c59s14_frozen_actor');exec(compile(source,str(actor_path),'exec'),base.__dict__)
        a=base._create_registered_actor('A',config,output,actors);b=base._create_registered_actor('B',config,output,actors)
        pids=[]
        for actor in actors:
            identity=query(actor,"jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'pid',pg_backend_pid(),'tag',(SELECT tag FROM c59s14_fixture.ownership))",'identity')
            require(identity['owner']==config['user'] and identity['db']==config['database'] and identity['port']==config['port']
                and identity['data']==config['expected_data_directory'] and identity['socket']==config['socket']
                and identity['listen']=='' and identity['tag']=='c59s14_reset_v1','actual_local_identity')
            pids.append(identity['pid'])
            actor.statement("SET statement_timeout='12s';SET lock_timeout='9s';SET request.jwt.claims='{\"role\":\"service_role\"}';SET TimeZone='UTC';SET DateStyle='ISO,YMD';")
        require(pids[0]!=pids[1],'distinct_AB')
        sentinel='c59ae000-0000-0000-0000-000000000201'
        sentinel_state=state(a,sentinel,'initial_other_owner')
        require(sentinel_state==query(a,'(SELECT sentinel FROM c59s14_fixture.ownership)','stored_other_owner'),'real_setup_sentinel')
        result['executed']=True
        for index,case in enumerate(CASE_IDS):
            p=query(a,'(SELECT payload FROM c59s14_fixture.cases WHERE case_id='+lit(case)+')','case_real_seed')
            owner=p['ownerID'];require(owner=='c59ae000-0000-0000-0000-'+str(index+11).zfill(12)
                and p['lifecycleKey']=='c59ae000-0000-0000-0000-'+str(index+1011).zfill(12),'fixture_owned_case_ids')
            before=state(a,owner,'before_case');a.begin()
            if index==12:
                require(before[X+'lifecycles']==[] and before['workout_logs']==[],'no_life_initial')
                a.statement('SELECT pg_advisory_xact_lock(hashtextextended('+lit(owner+':workouts')+',0));')
                b.begin();pending=b.send(reset(owner),'reset_without_life_waits_advisory_only')
                wait_block(a,pids[0],pids[1],deadline)
                a.statement('SELECT pg_stat_clear_snapshot();')
                require(query(a,"(SELECT wait_event_type='Lock' AND wait_event='advisory' FROM pg_stat_activity WHERE pid="+str(pids[1])+") AND EXISTS(SELECT 1 FROM pg_locks WHERE pid="+str(pids[1])+" AND locktype='advisory' AND NOT granted) AND NOT EXISTS(SELECT 1 FROM pg_locks WHERE pid="+str(pids[0])+" AND locktype='tuple') AND NOT EXISTS(SELECT 1 FROM pg_locks WHERE pid="+str(pids[0])+" AND relation IN('public.users'::regclass,'private.workout_strength_lifecycles'::regclass) AND mode<>'AccessShareLock' AND granted)",'actual_no_life_advisory_wait_no_A_tuple_lock') is True,'unconditional_advisory_wait_proved')
                a.finish(True)
                r=b.receive(pending);require(r=={'reset':True,'user_id':owner,'deleted_rows':0,'kept_plans':True},'no_life_real_reset_result')
                b.finish(True);after=state(a,owner,'after_no_life')
                require(after[X+'lifecycles']==[],'no_automatic_lifecycle_open')
            else:
                reset_first=index in [0,1,4,5]
                writer_first=index in [2,3,6,7,10,11]
                delete_first=index in [8,9]
                answer_case=4<=index<=7
                commit=index%2==0
                writer=answer(p) if answer_case else capture(p)
                if reset_first:
                    first=query(a,reset(owner),'real_reset_A')
                    require(first['reset'] is True,'actual_reset_before_wait')
                    b.begin();pending=b.send(attempt(writer),'real_writer_B_after_reset')
                    wait_block(a,pids[0],pids[1],deadline);a.finish(commit)
                    outcome=b.receive(pending);require(outcome.get('ok') is True,'writer_returns_union_not_hidden_error')
                    r=outcome['result']
                    if commit:
                        require(r==(NEG if answer_case else CAPTURE_NEG),'closed_life_before_old_replay_no_fallback')
                    elif answer_case:
                        check_answer(r,p)
                    else:
                        new_id=check_capture(r,p)
                    b.finish(True);after=state(a,owner,'durable_reset_first')
                    if commit:
                        reset_state(before,after,p)
                    else:
                        require(after[X+'lifecycles']==before[X+'lifecycles'],'reset_rollback_keeps_open_generation')
                        if answer_case:
                            require(len(after[X+'operations'])==len(before[X+'operations'])+1
                                and after[X+'facts'][0]['answer']=='yes' and after[X+'facts'][0]['revision']==1,'answer_commits_after_reset_rollback')
                        else:
                            require(len(after['workout_logs'])==len(before['workout_logs'])+1 and any(w['id']==new_id for w in after['workout_logs'])
                                and after['daily_snapshots'][0]['exercise_calories']==600 and after['daily_snapshots'][0]['training_done'] is True,'capture_after_rollback_real_totals')
                elif delete_first:
                    require(query(a,'c59s14_fixture.delete_owner('+lit(owner)+'::uuid)','real_DELETE_A')=={'deleted':True},'actual_DELETE_before_wait')
                    b.begin();pending=b.send(attempt(writer),'real_capture_B_waits_owner_delete')
                    wait_block(a,pids[0],pids[1],deadline);a.finish(commit);outcome=b.receive(pending)
                    if commit:
                        require(outcome=={'ok':False,'sqlstate':'P0002'},'deleted_owner_denies_actual_capture')
                    else:
                        require(outcome.get('ok') is True,'owner_restored_capture_no_error');new_id=check_capture(outcome['result'],p)
                    b.finish(True);after=state(a,owner,'durable_delete_first')
                    if commit:
                        require(after['user'] is None and all(value==[] for key,value in after.items() if key!='user'),'actual_owner_cascade_all_families')
                    else:
                        require(after['user']['id']==owner and after[X+'lifecycles']==before[X+'lifecycles']
                            and len(after['workout_logs'])==len(before['workout_logs'])+1 and any(w['id']==new_id for w in after['workout_logs'])
                            and after['daily_snapshots'][0]['exercise_calories']==600,'delete_rollback_restores_real_writer_and_snapshots')
                elif writer_first:
                    first=query(a,writer,'actual_writer_A')
                    if answer_case:
                        check_answer(first,p)
                    else:
                        new_id=check_capture(first,p)
                    before_final=state(a,owner,'actual_A_effects_before_wait') if commit else before
                    b.begin();pending=b.send(('c59s14_fixture.delete_owner('+lit(owner)+'::uuid)') if index>=10 else reset(owner),'real_reset_or_DELETE_B')
                    wait_block(a,pids[0],pids[1],deadline)
                    lower=query(a,"to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')",'DB_clock_after_observed_wait') if index<8 else None
                    a.finish(commit);r=b.receive(pending);b.finish(True)
                    after=state(a,owner,'durable_writer_first')
                    if index>=10:
                        require(r=={'deleted':True} and after['user'] is None and all(v==[] for k,v in after.items() if k!='user'),'writer_then_real_DELETE_cascades_no_partial')
                    else:
                        require(r['reset'] is True,'real_reset_completed_after_writer')
                        reset_state(before_final,after,p)
                        require(query(a,'(SELECT closed_at>='+lit(lower)+'::timestamptz FROM private.workout_strength_lifecycles WHERE user_id='+lit(owner)+'::uuid)','actual_post_lock_closure_clock') is True,'closure_clock_sampled_after_wait')
                else:
                    raise RuntimeError('C59S14_DRIVER:unreachable_case')
            require(state(a,sentinel,'other_owner_after_case')==sentinel_state,'other_owner_and_adjacent_snapshots_preserved')
            result['cases'].append({'id':case,'passed':True,'actual_B_blocked_by_A':True,
                'first_committed':index==12 or index%2==0,'actual_product_calls':True,'other_owner_unchanged':True})
        require([c['id'] for c in result['cases']]==CASE_IDS,'all_thirteen_once')
    except BaseException as failure:
        result['failure']=type(failure).__name__
        raise
    finally:
        cleanup=[]
        for actor in reversed(actors):
            try:
                cleanup.append(actor.close())
            except BaseException as failure:
                cleanup.append({'actor':actor.name,'reaped':False,'readers_stopped':False,'failure':type(failure).__name__})
        reaped=all(c['reaped'] for c in cleanup);readers=all(c['readers_stopped'] for c in cleanup)
        result['cleanup']={'complete':reaped and readers,'actors_reaped':reaped,'readers_stopped':readers,'actors':cleanup}
        (output/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    require(result['cleanup']['complete'] is True,'owned_actor_cleanup')
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--bindings-json',required=True);parser.add_argument('--output-dir',required=True)
    args=parser.parse_args();config=json.loads(Path(args.bindings_json).read_text(encoding='utf-8'));config['output_dir']=args.output_dir
    run(config)
