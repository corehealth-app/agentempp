import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { chmod, link, lstat, mkdtemp, mkdir, open, readFile, readdir, rm, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { PassThrough } from 'node:stream';
import test from 'node:test';

const MODULE_URL = new URL('./create-ios-staging-bridge-config.mjs', import.meta.url);
const GENERATOR_SOURCE = await readFile(MODULE_URL, 'utf8');

let bridge;
let bridgeLoadError;
try {
  bridge = await import(MODULE_URL);
} catch (error) {
  bridgeLoadError = error;
}

function subject() {
  assert.ifError(bridgeLoadError);
  return bridge;
}

function clone(value) {
  return structuredClone(value);
}

function sha(value) {
  return subject().sha256(Buffer.from(value));
}

const canonicalReceiptSourceContracts = Object.freeze([
  ['purpose', /const ENV_RECEIPT_PURPOSE = 'ci3-staging-mobile-bff';/],
  ['legacy key contract', /requireBoolean\(receipt\.legacy_key_contract, true, 'ENV_RECEIPT_STATE'\)/],
  ['local elevated exposure', /receipt\.local_elevated_secret_exposure !== 'no'/],
  ['required permission', /receipt\.required_permission_verified !== 'api_gateway_keys_read'/],
  ['URL classification', /NEXT_PUBLIC_SUPABASE_URL: 'public-configuration'/],
  ['anon classification', /NEXT_PUBLIC_SUPABASE_ANON_KEY: 'legacy-public-project-key'/],
  ['service classification', /SUPABASE_SERVICE_ROLE_KEY: 'legacy-server-sensitive-elevated'/],
]);

for (const [label, pattern] of canonicalReceiptSourceContracts) {
  test(`[ENV-RECEIPT-RED] canonical ${label} is literal`, () => {
    assert.match(GENERATOR_SOURCE, pattern);
  });
}

test('[LAUNCHER-SKELETON] generator classifies the current launcher as data-only versus the Mac predecessor', async () => {
  const predecessor = spawnSync('/usr/bin/git', [
    '-C', path.resolve(new URL('../..', import.meta.url).pathname),
    'cat-file', 'blob', 'ade9531832da39715a815f4c34831780ce5063e3',
  ], { encoding: null, env: { PATH: '/usr/bin:/bin' }, stdio: ['ignore', 'pipe', 'pipe'] });
  assert.equal(predecessor.status, 0);
  const current = await readFile(new URL('./ci3-bridge-launcher.zsh', import.meta.url));
  assert.deepEqual(subject().launcherStructuralSkeleton(current), subject().launcherStructuralSkeleton(predecessor.stdout));
});

test('[GIT-READER] bounded reader crosses the real 82,675-byte authority boundary', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-git-reader-red-'));
  try {
    assert.equal(spawnSync('/usr/bin/git', ['init', '-q', root], {
      env: { PATH: '/usr/bin:/bin' }, stdio: ['ignore', 'pipe', 'pipe'],
    }).status, 0);
    const blobBytes = Buffer.alloc(82_675, 0x61);
    const blobPath = path.join(root, 'authority-blob.bin');
    await writeFile(blobPath, blobBytes);
    const oidResult = spawnSync('/usr/bin/git', ['-C', root, 'hash-object', '-w', blobPath], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, stdio: ['ignore', 'pipe', 'pipe'],
    });
    assert.equal(oidResult.status, 0, oidResult.stderr);
    const oid = oidResult.stdout.trim();

    const result = await subject().readGitBlobBounded({
      authorityPath: 'synthetic/authority-blob.bin',
      expectedBlobOid: oid,
      expectedFileSha256: subject().sha256(blobBytes),
      oid,
      repositoryRoot: root,
    });
    assert.equal(result.bytes_read, 82_675);
    assert.deepEqual(result.bytes, blobBytes);
    assert.equal(result.attempt, 1);
    assert.equal(result.retry, false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

const READER_OID = subject().gitObjectOid(Buffer.from('bounded'), 'sha1');
const READER_GIT_IDENTITY = Object.freeze({
  sha256: '1'.repeat(64), identity_sha256: '2'.repeat(64), version_sha256: '3'.repeat(64),
});
const READER_REPOSITORY_IDENTITY = Object.freeze({ object_format: 'sha1', sha256: '4'.repeat(64) });

function fakeReaderAdapters({
  body = Buffer.from('bounded'), bodyStatus = 0, bodySignal = null, bodyStderr = Buffer.alloc(0),
  bodyChunks, close = true, gitIdentities = [READER_GIT_IDENTITY, READER_GIT_IDENTITY],
  metadataError = {}, objectTypes = ['blob', 'blob'], repositoryIdentities = [READER_REPOSITORY_IDENTITY, READER_REPOSITORY_IDENTITY],
  sizes = [body.length, body.length], timeoutMs = 100,
} = {}) {
  const counters = { body: 0, gitIdentity: 0, killed: 0, repositoryIdentity: 0, size: 0, type: 0 };
  const result = (stdout, errorKind) => ({
    error: errorKind === 'error' ? new Error('synthetic') : undefined,
    signal: errorKind === 'signal' ? 'SIGTERM' : null,
    status: errorKind === 'status' ? 1 : 0,
    stderr: errorKind === 'stderr' ? Buffer.from('synthetic') : Buffer.alloc(0),
    stdout: Buffer.from(stdout),
  });
  const adapters = {
    timeoutMs,
    gitExecutableIdentity: async () => gitIdentities[Math.min(counters.gitIdentity++, gitIdentities.length - 1)],
    repositoryIdentity: async () => repositoryIdentities[Math.min(counters.repositoryIdentity++, repositoryIdentities.length - 1)],
    runMetadata: (argv) => {
      if (argv.includes('-t')) {
        const index = counters.type++;
        return result(`${objectTypes[Math.min(index, objectTypes.length - 1)]}\n`, metadataError.type);
      }
      if (argv.includes('-s')) {
        const index = counters.size++;
        return result(`${sizes[Math.min(index, sizes.length - 1)]}\n`, metadataError.size);
      }
      throw new Error(`unexpected metadata argv: ${argv.join(' ')}`);
    },
    spawnBody: () => {
      counters.body += 1;
      const child = new EventEmitter();
      child.stdout = new PassThrough();
      child.stderr = new PassThrough();
      child.kill = () => {
        counters.killed += 1;
        queueMicrotask(() => child.emit('close', null, 'SIGKILL'));
        return true;
      };
      queueMicrotask(() => {
        if (!close) return;
        for (const chunk of bodyChunks ?? [body]) child.stdout.write(chunk);
        if (bodyStderr.length > 0) child.stderr.write(bodyStderr);
        child.stdout.end();
        child.stderr.end();
        queueMicrotask(() => child.emit('close', bodyStatus, bodySignal));
      });
      return child;
    },
  };
  return { adapters, counters };
}

function fakeReaderInput(adapters, overrides = {}) {
  return {
    adapters,
    authorityPath: 'synthetic/bounded-blob.bin',
    expectedBlobOid: READER_OID,
    oid: READER_OID,
    repositoryRoot: '/synthetic/repository',
    ...overrides,
  };
}

async function expectReaderCode(input, code = 'GIT_AUTHORITY') {
  await assert.rejects(subject().readGitBlobBounded(input), (error) => error?.code === code);
}

async function createRealReaderRepository(bytes) {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-git-reader-real-'));
  assert.equal(spawnSync('/usr/bin/git', ['init', '-q', root], { env: { PATH: '/usr/bin:/bin' } }).status, 0);
  const blobPath = path.join(root, 'blob.bin');
  await writeFile(blobPath, bytes);
  const result = spawnSync('/usr/bin/git', ['-C', root, 'hash-object', '-w', blobPath], {
    encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  assert.equal(result.status, 0, result.stderr);
  return { oid: result.stdout.trim(), root };
}

for (const size of [0, 1, 65_535, 65_536, 65_537, 1_048_576]) {
  test(`[GIT-READER] accepts exact boundary size ${size}`, async () => {
    const bytes = Buffer.alloc(size, size % 251);
    const { oid, root } = await createRealReaderRepository(bytes);
    try {
      const result = await subject().readGitBlobBounded({
        authorityPath: `synthetic/boundary-${size}.bin`, expectedBlobOid: oid,
        expectedFileSha256: subject().sha256(bytes), oid, repositoryRoot: root,
      });
      assert.equal(result.bytes_read, size);
      assert.equal(result.sha256, subject().sha256(bytes));
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
}

test('[GIT-READER] rejects 1,048,577 bytes before body spawn', async () => {
  const body = Buffer.alloc(1_048_577, 0x61);
  const { adapters, counters } = fakeReaderAdapters({ body, sizes: [body.length, body.length] });
  await expectReaderCode(fakeReaderInput(adapters));
  assert.equal(counters.body, 0);
});

for (const [label, oid] of [
  ['missing OID', undefined], ['short OID', 'a'.repeat(39)], ['long OID', 'a'.repeat(41)],
  ['uppercase OID', 'A'.repeat(40)], ['option-like OID', `-${'a'.repeat(39)}`],
  ['rev expression', `${'a'.repeat(38)}^1`], ['path expression', `${'a'.repeat(38)}:x`],
  ['whitespace OID', `${'a'.repeat(39)} `], ['NUL OID', `${'a'.repeat(39)}\0`],
]) {
  test(`[GIT-READER] rejects ${label}`, async () => {
    const { adapters, counters } = fakeReaderAdapters();
    await expectReaderCode(fakeReaderInput(adapters, { expectedBlobOid: oid, oid }));
    assert.equal(counters.body, 0);
  });
}

test('[GIT-READER] accepts SHA-256 OID only for SHA-256 object format', async () => {
  const oid = subject().gitObjectOid(Buffer.from('bounded'), 'sha256');
  const repository = Object.freeze({ object_format: 'sha256', sha256: '5'.repeat(64) });
  const { adapters } = fakeReaderAdapters({ repositoryIdentities: [repository, repository] });
  const result = await subject().readGitBlobBounded(fakeReaderInput(adapters, { expectedBlobOid: oid, oid }));
  assert.equal(result.oid, oid);
});

test('[GIT-READER] rejects SHA-1 OID in SHA-256 object format', async () => {
  const repository = Object.freeze({ object_format: 'sha256', sha256: '5'.repeat(64) });
  const { adapters } = fakeReaderAdapters({ repositoryIdentities: [repository, repository] });
  await expectReaderCode(fakeReaderInput(adapters));
});

for (const objectType of ['tree', 'commit', 'tag']) {
  test(`[GIT-READER] rejects ${objectType} object type`, async () => {
    const { adapters, counters } = fakeReaderAdapters({ objectTypes: [objectType, objectType] });
    await expectReaderCode(fakeReaderInput(adapters));
    assert.equal(counters.body, 0);
  });
}

for (const [label, metadataError] of [
  ['nonzero type process', { type: 'status' }], ['signalled type process', { type: 'signal' }],
  ['stderr type process', { type: 'stderr' }], ['errored size process', { size: 'error' }],
  ['nonzero size process', { size: 'status' }], ['stderr size process', { size: 'stderr' }],
]) {
  test(`[GIT-READER] rejects ${label}`, async () => {
    const { adapters, counters } = fakeReaderAdapters({ metadataError });
    await expectReaderCode(fakeReaderInput(adapters));
    assert.equal(counters.body, 0);
  });
}

for (const [label, options] of [
  ['nonzero body process', { bodyStatus: 1 }], ['signalled body process', { bodyStatus: null, bodySignal: 'SIGTERM' }],
  ['body stderr', { bodyStderr: Buffer.from('synthetic') }],
  ['short body', { body: Buffer.from('short'), sizes: [6, 6] }],
  ['long body', { body: Buffer.from('longer'), sizes: [4, 4] }],
  ['stderr over 64 KiB', { bodyStderr: Buffer.alloc(65_537), body: Buffer.from('bounded') }],
]) {
  test(`[GIT-READER] rejects ${label}`, async () => {
    const { adapters } = fakeReaderAdapters(options);
    await expectReaderCode(fakeReaderInput(adapters));
  });
}

test('[GIT-READER] times out and kills a stalled body process', async () => {
  const { adapters, counters } = fakeReaderAdapters({ close: false, timeoutMs: 5 });
  await expectReaderCode(fakeReaderInput(adapters));
  assert.equal(counters.killed, 1);
});

test('[GIT-READER] kills output that exceeds the declared size', async () => {
  const { adapters, counters } = fakeReaderAdapters({ body: Buffer.from('too-long'), sizes: [3, 3] });
  await expectReaderCode(fakeReaderInput(adapters));
  assert.equal(counters.killed, 1);
});

test('[GIT-READER] performs exactly one body spawn with zero retry', async () => {
  const { adapters, counters } = fakeReaderAdapters();
  const result = await subject().readGitBlobBounded(fakeReaderInput(adapters));
  assert.equal(counters.body, 1);
  assert.equal(result.attempt, 1);
  assert.equal(result.retry, false);
});

test('[GIT-READER] postflight does not reread the body', async () => {
  const { adapters, counters } = fakeReaderAdapters();
  await subject().readGitBlobBounded(fakeReaderInput(adapters));
  assert.equal(counters.body, 1);
  assert.equal(counters.type, 2);
  assert.equal(counters.size, 2);
});

test('[GIT-READER] rejects type drift', async () => {
  const { adapters } = fakeReaderAdapters({ objectTypes: ['blob', 'tree'] });
  await expectReaderCode(fakeReaderInput(adapters));
});

test('[GIT-READER] rejects size drift', async () => {
  const { adapters } = fakeReaderAdapters({ sizes: [7, 8] });
  await expectReaderCode(fakeReaderInput(adapters));
});

test('[GIT-READER] rejects repository identity drift', async () => {
  const drifted = Object.freeze({ object_format: 'sha1', sha256: '6'.repeat(64) });
  const { adapters } = fakeReaderAdapters({ repositoryIdentities: [READER_REPOSITORY_IDENTITY, drifted] });
  await expectReaderCode(fakeReaderInput(adapters));
});

test('[GIT-READER] rejects Git executable drift', async () => {
  const drifted = Object.freeze({ ...READER_GIT_IDENTITY, sha256: '7'.repeat(64) });
  const { adapters } = fakeReaderAdapters({ gitIdentities: [READER_GIT_IDENTITY, drifted] });
  await expectReaderCode(fakeReaderInput(adapters));
});

test('[GIT-READER] rejects tree/blob OID mismatch', async () => {
  const { adapters } = fakeReaderAdapters();
  await expectReaderCode(fakeReaderInput(adapters, { expectedBlobOid: 'b'.repeat(40) }));
});

test('[GIT-OBJECT-BINDING] rejects body whose computed Git object identity differs from requested OID', async () => {
  const { adapters } = fakeReaderAdapters({ body: Buffer.from('bounded') });
  await expectReaderCode(fakeReaderInput(adapters, { expectedBlobOid: 'a'.repeat(40), oid: 'a'.repeat(40) }));
});

test('[GIT-READER] rejects expected file SHA mismatch', async () => {
  const { adapters } = fakeReaderAdapters();
  await expectReaderCode(fakeReaderInput(adapters, { expectedFileSha256: 'f'.repeat(64) }));
});

test('[GIT-READER] returns only the bounded reader contract fields', async () => {
  const { adapters } = fakeReaderAdapters();
  const result = await subject().readGitBlobBounded(fakeReaderInput(adapters));
  assert.deepEqual(Object.keys(result).sort(), [
    'attempt', 'bytes', 'bytes_read', 'expected_size', 'git_executable_sha256', 'object_type', 'oid',
    'postflight_sha256', 'preflight_sha256', 'repository_identity_sha256', 'retry', 'sha256',
  ].sort());
});

test('[GIT-READER] rejects unsafe authority path', async () => {
  const { adapters, counters } = fakeReaderAdapters();
  await expectReaderCode(fakeReaderInput(adapters, { authorityPath: '../escape' }));
  assert.equal(counters.body, 0);
});

test('[GIT-READER] duplicate blob is allowed only across distinct manifest paths', () => {
  const entries = subject().AUTHORITY_PATHS.map((entryPath) => ({
    path: entryPath, blob_oid: READER_OID, sha256: 'b'.repeat(64),
  }));
  assert.equal(subject().validateAuthorityTreeManifest(entries), true);
});

test('[GIT-READER] architecture and one MiB limit are frozen', () => {
  assert.equal(subject().GIT_OBJECT_READER_ARCHITECTURE, 'BOUNDED_GIT_OBJECT_READER_V2');
  assert.equal(subject().AUTHORITY_BLOB_LIMIT_BYTES, 1_048_576);
});

function validFixture() {
  const envValues = {
    NEXT_PUBLIC_SUPABASE_ANON_KEY: 'synthetic-anon-value',
    NEXT_PUBLIC_SUPABASE_URL: 'https://stagingprojectref01.supabase.invalid',
    SUPABASE_SERVICE_ROLE_KEY: 'synthetic-service-role-value',
  };
  const envBytes = Buffer.from(
    `${Object.entries(envValues).map(([key, value]) => `${key}=${value}`).join('\n')}\n`,
  );
  const stagingRef = 'stagingprojectref01';
  const implementationSha = 'e3e1e252b48e42554e75899b950692c05186f60d';
  const cleanupDeadline = '2099-09-11T11:44:11.182Z';
  const previewOrigin = 'https://mobile-bff-preview.invalid';

  const envReceipt = {
    control_plane_pat_persisted: false,
    control_plane_source: 'existing_authorized_credential',
    created_at_utc: '2026-08-25T00:00:00.000Z',
    database_write: false,
    environment: 'staging',
    key_created: false,
    key_disabled: false,
    key_rotated: false,
    legacy_key_contract: true,
    local_elevated_secret_exposure: 'no',
    preview_branch_verified_via_dashboard_and_api_keys: true,
    production_accessed: false,
    purpose: 'ci3-staging-mobile-bff',
    rejected_env_local_used: false,
    required_permission_verified: 'api_gateway_keys_read',
    schema_version: 1,
    supabase_parent_project_ref: 'parentprojectref0001',
    supabase_project_ref: stagingRef,
    values_in_argv: false,
    values_in_git: false,
    values_printed: false,
    variables: ['NEXT_PUBLIC_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY'].map((name) => ({
      classification: name === 'NEXT_PUBLIC_SUPABASE_URL'
        ? 'public-configuration'
        : name === 'NEXT_PUBLIC_SUPABASE_ANON_KEY'
          ? 'legacy-public-project-key'
          : 'legacy-server-sensitive-elevated',
      name,
      sha256: sha(envValues[name]),
      validated: true,
    })),
  };

  const deploymentReceipt = {
    api_target_representation: null,
    app_paths_manifest_sha256: '1'.repeat(64),
    build_log_sha256: '2'.repeat(64),
    canonical_route_path_stream_sha256: '3'.repeat(64),
    env_development_count: 0,
    env_metadata: [
      { name: 'NEXT_PUBLIC_SUPABASE_ANON_KEY', target: ['preview'], type: 'encrypted' },
      { name: 'NEXT_PUBLIC_SUPABASE_URL', target: ['preview'], type: 'encrypted' },
      { name: 'SUPABASE_SERVICE_ROLE_KEY', target: ['preview'], type: 'encrypted' },
    ],
    env_preview_count: 3,
    env_production_count: 0,
    environment: 'staging',
    framework: 'nextjs',
    implementation_sha: implementationSha,
    implementation_tree: '4'.repeat(40),
    incident_receipt_sha256: '5'.repeat(64),
    mobile_route_count: 40,
    node: '24.14.0',
    origin_sha256: sha(previewOrigin),
    original_removal_verified: true,
    preview_deployment_id_sha256: '7'.repeat(64),
    preview_origin: previewOrigin,
    preview_receipt_sha256: '8'.repeat(64),
    production_deployment_count: 0,
    project_id_sha256: '9'.repeat(64),
    project_link_absent: true,
    public_probes: {
      attempted: 30,
      forbidden_base: 8,
      mobile: 3,
      passed: 30,
      prior_findings: 19,
      summary_sha256: 'a'.repeat(64),
    },
    purpose: 'ci3_dedicated_mobile_bff_deployment',
    ready_state: 'READY',
    recovery_authority_sha: 'b'.repeat(40),
    removed_original_deployment_id_sha256: 'c'.repeat(64),
    root: 'apps/mobile-bff',
    route_count: 40,
    schema_version: 1,
    secret_values_absent: true,
    sso_protection: null,
    target: 'preview',
    team_default_live_state: 'not_observed',
    team_default_mutation_requests: 0,
    token_absent: true,
  };

  const credential = {
    cleanup_required: true,
    created_at: '2026-08-28T11:44:11.182Z',
    email: 'synthetic@example.invalid',
    environment: 'staging',
    expires_at: cleanupDeadline,
    password: 'synthetic-only-not-a-real-secret',
    project_ref: stagingRef,
    schema_version: 1,
    synthetic_marker: 'ci3-synthetic-patient',
  };

  const provisioningReceipt = {
    actor_id: 'synthetic-actor-id',
    attempts: {
      auth_create: 1,
      auth_create_settlement: 1,
      auth_delete_rollback: 0,
      auth_preflight: 1,
      auth_readback: 1,
      auth_update: 0,
      bootstrap_readback: 1,
      entitlement_grant: 1,
      entitlement_readback: 1,
      entitlement_resolution: 1,
      entitlement_settlement: 1,
      entitlements_probe: 1,
      me_probe: 1,
      rollback_database_transaction: 0,
      rollback_settlement_read: 0,
      sign_in: 1,
      today_probe: 1,
    },
    auth_reused: true,
    auth_user_id: 'synthetic-auth-id',
    authority_sha: 'd'.repeat(40),
    ci3_started: false,
    ci4_started: false,
    cleanup_deadline: cleanupDeadline,
    cleanup_deadline_class: 'future',
    cleanup_required: true,
    created_at: '2026-08-28T11:44:11.182Z',
    email_canonicalization: 'normalized_alias_documented',
    entitlement_id: 'synthetic-entitlement-id',
    environment: 'staging',
    event_id: 'synthetic-event-id',
    expires_at: cleanupDeadline,
    fixture_counts: {
      auth: 1,
      entitlement: 1,
      event: 1,
      identity: 1,
      patient: 1,
      profile: 1,
      progress: 0,
      storage: 0,
    },
    grant_at: '2026-08-28T11:44:11.182Z',
    health_data_absent: true,
    id_hashes: {
      auth_user: 'e'.repeat(64),
      entitlement: 'f'.repeat(64),
      event: '0'.repeat(64),
      patient: '1'.repeat(64),
    },
    implementation_sha: implementationSha,
    implementation_tree: '4'.repeat(40),
    operation_id: 'synthetic-operation-id',
    patient_id: 'synthetic-patient-id',
    primary_live_open: false,
    product_production_write: false,
    project_ref: stagingRef,
    purpose: 'ci3_synthetic_patient',
    raw_response_absent: true,
    request_ids: {
      entitlements: 'synthetic-request-entitlements',
      me: 'synthetic-request-me',
      today: 'synthetic-request-today',
    },
    response_structure_sha256: {
      entitlements: '2'.repeat(64),
      me: '3'.repeat(64),
      today: '4'.repeat(64),
    },
    schema_version: 1,
    service_role_patient_bearer: false,
    state: 'TODAY_VERIFIED',
    supabase_http_request_counts: { patient: 3, service: 4 },
    synthetic_marker: 'ci3-synthetic-patient',
    token_persisted: false,
    vercel_write: false,
  };

  const authority = {
    commit: 'f'.repeat(40),
    parent: '456b4643d1a310bc88458a28a9a62a16dde2e1c8',
    tree: 'a'.repeat(40),
    subject: 'build(ops): reconcile staging env receipt for CI-3 bridge',
    committed_at_utc: '2026-08-29T10:00:00.000Z',
    generator_blob_sha: 'b'.repeat(40),
    generator_file_sha256: 'c'.repeat(64),
    controller_blob_oid: '2'.repeat(40),
    controller_file_sha256: '3'.repeat(64),
    launcher_blob_oid: '4'.repeat(40),
    launcher_file_sha256: '5'.repeat(64),
    launcher_target_environment: 'mac_local',
    launcher_runtime_path: '/bin/zsh',
    zsh_syntax_validation_deferred: true,
    zsh_syntax_validation_required_environment: 'mac_local',
    zsh_syntax_validation_required_before_network: true,
    zsh_syntax_validation_status: 'not_executed_on_vps',
    predecessor_launcher_structural_skeleton_sha256: 'a'.repeat(64),
    current_launcher_structural_skeleton_sha256: 'a'.repeat(64),
    launcher_structural_skeleton_equal: true,
    anchor_writer_blob_oid: '6'.repeat(40),
    anchor_writer_file_sha256: '7'.repeat(64),
    authority_tree_manifest_sha256: '8'.repeat(64),
    remote_bundle_generation_id: 'rb-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    source_generation_id: 'src-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    source_env_descriptor_identity_sha256: '9'.repeat(64),
  };

  const hashes = {
    env_source_sha256: 'd'.repeat(64),
    env_receipt_sha256: 'e'.repeat(64),
    deployment_receipt_sha256: 'f'.repeat(64),
    credential_source_sha256: '0'.repeat(64),
    provisioning_receipt_sha256: '1'.repeat(64),
  };

  return {
    authority,
    cleanupDeadline,
    credential,
    deploymentReceipt,
    envBytes,
    envReceipt,
    envValues,
    hashes,
    implementationSha,
    provisioningReceipt,
    stagingRef,
  };
}

function validate(fixture = validFixture(), now = new Date('2026-08-29T12:00:00.000Z')) {
  return subject().validateSourceDocuments({
    credential: fixture.credential,
    deploymentReceipt: fixture.deploymentReceipt,
    envBytes: fixture.envBytes,
    envReceipt: fixture.envReceipt,
    now,
    provisioningReceipt: fixture.provisioningReceipt,
  });
}

function build(fixture = validFixture()) {
  const validated = validate(fixture);
  return subject().buildBundleArtifacts({
    authority: fixture.authority,
    createdAt: '2026-08-29T12:00:00.000Z',
    credentialSourcePath: '/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json',
    hashes: fixture.hashes,
    validated,
  });
}

function authorityPublicationRoot(outputRoot, artifacts) {
  return path.join(outputRoot, artifacts.receipt.authority_commit);
}

function generationPublicationPath(outputRoot, artifacts) {
  return path.join(authorityPublicationRoot(outputRoot, artifacts), artifacts.receipt.remote_bundle_generation_id);
}

function stagingPublicationPath(outputRoot, artifacts) {
  return path.join(authorityPublicationRoot(outputRoot, artifacts), `.staging-${artifacts.receipt.remote_bundle_generation_id}`);
}

function publicationClaimPath(outputRoot, artifacts) {
  return path.join(authorityPublicationRoot(outputRoot, artifacts), `${artifacts.receipt.remote_bundle_generation_id}.claim.json`);
}

function expectCode(code, operation) {
  assert.throws(operation, (error) => error?.code === code);
}

function buildAuthorizedTerminalAnchor({ authoritySha, terminalReceiptPath, terminalReceiptSha256 }) {
  const terminalAnchorPath = `/Library/Application Support/Agentempp/ci3-terminal-authority/${authoritySha}/terminal.anchor.v1.json`;
  const privilegedWriterAuthority = {
    schema_version: 1,
    purpose: 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1',
    bridge_authority_sha: authoritySha,
    writer_identity_sha256: '3'.repeat(64),
    anchor_path_sha256: sha(terminalAnchorPath),
    controller_receipt_sha256: '4'.repeat(64),
    executable_sha256: '5'.repeat(64),
    uid: 0,
    gid: 0,
    open_flags: 'O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW',
    file_mode: '0444',
    immutable_flag: 'UF_IMMUTABLE',
    normal_executor_authorized: false,
  };
  const privilegedWriterAuthorityBytes = Buffer.from(`${JSON.stringify(privilegedWriterAuthority)}\n`);
  return subject().buildTerminalAnchorRecord({
    authoritySha,
    privilegedWriterAuthority,
    privilegedWriterAuthorityBytes,
    privilegedWriterAuthoritySha256: sha(privilegedWriterAuthorityBytes),
    terminalAnchorPath,
    terminalReceiptPath,
    terminalReceiptSha256,
  });
}

test('accepts only --self-test mode', () => {
  assert.equal(subject().parseMode(['--self-test']), 'self-test');
});

test('accepts only --create mode', () => {
  assert.equal(subject().parseMode(['--create']), 'create');
});

test('rejects a missing mode', () => {
  expectCode('MODE_INVALID', () => subject().parseMode([]));
});

test('rejects additional arguments', () => {
  expectCode('MODE_INVALID', () => subject().parseMode(['--create', 'extra']));
});

test('accepts exact regular single-link owner-only input metadata', () => {
  assert.equal(subject().validateInputMetadata({ uid: 0, gid: 0, mode: 0o600, nlink: 1, isFile: true }, 0), true);
});

test('rejects a symlink input', () => {
  expectCode('INPUT_TYPE', () => subject().validateInputMetadata({ uid: 0, gid: 0, mode: 0o600, nlink: 1, isFile: false, isSymbolicLink: true }, 0));
});

test('rejects a hardlinked input', () => {
  expectCode('INPUT_LINK_COUNT', () => subject().validateInputMetadata({ uid: 0, gid: 0, mode: 0o600, nlink: 2, isFile: true }, 0));
});

test('rejects an input owned by another uid', () => {
  expectCode('INPUT_OWNER', () => subject().validateInputMetadata({ uid: 501, gid: 0, mode: 0o600, nlink: 1, isFile: true }, 0));
});

test('rejects an input owned by another gid', () => {
  expectCode('INPUT_OWNER', () => subject().validateInputMetadata({ uid: 0, gid: 20, mode: 0o600, nlink: 1, isFile: true }, 0));
});

test('rejects a permissive input mode', () => {
  expectCode('INPUT_MODE', () => subject().validateInputMetadata({ uid: 0, gid: 0, mode: 0o640, nlink: 1, isFile: true }, 0));
});

test('accepts an exact owner-only parent directory', () => {
  assert.equal(subject().validateParentMetadata({ uid: 0, gid: 0, mode: 0o700, isDirectory: true }, 0), true);
});

test('rejects a permissive parent directory', () => {
  expectCode('PARENT_MODE', () => subject().validateParentMetadata({ uid: 0, gid: 0, mode: 0o750, isDirectory: true }, 0));
});

test('rejects a non-directory parent', () => {
  expectCode('PARENT_TYPE', () => subject().validateParentMetadata({ uid: 0, gid: 0, mode: 0o700, isDirectory: false }, 0));
});

test('rejects the primary denylist path without opening it', () => {
  expectCode('PRIMARY_PATH_DENIED', () => subject().assertKnownInputPath('/root/.config/agentempp/secrets/agentempp-primary-backend.env'));
});

test('rejects an unknown input path', () => {
  expectCode('INPUT_PATH_UNKNOWN', () => subject().assertKnownInputPath('/root/.config/agentempp/secrets/unknown.json'));
});

test('accepts every fixed source path', () => {
  for (const fixedPath of Object.values(subject().INPUT_PATHS)) {
    assert.equal(subject().assertKnownInputPath(fixedPath), true);
  }
});

test('rejects a wrong expected input hash', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-hash-'));
  const file = path.join(root, 'source');
  await writeFile(file, 'synthetic');
  await mkdir(path.join(root, 'parent'), { mode: 0o700 });
  expectCode('INPUT_HASH', () => subject().verifyExpectedHash(Buffer.from('synthetic'), '0'.repeat(64)));
});

test('rejects input mutation between descriptor observations', () => {
  const before = { uid: 0n, gid: 0n, mode: 0o100600n, nlink: 1n, dev: 1n, ino: 2n, size: 3n, mtimeNs: 4n };
  const after = { ...before, size: 4n, mtimeNs: 5n };
  expectCode('INPUT_MUTATED', () => subject().assertStableIdentity(before, after));
});

test('accepts an unchanged descriptor identity', () => {
  const observed = { uid: 0n, gid: 0n, mode: 0o100600n, nlink: 1n, dev: 1n, ino: 2n, size: 3n, mtimeNs: 4n };
  assert.equal(subject().assertStableIdentity(observed, { ...observed }), true);
});

test('round-17 stable identity rejects lossy Number projections of adjacent exact sizes', () => {
  const exactA = 9_007_199_254_740_992n;
  const exactB = exactA + 1n;
  const common = {
    uid: 0n, gid: 0n, mode: 0o100600n, nlink: 1n,
    mtimeNs: 1_788_176_481_711_164_293n, dev: 17n, ino: 19n,
  };
  const lossyA = { ...common, size: Number(exactA) };
  const lossyB = { ...common, size: Number(exactB) };
  assert.equal(lossyA.size, lossyB.size, 'numberEqual=true');
  let stableIdentityAccepted = false;
  try {
    subject().assertStableIdentity(lossyA, lossyB);
    stableIdentityAccepted = true;
  } catch {}
  assert.equal(stableIdentityAccepted, false,
    `stableIdentityAccepted=${stableIdentityAccepted} exactA=${exactA} exactB=${exactB}`);
  expectCode('INPUT_MUTATED', () => subject().assertStableIdentity(
    { ...common, size: exactA }, { ...common, size: exactB },
  ));
});

test('round-17 production owner-only reader rejects adjacent exact sizes in every publication context', async () => {
  assert.equal(typeof subject().readBoundOwnerOnlyFile, 'function', 'PRODUCTION_READER_EXACT_SIZE=false');
  const bytes = Buffer.from('synthetic-bound-reader\n');
  const exactA = 9_007_199_254_740_992n;
  const exactB = exactA + 1n;
  const statRecord = (size) => ({
    uid: 0n, gid: 0n, mode: 0o100600n, nlink: 1n, size,
    mtimeNs: 1_788_176_481_711_164_293n, dev: 23n, ino: 29n,
    isFile: () => true, isDirectory: () => false, isSymbolicLink: () => false,
  });
  for (const [context, code, expectedHash] of [
    ['original-claim', 'PUBLICATION_CLAIM', null],
    ['exact-existing', 'EXISTING_BUNDLE_DIVERGENT', subject().sha256(bytes)],
    ['staging', 'STAGING_DIVERGENT', subject().sha256(bytes)],
    ['recovery', 'STAGING_DIVERGENT', subject().sha256(bytes)],
  ]) {
    let lstatCalls = 0;
    let descriptorStatCalls = 0;
    const lstatFn = async (_filename, options) => {
      assert.deepEqual(options, { bigint: true });
      lstatCalls += 1;
      return statRecord(lstatCalls === 1 ? exactA : exactB);
    };
    const openFn = async (_filename, _flags) => ({
      stat: async (options) => {
        assert.deepEqual(options, { bigint: true });
        descriptorStatCalls += 1;
        return statRecord(descriptorStatCalls === 1 ? exactA : exactB);
      },
      readFile: async () => Buffer.from(bytes),
      close: async () => {},
    });
    await assert.rejects(subject().readBoundOwnerOnlyFile(
      `/synthetic/round17/${context}.json`, 0, 0, expectedHash, code, { lstatFn, openFn },
    ), (error) => error?.code === code, `${context}:stableIdentityAccepted=true`);
    assert.equal(descriptorStatCalls, 2, context);
  }
});

test('parses exactly the three approved env names', () => {
  assert.deepEqual(subject().parseExactEnv(validFixture().envBytes), validFixture().envValues);
});

test('rejects a missing Supabase URL', () => {
  const fixture = validFixture();
  fixture.envBytes = Buffer.from('NEXT_PUBLIC_SUPABASE_ANON_KEY=x\nSUPABASE_SERVICE_ROLE_KEY=y\n');
  expectCode('ENV_SCHEMA', () => validate(fixture));
});

test('rejects a missing anon key', () => {
  const fixture = validFixture();
  fixture.envBytes = Buffer.from('NEXT_PUBLIC_SUPABASE_URL=https://stagingprojectref01.supabase.invalid\nSUPABASE_SERVICE_ROLE_KEY=y\n');
  expectCode('ENV_SCHEMA', () => validate(fixture));
});

test('rejects a missing service role input even though it is never emitted', () => {
  const fixture = validFixture();
  fixture.envBytes = Buffer.from('NEXT_PUBLIC_SUPABASE_URL=https://stagingprojectref01.supabase.invalid\nNEXT_PUBLIC_SUPABASE_ANON_KEY=x\n');
  expectCode('ENV_SCHEMA', () => validate(fixture));
});

test('rejects an extra env name', () => {
  const fixture = validFixture();
  fixture.envBytes = Buffer.concat([fixture.envBytes, Buffer.from('EXTRA=value\n')]);
  expectCode('ENV_SCHEMA', () => validate(fixture));
});

test('rejects a duplicate env name', () => {
  const fixture = validFixture();
  fixture.envBytes = Buffer.concat([fixture.envBytes, Buffer.from('NEXT_PUBLIC_SUPABASE_URL=https://other.invalid\n')]);
  expectCode('ENV_SCHEMA', () => validate(fixture));
});

test('rejects an extra staging receipt field', () => {
  const fixture = validFixture();
  fixture.envReceipt.extra = true;
  expectCode('ENV_RECEIPT_SCHEMA', () => validate(fixture));
});

test('rejects a staging project mismatch between source receipt and URL', () => {
  const fixture = validFixture();
  fixture.envReceipt.supabase_project_ref = 'differentprojectref1';
  expectCode('STAGING_REF_MISMATCH', () => validate(fixture));
});

const receiptMutationCases = Object.freeze([
  ['purpose underscore fails', (f) => { f.envReceipt.purpose = 'ci3_staging_mobile_bff'; }, 'ENV_RECEIPT_STATE'],
  ['legacy key false fails', (f) => { f.envReceipt.legacy_key_contract = false; }, 'ENV_RECEIPT_STATE'],
  ['exposure none fails', (f) => { f.envReceipt.local_elevated_secret_exposure = 'none'; }, 'ENV_RECEIPT_STATE'],
  ['permission yes fails', (f) => { f.envReceipt.required_permission_verified = 'yes'; }, 'ENV_RECEIPT_STATE'],
  ['URL generic classification fails', (f) => { f.envReceipt.variables.find((v) => v.name === 'NEXT_PUBLIC_SUPABASE_URL').classification = 'public'; }, 'ENV_RECEIPT_STATE'],
  ['anon generic classification fails', (f) => { f.envReceipt.variables.find((v) => v.name === 'NEXT_PUBLIC_SUPABASE_ANON_KEY').classification = 'public'; }, 'ENV_RECEIPT_STATE'],
  ['service generic classification fails', (f) => { f.envReceipt.variables.find((v) => v.name === 'SUPABASE_SERVICE_ROLE_KEY').classification = 'sensitive'; }, 'ENV_RECEIPT_STATE'],
  ['purpose case variant fails', (f) => { f.envReceipt.purpose = 'CI3-staging-mobile-bff'; }, 'ENV_RECEIPT_STATE'],
  ['classification alias fails', (f) => { f.envReceipt.variables[0].classification = 'legacy_public_project_key'; }, 'ENV_RECEIPT_STATE'],
  ['duplicate variable fails', (f) => { f.envReceipt.variables.push(clone(f.envReceipt.variables[0])); }, 'ENV_RECEIPT_SCHEMA'],
  ['missing variable fails', (f) => { f.envReceipt.variables.pop(); }, 'ENV_RECEIPT_SCHEMA'],
  ['extra variable fails', (f) => { f.envReceipt.variables.push({ classification: 'public-configuration', name: 'EXTRA', sha256: '0'.repeat(64), validated: true }); }, 'ENV_RECEIPT_SCHEMA'],
  ['validated false fails', (f) => { f.envReceipt.variables[0].validated = false; }, 'ENV_RECEIPT_SCHEMA'],
  ['SHA mismatch fails', (f) => { f.envReceipt.variables[0].sha256 = '0'.repeat(64); }, 'ENV_VALUE_HASH'],
  ['project ref mismatch fails', (f) => { f.envReceipt.supabase_project_ref = 'differentprojectref1'; }, 'STAGING_REF_MISMATCH'],
  ['parent ref equal fails', (f) => { f.envReceipt.supabase_parent_project_ref = f.envReceipt.supabase_project_ref; }, 'ENV_RECEIPT_STATE'],
  ['missing preview verification fails', (f) => { delete f.envReceipt.preview_branch_verified_via_dashboard_and_api_keys; }, 'ENV_RECEIPT_SCHEMA'],
  ['key created true fails', (f) => { f.envReceipt.key_created = true; }, 'ENV_RECEIPT_STATE'],
  ['key rotated true fails', (f) => { f.envReceipt.key_rotated = true; }, 'ENV_RECEIPT_STATE'],
  ['key disabled true fails', (f) => { f.envReceipt.key_disabled = true; }, 'ENV_RECEIPT_STATE'],
  ['production accessed true fails', (f) => { f.envReceipt.production_accessed = true; }, 'ENV_RECEIPT_STATE'],
  ['database write true fails', (f) => { f.envReceipt.database_write = true; }, 'ENV_RECEIPT_STATE'],
  ['local exposure variant fails', (f) => { f.envReceipt.local_elevated_secret_exposure = 'NO'; }, 'ENV_RECEIPT_STATE'],
  ['unknown receipt key fails', (f) => { f.envReceipt.unknown = false; }, 'ENV_RECEIPT_SCHEMA'],
  ['missing canonical key fails', (f) => { delete f.envReceipt.required_permission_verified; }, 'ENV_RECEIPT_SCHEMA'],
]);

test('[ENV-RECEIPT-RECONCILIATION 01] canonical complete receipt passes', () => assert.doesNotThrow(() => validate()));
test('[ENV-RECEIPT-RECONCILIATION 02] sanitized receipt contains no raw env values', () => {
  const fixture = validFixture();
  const bytes = JSON.stringify(fixture.envReceipt);
  for (const value of Object.values(fixture.envValues)) assert.equal(bytes.includes(value), false);
  assert.doesNotThrow(() => validate(fixture));
});
test('[ENV-RECEIPT-RECONCILIATION 03] all three variable hashes remain bound', () => {
  const fixture = validFixture();
  for (const variable of fixture.envReceipt.variables) assert.equal(variable.sha256, sha(fixture.envValues[variable.name]));
});
test('[ENV-RECEIPT-RECONCILIATION 04] authorized extra gates remain required', () => {
  const fixture = validFixture(); delete fixture.envReceipt.control_plane_source;
  expectCode('ENV_RECEIPT_SCHEMA', () => validate(fixture));
});
test('[ENV-RECEIPT-RECONCILIATION 05] parent project ref remains distinct', () => {
  const fixture = validFixture(); fixture.envReceipt.supabase_parent_project_ref = fixture.envReceipt.supabase_project_ref;
  expectCode('ENV_RECEIPT_STATE', () => validate(fixture));
});
receiptMutationCases.forEach(([label, mutate, code], index) => {
  test(`[ENV-RECEIPT-RECONCILIATION ${String(index + 6).padStart(2, '0')}] ${label}`, () => {
    const fixture = validFixture(); mutate(fixture); expectCode(code, () => validate(fixture));
  });
});
test('[ENV-RECEIPT-RECONCILIATION 31] receipt bytes are not rewritten', () => {
  const fixture = validFixture(); const before = JSON.stringify(fixture.envReceipt); validate(fixture); assert.equal(JSON.stringify(fixture.envReceipt), before);
});
test('[ENV-RECEIPT-RECONCILIATION 32] env bytes are not rewritten', () => {
  const fixture = validFixture(); const before = Buffer.from(fixture.envBytes); validate(fixture); assert.deepEqual(fixture.envBytes, before);
});
test('[ENV-RECEIPT-RECONCILIATION 33] Bridge V1 lineage remains historical', () => assert.match(GENERATOR_SOURCE, /PREDECESSOR_AUTHORITY_COMMIT = 'ba8473799a19aec586b0fe706bb7d4084589c86c'/));
test('[ENV-RECEIPT-RECONCILIATION 34] Bridge V2 lineage remains historical', () => assert.match(GENERATOR_SOURCE, /PREDECESSOR_V2_AUTHORITY_COMMIT = 'c8e1d00c8d43912e55c5ecae3b2e3d84ae232026'/));
test('[ENV-RECEIPT-RECONCILIATION 35] fresh authority architecture is distinct', () => assert.match(GENERATOR_SOURCE, /WITH_CANONICAL_ENV_RECEIPT_V1/));
test('[ENV-RECEIPT-RECONCILIATION 36] old authority cannot be current', () => assert.doesNotMatch(GENERATOR_SOURCE, /const AUTHORITY_PARENT = '92cccf3dca21a29d601d2f274a67ea2ba284914b'/));
test('[ENV-RECEIPT-RECONCILIATION 37] old claim cannot authorize fresh attempt', () => assert.match(GENERATOR_SOURCE, /PREDECESSOR_V2_STOP_COMMIT = '456b4643d1a310bc88458a28a9a62a16dde2e1c8'/));
test('[ENV-RECEIPT-RECONCILIATION 38] no retroactive claim path exists', () => assert.doesNotMatch(GENERATOR_SOURCE, /retroactiveClaim|retroactive_claim/));
test('[ENV-RECEIPT-RECONCILIATION 39] runtime adoption is not mutated', () => assert.doesNotMatch(GENERATOR_SOURCE, /runtime.*(?:writeFile|rename|unlink)/i));
test('[ENV-RECEIPT-RECONCILIATION 40] generator has no ldd probe or chattr', () => assert.doesNotMatch(GENERATOR_SOURCE, /(?:^|\W)(?:ldd|chattr)(?:$|\W)/m));
test('[ENV-RECEIPT-RECONCILIATION 41] bounded Git reader remains one MiB', () => assert.equal(subject().AUTHORITY_BLOB_LIMIT_BYTES, 1_048_576));
test('[ENV-RECEIPT-RECONCILIATION 42] zsh gate remains deferred to Mac', () => assert.equal(build().receipt.zsh_syntax_validation_deferred, true));
test('[ENV-RECEIPT-RECONCILIATION 43] launcher structural skeleton remains equal', () => assert.equal(build().receipt.launcher_structural_skeleton_equal, true));
test('[ENV-RECEIPT-RECONCILIATION 44] service role is not emitted in config', () => assert.equal(build().configBytes.includes(validFixture().envValues.SUPABASE_SERVICE_ROLE_KEY), false));
test('[ENV-RECEIPT-RECONCILIATION 45] credential is not copied into output filenames', () => assert.equal(build().receipt.output_filenames.includes('synthetic-patient.credentials.json'), false));
test('[ENV-RECEIPT-RECONCILIATION 46] receipt and logs expose no raw values', () => {
  const fixture = validFixture(); const output = build(fixture).receiptBytes;
  for (const value of Object.values(fixture.envValues)) assert.equal(output.includes(value), false);
});
test('[ENV-RECEIPT-RECONCILIATION 47] original receipt variable order remains frozen', () => {
  const fixture = validFixture(); fixture.envReceipt.variables.reverse();
  expectCode('ENV_RECEIPT_SCHEMA', () => validate(fixture));
});

test('rejects an env variable digest mismatch', () => {
  const fixture = validFixture();
  fixture.envReceipt.variables[0].sha256 = '0'.repeat(64);
  expectCode('ENV_VALUE_HASH', () => validate(fixture));
});

test('rejects a deployment receipt with an extra field', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.aliases = [];
  expectCode('DEPLOYMENT_RECEIPT_SCHEMA', () => validate(fixture));
});

test('rejects Preview that is not READY', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.ready_state = 'BUILDING';
  expectCode('PREVIEW_STATE', () => validate(fixture));
});

test('rejects a non-preview deployment target', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.target = 'production';
  expectCode('PREVIEW_TARGET', () => validate(fixture));
});

test('rejects any Production deployment', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.production_deployment_count = 1;
  expectCode('PRODUCTION_COUNT', () => validate(fixture));
});

test('rejects a Preview env count other than three', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.env_preview_count = 2;
  expectCode('ENV_COUNTS', () => validate(fixture));
});

test('rejects a Production env count above zero', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.env_production_count = 1;
  expectCode('ENV_COUNTS', () => validate(fixture));
});

test('rejects a Development env count above zero', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.env_development_count = 1;
  expectCode('ENV_COUNTS', () => validate(fixture));
});

test('rejects nonnull SSO protection', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.sso_protection = 'enabled';
  expectCode('SSO_STATE', () => validate(fixture));
});

test('rejects alias or custom-domain representation through exact schema', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.custom_domains = ['preview.invalid'];
  expectCode('DEPLOYMENT_RECEIPT_SCHEMA', () => validate(fixture));
});

test('rejects a deployment implementation mismatch', () => {
  const fixture = validFixture();
  fixture.deploymentReceipt.implementation_sha = '0'.repeat(40);
  expectCode('IMPLEMENTATION_SHA', () => validate(fixture));
});

test('rejects an unverified provisioning state', () => {
  const fixture = validFixture();
  fixture.provisioningReceipt.state = 'PENDING';
  expectCode('PROVISIONING_STATE', () => validate(fixture));
});

test('rejects an expired cleanup deadline', () => {
  const fixture = validFixture();
  fixture.provisioningReceipt.cleanup_deadline = '2026-08-01T00:00:00.000Z';
  fixture.credential.expires_at = fixture.provisioningReceipt.cleanup_deadline;
  expectCode('CLEANUP_DEADLINE', () => validate(fixture));
});

test('rejects a credential project mismatch', () => {
  const fixture = validFixture();
  fixture.credential.project_ref = 'differentprojectref1';
  expectCode('CREDENTIAL_PROJECT', () => validate(fixture));
});

test('rejects a token field in the credential', () => {
  const fixture = validFixture();
  fixture.credential.token = 'synthetic-token';
  expectCode('CREDENTIAL_SCHEMA', () => validate(fixture));
});

test('rejects a service role field in the credential', () => {
  const fixture = validFixture();
  fixture.credential.service_role = 'synthetic-value';
  expectCode('CREDENTIAL_SCHEMA', () => validate(fixture));
});

test('rejects an extra provisioning receipt field', () => {
  const fixture = validFixture();
  fixture.provisioningReceipt.extra = true;
  expectCode('PROVISIONING_RECEIPT_SCHEMA', () => validate(fixture));
});

test('rejects primary or live access in provisioning evidence', () => {
  const fixture = validFixture();
  fixture.provisioningReceipt.primary_live_open = true;
  expectCode('PRIMARY_LIVE_STATE', () => validate(fixture));
});

test('rejects token persistence in provisioning evidence', () => {
  const fixture = validFixture();
  fixture.provisioningReceipt.token_persisted = true;
  expectCode('TOKEN_STATE', () => validate(fixture));
});

test('rejects a service role used as patient bearer', () => {
  const fixture = validFixture();
  fixture.provisioningReceipt.service_role_patient_bearer = true;
  expectCode('SERVICE_ROLE_BEARER', () => validate(fixture));
});

test('builds config with exactly the public contract keys', () => {
  assert.deepEqual(Object.keys(build().config).sort(), [
    'bridge_authority_sha',
    'cleanup_deadline',
    'environment',
    'mobile_bff_origin',
    'schema_version',
    'staging_project_ref',
    'supabase_anon_key',
    'supabase_url',
  ]);
});

test('config never emits the service role', () => {
  const fixture = validFixture();
  assert.equal(JSON.stringify(build(fixture).config).includes(fixture.envValues.SUPABASE_SERVICE_ROLE_KEY), false);
});

test('config never emits a token', () => {
  assert.equal('token' in build().config, false);
});

test('config contains the approved BFF origin', () => {
  const fixture = validFixture();
  assert.equal(build(fixture).config.mobile_bff_origin, fixture.deploymentReceipt.preview_origin);
});

test('config contains the approved anon key', () => {
  const fixture = validFixture();
  assert.equal(build(fixture).config.supabase_anon_key, fixture.envValues.NEXT_PUBLIC_SUPABASE_ANON_KEY);
});

test('receipt never contains the raw BFF origin', () => {
  const fixture = validFixture();
  assert.equal(build(fixture).receiptBytes.includes(fixture.deploymentReceipt.preview_origin), false);
});

test('receipt never contains the raw anon key', () => {
  const fixture = validFixture();
  assert.equal(build(fixture).receiptBytes.includes(fixture.envValues.NEXT_PUBLIC_SUPABASE_ANON_KEY), false);
});

test('receipt contains only the frozen provenance contract keys', () => {
  assert.deepEqual(Object.keys(build().receipt).sort(), subject().RECEIPT_KEYS.slice().sort());
});

test('receipt binds the generator commit and Git blob', () => {
  const fixture = validFixture();
  const receipt = build(fixture).receipt;
  assert.equal(receipt.authority_commit, fixture.authority.commit);
  assert.equal(receipt.generator_blob_sha, fixture.authority.generator_blob_sha);
});

test('receipt defers the exact launcher zsh syntax gate to Mac before network', () => {
  const receipt = build().receipt;
  assert.equal(receipt.launcher_target_environment, 'mac_local');
  assert.equal(receipt.launcher_runtime_path, '/bin/zsh');
  assert.equal(receipt.zsh_syntax_validation_deferred, true);
  assert.equal(receipt.zsh_syntax_validation_required_environment, 'mac_local');
  assert.equal(receipt.zsh_syntax_validation_required_before_network, true);
  assert.equal(receipt.zsh_syntax_validation_status, 'not_executed_on_vps');
});

test('receipt binds equal predecessor and current launcher structural skeletons', () => {
  const receipt = build().receipt;
  assert.match(receipt.predecessor_launcher_structural_skeleton_sha256, /^[a-f0-9]{64}$/);
  assert.equal(receipt.current_launcher_structural_skeleton_sha256, receipt.predecessor_launcher_structural_skeleton_sha256);
  assert.equal(receipt.launcher_structural_skeleton_equal, true);
});

test('receipt binds every source hash', () => {
  const fixture = validFixture();
  const receipt = build(fixture).receipt;
  for (const [key, value] of Object.entries(fixture.hashes)) assert.equal(receipt[key], value);
});

test('receipt binds the existing credential by fixed path and hash without copying it', () => {
  const fixture = validFixture();
  const receipt = build(fixture).receipt;
  assert.equal(receipt.credential_source_path, subject().INPUT_PATHS.credential);
  assert.equal(receipt.credential_source_sha256, fixture.hashes.credential_source_sha256);
  assert.equal(receipt.output_filenames.includes('synthetic-patient.credentials.json'), false);
});

test('receipt binds the cleanup deadline', () => {
  const fixture = validFixture();
  assert.equal(build(fixture).receipt.cleanup_deadline, fixture.cleanupDeadline);
});

test('receipt binds the hash of the exact config bytes', () => {
  const artifacts = build();
  assert.equal(artifacts.receipt.output_config_sha256, subject().sha256(Buffer.from(artifacts.configBytes)));
});

test('receipt marks sensitive and primary emission controls false', () => {
  const receipt = build().receipt;
  assert.equal(receipt.service_role_emitted, false);
  assert.equal(receipt.token_emitted, false);
  assert.equal(receipt.raw_values_reported, false);
  assert.equal(receipt.primary_opened, false);
});

test('authority validation rejects the wrong parent commit', () => {
  const fixture = validFixture();
  fixture.authority.parent = '0'.repeat(40);
  expectCode('AUTHORITY_PARENT', () => build(fixture));
});

test('authority validation rejects the wrong commit subject', () => {
  const fixture = validFixture();
  fixture.authority.subject = 'unexpected subject';
  expectCode('AUTHORITY_SUBJECT', () => build(fixture));
});

test('authority validation rejects a missing generator blob binding', () => {
  const fixture = validFixture();
  fixture.authority.generator_blob_sha = '';
  expectCode('GENERATOR_BLOB', () => build(fixture));
});

test('publishes exactly two files beneath an authority-addressed directory', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-publish-'));
  const artifacts = build();
  const result = await subject().publishAtomic({
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  });
  assert.equal(result.status, 'CREATED');
  assert.deepEqual((await readdir(result.finalPath)).sort(), ['bridge.receipt.json', 'mobile-staging-config.json']);
});

test('requires the final authority path to be absent for first publication', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-existing-'));
  const artifacts = build();
  await mkdir(authorityPublicationRoot(root, artifacts), { mode: 0o700 });
  const finalPath = generationPublicationPath(root, artifacts);
  await mkdir(finalPath, { mode: 0o700 });
  await writeFile(path.join(finalPath, 'mobile-staging-config.json'), '{}\n');
  await writeFile(path.join(finalPath, 'bridge.receipt.json'), '{}\n');
  await assert.rejects(
    subject().publishAtomic({ authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) }),
    (error) => error?.code === 'EXISTING_BUNDLE_DIVERGENT',
  );
});

test('recognizes an exact existing bundle read-only', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-idempotent-'));
  const artifacts = build();
  const options = { authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) };
  const first = await subject().publishAtomic(options);
  const before = await stat(path.join(first.finalPath, 'bridge.receipt.json'), { bigint: true });
  const second = await subject().publishAtomic(options);
  const after = await stat(path.join(first.finalPath, 'bridge.receipt.json'), { bigint: true });
  assert.equal(second.status, 'EXISTS_VERIFIED');
  assert.equal(after.mtimeNs, before.mtimeNs);
});

test('rejects a divergent existing config without rewriting it', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-divergent-'));
  const artifacts = build();
  const options = { authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) };
  const first = await subject().publishAtomic(options);
  await writeFile(path.join(first.finalPath, 'mobile-staging-config.json'), 'divergent\n');
  await assert.rejects(subject().publishAtomic(options), (error) => error?.code === 'EXISTING_BUNDLE_DIVERGENT');
  assert.equal(await readFile(path.join(first.finalPath, 'mobile-staging-config.json'), 'utf8'), 'divergent\n');
});

test('uses a same-filesystem staging directory under the output root', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-samefs-'));
  const artifacts = build();
  let observed;
  await subject().publishAtomic({
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    hooks: { afterStagingCreated: ({ outputRoot, stagingPath }) => { observed = { outputRoot, stagingPath }; } },
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  });
  assert.equal(observed.stagingPath.startsWith(`${observed.outputRoot}${path.sep}`), true);
  assert.equal(
    (await stat(observed.stagingPath, { bigint: true })).dev,
    (await stat(observed.outputRoot, { bigint: true })).dev,
  );
});

test('fails closed if the final path appears immediately before rename', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-race-'));
  const artifacts = build();
  await assert.rejects(subject().publishAtomic({
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    hooks: { beforeRename: async ({ finalPath }) => { await mkdir(finalPath, { mode: 0o700 }); } },
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  }), (error) => error?.code === 'FINAL_PATH_RACE');
});

test('fsyncs durable claim, staged files, commit directory and parent', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-fsync-'));
  const artifacts = build();
  const trace = [];
  await subject().publishAtomic({ authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes), trace });
  assert.deepEqual(trace.filter((event) => event.startsWith('fsync:')), ['fsync:claim', 'fsync:claim-parent', 'fsync:config', 'fsync:receipt', 'fsync:staging', 'fsync:final', 'fsync:parent']);
});

test('crash before rename leaves the final bundle absent', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-crash-before-'));
  const artifacts = build();
  await assert.rejects(subject().publishAtomic({ authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), hooks: { beforeRename: () => { throw new Error('synthetic crash'); } }, outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) }));
  await assert.rejects(stat(generationPublicationPath(root, artifacts)), { code: 'ENOENT' });
});

test('crash after files but before staging fsync leaves the final bundle absent', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-crash-files-'));
  const artifacts = build();
  await assert.rejects(subject().publishAtomic({ authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), hooks: { afterFilesFsynced: () => { throw new Error('synthetic crash'); } }, outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) }));
  await assert.rejects(stat(generationPublicationPath(root, artifacts)), { code: 'ENOENT' });
});

test('crash after rename before parent fsync is recovered by exact read-only verification', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-crash-after-'));
  const artifacts = build();
  const options = { authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) };
  await assert.rejects(subject().publishAtomic({ ...options, hooks: { afterRename: () => { throw new Error('synthetic crash'); } } }));
  assert.equal((await subject().publishAtomic(options)).status, 'EXISTS_VERIFIED');
});

test('never creates mutable current or latest aliases', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-alias-'));
  const artifacts = build();
  await subject().publishAtomic({ authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) });
  const entries = await readdir(root);
  assert.equal(entries.includes('current'), false);
  assert.equal(entries.includes('latest'), false);
});

test('does not render or regenerate when the exact bundle already exists', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-no-rerender-'));
  const artifacts = build();
  const options = { authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) };
  await subject().publishAtomic(options);
  let stagingCreated = false;
  const result = await subject().publishAtomic({ ...options, hooks: { afterStagingCreated: () => { stagingCreated = true; } } });
  assert.equal(result.status, 'EXISTS_VERIFIED');
  assert.equal(stagingCreated, false);
});

test('maps all five Review A Important findings independently', () => {
  const ids = subject().IMPORTANT_FINDINGS.filter((finding) => finding.reviewer === 'A').map((finding) => finding.id);
  assert.deepEqual(ids, ['RA1-I-5', 'A4-I-1', 'A4-I-3', 'A5-I-1', 'A5-I-2']);
});

test('maps all six Review B Important findings independently', () => {
  const ids = subject().IMPORTANT_FINDINGS.filter((finding) => finding.reviewer === 'B').map((finding) => finding.id);
  assert.deepEqual(ids, ['RA0-I-4', 'RA0-I-7', 'R2-I-2', 'R5-I-1', 'R5-I-2', 'R5-I-3']);
});

test('requires exactly eleven Important finding mappings without deduplication', () => {
  assert.equal(subject().verifyFindingCoverage(subject().IMPORTANT_FINDINGS), true);
  assert.equal(subject().IMPORTANT_FINDINGS.length, 11);
});

test('blocks self-test coverage when an Important finding is unmapped', () => {
  expectCode('FINDING_COVERAGE', () => subject().verifyFindingCoverage(subject().IMPORTANT_FINDINGS.slice(1)));
});

test('blocks self-test coverage when an unknown finding is added', () => {
  const unknown = [...subject().IMPORTANT_FINDINGS, { id: 'UNKNOWN-I-1', reviewer: 'A', architecture: 'none', test: 'none', receipt_field: 'none', terminal_gate: 'none' }];
  expectCode('FINDING_COVERAGE', () => subject().verifyFindingCoverage(unknown));
});

test('every finding maps architecture, test, receipt field and terminal gate', () => {
  for (const finding of subject().IMPORTANT_FINDINGS) {
    assert.equal(typeof finding.architecture, 'string');
    assert.equal(typeof finding.test, 'string');
    assert.equal(typeof finding.receipt_field, 'string');
    assert.equal(typeof finding.terminal_gate, 'string');
    assert.ok(finding.architecture && finding.test && finding.receipt_field && finding.terminal_gate);
  }
});

test('terminal scan findings map to terminal receipt hashes', () => {
  for (const id of ['RA1-I-5', 'A4-I-1', 'RA0-I-7', 'R2-I-2']) {
    const finding = subject().IMPORTANT_FINDINGS.find((entry) => entry.id === id);
    assert.match(finding.receipt_field, /terminal|scan|receipt/i);
  }
});

test('exact source generation findings map to immutable source hashes', () => {
  for (const id of ['A4-I-3', 'A5-I-2', 'R5-I-1', 'R5-I-3']) {
    const finding = subject().IMPORTANT_FINDINGS.find((entry) => entry.id === id);
    assert.match(`${finding.architecture} ${finding.receipt_field}`, /generation|hash|immutable|descriptor|bundle/i);
  }
});

test('capture generation finding maps to same-descriptor capture behavior', () => {
  const finding = subject().IMPORTANT_FINDINGS.find((entry) => entry.id === 'A5-I-1');
  assert.match(`${finding.architecture} ${finding.test}`, /capture|descriptor|inode/i);
});

test('native ssh effective-config finding maps to real ssh -G evidence', () => {
  const finding = subject().IMPORTANT_FINDINGS.find((entry) => entry.id === 'R5-I-2');
  assert.match(`${finding.architecture} ${finding.test}`, /ssh -G|effective config/i);
});

test('sanitized errors never include input values', () => {
  const sanitized = subject().sanitizeError(Object.assign(new Error('synthetic-sensitive-value'), { code: 'ENV_SCHEMA' }));
  assert.equal(sanitized.includes('synthetic-sensitive-value'), false);
  assert.equal(sanitized, 'ERROR ENV_SCHEMA');
});

test('self-test output contains no source values, host or IP', () => {
  const result = spawnSync(process.execPath, [new URL('./create-ios-staging-bridge-config.mjs', import.meta.url).pathname, '--self-test'], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, CI3_SENTINEL: 'must-not-be-reported' },
  });
  assert.equal(result.status, 0);
  assert.equal(`${result.stdout}${result.stderr}`.includes('must-not-be-reported'), false);
  assert.match(result.stdout, /^SELF_TEST PASS tests=\d+ network_calls=0\n$/);
});

test('self-test does not accept a value through argv', () => {
  const result = spawnSync(process.execPath, [new URL('./create-ios-staging-bridge-config.mjs', import.meta.url).pathname, '--self-test', 'synthetic-sensitive-value'], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.equal(`${result.stdout}${result.stderr}`.includes('synthetic-sensitive-value'), false);
});

test('self-test reports zero network calls', () => {
  const result = spawnSync(process.execPath, [new URL('./create-ios-staging-bridge-config.mjs', import.meta.url).pathname, '--self-test'], { encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /network_calls=0/);
});

test('stable identity covers owner mode links size time device and inode', () => {
  const stable = {
    uid: 0n,
    gid: 0n,
    mode: 0o100600n,
    nlink: 1n,
    size: 128n,
    mtimeNs: 11n,
    dev: 12n,
    ino: 13n,
  };
  for (const [key, value] of Object.entries({ uid: 1n, gid: 1n, mode: 0o100640n, nlink: 2n, size: 129n, mtimeNs: 12n, dev: 14n, ino: 15n })) {
    expectCode('INPUT_MUTATED', () => subject().assertStableIdentity(stable, { ...stable, [key]: value }));
  }
});

test('parent identity covers owner mode links time device and inode', () => {
  const stable = { uid: 0n, gid: 0n, mode: 0o40700n, nlink: 2n, size: 64n, mtimeNs: 21n, dev: 22n, ino: 23n };
  expectCode('INPUT_MUTATED', () => subject().assertStableIdentity(stable, { ...stable, mode: 0o40750n }));
});

test('receipt creation time is deterministically bound to the authority commit', () => {
  const fixture = validFixture();
  fixture.authority.committed_at_utc = '2026-08-29T10:00:00.000Z';
  const validated = validate(fixture);
  const first = subject().buildBundleArtifacts({
    authority: fixture.authority,
    createdAt: '2026-08-29T12:00:00.000Z',
    credentialSourcePath: subject().INPUT_PATHS.credential,
    hashes: fixture.hashes,
    validated,
  });
  const second = subject().buildBundleArtifacts({
    authority: fixture.authority,
    createdAt: '2026-08-30T12:00:00.000Z',
    credentialSourcePath: subject().INPUT_PATHS.credential,
    hashes: fixture.hashes,
    validated,
  });
  assert.equal(first.receipt.created_at_utc, fixture.authority.committed_at_utc);
  assert.equal(second.receiptBytes, first.receiptBytes);
});

test('preview deployment count is derived by source validation', () => {
  const validated = validate();
  assert.equal(validated.previewDeploymentCount, 1);
});

for (const [name, mutate, code] of [
  ['env receipt schema version', (fixture) => { fixture.envReceipt.schema_version = 2; }, 'ENV_RECEIPT_STATE'],
  ['env receipt purpose', (fixture) => { fixture.envReceipt.purpose = 'other'; }, 'ENV_RECEIPT_STATE'],
  ['env receipt authority source', (fixture) => { fixture.envReceipt.control_plane_source = 'operator_input'; }, 'ENV_RECEIPT_STATE'],
  ['deployment schema version', (fixture) => { fixture.deploymentReceipt.schema_version = 2; }, 'DEPLOYMENT_RECEIPT_STATE'],
  ['deployment purpose', (fixture) => { fixture.deploymentReceipt.purpose = 'other'; }, 'DEPLOYMENT_RECEIPT_STATE'],
  ['deployment origin digest relation', (fixture) => { fixture.deploymentReceipt.origin_sha256 = '0'.repeat(64); }, 'PREVIEW_ORIGIN'],
  ['deployment route counts relation', (fixture) => { fixture.deploymentReceipt.mobile_route_count = 39; }, 'DEPLOYMENT_RECEIPT_STATE'],
  ['deployment probe counts relation', (fixture) => { fixture.deploymentReceipt.public_probes.passed = 29; }, 'DEPLOYMENT_RECEIPT_STATE'],
  ['provisioning schema version', (fixture) => { fixture.provisioningReceipt.schema_version = 2; }, 'PROVISIONING_RECEIPT_STATE'],
  ['provisioning purpose', (fixture) => { fixture.provisioningReceipt.purpose = 'other'; }, 'PROVISIONING_RECEIPT_STATE'],
  ['provisioning authority shape', (fixture) => { fixture.provisioningReceipt.authority_sha = 'not-a-sha'; }, 'PROVISIONING_RECEIPT_STATE'],
  ['provisioning implementation tree binding', (fixture) => { fixture.provisioningReceipt.implementation_tree = '0'.repeat(40); }, 'IMPLEMENTATION_SHA'],
  ['provisioning fixture counts', (fixture) => { fixture.provisioningReceipt.fixture_counts.progress = 1; }, 'PROVISIONING_RECEIPT_STATE'],
]) {
  test(`rejects critical ${name}`, () => {
    const fixture = validFixture();
    mutate(fixture);
    expectCode(code, () => validate(fixture));
  });
}

test('publication claim is deterministic durable and precedes staging', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-claim-first-'));
  const artifacts = build();
  const trace = [];
  const result = await subject().publishAtomic({
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
    trace,
  });
  assert.equal(result.status, 'CREATED');
  assert.match(result.claimPath, new RegExp(`${artifacts.receipt.remote_bundle_generation_id}\\.claim\\.json$`));
  assert.ok(trace.indexOf('fsync:claim') < trace.indexOf('mkdir:staging'));
});

test('a crash immediately after the durable claim consumes generation without staging', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-claim-crash-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  await assert.rejects(subject().publishAtomic({ ...options, hooks: { afterClaimFsynced: () => { throw new Error('synthetic crash'); } } }));
  await assert.rejects(subject().publishAtomic(options), (error) => error?.code === 'CLAIM_CONSUMED_NO_CAPTURE');
});

test('recovery after staged capture uses captured bytes and ignores a rerender', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-capture-recovery-'));
  const first = build();
  const options = {
    authoritySha: first.receipt.authority_commit,
    configBytes: Buffer.from(first.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(first.receiptBytes),
  };
  await assert.rejects(subject().publishAtomic({ ...options, hooks: { afterStagingFsynced: () => { throw new Error('synthetic crash'); } } }));
  const divergentRerender = Buffer.from(first.receiptBytes.replace(first.receipt.created_at_utc, '2099-01-01T00:00:00.000Z'));
  const recovered = await subject().publishAtomic({ ...options, configBytes: Buffer.from('divergent\n'), receiptBytes: divergentRerender });
  assert.equal(recovered.status, 'RECOVERED');
  assert.equal(await readFile(path.join(recovered.finalPath, 'mobile-staging-config.json'), 'utf8'), first.configBytes);
});

test('concurrent publication has one durable claim and one verified result', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-concurrency-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  const results = await Promise.allSettled([subject().publishAtomic(options), subject().publishAtomic(options)]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 2);
  assert.deepEqual(results.map((result) => result.value.status).sort(), ['CREATED', 'EXISTS_VERIFIED']);
});

test('receipt-last commit marker prevents overwrite when a final receipt races publication', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-receipt-race-'));
  const artifacts = build();
  await assert.rejects(subject().publishAtomic({
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    hooks: {
      beforeReceiptCommit: async ({ finalPath }) => {
        await writeFile(path.join(finalPath, 'bridge.receipt.json'), '{}\n', { flag: 'wx', mode: 0o600 });
      },
    },
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  }), (error) => error?.code === 'FINAL_PATH_RACE');
  assert.equal(await readFile(path.join(generationPublicationPath(root, artifacts), 'bridge.receipt.json'), 'utf8'), '{}\n');
});

test('exact existing bundle rejects permissive root final and file modes', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-existing-modes-'));
  const artifacts = build();
  const options = { authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) };
  const first = await subject().publishAtomic(options);
  await chmod(first.finalPath, 0o755);
  await assert.rejects(subject().publishAtomic(options), (error) => error?.code === 'EXISTING_BUNDLE_DIVERGENT');
});

test('exact existing bundle rejects a hardlinked entry', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-existing-hardlink-'));
  const artifacts = build();
  const options = { authoritySha: artifacts.receipt.authority_commit, configBytes: Buffer.from(artifacts.configBytes), outputRoot: root, receiptBytes: Buffer.from(artifacts.receiptBytes) };
  const first = await subject().publishAtomic(options);
  await link(path.join(first.finalPath, 'mobile-staging-config.json'), path.join(root, 'extra-link'));
  await assert.rejects(subject().publishAtomic(options), (error) => error?.code === 'EXISTING_BUNDLE_DIVERGENT');
});

test('directory chain validation rejects a symlink component', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-chain-'));
  const real = path.join(root, 'real');
  const linked = path.join(root, 'linked');
  await mkdir(real, { mode: 0o700 });
  await symlink(real, linked);
  await assert.rejects(subject().validateDirectoryChainNoSymlinks(path.join(linked, 'child'), root), (error) => error?.code === 'DIRECTORY_CHAIN');
});

test('generator snapshot validation binds executable bytes to the Git blob without pathname hash-object', async () => {
  const bytes = Buffer.from('synthetic committed generator\n');
  const before = { uid: BigInt(process.getuid()), gid: BigInt(process.getgid()), mode: 0o100600n, nlink: 1n, size: BigInt(bytes.length), mtimeNs: 1n, dev: 2n, ino: 3n };
  assert.equal(subject().verifyExecutableSnapshot({
    after: { ...before },
    before,
    expectedBlobSha: subject().gitBlobSha(bytes),
    gitBlobBytes: bytes,
    snapshotBytes: bytes,
  }), true);
});

test('generator snapshot validation rejects a generation swap', () => {
  const bytes = Buffer.from('synthetic committed generator\n');
  const before = { uid: BigInt(process.getuid()), gid: BigInt(process.getgid()), mode: 0o100600n, nlink: 1n, size: BigInt(bytes.length), mtimeNs: 1n, dev: 2n, ino: 3n };
  expectCode('GENERATOR_SNAPSHOT', () => subject().verifyExecutableSnapshot({
    after: { ...before, ino: 4n },
    before,
    expectedBlobSha: subject().gitBlobSha(bytes),
    gitBlobBytes: bytes,
    snapshotBytes: Buffer.from('swapped generator\n'),
  }));
});

test('local publication receipt is pre-terminal and cannot claim install or scans', () => {
  const receipt = subject().buildLocalPublicationReceipt({
    authoritySha: 'a'.repeat(40),
    claimResultHashes: ['b'.repeat(64)],
    localConfigSha256: 'c'.repeat(64),
    localCredentialSha256: 'd'.repeat(64),
    remoteReceiptSha256: 'e'.repeat(64),
    simulatorGateSha256: 'f'.repeat(64),
    sshEffectiveConfigSha256: '1'.repeat(64),
  });
  assert.equal(receipt.purpose, 'CI3_LOCAL_PUBLICATION_RECEIPT_V1');
  assert.equal('scan_phase_hashes' in receipt, false);
  assert.equal('installation_receipt_sha256' in receipt, false);
  assert.equal(receipt.terminal_state, 'PRE_TERMINAL');
});

test('terminal receipt binds publication installation scans and every Important finding', () => {
  const receipt = subject().buildTerminalReceipt({
    authoritySha: 'a'.repeat(40),
    installationReceiptSha256: 'b'.repeat(64),
    localPublicationReceiptSha256: 'c'.repeat(64),
    scanPhaseHashes: [
      ['argv', '1'], ['history', '2'], ['terminal-log', '3'],
      ['attachment', '4'], ['xcresult', '5'], ['runtime', '6'],
    ].map(([id, value]) => ({ id, claim_sha256: value.repeat(64), result_sha256: value.repeat(64), receipt_sha256: value.repeat(64) })),
    simulatorPhaseRootSha256: 'f'.repeat(64),
  });
  assert.equal(receipt.purpose, 'CI3_TERMINAL_BRIDGE_RECEIPT_V1');
  assert.equal(receipt.terminal_state, 'TERMINAL_PASS');
  assert.deepEqual(receipt.important_ids, subject().TERMINAL_IMPORTANT_FINDING_IDS);
  assert.equal(receipt.important_ids.length, 24);
  assert.deepEqual(receipt.scan_phase_receipts.map(({ id }) => id), ['argv', 'history', 'terminal-log', 'attachment', 'xcresult', 'runtime']);
});

test('terminal receipt rejects an incomplete two-scan chain', () => {
  expectCode('TERMINAL_RECEIPT', () => subject().buildTerminalReceipt({
    authoritySha: 'a'.repeat(40),
    installationReceiptSha256: 'b'.repeat(64),
    localPublicationReceiptSha256: 'c'.repeat(64),
    scanPhaseHashes: ['d'.repeat(64), 'e'.repeat(64)],
    simulatorPhaseRootSha256: 'f'.repeat(64),
  }));
});

test('generator and executable authority share the one exact commit subject', () => {
  const fixture = validFixture();
  fixture.authority.subject = 'build(ops): reconcile staging env receipt for CI-3 bridge';
  assert.doesNotThrow(() => build(fixture));
});

test('external terminal anchor rejects a self-consistent receipt and anchor rewrite', () => {
  const terminal = Buffer.from('{"terminal":"first"}\n');
  const anchor = buildAuthorizedTerminalAnchor({
    authoritySha: 'a'.repeat(40),
    terminalReceiptPath: '/Library/Application Support/Agentempp/ci3/terminal/a/terminal-bridge.receipt.v1.json',
    terminalReceiptSha256: subject().sha256(terminal),
  });
  const anchorBytes = Buffer.from(`${JSON.stringify(anchor)}\n`);
  const authorityAnchorSha256 = subject().sha256(anchorBytes);
  const rewrittenTerminal = Buffer.from('{"terminal":"rewritten"}\n');
  const rewrittenAnchor = buildAuthorizedTerminalAnchor({
    authoritySha: 'a'.repeat(40),
    terminalReceiptPath: anchor.terminal_receipt_path,
    terminalReceiptSha256: subject().sha256(rewrittenTerminal),
  });
  expectCode('TERMINAL_ANCHOR_HASH', () => subject().verifyExternalTerminalAnchor({
    anchorBytes: Buffer.from(`${JSON.stringify(rewrittenAnchor)}\n`),
    expectedAnchorSha256: authorityAnchorSha256,
    expectedPath: anchor.terminal_receipt_path,
    terminalReceiptBytes: rewrittenTerminal,
  }));
});

test('ssh trust descriptor requires a VPS-pass hash binding and fixed native policy', () => {
  const descriptor = {
    schema_version: 1,
    purpose: 'CI3_MAC_FETCH_TRUST_DESCRIPTOR_V1',
    authority_sha: 'a'.repeat(40),
    remote_receipt_sha256: 'b'.repeat(64),
    alias: 'ci3-authority-a',
    destination_sha256: 'c'.repeat(64),
    port: 22,
    user: 'root',
    identity_path_sha256: 'd'.repeat(64),
    identity_public_key_sha256: 'e'.repeat(64),
    host_key_ed25519_sha256: 'f'.repeat(64),
    ssh_executable_sha256: '1'.repeat(64),
  };
  const descriptorBytes = Buffer.from(`${JSON.stringify(descriptor)}\n`);
  assert.equal(subject().validateMacFetchTrustDescriptor({ descriptor, expectedSha256: subject().sha256(descriptorBytes), descriptorBytes }), true);
  expectCode('SSH_TRUST_DESCRIPTOR_HASH', () => subject().validateMacFetchTrustDescriptor({ descriptor, expectedSha256: '0'.repeat(64), descriptorBytes }));
});

test('simulator gate validates exact bundle destination phase and physical metadata contracts', () => {
  const receipt = {
    schema_version: 1,
    purpose: 'CI3_SIMULATOR_GATE_RECEIPT_V1',
    authority_sha: 'a'.repeat(40),
    device_selection_sha256: 'b'.repeat(64),
    runtime_sha256: 'c'.repeat(64),
    bundle_id: 'com.bodyflow.app',
    container_identity_sha256: 'd'.repeat(64),
    config_relative_path: 'Library/Application Support/Agentempp/mobile-staging-config.json',
    credential_relative_path: 'Library/Application Support/Agentempp/synthetic-patient.credentials.json',
    probe_schema_version: 1,
    probe_sha256: 'e'.repeat(64),
    ack_sha256: 'f'.repeat(64),
    attempts: { resolve: 1, install_probe: 1, launch_probe: 1, consume_probe: 1, remove_probe: 1 },
    physical_effects_sha256: '1'.repeat(64),
    terminal_state: 'SIMULATOR_GATE_PASS',
  };
  assert.equal(subject().validateSimulatorGateReceipt(receipt), true);
  receipt.bundle_id = 'com.example.other';
  expectCode('SIMULATOR_GATE_SCHEMA', () => subject().validateSimulatorGateReceipt(receipt));
});

test('installation receipt freezes install binary destinations and readback metadata', () => {
  const receipt = {
    schema_version: 1,
    purpose: 'CI3_SIMULATOR_INSTALL_RECEIPT_V1',
    authority_sha: 'a'.repeat(40),
    install_executable: '/usr/bin/install',
    install_mode: '0600',
    config_relative_path: 'Library/Application Support/Agentempp/mobile-staging-config.json',
    credential_relative_path: 'Library/Application Support/Agentempp/synthetic-patient.credentials.json',
    config_sha256: 'b'.repeat(64),
    credential_sha256: 'c'.repeat(64),
    config_metadata_sha256: 'd'.repeat(64),
    credential_metadata_sha256: 'e'.repeat(64),
    physical_readback_sha256: 'f'.repeat(64),
  };
  assert.equal(subject().validateInstallationReceipt(receipt), true);
  receipt.install_mode = '0644';
  expectCode('INSTALL_RECEIPT_SCHEMA', () => subject().validateInstallationReceipt(receipt));
});

test('recovery completes a partial final directory after config promotion without rerender', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-partial-final-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  await assert.rejects(subject().publishAtomic({ ...options, hooks: { afterConfigPublished: () => { throw new Error('synthetic crash'); } } }));
  const result = await subject().publishAtomic({ ...options, configBytes: Buffer.from('rerender forbidden\n') });
  assert.equal(result.status, 'RECOVERED');
  assert.deepEqual((await readdir(result.finalPath)).sort(), ['bridge.receipt.json', 'mobile-staging-config.json']);
});

test('existing publication rejects a wrong-purpose receipt even when the durable claim hash is rewritten consistently', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-existing-wrong-purpose-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  const created = await subject().publishAtomic(options);
  const receiptPath = path.join(created.finalPath, 'bridge.receipt.json');
  const receipt = JSON.parse(await readFile(receiptPath, 'utf8'));
  receipt.purpose = 'SYNTHETIC_BYPASS_ATTEMPT';
  const receiptBytes = Buffer.from(`${JSON.stringify(receipt)}\n`);
  await writeFile(receiptPath, receiptBytes);
  const claim = JSON.parse(await readFile(created.claimPath, 'utf8'));
  claim.receipt_sha256 = subject().sha256(receiptBytes);
  await writeFile(created.claimPath, `${JSON.stringify(claim)}\n`);

  await assert.rejects(subject().publishAtomic(options), (error) => error?.code === 'PUBLISHED_CONTRACT');
});

test('recovery rejects a missing-purpose staged receipt even when the durable claim hash is rewritten consistently', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-recovery-missing-purpose-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  await assert.rejects(subject().publishAtomic({
    ...options,
    hooks: { afterStagingFsynced: () => { throw new Error('synthetic crash'); } },
  }));
  const stagingReceiptPath = path.join(stagingPublicationPath(root, artifacts), 'bridge.receipt.json');
  const stagedReceipt = JSON.parse(await readFile(stagingReceiptPath, 'utf8'));
  delete stagedReceipt.purpose;
  const stagedReceiptBytes = Buffer.from(`${JSON.stringify(stagedReceipt)}\n`);
  await writeFile(stagingReceiptPath, stagedReceiptBytes);
  const claimPath = publicationClaimPath(root, artifacts);
  const claim = JSON.parse(await readFile(claimPath, 'utf8'));
  claim.receipt_sha256 = subject().sha256(stagedReceiptBytes);
  await writeFile(claimPath, `${JSON.stringify(claim)}\n`);

  await assert.rejects(subject().publishAtomic(options), (error) => error?.code === 'PUBLISHED_CONTRACT');
});

test('receipt-last visibility classifies a config-only final directory as unpublished until recovery commits the marker', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-visibility-boundary-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  await assert.rejects(subject().publishAtomic({
    ...options,
    hooks: { afterConfigPublished: () => { throw new Error('synthetic crash'); } },
  }));
  const finalPath = generationPublicationPath(root, artifacts);
  assert.equal(await readFile(path.join(finalPath, 'mobile-staging-config.json'), 'utf8'), artifacts.configBytes);
  assert.equal(await subject().inspectPublicationVisibility({ finalPath }), 'UNPUBLISHED');

  const recovered = await subject().publishAtomic(options);
  assert.equal(recovered.status, 'RECOVERED');
  assert.equal(await subject().inspectPublicationVisibility({ finalPath }), 'COMMIT_MARKER_PRESENT_REQUIRES_VALIDATION');
});

test('terminal anchor preparation stops without hash-bound privileged-writer authority', () => {
  const authoritySha = 'a'.repeat(40);
  expectCode('PRIVILEGED_ANCHOR_WRITER_AUTHORITY', () => subject().validatePrivilegedAnchorWriterAuthority({
    authority: undefined,
    authorityBytes: Buffer.alloc(0),
    bridgeAuthoritySha: authoritySha,
    expectedSha256: '0'.repeat(64),
  }));

  const authority = {
    schema_version: 1,
    purpose: 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1',
    bridge_authority_sha: authoritySha,
    writer_identity_sha256: 'b'.repeat(64),
    anchor_path_sha256: 'c'.repeat(64),
    controller_receipt_sha256: 'd'.repeat(64),
    executable_sha256: 'e'.repeat(64),
    uid: 0,
    gid: 0,
    open_flags: 'O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW',
    file_mode: '0444',
    immutable_flag: 'UF_IMMUTABLE',
    normal_executor_authorized: false,
  };
  const authorityBytes = Buffer.from(`${JSON.stringify(authority)}\n`);
  assert.equal(subject().validatePrivilegedAnchorWriterAuthority({
    authority,
    authorityBytes,
    bridgeAuthoritySha: authoritySha,
    expectedSha256: subject().sha256(authorityBytes),
  }), true);
});

test('terminal anchor record builder refuses to infer privileged-writer authority', () => {
  expectCode('PRIVILEGED_ANCHOR_WRITER_AUTHORITY', () => subject().buildTerminalAnchorRecord({
    authoritySha: 'a'.repeat(40),
    terminalAnchorPath: '/Library/Application Support/Agentempp/ci3-terminal-authority/a/terminal.anchor.v1.json',
    terminalReceiptPath: '/Library/Application Support/Agentempp/ci3/terminal/a/terminal-bridge.receipt.v1.json',
    terminalReceiptSha256: 'b'.repeat(64),
  }));
});

test('external terminal anchor requires immutable root-owned physical identity', () => {
  const terminal = Buffer.from('{"terminal":"first"}\n');
  const anchor = buildAuthorizedTerminalAnchor({
    authoritySha: 'a'.repeat(40),
    terminalReceiptPath: '/Library/Application Support/Agentempp/ci3/terminal/a/terminal-bridge.receipt.v1.json',
    terminalReceiptSha256: subject().sha256(terminal),
  });
  const anchorBytes = Buffer.from(`${JSON.stringify(anchor)}\n`);
  expectCode('TERMINAL_ANCHOR_IDENTITY', () => subject().verifyExternalTerminalAnchor({
    anchorBytes,
    anchorMetadata: { uid: 501, gid: 20, mode: 0o100600, nlink: 1, flags: 0 },
    expectedAnchorSha256: subject().sha256(anchorBytes),
    expectedPath: anchor.terminal_receipt_path,
    terminalReceiptBytes: terminal,
  }));
});

test('recovery completes a crash between no-replace link and staging de-link', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-link-crash-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  await assert.rejects(subject().publishAtomic({ ...options, hooks: { afterConfigLinked: () => { throw new Error('synthetic crash'); } } }));
  const recovered = await subject().publishAtomic(options);
  assert.equal(recovered.status, 'RECOVERED');
  assert.equal((await stat(path.join(recovered.finalPath, 'mobile-staging-config.json'), { bigint: true })).nlink, 1n);
  assert.equal((await stat(path.join(recovered.finalPath, 'bridge.receipt.json'), { bigint: true })).nlink, 1n);
});

const EXECUTABLE_COMPONENT_EXPECTATIONS = Object.freeze([
  ['controller_blob_oid', '2'.repeat(40)],
  ['controller_file_sha256', '3'.repeat(64)],
  ['launcher_blob_oid', '4'.repeat(40)],
  ['launcher_file_sha256', '5'.repeat(64)],
  ['anchor_writer_blob_oid', '6'.repeat(40)],
  ['anchor_writer_file_sha256', '7'.repeat(64)],
]);

for (const [field, expected] of EXECUTABLE_COMPONENT_EXPECTATIONS) {
  test(`remote receipt binds exact executable provenance field ${field}`, () => {
    assert.equal(build().receipt[field], expected);
  });
}

test('remote receipt binds the exact fifteen-path authority tree manifest', () => {
  assert.equal(build().receipt.authority_tree_manifest_sha256, '8'.repeat(64));
});

test('remote receipt binds the remote bundle generation', () => {
  assert.equal(build().receipt.remote_bundle_generation_id, 'rb-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
});

test('remote receipt binds the source generation', () => {
  assert.equal(build().receipt.source_generation_id, 'src-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
});

test('remote receipt binds the source env descriptor physical identity', () => {
  assert.equal(build().receipt.source_env_descriptor_identity_sha256, '9'.repeat(64));
});

test('remote receipt freezes the exact ordered six terminal scan IDs', () => {
  assert.deepEqual(build().receipt.terminal_scan_ids, ['argv', 'history', 'terminal-log', 'attachment', 'xcresult', 'runtime']);
});

test('authority manifest requires exactly fifteen Git paths', () => {
  const entries = Array.from({ length: 15 }, (_, index) => ({
    path: `synthetic/path-${String(index).padStart(2, '0')}`,
    blob_oid: `${(index % 9) + 1}`.repeat(40),
    sha256: `${(index % 9) + 1}`.repeat(64),
  }));
  assert.equal(subject().validateAuthorityTreeManifest(entries), true);
});

test('authority manifest rejects a thirteen-only path set', () => {
  const entries = Array.from({ length: 13 }, (_, index) => ({
    path: `synthetic/path-${String(index).padStart(2, '0')}`,
    blob_oid: 'a'.repeat(40),
    sha256: 'b'.repeat(64),
  }));
  expectCode('AUTHORITY_TREE_MANIFEST', () => subject().validateAuthorityTreeManifest(entries));
});

test('authority manifest rejects duplicate Git paths', () => {
  const entries = Array.from({ length: 15 }, (_, index) => ({
    path: index === 14 ? 'synthetic/path-00' : `synthetic/path-${String(index).padStart(2, '0')}`,
    blob_oid: 'a'.repeat(40),
    sha256: 'b'.repeat(64),
  }));
  expectCode('AUTHORITY_TREE_MANIFEST', () => subject().validateAuthorityTreeManifest(entries));
});

test('authority manifest rejects a malformed executable blob oid', () => {
  const fixture = validFixture();
  fixture.authority.controller_blob_oid = 'not-a-blob';
  expectCode('AUTHORITY_COMPONENTS', () => build(fixture));
});

test('authority manifest rejects a malformed executable file digest', () => {
  const fixture = validFixture();
  fixture.authority.anchor_writer_file_sha256 = 'not-a-digest';
  expectCode('AUTHORITY_COMPONENTS', () => build(fixture));
});

test('original generator claim freezes all executable and generation bindings', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-full-claim-'));
  const artifacts = build();
  const result = await subject().publishAtomic({
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  });
  const claim = JSON.parse(await readFile(result.claimPath, 'utf8'));
  assert.equal(claim.authority_tree_manifest_sha256, artifacts.receipt.authority_tree_manifest_sha256);
  assert.equal(claim.remote_bundle_generation_id, artifacts.receipt.remote_bundle_generation_id);
  assert.equal(claim.controller_blob_oid, artifacts.receipt.controller_blob_oid);
});

test('exact-existing rejects an original claim with rewritten controller provenance', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-claim-controller-drift-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  const result = await subject().publishAtomic(options);
  const claim = JSON.parse(await readFile(result.claimPath, 'utf8'));
  claim.controller_blob_oid = '0'.repeat(40);
  await writeFile(result.claimPath, `${JSON.stringify(claim)}\n`);
  await assert.rejects(subject().publishAtomic(options), (error) => ['PUBLICATION_CLAIM', 'PUBLISHED_CONTRACT'].includes(error?.code));
});

test('exact-existing rejects a published bundle whose remote generation is rewritten self-consistently', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-generation-drift-'));
  const artifacts = build();
  const options = {
    authoritySha: artifacts.receipt.authority_commit,
    configBytes: Buffer.from(artifacts.configBytes),
    outputRoot: root,
    receiptBytes: Buffer.from(artifacts.receiptBytes),
  };
  const result = await subject().publishAtomic(options);
  const receiptPath = path.join(result.finalPath, 'bridge.receipt.json');
  const receipt = JSON.parse(await readFile(receiptPath, 'utf8'));
  receipt.remote_bundle_generation_id = 'rb-cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  const receiptBytes = Buffer.from(`${JSON.stringify(receipt)}\n`);
  await writeFile(receiptPath, receiptBytes);
  const claim = JSON.parse(await readFile(result.claimPath, 'utf8'));
  claim.receipt_sha256 = subject().sha256(receiptBytes);
  await writeFile(result.claimPath, `${JSON.stringify(claim)}\n`);
  await assert.rejects(subject().publishAtomic(options), (error) => error?.code === 'PUBLISHED_CONTRACT');
});
