#!/usr/bin/env python3
"""Exact harness ownership regression, to be run by Root in isolated Python.
No PostgreSQL/CLI child is created. The actual driver run/finally is exercised
with FakeActor; a real INT/TERM is delivered at the caller opcode after the
constructor returns and before registry append, outside constructor cleanup.
Run unchanged against old9eae (expected causal failures) and new R3 (expected PASS).
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import sys
import types


def run_case(driver_path, case_dir, target_actor, signum):
    source = driver_path.read_text(encoding='utf-8')
    module = types.ModuleType('s7_driver_interrupt_regression')
    exec(compile(source, str(driver_path), 'exec'), module.__dict__)
    allocated = []
    closed = []
    armed_frame = None
    fired_boundary = None
    previous_trace = sys.gettrace()
    original_int = signal.getsignal(signal.SIGINT)
    original_term = signal.getsignal(signal.SIGTERM)

    def caller_interrupt(_signum, _frame):
        raise InterruptedError('S7_TEST_REAL_SYNTHETIC_SIGNAL')

    class FakeActor:
        def __init__(self, name, _config, _output):
            self.name = name
            allocated.append(self)
            # Returns normally. No injected exception inside constructor cleanup.

        def close(self):
            if self.name not in closed:
                closed.append(self.name)
            return {'actor': self.name, 'reaped': True, 'readers_stopped': True, 'exit_code': 0}

    def trace_boundary(frame, event, _arg):
        nonlocal armed_frame, fired_boundary
        if event == 'return' and frame.f_code is FakeActor.__init__.__code__:
            if frame.f_locals['name'] == target_actor:
                armed_frame = frame.f_back
                armed_frame.f_trace = trace_boundary
                armed_frame.f_trace_opcodes = True
        elif event == 'opcode' and frame is armed_frame:
            # This opcode is reached only AFTER the constructor CALL returned.
            # Old run has not appended a/b; new helper still defers INT/TERM.
            armed_frame = None
            fired_boundary = {'event': 'caller-opcode-after-constructor-return',
                'function': frame.f_code.co_name, 'offset': frame.f_lasti}
            os.kill(os.getpid(), signum)
        return trace_boundary

    module.Actor = FakeActor
    config = {'root_reviewed': True, 'output_dir': str(case_dir), 'psql': str(driver_path),
        # This file identity passes the inert configuration gate only. FakeActor
        # never runs it as a program or connects a database.
        'psql_sha256': hashlib.sha256(driver_path.read_bytes()).hexdigest(),
        'socket': '/private/tmp/performe-c59a2-pg.S7_FAKE_NO_SERVER', 'port': 55493,
        'user': 'c59a2_local_admin', 'database': 'postgres', **module.EXPECTED_IDS}
    interrupted = False
    try:
        signal.signal(signal.SIGINT, caller_interrupt)
        signal.signal(signal.SIGTERM, caller_interrupt)
        sys.settrace(trace_boundary)
        try:
            module.run(config)
        except InterruptedError:
            interrupted = True
        restored = signal.getsignal(signal.SIGINT) is caller_interrupt and signal.getsignal(signal.SIGTERM) is caller_interrupt
    finally:
        sys.settrace(previous_trace)
        signal.signal(signal.SIGINT, original_int)
        signal.signal(signal.SIGTERM, original_term)
    receipt_path = case_dir / 'RESULT.json'
    receipt = json.loads(receipt_path.read_text(encoding='utf-8')) if receipt_path.exists() else None
    expected_names = ['A'] if target_actor == 'A' else ['A', 'B']
    registry_closed = [] if receipt is None else [actor['actor'] for actor in receipt['cleanup']['actors']]
    passed = (interrupted and restored and fired_boundary is not None and [actor.name for actor in allocated] == expected_names
        and set(closed) == set(expected_names) and set(registry_closed) == set(expected_names)
        and receipt is not None and receipt['failure'] == 'InterruptedError'
        and receipt['cleanup']['complete'] is True and receipt['cleanup']['actors_reaped'] is True
        and receipt['cleanup']['readers_stopped'] is True)
    return {'case': target_actor + '-' + signal.Signals(signum).name, 'passed': passed,
        'allocation_before_registry': [actor.name for actor in allocated], 'actually_closed': closed,
        'receipt_registry': registry_closed, 'interrupted': interrupted, 'caller_handlers_restored': restored,
        'signal_boundary': fired_boundary,
        'oracle': 'every allocated Actor must be in real driver finally cleanup before complete=true'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--driver-path', required=True)
    parser.add_argument('--output-dir', required=True)
    options = parser.parse_args()
    driver_path = Path(options.driver_path).resolve(strict=True)
    output = Path(options.output_dir)
    output.mkdir(parents=True, exist_ok=False)
    cases = [run_case(driver_path, output / (target + '-' + signal.Signals(signum).name), target, signum)
        for target in ['A', 'B'] for signum in [signal.SIGINT, signal.SIGTERM]]
    result = {'driver_sha256': hashlib.sha256(driver_path.read_bytes()).hexdigest(),
        'real_database_or_child_process': False, 'cases': cases, 'passed': all(case['passed'] for case in cases)}
    (output / 'REGRESSION-RESULT.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))
    raise SystemExit(0 if result['passed'] else 1)
