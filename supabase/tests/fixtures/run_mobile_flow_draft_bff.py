#!/usr/bin/env python3
"""Real Flow tools/generators/BFF/SQL, one task-owned rollback. No provider."""
import argparse
import datetime
import json
import select
import shutil
import subprocess
from pathlib import Path
from run_mobile_reevaluation_cycle import LocalCycleDatabase
from run_mobile_health_hold_authority import Sessions, require, exclusive_json
from run_mobile_clinical_http import literal


def run(db,output):
    root=Path(__file__).resolve().parents[3];folder=Path(__file__).resolve().parent;output=Path(output).resolve()
    require(not output.exists(),'Evidence already exists')
    clean="SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL AND NOT EXISTS(SELECT 1 FROM net.http_request_queue) AND NOT EXISTS(SELECT 1 FROM private.mobile_flow_plan_draft_origins) AND NOT EXISTS(SELECT 1 FROM private.mobile_flow_plan_day_revisions)"
    require(db.query(clean)=='t','Owned PG not clean')
    globals_sql="SELECT md5(jsonb_build_object('config',(SELECT jsonb_agg(to_jsonb(c) ORDER BY key) FROM public.global_config c),'legal',(SELECT jsonb_agg(to_jsonb(d) ORDER BY id) FROM public.onboarding_legal_documents d),'sets',(SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM public.onboarding_legal_requirement_sets s),'audit',(SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM public.audit_log a))::text)"
    before=db.query(globals_sql);runners=list((root/'node_modules/.pnpm').glob('vite-node@*/node_modules/vite-node/vite-node.mjs'));node=shutil.which('node');require(node and len(runners)==1,'Vite runtime unavailable/ambiguous')
    owner='b3b01000-0000-4000-8000-000000006360'
    turns={k:'mobile_flow/'+owner+'/qa-current-draft-'+k for k in ['A','B','T']}
    signatures={'get_mobile_flow_plan_context':['p_user_id'],
      'get_mobile_current_clinical_state':['p_user_id','p_mode','p_body','p_expected'],
      'lookup_mobile_flow_plan_draft':['p_user_id','p_domain','p_request_key','p_source_message_id','p_expected'],
      'create_mobile_flow_plan_draft':['p_user_id','p_domain','p_request_key','p_source_message_id','p_expected','p_status','p_payload','p_uncertain_fields','p_origin_detail']}
    sessions=Sessions(db);session=None;child=None;result=None;failure=None;child_log='';seeded=False;armed=False;injected=0;edits=0;calls=0;turn_reads=0
    try:
        session=sessions.spawn('BEGIN;\n\\i '+str(folder/'mobile_clinical_signup_targets_fixture.sql')+'\n'
          "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);\n"
          "CREATE FUNCTION pg_temp.flow_rpc(statement text) RETURNS jsonb LANGUAGE plpgsql AS $rpc$ DECLARE data jsonb; BEGIN EXECUTE statement INTO data; RETURN jsonb_build_object('data',data,'error',NULL);EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('data',NULL,'error',jsonb_build_object('code',SQLSTATE));END $rpc$;GRANT EXECUTE ON FUNCTION pg_temp.flow_rpc(text) TO service_role;SELECT 'READY';\n")
        sessions.until(session,lambda line:line=='READY')
        child=subprocess.Popen([node,str(runners[0]),'--script',str(folder/'mobile_flow_draft_bff_bridge.ts')],cwd=root,env=dict(db.env,PERFORME_FLOW_DRAFT_QA='owned-local-rollback'),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        while True:
            require(select.select([child.stdout],[],[],30)[0],'Specific bridge observation timed out')
            line=child.stdout.readline();require(line,'Bridge stream closed');packet=json.loads(line);kind=packet.get('type')
            if kind=='result':result=packet;break
            require(kind!='failure','Bridge assertion failed')
            if kind=='seed':
                require(not seeded,'Seed replay refused');seeded=True
                inserts=''.join("INSERT INTO public.messages(user_id,direction,role,content_type,content,provider,provider_message_id) VALUES("+literal(owner)+",'in','user','text','Synthetic draft bridge','mobile_flow',"+literal(v)+");" for v in turns.values())
                sql="DO $seed$ DECLARE c jsonb;a uuid;day jsonb;BEGIN c:=m3b_cycle_test.signup_target_context(6360,'recomposicao');a:=(c->>'user')::uuid;day:=public.get_mobile_clinical_daily_context(a);PERFORM public.apply_mobile_clinical_daily(a,gen_random_uuid(),day->>'context_hash','{\"version\":1,\"formulaKcal\":2000,\"maintenanceKcal\":2500,\"sedentaryKcal\":1900,\"proteinTarget\":144,\"maintenanceProteinTarget\":126}');END $seed$;"+inserts+"SELECT "+literal({'owner':owner,'turns':turns})+'::jsonb;'
            elif kind=='rpc':
                calls+=1;name,args=packet['name'],packet['args'];require(calls<=180 and name in signatures and set(args)==set(signatures[name]) and args['p_user_id']==owner,'RPC scope/bound refused')
                if armed and name=='create_mobile_flow_plan_draft':
                    require(args['p_domain']=='nutrition' and args['p_request_key']==turns['B']+':propoe_plano_dieta' and injected==0,'CAS injection scope differs')
                    session.stdin.write(('UPDATE public.daily_snapshots SET protein_target=145 WHERE user_id='+literal(owner)+';UPDATE public.daily_snapshots SET protein_target=144 WHERE user_id='+literal(owner)+";SELECT 'INJECTED';\n").encode());session.stdin.flush();sessions.until(session,lambda line:line=='INJECTED');injected+=1;armed=False
                statement='SELECT public.'+name+'('+','.join(literal(args[k]) for k in signatures[name])+')'
                sql='SET LOCAL ROLE service_role;SELECT pg_temp.flow_rpc('+literal(statement)+');RESET ROLE;'
            elif kind=='turn':
                turn_reads+=1;require(turn_reads<=12 and packet['providerID'] in turns.values(),'Turn metadata scope refused')
                sql="SELECT jsonb_build_object('data',(SELECT jsonb_build_object('id',id) FROM public.messages WHERE user_id="+literal(owner)+" AND provider='mobile_flow' AND direction='in' AND role='user' AND provider_message_id="+literal(packet['providerID'])+"),'error',NULL)"
            elif kind=='witness':
                sql="SELECT jsonb_build_object('drafts',(SELECT count(*) FROM public.plan_drafts WHERE user_id="+literal(owner)+"),'origins',(SELECT count(*) FROM private.mobile_flow_plan_draft_origins WHERE user_id="+literal(owner)+"),'active_plans',(SELECT count(*) FROM public.training_plans WHERE user_id="+literal(owner)+")+(SELECT count(*) FROM public.prescriptions WHERE user_id="+literal(owner)+"),'revision',coalesce((SELECT revision::text FROM private.mobile_flow_plan_day_revisions WHERE user_id="+literal(owner)+"),'0'));"
            elif kind=='edit':
                edits+=1;require(edits==1,'Edit bound exceeded')
                sql="SELECT public.update_plan_draft_atomic("+literal(owner)+','+literal(packet['id'])+",(SELECT payload_version FROM public.plan_drafts WHERE user_id="+literal(owner)+' AND id='+literal(packet['id'])+"),(SELECT payload||'{\"notes\":\"QA edited notes\"}' FROM public.plan_drafts WHERE user_id="+literal(owner)+' AND id='+literal(packet['id'])+"),'[]',false)"
            elif kind=='arm':
                require(not armed and injected==0,'Injection replay refused');armed=True;sql="SELECT '{\"armed\":true}'::jsonb"
            else:raise ValueError('Unknown bridge operation')
            session.stdin.write((sql.rstrip().rstrip(';')+";\nSELECT 'REPLY';\n").encode());session.stdin.flush();rows=sessions.until(session,lambda item:item=='REPLY');values=[v for v in rows if v.startswith('{')];require(len(values)==1,'SQL response cardinality differs')
            child.stdin.write(values[0]+'\n');child.stdin.flush()
        child.stdin.close();child.wait(timeout=10);child_log=child.stderr.read()
        require(child.returncode==0 and result['status']=='PASS_ACTUAL_FLOW_TOOL_GENERATOR_BFF_SQL' and len(result['cases'])==8 and injected==1 and result['legacy_write_RPCs']==0,'Bridge qualification incomplete')
        sessions.finish(session,'SET CONSTRAINTS ALL IMMEDIATE;ROLLBACK;\n')
    except Exception as error:failure={'type':type(error).__name__,'message':str(error)}
    finally:
        if child and child.poll() is None:child.terminate();child.wait(timeout=5)
        if child and child.stderr and not child_log:child_log=child.stderr.read()
        if session and session.poll() is not None and not session.stderr.closed:child_log+='\nSQL:'+session.stderr.read().decode()[-8000:]
        sessions.close()
    clean_after=db.query(clean)=='t';globals_preserved=db.query(globals_sql)==before
    with Path(str(output)+'.child.log').open('x') as stream:stream.write(child_log)
    report={'at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'PASS' if failure is None and clean_after and globals_preserved else 'FAIL','failure':failure,'bridge':result,'RPCs':calls,'turn_metadata_reads':turn_reads,'CAS_injections':injected,'owned_PG_clean':clean_after,'config_legal_audit_preserved':globals_preserved,'tool_generator_BFF_SQL_real':True,'LLM_provider':False,'auxiliary_quotas_history_events_and_numeric_readers':'synthetic inputs/sinks; clinical state, original source, draft persistence, mutable replay and CAS are actual SQL','PostgREST':False,'connected_app':False,'Storage':False,'remote_operations':0,'new_paid_resources':0}
    exclusive_json(output,report);require(report['status']=='PASS','Flow draft BFF bridge failed; inspect evidence');return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--config',required=True);parser.add_argument('--output',required=True);args=parser.parse_args()
    report=run(LocalCycleDatabase(args.config),args.output);print(json.dumps({'status':report['status'],'RPCs':report['RPCs']}))
