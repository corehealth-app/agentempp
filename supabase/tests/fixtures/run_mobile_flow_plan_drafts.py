#!/usr/bin/env python3
"""Actual draft races on the exact task-owned UNIX PG. No provider or cloud."""
import argparse
import datetime
import json
import time
from pathlib import Path
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_clinical_http import literal


def run(db, output):
    root=Path(__file__).resolve().parents[3];folder=Path(__file__).resolve().parent
    output=Path(output).resolve();require(not output.exists(),'Evidence already exists')
    clean="SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)"
    require(db.query(clean)=='t','Owned PG is not clean')
    require(db.query("SELECT to_regprocedure('public.create_mobile_flow_plan_draft(uuid,text,text,uuid,jsonb,text,jsonb,jsonb,jsonb)') IS NOT NULL")=='t','Draft migration missing')
    preserved="SELECT md5(jsonb_build_object('config',(SELECT jsonb_agg(to_jsonb(c) ORDER BY key) FROM public.global_config c),'legal',(SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM public.onboarding_legal_documents d),'sets',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM public.onboarding_legal_requirement_sets s),'audit',(SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM public.audit_log a))::text)"
    before=db.query(preserved);sessions=Sessions(db);results=[];owners=[];failure=None
    def rpc(q):
        return 'SELECT public.create_mobile_flow_plan_draft('+','.join(literal(v) for v in [q['owner'],'nutrition',q['key'],q['message'],q['context'],'needs_completion',{'meta_kcal':2000,'meta_protein_g':144,'notes':'synthetic race'},[],{}])+');'
    def finish(child,ending='',expected=0,error=None):
        if ending:child.stdin.write(ending.encode());child.stdin.flush()
        child.stdin.close();child.stdin=None
        out,err=child.communicate(timeout=12)
        require(child.returncode==expected and (error in err.decode() if error else not err.strip()),'Owned race terminal state differs')
        return (sessions.buffers[child.pid]+out).decode()
    def wait_on(child,holder):
        lines=sessions.until(child,lambda s:s.startswith('PID:'));pid=int(next(s[4:] for s in lines if s.startswith('PID:')))
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            row=json.loads(db.query("SELECT jsonb_build_object('waiting',wait_event_type='Lock','blocked_by_holder',"+str(holder)+"=ANY(pg_blocking_pids(pid))) FROM pg_stat_activity WHERE pid="+str(pid)))
            if row['waiting'] and row['blocked_by_holder']:return
            require(child.poll() is None,'Waiter exited before a real lock was observed')
            time.sleep(.05)
        raise TimeoutError('Specific owner lock was not observed')
    try:
        require(db.run_file(folder/'mobile_reevaluation_cycle_fixture.sql',str(output)+'.setup.log')==0,'Fixture DDL failed')
        for index,name in enumerate(['same_key','target_changed','legacy_advisory_busy']):
            n=6350+index;owner=f'b3b01000-0000-4000-8000-{n:012d}';owners.append(owner)
            key=f'qa-mobile-race-{n}';row=json.loads(db.query("""WITH owner AS(SELECT m3b_cycle_test.seed("""+str(n)+""",clock_timestamp()-interval '1 day') AS id)
SELECT jsonb_build_object('owner',id) FROM owner"""));require(row['owner']==owner,'Seed identity differs')
            setup_output=db.query("""UPDATE public.user_profiles SET sex='masculino',birth_date='1990-01-01',height_cm=180,
weight_kg=80,body_fat_percent=24,current_protocol='recomposicao',activity_level='moderado',training_frequency=4 WHERE user_id="""+literal(owner)+""";
INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol)
VALUES("""+literal(owner)+""",(clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date,2000,144,'recomposicao');
WITH message AS(INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id)
VALUES("""+literal(owner)+",'in','user','text','Synthetic race','mobile_flow',"+literal(key)+") RETURNING id)\nSELECT jsonb_build_object('message',id) FROM message")
            json_rows=[line for line in setup_output.splitlines() if line.startswith('{')]
            require(len(json_rows)==1,'Seed response cardinality differs');row=json.loads(json_rows[0])
            q={'owner':owner,'message':row['message'],'key':key+':propoe_plano_dieta','context':json.loads(db.query('SELECT public.get_mobile_flow_plan_context('+literal(owner)+')'))}
            if name=='same_key':
                first=sessions.spawn('BEGIN;'+rpc(q)+"SELECT 'HOLDER:'||pg_backend_pid();SELECT 'READY';\n")
                lines=sessions.until(first,lambda s:s=='READY');first_result=json.loads(next(s for s in lines if s.startswith('{')));holder=int(next(s[7:] for s in lines if s.startswith('HOLDER:')))
                second=sessions.spawn("SELECT 'PID:'||pg_backend_pid();"+rpc(q)+'\n');wait_on(second,holder)
                finish(first,'COMMIT;\n');out=finish(second);second_result=json.loads(next(s for s in out.splitlines() if s.startswith('{')))
                require(first_result['inserted'] and not second_result['inserted'] and first_result['id']==second_result['id'],'Same-key race duplicated or relabeled a draft')
                require(db.query('SELECT count(*)=1 FROM public.plan_drafts WHERE user_id='+literal(owner))=='t','More than one draft')
                require(db.query('SELECT count(*)=1 FROM private.mobile_flow_plan_draft_origins WHERE user_id='+literal(owner))=='t','More than one origin')
                results.append({'case':name,'observed_owner_lock':True,'one_draft_one_origin':True,'accepted_replay_same_id':True})
            elif name=='target_changed':
                first=sessions.spawn('BEGIN;UPDATE public.daily_snapshots SET protein_target=145 WHERE user_id='+literal(owner)+";SELECT 'HOLDER:'||pg_backend_pid();SELECT 'READY';\n")
                lines=sessions.until(first,lambda s:s=='READY');holder=int(next(s[7:] for s in lines if s.startswith('HOLDER:')))
                second=sessions.spawn("SELECT 'PID:'||pg_backend_pid();"+rpc(q)+'\n');wait_on(second,holder)
                finish(first,'COMMIT;\n');finish(second,expected=3,error='mobile_current_clinical_changed')
                require(db.query('SELECT NOT EXISTS(SELECT 1 FROM public.plan_drafts WHERE user_id='+literal(owner)+')')=='t','Stale target stored draft')
                results.append({'case':name,'observed_owner_lock':True,'stale_context_refused':True,'drafts':0})
            else:
                first=sessions.spawn('BEGIN;SELECT pg_advisory_xact_lock(hashtextextended('+literal(owner+':plan-drafts')+",0));SELECT 'READY';\n")
                sessions.until(first,lambda s:s=='READY')
                second=sessions.spawn(rpc(q)+'\n');finish(second,expected=3,error='mobile_flow_draft_busy');finish(first,'ROLLBACK;\n')
                require(db.query('SELECT NOT EXISTS(SELECT 1 FROM public.plan_drafts WHERE user_id='+literal(owner)+')')=='t','Busy refusal wrote draft')
                results.append({'case':name,'busy_refused_without_deadlock':True,'drafts':0})
    except Exception as error:failure=str(error)
    finally:
        sessions.close()
        # Only exact synthetic owner IDs created above; no shared-data cleanup.
        if owners:
            require(all(v.startswith('b3b01000-0000-4000-8000-00000000635') for v in owners),'Cleanup owner scope differs')
            ids=','.join(literal(v) for v in owners)
            # Existing base fixture requires NO ACTION receipt parents first;
            # preserve these constraints rather than loosening the runtime.
            db.query('DELETE FROM private.mobile_reevaluation_cycles WHERE user_id IN('+ids+');'
                     'DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id IN('+ids+');'
                     'DELETE FROM public.users WHERE id IN('+ids+');')
        if db.query("SELECT to_regnamespace('m3b_cycle_test') IS NOT NULL")=='t':db.query('DROP SCHEMA m3b_cycle_test CASCADE')
    after=db.query(preserved);clean_after=db.query(clean)=='t'
    result={'at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'PASS' if failure is None and len(results)==3 and clean_after and before==after else 'FAIL','failure':failure,'cases':results,'owned_PG_clean':clean_after,'config_legal_audit_preserved':before==after,'synthetic_seeds':'Existing base seed creates explicit synthetic signup/epoch fixtures; not a clinical formula or genuine end-to-end signup proof','provider':False,'PostgREST':False,'Storage':False,'remote_operations':0,'new_paid_resources':0}
    exclusive_json(output,result);require(result['status']=='PASS','Draft concurrency failed; inspect evidence');return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',required=True);parser.add_argument('--output',required=True);args=parser.parse_args()
    report=run(LocalCycleDatabase(args.config),args.output);print(json.dumps({'status':report['status'],'cases':len(report['cases'])}))
