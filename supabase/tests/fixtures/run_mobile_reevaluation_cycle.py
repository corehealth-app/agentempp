#!/usr/bin/env python3
"""Run cycle SQL only in a task-owned UNIX-socket database. Import is inert."""
import argparse
import hashlib
import json
import os
import select
import subprocess
import time
from pathlib import Path


class LocalCycleDatabase:
    def __init__(self, config_path):
        self.config_path = Path(config_path).resolve(strict=True)
        self.config = json.loads(self.config_path.read_text())
        c = self.config
        self.data = Path(c["data_directory"]).resolve(strict=True)
        self.socket = Path(c["socket_directory"]).resolve(strict=True)
        self.psql = Path(c["psql"]).resolve(strict=True)
        marker = json.loads((self.data.parent / "OWNER.json").read_text())
        if (c["task"] != "performe-m3b-cycle-foundation"
                or marker["task"] != c["task"] or marker["nonce"] != c["nonce"]
                or self.data.parent != self.config_path.parent
                or not str(self.socket).startswith("/private/tmp/performe-m3b-")
                or self.socket.stat().st_uid != os.geteuid()
                or self.socket.stat().st_mode & 0o077
                or self.data.stat().st_uid != os.geteuid()
                or hashlib.sha256(self.psql.read_bytes()).hexdigest() != c["psql_sha256"]
                or c["database"] != "postgres" or c["port"] != 22997):
            raise ValueError("M3B local target identity mismatch")
        self.env = {k: os.environ[k] for k in ("PATH", "LANG", "TMPDIR") if k in os.environ}
        self.env.update(HOME=c["runtime_home"], PGCONNECT_TIMEOUT="5",
                        PGPASSFILE=str(Path(c["runtime_home"]) / ".pgpass.empty"))
        self.args = [str(self.psql), "-w", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
                     "-h", str(self.socket), "-p", str(c["port"]), "-U", "postgres", "-d", "postgres"]
        observed = json.loads(self.query("""
            SELECT json_build_object('user',current_user,'db',current_database(),
              'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),
              'config',current_setting('config_file'),'hba',current_setting('hba_file'),
              'listen',current_setting('listen_addresses'),'tcp',inet_server_addr(),
              'cron_off',current_setting('cron.launch_active_jobs')='off',
              'net_zero',current_setting('pg_net.batch_size')='0',
              'pid',pg_postmaster_start_time()::text)::text
        """))
        if (observed["user"] != "postgres" or observed["db"] != "postgres"
                or Path(observed["data"]).resolve() != self.data
                or Path(observed["config"]).resolve() != self.data / "postgresql.conf"
                or Path(observed["hba"]).resolve() != self.data / "pg_hba.conf"
                or observed["socket"] != str(self.socket) or observed["listen"] != ""
                or observed["tcp"] is not None or not observed["cron_off"] or not observed["net_zero"]):
            raise ValueError("M3B server guard refused target")
        self.guard = observed

    def query(self, sql):
        result = subprocess.run(self.args + ["-c", sql], env=self.env,
                                capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError("M3B local query failed: " + result.stderr[-2000:])
        return result.stdout.strip()

    def run_file(self, path, log):
        path = Path(path).resolve(strict=True)
        repo = Path(__file__).resolve().parents[3]
        if not path.is_relative_to(repo / "supabase") or path.suffix != ".sql":
            raise ValueError("Only repository Supabase SQL is accepted")
        log = Path(log).resolve()
        with os.fdopen(os.open(log, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), "w") as stream:
            result = subprocess.run(self.args + ["-f", str(path)], env=self.env,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=90)
        return result.returncode


def run_concurrency(database, log):
    """Observe an actual blocked backend, then release its owning transaction."""
    results = []
    children = []
    buffers = {}
    owners = [f"b3b01000-0000-4000-8000-{n:012d}" for n in range(20, 24)]
    key_a = "b3b01000-1000-4000-8000-000000000020"
    key_b = "b3b01000-1000-4000-8000-000000000021"
    fixture = Path(__file__).with_name("mobile_reevaluation_cycle_fixture.sql")
    if database.query("SELECT to_regnamespace('m3b_cycle_test') IS NULL") != "t":
        raise RuntimeError("Concurrency fixture already exists")
    if database.run_file(fixture, str(log) + ".setup.log"):
        raise RuntimeError("Concurrency fixture setup failed")

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
                line = line.decode()
                lines.append(line)
                if predicate(line):
                    return lines
            ready, _, _ = select.select([child.stdout], [], [], 0.1)
            if ready:
                chunk = os.read(child.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError("Owned SQL session exited before its marker")
                buffers[child.pid] += chunk
        raise TimeoutError("Owned SQL session did not produce its marker")

    def finish(child, ending=""):
        if ending:
            child.stdin.write(ending.encode())
            child.stdin.flush()
        child.stdin.close()
        child.stdin = None
        out, err = child.communicate(timeout=15)
        return child.returncode, (buffers[child.pid] + out).decode(), err.decode()

    try:
        database.query("SELECT m3b_cycle_test.seed(n,'2026-10-01T23:00:00Z') FROM generate_series(20,23) n")
        for index, mode in enumerate(("same_key_commit", "different_keys_commit", "rollback", "reset")):
            owner = owners[index]
            if mode == "reset":
                original = json.loads(database.query(
                    f"SELECT public.start_mobile_reevaluation_cycle('{owner}','{key_a}')"))
                first_sql = f"SELECT public.reset_user_conversation_atomic('{owner}',true);"
            else:
                first_sql = f"SELECT public.start_mobile_reevaluation_cycle('{owner}','{key_a}');"
            first = spawn("BEGIN;\nSELECT jsonb_build_object('holder_pid',pg_backend_pid());\n"
                          + first_sql + "\nSELECT 'M3B_READY';\n")
            first_lines = read_until(first, lambda line: line == "M3B_READY")
            holder_pid = json.loads(next(line for line in first_lines if line.startswith('{"holder_pid"')))["holder_pid"]
            first_result = json.loads(next(line for line in first_lines if line.startswith("{")
                                           and not line.startswith('{"holder_pid"')))
            second_key = key_b if mode == "different_keys_commit" else key_a
            second = spawn("SELECT jsonb_build_object('pid',pg_backend_pid());\n"
                           f"SELECT public.start_mobile_reevaluation_cycle('{owner}','{second_key}');\n")
            second_lines = read_until(second, lambda line: line.startswith('{"pid"'))
            backend_pid = json.loads(second_lines[-1])["pid"]
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                waiting = json.loads(database.query(
                    f"SELECT json_build_object('waiting',wait_event_type='Lock',"
                    f"'blockers',pg_blocking_pids(pid)) FROM pg_stat_activity WHERE pid={int(backend_pid)}"))
                if waiting["waiting"] and holder_pid in waiting["blockers"]:
                    break
                if second.poll() is not None:
                    raise RuntimeError("Second session exited instead of waiting on owner")
                time.sleep(0.05)
            else:
                raise TimeoutError("Real owner lock was not observed")
            end = "ROLLBACK" if mode == "rollback" else "COMMIT"
            first_exit, _, first_err = finish(first, end + ";\n")
            second_exit, second_out, second_err = finish(second)
            if first_exit or first_err.strip():
                raise RuntimeError("First owner transaction failed: " + first_err)
            if mode == "reset":
                if second_exit != 3 or "mobile_reevaluation_generation_changed" not in second_err:
                    raise AssertionError("Reset did not reject the waiting stale key")
                state = json.loads(database.query(f"SELECT public.get_mobile_reevaluation_cycle('{owner}')"))
                if state["unavailable_reason"] != "onboarding_incomplete" or state["cycle"] is not None:
                    raise AssertionError("Reset exposed a historical cycle")
                if not original["cycle"]["id"]:
                    raise AssertionError("Reset fixture did not have a prior cycle")
            else:
                if second_exit:
                    raise RuntimeError("Second owner transaction failed: " + second_err)
                second_result = json.loads(next(line for line in second_out.splitlines() if line.startswith("{")))
                first_id = first_result["cycle"]["id"]
                second_id = second_result["cycle"]["id"]
                if (first_id == second_id) if mode == "rollback" else (first_id != second_id):
                    raise AssertionError("Cycle identity did not follow transaction outcome")
                if database.query(f"SELECT count(*) FROM private.mobile_reevaluation_cycles WHERE user_id='{owner}'") != "1":
                    raise AssertionError("Concurrent start did not leave exactly one cycle")
                expected_keys = "2" if mode == "different_keys_commit" else "1"
                if database.query(f"SELECT count(*) FROM private.mobile_reevaluation_start_keys WHERE user_id='{owner}'") != expected_keys:
                    raise AssertionError("Concurrent start key count differs")
            results.append({"case": mode, "owner_lock_observed": True,
                            "holder_backend_pid": holder_pid, "waiting_backend_pid": backend_pid,
                            "observed_blockers": waiting["blockers"], "status": "PASS"})
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=3)
        ids = ",".join("'" + owner + "'::uuid" for owner in owners)
        # Real historical provenance FKs are NO ACTION: delete only this runner's
        # synthetic cycles/receipts before its owners, never weaken those FKs.
        database.query(f"DELETE FROM private.mobile_reevaluation_cycles WHERE user_id IN({ids});"
                       f"DELETE FROM private.mobile_signup_strength_completion_receipts WHERE user_id IN({ids});"
                       f"DELETE FROM public.users WHERE id IN({ids}); DROP SCHEMA m3b_cycle_test CASCADE;")
    with os.fdopen(os.open(log, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), "w") as stream:
        json.dump({"status": "PASS", "cases": results, "owned_clients_reaped": True}, stream, indent=2)
        stream.write("\n")
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--sql")
    mode.add_argument("--concurrency", action="store_true")
    mode.add_argument("--suite", action="store_true")
    parser.add_argument("--log", required=True)
    args = parser.parse_args()
    database = LocalCycleDatabase(args.config)
    if args.suite:
        behavior_log = str(args.log) + ".behavior.log"
        test = Path(__file__).parents[1] / "mobile_reevaluation_cycle.sql"
        code = database.run_file(test, behavior_log)
        if code == 0:
            code = run_concurrency(database, str(args.log) + ".concurrency.json")
        with os.fdopen(os.open(args.log, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), "w") as stream:
            json.dump({"exit": code, "behavior_log": behavior_log,
                       "concurrency_log": str(args.log) + ".concurrency.json"}, stream, indent=2)
            stream.write("\n")
    else:
        code = run_concurrency(database, args.log) if args.concurrency else database.run_file(args.sql, args.log)
    print(json.dumps({"exit": code, "log": str(Path(args.log).resolve()),
                      "unix_socket_only": True, "new_paid_resources": 0}))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
