#!/usr/bin/env python3
"""S7 bounded A/B SQL test driver. Import is inert; no server lifecycle or DDL.
run(config) requires Root-reviewed local bindings and always writes RESULT.json
AFTER owned actor cleanup, including when the original BaseException propagates.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import signal
import subprocess
import threading
import time

EXPECTED_IDS = {
    'owner_commit': 'c59a8000-0000-0000-0000-000000000003',
    'life_commit': 'c59a8000-0000-0000-0000-000000000103',
    'owner_rollback': 'c59a8000-0000-0000-0000-000000000004',
    'life_rollback': 'c59a8000-0000-0000-0000-000000000104',
}
JSON_NULL = object()
WIRE_KEYS = {'ownerID', 'lifecycleKey', 'operationKey', 'originalOperationType', 'legacyArguments', 'admittedAt', 'recentCutoff'}


def require(value, label):
    if value is not True:
        raise RuntimeError('C59S7_DRIVER:' + label)


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def instant(value):
    require(isinstance(value, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z', value) is not None, 'US6')
    return datetime.datetime.strptime(value, '%Y-%m-%dT%H:%M:%S.%fZ').replace(tzinfo=datetime.timezone.utc)


def candidate(owner, raw, later=False):
    return {'p_user_id': owner, 'p_date': '2026-10-13' if later else '2026-10-12',
        'p_workout_type': raw, 'p_duration_min': 90 if later else 60,
        'p_estimated_kcal': 600 if later else 300, 'p_intensity': 'alta' if later else 'moderada',
        'p_notes': 'candidate B' if later else 'candidate A',
        'p_performed_at': '2026-10-13 16:00:00.654321+00' if later else '2026-10-12 15:00:00.123456+00',
        'p_provider_message_id': 'provider-B' if later else 'provider-A',
        'p_calories_target': 2200 if later else 2000, 'p_protein_target': 170 if later else 150,
        'p_replace_recent': later, 'p_replace_since': '2026-10-13 10:00:00+00' if later else '2026-10-12 09:00:00+00'}


def call(owner, life, key, raw, args):
    payload = ('NULL' if args is None else "'null'::jsonb" if args is JSON_NULL
        else literal(json.dumps(args, ensure_ascii=False)) + '::jsonb')
    return 'public.read_or_admit_workout_strength_command(' + ','.join(
        [literal(owner) + '::uuid', literal(life) + '::uuid', literal(key), literal(raw), payload]) + ')'


class Actor:
    def __init__(self, name, config, output):
        self.name = name
        self.output = output
        self.queue = queue.Queue()
        env = {key: os.environ[key] for key in ['PATH', 'HOME', 'LANG', 'LC_ALL', 'TMPDIR'] if key in os.environ}
        for config_key, env_key in [('pgpassfile', 'PGPASSFILE'), ('pgservicefile', 'PGSERVICEFILE')]:
            empty_file = Path(config[config_key])
            require(empty_file.is_absolute() and empty_file.is_file() and empty_file.read_bytes() == b'', 'empty_' + config_key)
            env[env_key] = str(empty_file)
        env.update({'PGCONNECT_TIMEOUT': '5', 'PGAPPNAME': 'c59s7-' + name})
        self.out = open(output / (name + '.stdout.log'), 'x', encoding='utf-8')
        self.err = open(output / (name + '.stderr.log'), 'x', encoding='utf-8')
        self.threads = []
        self.proc = None
        self.serial = 0
        self.transaction = False
        argv = [config['psql'], '-w', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
            '-h', config['socket'], '-p', str(config['port']), '-U', config['user'], '-d', config['database']]
        try:
            self.proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, encoding='utf-8', bufsize=1, env=env)
            for stream, log, deliver in [(self.proc.stdout, self.out, True), (self.proc.stderr, self.err, False)]:
                thread = threading.Thread(target=self._read, args=(stream, log, deliver), daemon=True)
                thread.start()
                self.threads.append(thread)
        except BaseException:
            self.close()
            raise

    def _read(self, stream, log, deliver):
        try:
            for line in stream:
                log.write(line)
                log.flush()
                if deliver:
                    self.queue.put(line.rstrip('\r\n'))
        finally:
            if deliver:
                self.queue.put(None)

    def send(self, sql, label):
        self.serial += 1
        token = 'C59S7_END_' + self.name + '_' + str(self.serial)
        command = "SELECT jsonb_build_object('tag'," + literal(label) + ",'value',(" + sql + "))::text;\n\\echo " + token + '\n'
        self.proc.stdin.write(command)
        self.proc.stdin.flush()
        return label, token

    def receive(self, ticket, timeout=10):
        label, token = ticket
        deadline = time.monotonic() + timeout
        value = None
        seen = False
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('C59S7_DRIVER:' + self.name + ':' + label)
            line = self.queue.get(timeout=remaining)
            if line is None:
                raise RuntimeError('C59S7_DRIVER:actor_closed:' + self.name)
            if line == token:
                require(seen, 'missing_tag:' + label)
                return value
            if line.startswith('{'):
                parsed = json.loads(line)
                if parsed.get('tag') == label:
                    require(not seen, 'duplicate_tag:' + label)
                    seen = True
                    value = parsed['value']

    def query(self, expression, label, timeout=10):
        return self.receive(self.send(expression, label), timeout)

    def statement(self, sql):
        self.proc.stdin.write(sql + '\n')
        self.proc.stdin.flush()
        self.query('true', 'statement_barrier')

    def begin(self):
        self.statement('BEGIN ISOLATION LEVEL READ COMMITTED;')
        self.transaction = True

    def finish(self, commit):
        self.statement('COMMIT;' if commit else 'ROLLBACK;')
        self.transaction = False

    def close(self):
        proc = self.proc
        reaped = proc is None
        if proc is not None:
            try:
                if proc.poll() is None:
                    try:
                        proc.stdin.write(('ROLLBACK;\n' if self.transaction else '') + '\\q\n')
                        proc.stdin.flush()
                    except (BrokenPipeError, OSError, ValueError):
                        pass
                    try:
                        proc.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        proc.terminate()
                        try:
                            proc.wait(timeout=2)
                        except subprocess.TimeoutExpired:
                            proc.kill()
                            proc.wait(timeout=2)
                else:
                    proc.wait(timeout=1)
                reaped = proc.poll() is not None
            finally:
                if proc.stdin is not None:
                    try:
                        proc.stdin.close()
                    except (BrokenPipeError, OSError, ValueError):
                        pass
        for thread in self.threads:
            thread.join(timeout=2)
        readers = all(not thread.is_alive() for thread in self.threads)
        if proc is not None:
            for stream in [proc.stdout, proc.stderr]:
                if stream is not None:
                    stream.close()
        self.out.close()
        self.err.close()
        return {'actor': self.name, 'reaped': reaped, 'readers_stopped': readers,
            'exit_code': None if proc is None else proc.returncode}


def check_wire(wire, owner, life, key, raw, args):
    require(isinstance(wire, dict) and set(wire) == WIRE_KEYS, 'wire7keys')
    require(wire['ownerID'] == owner and wire['lifecycleKey'] == life and wire['operationKey'] == key
        and wire['originalOperationType'] == raw and wire['legacyArguments'] == args, 'winner_literals')
    require(instant(wire['admittedAt']) - instant(wire['recentCutoff']) == datetime.timedelta(hours=6), 'cutoff6h')


def _create_registered_actor(name, config, output, actors):
    """Defer only INT/TERM while a child can exist before registry ownership.
    Do not mask signals: the child must not inherit a blocked signal mask.
    Restore caller handlers before propagating the deferred interruption.
    """
    pending = []
    previous_int = signal.getsignal(signal.SIGINT)
    previous_term = signal.getsignal(signal.SIGTERM)

    def defer_signal(_signum, _frame):
        pending.append(_signum)

    try:
        signal.signal(signal.SIGINT, defer_signal)
        signal.signal(signal.SIGTERM, defer_signal)
        actor = Actor(name, config, output)
        actors.append(actor)
    finally:
        try:
            signal.signal(signal.SIGINT, previous_int)
        finally:
            signal.signal(signal.SIGTERM, previous_term)
    if pending:
        raise InterruptedError('C59S7_DRIVER:deferred_actor_creation_signal')
    return actor


def run(config):
    output = Path(config['output_dir'])
    output.mkdir(parents=True, exist_ok=False)
    result = {'executed': False, 'failure': None, 'cases': [],
        'cleanup': {'complete': False, 'actors_reaped': False, 'readers_stopped': False, 'actors': []}}
    actors = []
    try:
        require(config.get('root_reviewed') is True, 'root_review_required')
        require(config.get('database') == 'postgres' and config.get('user') == 'c59a2_local_admin', 'local_identity_binding')
        require(config.get('port') == 55493 and str(config.get('socket', '')).startswith('/private/tmp/performe-c59a2-pg.'), 'local_socket_binding')
        require(Path(config['psql']).is_absolute() and hashlib.sha256(Path(config['psql']).read_bytes()).hexdigest() == config['psql_sha256'], 'psql_pin')
        for key, value in EXPECTED_IDS.items():
            require(config.get(key) == value, 'fixture_ID:' + key)
        a = _create_registered_actor('A', config, output, actors)
        b = _create_registered_actor('B', config, output, actors)
        identity = "jsonb_build_object('owner',session_user,'db',current_database(),'port',current_setting('port')::int,'data',current_setting('data_directory'),'socket',current_setting('unix_socket_directories'),'listen',current_setting('listen_addresses'),'pid',pg_backend_pid(),'isolation',current_setting('transaction_isolation'),'marker',(SELECT tag FROM c59s7_fixture.ownership))"
        ids = []
        for actor in actors:
            info = actor.query(identity, 'identity')
            require(info['owner'] == config['user'] and info['db'] == config['database']
                and info['port'] == config['port'] and info['data'] == config['expected_data_directory']
                and info['socket'] == config['socket'] and info['listen'] == ''
                and info['isolation'] == 'read committed' and info['marker'] == 'c59s7_command_v1', 'actual_local_identity')
            ids.append(info['pid'])
            actor.statement("SET statement_timeout='10s'; SET lock_timeout='8s'; SET request.jwt.claims='{\"role\":\"service_role\"}';")
        require(ids[0] != ids[1], 'distinct_A_B')
        result['executed'] = True
        for commit, suffix in [(True, 'commit'), (False, 'rollback')]:
            owner, life = config['owner_' + suffix], config['life_' + suffix]
            raw, key = '  musculacao  ', 'concurrent-' + suffix
            args_a, args_b = candidate(owner, raw), candidate(owner, raw, True)
            a.begin()
            winner_a = a.query(call(owner, life, key, raw, args_a), 'admit_A_' + suffix)
            check_wire(winner_a, owner, life, key, raw, args_a)
            b.begin()
            pending_b = b.send(call(owner, life, key, raw, args_b), 'admit_B_' + suffix)
            deadline = time.monotonic() + 6
            blocked = False
            while time.monotonic() < deadline:
                a.statement('SELECT pg_stat_clear_snapshot();')
                blocked = a.query(str(ids[0]) + '=ANY(pg_blocking_pids(' + str(ids[1]) + '))', 'observed_block_' + suffix)
                if blocked is True:
                    break
            require(blocked is True, 'actual_B_blocked_by_A:' + suffix)
            lower = a.query("to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"')", 'before_release_' + suffix)
            a.finish(commit)
            winner_b = b.receive(pending_b)
            expected_args = args_a if commit else args_b
            check_wire(winner_b, owner, life, key, raw, expected_args)
            if commit:
                require(winner_b == winner_a, 'first_winner_all7despite_11_divergent_prepared_args')
            else:
                require(instant(winner_b['admittedAt']) >= instant(lower), 'clock_after_observed_block_lower_bound')
            after_invalid = b.query(call(owner, life, key, raw, JSON_NULL), 'invalid_later_' + suffix)
            require(after_invalid == winner_b, 'invalid_candidate_ignored_after_winner')
            b.finish(True)
            durable = a.query(call(owner, life, key, raw, None), 'durable_' + suffix)
            require(durable == winner_b, 'durable_exact_winner')
            count = a.query('(SELECT count(*) FROM private.workout_strength_commands WHERE user_id=' + literal(owner) + '::uuid)', 'one_row_' + suffix)
            require(count == 1, 'one_durable_command')
            result['cases'].append({'id': 'commit-divergent-winner' if commit else 'rollback-new-winner',
                'passed': True, 'B_blocked_by_A_observed': True, 'durable_one_row': True,
                'invalid_later_ignored': True, 'all7_winner_exact': True,
                'clock_after_block_lower_bound': None if commit else True,
                'release_clock_lower_bound': lower, 'admitted_at': winner_b['admittedAt'],
                'recent_cutoff': winner_b['recentCutoff']})
    except BaseException as failure:
        result['failure'] = type(failure).__name__
        raise
    finally:
        cleanup = []
        for actor in reversed(actors):
            try:
                cleanup.append(actor.close())
            except BaseException as failure:
                cleanup.append({'actor': actor.name, 'reaped': False, 'readers_stopped': False,
                    'failure': type(failure).__name__})
        reaped = all(item['reaped'] for item in cleanup)
        readers = all(item['readers_stopped'] for item in cleanup)
        result['cleanup'] = {'complete': reaped and readers, 'actors_reaped': reaped,
            'readers_stopped': readers, 'actors': cleanup}
        (output / 'RESULT.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    require(result['cleanup']['complete'] is True, 'actor_cleanup')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bindings-json', required=True)
    parser.add_argument('--output-dir', required=True)
    options = parser.parse_args()
    config = json.loads(Path(options.bindings_json).read_text(encoding='utf-8'))
    config['output_dir'] = options.output_dir
    run(config)
