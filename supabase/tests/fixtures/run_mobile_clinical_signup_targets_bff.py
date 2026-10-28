#!/usr/bin/env python3
"""Genuine synthetic assigned signup -> core/service/SQL; one owned rollback."""
import argparse
import datetime
import json
import select
import shutil
import subprocess
from pathlib import Path
from run_mobile_clinical_http import literal
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output):
    root=Path(__file__).resolve().parents[3];folder=Path(__file__).resolve().parent;output=Path(output).resolve()
    require(not output.exists(),'Evidence exists')
    clean="SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue)"
    require(database.query(clean)=='t','Owned runtime not clean')
    config_sql="SELECT md5(jsonb_build_object('config',(SELECT jsonb_agg(to_jsonb(c) ORDER BY key) FROM public.global_config c),'legal',(SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM public.onboarding_legal_documents d),'sets',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM public.onboarding_legal_requirement_sets s),'audit',(SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM public.audit_log a))::text)"
    before=database.query(config_sql)
    runners=list((root/'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'));node=shutil.which('node')
    require(node and len(runners)==1,'Runtime ambiguous')
    signatures={'get_mobile_clinical_daily_receipt':['p_user_id','p_operation_key'],'get_mobile_clinical_daily_context':['p_user_id'],'apply_mobile_clinical_daily':['p_user_id','p_operation_key','p_context_hash','p_calculation']}
    signatures.update({'get_mobile_clinical_full_context':['p_user_id','p_kind','p_cycle_id'],'get_mobile_clinical_full_command':['p_user_id','p_preview_id','p_prepare_operation_key'],'prepare_mobile_clinical_full_command':['p_user_id','p_kind','p_cycle_id','p_operation_key','p_context_hash','p_command','p_form','p_intent','p_proposal'],'get_mobile_clinical_full_command_receipt':['p_user_id','p_preview_id','p_operation_key'],'confirm_mobile_clinical_full_command':['p_user_id','p_preview_id','p_operation_key','p_command','p_form','p_intent','p_proposal']})
    names=['recomposicao','manutencao','ganho_massa','first_EARLY','HOLD','no_plan','unknown_current','unknown_prior','closed']
    sessions=Sessions(database);session=None;bridge=None;owner=None;generation=None;epoch=None;name=None;prior=None
    seeded=[];calls=0;reads=0;advances=set();resets=set();result=None;failure=None;child_log='';last_type=None;last_rpc=None
    try:
        session=sessions.spawn("BEGIN;SET LOCAL request.jwt.claim='{"+'"role":"service_role"'+"}';\n\\i '"+str(folder/'mobile_clinical_signup_targets_fixture.sql')+"'\nCREATE FUNCTION pg_temp.signup_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$ DECLARE data jsonb;BEGIN EXECUTE statement INTO data;RETURN jsonb_build_object('data',data,'error',NULL);EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE));END $rpc$;GRANT EXECUTE ON FUNCTION pg_temp.signup_rpc(text) TO service_role;SELECT 'READY';\n")
        sessions.until(session,lambda line:line=='READY')
        bridge=subprocess.Popen([node,str(runners[0]),'--script',str(folder/'mobile_clinical_signup_targets_bff_bridge.ts')],cwd=root,env=dict(database.env,PERFORME_SIGNUP_TARGET_QA='owned-local-rollback'),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        while True:
            require(select.select([bridge.stdout],[],[],20)[0],'Observation timeout')
            line=bridge.stdout.readline();require(line,'Child closed');packet=json.loads(line);last_type=packet.get('type')
            if packet['type']=='result':result=packet;break
            require(packet['type']!='failure','Child assertion failed')
            if packet['type']=='seed':
                name=packet['case'];require(name==names[len(seeded)],'Case order differs');n=6300+len(seeded);seeded.append(name)
                owner=f'b3b01000-0000-4000-8000-{n:012d}';prior=None
                phase=name if name in names[:3] else None if name=='no_plan' else 'manutencao' if name=='HOLD' else 'recomposicao'
                extra=""
                if name=='HOLD':extra="PERFORM public.declare_mobile_health_risk(a,gen_random_uuid(),ARRAY['reduced_intake']);"
                if name in ['unknown_current','unknown_prior','closed']:
                    extra+="INSERT INTO public.daily_snapshots(user_id,date,calories_target,protein_target,current_protocol,day_closed,closed_at) VALUES(a,(clock_timestamp() AT TIME ZONE 'Etc/GMT+12')::date,1099,120,'recomposicao',"+('true' if name=='closed' else 'false')+", "+('clock_timestamp()' if name=='closed' else 'NULL')+");"
                sql="DO $seed$ DECLARE c jsonb;a uuid;BEGIN c:=m3b_cycle_test.signup_target_context("+str(n)+","+literal(phase)+",'Etc/GMT+12');a:=(c->>'user')::uuid;"+extra+"PERFORM set_config('m3b.signup_seed',c::text,true);END $seed$;SELECT current_setting('m3b.signup_seed')::jsonb;"
            elif packet['type']=='rpc':
                calls+=1;require(calls<=100,'RPC bound exceeded');rpc,args=packet['name'],packet['args']
                last_rpc=rpc
                require(rpc in signatures and set(args)==set(signatures[rpc]) and args['p_user_id']==owner,'RPC scope refused')
                statement='SELECT public.'+rpc+'('+','.join(literal(args[k]) for k in signatures[rpc])+')'
                sql='SET LOCAL ROLE service_role;SELECT pg_temp.signup_rpc('+literal(statement)+');RESET ROLE;'
            elif packet['type']=='state':
                reads+=1;require(owner and reads<=65,'State bound exceeded')
                today="(clock_timestamp() AT TIME ZONE (SELECT timezone FROM public.users WHERE id="+literal(owner)+"))::date"
                sql="SELECT jsonb_build_object('hash',md5(m3b_cycle_test.original_state("+literal(owner)+")::text),'day',(SELECT to_jsonb(s) FROM public.daily_snapshots s WHERE user_id="+literal(owner)+" AND date="+today+"),'origin',private.mobile_clinical_target_origin("+literal(owner)+","+literal(generation)+"::uuid,"+literal(epoch)+"::uuid,"+today+",clock_timestamp()),'fulls',(SELECT count(*) FROM private.mobile_clinical_full_receipts WHERE user_id="+literal(owner)+"),'events',(SELECT count(*) FROM private.mobile_clinical_episode_events WHERE user_id="+literal(owner)+"),'applications',(SELECT count(*) FROM private.mobile_clinical_signup_applications WHERE user_id="+literal(owner)+"),'origins',(SELECT count(*) FROM private.mobile_clinical_target_origins WHERE user_id="+literal(owner)+"),'prior_hash',(SELECT md5(to_jsonb(s)::text) FROM public.daily_snapshots s WHERE id="+literal(prior)+"::uuid));"
            elif packet['type']=='advance':
                require(name in names[:3]+['unknown_prior'] and owner not in advances,'Advance refused');advances.add(owner)
                session.stdin.write(("SELECT id::text FROM public.daily_snapshots WHERE user_id="+literal(owner)+" AND date=(clock_timestamp() AT TIME ZONE 'Etc/GMT+12')::date;\nSELECT 'PRIOR';\n").encode());session.stdin.flush()
                rows=sessions.until(session,lambda line:line=='PRIOR');ids=[v for v in rows if len(v)==36 and v.count('-')==4];require(len(ids)==1,'Prior row ambiguous');prior=ids[0]
                sql="UPDATE public.users SET timezone='Pacific/Kiritimati' WHERE id="+literal(owner)+";SELECT jsonb_build_object('prior_hash',(SELECT md5(to_jsonb(s)::text) FROM public.daily_snapshots s WHERE id="+literal(prior)+"::uuid));"
            elif packet['type']=='reset':
                require(name in names[:3] and owner not in resets,'Reset refused');resets.add(owner)
                sql="SELECT public.reset_user_conversation_atomic("+literal(owner)+",true);"
            elif packet['type']=='early':
                require(name=='first_EARLY','EARLY refused')
                sql="SELECT private.start_mobile_clinical_full_at("+literal(owner)+",gen_random_uuid(),'EARLY_FULL','not_well_with_plan',NULL);"
            else:raise ValueError('Packet refused')
            session.stdin.write((sql+"\nSELECT 'REPLY';\n").encode());session.stdin.flush();rows=sessions.until(session,lambda line:line=='REPLY');values=[v for v in rows if v.startswith('{')];require(len(values)==1,'Reply cardinality differs')
            reply=json.loads(values[0])
            if packet['type']=='seed':generation=reply['generation'];epoch=reply['epoch']
            bridge.stdin.write(values[0]+'\n');bridge.stdin.flush()
        bridge.stdin.close();bridge.wait(timeout=10);child_log=bridge.stderr.read()
        require(bridge.returncode==0 and result['status']=='PASS_ACTUAL_ASSIGNED_SIGNUP_DAILY_SQL' and len(result['cases'])==9,'Terminal qualification differs')
        sessions.finish(session,'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;\n')
    except Exception as error:failure=str(error)
    finally:
        if bridge and bridge.poll() is None:
            bridge.terminate()
            try:bridge.wait(timeout=5)
            except subprocess.TimeoutExpired:bridge.kill();bridge.wait(timeout=5)
        if bridge and bridge.stderr and not child_log:child_log=bridge.stderr.read()
        if session and session.poll() is not None and not session.stderr.closed:child_log+='\nSQL:\n'+session.stderr.read().decode()[-8000:]
        sessions.close()
    rolled_back=database.query(clean)=='t';preserved=database.query(config_sql)==before
    with Path(str(output)+'.child.log').open('x') as f:f.write(child_log)
    report={'at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'PASS' if not failure and rolled_back and preserved else 'FAIL','failure':failure,'last_type':last_type,'last_rpc':last_rpc,'seeded':seeded,'bridge':result,'RPCs':calls,'state_reads':reads,'real_keyed_signup':True,'all_rolled_back':rolled_back,'config_legal_audit_preserved':preserved,'provider':False,'Storage':False,'PostgREST':False,'deployed_HTTP':False,'remote_operations':0,'new_paid_resources':0}
    exclusive_json(output,report);require(report['status']=='PASS','Signup target BFF/SQL failed; inspect evidence');return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',required=True);parser.add_argument('--output',required=True);args=parser.parse_args()
    report=run(LocalCycleDatabase(args.config),args.output);print(json.dumps({'status':report['status'],'RPCs':report['RPCs']}))
