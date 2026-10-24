#!/usr/bin/env python3
"""Real consent races, restricted to the existing owned local socket runtime."""
import argparse
import json
import os
import select
import subprocess
import time
from pathlib import Path

from run_mobile_reevaluation_cycle import LocalCycleDatabase


def cleanup_fixture(database, owners, documents):
    """Teardown only our committed synthetic rows after clients have terminated.

    Legal rows are immutable even for their owner. The single immutable trigger
    is disabled ONLY inside this teardown transaction, under an exclusive lock;
    all FKs remain enabled, no test runs in it, and re-enable is transactional.
    LocalCycleDatabase has already proved the owned, socket-only target.
    """
    ids = ','.join("'" + owner + "'::uuid" for owner in owners)
    docs = ','.join("'" + document + "'::uuid" for document in documents)
    database.query(
        "BEGIN; LOCK TABLE public.legal_documents IN ACCESS EXCLUSIVE MODE;"
        "DO $guard$ BEGIN IF EXISTS(SELECT 1 FROM public.legal_documents "
        f"WHERE id IN({docs}) AND body NOT LIKE 'SYNTHETIC LOCAL %') THEN "
        "RAISE EXCEPTION 'Refuse non-fixture legal row'; END IF; END $guard$;"
        f"DELETE FROM private.mobile_reevaluation_cycles WHERE user_id IN({ids});"
        f"DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id IN({ids});"
        f"DELETE FROM public.users WHERE id IN({ids}) AND email LIKE 'm3b-cycle-%@example.invalid';"
        f"DELETE FROM private.mobile_reevaluation_photo_policies WHERE document_id IN({docs});"
        "ALTER TABLE public.legal_documents DISABLE TRIGGER legal_documents_immutable;"
        f"DELETE FROM public.legal_documents WHERE id IN({docs});"
        "ALTER TABLE public.legal_documents ENABLE TRIGGER legal_documents_immutable;"
        "DROP SCHEMA m3b_cycle_test CASCADE; COMMIT;")


def run_races(database, log):
    children = []
    buffers = {}
    results = []
    owners = [f"b3b01000-0000-4000-8000-{n:012d}" for n in range(111, 116)]
    doc_id = "b3b01000-0000-4000-8000-000000000411"
    new_doc_id = "b3b01000-0000-4000-8000-000000000412"
    key_a = "b3b01000-1000-4000-8000-000000000111"
    key_b = "b3b01000-1000-4000-8000-000000000112"
    fixture = Path(__file__).with_name("mobile_reevaluation_cycle_fixture.sql")
    if database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") != "t":
        raise RuntimeError("Consent race fixture already exists")
    if database.run_file(fixture, str(log) + ".setup.log"):
        raise RuntimeError("Consent race fixture setup failed")

    def spawn(sql):
        child = subprocess.Popen(database.args, env=database.env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        children.append(child)
        buffers[child.pid] = b""
        child.stdin.write(sql.encode())
        child.stdin.flush()
        return child

    def read_until(child, predicate):
        deadline = time.monotonic() + 15
        lines = []
        while time.monotonic() < deadline:
            while b"\n" in buffers[child.pid]:
                line, buffers[child.pid] = buffers[child.pid].split(b"\n", 1)
                decoded = line.decode()
                lines.append(decoded)
                if predicate(decoded):
                    return lines
            if select.select([child.stdout], [], [], 0.1)[0]:
                chunk = os.read(child.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError("Consent client exited before its marker")
                buffers[child.pid] += chunk
        raise TimeoutError("Consent client marker timeout")

    def finish(child, ending=""):
        if ending:
            child.stdin.write(ending.encode())
            child.stdin.flush()
        child.stdin.close()
        child.stdin = None
        out, err = child.communicate(timeout=15)
        return child.returncode, (buffers[child.pid] + out).decode(), err.decode()

    def accept(owner, cycle, key):
        return ("SELECT public.accept_mobile_reevaluation_photo_consent("
                f"'{owner}','{cycle}',1,'{doc_id}','body_photo_reevaluation_consent',"
                f"'race-local-1','pt-BR',(SELECT body_hash FROM public.legal_documents WHERE id='{doc_id}'),'{key}');")

    try:
        database.query("""
            INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from)
              VALUES('""" + doc_id + """','body_photo_reevaluation_consent','race-local-1','pt-BR',
                'SYNTHETIC LOCAL CONSENT RACE','2026-10-20T00:00:00Z');
            INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,
              version,locale,body_hash,idle_timeout_seconds,enabled)
              SELECT id,document_key,version,locale,body_hash,60,true FROM public.legal_documents
                WHERE id='""" + doc_id + """';
            SELECT m3b_cycle_test.seed(n,'2026-10-01T23:00:00Z') FROM generate_series(111,115) n;
        """)
        for owner, mode in zip(owners, ("same_key", "different_keys", "rollback", "reset", "publication_wait")):
            cycle = json.loads(database.query(
                "SET request.jwt.claims='{\"role\":\"service_role\"}';"
                f"SELECT public.start_mobile_reevaluation_cycle('{owner}',gen_random_uuid())"))['cycle']['id']
            if mode == "reset":
                first_action = f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
            elif mode == "publication_wait":
                first_action = (
                    "INSERT INTO public.legal_documents(id,document_key,version,locale,body,required_from) "
                    f"VALUES('{new_doc_id}','body_photo_reevaluation_consent','race-local-2','pt-BR',"
                    "'SYNTHETIC LOCAL REPLACEMENT',clock_timestamp()+interval '0.25 seconds');"
                    "INSERT INTO private.mobile_reevaluation_photo_policies(document_id,document_key,"
                    "version,locale,body_hash,idle_timeout_seconds,enabled) "
                    f"SELECT id,document_key,version,locale,body_hash,60,true FROM public.legal_documents WHERE id='{new_doc_id}';")
            else:
                first_action = accept(owner, cycle, key_a)
            header = "SET request.jwt.claims='{\"role\":\"service_role\"}';\n"
            first = spawn(header + "BEGIN;\nSELECT json_build_object('holder_pid',pg_backend_pid());\n"
                          + first_action + "\nSELECT 'CONSENT_READY';\n")
            first_lines = read_until(first, lambda line: line == "CONSENT_READY")
            holder_pid = json.loads(next(line for line in first_lines if line.startswith('{"holder_pid"')))["holder_pid"]
            first_receipt = next((json.loads(line) for line in first_lines
                                  if line.startswith('{"version"')), None)
            second_key = key_b if mode == "different_keys" else key_a
            second = spawn(header + "SELECT json_build_object('waiter_pid',pg_backend_pid());\n"
                           + accept(owner, cycle, second_key) + "\n")
            second_lines = read_until(second, lambda line: line.startswith('{"waiter_pid"'))
            waiter_pid = json.loads(second_lines[-1])["waiter_pid"]
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                waiting = json.loads(database.query(
                    "SELECT json_build_object('waiting',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) "
                    f"FROM pg_stat_activity WHERE pid={int(waiter_pid)}"))
                if waiting['waiting'] and holder_pid in waiting['blockers']:
                    break
                if second.poll() is not None:
                    raise RuntimeError("Waiter exited without waiting on owner")
                time.sleep(0.05)
            else:
                raise TimeoutError("Consent owner lock was not observed")
            if mode == "publication_wait":
                # Publication becomes effective during the genuine table-lock
                # wait. A pre-wait clock would incorrectly select the old text.
                database.query("SELECT pg_sleep(0.35)")
            release_time = database.query("SELECT clock_timestamp() AT TIME ZONE 'UTC'")
            first_exit, _, first_err = finish(first, "ROLLBACK;\n" if mode == "rollback" else "COMMIT;\n")
            second_exit, second_out, second_err = finish(second)
            if first_exit or first_err.strip():
                raise RuntimeError("Holder failed: " + first_err)
            if mode in ("different_keys", "reset", "publication_wait"):
                expected_error = {"different_keys": "mobile_reevaluation_revision_changed",
                                  "reset": "mobile_reevaluation_cycle_changed",
                                  "publication_wait": "mobile_reevaluation_photo_consent_changed"}[mode]
                if second_exit != 3 or expected_error not in second_err:
                    raise AssertionError("Waiting stale request was not rejected: " + second_err)
                expected_count = "1" if mode == "different_keys" else "0"
            else:
                if second_exit or second_err.strip():
                    raise RuntimeError("Waiting consent failed: " + second_err)
                second_receipt = json.loads(next(line for line in second_out.splitlines() if line.startswith('{"version"')))
                first_id = first_receipt['acceptance']['acceptance_id']
                second_id = second_receipt['acceptance']['acceptance_id']
                if mode == "same_key" and first_id != second_id:
                    raise AssertionError("Concurrent replay duplicated acceptance")
                if mode == "rollback" and first_id == second_id:
                    raise AssertionError("Rollback leaked the holder receipt")
                if mode == "rollback" and database.query(
                    f"SELECT accepted_at AT TIME ZONE 'UTC'>='{release_time}'::timestamp "
                    f"FROM private.mobile_reevaluation_photo_consents WHERE acceptance_id='{second_id}'") != "t":
                    raise AssertionError("Public clock captured before owner wait")
                expected_count = "1"
            actual_count = database.query(
                f"SELECT count(*) FROM private.mobile_reevaluation_photo_consents WHERE cycle_id='{cycle}'")
            if actual_count != expected_count:
                raise AssertionError("Unexpected number of consent receipts")
            if mode != "reset":
                expected_revision = "2" if expected_count == "1" else "1"
                if database.query(f"SELECT revision FROM private.mobile_reevaluation_cycles WHERE cycle_id='{cycle}'") != expected_revision:
                    raise AssertionError("Consent revision incremented more than once")
            results.append({'case': mode, 'status': 'PASS', 'owner_lock_observed': True,
                            'holder_backend_pid': holder_pid, 'waiter_backend_pid': waiter_pid,
                            'observed_blockers': waiting['blockers']})
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=3)
        cleanup_fixture(database, owners, (doc_id, new_doc_id))
    Path(log).write_text(json.dumps({'status': 'PASS', 'cases': results, 'owned_clients_reaped': True}, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--log', required=True)
    args = parser.parse_args()
    result_path = Path(args.log).resolve()
    if result_path.exists():
        raise ValueError('Evidence path already exists')
    database = LocalCycleDatabase(args.config)
    # Keep machine-readable SELECT output free of SET/transaction command tags.
    database.args.insert(1, '-q')
    behavior_log = str(result_path) + '.behavior.log'
    code = database.run_file(Path(__file__).parents[1] / 'mobile_reevaluation_photo_consent.sql', behavior_log)
    if code == 0:
        run_races(database, str(result_path) + '.races.json')
    result = {'exit': code, 'behavior_log': behavior_log,
              'race_log': str(result_path) + '.races.json', 'unix_socket_only': True}
    result_path.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
