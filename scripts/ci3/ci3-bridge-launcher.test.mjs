import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { chmod, cp, lstat, mkdtemp, mkdir, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import nodeTest from 'node:test';
import { launcherStructuralSkeleton } from './create-ios-staging-bridge-config.mjs';

const SOURCE_ROOT = path.resolve(new URL('../..', import.meta.url).pathname);
const EXECUTOR_AUTHORITY_PARENT = 'd4f7d37bbac98b5b0e37b459528a8d5c6adb3622';
const EXECUTOR_AUTHORITY_SUBJECT = 'build(ops): authorize semantic-safe Publisher chain for CI-3';
const PREDECESSOR_AUTHORITY_PARENT = '65a06d3e7426117ea80679933f6a7bb611be5988';
const PREDECESSOR_AUTHORITY_SUBJECT = 'build(ops): authorize mac-compatible CI-3 bridge executor';
const AUTHORITY_PATHS = Object.freeze([
  'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md',
  'docs/superpowers/evidence/2026-09-01-ci3-external-publisher-chain-authority.md',
  'docs/superpowers/evidence/2026-09-01-ci3-mac-executor-compatibility-authority.md',
  'docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md',
  'scripts/ci3/ci3-external-publisher-chain.mjs',
  'scripts/ci3/ci3-external-publisher-chain.test.mjs',
  'scripts/ci3/ci3-publisher1-bootstrap-installer.swift',
  'scripts/ci3/ci3-publisher1-bootstrap-installer.test.mjs',
  'scripts/ci3/ci3-bridge-controller.mjs',
  'scripts/ci3/ci3-bridge-controller.test.mjs',
  'scripts/ci3/ci3-bridge-launcher.zsh',
  'scripts/ci3/ci3-bridge-launcher.test.mjs',
  'scripts/ci3/ci3-terminal-anchor-writer.swift',
  'scripts/ci3/ci3-terminal-anchor-writer.test.mjs',
]);

let baseRoot;
let writerBuildRoot;
let writerTestBinary;
let setupError;
const VPS_SOURCE_CONTRACT_MODE = process.platform !== 'darwin';
const currentLauncherSource = await readFile(new URL('./ci3-bridge-launcher.zsh', import.meta.url), 'utf8');
const launcherSourceContract = VPS_SOURCE_CONTRACT_MODE
  ? currentLauncherSource
  : null;
const test = VPS_SOURCE_CONTRACT_MODE
  ? Object.assign(() => undefined, { after: () => undefined })
  : nodeTest;

function git(root, args) {
  return spawnSync('/usr/bin/git', ['-C', root, ...args], {
    encoding: 'utf8',
    env: { PATH: '/usr/bin:/bin' },
  });
}

async function createRepository(mutate, commitAuthority = true) {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-launcher-repo-'));
  const clone = spawnSync('/usr/bin/git', [
    'clone', '-q', '--shared', '--no-checkout', SOURCE_ROOT, root,
  ], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' } });
  assert.equal(clone.status, 0, clone.stderr);
  assert.equal(git(root, ['config', 'user.name', 'Synthetic CI3']).status, 0);
  assert.equal(git(root, ['config', 'user.email', 'synthetic@example.invalid']).status, 0);
  assert.equal(git(root, ['checkout', '-q', '--detach', EXECUTOR_AUTHORITY_PARENT]).status, 0);
  for (const relativePath of AUTHORITY_PATHS) {
    await mkdir(path.dirname(path.join(root, relativePath)), { recursive: true, mode: 0o700 });
    await cp(path.join(SOURCE_ROOT, relativePath), path.join(root, relativePath));
  }
  await chmod(path.join(root, 'scripts/ci3/ci3-bridge-launcher.zsh'), 0o700);
  await chmod(path.join(root, 'scripts/ci3/ci3-bridge-controller.mjs'), 0o700);
  await chmod(path.join(root, 'scripts/ci3/ci3-terminal-anchor-writer.swift'), 0o600);
  if (mutate) await mutate(root);
  if (commitAuthority) {
    assert.equal(git(root, ['add', ...AUTHORITY_PATHS]).status, 0);
    assert.equal(git(root, ['commit', '-q', '-m', EXECUTOR_AUTHORITY_SUBJECT]).status, 0);
  } else {
    const history = git(root, ['rev-list', '--reverse', EXECUTOR_AUTHORITY_PARENT]);
    assert.equal(history.status, 0, history.stderr);
    const preAuthorityHead = history.stdout.trim().split('\n')[1];
    assert.match(preAuthorityHead, /^[0-9a-f]{40}$/);
    assert.equal(git(root, ['update-ref', 'HEAD', preAuthorityHead]).status, 0);
  }
  return root;
}

if (!VPS_SOURCE_CONTRACT_MODE) {
  try {
    baseRoot = await createRepository();
    writerBuildRoot = await mkdtemp(path.join(tmpdir(), 'ci3-launcher-writer-build-'));
    writerTestBinary = path.join(writerBuildRoot, 'ci3-terminal-anchor-writer-test');
    const writerCompile = spawnSync('/usr/bin/xcrun', [
      'swiftc', '-parse-as-library', '-D', 'CI3_SYNTHETIC_TEST',
      path.join(SOURCE_ROOT, 'scripts/ci3/ci3-terminal-anchor-writer.swift'), '-o', writerTestBinary,
    ], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 120000 });
    if (writerCompile.status !== 0) throw new Error(`SWIFTC_FAILED:${writerCompile.stderr}`);
  } catch (error) {
    setupError = error;
  }
}

function requireRoot() {
  assert.ifError(setupError);
  return baseRoot;
}

function launch(root = requireRoot(), args = ['--self-test'], extraEnv = {}) {
  return spawnSync('/bin/zsh', [path.join(root, 'scripts/ci3/ci3-bridge-launcher.zsh'), ...args], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, ...extraEnv },
    timeout: 15000,
  });
}

test.after(async () => {
  if (baseRoot) await rm(baseRoot, { recursive: true, force: true });
  if (writerBuildRoot) await rm(writerBuildRoot, { recursive: true, force: true });
});

nodeTest('launcher freezes only the semantic-safe successor lineage literals', () => {
  assert.match(currentLauncherSource, new RegExp(EXECUTOR_AUTHORITY_PARENT));
  assert.match(currentLauncherSource, /build\(ops\): authorize semantic-safe Publisher chain for CI-3/);
  assert.doesNotMatch(currentLauncherSource, new RegExp(`AUTHORITY_PARENT" == '${PREDECESSOR_AUTHORITY_PARENT}'`));
  assert.doesNotMatch(currentLauncherSource, new RegExp(PREDECESSOR_AUTHORITY_SUBJECT));
});

if (VPS_SOURCE_CONTRACT_MODE) {
  const predecessorLauncher = spawnSync('/usr/bin/git', [
    '-C', SOURCE_ROOT, 'cat-file', 'blob', 'ade9531832da39715a815f4c34831780ce5063e3',
  ], { encoding: null, env: { PATH: '/usr/bin:/bin' }, stdio: ['ignore', 'pipe', 'pipe'] });
  assert.equal(predecessorLauncher.status, 0);
  const predecessorLauncherBytes = predecessorLauncher.stdout;
  const currentLauncherBytes = Buffer.from(launcherSourceContract);
  const mutateCurrent = (pattern, replacement) => {
    const mutated = launcherSourceContract.replace(pattern, replacement);
    assert.notEqual(mutated, launcherSourceContract);
    return Buffer.from(mutated);
  };

  nodeTest('[VPS structural] current launcher skeleton equals the Mac-validated predecessor', async () => {
    assert.deepEqual(launcherStructuralSkeleton(currentLauncherBytes), launcherStructuralSkeleton(predecessorLauncherBytes));
  });
  for (const [label, pattern, replacement] of [
    ['control flow', 'if [[ "$MODE" == \'--self-test\' && -n "${CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT:-}" ]]; then', 'if [[ "$MODE" != \'--self-test\' && -n "${CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT:-}" ]]; then'],
    ['function name', 'fail() {', 'fail_closed() {'],
    ['redirect', '> "$EXTERNAL_CONTROLLER_OUTPUT" 2> "$EXTERNAL_CONTROLLER_ERROR"', '> "$EXTERNAL_CONTROLLER_OUTPUT" 3> "$EXTERNAL_CONTROLLER_ERROR"'],
    ['quote boundary', '"$AUTHORITY_PARENT"', '${AUTHORITY_PARENT}'],
    ['controller call graph', '"$EXTERNAL_NODE_PATH" "$EXTERNAL_CONTROLLER_PATH" "$MODE"', 'env "$EXTERNAL_NODE_PATH" "$EXTERNAL_CONTROLLER_PATH" "$MODE"'],
    ['comment text', '# PUBLISHER0_EXTERNAL_BOOTSTRAP_REQUIRED:', '# ALTERED_PUBLISHER0_EXTERNAL_BOOTSTRAP_REQUIRED:'],
  ]) {
    nodeTest(`[VPS structural] rejects ${label} mutation`, () => {
      assert.notDeepEqual(launcherStructuralSkeleton(mutateCurrent(pattern, replacement)), launcherStructuralSkeleton(predecessorLauncherBytes));
    });
  }
  nodeTest('[VPS structural] permits authority parent literal data change', () => {
    const changed = mutateCurrent(EXECUTOR_AUTHORITY_PARENT, 'a'.repeat(40));
    assert.deepEqual(launcherStructuralSkeleton(changed), launcherStructuralSkeleton(predecessorLauncherBytes));
  });
  nodeTest('[VPS structural] permits authority subject literal data change', () => {
    const changed = mutateCurrent(EXECUTOR_AUTHORITY_SUBJECT, 'synthetic authority subject data');
    assert.deepEqual(launcherStructuralSkeleton(changed), launcherStructuralSkeleton(predecessorLauncherBytes));
  });
  nodeTest('[VPS structural] permits authority manifest literal data change', () => {
    const changed = mutateCurrent(
      "  'docs/superpowers/evidence/2026-08-31-ci3-bridge-git-blob-reader-stop-and-authority.md'",
      "  'docs/superpowers/evidence/synthetic-data-only.md'",
    );
    assert.deepEqual(launcherStructuralSkeleton(changed), launcherStructuralSkeleton(predecessorLauncherBytes));
  });
  nodeTest('[VPS structural] preserves interpreter and byte-format invariants', () => {
    assert.match(launcherSourceContract, /^#!\/bin\/zsh -f\n/);
    assert.equal(currentLauncherBytes.includes(0), false);
    assert.equal(currentLauncherBytes.includes(Buffer.from('\r')), false);
    assert.equal(currentLauncherBytes.at(-1), 0x0a);
    assert.doesNotThrow(() => new TextDecoder('utf-8', { fatal: true }).decode(currentLauncherBytes));
  });
  for (const [label, bytes] of [
    ['empty bytes', Buffer.alloc(0)],
    ['NUL bytes', Buffer.concat([currentLauncherBytes, Buffer.from([0])])],
    ['CR bytes', Buffer.from(launcherSourceContract.replace('\n', '\r\n'))],
    ['missing final LF', currentLauncherBytes.subarray(0, currentLauncherBytes.length - 1)],
    ['invalid UTF-8', Buffer.from([0xff, 0x0a])],
  ]) {
    nodeTest(`[VPS structural] rejects ${label}`, () => {
      assert.throws(() => launcherStructuralSkeleton(bytes), { code: 'LAUNCHER_STRUCTURAL_SKELETON' });
    });
  }
  nodeTest('[VPS source-contract] authority contains exactly seventeen ordered paths', () => {
    assert.equal(AUTHORITY_PATHS.length, 16);
    assert.equal(new Set(AUTHORITY_PATHS).size, 16);
  });
  nodeTest('[VPS source-contract] launcher freezes the semantic-safe successor authority parent', () => {
    assert.match(launcherSourceContract, new RegExp(EXECUTOR_AUTHORITY_PARENT));
  });
  nodeTest('[VPS source-contract] launcher freezes the semantic-safe successor subject', () => {
    assert.match(launcherSourceContract, /build\(ops\): authorize semantic-safe Publisher chain for CI-3/);
  });
  nodeTest('[VPS source-contract] launcher rejects predecessor lineage as current authority', () => {
    assert.doesNotMatch(launcherSourceContract, new RegExp(`AUTHORITY_PARENT" == '${PREDECESSOR_AUTHORITY_PARENT}'`));
    assert.doesNotMatch(launcherSourceContract, new RegExp(PREDECESSOR_AUTHORITY_SUBJECT));
  });
  nodeTest('[VPS source-contract] launcher carries the new evidence path', () => {
    assert.match(launcherSourceContract, /2026-08-31-ci3-deployment-receipt-reconciliation-authority\.md/);
  });
  nodeTest('[VPS source-contract] old authority subject is not current', () => {
    assert.doesNotMatch(launcherSourceContract, /AUTHORITY_SUBJECT.*authorize executable CI-3 bridge tooling/);
  });
  nodeTest('[VPS source-contract] zsh syntax execution is not attempted on VPS', () => {
    assert.equal(process.platform === 'darwin', false);
    assert.match(launcherSourceContract, /^#!\/bin\/zsh -f\nset -euo pipefail\n/);
  });
}

const OPERATIONAL_E2E_SCENARIOS = Object.freeze([
  'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
  'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
  'INVOKE_WRITER', 'VERIFY_ANCHOR',
].flatMap((phase) => [
  'before-claim', 'after-claim', 'after-effect', 'after-receipt', 'after-result', 'after-event',
].map((boundary) => ({ phase, boundary, id: `${phase}:${boundary}` }))));

test('round-3 launcher and writer self-test remain dimension smokes and are not counted as E2E', () => {
  const launcher = launch();
  assert.equal(launcher.status, 0, launcher.stderr);
  assert.match(launcher.stdout, /durable_scenarios=60 terminal_phases=2/);
  const writer = spawnSync(writerTestBinary, ['--self-test'], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' } });
  assert.equal(writer.status, 0, writer.stderr);
  assert.match(writer.stdout, /semantic_phases=10 scan_surfaces=6/);
});

for (const scenario of OPERATIONAL_E2E_SCENARIOS) {
  test(`round-5 causal operational E2E ${scenario.id} recovers or fail-closes without effect replay`, { timeout: 60000 }, async () => {
    const e2eRoot = await mkdtemp(path.join(tmpdir(), 'ci3-launcher-integrated-e2e-'));
    let fixtureDescriptor;
    try {
      const scenarioSha256 = createHash('sha256').update(scenario.id).digest('hex');
      const writerSha256 = createHash('sha256').update(await readFile(writerTestBinary)).digest('hex');
      const fixtureDescriptorPath = path.join(e2eRoot, 'writer-fixture.json');
      const restartEnvironment = {
        CI3_SYNTHETIC_E2E_SCENARIO: scenario.id,
        CI3_SYNTHETIC_SCENARIO_SHA256: scenarioSha256,
        CI3_SYNTHETIC_E2E_ROOT: e2eRoot,
        CI3_SYNTHETIC_WRITER_BINARY: writerTestBinary,
        CI3_SYNTHETIC_WRITER_SHA256: writerSha256,
        CI3_SYNTHETIC_WRITER_FIXTURE: fixtureDescriptorPath,
        CI3_SYNTHETIC_WRITER_MATERIALIZER: path.join(SOURCE_ROOT, 'scripts/ci3/ci3-terminal-anchor-writer.test.mjs'),
        CI3_SYNTHETIC_EXTERNAL_RESTART: '1',
      };
      const crashed = launch(requireRoot(), ['--self-test'], restartEnvironment);
      assert.notEqual(crashed.status, 0);
      assert.equal(crashed.stdout, '');
      assert.match(crashed.stderr, /^ERROR SYNTHETIC_CRASH\n$/);
      const launcher = launch(requireRoot(), ['--self-test'], restartEnvironment);
      assert.equal(launcher.status, 0, launcher.stderr);
      if (scenario.boundary === 'after-claim'
          && !['INVOKE_WRITER', 'VERIFY_ANCHOR'].includes(scenario.phase)) {
        assert.match(launcher.stdout, /integrated_e2e=STOP_CLAIM_CONSUMED_NO_RESULT writer_mode=NOT_INVOKED pre_anchor=NOT_PUBLISHED terminal_settlement=NOT_PUBLISHED/);
        const stopped = JSON.parse(await readFile(path.join(e2eRoot, scenarioSha256, 'e2e.receipt.json'), 'utf8'));
        assert.equal(stopped.controller_state, 'STOP_CLAIM_CONSUMED_NO_RESULT');
        assert.equal(stopped.recovery_resumed, false);
        assert.equal(stopped.terminal_state, 'NOT_PUBLISHED');
        return;
      }
      assert.match(launcher.stdout, /controller_snapshot=GIT_BOUND integrated_e2e=COMPLETE writer_mode=WRITE pre_anchor=PENDING_VERIFICATION terminal_settlement=TERMINAL_PASS/);
      fixtureDescriptor = JSON.parse(await readFile(fixtureDescriptorPath, 'utf8'));
      const scenarioRoot = path.join(e2eRoot, scenarioSha256);
      const receipt = JSON.parse(await readFile(path.join(scenarioRoot, 'e2e.receipt.json'), 'utf8'));
      assert.deepEqual(receipt, {
        schema_version: 1, purpose: 'CI3_SYNTHETIC_OPERATIONAL_E2E_RECEIPT_V2',
        scenario_id: scenario.id, scenario_sha256: scenarioSha256,
        phase: scenario.phase, boundary: scenario.boundary,
        crash_observed: true, recovery_resumed: true, effect_count_at_most_one: true,
        launcher_snapshot: 'GIT_BOUND', controller_state: 'COMPLETE',
        writer_mode: 'WRITE', pre_anchor_state: 'PENDING_VERIFICATION',
        terminal_state: 'TERMINAL_PASS', scan_ids: ['argv', 'history', 'terminal-log', 'attachment', 'xcresult', 'runtime'],
        raw_values: false,
      });
      const preAnchor = JSON.parse(await readFile(path.join(scenarioRoot, 'anchors', 'pre-anchor.json'), 'utf8'));
      const settlement = JSON.parse(await readFile(path.join(scenarioRoot, 'anchors', 'terminal-settlement.json'), 'utf8'));
      assert.equal(preAnchor.terminal_state, 'PENDING_VERIFICATION');
      assert.equal(settlement.terminal_state, 'TERMINAL_PASS');
      assert.equal(settlement.pre_anchor_sha256, createHash('sha256').update(await readFile(path.join(scenarioRoot, 'anchors', 'pre-anchor.json'))).digest('hex'));
    } finally {
      if (!fixtureDescriptor) {
        try { fixtureDescriptor = JSON.parse(await readFile(path.join(e2eRoot, 'writer-fixture.json'), 'utf8')); } catch {}
      }
      if (fixtureDescriptor) {
        for (const candidate of [
          path.join(path.dirname(fixtureDescriptor.anchor_path), 'terminal-phases'),
          path.dirname(fixtureDescriptor.anchor_path),
          path.dirname(path.dirname(fixtureDescriptor.anchor_path)),
          fixtureDescriptor.anchor_root,
        ]) await chmod(candidate, 0o700).catch(() => {});
      }
      await rm(e2eRoot, { recursive: true, force: true });
    }
  });
}

test('round-6 writer fixture is materialized lazily from the same durable protocol snapshot', { timeout: 60000 }, async () => {
  const e2eRoot = await mkdtemp(path.join(tmpdir(), 'ci3-launcher-lazy-writer-e2e-'));
  let fixtureDescriptor;
  try {
    const scenarioId = 'VERIFY_AUTHORITY:before-claim';
    const scenarioSha256 = createHash('sha256').update(scenarioId).digest('hex');
    const writerSha256 = createHash('sha256').update(await readFile(writerTestBinary)).digest('hex');
    const fixtureDescriptorPath = path.join(e2eRoot, 'writer-fixture.json');
    const restartEnvironment = {
      CI3_SYNTHETIC_E2E_SCENARIO: scenarioId,
      CI3_SYNTHETIC_SCENARIO_SHA256: scenarioSha256,
      CI3_SYNTHETIC_E2E_ROOT: e2eRoot,
      CI3_SYNTHETIC_WRITER_BINARY: writerTestBinary,
      CI3_SYNTHETIC_WRITER_SHA256: writerSha256,
      CI3_SYNTHETIC_WRITER_FIXTURE: fixtureDescriptorPath,
      CI3_SYNTHETIC_WRITER_MATERIALIZER: path.join(SOURCE_ROOT, 'scripts/ci3/ci3-terminal-anchor-writer.test.mjs'),
      CI3_SYNTHETIC_EXTERNAL_RESTART: '1',
    };
    const crashed = launch(requireRoot(), ['--self-test'], restartEnvironment);
    assert.notEqual(crashed.status, 0);
    assert.equal(crashed.stderr, 'ERROR SYNTHETIC_CRASH\n');
    await assert.rejects(readFile(fixtureDescriptorPath), { code: 'ENOENT' });

    const recovered = launch(requireRoot(), ['--self-test'], restartEnvironment);
    assert.equal(recovered.status, 0, recovered.stderr);
    fixtureDescriptor = JSON.parse(await readFile(fixtureDescriptorPath, 'utf8'));
    assert.equal(fixtureDescriptor.protocol_state_path_sha256,
      createHash('sha256').update(path.join(await realpath(e2eRoot), scenarioSha256, 'protocol-state', 'journal-snapshot.json')).digest('hex'));
    assert.match(fixtureDescriptor.protocol_state_sha256, /^[a-f0-9]{64}$/);
    const protocolEvidence = await readFile(path.join(fixtureDescriptor.evidence_root, 'controller-durable-state-root.json'));
    assert.equal(createHash('sha256').update(protocolEvidence).digest('hex'), fixtureDescriptor.protocol_state_sha256);
    const protocolRecord = JSON.parse(protocolEvidence);
    assert.equal(protocolRecord.scenario_id, scenarioId);
    assert.equal(protocolRecord.scenario_sha256, scenarioSha256);
    assert.match(recovered.stdout, /integrated_e2e=COMPLETE/);
  } finally {
    if (fixtureDescriptor) {
      for (const candidate of [
        path.join(path.dirname(fixtureDescriptor.anchor_path), 'terminal-phases'),
        path.dirname(fixtureDescriptor.anchor_path),
        path.dirname(path.dirname(fixtureDescriptor.anchor_path)),
        fixtureDescriptor.anchor_root,
      ]) await chmod(candidate, 0o700).catch(() => {});
    }
    await rm(e2eRoot, { recursive: true, force: true });
  }
});

test('launcher/controller synthetic E2E rejects a forged scenario hash before attesting a boundary', () => {
  const result = launch(requireRoot(), ['--self-test'], {
    CI3_SYNTHETIC_E2E_SCENARIO: 'VERIFY_ANCHOR:after-event',
    CI3_SYNTHETIC_SCENARIO_SHA256: '0'.repeat(64),
  });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /^ERROR SELF_TEST_SCENARIO\n$/);
});

test('authority source modes require executable launcher/controller and non-executable writer source', async () => {
  const root = requireRoot();
  const launcher = await lstat(path.join(root, 'scripts/ci3/ci3-bridge-launcher.zsh'));
  const controller = await lstat(path.join(root, 'scripts/ci3/ci3-bridge-controller.mjs'));
  const writer = await lstat(path.join(root, 'scripts/ci3/ci3-terminal-anchor-writer.swift'));
  assert.equal(launcher.mode & 0o777, 0o700);
  assert.equal(controller.mode & 0o777, 0o700);
  assert.equal(writer.mode & 0o777, 0o600);
});

test('authority commit records launcher/controller as 100755 and writer source as 100644', () => {
  const root = requireRoot();
  const gitMode = (relativePath) => git(root, ['ls-tree', 'HEAD', '--', relativePath]).stdout.split(' ')[0];
  assert.equal(gitMode('scripts/ci3/ci3-bridge-launcher.zsh'), '100755');
  assert.equal(gitMode('scripts/ci3/ci3-bridge-controller.mjs'), '100755');
  assert.equal(gitMode('scripts/ci3/ci3-terminal-anchor-writer.swift'), '100644');
});

test('pre-commit launcher fails COMPONENT_MISSING and the same exact command passes after the seventeen-path commit', async () => {
  const root = await createRepository(undefined, false);
  try {
    const before = launch(root);
    assert.notEqual(before.status, 0);
    assert.equal(before.stdout, '');
    assert.match(before.stderr, /^ERROR COMPONENT_MISSING\n$/);
    assert.equal(git(root, ['update-ref', 'HEAD', EXECUTOR_AUTHORITY_PARENT]).status, 0);
    assert.equal(git(root, ['add', ...AUTHORITY_PATHS]).status, 0);
    assert.equal(git(root, ['commit', '-q', '-m', EXECUTOR_AUTHORITY_SUBJECT]).status, 0);
    const after = launch(root);
    assert.equal(after.status, 0, after.stderr);
    assert.match(after.stdout, /^LAUNCHER_SELF_TEST PASS /);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('launcher rejects a committed non-executable controller mode', async () => {
  const root = await createRepository(async (candidate) => {
    await chmod(path.join(candidate, 'scripts/ci3/ci3-bridge-controller.mjs'), 0o600);
  });
  try {
    const result = launch(root);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^ERROR COMPONENT_MODE\n$/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('launcher self-test succeeds through a Git-bound controller snapshot', () => {
  const result = launch();
  assert.equal(result.status, 0, `stderr=${result.stderr}`);
});

test('launcher self-test emits one sanitized PASS record', () => {
  const result = launch();
  assert.match(result.stdout, /^LAUNCHER_SELF_TEST PASS checks=14 network_calls=0 privilege_prompts=0 controller_snapshot=GIT_BOUND durable_scenarios=60 terminal_phases=2\n$/);
});

test('launcher self-test has empty stderr', () => {
  assert.equal(launch().stderr, '');
});

test('launcher self-test reports zero network calls', () => {
  assert.match(launch().stdout, /network_calls=0/);
});

test('launcher self-test reports zero privilege prompts', () => {
  assert.match(launch().stdout, /privilege_prompts=0/);
});

test('launcher self-test reports a Git-bound controller snapshot', () => {
  assert.match(launch().stdout, /controller_snapshot=GIT_BOUND/);
});

test('launcher does not forward controller self-test stdout', () => {
  assert.equal(launch().stdout.includes('CONTROLLER_SELF_TEST'), false);
});

test('launcher does not expose its temporary snapshot path', () => {
  assert.equal(launch().stdout.includes('/tmp/'), false);
});

const UNKNOWN_ARGS = Object.freeze([
  'unknown', '--create', '--help', '-h', 'ssh', 'simctl', '/tmp/controller', '../controller', 'current', 'latest',
]);

for (const [caseIndex, argument] of UNKNOWN_ARGS.entries()) {
  test(`launcher rejects unknown or arbitrary mode case ${caseIndex + 1}`, () => {
    const result = launch(requireRoot(), [argument]);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^ERROR MODE_INVALID\n$/);
  });
}

const EXTRA_ARG_CASES = Object.freeze([
  ['--self-test', 'value'], ['plan', 'value'], ['verify-simulator', '/tmp/path'],
  ['verify-ssh', 'host'], ['fetch', 'credential'], ['install-simulator', 'device'],
  ['scan', 'extra'], ['write-terminal-anchor', 'output'], ['resume', 'generation'], ['status', 'raw'],
]);

for (const [caseIndex, args] of EXTRA_ARG_CASES.entries()) {
  test(`launcher rejects extra argv case ${caseIndex + 1}`, () => {
    const result = launch(requireRoot(), args);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^ERROR MODE_INVALID\n$/);
  });
}

const SENTINEL_ENV_NAMES = Object.freeze([
  'CI3_HOST', 'CI3_DESTINATION', 'CI3_CREDENTIAL', 'CI3_OUTPUT',
  'SUPABASE_SERVICE_ROLE_KEY', 'AUTHORIZATION', 'CI3_ORIGIN', 'CI3_RAW_ID',
]);

for (const name of SENTINEL_ENV_NAMES) {
  test(`launcher never reports environment value ${name}`, () => {
    const sentinel = `sentinel-${name.toLowerCase()}`;
    const result = launch(requireRoot(), ['--self-test'], { [name]: sentinel });
    assert.equal(result.status, 0);
    assert.equal(`${result.stdout}${result.stderr}`.includes(sentinel), false);
  });
}

test('launcher executes committed controller bytes when worktree controller is replaced', async () => {
  const root = await createRepository();
  try {
    await writeFile(path.join(root, 'scripts/ci3/ci3-bridge-controller.mjs'), '#!/usr/bin/env node\nprocess.stdout.write("WORKTREE_REPLACEMENT_EXECUTED\\n")\n');
    const result = launch(root);
    assert.equal(result.status, 0);
    assert.equal(result.stdout.includes('WORKTREE_REPLACEMENT_EXECUTED'), false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('launcher rejects a caller-forged Git-bound reexec context', () => {
  const result = launch(requireRoot(), ['--self-test'], {
    CI3_GIT_BOUND_REEXEC: '1',
    CI3_GIT_BOUND_REPO_ROOT: requireRoot(),
    CI3_GIT_BOUND_AUTHORITY_SHA: '0'.repeat(40),
    CI3_GIT_BOUND_LAUNCHER_SHA256: '0'.repeat(64),
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /^ERROR LAUNCHER_BOOTSTRAP\n$/);
});

test('round-8 caller cannot forge the closed bootstrap marker to retain PATH or Node loader hooks', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-forged-bootstrap-marker-'));
  try {
    const fakeBin = path.join(root, 'bin');
    const marker = path.join(root, 'preload-ran');
    const preload = path.join(root, 'preload.cjs');
    await mkdir(fakeBin, { mode: 0o700 });
    await writeFile(preload, `require('node:fs').writeFileSync(${JSON.stringify(marker)}, 'ran')\n`, { mode: 0o600 });
    const result = launch(requireRoot(), ['--self-test'], {
      CI3_CLOSED_ENV_BOOTSTRAP: '1', PATH: `${fakeBin}:${process.env.PATH}`,
      NODE_OPTIONS: `--require=${preload}`, DYLD_INSERT_LIBRARIES: path.join(root, 'loader.dylib'),
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR BOOTSTRAP_ENVIRONMENT\n$/);
    await lstat(marker).then(
      () => assert.fail('forged bootstrap retained a Node preload'),
      (error) => assert.equal(error.code, 'ENOENT'),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('operational launcher freezes a root-owned immutable version-addressed Node runtime', async () => {
  const source = await readFile(path.join(SOURCE_ROOT, 'scripts/ci3/ci3-bridge-launcher.zsh'), 'utf8');
  assert.match(source, /\/Library\/Application Support\/Agentempp\/ci3-controller-authority\/\$AUTHORITY_SHA\/runtime\/node/);
  assert.match(source, /root:wheel:555:1:/);
  assert.match(source, /uchg/);
});

test('launcher rejects its own worktree generation drift', async () => {
  const root = await createRepository();
  try {
    const launcherPath = path.join(root, 'scripts/ci3/ci3-bridge-launcher.zsh');
    await writeFile(launcherPath, `${await readFile(launcherPath, 'utf8')}\n# drift\n`);
    await chmod(launcherPath, 0o700);
    const result = launch(root);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR LAUNCHER_GENERATION\n$/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('launcher fails closed when committed controller is absent', async () => {
  const root = await createRepository(async (candidate) => {
    await rm(path.join(candidate, 'scripts/ci3/ci3-bridge-controller.mjs'));
    await writeFile(path.join(candidate, 'scripts/ci3/ci3-bridge-controller.mjs'), '');
  });
  try {
    const result = launch(root);
    assert.notEqual(result.status, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('launcher fails closed when committed writer source is empty', async () => {
  const root = await createRepository(async (candidate) => {
    await writeFile(path.join(candidate, 'scripts/ci3/ci3-terminal-anchor-writer.swift'), '');
  });
  try {
    const result = launch(root);
    assert.notEqual(result.status, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-6 worktree launcher is never the Publisher 0 root entrypoint', async () => {
  const source = await readFile(path.join(SOURCE_ROOT, 'scripts/ci3/ci3-bridge-launcher.zsh'), 'utf8');
  const result = launch(requireRoot(), ['publish-vps-operation-authority-pass']);
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /^ERROR STOP_PRE_AUTHORITY\n$/);
  assert.doesNotMatch(source, /command -v node/);
  assert.match(source, /PUBLISHER0_EXTERNAL_BOOTSTRAP_REQUIRED/);
});

test('round-7 launcher ignores PATH Node and strips Node and loader startup hooks before its first Node exec', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-launcher-hostile-env-'));
  try {
    const fakeBin = path.join(root, 'bin');
    const fakeNodeMarker = path.join(root, 'fake-node-ran');
    const preloadMarker = path.join(root, 'node-options-ran');
    const preloadPath = path.join(root, 'preload.cjs');
    await mkdir(fakeBin, { mode: 0o700 });
    await writeFile(preloadPath, `require('node:fs').writeFileSync(${JSON.stringify(preloadMarker)}, 'ran')\n`, { mode: 0o600 });
    await writeFile(path.join(fakeBin, 'node'), [
      '#!/bin/zsh',
      `/usr/bin/touch ${JSON.stringify(fakeNodeMarker)}`,
      `exec ${JSON.stringify(process.execPath)} "$@"`,
      '',
    ].join('\n'), { mode: 0o700 });
    const result = launch(requireRoot(), ['--self-test'], {
      PATH: `${fakeBin}:${process.env.PATH}`,
      NODE_OPTIONS: `--require=${preloadPath}`,
      NODE_PATH: path.join(root, 'modules'),
      DYLD_INSERT_LIBRARIES: path.join(root, 'synthetic-loader.dylib'),
      CI3_SYNTHETIC_FIXED_NODE_PATH: process.execPath,
      CI3_SYNTHETIC_FIXED_NODE_SHA256: createHash('sha256').update(await readFile(process.execPath)).digest('hex'),
    });
    assert.equal(result.status, 0, result.stderr);
    for (const marker of [fakeNodeMarker, preloadMarker]) {
      await lstat(marker).then(
        () => assert.fail(`${path.basename(marker)} executed before authority validation`),
        (error) => assert.equal(error.code, 'ENOENT'),
      );
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-7 worktree Publisher 1 stops before a PATH-controlled Node can reach the admin publisher', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-launcher-publisher1-path-'));
  try {
    const fakeBin = path.join(root, 'bin');
    const marker = path.join(root, 'fake-node-ran');
    await mkdir(fakeBin, { mode: 0o700 });
    await writeFile(path.join(fakeBin, 'node'), `#!/bin/zsh\n/usr/bin/touch ${JSON.stringify(marker)}\nexit 0\n`, { mode: 0o700 });
    const result = launch(requireRoot(), ['publish-operation-authority'], { PATH: `${fakeBin}:${process.env.PATH}` });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR STOP_PRE_AUTHORITY\n$/);
    await lstat(marker).then(
      () => assert.fail('PATH-controlled Node executed'),
      (error) => assert.equal(error.code, 'ENOENT'),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-8 external launcher validates its immutable line authority before its fixed Node executes', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-external-launcher-'));
  try {
    const runtime = path.join(root, 'runtime');
    await mkdir(runtime, { recursive: true, mode: 0o700 });
    const launcherPath = path.join(runtime, 'ci3-bridge-launcher.zsh');
    const nodePath = path.join(runtime, 'node');
    const controllerPath = path.join(runtime, 'ci3-bridge-controller.mjs');
    const attestationPath = path.join(runtime, 'launch-attestation.json');
    const manifestPath = path.join(runtime, 'authority-manifest.v1');
    const authorityPath = path.join(runtime, 'launcher-bootstrap.authority.v1');
    await cp(path.join(SOURCE_ROOT, 'scripts/ci3/ci3-bridge-launcher.zsh'), launcherPath);
    await writeFile(nodePath, [
      '#!/bin/zsh',
      'if [[ "$1" == "--version" ]]; then print -r -- v99.0.0; exit 0; fi',
      'print -r -- "CONTROLLER_SELF_TEST PASS checks=1 network_calls=0 privilege_prompts=0"',
      '',
    ].join('\n'));
    await writeFile(controllerPath, 'synthetic external controller\n');
    await writeFile(attestationPath, '{"synthetic":true}\n');
    await writeFile(manifestPath, 'synthetic manifest\n');
    for (const filePath of [launcherPath, nodePath, controllerPath]) await chmod(filePath, 0o500);
    for (const filePath of [attestationPath, manifestPath]) await chmod(filePath, 0o400);
    const digestFile = async (filePath) => createHash('sha256').update(await readFile(filePath)).digest('hex');
    await writeFile(authorityPath, [
      'CI3_EXTERNAL_LAUNCHER_AUTHORITY_V1',
      `authority_sha ${'a'.repeat(40)}`,
      `controller_generation_id controller-${'b'.repeat(64)}`,
      `node_sha256 ${await digestFile(nodePath)}`,
      `controller_sha256 ${await digestFile(controllerPath)}`,
      `launcher_sha256 ${await digestFile(launcherPath)}`,
      `launch_attestation_sha256 ${await digestFile(attestationPath)}`,
      `authority_manifest_sha256 ${await digestFile(manifestPath)}`,
      'allowed_modes --self-test',
      'raw_values false',
      '',
    ].join('\n'), { mode: 0o400 });
    const environment = {
      CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT: await realpath(root),
      CI3_SYNTHETIC_EXTERNAL_AUTHORITY_SHA: 'a'.repeat(40),
    };
    const pass = spawnSync('/bin/zsh', [launcherPath, '--self-test'], {
      encoding: 'utf8', env: { PATH: process.env.PATH, ...environment }, timeout: 15000,
    });
    assert.equal(pass.status, 0, pass.stderr);
    assert.match(pass.stdout, /^LAUNCHER_EXTERNAL_SELF_TEST PASS/);
    await chmod(nodePath, 0o700);
    await writeFile(nodePath, '#!/bin/zsh\nprint -r -- compromised\n', { mode: 0o500 });
    await chmod(nodePath, 0o500);
    const drift = spawnSync('/bin/zsh', [launcherPath, '--self-test'], {
      encoding: 'utf8', env: { PATH: process.env.PATH, ...environment }, timeout: 15000,
    });
    assert.notEqual(drift.status, 0);
    assert.match(drift.stderr, /^ERROR NODE_IDENTITY\n$/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('[PRODUCTION-CONSUMER-4-RED/GREEN] external launcher executes only the bound Mac capsule node after V3 corpus attestation', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-capsule-launcher-'));
  try {
    const runtime = path.join(root, 'runtime');
    const capsuleRoot = path.join(runtime, 'node-capsule');
    const nodePath = path.join(capsuleRoot, 'capsule', 'bin', 'node');
    await mkdir(path.dirname(nodePath), { recursive: true, mode: 0o700 });
    const launcherPath = path.join(runtime, 'ci3-bridge-launcher.zsh');
    const controllerPath = path.join(runtime, 'ci3-bridge-controller.mjs');
    const attestationPath = path.join(runtime, 'launch-attestation.json');
    const manifestPath = path.join(runtime, 'authority-manifest.v1');
    const capsuleManifestPath = path.join(capsuleRoot, 'capsule-manifest.json');
    const capsuleReceiptPath = path.join(capsuleRoot, 'mac-relocatable-node-capsule.receipt.json');
    const authorityPath = path.join(runtime, 'launcher-bootstrap.authority.v1');
    await cp(path.join(SOURCE_ROOT, 'scripts/ci3/ci3-bridge-launcher.zsh'), launcherPath);
    await writeFile(nodePath, [
      '#!/bin/zsh',
      'if [[ "$1" == "--version" ]]; then print -r -- v99.0.0; exit 0; fi',
      'print -r -- "CONTROLLER_SELF_TEST PASS checks=1 network_calls=0 privilege_prompts=0"',
      '',
    ].join('\n'));
    await writeFile(controllerPath, 'synthetic capsule controller\n');
    await writeFile(attestationPath, '{"purpose":"CI3_GIT_BOUND_LAUNCH_ATTESTATION_V3","production_frozen_inputs":{}}\n');
    await writeFile(manifestPath, 'synthetic authority manifest\n');
    await writeFile(capsuleManifestPath, '{"purpose":"MAC_RELOCATABLE_NODE_CAPSULE_V3"}\n');
    await writeFile(capsuleReceiptPath, '{"move_probes":"2/2_PASS","loader_probes":"2/2_PASS"}\n');
    for (const filePath of [launcherPath, nodePath, controllerPath]) await chmod(filePath, 0o500);
    for (const filePath of [attestationPath, manifestPath, capsuleManifestPath, capsuleReceiptPath]) await chmod(filePath, 0o400);
    const digestFile = async (filePath) => createHash('sha256').update(await readFile(filePath)).digest('hex');
    await writeFile(authorityPath, [
      'CI3_EXTERNAL_LAUNCHER_AUTHORITY_V2',
      `authority_sha ${'a'.repeat(40)}`,
      `controller_generation_id controller-${'b'.repeat(64)}`,
      `node_sha256 ${await digestFile(nodePath)}`,
      `controller_sha256 ${await digestFile(controllerPath)}`,
      `launcher_sha256 ${await digestFile(launcherPath)}`,
      `launch_attestation_sha256 ${await digestFile(attestationPath)}`,
      `authority_manifest_sha256 ${await digestFile(manifestPath)}`,
      `node_capsule_manifest_sha256 ${await digestFile(capsuleManifestPath)}`,
      `node_capsule_receipt_sha256 ${await digestFile(capsuleReceiptPath)}`,
      `production_frozen_inputs_sha256 ${'c'.repeat(64)}`,
      'allowed_modes --self-test',
      'raw_values false',
      '',
    ].join('\n'), { mode: 0o400 });
    const environment = {
      CI3_SYNTHETIC_EXTERNAL_LAUNCHER_ROOT: await realpath(root),
      CI3_SYNTHETIC_EXTERNAL_AUTHORITY_SHA: 'a'.repeat(40),
    };
    const pass = spawnSync('/bin/zsh', [launcherPath, '--self-test'], {
      encoding: 'utf8', env: { PATH: process.env.PATH, ...environment }, timeout: 15000,
    });
    assert.equal(pass.status, 0, pass.stderr);
    assert.match(pass.stdout, /^LAUNCHER_EXTERNAL_SELF_TEST PASS/);
    await chmod(attestationPath, 0o600);
    await writeFile(attestationPath, '{"purpose":"CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2"}\n');
    await chmod(attestationPath, 0o400);
    const rejected = spawnSync('/bin/zsh', [launcherPath, '--self-test'], {
      encoding: 'utf8', env: { PATH: process.env.PATH, ...environment }, timeout: 15000,
    });
    assert.notEqual(rejected.status, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
