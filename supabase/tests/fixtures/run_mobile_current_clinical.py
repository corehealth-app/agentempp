#!/usr/bin/env python3
"""Current capture sees committed config and a fresh clock after an actual wait."""
import argparse
import json
import time
from pathlib import Path
from run_mobile_health_hold_authority import Sessions, exclusive_json, require
from run_mobile_reevaluation_cycle import LocalCycleDatabase


def run(database, output):
    output = Path(output).resolve(); require(not output.exists(), 'Evidence exists')
    clean = "SELECT NOT EXISTS(SELECT 1 FROM public.users) AND to_regnamespace('m3b_cycle_test') IS NULL"
    require(database.query(clean) == 't', 'Owned runtime not clean')
    saved = database.query("SELECT coalesce((SELECT to_jsonb(c) FROM public.global_config c WHERE key='calc.training_min'),'null'::jsonb)")
    fixture = Path(__file__).with_name('mobile_clinical_no_plan_fixture.sql')
    sessions = Sessions(database)
    literal = lambda s: "'" + s.replace("'", "''") + "'"
    try:
        first = sessions.spawn("BEGIN; LOCK TABLE public.global_config IN ROW EXCLUSIVE MODE;"
            "INSERT INTO public.global_config(key,value) VALUES('calc.training_min','7') ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=clock_timestamp();"
            "SELECT json_build_object('holder',pg_backend_pid());\nSELECT 'HELD';\n")
        lines = sessions.until(first, lambda line: line == 'HELD'); holder = json.loads(next(x for x in lines if x.startswith('{"holder"')))['holder']
        second = sessions.spawn("BEGIN; SET LOCAL request.jwt.claim.role='service_role';\n\\i '" + str(fixture) + "'\n"
            "SELECT m3b_cycle_test.seed(2920,NULL);SELECT json_build_object('waiter',pg_backend_pid());\nSELECT 'BEFORE';\n")
        lines = sessions.until(second, lambda line: line == 'BEFORE'); waiter = json.loads(next(x for x in lines if x.startswith('{"waiter"')))['waiter']
        body = '{"locale":"pt-BR","timezone":"America/Sao_Paulo","sex":"masculino","birth_date":"1990-01-01","height_cm":180,"weight_kg":80,"body_fat_percent":24,"training_frequency":4}'
        second.stdin.write(("SELECT private.capture_mobile_current_clinical_state_at(m3b_cycle_test.uid(2920),'signup'," + literal(body) + ",NULL,NULL);\nSELECT 'CAPTURED';\n").encode());second.stdin.flush()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            blocked = json.loads(database.query("SELECT json_build_object('lock',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid=" + str(int(waiter))))
            if blocked['lock'] and holder in blocked['blockers']: break
            require(second.poll() is None, 'Capture exited before contention');time.sleep(.03)
        else: raise TimeoutError('Actual config wait not observed')
        before_release = database.query("SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')")
        sessions.finish(first,'COMMIT;\n')
        lines = sessions.until(second, lambda line: line == 'CAPTURED'); value = json.loads(next(x for x in lines if '"context_hash"' in x))
        require(value['observed_at'] >= before_release and value['safety']['observed_at'] == value['observed_at'], 'Capture reused a pre-wait clock')
        require(next(x['value'] for x in value['calculation_config'] if x['key'] == 'calc.training_min') == 7, 'Capture missed committed config')
        sessions.finish(second,'ROLLBACK;\n')
    finally:
        sessions.close()
        if saved == 'null': database.query("DELETE FROM public.global_config WHERE key='calc.training_min'")
        else: database.query("UPDATE public.global_config SET value=(" + literal(saved) + "::jsonb)->'value',updated_at=((" + literal(saved) + "::jsonb)->>'updated_at')::timestamptz WHERE key='calc.training_min'")
    restored = database.query("SELECT coalesce((SELECT to_jsonb(c) FROM public.global_config c WHERE key='calc.training_min'),'null'::jsonb)") == saved
    require(restored and database.query(clean) == 't','Owned state not restored')
    result = {'status':'PASS','case':'actual_config_commit_and_clock_after_wait','blockers':blocked['blockers'],
              'fresh_clock':True,'committed_value_observed':True,'config_restored_exact':True,'fixture_rolled_back':True,
              'guard':database.guard,'remote_operations':0,'new_paid_resources':0}
    exclusive_json(output,result);return result


if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    print(json.dumps(run(LocalCycleDatabase(a.config),a.output)))
