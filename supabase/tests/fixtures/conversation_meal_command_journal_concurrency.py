"""Bounded real-PG journal races. Import is inert; no PG/cloud lifecycle.

Call run(config) only after an external owned-local-target guard. config supplies
psql_args, subprocess_env and ownership_verified; credentials stay in memory.
Every persisted synthetic fixture is removed in finally; failures remain failures.
"""
import json
import queue
import subprocess
import threading
import time

OWNER = 'c3b00000-0000-4000-8000-000000000001'
COMMAND = 'c3b00000-0000-4000-8000-000000000002'


def require(value, label):
    if value is not True:
        raise AssertionError('JOURNAL_RACE:' + label)


def lit(value):
    return "'" + str(value).replace("'", "''") + "'"


class Actor:
    def __init__(self, config):
        self.process = subprocess.Popen(config['psql_args'], env=config['subprocess_env'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1)
        self.lines = queue.Queue()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.counter = 0
        self.pid = self.query('pg_backend_pid()')
        self.command("SET statement_timeout='8s'; SET lock_timeout='6s'; SET request.jwt.claims='{\"role\":\"service_role\"}'")

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line.strip())
        self.lines.put(None)

    def send(self, expression):
        self.counter += 1
        marker = str(self.counter)
        self.process.stdin.write("SELECT json_build_object('marker'," + lit(marker) + ",'value',(" + expression + '))::text;\n')
        self.process.stdin.flush()
        return marker

    def receive(self, marker):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            line = self.lines.get(timeout=max(.01, deadline-time.monotonic()))
            if line is None:
                raise RuntimeError('psql actor exited')
            if 'ERROR:' in line or 'FATAL:' in line:
                raise RuntimeError(line)
            try:
                value = json.loads(line)
            except ValueError:
                continue
            if isinstance(value, dict) and value.get('marker') == marker:
                return value['value']
        raise TimeoutError('actor response deadline')

    def query(self, expression):
        return self.receive(self.send(expression))

    def command(self, statement):
        self.process.stdin.write(statement + ';\n')
        self.process.stdin.flush()
        return self.query('true')

    def close(self):
        if self.process.poll() is None:
            try:
                self.process.stdin.write('ROLLBACK;\n\\q\n')
                self.process.stdin.flush()
                self.process.wait(timeout=3)
            except (OSError, subprocess.TimeoutExpired):
                self.process.terminate()
                self.process.wait(timeout=3)
        self.reader.join(timeout=1)


def run(config):
    require(config.get('ownership_verified') is True, 'external ownership guard required')
    actors = []
    result = {'cases': [], 'cleanup': False, 'actors_reaped': False}
    admin = Actor(config)
    actors.append(admin)
    a = Actor(config)
    actors.append(a)
    b = Actor(config)
    actors.append(b)
    source = {'command_protocol': 'conversation.command.v1', 'command_id': COMMAND,
        'kind': 'meal.report', 'meal_type': 'almoco',
        'source': {'channel': 'text', 'text': 'Comi 100g de arroz sintetico'}}
    admit = 'public.admit_conversation_meal_command(' + lit(OWNER) + '::uuid,' + lit(json.dumps(source)) + '::jsonb)'
    reset = 'public.reset_user_conversation_atomic(' + lit(OWNER) + '::uuid,true)'
    read = 'public.read_conversation_meal_command(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid)'

    def setup():
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        admin.command("INSERT INTO public.users(id,email,status,timezone) VALUES(" + lit(OWNER) + "::uuid,'journal-race@example.invalid','active','UTC')")

    def blocked(blocker, waiter):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if admin.query(str(blocker.pid) + '=ANY(pg_blocking_pids(' + str(waiter.pid) + '))'):
                return
            time.sleep(.02)
        raise AssertionError('JOURNAL_RACE: actual blocking not observed')

    def counts(expected_ids, expected_sources, expected_candidates):
        actual = admin.query("json_build_array((SELECT count(*) FROM private.conversation_meal_command_ids WHERE user_id=" + lit(OWNER) + "::uuid),(SELECT count(*) FROM private.conversation_meal_command_sources WHERE user_id=" + lit(OWNER) + "::uuid),(SELECT count(*) FROM private.conversation_meal_command_candidates WHERE user_id=" + lit(OWNER) + '::uuid))')
        require(actual == [expected_ids, expected_sources, expected_candidates], 'exact row counts')

    try:
        require(admin.query("NOT EXISTS(SELECT 1 FROM public.users WHERE id=" + lit(OWNER) + '::uuid)'), 'synthetic identity unused')
        setup()
        a.command('BEGIN')
        first = a.query(admit)
        marker = b.send(admit)
        blocked(a, b)
        a.command('COMMIT')
        second = b.receive(marker)
        require(first['action'] == 'admitted' and second['action'] == 'replay' and first['command'] == second['command'], 'concurrent admission exact replay')
        counts(1, 1, 0)
        result['cases'].append('two-session-one-admission')
        h = first['command']['input_hash']
        candidate = {'schema': 'conversation.meal-candidate.v1', 'input_hash': h,
            'status': 'prepared', 'candidate': {'synthetic': True}}
        attach = 'public.attach_conversation_meal_candidate(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid,' + lit(h) + ',' + lit(json.dumps(candidate)) + '::jsonb)'
        a.command('BEGIN')
        first = a.query(attach)
        marker = b.send(attach)
        blocked(a, b)
        a.command('COMMIT')
        second = b.receive(marker)
        require(first['action'] == 'attached' and second == dict(first, action='replay'), 'concurrent candidate exact replay')
        counts(1, 1, 1)
        result['cases'].append('two-session-one-candidate')
        # Reset races are both serialized directions, with commit and rollback.
        for reset_first in [False, True]:
            for rollback in [False, True]:
                setup()
                admitted = admin.query(admit)
                h = admitted['command']['input_hash']
                candidate['input_hash'] = h
                attach = 'public.attach_conversation_meal_candidate(' + lit(OWNER) + '::uuid,' + lit(COMMAND) + '::uuid,' + lit(h) + ',' + lit(json.dumps(candidate)) + '::jsonb)'
                a.command('BEGIN')
                first = a.query(reset if reset_first else attach)
                marker = b.send(attach if reset_first else reset)
                blocked(a, b)
                a.command('ROLLBACK' if rollback else 'COMMIT')
                second = b.receive(marker)
                if reset_first and rollback:
                    require(second['action'] == 'attached' and admin.query(read)['action'] == 'available', 'rollback reset retains admission')
                    counts(1, 1, 1)
                else:
                    if reset_first:
                        require(second == {'action': 'stale_epoch'}, 'reset commit fences waiting candidate')
                    require(admin.query(read) == {'action': 'stale_epoch'}, 'reset scrubs race winner')
                    require(admin.query(admit) == {'action': 'stale_epoch'}, 'old UUID permanently fenced')
                    counts(1, 0, 0)
                result['cases'].append(('reset-before-attach' if reset_first else 'attach-before-reset') + ('-rollback' if rollback else '-commit'))
        # Admissions waiting behind reset cannot rebind old UUIDs either.
        setup()
        admin.query(admit)
        a.command('BEGIN')
        a.query(reset)
        marker = b.send(admit)
        blocked(a, b)
        a.command('COMMIT')
        require(b.receive(marker) == {'action': 'stale_epoch'}, 'reset fences waiting admission')
        counts(1, 0, 0)
        result['cases'].append('reset-before-admission')
    finally:
        for actor in [a, b]:
            actor.close()
        admin.command('DELETE FROM public.users WHERE id=' + lit(OWNER) + '::uuid')
        result['cleanup'] = admin.query("NOT EXISTS(SELECT 1 FROM public.users WHERE id=" + lit(OWNER) + "::uuid) AND NOT EXISTS(SELECT 1 FROM private.conversation_meal_command_ids WHERE user_id=" + lit(OWNER) + '::uuid)')
        admin.close()
        result['actors_reaped'] = all(x.process.poll() is not None and not x.reader.is_alive() for x in actors)
    require(result['cleanup'] and result['actors_reaped'], 'cleanup verified')
    return result
