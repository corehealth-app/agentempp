import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, sign as ed25519Sign } from 'node:crypto';
import { chmod, link, lstat, mkdtemp, mkdir, readFile, readdir, rename, rm, stat, symlink, utimes, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const MODULE_URL = new URL('./ci3-bridge-controller.mjs', import.meta.url);

let controller;
let loadError;
try {
  controller = await import(MODULE_URL);
} catch (error) {
  loadError = error;
}

const descriptorHelperPath = null;
const descriptorHelperSha256 = null;

function subject() {
  assert.ifError(loadError);
  return controller;
}

function expectCode(code, operation) {
  assert.throws(operation, (error) => error?.code === code);
}

async function rejectCode(code, operation) {
  await assert.rejects(operation, (error) => error?.code === code);
}

const SCAN_IDS = Object.freeze(['argv', 'history', 'terminal-log', 'attachment', 'xcresult', 'runtime']);
const FINDING_IDS = Object.freeze([
  'RA1-I-5', 'A4-I-1', 'A4-I-3', 'A5-I-1', 'A5-I-2',
  'RA0-I-4', 'RA0-I-7', 'R2-I-2', 'R5-I-1', 'R5-I-2', 'R5-I-3',
  ...Array.from({ length: 6 }, (_, index) => `RA-FINAL-I-${index + 1}`),
  ...Array.from({ length: 7 }, (_, index) => `RB-FINAL-I-${index + 1}`),
]);

function digest(character) {
  return character.repeat(64);
}

function oid(character) {
  return character.repeat(40);
}

function generation(prefix, character) {
  return `${prefix}-${digest(character)}`;
}

function authorityManifest() {
  const paths = [
    'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md',
    'docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md',
    'docs/superpowers/evidence/2026-08-31-ci3-bridge-git-blob-reader-stop-and-authority.md',
    'docs/superpowers/evidence/2026-08-31-ci3-env-receipt-reconciliation-authority.md',
    'docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md',
    'docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md',
    'docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md',
    'scripts/ci3/create-ios-staging-bridge-config.mjs',
    'scripts/ci3/create-ios-staging-bridge-config.test.mjs',
    'scripts/ci3/ci3-bridge-controller.mjs',
    'scripts/ci3/ci3-bridge-controller.test.mjs',
    'scripts/ci3/ci3-bridge-launcher.zsh',
    'scripts/ci3/ci3-bridge-launcher.test.mjs',
    'scripts/ci3/ci3-terminal-anchor-writer.swift',
    'scripts/ci3/ci3-terminal-anchor-writer.test.mjs',
  ];
  const entries = paths.map((entryPath, index) => ({
    path: entryPath,
    blob_oid: oid(String((index % 9) + 1)),
    sha256: digest(String((index % 9) + 1)),
  }));
  for (const [name, component] of Object.entries(components())) {
    const entry = entries.find(({ path: entryPath }) => entryPath === component.path);
    entry.blob_oid = component.blob_oid;
    entry.sha256 = component.sha256;
    assert.ok(name);
  }
  return entries;
}

function components() {
  return {
    generator: { path: 'scripts/ci3/create-ios-staging-bridge-config.mjs', blob_oid: oid('1'), sha256: digest('1') },
    controller: { path: 'scripts/ci3/ci3-bridge-controller.mjs', blob_oid: oid('2'), sha256: digest('2') },
    launcher: { path: 'scripts/ci3/ci3-bridge-launcher.zsh', blob_oid: oid('3'), sha256: digest('3') },
    writer: { path: 'scripts/ci3/ci3-terminal-anchor-writer.swift', blob_oid: oid('4'), sha256: digest('4') },
  };
}

function baseContext() {
  return {
    authority: {
      commit: oid('a'),
      parent: '456b4643d1a310bc88458a28a9a62a16dde2e1c8',
      tree: oid('b'),
      subject: 'build(ops): reconcile staging env receipt for CI-3 bridge',
      committed_at_utc: '2026-08-30T12:00:00.000Z',
      manifest_sha256: digest('c'),
      components: components(),
    },
    generations: {
      remote: generation('remote', 'd'),
      controller: generation('controller', 'e'),
      simulator: generation('simulator', 'f'),
      terminal: generation('terminal', '1'),
    },
    remote: {
      bundle_path_sha256: digest('2'),
      receipt_path_sha256: digest('3'),
      receipt_sha256: digest('4'),
      config_path_sha256: digest('5'),
      config_sha256: digest('6'),
      credential_path_sha256: digest('7'),
      credential_sha256: digest('8'),
    },
    ssh: {
      executable_sha256: digest('9'),
      code_signature_sha256: digest('a'),
      effective_config_sha256: digest('b'),
      config_sha256: digest('c'),
      known_hosts_sha256: digest('d'),
      identity_public_key_sha256: digest('e'),
      host_key_ed25519_sha256: digest('f'),
      destination_sha256: digest('0'),
      version_sha256: digest('1'),
      trust_descriptor_sha256: digest('2'),
    },
    simulator_gate_sha256: digest('2'),
  };
}

function launchAttestation() {
  return {
    schema_version: 1,
    purpose: 'CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2',
    authority_sha: oid('a'),
    authority_parent: '456b4643d1a310bc88458a28a9a62a16dde2e1c8',
    authority_tree: oid('b'),
    authority_subject_sha256: digest('c'),
    authority_manifest_sha256: digest('d'),
    components: components(),
    tools: {
      node: { path_sha256: digest('1'), binary_sha256: digest('2'), version_sha256: digest('3') },
      ssh: { path_sha256: digest('4'), binary_sha256: digest('5'), version_sha256: digest('6') },
      swiftc: { path_sha256: digest('7'), binary_sha256: digest('8'), version_sha256: digest('9') },
      xcodebuild: { path_sha256: digest('a'), binary_sha256: digest('b'), version_sha256: digest('c') },
    },
    raw_values: false,
  };
}

function metadata(overrides = {}) {
  return {
    uid: process.getuid?.() ?? 0,
    gid: process.getgid?.() ?? 0,
    mode: 0o100600,
    nlink: 1,
    size: 128,
    mtime_ns: '1700000000000000000',
    dev: '1',
    ino: '2',
    type: 'file',
    symlink: false,
    ...overrides,
  };
}

const PUBLIC_MODES = Object.freeze([
  '--self-test', 'plan', 'verify-simulator', 'verify-ssh', 'fetch',
  'install-simulator', 'scan', 'write-terminal-anchor', 'resume', 'status',
]);

for (const mode of PUBLIC_MODES) {
  test(`accepts closed controller mode ${mode}`, () => {
    assert.equal(subject().parseControllerMode([mode]), mode);
  });
}

for (const argv of [[], ['unknown'], ['plan', 'extra'], ['fetch', '/tmp/path'], ['--self-test', 'value']]) {
  test(`rejects arbitrary controller argv ${JSON.stringify(argv)}`, () => {
    expectCode('MODE_INVALID', () => subject().parseControllerMode(argv));
  });
}

test('launcher attestation v2 closes commit tree manifest components and tools', () => {
  assert.equal(subject().validateLaunchAttestation(launchAttestation()), true);
});

test('controller freezes the single exact authority commit subject', () => {
  assert.equal(subject().AUTHORITY_SUBJECT, 'build(ops): reconcile staging env receipt for CI-3 bridge');
});

test('terminal ledger contains all 24 inherited and final Important IDs once and in authority order', () => {
  assert.deepEqual(subject().IMPORTANT_FINDINGS.map(({ id }) => id), FINDING_IDS);
  assert.equal(new Set(FINDING_IDS).size, 24);
});

for (const field of ['authority_parent', 'authority_tree', 'authority_manifest_sha256', 'components', 'tools', 'raw_values']) {
  test(`launcher attestation rejects missing ${field}`, () => {
    const attestation = launchAttestation();
    delete attestation[field];
    expectCode('LAUNCHER_REQUIRED', () => subject().validateLaunchAttestation(attestation));
  });
}

for (const component of ['generator', 'controller', 'launcher', 'writer']) {
  test(`launcher attestation rejects ${component} provenance drift`, () => {
    const attestation = launchAttestation();
    attestation.components[component].sha256 = 'bad';
    expectCode('LAUNCHER_REQUIRED', () => subject().validateLaunchAttestation(attestation));
  });
}

for (const tool of ['node', 'ssh', 'swiftc', 'xcodebuild']) {
  test(`launcher attestation rejects incomplete ${tool} tool identity`, () => {
    const attestation = launchAttestation();
    delete attestation.tools[tool].binary_sha256;
    expectCode('LAUNCHER_REQUIRED', () => subject().validateLaunchAttestation(attestation));
  });
}

for (const [name, value] of Object.entries({
  REMOTE_BUNDLE_GENERATION_ID: generation('remote', 'a'),
  MAC_CONTROLLER_GENERATION_ID: generation('controller', 'b'),
  SIMULATOR_INSTALL_GENERATION_ID: generation('simulator', 'c'),
  TERMINAL_ANCHOR_GENERATION_ID: generation('terminal', 'd'),
})) {
  test(`accepts exact generation grammar for ${name}`, () => {
    assert.equal(subject().validateGenerationId(value), true);
  });
}

for (const value of ['', 'remote', 'remote-short', `remote-${'G'.repeat(64)}`, `other-${'a'.repeat(63)}`]) {
  test(`rejects malformed generation ${value || '<empty>'}`, () => {
    expectCode('GENERATION_ID', () => subject().validateGenerationId(value));
  });
}

test('validates the exact fifteen-path authority manifest and components', () => {
  assert.equal(subject().validateAuthorityManifest({ entries: authorityManifest(), components: components() }), true);
});

for (const componentName of ['generator', 'controller', 'launcher', 'writer']) {
  for (const field of ['path', 'blob_oid', 'sha256']) {
    test(`authority manifest rejects ${componentName} ${field} drift`, () => {
      const manifestComponents = structuredClone(components());
      manifestComponents[componentName][field] = 'drift';
      expectCode('AUTHORITY_MANIFEST', () => subject().validateAuthorityManifest({ entries: authorityManifest(), components: manifestComponents }));
    });
  }
}

test('authority manifest rejects missing path', () => {
  expectCode('AUTHORITY_MANIFEST', () => subject().validateAuthorityManifest({ entries: authorityManifest().slice(1), components: components() }));
});

test('authority manifest rejects extra path', () => {
  expectCode('AUTHORITY_MANIFEST', () => subject().validateAuthorityManifest({ entries: [...authorityManifest(), { path: 'extra', blob_oid: oid('a'), sha256: digest('a') }], components: components() }));
});

test('authority manifest rejects duplicate path', () => {
  const entries = authorityManifest();
  entries[12] = { ...entries[12], path: entries[0].path };
  expectCode('AUTHORITY_MANIFEST', () => subject().validateAuthorityManifest({ entries, components: components() }));
});

const AUTHORITY_ENTRY_MUTATIONS = Object.freeze([
  ['absolute path', (entries, index) => { entries[index].path = '/absolute'; }],
  ['parent traversal path', (entries, index) => { entries[index].path = '../escape'; }],
  ['empty path', (entries, index) => { entries[index].path = ''; }],
  ['duplicate path', (entries, index) => { entries[index].path = entries[(index + 1) % entries.length].path; }],
  ['short blob OID', (entries, index) => { entries[index].blob_oid = 'a'.repeat(39); }],
  ['uppercase blob OID', (entries, index) => { entries[index].blob_oid = 'A'.repeat(40); }],
  ['option-like blob OID', (entries, index) => { entries[index].blob_oid = `-${'a'.repeat(39)}`; }],
  ['short SHA-256', (entries, index) => { entries[index].sha256 = 'b'.repeat(63); }],
  ['uppercase SHA-256', (entries, index) => { entries[index].sha256 = 'B'.repeat(64); }],
  ['missing path field', (entries, index) => { delete entries[index].path; }],
  ['extra field', (entries, index) => { entries[index].extra = true; }],
  ['null entry', (entries, index) => { entries[index] = null; }],
  ['out-of-order entry', (entries, index) => {
    const other = (index + 1) % entries.length;
    [entries[index], entries[other]] = [entries[other], entries[index]];
  }],
  ['whitespace blob OID', (entries, index) => { entries[index].blob_oid = `${'a'.repeat(39)} `; }],
  ['whitespace SHA-256', (entries, index) => { entries[index].sha256 = `${'b'.repeat(63)} `; }],
]);

for (const index of Array.from({ length: 15 }, (_, value) => value)) {
  for (const [label, mutate] of AUTHORITY_ENTRY_MUTATIONS) {
    test(`[AUTHORITY-15] rejects ${label} at index ${index}`, () => {
      const entries = authorityManifest();
      mutate(entries, index);
      expectCode('AUTHORITY_MANIFEST', () => subject().validateAuthorityManifest({ entries, components: components() }));
    });
  }
}

test('bootstrap claim binds every executable generation and trust root', () => {
  const claim = subject().buildBootstrapClaim(baseContext());
  assert.equal(claim.purpose, 'CI3_MAC_BRIDGE_BOOTSTRAP_CLAIM_V1');
  assert.equal(claim.attempt, 1);
  assert.equal(claim.retry, false);
  assert.deepEqual(claim.components, components());
});

const BOOTSTRAP_MUTATIONS = Object.freeze([
  ['purpose', 'wrong'], ['attempt', 2], ['retry', true],
  ['authority_sha', oid('0')], ['authority_manifest_sha256', digest('0')],
  ['remote_bundle_path_sha256', digest('0')], ['remote_receipt_path_sha256', digest('0')],
  ['simulator_gate_sha256', digest('0')], ['ssh_executable_sha256', digest('0')],
  ['ssh_effective_config_sha256', digest('0')], ['controller_generation_id', generation('controller', '0')],
  ['terminal_generation_id', generation('terminal', '0')],
]);

for (const [field, replacement] of BOOTSTRAP_MUTATIONS) {
  test(`bootstrap claim validation catches ${field} drift`, () => {
    const context = baseContext();
    const claim = subject().buildBootstrapClaim(context);
    claim[field] = replacement;
    expectCode('BOOTSTRAP_CLAIM', () => subject().validateBootstrapClaim(claim, context));
  });
}

for (const kind of ['receipt', 'config', 'credential']) {
  test(`builds ${kind} read claim before its one allowed spawn`, () => {
    const context = baseContext();
    const bootstrap = subject().buildBootstrapClaim(context);
    const claim = subject().buildReadClaim({
      kind,
      bootstrapClaimSha256: subject().sha256(subject().canonicalJson(bootstrap)),
      expectedPathSha256: context.remote[`${kind}_path_sha256`] ?? context.remote.credential_path_sha256,
      expectedSha256: context.remote[`${kind}_sha256`] ?? context.remote.credential_sha256,
      remoteGenerationId: kind === 'receipt' ? null : context.generations.remote,
      ssh: context.ssh,
    });
    assert.equal(claim.kind, kind);
    assert.equal(claim.attempt, 1);
    assert.equal(claim.retry, false);
  });
}

for (const kind of ['other', 'RECEIPT', '', '../config']) {
  test(`rejects noncanonical read kind ${kind || '<empty>'}`, () => {
    expectCode('READ_CLAIM', () => subject().buildReadClaim({ kind }));
  });
}

test('read result binds the original claim capture and effective SSH generation', () => {
  const result = subject().buildReadResult({
    kind: 'config',
    claimSha256: digest('1'),
    captureSha256: digest('2'),
    captureIdentitySha256: digest('5'),
    remoteCommandSha256: digest('6'),
    descriptorRead: true,
    bytes: 512,
    exit: 0,
    stderrClass: 'EMPTY',
    startedAt: '2026-08-30T12:00:00.000Z',
    finishedAt: '2026-08-30T12:00:01.000Z',
    sshEffectiveConfigSha256: digest('3'),
    sshTrustDescriptorSha256: digest('4'),
    remoteGenerationId: generation('remote', '4'),
  });
  assert.equal(result.raw_values, false);
  assert.equal(result.exit, 0);
});

for (const [field, value] of [
  ['exit', 1], ['bytes', -1], ['stderrClass', 'RAW stderr'], ['claimSha256', 'bad'],
  ['captureSha256', 'bad'], ['captureIdentitySha256', 'bad'], ['remoteCommandSha256', 'bad'], ['descriptorRead', false],
]) {
  test(`read result rejects invalid ${field}`, () => {
    const input = {
      kind: 'config', claimSha256: digest('1'), captureSha256: digest('2'), captureIdentitySha256: digest('5'), remoteCommandSha256: digest('6'), descriptorRead: true, bytes: 1, exit: 0,
      stderrClass: 'EMPTY', startedAt: '2026-08-30T12:00:00.000Z', finishedAt: '2026-08-30T12:00:01.000Z',
      sshEffectiveConfigSha256: digest('3'), sshTrustDescriptorSha256: digest('4'), remoteGenerationId: generation('remote', '4'),
    };
    input[field] = value;
    expectCode('READ_RESULT', () => subject().buildReadResult(input));
  });
}

for (const [field, replacement] of [
  ['uid', 99999], ['gid', 99999], ['mode', 0o100644], ['nlink', 2], ['size', -1],
  ['mtime_ns', 'bad'], ['dev', 'bad'], ['ino', 'bad'], ['type', 'directory'], ['symlink', true],
]) {
  test(`physical metadata rejects ${field} divergence`, () => {
    expectCode('PHYSICAL_METADATA', () => subject().validatePhysicalMetadata(metadata({ [field]: replacement }), {
      uid: process.getuid?.() ?? 0, gid: process.getgid?.() ?? 0, mode: 0o600,
    }));
  });
}

test('physical metadata accepts exact owner single-link 0600 file', () => {
  assert.equal(subject().validatePhysicalMetadata(metadata(), {
    uid: process.getuid?.() ?? 0, gid: process.getgid?.() ?? 0, mode: 0o600,
  }), true);
});

function simulatorReceipt() {
  return {
    schema_version: 1,
    purpose: 'CI3_SIMULATOR_GATE_RECEIPT_V2',
    authority_sha: oid('a'),
    controller_generation_id: generation('controller', 'b'),
    simulator_generation_id: generation('simulator', 'c'),
    device_selection_sha256: digest('d'),
    runtime_sha256: digest('e'),
    app_installation_sha256: digest('f'),
    source_commit: oid('1'),
    bundle_id: 'com.bodyflow.app',
    container_identity_sha256: digest('2'),
    probe_config_sha256: digest('3'),
    probe_credential_sha256: digest('4'),
    probe_ack_sha256: digest('5'),
    removal_proof_sha256: digest('6'),
    phases: ['SELECT_DEVICE', 'RESOLVE_CONTAINER', 'INSTALL_PROBE', 'LAUNCH_PROBE', 'ACK_PROBE', 'REMOVE_PROBE', 'REOBSERVE'],
    phase_receipt_hashes: Array.from({ length: 7 }, (_, index) => digest(String((index % 9) + 1))),
    attempts: { select: 1, resolve: 1, install: 1, launch: 1, ack: 1, remove: 1, reobserve: 1 },
    raw_container_path_reported: false,
    terminal_state: 'SIMULATOR_GATE_PASS',
  };
}

test('simulator gate validates exact seven-phase state machine', () => {
  assert.equal(subject().validateSimulatorGateReceipt(simulatorReceipt()), true);
});

for (const phase of simulatorReceipt().phases) {
  test(`simulator gate rejects missing phase ${phase}`, () => {
    const receipt = simulatorReceipt();
    receipt.phases = receipt.phases.filter((value) => value !== phase);
    expectCode('SIMULATOR_GATE', () => subject().validateSimulatorGateReceipt(receipt));
  });
}

for (const field of ['device_selection_sha256', 'runtime_sha256', 'app_installation_sha256', 'container_identity_sha256', 'removal_proof_sha256']) {
  test(`simulator gate rejects invalid ${field}`, () => {
    const receipt = simulatorReceipt();
    receipt[field] = 'bad';
    expectCode('SIMULATOR_GATE', () => subject().validateSimulatorGateReceipt(receipt));
  });
}

test('real ssh-G parser preserves duplicate keys and line order', () => {
  const parsed = subject().parseSshG(Buffer.from('identityfile /one\nidentityfile /two\nhostname example.invalid\n'));
  assert.deepEqual(parsed.map(({ key }) => key), ['identityfile', 'identityfile', 'hostname']);
});

test('real ssh-G parser preserves an empty native value', () => {
  assert.deepEqual(subject().parseSshG(Buffer.from('canonicaldomains \n')), [{ key: 'canonicaldomains', value: '', ordinal: 0 }]);
});

test('complete SSH descriptor binds exact native ordered duplicate-aware output and executable identity', () => {
  const records = subject().parseSshG(Buffer.from('identityfile /one\nidentityfile /two\nhostname example.invalid\n'));
  const descriptor = {
    schema_version: 1,
    purpose: 'CI3_MAC_SSH_TRUST_DESCRIPTOR_V1',
    authority_sha: oid('a'),
    remote_generation_id: generation('remote', 'b'),
    ssh_executable_path_sha256: digest('1'),
    ssh_executable_sha256: digest('2'),
    ssh_code_signature_sha256: digest('3'),
    ssh_version_sha256: digest('4'),
    isolated_config_sha256: digest('5'),
    known_hosts_sha256: digest('6'),
    identity_public_key_sha256: digest('7'),
    identity_public_key_fingerprint_sha256: digest('8'),
    host_key_ed25519_fingerprint_sha256: digest('9'),
    destination_sha256: digest('a'),
    native_records_sha256: subject().sha256(subject().canonicalJson(records)),
    native_record_count: records.length,
    native_key_order: records.map(({ key }) => key),
    raw_destination_reported: false,
  };
  assert.equal(subject().validateSshTrustDescriptor(descriptor, records), true);
});

test('remote read command is fixed exec usr-bin-cat grammar and rejects shell metacharacters', () => {
  assert.equal(subject().buildRemoteCatCommand('/root/.config/agentempp/bridges/ci3/a/file.json'), 'exec /usr/bin/cat -- /root/.config/agentempp/bridges/ci3/a/file.json');
  for (const value of ['/tmp/a;id', '/tmp/a b', '/tmp/a\n/bin/id', '-option', '/tmp/$HOME']) {
    expectCode('REMOTE_PATH', () => subject().buildRemoteCatCommand(value));
  }
});

test('semantic remote validator rejects hash-bound but authority-incompatible receipt bytes', () => {
  const context = baseContext();
  const configBytes = subject().canonicalJson({
    schema_version: 1, environment: 'staging', bridge_authority_sha: context.authority.commit,
    staging_project_ref: 'syntheticref', supabase_url: 'https://syntheticref.supabase.invalid',
    supabase_anon_key: 'synthetic', mobile_bff_origin: 'https://preview.invalid', cleanup_deadline: '2099-01-01T00:00:00.000Z',
  });
  const credentialBytes = subject().canonicalJson({ schema_version: 1, purpose: 'CI3_SYNTHETIC_PATIENT_CREDENTIAL_V1', authority_sha: context.authority.commit, remote_generation_id: context.generations.remote, opaque_credential: 'synthetic' });
  const receiptBytes = subject().canonicalJson({
    schema_version: 1, purpose: 'VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING_WITH_CANONICAL_ENV_RECEIPT_V1', authority_commit: oid('0'),
    authority_parent: context.authority.parent, authority_tree: context.authority.tree,
    authority_subject: context.authority.subject, authority_tree_manifest_sha256: context.authority.manifest_sha256,
    remote_bundle_generation_id: context.generations.remote, output_config_sha256: subject().sha256(configBytes),
    credential_source_sha256: subject().sha256(credentialBytes), terminal_scan_ids: SCAN_IDS,
    components: context.authority.components, raw_values_reported: false,
  });
  expectCode('REMOTE_BUNDLE_SEMANTICS', () => subject().validateRemoteBundleSemantics({ context, configBytes, credentialBytes, receiptBytes }));
});

test('launcher gate receipt defers zsh syntax to the exact Mac runtime before network', () => {
  const skeleton = digest('a');
  assert.equal(subject().validateLauncherGateReceipt({
    launcher_target_environment: 'mac_local', launcher_runtime_path: '/bin/zsh',
    zsh_syntax_validation_deferred: true, zsh_syntax_validation_required_environment: 'mac_local',
    zsh_syntax_validation_required_before_network: true,
    zsh_syntax_validation_status: 'not_executed_on_vps',
    predecessor_launcher_structural_skeleton_sha256: skeleton,
    current_launcher_structural_skeleton_sha256: skeleton,
    launcher_structural_skeleton_equal: true,
  }), true);
});

for (const [field, value] of [
  ['launcher_target_environment', 'vps'], ['launcher_runtime_path', '/bin/bash'],
  ['zsh_syntax_validation_deferred', false], ['zsh_syntax_validation_required_environment', 'vps'],
  ['zsh_syntax_validation_required_before_network', false], ['zsh_syntax_validation_status', 'passed_on_vps'],
  ['current_launcher_structural_skeleton_sha256', digest('b')], ['launcher_structural_skeleton_equal', false],
]) {
  test(`launcher gate receipt rejects ${field} mutation`, () => {
    const skeleton = digest('a');
    const receipt = {
      launcher_target_environment: 'mac_local', launcher_runtime_path: '/bin/zsh',
      zsh_syntax_validation_deferred: true, zsh_syntax_validation_required_environment: 'mac_local',
      zsh_syntax_validation_required_before_network: true,
      zsh_syntax_validation_status: 'not_executed_on_vps',
      predecessor_launcher_structural_skeleton_sha256: skeleton,
      current_launcher_structural_skeleton_sha256: skeleton,
      launcher_structural_skeleton_equal: true,
      [field]: value,
    };
    expectCode('REMOTE_BUNDLE_SEMANTICS', () => subject().validateLauncherGateReceipt(receipt));
  });
}

test('local bundle promotion exposes the receipt commit marker last and preserves raced staging evidence', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-local-promotion-'));
  try {
    const firstStaging = path.join(root, '.staging-first');
    const finalRoot = path.join(root, 'remote-generation');
    await mkdir(firstStaging, { mode: 0o700 });
    for (const name of ['mobile-staging-config.json', 'synthetic-patient.credentials.json', 'local-bridge.receipt.json']) {
      await writeFile(path.join(firstStaging, name), `${name}\n`, { mode: 0o600 });
    }
    assert.equal((await subject().promoteDirectoryNoReplace({
      stagingRoot: firstStaging, finalRoot,
      exclusiveRename: ({ source, destination }) => rename(source, destination),
    })).status, 'CREATED');
    const secondStaging = path.join(root, '.staging-second');
    await mkdir(secondStaging, { mode: 0o700 });
    await writeFile(path.join(secondStaging, 'evidence'), 'preserve\n', { mode: 0o600 });
    await rejectCode('LOCAL_PUBLICATION_RACE', () => subject().promoteDirectoryNoReplace({
      stagingRoot: secondStaging, finalRoot,
      exclusiveRename: ({ source, destination }) => rename(source, destination),
    }));
    assert.equal(await readFile(path.join(secondStaging, 'evidence'), 'utf8'), 'preserve\n');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('local bundle no-clobber rejects an empty-directory race after the absence check', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-local-empty-race-'));
  try {
    const stagingRoot = path.join(root, '.staging');
    const finalRoot = path.join(root, 'remote-generation');
    await mkdir(stagingRoot, { mode: 0o700 });
    for (const name of ['mobile-staging-config.json', 'synthetic-patient.credentials.json', 'local-bridge.receipt.json']) {
      await writeFile(path.join(stagingRoot, name), `${name}\n`, { mode: 0o600 });
    }
    await rejectCode('LOCAL_PUBLICATION_RACE', () => subject().promoteDirectoryNoReplace({
      stagingRoot, finalRoot, beforeRename: async () => mkdir(finalRoot, { mode: 0o700 }),
      exclusiveRename: async ({ source, destination }) => {
        if (await lstat(destination).catch(() => null)) throw Object.assign(new Error('exists'), { code: 'EEXIST' });
        await rename(source, destination);
      },
    }));
    assert.deepEqual((await readdir(stagingRoot)).sort(), [
      'local-bridge.receipt.json', 'mobile-staging-config.json', 'synthetic-patient.credentials.json',
    ]);
    assert.deepEqual(await readdir(finalRoot), []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

for (const bytes of [Buffer.from(''), Buffer.from('bad-key value\n'), Buffer.from('key\0value\n'), Buffer.from('key value\r\n')]) {
  test('real ssh-G parser rejects malformed native output', () => {
    expectCode('SSH_G_PARSE', () => subject().parseSshG(bytes));
  });
}

const UNSAFE_SSH_OPTIONS = Object.freeze([
  ['forwardagent', 'yes'], ['passwordauthentication', 'yes'], ['kbdinteractiveauthentication', 'yes'],
  ['proxycommand', 'ssh proxy'], ['proxyjump', 'proxy'], ['controlmaster', 'auto'],
  ['localcommand', 'touch /tmp/x'], ['permitlocalcommand', 'yes'], ['clearallforwardings', 'no'],
  ['stricthostkeychecking', 'no'], ['requesttty', 'yes'], ['gatewayports', 'yes'],
  ['exitonforwardfailure', 'no'], ['hostbasedauthentication', 'yes'], ['gssapiauthentication', 'yes'],
]);

for (const [key, value] of UNSAFE_SSH_OPTIONS) {
  test(`SSH policy rejects unsafe ${key}`, () => {
    expectCode('SSH_POLICY', () => subject().validateSshSecurityPolicy([{ key, value, ordinal: 0 }]));
  });
}

test('SSH policy rejects a native key outside the frozen complete allowlist', () => {
  expectCode('SSH_POLICY', () => subject().validateSshSecurityPolicy([{ key: 'futureunknownoption', value: 'no', ordinal: 0 }]));
});

test('executes actual /usr/bin/ssh -G against an isolated synthetic config without network', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-ssh-g-'));
  const configPath = path.join(root, 'ssh_config');
  const knownHostsPath = path.join(root, 'known_hosts');
  const identityPath = path.join(root, 'identity');
  await writeFile(knownHostsPath, '', { mode: 0o600 });
  await writeFile(identityPath, 'synthetic-not-a-key\n', { mode: 0o600 });
  await writeFile(configPath, [
    'Host ci3-synthetic',
    '  HostName example.invalid',
    '  User root',
    '  Port 22',
    `  IdentityFile ${identityPath}`,
    `  UserKnownHostsFile ${knownHostsPath}`,
    '  GlobalKnownHostsFile none',
    '  StrictHostKeyChecking yes',
    '  IdentitiesOnly yes',
    '  ForwardAgent no',
    '  ForwardX11 no',
    '  ForwardX11Trusted no',
    '  PasswordAuthentication no',
    '  KbdInteractiveAuthentication no',
    '  PubkeyAuthentication yes',
    '  ProxyCommand none',
    '  ControlMaster no',
    '  PermitLocalCommand no',
    '  ClearAllForwardings yes',
    '  ExitOnForwardFailure yes',
    '  GatewayPorts no',
    '  HostbasedAuthentication no',
    '  GSSAPIAuthentication no',
    '  RequestTTY no',
    '',
  ].join('\n'), { mode: 0o600 });
  const result = await subject().runSshG({ alias: 'ci3-synthetic', configPath });
  assert.equal(result.exit, 0);
  assert.ok(result.records.length > 20);
  assert.equal(result.network_calls, 0);
});

test('scan allowlist accepts exactly the six review-defined IDs in order', () => {
  assert.equal(subject().validateScanIds(SCAN_IDS), true);
});

for (const candidate of [SCAN_IDS.slice(1), [...SCAN_IDS, 'extra'], [...SCAN_IDS].reverse(), ['argv', ...SCAN_IDS], ['argv', 'history', 'terminal_log', 'attachment', 'xcresult', 'runtime']]) {
  test(`scan allowlist rejects ${JSON.stringify(candidate)}`, () => {
    expectCode('TERMINAL_SCAN_SET', () => subject().validateScanIds(candidate));
  });
}

function scanSurfaceAuthority() {
  return Object.fromEntries(SCAN_IDS.map((scanId) => [scanId, {
    id: scanId,
    collector_version: subject().SCAN_SURFACE_CONTRACTS[scanId].collector_version,
    format: subject().SCAN_SURFACE_CONTRACTS[scanId].format,
    source_role: subject().SCAN_SURFACE_CONTRACTS[scanId].source_role,
    tool_sha256: digest('3'),
    contract_sha256: subject().scannerSchemaSha256(scanId),
  }]));
}

test('operational scan authority freezes one collector contract for every literal scan ID without prepublished surfaces', () => {
  assert.equal(subject().validateScanSurfaceAuthority(scanSurfaceAuthority()), true);
});

for (const scanId of SCAN_IDS) {
  test(`operational scan authority rejects missing observer surface for ${scanId}`, () => {
    const scans = scanSurfaceAuthority();
    delete scans[scanId];
    expectCode('OPERATION_AUTHORITY', () => subject().validateScanSurfaceAuthority(scans));
  });
}

const SURFACE_SPECIFIC_DIRTY_RECORDS = Object.freeze({
  argv: 'password=hidden --email=user@example.invalid aaaaaaaa.bbbbbbbb.cccccccc token=opaque destination=host.invalid',
  history: 'export PASSWORD=hidden user@example.invalid aaaaaaaa.bbbbbbbb.cccccccc TOKEN=opaque ssh user@host.invalid',
  'terminal-log': 'secret: hidden user@example.invalid aaaaaaaa.bbbbbbbb.cccccccc token: opaque destination: host.invalid',
  attachment: '{"password":"hidden","email":"user@example.invalid","jwt":"aaaaaaaa.bbbbbbbb.cccccccc","token":"opaque","origin":"host.invalid"}',
  xcresult: 'secret=hidden email=user@example.invalid jwt=aaaaaaaa.bbbbbbbb.cccccccc token=opaque origin=host.invalid',
  runtime: 'SECRET=hidden EMAIL=user@example.invalid JWT=aaaaaaaa.bbbbbbbb.cccccccc TOKEN=opaque ORIGIN=host.invalid',
});

for (const scanId of SCAN_IDS) {
  test(`surface-specific scanner ${scanId} recognizes its own serialized schema`, () => {
    const result = subject().scanTerminalSurface(scanId, Buffer.from(SURFACE_SPECIFIC_DIRTY_RECORDS[scanId]));
    for (const counter of ['secret', 'pii', 'jwt', 'token', 'raw_destination']) assert.ok(result.counters[counter] > 0, `${scanId}:${counter}`);
  });
}

function scanReceipt(scanId) {
  return {
    schema_version: 1,
    purpose: 'CI3_TERMINAL_SCAN_RECEIPT_V1',
    scan_id: scanId,
    authority_sha: oid('a'),
    controller_generation_id: generation('controller', 'b'),
    remote_generation_id: generation('remote', 'c'),
    simulator_generation_id: generation('simulator', 'd'),
    terminal_generation_id: generation('terminal', 'e'),
    local_bundle_sha256: digest('d'),
    simulator_install_sha256: digest('e'),
    worktree_diff_sha256: digest('f'),
    input_manifest_sha256: digest('1'),
    input_observations: [{ path: `/synthetic/${scanId}`, path_sha256: subject().sha256(Buffer.from(`/synthetic/${scanId}`)), sha256: digest('5'), metadata: { dev: '1', gid: 0, ino: '2', mode: 0o600, mtime_ns: '3', nlink: 1, size: 1, uid: 0 } }],
    tool_sha256: digest('2'),
    command_sha256: digest('3'),
    scanner_schema_sha256: subject().scannerSchemaSha256(scanId),
    counters: { secret: 0, pii: 0, jwt: 0, token: 0, raw_destination: 0 },
    started_at: '2026-08-30T12:00:00.000Z',
    finished_at: '2026-08-30T12:00:01.000Z',
    result: 'CLEAN',
    match_count: 0,
    output_sha256: digest('4'),
    redaction: true,
    input_stable_after_scan: true,
  };
}

for (const scanId of SCAN_IDS) {
  test(`terminal scan receipt validates closed surface ${scanId}`, () => {
    assert.equal(subject().validateScanReceipt(scanReceipt(scanId), scanId), true);
  });
}

for (const field of ['result', 'match_count', 'redaction', 'input_stable_after_scan', 'controller_generation_id', 'local_bundle_sha256']) {
  test(`terminal scan receipt rejects unsafe ${field}`, () => {
    const receipt = scanReceipt('attachment');
    receipt[field] = field === 'match_count' ? 1 : field === 'redaction' || field === 'input_stable_after_scan' ? false : 'wrong';
    expectCode('TERMINAL_SCAN_RECEIPT', () => subject().validateScanReceipt(receipt, 'attachment'));
  });
}

test('terminal manifest binds all 71 semantic evidence roles without deduplication', () => {
  const terminalMetadata = (index) => ({
    uid: process.getuid?.() ?? 0, gid: process.getgid?.() ?? 0, mode: 0o600,
    nlink: 1, size: index + 1, mtime_ns: String(1700000000000000000n + BigInt(index)),
    dev: '1', ino: String(index + 1),
  });
  const evidenceRoles = [...subject().TERMINAL_MANIFEST_EVIDENCE_ROLES];
  assert.equal(evidenceRoles.length, 71);
  const runScansResultSha256 = digest('b');
  const terminalSettlementContracts = subject().buildTerminalSettlementContracts({
    authoritySha: oid('a'), controllerGenerationId: baseContext().generations.controller,
    terminalGenerationId: baseContext().generations.terminal, runScansResultSha256,
  });
  const manifest = subject().buildTerminalManifest({
    authoritySha: oid('a'),
    authorityTree: oid('b'),
    authorityManifestSha256: digest('0'),
    components: components(),
    generations: baseContext().generations,
    bootstrapClaimSha256: digest('1'),
    readChainSha256: digest('2'),
    remoteBundleSha256: digest('3'),
    localBundleSha256: digest('4'),
    sshProvenanceSha256: digest('5'),
    simulatorGateSha256: digest('6'),
    installReceiptSha256: digest('7'),
    scanReceipts: SCAN_IDS.map((scanId, index) => ({
      id: scanId, path: `/synthetic/scan-${scanId}.json`,
      sha256: digest(String(index + 1)), metadata: terminalMetadata(index),
    })),
    evidence: evidenceRoles.map((role, index) => ({
      role, path: `/synthetic/${role}.json`, sha256: digest(String((index % 9) + 1)), metadata: terminalMetadata(index + 10),
    })),
    writerAuthorityPathSha256: digest('8'),
    writerSourceSha256: digest('4'),
    writerBinarySha256: digest('9'),
    writerSignatureSha256: digest('a'),
    runScansResultSha256,
    terminalSettlementContracts,
    createdAtUtc: '2026-08-30T12:00:00.000Z',
  });
  assert.deepEqual(Object.keys(manifest).sort(), [
    'anchor_relative_path', 'authority_manifest_sha256', 'authority_sha', 'authority_tree',
    'bootstrap_claim_sha256', 'claim_result_chain_sha256', 'components', 'created_at_utc',
    'evidence', 'generations', 'important_finding_ids', 'local_bundle_sha256',
    'privilege_mode', 'purpose', 'raw_values', 'remote_bundle_sha256', 'scan_receipts',
    'schema_version', 'secret_read', 'simulator_gate_sha256', 'simulator_install_sha256',
    'ssh_provenance_sha256', 'terminal_settlement_contracts', 'terminal_state', 'writer_authority_path_sha256',
    'writer_binary_sha256', 'writer_signature_sha256', 'writer_source_sha256',
  ].sort());
  assert.deepEqual(manifest.important_finding_ids, FINDING_IDS);
  assert.deepEqual(manifest.scan_receipts.map(({ id }) => id), SCAN_IDS);
  assert.equal(manifest.evidence.length, 71);
});

function privilegedWriterAuthorityReceipt() {
  const authoritySha = oid('a');
  const terminalGenerationId = generation('terminal', '1');
  const executablePath = `/Library/Application Support/Agentempp/ci3-terminal-authority/${authoritySha}/${terminalGenerationId}/writer/ci3-terminal-anchor-writer`;
  return {
    schema_version: 1,
    purpose: 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1',
    authority_sha: authoritySha,
    terminal_generation_id: terminalGenerationId,
    terminal_manifest_sha256: digest('2'),
    writer_source_sha256: digest('4'),
    writer_binary_sha256: digest('3'),
    writer_signature_sha256: digest('5'),
    privileged_claim_sha256: digest('6'),
    authority_path_sha256: digest('7'),
    anchor_path_sha256: digest('b'),
    terminal_manifest_path_sha256: digest('a'),
    writer_executable_path_sha256: subject().sha256(Buffer.from(executablePath)),
    writer_executable_identity_sha256: digest('9'),
    writer_executable_uid: 0,
    writer_executable_gid: 0,
    writer_executable_mode: '0555',
    writer_executable_immutable_flag: 'UF_IMMUTABLE',
    normal_executor_authorized: false,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
}

function privilegedWriterAuthorityExpected() {
  const authoritySha = oid('a');
  const terminalGenerationId = generation('terminal', '1');
  const executablePath = `/Library/Application Support/Agentempp/ci3-terminal-authority/${authoritySha}/${terminalGenerationId}/writer/ci3-terminal-anchor-writer`;
  return {
    authoritySha,
    terminalGenerationId,
    terminalManifestSha256: digest('2'),
    writerSourceSha256: digest('4'),
    writerBinarySha256: digest('3'),
    writerSignatureSha256: digest('5'),
    privilegedClaimSha256: digest('6'),
    authorityPathSha256: digest('7'),
    anchorPathSha256: digest('b'),
    terminalManifestPathSha256: digest('a'),
    writerExecutablePathSha256: subject().sha256(Buffer.from(executablePath)),
    writerExecutableIdentitySha256: digest('9'),
  };
}

test('privileged writer authority validates only after scan-produced artifacts and an external claim are hash-bound', () => {
  assert.equal(subject().validatePrivilegedWriterAuthorityReceipt(
    privilegedWriterAuthorityReceipt(), privilegedWriterAuthorityExpected(),
  ), true);
});

test('privileged invocation selects only the immutable root-owned executable and ignores replaced user candidate', () => {
  const expected = privilegedWriterAuthorityExpected();
  const executablePath = `/Library/Application Support/Agentempp/ci3-terminal-authority/${expected.authoritySha}/${expected.terminalGenerationId}/writer/ci3-terminal-anchor-writer`;
  const executablePathSha256 = subject().sha256(Buffer.from(executablePath));
  const receipt = {
    ...privilegedWriterAuthorityReceipt(),
    writer_executable_path_sha256: executablePathSha256,
    writer_executable_identity_sha256: digest('9'),
    writer_executable_mode: '0555',
    writer_executable_uid: 0,
    writer_executable_gid: 0,
    writer_executable_immutable_flag: 'UF_IMMUTABLE',
    terminal_manifest_path_sha256: digest('a'),
  };
  Object.assign(expected, {
    writerExecutablePathSha256: executablePathSha256, writerExecutableIdentitySha256: digest('9'),
    terminalManifestPathSha256: digest('a'),
  });
  const first = subject().selectPrivilegedWriterInvocation({ authorityReceipt: receipt, expected, userCandidatePath: '/tmp/user-writer-v1' });
  const replaced = subject().selectPrivilegedWriterInvocation({ authorityReceipt: receipt, expected, userCandidatePath: '/tmp/user-writer-replaced' });
  assert.equal(first.executablePath, replaced.executablePath);
  assert.match(first.executablePath, /^\/Library\/Application Support\/Agentempp\/ci3-terminal-authority\//);
  assert.notEqual(first.executablePath, '/tmp/user-writer-replaced');
});

for (const phase of ['VERIFY_SIMULATOR', 'VERIFY_SSH', 'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS', 'INVOKE_WRITER', 'VERIFY_ANCHOR']) {
  test(`durable ${phase} claim precedes effect and result binds physical observation`, () => {
    const claim = subject().buildPhaseClaim({
      phase, authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b'),
      predecessorResultSha256: digest('1'), contractSha256: digest('2'),
    });
    const result = subject().buildPhaseResult({
      phase, claimSha256: subject().sha256(subject().canonicalJson(claim)),
      receiptSha256: digest('3'), physicalObservationSha256: digest('4'),
    });
    assert.equal(claim.attempt, 1);
    assert.equal(claim.retry, false);
    assert.equal(result.claim_sha256, subject().sha256(subject().canonicalJson(claim)));
  });
}

for (const scanId of SCAN_IDS) {
  test(`surface-specific scanner ${scanId} emits independent secret PII JWT token and destination counters`, async () => {
    if (scanId === 'argv') {
      const source = await readFile(new URL('./ci3-bridge-controller.test.mjs', import.meta.url), 'utf8');
      const rawIpv4 = new RegExp(String.raw`\b(?:\d{1,3}\.){3}\d{1,3}\b`);
      assert.equal(rawIpv4.test(source), false);
    }
    const clean = subject().scanTerminalSurface(scanId, Buffer.from('synthetic clean record\n'));
    assert.deepEqual(Object.keys(clean.counters).sort(), ['jwt', 'pii', 'raw_destination', 'secret', 'token']);
    assert.equal(clean.total, 0);
    const dirty = subject().scanTerminalSurface(scanId, Buffer.from('Authorization: Bearer aaa.bbb.ccc user@example.invalid host=relay.synthetic.invalid token=synthetic\n'));
    assert.ok(dirty.total > 0);
  });
}

for (const field of [
  'purpose', 'authority_sha', 'terminal_generation_id', 'terminal_manifest_sha256',
  'writer_source_sha256', 'writer_binary_sha256', 'writer_signature_sha256',
  'privileged_claim_sha256', 'authority_path_sha256', 'normal_executor_authorized',
  'anchor_path_sha256', 'terminal_manifest_path_sha256',
  'writer_executable_path_sha256', 'writer_executable_identity_sha256',
  'writer_executable_uid', 'writer_executable_gid', 'writer_executable_mode',
  'writer_executable_immutable_flag',
  'attempt', 'retry', 'raw_values',
]) {
  test(`privileged writer authority rejects drift in ${field}`, () => {
    const receipt = privilegedWriterAuthorityReceipt();
    receipt[field] = field === 'normal_executor_authorized' || field === 'retry' || field === 'raw_values'
      ? true
      : ['attempt', 'writer_executable_uid', 'writer_executable_gid'].includes(field) ? 2 : 'drift';
    expectCode('STOP_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY', () => {
      subject().validatePrivilegedWriterAuthorityReceipt(receipt, privilegedWriterAuthorityExpected());
    });
  });
}

for (const findingId of FINDING_IDS) {
  test(`finding matrix maps ${findingId} to a test receipt and terminal anchor field`, () => {
    const mapping = subject().IMPORTANT_FINDINGS.find(({ id }) => id === findingId);
    assert.equal(mapping.id, findingId);
    assert.ok(mapping.test);
    assert.ok(mapping.receipt_field);
    assert.ok(mapping.anchor_field);
  });
}

for (const state of ['bundle', 'capture', 'result', 'install', 'anchor']) {
  test(`rejects unclaimed exact-existing ${state}`, () => {
    expectCode('REJECT_UNCLAIMED_EXISTING_STATE', () => subject().validateExistingState({ state, originalClaim: null }));
  });
}

for (const state of ['bundle', 'capture', 'result', 'install', 'anchor']) {
  test(`accepts exact-existing ${state} only with original full provenance`, () => {
    assert.equal(subject().validateExistingState({
      state,
      originalClaim: { sha256: digest('a'), generations: baseContext().generations, components: components(), authority_sha: oid('a') },
      expected: { claim_sha256: digest('a'), generations: baseContext().generations, components: components(), authority_sha: oid('a') },
    }), true);
  });
}

test('recovery with a claim and no result consumes budget and forbids refetch', () => {
  assert.deepEqual(subject().classifyRecovery({ claim: true, capture: false, result: false }), { state: 'CLAIM_CONSUMED_NO_RESULT', refetch: false });
});

test('recovery with claim capture and result stays local-only', () => {
  assert.deepEqual(subject().classifyRecovery({ claim: true, capture: true, result: true }), { state: 'LOCAL_RECOVERY', refetch: false });
});

test('recovery never creates a retroactive claim for existing evidence', () => {
  expectCode('REJECT_UNCLAIMED_EXISTING_STATE', () => subject().classifyRecovery({ claim: false, capture: true, result: true }));
});

test('remote capture hashes and persists bytes through the one preopened descriptor', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-capture-fd-'));
  try {
    const capturePath = path.join(root, 'config.capture');
    const expected = Buffer.from('same-descriptor-evidence');
    const captured = await subject().captureCommandToNewFile({
      executable: '/usr/bin/printf', args: ['%s', expected.toString('utf8')],
      capturePath, expectedSha256: subject().sha256(expected),
    });
    assert.deepEqual(captured.bytes, expected);
    assert.equal(captured.descriptor_read, true);
    assert.deepEqual(await readFile(capturePath), expected);
    assert.match(captured.identity_sha256, /^[a-f0-9]{64}$/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('remote capture rejects pathname replacement after descriptor open without trusting replacement bytes', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-capture-race-'));
  try {
    const capturePath = path.join(root, 'receipt.capture');
    await rejectCode('REMOTE_CAPTURE_RACE', () => subject().captureCommandToNewFile({
      executable: '/usr/bin/printf', args: ['%s', 'trusted'], capturePath,
      expectedSha256: subject().sha256(Buffer.from('trusted')),
      afterOpen: async () => {
        await writeFile(`${capturePath}.replacement`, 'attacker');
        await rename(capturePath, `${capturePath}.original`);
        await rename(`${capturePath}.replacement`, capturePath);
      },
    }));
    assert.equal(await readFile(capturePath, 'utf8'), 'attacker');
    assert.equal(await readFile(`${capturePath}.original`, 'utf8'), 'trusted');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

const PROTOCOL_STATES = Object.freeze([
  ['INIT', 'VERIFY_AUTHORITY', 'AUTHORITY_VERIFIED'],
  ['AUTHORITY_VERIFIED', 'VERIFY_WORKTREE', 'WORKTREE_VERIFIED'],
  ['WORKTREE_VERIFIED', 'VERIFY_SIMULATOR', 'SIMULATOR_VERIFIED'],
  ['SIMULATOR_VERIFIED', 'VERIFY_SSH', 'SSH_VERIFIED'],
  ['SSH_VERIFIED', 'READ_RECEIPT', 'RECEIPT_FETCHED'],
  ['RECEIPT_FETCHED', 'READ_CONFIG', 'CONFIG_FETCHED'],
  ['CONFIG_FETCHED', 'READ_CREDENTIAL', 'CREDENTIAL_FETCHED'],
  ['CREDENTIAL_FETCHED', 'PUBLISH_LOCAL', 'LOCAL_PUBLISHED'],
  ['LOCAL_PUBLISHED', 'INSTALL_SIMULATOR', 'INSTALLED'],
  ['INSTALLED', 'REMOVE_CREDENTIAL', 'CREDENTIAL_REMOVED'],
  ['CREDENTIAL_REMOVED', 'RUN_SCANS', 'SCANNED'],
  ['SCANNED', 'COMPLETE', 'COMPLETE'],
]);

for (const [state, event, expected] of PROTOCOL_STATES) {
  test(`protocol E2E advances ${state} with ${event}`, () => {
    assert.equal(subject().advanceProtocol(state, event), expected);
  });
}

for (const [state, , expected] of PROTOCOL_STATES) {
  test(`protocol E2E rejects out-of-order event from ${state}`, () => {
    expectCode('PROTOCOL_TRANSITION', () => subject().advanceProtocol(state, 'UNEXPECTED'));
    assert.notEqual(state, expected);
  });
}

const E2E_RECOVERY_CASES = Object.freeze([
  [{ claim: true, capture: false, result: false }, 'CLAIM_CONSUMED_NO_RESULT'],
  [{ claim: true, capture: true, result: false }, 'CAPTURE_PENDING_RESULT_LOCAL_ONLY'],
  [{ claim: true, capture: true, result: true }, 'LOCAL_RECOVERY'],
  [{ claim: false, capture: false, result: false }, 'ABSENT'],
  [{ claim: true, capture: false, result: true }, 'DIVERGENT'],
  [{ claim: false, capture: false, result: true }, 'REJECT'],
  [{ claim: false, capture: true, result: false }, 'REJECT'],
  [{ claim: false, capture: true, result: true }, 'REJECT'],
  [{ claim: true, capture: true, result: true, generationDrift: true }, 'DIVERGENT'],
  [{ claim: true, capture: true, result: true, provenanceDrift: true }, 'DIVERGENT'],
]);

for (const [input, expected] of E2E_RECOVERY_CASES) {
  test(`protocol E2E recovery is fail-closed for ${JSON.stringify(input)}`, () => {
    if (expected === 'REJECT') {
      expectCode('REJECT_UNCLAIMED_EXISTING_STATE', () => subject().classifyRecovery(input));
    } else {
      assert.equal(subject().classifyRecovery(input).state, expected);
    }
  });
}

const E2E_REPEAT_EVENTS = Object.freeze([
  ['AUTHORITY_VERIFIED', 'VERIFY_AUTHORITY'], ['WORKTREE_VERIFIED', 'VERIFY_WORKTREE'],
  ['SIMULATOR_VERIFIED', 'VERIFY_SIMULATOR'], ['SSH_VERIFIED', 'VERIFY_SSH'],
  ['RECEIPT_FETCHED', 'READ_RECEIPT'], ['CONFIG_FETCHED', 'READ_CONFIG'],
  ['CREDENTIAL_FETCHED', 'READ_CREDENTIAL'], ['LOCAL_PUBLISHED', 'PUBLISH_LOCAL'],
  ['INSTALLED', 'INSTALL_SIMULATOR'], ['SCANNED', 'RUN_SCANS'],
]);

for (const [state, event] of E2E_REPEAT_EVENTS) {
  test(`protocol E2E never repeats consumed event ${event}`, () => {
    expectCode('PROTOCOL_TRANSITION', () => subject().advanceProtocol(state, event));
  });
}

test('full synthetic controller state machine reaches anchored terminal PASS with zero network', async () => {
  const outcome = await subject().runSyntheticProtocol();
  assert.equal(outcome.state, 'COMPLETE');
  assert.equal(outcome.network_calls, 0);
  assert.equal(outcome.privilege_prompts, 0);
  assert.deepEqual(outcome.scan_ids, SCAN_IDS);
});

for (const scenario of subject().FULL_PROTOCOL_E2E_SCENARIOS) {
  test(`full protocol E2E ${scenario.id} has deterministic no-reexecution recovery`, async () => {
    const fixture = crashRecoveryFixture(scenario);
    await assert.rejects(
      subject().runProtocol({ adapters: fixture.adapters, context: fixture.context, journal: fixture.journal }),
      (error) => error?.message === `SYNTHETIC_CRASH:${scenario.id}`,
    );
    fixture.disableCrash();
    if (!['INVOKE_WRITER', 'VERIFY_ANCHOR'].includes(scenario.phase)
        && ['after-claim', 'after-effect'].includes(scenario.boundary)) {
      await rejectCode('CLAIM_CONSUMED_NO_RESULT', () => subject().runProtocol({ adapters: fixture.adapters, context: fixture.context, journal: fixture.journal }));
    } else {
      const outcome = await subject().runProtocol({ adapters: fixture.adapters, context: fixture.context, journal: fixture.journal });
      assert.equal(outcome.state, 'COMPLETE');
    }
    const expectedCount = !['INVOKE_WRITER', 'VERIFY_ANCHOR'].includes(scenario.phase)
      && scenario.boundary === 'after-claim' ? 0 : 1;
    assert.equal(fixture.effectCount(scenario.phase), expectedCount);
  });
}

function crashRecoveryFixture(scenario) {
  const base = operationalSyntheticFixture();
  const events = new Map();
  const phaseClaims = new Map();
  const phaseReceipts = new Map();
  const phaseResults = new Map();
  const claims = new Map();
  const results = new Map();
  const effectCounts = new Map();
  const privilegedTerminalProgress = new Map();
  let privilegedWriterResult = null;
  let crashEnabled = true;
  const crash = (phase, boundary) => {
    if (crashEnabled && scenario.phase === phase && scenario.boundary === boundary) throw new Error(`SYNTHETIC_CRASH:${scenario.id}`);
  };
  const wrapEffect = (phase, valueFactory) => async (...args) => {
    effectCounts.set(phase, (effectCounts.get(phase) ?? 0) + 1);
    return valueFactory(...args);
  };
  const privilegedTerminalEffect = async (...args) => {
    for (const phase of ['INVOKE_WRITER', 'VERIFY_ANCHOR']) {
      let progress = privilegedTerminalProgress.get(phase) ?? 0;
      if (progress < 1) { crash(phase, 'before-claim'); privilegedTerminalProgress.set(phase, 1); progress = 1; }
      if (progress < 2) { crash(phase, 'after-claim'); privilegedTerminalProgress.set(phase, 2); progress = 2; }
      if (progress < 3) {
        effectCounts.set(phase, (effectCounts.get(phase) ?? 0) + 1);
        privilegedTerminalProgress.set(phase, 3); progress = 3;
        crash(phase, 'after-effect');
      }
      if (progress < 4) { crash(phase, 'after-receipt'); privilegedTerminalProgress.set(phase, 4); progress = 4; }
      if (progress < 5) { crash(phase, 'after-result'); privilegedTerminalProgress.set(phase, 5); progress = 5; }
      if (progress < 6) { crash(phase, 'after-event'); privilegedTerminalProgress.set(phase, 6); }
    }
    if (privilegedWriterResult === null) privilegedWriterResult = await base.adapters.invokeWriter(...args);
    return structuredClone(privilegedWriterResult);
  };
  const recoveringWriterEffect = async (...args) => {
    if (privilegedWriterResult !== null) return structuredClone(privilegedWriterResult);
    effectCounts.set('INVOKE_WRITER', (effectCounts.get('INVOKE_WRITER') ?? 0) + 1);
    privilegedWriterResult = await base.adapters.invokeWriter(...args);
    return structuredClone(privilegedWriterResult);
  };
  const adapters = {
    observePhase: base.adapters.observePhase,
    recoverPhase: async () => null,
    verifyAuthority: wrapEffect('VERIFY_AUTHORITY', async () => ({ verified: true })),
    verifyWorktree: wrapEffect('VERIFY_WORKTREE', async () => ({ verified: true })),
    verifySimulator: wrapEffect('VERIFY_SIMULATOR', async () => ({ receipt: simulatorReceipt() })),
    verifySsh: wrapEffect('VERIFY_SSH', async () => ({ provenance: base.context.ssh })),
    readRemote: base.adapters.readRemote,
    recoverRemote: base.adapters.readRemote,
    publishLocal: wrapEffect('PUBLISH_LOCAL', async () => ({ local_bundle_sha256: digest('4') })),
    installSimulator: wrapEffect('INSTALL_SIMULATOR', async () => ({ install_receipt_sha256: digest('5') })),
    removeSimulatorCredential: wrapEffect('REMOVE_CREDENTIAL', async () => ({ removed: true })),
    scan: wrapEffect('RUN_SCANS', async () => SCAN_IDS.map((id) => scanReceipt(id))),
    invokeWriter: ['INVOKE_WRITER', 'VERIFY_ANCHOR'].includes(scenario.phase)
      ? privilegedTerminalEffect
      : recoveringWriterEffect,
    verifyAnchor: wrapEffect('VERIFY_ANCHOR', base.adapters.verifyAnchor),
    settleTerminal: async ({ invokeWriter, verifyAnchor }) => subject().buildTerminalSettlementReceipt({
      authoritySha: base.context.authority.commit,
      generations: base.context.generations,
      preAnchorSha256: digest('6'),
      invokeWriter,
      verifyAnchor,
      settlementAuthoritySha256: digest('b'),
      terminalSettlementContractsSha256: digest('c'),
      terminalPhaseGraphSha256: digest('d'),
      terminalFinalScanSha256: digest('e'),
    }),
  };
  const journal = {
    load: async (event) => events.get(event) ?? null,
    append: async (record) => {
      events.set(record.event, structuredClone(record));
      crash(record.event, 'after-event');
      return subject().sha256(subject().canonicalJson(record));
    },
    loadPhaseClaim: async (phase) => phaseClaims.get(phase) ?? null,
    appendPhaseClaim: async (claim) => {
      crash(claim.phase, 'before-claim');
      phaseClaims.set(claim.phase, structuredClone(claim));
      crash(claim.phase, 'after-claim');
      return subject().sha256(subject().canonicalJson(claim));
    },
    settlePhaseReceipt: async (phase, claimSha256, result, observation) => {
      crash(phase, 'after-effect');
      const receipt = {
        result: structuredClone(result), receiptSha256: subject().sha256(subject().canonicalJson({ phase, result })),
        physicalObservationSha256: observation.observation_sha256,
        observation: structuredClone(observation),
      };
      phaseReceipts.set(phase, receipt);
      crash(phase, 'after-receipt');
      return structuredClone(receipt);
    },
    reobservePhaseReceipt: async (phase) => structuredClone(phaseReceipts.get(phase) ?? null),
    loadPhaseResult: async (phase) => phaseResults.get(phase) ?? null,
    appendPhaseResult: async (result) => {
      phaseResults.set(result.phase, structuredClone(result));
      crash(result.phase, 'after-result');
      return subject().sha256(subject().canonicalJson(result));
    },
    loadClaim: async (kind) => claims.get(kind) ?? null,
    appendClaim: async (claim) => {
      const kind = claim.purpose === 'CI3_MAC_BRIDGE_BOOTSTRAP_CLAIM_V1' ? 'bootstrap' : claim.kind;
      const existing = claims.get(kind);
      if (existing && !subject().canonicalJson(existing).equals(subject().canonicalJson(claim))) throw new Error('DIVERGENT');
      claims.set(kind, structuredClone(claim));
      return subject().sha256(subject().canonicalJson(claim));
    },
    loadResult: async (kind) => results.get(kind) ?? null,
    appendResult: async (result) => {
      results.set(result.kind, structuredClone(result));
      return subject().sha256(subject().canonicalJson(result));
    },
  };
  return {
    adapters, context: base.context, journal,
    disableCrash: () => { crashEnabled = false; },
    effectCount: (phase) => effectCounts.get(phase) ?? 0,
  };
}

function operationalSyntheticFixture() {
  const context = baseContext();
  const calls = [];
  const phaseClaims = new Map();
  const phaseReceipts = new Map();
  const phaseResults = new Map();
  const observe = ({ event, result }) => {
    const metadata = { dev: '1', gid: 0, ino: '2', mode: 0o600, mtime_ns: '3', nlink: 1, size: 1, uid: 0 };
    const identitySha256 = subject().sha256(Buffer.from('uid=0;gid=0;mode=384;nlink=1;size=1;mtime=3;dev=1;ino=2'));
    const body = {
      schema_version: 1, purpose: 'CI3_MAC_PHASE_EFFECT_OBSERVATION_V1', phase: event,
      targets: [{
        role: `synthetic-${event.toLowerCase().replaceAll('_', '-')}`, state: 'PRESENT',
        path: `/synthetic/${event}`,
        path_sha256: subject().sha256(Buffer.from(`/synthetic/${event}`)),
        sha256: subject().sha256(subject().canonicalJson(result ?? {})),
        identity_sha256: identitySha256, metadata,
      }],
      raw_values: false,
    };
    return { ...body, observation_sha256: subject().sha256(subject().canonicalJson(body)) };
  };
  const adapters = {
    observePhase: async (input) => observe(input),
    verifyAuthority: async () => { calls.push('VERIFY_AUTHORITY'); return { verified: true }; },
    verifyWorktree: async () => { calls.push('VERIFY_WORKTREE'); return { verified: true }; },
    verifySimulator: async () => { calls.push('VERIFY_SIMULATOR'); return { receipt: simulatorReceipt() }; },
    verifySsh: async () => { calls.push('VERIFY_SSH'); return { provenance: context.ssh }; },
    readRemote: async ({ kind }) => {
      calls.push(`READ_${kind.toUpperCase()}`);
      return { captureSha256: digest(kind === 'receipt' ? '1' : kind === 'config' ? '2' : '3'), captureIdentitySha256: digest('4'), remoteCommandSha256: digest('5'), descriptorRead: true, bytes: 64, exit: 0, stderrClass: 'EMPTY', startedAt: '2026-08-30T12:00:00.000Z', finishedAt: '2026-08-30T12:00:01.000Z' };
    },
    publishLocal: async () => { calls.push('PUBLISH_LOCAL'); return { local_bundle_sha256: digest('4') }; },
    installSimulator: async () => { calls.push('INSTALL_SIMULATOR'); return { install_receipt_sha256: digest('5') }; },
    removeSimulatorCredential: async () => { calls.push('REMOVE_CREDENTIAL'); return { removed: true }; },
    scan: async () => { calls.push('RUN_SCANS'); return SCAN_IDS.map((id) => scanReceipt(id)); },
    invokeWriter: async () => {
      calls.push('INVOKE_WRITER');
      return {
        pre_anchor_sha256: digest('6'), terminal_state: 'TERMINAL_PASS', complete_sha256: digest('7'),
        marker_sha256: digest('9'), marker_verified: true,
        settlement: subject().buildTerminalSettlementReceipt({
          authoritySha: context.authority.commit, generations: context.generations,
          preAnchorSha256: digest('6'),
          invokeWriter: { claim_sha256: digest('1'), receipt_sha256: digest('2'), result_sha256: digest('3') },
          verifyAnchor: { claim_sha256: digest('4'), receipt_sha256: digest('5'), result_sha256: digest('6') },
          settlementAuthoritySha256: digest('b'), terminalSettlementContractsSha256: digest('c'),
          terminalPhaseGraphSha256: digest('d'), terminalFinalScanSha256: digest('e'),
        }),
      };
    },
    verifyAnchor: async () => { calls.push('VERIFY_ANCHOR'); return { verified: true }; },
    settleTerminal: async ({ invokeWriter, verifyAnchor }) => {
      calls.push('SETTLE_TERMINAL');
      return subject().buildTerminalSettlementReceipt({
        authoritySha: context.authority.commit,
        generations: context.generations,
        preAnchorSha256: digest('6'), invokeWriter, verifyAnchor,
        settlementAuthoritySha256: digest('b'),
        terminalSettlementContractsSha256: digest('c'),
        terminalPhaseGraphSha256: digest('d'),
        terminalFinalScanSha256: digest('e'),
      });
    },
  };
  const records = [];
  const journal = {
    append: async (record) => { records.push(record); return subject().sha256(subject().canonicalJson(record)); },
    appendClaim: async (record) => { records.push(record); return subject().sha256(subject().canonicalJson(record)); },
    appendResult: async (record) => { records.push(record); return subject().sha256(subject().canonicalJson(record)); },
    loadPhaseClaim: async (phase) => phaseClaims.get(phase) ?? null,
    appendPhaseClaim: async (record) => {
      phaseClaims.set(record.phase, structuredClone(record));
      records.push(record);
      return subject().sha256(subject().canonicalJson(record));
    },
    settlePhaseReceipt: async (phase, claimSha256, result, observation) => {
      const receipt = {
        result: structuredClone(result), observation: structuredClone(observation),
        receiptSha256: subject().sha256(subject().canonicalJson({ phase, claimSha256, result, observation })),
        physicalObservationSha256: observation.observation_sha256,
      };
      phaseReceipts.set(phase, receipt);
      return structuredClone(receipt);
    },
    reobservePhaseReceipt: async (phase) => structuredClone(phaseReceipts.get(phase) ?? null),
    loadPhaseResult: async (phase) => phaseResults.get(phase) ?? null,
    appendPhaseResult: async (record) => {
      phaseResults.set(record.phase, structuredClone(record));
      records.push(record);
      return subject().sha256(subject().canonicalJson(record));
    },
    status: async () => ({ state: 'LOCAL_SYNTHETIC', raw_values: false }),
  };
  return { adapters, calls, context, journal, records };
}

// Round-2 security regressions: these assertions intentionally describe the
// production contract before its implementation.  Keep them independent of
// the synthetic happy-path loop above so every reviewed boundary is visible.
const EXACT_PRESERVED_CI3_PATHS = Object.freeze([
  'apps/ios/BodyFlow/BodyFlow/BodyFlowApp.swift',
  'apps/ios/BodyFlow/BodyFlow/App/AppLaunchConfiguration.swift',
  'apps/ios/BodyFlow/BodyFlow/Core/Configuration/MobileStagingConfiguration.swift',
  'apps/ios/BodyFlow/BodyFlowTests/CI3StagingLaunchConfigurationTests.swift',
  'apps/ios/BodyFlow/BodyFlowTests/MobileStagingConfigurationTests.swift',
]);

test('remote SSH adapter argv contains exactly one destination and one remote command without spurious separator', () => {
  assert.deepEqual(subject().buildSshReadArgv({
    configPath: '/synthetic/ssh_config', alias: 'ci3-synthetic',
    remotePath: '/root/.config/agentempp/bridges/ci3/generation/bridge.receipt.json',
  }), [
    '-F', '/synthetic/ssh_config', 'ci3-synthetic',
    'exec /usr/bin/cat -- /root/.config/agentempp/bridges/ci3/generation/bridge.receipt.json',
  ]);
});

test('operation authority freezes the five preserved iOS paths literally and in order', () => {
  assert.deepEqual(subject().PRESERVED_CI3_PATHS, EXACT_PRESERVED_CI3_PATHS);
  assert.equal(subject().validatePreservedCi3Paths(EXACT_PRESERVED_CI3_PATHS), true);
});

for (const candidate of [
  EXACT_PRESERVED_CI3_PATHS.slice(1),
  [...EXACT_PRESERVED_CI3_PATHS, 'extra'],
  [...EXACT_PRESERVED_CI3_PATHS].reverse(),
  EXACT_PRESERVED_CI3_PATHS.map((value, index) => index === 2 ? 'apps/ios/BodyFlow/substituted.swift' : value),
]) {
  test(`operation authority rejects nonliteral preserved path vector ${candidate.length}`, () => {
    expectCode('OPERATION_AUTHORITY', () => subject().validatePreservedCi3Paths(candidate));
  });
}

for (const [key, value] of [
  ['forwardx11', 'yes'], ['forwardx11trusted', 'yes'], ['tunnel', 'yes'],
  ['tunnel', 'point-to-point'], ['tunnel', 'ethernet'], ['controlmaster', 'autoask'],
]) {
  test(`SSH policy round-2 rejects unsafe ${key}=${value}`, () => {
    expectCode('SSH_POLICY', () => subject().validateSshSecurityPolicy([{ key, value, ordinal: 0 }]));
  });
}

test('SSH trust descriptor is cross-bound to operation authority and concrete generation', () => {
  const records = subject().parseSshG(Buffer.from('hostname example.invalid\n'));
  const descriptor = {
    schema_version: 1, purpose: 'CI3_MAC_SSH_TRUST_DESCRIPTOR_V1',
    authority_sha: oid('a'), remote_generation_id: generation('remote', 'b'),
    ssh_executable_path_sha256: digest('1'), ssh_executable_sha256: digest('2'),
    ssh_code_signature_sha256: digest('3'), ssh_version_sha256: digest('4'),
    isolated_config_sha256: digest('5'), known_hosts_sha256: digest('6'),
    identity_public_key_sha256: digest('7'), identity_public_key_fingerprint_sha256: digest('8'),
    host_key_ed25519_fingerprint_sha256: digest('9'), destination_sha256: digest('a'),
    native_records_sha256: subject().sha256(subject().canonicalJson(records)),
    native_record_count: 1, native_key_order: ['hostname'], raw_destination_reported: false,
  };
  assert.equal(subject().validateSshTrustDescriptor(descriptor, records, {
    authoritySha: oid('a'), remoteGenerationId: generation('remote', 'b'),
    executablePathSha256: digest('1'), executableSha256: digest('2'), codeSignatureSha256: digest('3'),
    versionSha256: digest('4'), configSha256: digest('5'), knownHostsSha256: digest('6'),
    identityPublicKeySha256: digest('7'), identityPublicKeyFingerprintSha256: digest('8'),
    hostKeyFingerprintSha256: digest('9'), destinationSha256: digest('a'),
  }), true);
  descriptor.authority_sha = oid('c');
  expectCode('SSH_TRUST_DESCRIPTOR', () => subject().validateSshTrustDescriptor(descriptor, records, {
    authoritySha: oid('a'), remoteGenerationId: generation('remote', 'b'),
  }));
});

test('generic claim-only recovery never receives or invokes the original effect', async () => {
  let effects = 0;
  await rejectCode('CLAIM_CONSUMED_NO_RESULT', () => subject().recoverSettledPhase({
    event: 'VERIFY_SSH', claim: { purpose: 'CI3_MAC_PHASE_CLAIM_V1' }, result: null,
    reobserve: async () => null,
    operation: async () => { effects += 1; },
  }));
  assert.equal(effects, 0);
});

test('physical preflight runs before an original durable phase claim is minted', async () => {
  const order = [];
  const journal = {
    load: async () => null,
    loadPhaseClaim: async () => null,
    loadPhaseResult: async () => null,
    appendPhaseClaim: async (claim) => { order.push('claim'); return subject().sha256(subject().canonicalJson(claim)); },
    settlePhaseReceipt: async (_phase, _claimSha256, result, observation) => ({
      result, receiptSha256: digest('1'), physicalObservationSha256: observation.observation_sha256, observation,
    }),
    appendPhaseResult: async () => digest('3'),
    append: async () => digest('4'),
  };
  await subject().runProtocol({
    context: baseContext(), journal, stopAfter: 'VERIFY_AUTHORITY',
    adapters: {
      preflightPhase: async ({ event }) => { assert.equal(event, 'VERIFY_AUTHORITY'); order.push('preflight'); },
      verifyAuthority: async () => ({ verified: true }),
      observePhase: async ({ event }) => {
        const metadata = { dev: '1', gid: 0, ino: '2', mode: 0o600, mtime_ns: '3', nlink: 1, size: 1, uid: 0 };
        const body = {
          schema_version: 1, purpose: 'CI3_MAC_PHASE_EFFECT_OBSERVATION_V1', phase: event,
          targets: [{
            role: 'synthetic-preflight', state: 'PRESENT', path: '/synthetic/preflight',
            path_sha256: subject().sha256(Buffer.from('/synthetic/preflight')), sha256: digest('2'),
            identity_sha256: subject().sha256(Buffer.from('uid=0;gid=0;mode=384;nlink=1;size=1;mtime=3;dev=1;ino=2')),
            metadata,
          }], raw_values: false,
        };
        return { ...body, observation_sha256: subject().sha256(subject().canonicalJson(body)) };
      },
    },
  });
  assert.deepEqual(order, ['preflight', 'claim']);
});

test('physical phase observation is independently bound to reopened bytes and metadata', () => {
  const first = subject().buildPhysicalObservationSha256({
    bytes: Buffer.from('{"physical":true}\n'),
    metadata: { uid: 501, gid: 20, mode: 0o600, nlink: 1, size: 18, mtime_ns: '1', dev: '2', ino: '3' },
  });
  const second = subject().buildPhysicalObservationSha256({
    bytes: Buffer.from('{"physical":true}\n'),
    metadata: { uid: 501, gid: 20, mode: 0o600, nlink: 1, size: 18, mtime_ns: '1', dev: '2', ino: '4' },
  });
  assert.notEqual(first, second);
  assert.notEqual(first, subject().sha256(subject().canonicalJson({ physical: true })));
});

test('simulator terminal evidence exposes claim receipt and result for every ordered phase', () => {
  assert.equal(subject().SIMULATOR_EVIDENCE_ROLES.length, 21);
  for (const phase of simulatorReceipt().phases) {
    const prefix = `simulator-phase-${phase.toLowerCase().replaceAll('_', '-')}`;
    assert.deepEqual(subject().SIMULATOR_EVIDENCE_ROLES.filter((role) => role.startsWith(prefix)), [
      `${prefix}-claim`, `${prefix}-receipt`, `${prefix}-result`,
    ]);
  }
});

test('scanner authority uses six typed fixed contracts rather than caller-selected absolute paths', () => {
  assert.deepEqual(Object.keys(subject().SCAN_SURFACE_CONTRACTS), SCAN_IDS);
  for (const id of SCAN_IDS) {
    const contract = subject().SCAN_SURFACE_CONTRACTS[id];
    assert.equal(contract.id, id);
    assert.match(contract.collector_version, /^ci3-[a-z0-9-]+-v1$/);
    assert.ok(contract.format);
    assert.ok(contract.fixed_relative_path);
    assert.match(subject().scannerSchemaSha256(id), /^[a-f0-9]{64}$/);
  }
  assert.equal(new Set(SCAN_IDS.map((id) => subject().scannerSchemaSha256(id))).size, 6);
});

test('controller exposes separately authorized one-shot publishers as closed public modes', () => {
  assert.equal(subject().parseControllerMode(['publish-operation-authority']), 'publish-operation-authority');
  assert.equal(subject().parseControllerMode(['publish-privileged-writer-authority']), 'publish-privileged-writer-authority');
});

test('privileged publisher builds the original claim before any root writer installation', () => {
  const claim = subject().buildPrivilegedPublisherClaim({
    authoritySha: oid('a'), terminalGenerationId: generation('terminal', 'b'),
    terminalManifestSha256: digest('c'), writerSourceSha256: digest('d'),
    writerBinarySha256: digest('e'), anchorPathSha256: digest('f'),
  });
  assert.deepEqual(Object.keys(claim).sort(), [
    'anchor_path_sha256', 'attempt', 'authority_sha', 'file_mode', 'gid',
    'immutable_flag', 'normal_executor_authorized', 'purpose', 'retry',
    'schema_version', 'terminal_generation_id', 'terminal_manifest_sha256',
    'uid', 'writer_binary_sha256', 'writer_source_sha256',
  ]);
  assert.equal(claim.attempt, 1);
  assert.equal(claim.retry, false);
  assert.equal(claim.normal_executor_authorized, false);
});

test('privileged publisher receipt is recomputed from the installed root physical identity', () => {
  const receipt = subject().buildPrivilegedPublisherReceipt({
    authoritySha: oid('a'), terminalGenerationId: generation('terminal', 'b'),
    terminalManifestSha256: digest('c'), writerSourceSha256: digest('d'),
    writerBinarySha256: digest('e'), writerSignatureSha256: digest('f'),
    privilegedClaimSha256: digest('1'), authorityPathSha256: digest('2'),
    anchorPathSha256: digest('3'), terminalManifestPathSha256: digest('4'),
    writerExecutablePathSha256: digest('5'), writerExecutableIdentitySha256: digest('6'),
  });
  assert.equal(subject().validatePrivilegedWriterAuthorityReceipt(receipt, {
    authoritySha: oid('a'), terminalGenerationId: generation('terminal', 'b'),
    terminalManifestSha256: digest('c'), writerSourceSha256: digest('d'),
    writerBinarySha256: digest('e'), writerSignatureSha256: digest('f'),
    privilegedClaimSha256: digest('1'), authorityPathSha256: digest('2'),
    anchorPathSha256: digest('3'), terminalManifestPathSha256: digest('4'),
    writerExecutablePathSha256: digest('5'), writerExecutableIdentitySha256: digest('6'),
  }), true);
});

for (const [mode, adapterName, state] of [
  ['publish-operation-authority', 'publishOperationAuthority', 'OPERATION_AUTHORITY_PUBLISHED'],
  ['publish-privileged-writer-authority', 'publishPrivilegedWriterAuthority', 'PRIVILEGED_WRITER_AUTHORITY_PUBLISHED'],
]) {
  test(`${mode} consumes exactly its separately authorized publisher adapter`, async () => {
    const calls = [];
    const outcome = await subject().dispatchControllerMode({
      mode,
      adapters: { [adapterName]: async () => { calls.push(adapterName); return { status: 'CREATED', raw_values: false }; } },
    });
    assert.deepEqual(calls, [adapterName]);
    assert.deepEqual(outcome, { mode, state, raw_values: false });
  });
}

test('operation publisher consumes a schema-exact human authorization receipt bound to the authority', () => {
  const receipt = {
    schema_version: 1, purpose: 'CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V1',
    authority_sha: oid('a'), authority_manifest_sha256: digest('b'),
    node_binary_sha256: digest('c'), operation_authority_sha256: digest('d'),
    publisher_input_manifest_sha256: digest('e'), vps_operation_authority_pass_sha256: digest('f'),
    approved_action: 'PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY',
    attempt: 1, retry: false, raw_values: false,
  };
  assert.equal(subject().validatePublisherHumanAuthorizationReceipt(receipt, {
    authoritySha: oid('a'), authorityManifestSha256: digest('b'),
    nodeBinarySha256: digest('c'), operationAuthoritySha256: digest('d'),
    publisherInputManifestSha256: digest('e'), vpsOperationAuthorityPassSha256: digest('f'),
  }), true);
  delete receipt.approved_action;
  expectCode('OPERATION_AUTHORITY_PUBLISHER', () => subject().validatePublisherHumanAuthorizationReceipt(receipt, {
    authoritySha: oid('a'), authorityManifestSha256: digest('b'),
    nodeBinarySha256: digest('c'), operationAuthoritySha256: digest('d'),
    publisherInputManifestSha256: digest('e'), vpsOperationAuthorityPassSha256: digest('f'),
  }));
});

test('60 E2E definitions are materially distinct and cover every durable phase and crash boundary', () => {
  const scenarios = subject().FULL_PROTOCOL_E2E_SCENARIOS;
  assert.equal(scenarios.length, 60);
  assert.equal(new Set(scenarios.map((scenario) => scenario.id)).size, 60);
  assert.equal(new Set(scenarios.map((scenario) => subject().sha256(subject().canonicalJson(scenario)))).size, 60);
  for (const boundary of ['before-claim', 'after-claim', 'after-effect', 'after-receipt', 'after-result', 'after-event']) {
    assert.ok(scenarios.some((scenario) => scenario.boundary === boundary), boundary);
  }
});

const MODE_TARGETS = Object.freeze([
  ['plan', 'VERIFY_WORKTREE'],
  ['verify-simulator', 'VERIFY_SIMULATOR'],
  ['verify-ssh', 'VERIFY_SSH'],
  ['fetch', 'PUBLISH_LOCAL'],
  ['install-simulator', 'REMOVE_CREDENTIAL'],
  ['scan', 'RUN_SCANS'],
  ['write-terminal-anchor', 'INVOKE_WRITER'],
  ['resume', 'INVOKE_WRITER'],
]);

for (const [mode, expectedLastCall] of MODE_TARGETS) {
  test(`operational mode ${mode} reaches its real state-machine phase instead of an unconditional STOP stub`, async () => {
    const fixture = operationalSyntheticFixture();
    const outcome = await subject().dispatchControllerMode({ mode, ...fixture });
    assert.equal(fixture.calls.at(-1), expectedLastCall);
    assert.equal(outcome.mode, mode);
    assert.equal(outcome.raw_values, false);
  });
}

test('operational status mode is local-only and does not enter an adapter phase', async () => {
  const fixture = operationalSyntheticFixture();
  const outcome = await subject().dispatchControllerMode({ mode: 'status', ...fixture });
  assert.deepEqual(outcome, { mode: 'status', state: 'LOCAL_SYNTHETIC', raw_values: false });
  assert.deepEqual(fixture.calls, []);
});

test('versioned operational journal persists and reloads a phase receipt without rewrite', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-controller-journal-'));
  try {
    const journal = await subject().createVersionedJournal({ root, authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b') });
    const record = { event: 'VERIFY_AUTHORITY', state: 'AUTHORITY_VERIFIED', result: { verified: true }, result_sha256: digest('1') };
    await journal.append(record);
    assert.deepEqual(await journal.load('VERIFY_AUTHORITY'), record);
    assert.deepEqual(await journal.append(record), subject().sha256(subject().canonicalJson(record)));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('versioned operational journal rejects a self-consistent rewrite of an existing event', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-controller-journal-'));
  try {
    const journal = await subject().createVersionedJournal({ root, authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b') });
    await journal.append({ event: 'VERIFY_AUTHORITY', state: 'AUTHORITY_VERIFIED', result: { verified: true }, result_sha256: digest('1') });
    await rejectCode('JOURNAL_DIVERGENT_EXISTING', () => journal.append({ event: 'VERIFY_AUTHORITY', state: 'AUTHORITY_VERIFIED', result: { verified: false }, result_sha256: digest('2') }));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('versioned operational journal keeps original read claim and result separately', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-controller-journal-'));
  try {
    const journal = await subject().createVersionedJournal({ root, authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b') });
    const claim = subject().buildReadClaim({ kind: 'config', bootstrapClaimSha256: digest('1'), expectedPathSha256: digest('2'), expectedSha256: digest('3'), remoteGenerationId: generation('remote', '4'), ssh: baseContext().ssh });
    const claimHash = await journal.appendClaim(claim);
    const result = subject().buildReadResult({ kind: 'config', claimSha256: claimHash, captureSha256: digest('5'), captureIdentitySha256: digest('6'), remoteCommandSha256: digest('7'), descriptorRead: true, bytes: 64, exit: 0, stderrClass: 'EMPTY', startedAt: '2026-08-30T12:00:00.000Z', finishedAt: '2026-08-30T12:00:01.000Z', sshEffectiveConfigSha256: digest('b'), sshTrustDescriptorSha256: digest('2'), remoteGenerationId: generation('remote', '4') });
    await journal.appendResult(result);
    assert.deepEqual(await journal.loadClaim('config'), claim);
    assert.deepEqual(await journal.loadResult('config'), result);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('versioned operational journal emits sanitized local status only', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-controller-journal-'));
  try {
    const journal = await subject().createVersionedJournal({ root, authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b') });
    assert.deepEqual(await journal.status(), { state: 'INIT', raw_values: false });
    await journal.append({ event: 'VERIFY_AUTHORITY', state: 'AUTHORITY_VERIFIED', result: { verified: true }, result_sha256: digest('1') });
    assert.deepEqual(await journal.status(), { state: 'AUTHORITY_VERIFIED', raw_values: false });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('controller self-test CLI is local synthetic and sanitized', () => {
  const result = spawnSync(process.execPath, [new URL('./ci3-bridge-controller.mjs', import.meta.url).pathname, '--self-test'], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, CI3_SENTINEL: 'must-not-be-reported' },
  });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /^CONTROLLER_SELF_TEST PASS checks=\d+ network_calls=0 privilege_prompts=0\n$/);
  assert.equal(`${result.stdout}${result.stderr}`.includes('must-not-be-reported'), false);
});

test('controller unknown mode fails before filesystem and network', () => {
  const result = spawnSync(process.execPath, [new URL('./ci3-bridge-controller.mjs', import.meta.url).pathname, 'unknown', '/tmp/raw'], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /^ERROR MODE_INVALID\n$/);
});

test('round-3 physical observer derives its digest from reopened effect targets rather than the journal receipt', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round3-observer-'));
  try {
    const targetPath = path.join(root, 'local-bridge.receipt.json');
    const targetBytes = Buffer.from('{"effect":"published"}\n');
    await writeFile(targetPath, targetBytes, { mode: 0o600 });
    const observation = await subject().observePhysicalEffect({
      phase: 'PUBLISH_LOCAL',
      targets: [{ role: 'local-receipt', path: targetPath, state: 'PRESENT', expectedSha256: subject().sha256(targetBytes) }],
    });
    assert.equal(observation.phase, 'PUBLISH_LOCAL');
    assert.equal(observation.targets[0].sha256, subject().sha256(targetBytes));
    assert.match(observation.targets[0].identity_sha256, /^[a-f0-9]{64}$/);
    assert.equal(observation.observation_sha256, subject().sha256(subject().canonicalJson({
      phase: observation.phase,
      purpose: observation.purpose,
      raw_values: false,
      schema_version: 1,
      targets: observation.targets,
    })));
    assert.notEqual(observation.observation_sha256, subject().sha256(subject().canonicalJson({ result: { published: true } })));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-3 phase recovery reruns only the typed physical observer and rejects target drift', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round3-reobserve-'));
  try {
    const targetPath = path.join(root, 'effect.json');
    await writeFile(targetPath, 'original\n', { mode: 0o600 });
    const original = await subject().observePhysicalEffect({
      phase: 'VERIFY_AUTHORITY',
      targets: [{ role: 'operation-authority', path: targetPath, state: 'PRESENT', expectedSha256: subject().sha256(Buffer.from('original\n')) }],
    });
    await writeFile(targetPath, 'changed!\n', { mode: 0o600 });
    let effects = 0;
    await rejectCode('PHASE_RECOVERY_DIVERGENCE', () => subject().recoverSettledPhase({
      persistedObservation: original,
      reobserve: () => subject().observePhysicalEffect({
        phase: 'VERIFY_AUTHORITY',
        targets: [{ role: 'operation-authority', path: targetPath, state: 'PRESENT', expectedSha256: subject().sha256(Buffer.from('original\n')) }],
      }),
      operation: async () => { effects += 1; },
    }));
    assert.equal(effects, 0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-3 simulator probe preflight rejects config credential or ACK before their original claims', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round3-simulator-preflight-'));
  try {
    const paths = ['config.json', 'credential.json', 'ack.json'].map((name) => path.join(root, name));
    assert.equal(await subject().assertSimulatorProbeTargetsAbsent(paths), true);
    for (const candidate of paths) {
      await writeFile(candidate, 'preexisting\n', { mode: 0o600 });
      await rejectCode('REJECT_UNCLAIMED_EXISTING_STATE', () => subject().assertSimulatorProbeTargetsAbsent(paths));
      await rm(candidate);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-3 simulator recovery reobserves the physical phase without replaying its effect', async () => {
  const persisted = { config_sha256: digest('1'), credential_sha256: digest('2') };
  let effects = 0;
  let observers = 0;
  const settled = await subject().settleSimulatorPhaseObservation({
    priorReceipt: { observation: persisted },
    effect: async () => { effects += 1; return persisted; },
    reobserve: async () => { observers += 1; return structuredClone(persisted); },
  });
  assert.deepEqual(settled, { observation: persisted, recovered: true });
  assert.equal(effects, 0);
  assert.equal(observers, 1);
});

test('round-3 simulator recovery rejects physical drift instead of adopting a prior receipt', async () => {
  await rejectCode('SIMULATOR_GATE', () => subject().settleSimulatorPhaseObservation({
    priorReceipt: { observation: { probe_ack_sha256: digest('1') } },
    effect: async () => ({ probe_ack_sha256: digest('1') }),
    reobserve: async () => ({ probe_ack_sha256: digest('2') }),
  }));
});

test('round-3 original simulator phase executes its effect exactly once and never calls recovery observer', async () => {
  let effects = 0;
  let observers = 0;
  const observation = { launch_contract_sha256: digest('3') };
  const settled = await subject().settleSimulatorPhaseObservation({
    priorReceipt: null,
    effect: async () => { effects += 1; return observation; },
    reobserve: async () => { observers += 1; return observation; },
  });
  assert.deepEqual(settled, { observation, recovered: false });
  assert.equal(effects, 1);
  assert.equal(observers, 0);
});

test('round-3 scan authority freezes collectors but never accepts a prepublished surface as final evidence', () => {
  const scans = scanSurfaceAuthority();
  for (const id of SCAN_IDS) {
    scans[id] = {
      id,
      collector_version: subject().SCAN_SURFACE_CONTRACTS[id].collector_version,
      format: subject().SCAN_SURFACE_CONTRACTS[id].format,
      source_role: subject().SCAN_SURFACE_CONTRACTS[id].source_role,
      tool_sha256: components().controller.sha256,
      contract_sha256: subject().scannerSchemaSha256(id),
    };
  }
  assert.equal(subject().validateScanSurfaceAuthority(scans, oid('a'), components().controller.sha256), true);
  scans.argv.path = '/prepublished/argv.surface';
  scans.argv.content_sha256 = digest('1');
  expectCode('OPERATION_AUTHORITY', () => subject().validateScanSurfaceAuthority(scans, oid('a'), components().controller.sha256));
});

test('round-3 final scan surface is generation-bound and derived from current operation roots', () => {
  const context = baseContext();
  const sourceBytes = Buffer.from('synthetic current runtime observation\n');
  const bytes = subject().buildFinalScanSurfaceBytes({
    scanId: 'runtime',
    authoritySha: context.authority.commit,
    controllerGenerationId: context.generations.controller,
    terminalGenerationId: context.generations.terminal,
    sourceRoots: [{ role: 'runtime-provenance', sha256: subject().sha256(sourceBytes), identity_sha256: digest('8') }],
    sourceBytes,
  });
  const parsed = JSON.parse(bytes);
  assert.equal(parsed.scan_id, 'runtime');
  assert.equal(parsed.controller_generation_id, context.generations.controller);
  assert.equal(parsed.terminal_generation_id, context.generations.terminal);
  assert.deepEqual(parsed.source_roots, [{ role: 'runtime-provenance', sha256: subject().sha256(sourceBytes), identity_sha256: digest('8') }]);
  assert.equal(parsed.content_sha256, subject().sha256(sourceBytes));
  assert.equal(parsed.content_byte_length, sourceBytes.length);
  assert.deepEqual(Buffer.from(parsed.content_base64, 'base64'), sourceBytes);
});

test('round-3 final scan surface refuses dirty current-operation bytes before publication', () => {
  const context = baseContext();
  expectCode('TERMINAL_SCAN_MATCH', () => subject().buildFinalScanSurfaceBytes({
    scanId: 'runtime', authoritySha: context.authority.commit,
    controllerGenerationId: context.generations.controller,
    terminalGenerationId: context.generations.terminal,
    sourceRoots: [{ role: 'runtime-provenance', sha256: digest('7'), identity_sha256: digest('8') }],
    sourceBytes: Buffer.from('TOKEN=synthetic-secret-value\n'),
  }));
});

function round3VpsPassReceipt() {
  return {
    schema_version: 1,
    purpose: 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1',
    authority_sha: oid('a'),
    authority_parent: '456b4643d1a310bc88458a28a9a62a16dde2e1c8',
    authority_tree: oid('b'),
    authority_subject_sha256: digest('c'),
    authority_manifest_sha256: digest('d'),
    operation_authority_sha256: digest('e'),
    node_candidate_sha256: digest('f'),
    collector_contracts_sha256: digest('1'),
    publisher_input_manifest_sha256: digest('2'),
    remote_generation_id: generation('remote', '3'),
    controller_generation_id: generation('controller', '4'),
    source_generation_id: `src-${digest('5')}`,
    transfer_payload_sha256: digest('6'),
    issuer_authority_sha256: digest('7'),
    issuer_key_sha256: digest('8'),
    signed_payload_sha256: digest('9'),
    signature_base64: Buffer.alloc(64).toString('base64'),
    attempt: 1,
    retry: false,
    raw_values: false,
  };
}

test('round-3 Publisher 1 requires a VPS PASS root that binds every materialized input', () => {
  const receipt = round3VpsPassReceipt();
  assert.equal(subject().validateVpsOperationAuthorityPass(receipt, {
    authoritySha: oid('a'), authorityTree: oid('b'), authoritySubjectSha256: digest('c'),
    authorityManifestSha256: digest('d'), operationAuthoritySha256: digest('e'),
    nodeCandidateSha256: digest('f'), collectorContractsSha256: digest('1'),
    publisherInputManifestSha256: digest('2'), remoteGenerationId: generation('remote', '3'),
    controllerGenerationId: generation('controller', '4'), transferPayloadSha256: digest('6'),
  }), true);
  receipt.operation_authority_sha256 = digest('0');
  expectCode('VPS_OPERATION_AUTHORITY_PASS', () => subject().validateVpsOperationAuthorityPass(receipt, {
    authoritySha: oid('a'), authorityTree: oid('b'), authoritySubjectSha256: digest('c'),
    authorityManifestSha256: digest('d'), operationAuthoritySha256: digest('e'),
    nodeCandidateSha256: digest('f'), collectorContractsSha256: digest('1'),
    publisherInputManifestSha256: digest('2'), remoteGenerationId: generation('remote', '3'),
    controllerGenerationId: generation('controller', '4'), transferPayloadSha256: digest('6'),
  }));
});

test('round-3 SSH provenance keeps public-key byte hash distinct from fingerprint-output hash', () => {
  const provenance = subject().buildSshProvenance({
    executableSha256: digest('1'), codeSignatureSha256: digest('2'), effectiveConfigSha256: digest('3'),
    configSha256: digest('4'), knownHostsSha256: digest('5'), identityPublicKeySha256: digest('6'),
    identityPublicKeyFingerprintSha256: digest('7'), hostKeyEd25519Sha256: digest('8'),
    destinationSha256: digest('9'), versionSha256: digest('a'), trustDescriptorSha256: digest('b'),
  });
  assert.equal(provenance.identity_public_key_sha256, digest('6'));
  assert.equal(provenance.identity_public_key_fingerprint_sha256, digest('7'));
  assert.notEqual(provenance.identity_public_key_sha256, provenance.identity_public_key_fingerprint_sha256);
});

test('round-3 terminal evidence includes RUN_SCANS and authorizes non-circular INVOKE_WRITER and VERIFY_ANCHOR contracts', () => {
  assert.deepEqual(subject().CONTROLLER_EVIDENCE_PHASES, [
    'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
    'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
  ]);
  assert.deepEqual(subject().TERMINAL_SETTLEMENT_PHASES, ['INVOKE_WRITER', 'VERIFY_ANCHOR']);
  const contracts = subject().buildTerminalSettlementContracts({
    authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b'),
    terminalGenerationId: generation('terminal', 'c'), runScansResultSha256: digest('d'),
  });
  assert.deepEqual(contracts.map(({ phase }) => phase), ['INVOKE_WRITER', 'VERIFY_ANCHOR']);
  assert.equal(contracts[1].predecessor_contract_sha256, subject().sha256(subject().canonicalJson(contracts[0])));
});

test('round-3 crash matrix covers all ten durable phases including writer and anchor settlement', () => {
  const scenarios = subject().FULL_PROTOCOL_E2E_SCENARIOS;
  assert.equal(scenarios.length, 60);
  assert.deepEqual([...new Set(scenarios.map(({ phase }) => phase))], [
    'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
    'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
    'INVOKE_WRITER', 'VERIFY_ANCHOR',
  ]);
});

// Round-4 review regressions. Each assertion names an externally observable
// security break and intentionally precedes the production implementation.

test('round-4 physical observations retain the authority-fixed target path for privileged reopen', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round4-target-path-'));
  try {
    const targetPath = path.join(root, 'effect.json');
    const bytes = Buffer.from('{"effect":"current"}\n');
    await writeFile(targetPath, bytes, { mode: 0o600 });
    const observation = await subject().observePhysicalEffect({
      phase: 'VERIFY_AUTHORITY',
      targets: [{ role: 'operation-authority', path: targetPath, state: 'PRESENT', expectedSha256: subject().sha256(bytes) }],
    });
    assert.equal(observation.targets[0].path, targetPath);
    assert.equal(observation.targets[0].path_sha256, subject().sha256(Buffer.from(targetPath)));
    const rewritten = structuredClone(observation);
    rewritten.targets[0].path = path.join(root, 'substituted.json');
    expectCode('PHASE_PHYSICAL_OBSERVATION', () => subject().validatePhysicalEffectObservation(rewritten, 'VERIFY_AUTHORITY'));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-4 a second complete run reobserves all eight normal phases and the privileged marker transaction', async () => {
  const fixture = crashRecoveryFixture({ phase: 'NONE', boundary: 'none', id: 'none' });
  fixture.disableCrash();
  await subject().runProtocol({ adapters: fixture.adapters, context: fixture.context, journal: fixture.journal });
  const originalObserver = fixture.adapters.observePhase;
  const observed = [];
  fixture.adapters.observePhase = async (input) => {
    observed.push(input.event);
    return originalObserver(input);
  };
  const resumed = await subject().runProtocol({ adapters: fixture.adapters, context: fixture.context, journal: fixture.journal });
  assert.equal(resumed.state, 'COMPLETE');
  assert.deepEqual(observed, [
    'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
    'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
  ]);
  assert.equal(fixture.effectCount('INVOKE_WRITER'), 1);
});

for (const phase of [
  'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
  'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
]) {
  test(`round-4 settled event recovery rejects current physical drift in ${phase}`, async () => {
    const fixture = crashRecoveryFixture({ phase: 'NONE', boundary: 'none', id: 'none' });
    fixture.disableCrash();
    await subject().runProtocol({ adapters: fixture.adapters, context: fixture.context, journal: fixture.journal });
    const originalObserver = fixture.adapters.observePhase;
    fixture.adapters.observePhase = async (input) => {
      const observation = await originalObserver(input);
      if (input.event === phase) {
        const rewritten = structuredClone(observation);
        rewritten.targets[0].sha256 = digest('f');
        const { observation_sha256: _old, ...body } = rewritten;
        rewritten.observation_sha256 = subject().sha256(subject().canonicalJson(body));
        return rewritten;
      }
      return observation;
    };
    await rejectCode('PHASE_RECOVERY_DIVERGENCE', () => subject().runProtocol({
      adapters: fixture.adapters, context: fixture.context, journal: fixture.journal,
    }));
  });
}

test('round-4 scan contracts name six authority-fixed semantic source paths, never journal aliases', () => {
  const forbidden = /(?:claim|receipt|result|event)\.json$/;
  for (const id of SCAN_IDS) {
    const contract = subject().SCAN_SURFACE_CONTRACTS[id];
    assert.equal(contract.id, id);
    assert.equal(contract.source_semantics, id);
    assert.match(contract.fixed_source_relative_path, new RegExp(`(?:^|/)${id}\\.surface$`));
    assert.equal(forbidden.test(contract.fixed_source_relative_path), false);
    assert.ok(['REQUIRED_PRESENT', 'PRESENT_OR_PROVEN_ABSENT'].includes(contract.required_state));
  }
});

test('round-4 semantic surface observer reads a present fixed final source and binds its full byte range', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round4-surface-'));
  try {
    const sourcePath = path.join(root, 'final-sources', 'argv.surface');
    await mkdir(path.dirname(sourcePath), { recursive: true, mode: 0o700 });
    const bytes = Buffer.from('["resume"]\n');
    await writeFile(sourcePath, bytes, { mode: 0o600 });
    const observation = await subject().observeTerminalScanSource({ scanId: 'argv', root });
    assert.equal(observation.state, 'PRESENT');
    assert.equal(observation.path, sourcePath);
    assert.deepEqual(observation.byte_range, { start: 0, end: bytes.length });
    assert.equal(observation.content_sha256, subject().sha256(bytes));
    assert.match(observation.identity_sha256, /^[a-f0-9]{64}$/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-4 optional xcresult uses an authenticated fixed-path absence receipt rather than an alias', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round4-absence-'));
  try {
    await mkdir(path.join(root, 'final-sources'), { recursive: true, mode: 0o700 });
    const observation = await subject().observeTerminalScanSource({ scanId: 'xcresult', root });
    assert.equal(observation.state, 'ABSENT');
    assert.equal(observation.path, path.join(root, 'final-sources', 'xcresult.surface'));
    assert.equal(observation.content_sha256, null);
    assert.equal(observation.identity_sha256, null);
    assert.match(observation.parent_identity_sha256, /^[a-f0-9]{64}$/);
    assert.match(observation.absence_observation_sha256, /^[a-f0-9]{64}$/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-4 materializer publishes five semantic final sources and proves the current xcresult absence', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round4-materialize-'));
  const records = {
    argv: Buffer.from('{"mode":"resume"}\n'),
    history: Buffer.from('VERIFY_AUTHORITY\nVERIFY_WORKTREE\n'),
    'terminal-log': Buffer.from('{"event":"VERIFY_SIMULATOR","state":"SIMULATOR_VERIFIED"}\n'),
    attachment: Buffer.from('{"role":"input-manifest","sha256":"' + digest('a') + '"}\n'),
    runtime: Buffer.from('{"engine":"node","synthetic":true}\n'),
  };
  try {
    const observations = await subject().materializeTerminalScanSources({ root, records });
    assert.deepEqual(Object.keys(observations), SCAN_IDS);
    for (const id of SCAN_IDS) {
      const observation = observations[id];
      assert.equal(observation.source_semantics, id);
      assert.equal(observation.path, path.join(root, 'final-sources', `${id}.surface`));
      if (id === 'xcresult') {
        assert.equal(observation.state, 'ABSENT');
        continue;
      }
      assert.equal(observation.state, 'PRESENT');
      assert.deepEqual(await readFile(observation.path), records[id]);
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

function round4SignedVpsAuthority() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const rawPublicKey = Buffer.from(publicKey.export({ format: 'jwk' }).x, 'base64url');
  const issuer = {
    schema_version: 1,
    purpose: 'CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1',
    authority_sha: oid('a'),
    issuer_generation_id: generation('issuer', '9'),
    issuer_identity_sha256: digest('8'),
    public_key_algorithm: 'Ed25519',
    public_key_raw_base64: rawPublicKey.toString('base64'),
    public_key_sha256: subject().sha256(rawPublicKey),
    allowed_pass_purpose: 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1',
    normal_executor_authorized: false,
    raw_values: false,
  };
  const pass = round3VpsPassReceipt();
  pass.issuer_authority_sha256 = subject().sha256(subject().canonicalJson(issuer));
  pass.issuer_key_sha256 = issuer.public_key_sha256;
  const payload = subject().vpsPassSigningPayload(pass);
  pass.signed_payload_sha256 = subject().sha256(payload);
  pass.signature_base64 = ed25519Sign(null, payload, privateKey).toString('base64');
  return { issuer, pass };
}

test('round-4 VPS PASS requires an external Ed25519 issuer root and verifies its signature', () => {
  const { issuer, pass } = round4SignedVpsAuthority();
  assert.equal(subject().verifySignedVpsOperationAuthorityPass(pass, issuer), true);
  const rewritten = structuredClone(pass);
  rewritten.transfer_payload_sha256 = digest('0');
  expectCode('VPS_OPERATION_AUTHORITY_SIGNATURE', () => subject().verifySignedVpsOperationAuthorityPass(rewritten, issuer));
  expectCode('STOP_PRE_AUTHORITY', () => subject().verifySignedVpsOperationAuthorityPass(pass, null));
});

test('round-4 Publisher 1 post-install verifier rejects only a swapped human authorization target', async () => {
  const roles = [
    'node-runtime', 'controller', 'launcher-runtime', 'launcher-bootstrap-authority',
    'launch-attestation', 'authority-manifest',
    'operation-authority', 'human-authorization', 'vps-pass', 'vps-issuer-authority',
    'publisher-input-manifest', 'ssh-config', 'ssh-known-hosts', 'ssh-private-key',
    'ssh-public-key', 'ssh-trust-descriptor',
  ];
  const expected = Object.fromEntries(roles.map((role) => [role, subject().sha256(Buffer.from(role))]));
  await rejectCode('OPERATION_AUTHORITY_PUBLISHER', () => subject().verifyInstalledPublisherTargets({
    expectedSha256ByRole: expected,
    readTarget: async (role) => ({
      bytes: Buffer.from(role === 'human-authorization' ? 'swapped' : role),
      metadata: metadata({
        mode: 0o100000 | (['node-runtime', 'controller', 'launcher-runtime'].includes(role)
          ? 0o555 : role === 'ssh-private-key' ? 0o400 : 0o444),
        uid: 0, gid: 0,
      }),
      immutable: true,
    }),
  }));
});

test('round-4 pre-anchor is pending and only an external settlement over final phase roots declares PASS', () => {
  const preAnchor = subject().buildPreAnchorState({
    authoritySha: oid('a'), terminalGenerationId: generation('terminal', 'b'),
    manifestSha256: digest('c'), evidenceChainSha256: digest('d'),
  });
  assert.equal(preAnchor.terminal_state, 'PENDING_VERIFICATION');
  const settlement = subject().buildTerminalSettlementReceipt({
    authoritySha: oid('a'), generations: baseContext().generations,
    preAnchorSha256: subject().sha256(subject().canonicalJson(preAnchor)),
    invokeWriter: { claim_sha256: digest('1'), receipt_sha256: digest('2'), result_sha256: digest('3') },
    verifyAnchor: { claim_sha256: digest('4'), receipt_sha256: digest('5'), result_sha256: digest('6') },
    settlementAuthoritySha256: digest('7'),
    terminalSettlementContractsSha256: digest('8'),
    terminalPhaseGraphSha256: digest('9'),
    terminalFinalScanSha256: digest('a'),
  });
  assert.equal(settlement.terminal_state, 'TERMINAL_PASS');
  assert.equal(subject().validateTerminalSettlementReceipt(settlement), true);
  const forged = structuredClone(settlement);
  forged.verify_anchor.result_sha256 = digest('8');
  expectCode('TERMINAL_SETTLEMENT', () => subject().validateTerminalSettlementReceipt(forged));
});

test('round-10 protocol reaches COMPLETE only from the single privileged writer settlement triples', async () => {
  const fixture = crashRecoveryFixture({ id: 'none:none', phase: 'NONE', boundary: 'none' });
  fixture.disableCrash();
  let writerCalls = 0;
  const originalWriter = fixture.adapters.invokeWriter;
  fixture.adapters.invokeWriter = async (...args) => {
    writerCalls += 1;
    const writer = await originalWriter(...args);
    for (const triple of [writer.settlement.invoke_writer, writer.settlement.verify_anchor]) {
      assert.match(triple.claim_sha256, /^[a-f0-9]{64}$/);
      assert.match(triple.receipt_sha256, /^[a-f0-9]{64}$/);
      assert.match(triple.result_sha256, /^[a-f0-9]{64}$/);
    }
    return writer;
  };
  const outcome = await subject().runProtocol({
    adapters: fixture.adapters, context: fixture.context, journal: fixture.journal,
  });
  assert.equal(outcome.state, 'COMPLETE');
  assert.equal(outcome.settlement.terminal_state, 'TERMINAL_PASS');
  assert.equal(writerCalls, 1);
});

test('round-5 terminal settlement closes all generations contracts and independently derived phase graph', () => {
  const generations = {
    remote: generation('remote', '1'), controller: generation('controller', '2'),
    simulator: generation('simulator', '3'), terminal: generation('terminal', '4'),
  };
  const receipt = subject().buildTerminalSettlementReceipt({
    authoritySha: oid('a'), generations, preAnchorSha256: digest('5'),
    invokeWriter: { claim_sha256: digest('6'), receipt_sha256: digest('7'), result_sha256: digest('8') },
    verifyAnchor: { claim_sha256: digest('9'), receipt_sha256: digest('a'), result_sha256: digest('b') },
    settlementAuthoritySha256: digest('c'), terminalSettlementContractsSha256: digest('d'),
    terminalPhaseGraphSha256: digest('e'), terminalFinalScanSha256: digest('f'),
  });
  assert.deepEqual(receipt.generations, generations);
  assert.equal(receipt.terminal_settlement_contracts_sha256, digest('d'));
  assert.equal(receipt.terminal_phase_graph_sha256, digest('e'));
  assert.equal(receipt.terminal_final_scan_sha256, digest('f'));
  assert.equal(subject().validateTerminalSettlementReceipt(receipt), true);
});

test('round-5 remote bindings are recomputed from external authority paths and canonical cat grammar', () => {
  const operationRemote = {
    receipt_path: '/srv/ci3.invalid/generation/bridge.receipt.json',
    config_path: '/srv/ci3.invalid/generation/mobile-staging-config.json',
    credential_path: '/srv/ci3.invalid/generation/synthetic-patient.credentials.json',
  };
  const bindings = subject().deriveRemoteAuthorityBindings(operationRemote);
  for (const kind of ['receipt', 'config', 'credential']) {
    assert.equal(bindings[kind].path_sha256, subject().sha256(Buffer.from(operationRemote[`${kind}_path`])));
    assert.equal(bindings[kind].command_sha256, subject().sha256(Buffer.from(`exec /usr/bin/cat -- ${operationRemote[`${kind}_path`]}`)));
  }
});

test('round-5 phase target contract rejects a fully hash-consistent alternate absolute target', () => {
  const authorizedPath = '/authority.invalid/fixed/operation-authority.json';
  const alternatePath = '/authority.invalid/alternate/operation-authority.json';
  const contracts = [{
    phase: 'VERIFY_AUTHORITY',
    targets: [{
      role: 'operation-authority', state: 'PRESENT', path_sha256: subject().sha256(Buffer.from(authorizedPath)),
      modes: [0o444], allowed_uids: [0], allowed_gids: [0], immutable: true,
    }],
  }];
  const observation = {
    phase: 'VERIFY_AUTHORITY',
    targets: [{
      role: 'operation-authority', state: 'PRESENT', path: alternatePath,
      path_sha256: subject().sha256(Buffer.from(alternatePath)),
      sha256: digest('1'), identity_sha256: digest('2'), metadata: metadata({ mode: 0o100444, uid: 0, gid: 0 }),
    }],
  };
  expectCode('PHASE_TARGET_AUTHORITY', () => subject().validateAuthorizedPhaseTargets({ contracts, observation }));
});

test('round-5 actual surface collector preserves complete bytes instead of sanitized summaries', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round5-actual-surfaces-'));
  try {
    const historyPath = path.join(root, 'history.jsonl');
    const terminalPath = path.join(root, 'terminal.log');
    const attachmentPath = path.join(root, 'attachment.bin');
    const xcresultPath = path.join(root, 'actual-result.xcresult');
    await writeFile(historyPath, 'claim-complete\nresult-complete\n', { mode: 0o600 });
    await writeFile(terminalPath, 'stdout-complete\nstderr-empty\n', { mode: 0o600 });
    await writeFile(attachmentPath, Buffer.from([0, 1, 2, 3]), { mode: 0o600 });
    const surfaces = await subject().collectActualTerminalSurfaces({
      argv: ['/root/runtime/node', '/root/runtime/controller.mjs', 'resume'],
      historyPaths: [historyPath], terminalLogPaths: [terminalPath], attachmentPaths: [attachmentPath],
      xcresultPath, runtime: { executable: '/root/runtime/node', exec_argv: [], environment: { PATH: '/usr/bin:/bin' } },
    });
    assert.deepEqual(JSON.parse(surfaces.argv), ['/root/runtime/node', '/root/runtime/controller.mjs', 'resume']);
    assert.match(surfaces.history.toString(), /Y2xhaW0tY29tcGxldGU/);
    assert.match(surfaces['terminal-log'].toString(), /c3Rkb3V0LWNvbXBsZXRl/);
    assert.match(surfaces.attachment.toString(), /AAECAw==/);
    assert.equal(surfaces.xcresult, null);
    assert.deepEqual(JSON.parse(surfaces.runtime), { environment: { PATH: '/usr/bin:/bin' }, exec_argv: [], executable: '/root/runtime/node' });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-5 Publisher 0 is a closed public mode and signs the exact VPS PASS payload', () => {
  assert.equal(subject().parseControllerMode(['publish-vps-operation-authority-pass']), 'publish-vps-operation-authority-pass');
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const publicKeyBytes = Buffer.from(publicKey.export({ format: 'jwk' }).x, 'base64url');
  const issuer = {
    schema_version: 1, purpose: 'CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1', authority_sha: oid('a'),
    issuer_generation_id: `issuer-${'1'.repeat(64)}`, issuer_identity_sha256: digest('2'),
    public_key_algorithm: 'Ed25519', public_key_raw_base64: publicKeyBytes.toString('base64'),
    public_key_sha256: subject().sha256(publicKeyBytes), allowed_pass_purpose: 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1',
    normal_executor_authorized: false, raw_values: false,
  };
  const unsigned = round3VpsPassReceipt();
  unsigned.issuer_authority_sha256 = subject().sha256(subject().canonicalJson(issuer));
  unsigned.issuer_key_sha256 = issuer.public_key_sha256;
  const signed = subject().signVpsOperationAuthorityPass({ unsigned, issuer, privateKey });
  assert.equal(subject().verifySignedVpsOperationAuthorityPass(signed, issuer), true);
});

test('round-5 Publisher 0 operational adapter consumes root authority and publishes one signed no-clobber PASS', async () => {
  const attestation = launchAttestation();
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const publicKeyBytes = Buffer.from(publicKey.export({ format: 'jwk' }).x, 'base64url');
  const issuer = {
    schema_version: 1, purpose: 'CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1', authority_sha: attestation.authority_sha,
    issuer_generation_id: `issuer-${'1'.repeat(64)}`, issuer_identity_sha256: digest('2'),
    public_key_algorithm: 'Ed25519', public_key_raw_base64: publicKeyBytes.toString('base64'),
    public_key_sha256: subject().sha256(publicKeyBytes), allowed_pass_purpose: 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1',
    normal_executor_authorized: false, raw_values: false,
  };
  const unsigned = round3VpsPassReceipt();
  delete unsigned.signed_payload_sha256;
  delete unsigned.signature_base64;
  unsigned.issuer_authority_sha256 = subject().sha256(subject().canonicalJson(issuer));
  unsigned.issuer_key_sha256 = issuer.public_key_sha256;
  const privateKeyDer = privateKey.export({ format: 'der', type: 'pkcs8' });
  let published;
  const runtime = await subject().createVpsOperationAuthorityPassPublisher({
    launchAttestation: attestation,
    io: {
      readIssuer: async () => Buffer.from(subject().canonicalJson(issuer)),
      readUnsignedRequest: async () => Buffer.from(subject().canonicalJson(unsigned)),
      readPrivateKey: async () => privateKeyDer,
      publishNoClobber: async (bytes) => { published = bytes; return 'CREATED'; },
    },
  });
  const result = await runtime.publishVpsOperationAuthorityPass();
  assert.equal(result.status, 'CREATED');
  assert.equal(result.raw_values, false);
  assert.equal(subject().verifySignedVpsOperationAuthorityPass(JSON.parse(published), issuer), true);
});

test('round-6 Publisher 0 accepts only an externally installed immutable bootstrap with fixed runtime and empty environment', async () => {
  const authoritySha = oid('a');
  const generationId = generation('bootstrap', 'b');
  const root = `/var/lib/agentempp/ci3-publisher0-bootstrap/${authoritySha}/${generationId}`;
  const boundary = {
    schema_version: 1,
    purpose: 'CI3_VPS_PUBLISHER0_BOOTSTRAP_AUTHORITY_V2',
    authority_sha: authoritySha,
    bootstrap_generation_id: generationId,
    root,
    node_path: `${root}/runtime/node`,
    node_sha256: digest('1'),
    controller_path: `${root}/runtime/ci3-bridge-controller.mjs`,
    controller_sha256: digest('2'),
    launcher_path: `${root}/runtime/ci3-bridge-launcher.zsh`, launcher_sha256: digest('3'),
    launch_attestation_path: `${root}/runtime/launch-attestation.json`, launch_attestation_sha256: digest('4'),
    authority_manifest_path: `${root}/runtime/authority-manifest.v1`, authority_manifest_sha256: digest('5'),
    descriptor_backend: 'NODE_CORE_PROC_FD_V1', materializer_mode: 'publish-vps-operation-authority-pass',
    issuer_receipt_sha256: digest('3'),
    allowed_environment: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
    user_checkout_executable: false,
    raw_values: false,
  };
  const chain = `${root}/runtime`.split('/').filter(Boolean).map((name, index, names) => ({
    path: `/${names.slice(0, index + 1).join('/')}`,
    uid: 0, gid: 0, mode: index >= names.length - 2 ? 0o555 : 0o755,
    nlink: 1, type: 'directory', symlink: false, immutable: index >= 3,
    identity_sha256: digest(String((index % 9) + 1)),
  }));
  const processState = {
    exec_path: boundary.node_path,
    script_path: boundary.controller_path,
    launcher_path: boundary.launcher_path, launch_attestation_path: boundary.launch_attestation_path,
    authority_manifest_path: boundary.authority_manifest_path, descriptor_backend: boundary.descriptor_backend,
    environment: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
    node_sha256: boundary.node_sha256,
    controller_sha256: boundary.controller_sha256,
    launcher_sha256: boundary.launcher_sha256,
    launch_attestation_sha256: boundary.launch_attestation_sha256,
    authority_manifest_sha256: boundary.authority_manifest_sha256,
  };
  assert.equal(await subject().validatePublisher0BootstrapBoundary({ boundary, processState, chain }), true);
  for (const mutation of [
    (candidate) => { candidate.processState.exec_path = '/usr/local/bin/node'; },
    (candidate) => { candidate.processState.script_path = '/home/operator/checkout/scripts/ci3/ci3-bridge-controller.mjs'; },
    (candidate) => { candidate.processState.environment.NODE_OPTIONS = '--require=/tmp/user.js'; },
    (candidate) => { candidate.chain[4].symlink = true; },
    (candidate) => { candidate.chain[5].uid = 501; },
  ]) {
    const candidate = structuredClone({ boundary, processState, chain });
    mutation(candidate);
    await rejectCode('VPS_PUBLISHER0_BOOTSTRAP', () => subject().validatePublisher0BootstrapBoundary(candidate));
  }
});

test('round-6 runtime evidence uses a closed allowlist and rejects credential-like inherited keys', () => {
  assert.deepEqual(subject().sanitizeTerminalRuntimeEnvironment({
    PATH: '/usr/bin:/bin', HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', TMPDIR: '/private/tmp',
  }), { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin', TMPDIR: '/private/tmp' });
  for (const name of ['AWS_ACCESS_KEY_ID', 'NODE_OPTIONS', 'SUPABASE_SERVICE_ROLE_KEY', 'CI3_CREDENTIAL', 'SSH_AUTH_SOCK']) {
    expectCode('RUNTIME_ENVIRONMENT', () => subject().sanitizeTerminalRuntimeEnvironment({ PATH: '/usr/bin:/bin', [name]: 'synthetic' }));
  }
});

test('round-6 semantic scanners inspect decoded bytes before reversible framing', () => {
  const payloads = {
    history: [Buffer.from('export PASSWORD=synthetic-secret\n')],
    'terminal-log': [Buffer.from('Authorization: Bearer synthetic-token\n')],
    attachment: [Buffer.from('{"service_role":"synthetic-secret"}')],
  };
  for (const [scanId, parts] of Object.entries(payloads)) {
    expectCode('TERMINAL_SCAN_MATCH', () => subject().frameScannedTerminalPayloads(scanId, parts));
  }
  const clean = subject().frameScannedTerminalPayloads('history', [Buffer.from('claim-complete\n')]);
  assert.match(clean.toString(), /Y2xhaW0tY29tcGxldGU/);
});

test('round-6 SSH policy forbids environment forwarding, agent persistence and background authentication', () => {
  const baseline = [
    { key: 'sendenv', value: 'none' }, { key: 'setenv', value: 'none' },
    { key: 'addkeystoagent', value: 'no' }, { key: 'forkafterauthentication', value: 'no' },
    { key: 'identityagent', value: 'none' },
  ];
  assert.equal(subject().validateSshSecurityPolicy(baseline), true);
  for (const [key, value] of [
    ['sendenv', 'LANG'], ['setenv', 'TOKEN=synthetic'], ['addkeystoagent', 'yes'],
    ['forkafterauthentication', 'yes'], ['identityagent', '/tmp/agent.sock'],
  ]) expectCode('SSH_POLICY', () => subject().validateSshSecurityPolicy([{ key, value }]));
});

test('round-6 SSH snapshot remains the same stable physical object across ssh-G and connect', async () => {
  const before = {
    config: { path: '/root/frozen/ssh_config', sha256: digest('1'), identity_sha256: digest('2') },
    known_hosts: { path: '/root/frozen/known_hosts', sha256: digest('3'), identity_sha256: digest('4') },
    identity: { path: '/root/frozen/id_ed25519', sha256: digest('5'), identity_sha256: digest('6') },
    public_key: { path: '/root/frozen/id_ed25519.pub', sha256: digest('7'), identity_sha256: digest('8') },
    trust_descriptor: { path: '/root/frozen/trust-descriptor.json', sha256: digest('9'), identity_sha256: digest('a') },
  };
  assert.equal(await subject().validateStableSshSnapshots({ before, afterSshG: structuredClone(before), afterConnect: structuredClone(before) }), true);
  const swapped = structuredClone(before);
  swapped.identity.identity_sha256 = digest('0');
  await rejectCode('SSH_SNAPSHOT_DRIFT', () => subject().validateStableSshSnapshots({ before, afterSshG: before, afterConnect: swapped }));
});

test('round-6 terminal final scan domain includes journal output settlement and COMPLETE surfaces', () => {
  assert.deepEqual(subject().TERMINAL_FINAL_SURFACE_ROLES, [
    'process-argv', 'controller-journal', 'controller-stdout', 'controller-stderr',
    'terminal-attachments', 'simulator-xcresult', 'runtime-environment',
    'writer-output', 'terminal-settlement', 'complete-result',
  ]);
});

test('round-7 bootstrap environment is an exact closed map before any Node process starts', () => {
  const closed = { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' };
  assert.equal(subject().validateClosedBootstrapEnvironment(closed), true);
  for (const [name, value] of [
    ['NODE_OPTIONS', '--require=/tmp/synthetic-preload.cjs'],
    ['NODE_PATH', '/tmp/synthetic-modules'],
    ['DYLD_INSERT_LIBRARIES', '/tmp/synthetic-loader.dylib'],
    ['DYLD_LIBRARY_PATH', '/tmp/synthetic-libraries'],
    ['ZDOTDIR', '/tmp/synthetic-zdotdir'],
  ]) {
    expectCode('BOOTSTRAP_ENVIRONMENT', () => subject().validateClosedBootstrapEnvironment({ ...closed, [name]: value }));
  }
});

test('round-7 scanner counters count disjoint specific and generic matches without double-counting overlaps', () => {
  const disjoint = subject().scanTerminalSurface(
    'history',
    Buffer.from('ssh user@relay.synthetic.invalid\nhost=second.synthetic.invalid\n'),
  );
  assert.equal(disjoint.counters.raw_destination, 2);
  const overlap = subject().scanTerminalSurface('terminal-log', Buffer.from('host=relay.synthetic.invalid\n'));
  assert.equal(overlap.counters.raw_destination, 1);
});

test('round-7 SSH AddKeysToAgent is the exact single token no and rejects stateful or ambiguous records', () => {
  assert.equal(subject().validateSshSecurityPolicy([{ key: 'addkeystoagent', value: 'no', ordinal: 0 }]), true);
  for (const records of [
    [{ key: 'addkeystoagent', value: '1h', ordinal: 0 }],
    [{ key: 'addkeystoagent', value: 'confirm 1h', ordinal: 0 }],
    [{ key: 'addkeystoagent', value: 'NO', ordinal: 0 }],
    [{ key: 'addkeystoagent', value: ' no ', ordinal: 0 }],
    [
      { key: 'addkeystoagent', value: 'no', ordinal: 0 },
      { key: 'addkeystoagent', value: 'no', ordinal: 1 },
    ],
  ]) expectCode('SSH_POLICY', () => subject().validateSshSecurityPolicy(records));
});

test('round-7 SSH physical snapshot binds and reobserves all five installed files', async () => {
  const before = {
    config: { path: '/root/frozen/ssh_config', sha256: digest('1'), identity_sha256: digest('2') },
    known_hosts: { path: '/root/frozen/known_hosts', sha256: digest('3'), identity_sha256: digest('4') },
    identity: { path: '/root/frozen/id_ed25519', sha256: digest('5'), identity_sha256: digest('6') },
    public_key: { path: '/root/frozen/id_ed25519.pub', sha256: digest('7'), identity_sha256: digest('8') },
    trust_descriptor: { path: '/root/frozen/trust-descriptor.json', sha256: digest('9'), identity_sha256: digest('a') },
  };
  assert.equal(await subject().validateStableSshSnapshots({
    before, afterSshG: structuredClone(before), afterConnect: structuredClone(before),
  }), true);
  for (const role of Object.keys(before)) {
    const drifted = structuredClone(before);
    drifted[role].identity_sha256 = digest('0');
    await rejectCode('SSH_SNAPSHOT_DRIFT', () => subject().validateStableSshSnapshots({
      before, afterSshG: before, afterConnect: drifted,
    }));
  }
});

test('round-7 descriptor-relative transaction reads and exclusively publishes through one retained chain', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-dirfd-transaction-'));
  try {
    await mkdir(path.join(root, 'authority'), { mode: 0o700 });
    await mkdir(path.join(root, 'authority', 'runtime'), { mode: 0o700 });
    await writeFile(path.join(root, 'authority', 'runtime', 'node'), 'synthetic-node', { mode: 0o600 });
    const read = await subject().descriptorRelativeFileTransaction({
      root,
      relativePath: 'authority/runtime/node',
      operation: 'read',
      expectedMode: 0o600,
      expectedUid: process.getuid(),
      expectedGid: process.getgid(),
      allowedDirectoryModes: [0o700],
      helperPath: descriptorHelperPath, helperSha256: descriptorHelperSha256,
    });
    assert.equal(read.bytes.toString(), 'synthetic-node');
    const created = await subject().descriptorRelativeFileTransaction({
      root,
      relativePath: 'authority/vps-operation-authority.pass.json',
      operation: 'create-exclusive',
      bytes: Buffer.from('synthetic-pass'),
      expectedMode: 0o600,
      expectedUid: process.getuid(),
      expectedGid: process.getgid(),
      allowedDirectoryModes: [0o700],
      helperPath: descriptorHelperPath, helperSha256: descriptorHelperSha256,
    });
    assert.equal(created.bytes.toString(), 'synthetic-pass');
    await rejectCode('DESCRIPTOR_NO_CLOBBER', () => subject().descriptorRelativeFileTransaction({
      root,
      relativePath: 'authority/vps-operation-authority.pass.json',
      operation: 'create-exclusive',
      bytes: Buffer.from('replacement'),
      expectedMode: 0o600,
      expectedUid: process.getuid(),
      expectedGid: process.getgid(),
      allowedDirectoryModes: [0o700],
      helperPath: descriptorHelperPath, helperSha256: descriptorHelperSha256,
    }));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-7 descriptor-relative transaction rejects an intermediate symlink and writable runtime', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-dirfd-negative-'));
  try {
    await mkdir(path.join(root, 'outside'), { mode: 0o700 });
    await writeFile(path.join(root, 'outside', 'node'), 'synthetic-node', { mode: 0o600 });
    await symlink(path.join(root, 'outside'), path.join(root, 'runtime'));
    await rejectCode('DESCRIPTOR_CHAIN', () => subject().descriptorRelativeFileTransaction({
      root,
      relativePath: 'runtime/node',
      operation: 'read', expectedMode: 0o600,
      expectedUid: process.getuid(), expectedGid: process.getgid(), allowedDirectoryModes: [0o700],
      helperPath: descriptorHelperPath, helperSha256: descriptorHelperSha256,
    }));
    await rm(path.join(root, 'runtime'));
    await mkdir(path.join(root, 'runtime'), { mode: 0o777 });
    await writeFile(path.join(root, 'runtime', 'node'), 'synthetic-node', { mode: 0o600 });
    await rejectCode('DESCRIPTOR_CHAIN', () => subject().descriptorRelativeFileTransaction({
      root,
      relativePath: 'runtime/node',
      operation: 'read', expectedMode: 0o600,
      expectedUid: process.getuid(), expectedGid: process.getgid(), allowedDirectoryModes: [0o700],
      helperPath: descriptorHelperPath, helperSha256: descriptorHelperSha256,
    }));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-7 retained directory identities stop a physical ancestor swap before leaf creation', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-dirfd-swap-'));
  try {
    await mkdir(path.join(root, 'authority'), { mode: 0o700 });
    await rejectCode('DESCRIPTOR_CHAIN_DRIFT', () => subject().descriptorRelativeFileTransaction({
      root,
      relativePath: 'authority/pass.json',
      operation: 'create-exclusive', bytes: Buffer.from('synthetic-pass'), expectedMode: 0o600,
      expectedUid: process.getuid(), expectedGid: process.getgid(), allowedDirectoryModes: [0o700],
      helperPath: descriptorHelperPath, helperSha256: descriptorHelperSha256,
      scheduler: {
        afterChainOpen: async () => {
          await rename(path.join(root, 'authority'), path.join(root, 'authority-original'));
          await mkdir(path.join(root, 'authority'), { mode: 0o700 });
        },
      },
    }));
    await lstat(path.join(root, 'authority', 'pass.json')).then(
      () => assert.fail('replacement tree received publication'),
      (error) => assert.equal(error.code, 'ENOENT'),
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-7 posterior scan cannot publish a normal-owned terminal tail receipt', async () => {
  assert.equal(subject().publishTerminalTailReceipt, undefined);
  assert.equal(subject().validateTerminalTailReceipt, undefined);
  const controllerSource = await readFile(new URL('./ci3-bridge-controller.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(controllerSource, /CI3_TERMINAL_TAIL_RECEIPT_V1|claimTerminalTail|publishTerminalTail/);
  assert.match(controllerSource, /CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1/);
});

test('round-7 Publisher 1 contract installs bootstrap inputs and the exact five-file SSH snapshot', async () => {
  const authoritySha = oid('a');
  const controllerGenerationId = generation('controller', 'b');
  const contract = subject().buildPublisherInstallationContract({ authoritySha, controllerGenerationId });
  const versionRoot = `/Library/Application Support/Agentempp/ci3-controller-authority/${authoritySha}`;
  const snapshotRoot = `${versionRoot}/ssh-snapshots/${controllerGenerationId}`;
  assert.deepEqual(contract.ssh, {
    config: { path: `${snapshotRoot}/ssh_config`, mode: 0o444 },
    known_hosts: { path: `${snapshotRoot}/known_hosts`, mode: 0o444 },
    identity: { path: `${snapshotRoot}/id_ed25519`, mode: 0o400 },
    public_key: { path: `${snapshotRoot}/id_ed25519.pub`, mode: 0o444 },
    trust_descriptor: { path: `${snapshotRoot}/trust-descriptor.json`, mode: 0o444 },
  });
  assert.deepEqual(Object.keys(contract.targets), [
    'node-runtime', 'controller', 'launcher-runtime', 'launcher-bootstrap-authority',
    'launch-attestation', 'authority-manifest',
    'operation-authority', 'human-authorization', 'vps-pass', 'vps-issuer-authority',
    'publisher-input-manifest', 'ssh-config', 'ssh-known-hosts', 'ssh-private-key',
    'ssh-public-key', 'ssh-trust-descriptor',
  ]);
  const expected = Object.fromEntries(Object.keys(contract.targets).map((role) => [role, subject().sha256(Buffer.from(role))]));
  assert.equal(await subject().verifyInstalledPublisherTargets({
    expectedSha256ByRole: expected,
    readTarget: async (role) => ({
      bytes: Buffer.from(role),
      metadata: metadata({ mode: 0o100000 | contract.targets[role].mode, uid: 0, gid: 0 }),
      immutable: true,
    }),
  }), true);
});

test('round-8 Publisher 1 derives the external launcher line authority from already authenticated bytes', () => {
  const authority = subject().buildExternalLauncherAuthority({
    authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b'),
    nodeSha256: digest('1'), controllerSha256: digest('2'), launcherSha256: digest('3'),
    launchAttestationSha256: digest('4'), authorityManifestSha256: digest('5'),
    allowedModes: [
      'plan', 'verify-simulator', 'verify-ssh', 'fetch', 'install-simulator', 'scan',
      'write-terminal-anchor', 'resume', 'status', 'publish-privileged-writer-authority',
    ],
  });
  assert.equal(subject().validateExternalLauncherAuthority(authority, {
    authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b'),
    nodeSha256: digest('1'), controllerSha256: digest('2'), launcherSha256: digest('3'),
    launchAttestationSha256: digest('4'), authorityManifestSha256: digest('5'),
    allowedModes: [
      'plan', 'verify-simulator', 'verify-ssh', 'fetch', 'install-simulator', 'scan',
      'write-terminal-anchor', 'resume', 'status', 'publish-privileged-writer-authority',
    ],
  }), true);
  assert.match(authority.toString('utf8'), /^CI3_EXTERNAL_LAUNCHER_AUTHORITY_V1\n/);
  const drifted = Buffer.from(authority.toString('utf8').replace(`node_sha256 ${digest('1')}`, `node_sha256 ${digest('0')}`));
  expectCode('EXTERNAL_LAUNCHER_AUTHORITY', () => subject().validateExternalLauncherAuthority(drifted, {
    authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b'),
    nodeSha256: digest('1'), controllerSha256: digest('2'), launcherSha256: digest('3'),
    launchAttestationSha256: digest('4'), authorityManifestSha256: digest('5'),
    allowedModes: [
      'plan', 'verify-simulator', 'verify-ssh', 'fetch', 'install-simulator', 'scan',
      'write-terminal-anchor', 'resume', 'status', 'publish-privileged-writer-authority',
    ],
  }));
});

test('round-7 authenticated transport manifest binds every executable bootstrap and SSH input', () => {
  const roles = [
    'node-runtime', 'controller', 'launcher-runtime', 'launch-attestation', 'authority-manifest',
    'operation-authority', 'ssh-config', 'ssh-known-hosts', 'ssh-private-key',
    'ssh-public-key', 'ssh-trust-descriptor',
  ];
  const entries = roles.map((role, index) => ({
    role, path_sha256: digest(String((index % 9) + 1)), sha256: digest(String(((index + 1) % 9) + 1)),
  }));
  const manifest = {
    schema_version: 1,
    purpose: 'CI3_VPS_PUBLISHER_INPUT_MANIFEST_V2',
    authority_sha: oid('a'),
    remote_generation_id: generation('remote', 'b'),
    controller_generation_id: generation('controller', 'c'),
    collector_contracts_sha256: digest('d'),
    entries,
    transfer_payload_sha256: subject().sha256(subject().canonicalJson(entries)),
    raw_values: false,
  };
  assert.equal(subject().validatePublisherTransportManifest(manifest, {
    authoritySha: oid('a'), remoteGenerationId: generation('remote', 'b'),
    controllerGenerationId: generation('controller', 'c'), collectorContractsSha256: digest('d'), entries,
  }), true);
  for (const role of roles) {
    const mutated = structuredClone(manifest);
    mutated.entries.find((entry) => entry.role === role).sha256 = digest('0');
    expectCode('OPERATION_AUTHORITY_PUBLISHER', () => subject().validatePublisherTransportManifest(mutated, {
      authoritySha: oid('a'), remoteGenerationId: generation('remote', 'b'),
      controllerGenerationId: generation('controller', 'c'), collectorContractsSha256: digest('d'), entries,
    }));
  }
});

test('round-7 Publisher 0 bootstrap binds the complete runtime and materializer tool before execution', async () => {
  const authoritySha = oid('a');
  const bootstrapGenerationId = generation('bootstrap', 'b');
  const root = `/var/lib/agentempp/ci3-publisher0-bootstrap/${authoritySha}/${bootstrapGenerationId}`;
  const runtime = `${root}/runtime`;
  const boundary = {
    schema_version: 1, purpose: 'CI3_VPS_PUBLISHER0_BOOTSTRAP_AUTHORITY_V2',
    authority_sha: authoritySha, bootstrap_generation_id: bootstrapGenerationId, root,
    node_path: `${runtime}/node`, node_sha256: digest('1'),
    controller_path: `${runtime}/ci3-bridge-controller.mjs`, controller_sha256: digest('2'),
    launcher_path: `${runtime}/ci3-bridge-launcher.zsh`, launcher_sha256: digest('3'),
    launch_attestation_path: `${runtime}/launch-attestation.json`, launch_attestation_sha256: digest('4'),
    authority_manifest_path: `${runtime}/authority-manifest.v1`, authority_manifest_sha256: digest('5'),
    descriptor_backend: 'NODE_CORE_PROC_FD_V1', issuer_receipt_sha256: digest('7'),
    materializer_mode: 'publish-vps-operation-authority-pass',
    allowed_environment: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
    user_checkout_executable: false, raw_values: false,
  };
  const names = `${root}/runtime`.split('/').filter(Boolean);
  const chain = names.map((name, index) => ({
    path: `/${names.slice(0, index + 1).join('/')}`,
    uid: 0, gid: 0, mode: index >= names.length - 2 ? 0o555 : 0o755,
    nlink: 1, type: 'directory', symlink: false, immutable: index >= 3,
    identity_sha256: digest(String((index % 9) + 1)),
  }));
  const processState = {
    exec_path: boundary.node_path, script_path: boundary.controller_path,
    launcher_path: boundary.launcher_path, launch_attestation_path: boundary.launch_attestation_path,
    authority_manifest_path: boundary.authority_manifest_path,
    descriptor_backend: boundary.descriptor_backend,
    environment: boundary.allowed_environment,
    node_sha256: boundary.node_sha256, controller_sha256: boundary.controller_sha256,
    launcher_sha256: boundary.launcher_sha256,
    launch_attestation_sha256: boundary.launch_attestation_sha256,
    authority_manifest_sha256: boundary.authority_manifest_sha256,
  };
  assert.equal(await subject().validatePublisher0BootstrapBoundary({ boundary, processState, chain }), true);
  for (const mutate of [
    (candidate) => { candidate.chain.at(-1).mode = 0o777; },
    (candidate) => { candidate.processState.launcher_sha256 = digest('0'); },
    (candidate) => { candidate.processState.descriptor_backend = 'PATHNAME_V1'; },
    (candidate) => { candidate.processState.environment.NODE_OPTIONS = '--require=/tmp/synthetic.cjs'; },
  ]) {
    const candidate = structuredClone({ boundary, processState, chain });
    mutate(candidate);
    await rejectCode('VPS_PUBLISHER0_BOOTSTRAP', () => subject().validatePublisher0BootstrapBoundary(candidate));
  }
});

test('round-8 resume is pre-terminal until the receipt-last controller tail is settled', async () => {
  const fixture = operationalSyntheticFixture();
  const outcome = await subject().dispatchControllerMode({ mode: 'resume', ...fixture });
  assert.deepEqual(outcome, { mode: 'resume', state: 'PRE_TERMINAL_UNPUBLISHED', raw_values: false });
  assert.equal(fixture.calls.at(-1), 'INVOKE_WRITER');
});

test('round-8 internal tail terminalizer is a closed dispatch that alone returns TERMINAL_PASS', async () => {
  assert.equal(subject().parseControllerMode(['--terminalize-tail']), '--terminalize-tail');
  const calls = [];
  const outcome = await subject().dispatchControllerMode({
    mode: '--terminalize-tail',
    adapters: {
      terminalizeTail: async () => {
        calls.push('terminalizeTail');
        return { terminal_state: 'TERMINAL_PASS', receipt_is_commit_marker: true, raw_values: false };
      },
    },
  });
  assert.deepEqual(calls, ['terminalizeTail']);
  assert.deepEqual(outcome, { mode: '--terminalize-tail', state: 'TERMINAL_PASS', raw_values: false });
});

test('round-8 status remains unpublished after COMPLETE until a validated terminal tail exists', async () => {
  const before = await subject().dispatchControllerMode({
    mode: 'status', adapters: {}, context: {},
    journal: { terminalStatus: async () => ({ state: 'PRE_TERMINAL_UNPUBLISHED', raw_values: false }) },
  });
  assert.deepEqual(before, { mode: 'status', state: 'PRE_TERMINAL_UNPUBLISHED', raw_values: false });
  const after = await subject().dispatchControllerMode({
    mode: 'status', adapters: {}, context: {},
    journal: { terminalStatus: async () => ({ state: 'TERMINAL_PASS', raw_values: false }) },
  });
  assert.deepEqual(after, { mode: 'status', state: 'TERMINAL_PASS', raw_values: false });
});

test('round-9 normal journal cannot manufacture the privileged terminal PASS marker', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round8-tail-journal-'));
  try {
    const context = baseContext();
    const journal = await subject().createVersionedJournal({
      root, authoritySha: context.authority.commit,
      controllerGenerationId: context.generations.controller,
      terminalAuthority: { context, readMarker: async () => null },
    });
    for (const event of [
      'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
      'READ_RECEIPT', 'READ_CONFIG', 'READ_CREDENTIAL',
      'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS',
      'INVOKE_WRITER', 'VERIFY_ANCHOR', 'COMPLETE',
    ]) await journal.append({ event });
    assert.deepEqual(await journal.terminalStatus(), { state: 'PRE_TERMINAL_UNPUBLISHED', raw_values: false });
    assert.equal(journal.claimTerminalTail, undefined);
    assert.equal(journal.publishTerminalTail, undefined);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

function terminalTransitiveInputs(context, paths, {
  mutateAuthority = null, mutatePreAnchor = null, mutateSettlement = null,
} = {}) {
  const bytes = (value) => subject().canonicalJson(value);
  const externalAuthorityRoots = [
    'operation-authority-root', 'vps-pass-root', 'vps-issuer-authority-root',
    'human-authorization-root', 'publisher-input-manifest-root',
    'ssh-trust-descriptor', 'ssh-public-key', 'ssh-public-key-fingerprint',
  ].map((role, index) => ({ role, sha256: digest(String(index + 1)) }));
  const phaseTargetRoots = subject().CONTROLLER_EVIDENCE_PHASES.map((phase, index) => ({
    phase, receipt_sha256: digest(String(index + 1)), targets_sha256: digest(String(index + 2)),
  }));
  const scanReceipts = SCAN_IDS.map((id, index) => ({
    id, sha256: digest(String(index + 1)),
  }));
  const baselineExternalAuthorityRoots = structuredClone(externalAuthorityRoots);
  const baselinePhaseTargetRoots = structuredClone(phaseTargetRoots);
  const baselineScanReceipts = structuredClone(scanReceipts);
  const runScansResultSha256 = digest('6');
  const terminalSettlementContracts = subject().buildTerminalSettlementContracts({
    authoritySha: context.authority.commit,
    controllerGenerationId: context.generations.controller,
    terminalGenerationId: context.generations.terminal,
    runScansResultSha256,
  });
  const terminalSettlementContractsSha256 = subject().sha256(bytes(terminalSettlementContracts));
  const preAnchor = {
    schema_version: 1, purpose: 'CI3_PRE_TERMINAL_ANCHOR_V1',
    authority_sha: context.authority.commit, authority_tree: context.authority.tree,
    authority_manifest_sha256: context.authority.manifest_sha256,
    components: structuredClone(context.authority.components),
    writer_source_sha256: context.authority.components.writer.sha256,
    writer_binary_sha256: digest('6'), writer_signature_sha256: digest('7'),
    generations: structuredClone(context.generations),
    bootstrap_claim_sha256: digest('8'), claim_result_chain_sha256: digest('9'),
    remote_bundle_sha256: digest('a'), local_bundle_sha256: digest('b'),
    ssh_provenance_sha256: digest('c'), simulator_gate_sha256: digest('d'),
    simulator_install_sha256: digest('e'),
    writer_authority_path_sha256: subject().sha256(Buffer.from(paths.privilegedAuthority)),
    privileged_claim_sha256: digest('2'), evidence_chain_sha256: digest('f'),
    external_authority_roots: externalAuthorityRoots,
    external_authority_roots_sha256: subject().sha256(bytes(externalAuthorityRoots)),
    phase_target_roots: phaseTargetRoots,
    phase_target_roots_sha256: subject().sha256(bytes(phaseTargetRoots)),
    scan_ids: [...SCAN_IDS], scan_receipts: scanReceipts,
    terminal_settlement_contracts_sha256: terminalSettlementContractsSha256,
    important_finding_ids: [...FINDING_IDS], terminal_state: 'PENDING_VERIFICATION',
    created_at_utc: '2026-08-30T12:00:00.000Z', raw_values: false, secret_read: false,
    privilege_mode: 'MACOS_ROOT_SINGLE_ADMIN_PROMPT', append_only: true, no_clobber: true,
  };
  mutatePreAnchor?.(preAnchor);
  const preAnchorBytes = bytes(preAnchor);
  const terminalManifestPath = '/fixed.invalid/terminal-anchor.manifest.v1.json';
  const writerExecutablePath = subject().privilegedWriterExecutablePath(
    context.authority.commit, context.generations.terminal,
  );
  const authorityExpected = {
    authoritySha: context.authority.commit,
    terminalGenerationId: context.generations.terminal,
    terminalManifestSha256: digest('0'),
    writerSourceSha256: context.authority.components.writer.sha256,
    writerBinarySha256: digest('6'), writerSignatureSha256: digest('7'),
    privilegedClaimSha256: digest('2'),
    authorityPathSha256: subject().sha256(Buffer.from(paths.privilegedAuthority)),
    anchorPathSha256: subject().sha256(Buffer.from(paths.preAnchor)),
    terminalManifestPathSha256: subject().sha256(Buffer.from(terminalManifestPath)),
    writerExecutablePathSha256: subject().sha256(Buffer.from(writerExecutablePath)),
    writerExecutableIdentitySha256: digest('5'),
  };
  const preAnchorExpected = {
    authorityTree: context.authority.tree,
    authorityManifestSha256: context.authority.manifest_sha256,
    components: structuredClone(context.authority.components),
    writerSourceSha256: context.authority.components.writer.sha256,
    writerBinarySha256: digest('6'), writerSignatureSha256: digest('7'),
    generations: structuredClone(context.generations),
    bootstrapClaimSha256: digest('8'), claimResultChainSha256: digest('9'),
    remoteBundleSha256: digest('a'), localBundleSha256: digest('b'),
    sshProvenanceSha256: digest('c'), simulatorGateSha256: digest('d'),
    simulatorInstallSha256: digest('e'),
    writerAuthorityPathSha256: subject().sha256(Buffer.from(paths.privilegedAuthority)),
    privilegedClaimSha256: digest('2'), evidenceChainSha256: digest('f'),
    externalAuthorityRoots: baselineExternalAuthorityRoots,
    phaseTargetRoots: baselinePhaseTargetRoots,
    scanReceipts: baselineScanReceipts,
    terminalSettlementContractsSha256,
    createdAtUtc: '2026-08-30T12:00:00.000Z',
  };
  const authorityReceipt = {
    schema_version: 1, purpose: 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1',
    authority_sha: authorityExpected.authoritySha,
    terminal_generation_id: authorityExpected.terminalGenerationId,
    terminal_manifest_sha256: authorityExpected.terminalManifestSha256,
    writer_source_sha256: authorityExpected.writerSourceSha256,
    writer_binary_sha256: authorityExpected.writerBinarySha256,
    writer_signature_sha256: authorityExpected.writerSignatureSha256,
    privileged_claim_sha256: authorityExpected.privilegedClaimSha256,
    authority_path_sha256: authorityExpected.authorityPathSha256,
    anchor_path_sha256: authorityExpected.anchorPathSha256,
    terminal_manifest_path_sha256: authorityExpected.terminalManifestPathSha256,
    writer_executable_path_sha256: authorityExpected.writerExecutablePathSha256,
    writer_executable_identity_sha256: authorityExpected.writerExecutableIdentitySha256,
    writer_executable_uid: 0, writer_executable_gid: 0, writer_executable_mode: '0555',
    writer_executable_immutable_flag: 'UF_IMMUTABLE', normal_executor_authorized: false,
    attempt: 1, retry: false, raw_values: false,
  };
  mutateAuthority?.(authorityReceipt);
  const authorityReceiptBytes = bytes(authorityReceipt);
  const evidenceRoots = subject().TERMINAL_MANIFEST_EVIDENCE_ROLES.map((role, index) => ({
    role, sha256: digest(String((index % 10))),
  }));
  const semanticRoots = {
    authority_manifest_sha256: context.authority.manifest_sha256,
    bootstrap_claim_sha256: digest('8'), claim_result_chain_sha256: digest('9'),
    remote_bundle_sha256: digest('a'), local_bundle_sha256: digest('b'),
    ssh_provenance_sha256: digest('c'), simulator_gate_sha256: digest('d'),
    simulator_install_sha256: digest('e'), evidence_chain_sha256: digest('f'),
    external_authority_roots: baselineExternalAuthorityRoots,
    phase_target_roots: baselinePhaseTargetRoots,
    scan_receipts: baselineScanReceipts,
    terminal_settlement_contracts_sha256: terminalSettlementContractsSha256,
  };
  const semanticEvidenceReceipt = {
    schema_version: 1, purpose: 'CI3_TERMINAL_SEMANTIC_VALIDATION_RECEIPT_V1',
    authority_sha: context.authority.commit, generations: structuredClone(context.generations),
    terminal_manifest_sha256: authorityExpected.terminalManifestSha256,
    writer_binary_sha256: authorityExpected.writerBinarySha256,
    writer_signature_sha256: authorityExpected.writerSignatureSha256,
    writer_executable_identity_sha256: authorityExpected.writerExecutableIdentitySha256,
    run_scans_result_sha256: runScansResultSha256,
    terminal_settlement_contracts: terminalSettlementContracts,
    terminal_settlement_contracts_sha256: terminalSettlementContractsSha256,
    evidence_count: evidenceRoots.length, evidence_roots: evidenceRoots,
    evidence_roots_sha256: subject().sha256(bytes(evidenceRoots)),
    evidence_roles_sha256: subject().sha256(Buffer.from(subject().TERMINAL_MANIFEST_EVIDENCE_ROLES.join('\n'))),
    scan_receipt_count: baselineScanReceipts.length,
    scan_receipt_roots: baselineScanReceipts,
    scan_receipt_roots_sha256: subject().sha256(bytes(baselineScanReceipts)),
    semantic_roots: semanticRoots,
    semantic_roots_sha256: subject().sha256(bytes(semanticRoots)), raw_values: false,
  };
  const metadata = (content, seed) => ({
    dev: String(seed), gid: 0, ino: String(seed + 100), mode: 0o444,
    mtime_ns: String(seed + 200), nlink: 1, size: content.length, uid: 0,
  });
  const target = (role, targetPath, content, seed) => {
    const observed = metadata(content, seed);
    return {
      role, state: 'PRESENT', path: targetPath,
      path_sha256: subject().sha256(Buffer.from(targetPath)), sha256: subject().sha256(content),
      identity_sha256: subject().sha256(Buffer.from([
        `uid=${observed.uid}`, `gid=${observed.gid}`, `mode=${observed.mode}`,
        `nlink=${observed.nlink}`, `size=${observed.size}`, `mtime=${observed.mtime_ns}`,
        `dev=${observed.dev}`, `ino=${observed.ino}`,
      ].join(';'))),
      metadata: observed,
    };
  };
  const observation = (phase, targets) => {
    const body = {
      schema_version: 1, purpose: 'CI3_MAC_PHASE_EFFECT_OBSERVATION_V1',
      phase, targets, raw_values: false,
    };
    return { ...body, observation_sha256: subject().sha256(bytes(body)) };
  };
  const invokeClaim = {
    schema_version: 1, purpose: 'CI3_MAC_PHASE_CLAIM_V1', phase: 'INVOKE_WRITER',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    predecessor_result_sha256: runScansResultSha256,
    contract_sha256: subject().sha256(bytes(terminalSettlementContracts[0])),
    attempt: 1, retry: false, raw_values: false,
  };
  const invokeWriterClaimBytes = bytes(invokeClaim);
  const invokeResultBody = {
    pre_anchor_sha256: subject().sha256(preAnchorBytes),
    writer_transaction: 'SINGLE_PRIVILEGED_INVOCATION', raw_values: false,
  };
  const invokeObservation = observation('INVOKE_WRITER', [
    target('terminal-pre-anchor', paths.preAnchor, preAnchorBytes, 1),
  ]);
  const invokeReceipt = {
    schema_version: 1, purpose: 'CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1', phase: 'INVOKE_WRITER',
    claim_sha256: subject().sha256(invokeWriterClaimBytes), result: invokeResultBody,
    result_sha256: subject().sha256(bytes(invokeResultBody)), observation: invokeObservation,
    raw_values: false,
  };
  const invokeWriterReceiptBytes = bytes(invokeReceipt);
  const invokeResult = {
    schema_version: 1, purpose: 'CI3_MAC_PHASE_RESULT_V1', phase: 'INVOKE_WRITER',
    claim_sha256: subject().sha256(invokeWriterClaimBytes),
    receipt_sha256: subject().sha256(invokeWriterReceiptBytes),
    physical_observation_sha256: invokeObservation.observation_sha256,
    terminal_state: 'PHASE_SETTLED', raw_values: false,
  };
  const invokeWriterResultBytes = bytes(invokeResult);
  const verifyClaim = {
    schema_version: 1, purpose: 'CI3_MAC_PHASE_CLAIM_V1', phase: 'VERIFY_ANCHOR',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    predecessor_result_sha256: subject().sha256(invokeWriterResultBytes),
    contract_sha256: subject().sha256(bytes(terminalSettlementContracts[1])),
    attempt: 1, retry: false, raw_values: false,
  };
  const verifyAnchorClaimBytes = bytes(verifyClaim);
  const verifyResultBody = {
    pre_anchor_sha256: subject().sha256(preAnchorBytes), readback_verified: true, raw_values: false,
  };
  const verifyObservation = observation('VERIFY_ANCHOR', [
    target('terminal-pre-anchor-readback', paths.preAnchor, preAnchorBytes, 1),
    target('invoke-writer-result-root', paths.invokeWriterResult, invokeWriterResultBytes, 2),
  ]);
  const verifyReceipt = {
    schema_version: 1, purpose: 'CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1', phase: 'VERIFY_ANCHOR',
    claim_sha256: subject().sha256(verifyAnchorClaimBytes), result: verifyResultBody,
    result_sha256: subject().sha256(bytes(verifyResultBody)), observation: verifyObservation,
    raw_values: false,
  };
  const verifyAnchorReceiptBytes = bytes(verifyReceipt);
  const verifyResult = {
    schema_version: 1, purpose: 'CI3_MAC_PHASE_RESULT_V1', phase: 'VERIFY_ANCHOR',
    claim_sha256: subject().sha256(verifyAnchorClaimBytes),
    receipt_sha256: subject().sha256(verifyAnchorReceiptBytes),
    physical_observation_sha256: verifyObservation.observation_sha256,
    terminal_state: 'PHASE_SETTLED', raw_values: false,
  };
  const verifyAnchorResultBytes = bytes(verifyResult);
  const invokeWriter = {
    claim_sha256: subject().sha256(invokeWriterClaimBytes),
    receipt_sha256: subject().sha256(invokeWriterReceiptBytes),
    result_sha256: subject().sha256(invokeWriterResultBytes),
  };
  const verifyAnchor = {
    claim_sha256: subject().sha256(verifyAnchorClaimBytes),
    receipt_sha256: subject().sha256(verifyAnchorReceiptBytes),
    result_sha256: subject().sha256(verifyAnchorResultBytes),
  };
  const phaseGraph = [
    { phase: 'INVOKE_WRITER', ...invokeWriter }, { phase: 'VERIFY_ANCHOR', ...verifyAnchor },
  ];
  const settlement = subject().buildTerminalSettlementReceipt({
    authoritySha: context.authority.commit, generations: context.generations,
    preAnchorSha256: subject().sha256(preAnchorBytes), invokeWriter, verifyAnchor,
    settlementAuthoritySha256: subject().sha256(authorityReceiptBytes),
    terminalSettlementContractsSha256,
    terminalPhaseGraphSha256: subject().sha256(bytes(phaseGraph)),
    terminalFinalScanSha256: digest('9'),
  });
  mutateSettlement?.(settlement);
  const settlementBytes = bytes(settlement);
  const writerOutputBytes = bytes({
    schema_version: 1, purpose: 'CI3_PRIVILEGED_WRITER_OUTPUT_V1',
    authority_sha: context.authority.commit, terminal_generation_id: context.generations.terminal,
    pre_anchor_sha256: subject().sha256(preAnchorBytes),
    terminal_settlement_sha256: subject().sha256(settlementBytes), raw_values: false,
  });
  const scanResults = SCAN_IDS.map((id) => ({ id, match_count: 0 }));
  const terminalFinalScanBytes = bytes({
    schema_version: 1, purpose: 'CI3_TERMINAL_FINAL_SCAN_V1',
    authority_sha: context.authority.commit, terminal_generation_id: context.generations.terminal,
    surface_roles: [
      'process-argv', 'controller-journal', 'controller-stdout', 'controller-stderr',
      'terminal-attachments', 'simulator-xcresult', 'runtime-environment',
      'writer-output', 'terminal-settlement',
    ],
    scan_results: scanResults, input_sha256: digest('a'), input_byte_length: 1, raw_values: false,
  });
  const completeBytes = bytes({
    schema_version: 1, purpose: 'CI3_TERMINAL_COMPLETE_RESULT_V1',
    authority_sha: context.authority.commit, generations: context.generations,
    terminal_generation_id: context.generations.terminal,
    pre_anchor_sha256: subject().sha256(preAnchorBytes),
    terminal_settlement_sha256: subject().sha256(settlementBytes),
    terminal_final_scan_sha256: subject().sha256(terminalFinalScanBytes),
    terminal_state: 'COMPLETE', raw_values: false,
  });
  const completeFinalScanBytes = bytes({
    schema_version: 1, purpose: 'CI3_TERMINAL_COMPLETE_FINAL_SCAN_V1',
    authority_sha: context.authority.commit, terminal_generation_id: context.generations.terminal,
    surface_roles: ['complete-result'], scan_results: scanResults,
    input_sha256: subject().sha256(completeBytes), input_byte_length: completeBytes.length, raw_values: false,
  });
  const completeResult = { terminal_commit_contract_sha256: digest('b') };
  const completeEventBytes = bytes({
    event: 'COMPLETE', state: 'COMPLETE', result: completeResult,
    result_sha256: subject().sha256(bytes(completeResult)),
  });
  return {
    authorityExpected, preAnchorExpected, semanticEvidenceReceipt,
    authorityReceiptBytes, completeBytes, completeEventBytes, completeFinalScanBytes,
    invokeWriterClaimBytes, invokeWriterReceiptBytes, invokeWriterResultBytes,
    journalFrameBytes: Buffer.concat([Buffer.from('events/COMPLETE.json\n'), completeEventBytes]),
    preAnchorBytes, settlementBytes, stderrBytes: Buffer.alloc(0),
    stdoutBytes: Buffer.from('CONTROLLER RESUME TERMINAL_PASS state=TERMINAL_PASS raw_values=false\n'),
    terminalFinalScanBytes, verifyAnchorClaimBytes, verifyAnchorReceiptBytes,
    verifyAnchorResultBytes, writerOutputBytes,
  };
}

test('round-9 privileged terminal marker binds authority generations fixed paths and exact posterior bytes', () => {
  const context = baseContext();
  const journalGenerationRoot = '/fixed.invalid/controller-journal/'
    + `${context.authority.commit}/${context.generations.controller}`;
  const paths = subject().derivePrivilegedTerminalPassPaths({ context, journalGenerationRoot });
  assert.equal(paths.marker, `/Library/Application Support/Agentempp/ci3-terminal-authority/`
    + `${context.authority.commit}/${context.generations.terminal}/terminal-pass.marker.json`);
  assert.equal(paths.completeEvent, `/Library/Application Support/Agentempp/ci3-terminal-authority/`
    + `${context.authority.commit}/${context.generations.terminal}/controller-complete.event.json`);
  assert.equal(paths.preAnchor, `/Library/Application Support/Agentempp/ci3-terminal-authority/`
    + `${context.authority.commit}/${context.generations.terminal}/pre-anchor.json`);
  assert.equal(paths.writerOutput, `/Library/Application Support/Agentempp/ci3-terminal-authority/`
    + `${context.authority.commit}/${context.generations.terminal}/writer-output.json`);
  assert.equal(paths.terminalFinalScan, `/Library/Application Support/Agentempp/ci3-terminal-authority/`
    + `${context.authority.commit}/${context.generations.terminal}/terminal-final-scan.json`);
  assert.equal(paths.invokeWriterClaim, `/Library/Application Support/Agentempp/ci3-terminal-authority/`
    + `${context.authority.commit}/${context.generations.terminal}/terminal-phases/invoke-writer.claim.json`);
  assert.equal(paths.verifyAnchorResult, `/Library/Application Support/Agentempp/ci3-terminal-authority/`
    + `${context.authority.commit}/${context.generations.terminal}/terminal-phases/verify-anchor.result.json`);
  const inputs = terminalTransitiveInputs(context, paths);
  const marker = subject().buildPrivilegedTerminalPassMarker({ context, paths, ...inputs });
  assert.equal(subject().validatePrivilegedTerminalPassMarker({ marker, context, paths, ...inputs }), true);
  assert.equal(subject().validatePrivilegedTerminalTransitiveRoots({ context, paths, ...inputs }), true);
  assert.deepEqual(marker.generations, context.generations);
  assert.equal(marker.normal_executor_authorized, false);
  assert.equal(marker.pre_anchor_sha256, subject().sha256(inputs.preAnchorBytes));
  assert.equal(marker.writer_output_sha256, subject().sha256(inputs.writerOutputBytes));
  assert.equal(marker.terminal_final_scan_sha256, subject().sha256(inputs.terminalFinalScanBytes));
  assert.equal(Object.keys(marker.paths).length, 18);
  for (const mutation of [
    (candidate) => { candidate.authority_sha = oid('0'); },
    (candidate) => { candidate.generations.remote = generation('remote', '0'); },
    (candidate) => { candidate.paths.marker_sha256 = digest('0'); },
    (candidate) => { candidate.complete_event_sha256 = digest('0'); },
    (candidate) => { candidate.controller_sha256 = digest('0'); },
    (candidate) => { candidate.launcher_sha256 = digest('0'); },
  ]) {
    const forged = structuredClone(marker);
    mutation(forged);
    expectCode('TERMINAL_TAIL_AUTHORITY', () => subject().validatePrivilegedTerminalPassMarker({
      marker: forged, context, paths, ...inputs,
    }));
  }
  const alternatePaths = { ...paths, marker: '/tmp/user-selected-terminal-pass.json' };
  expectCode('TERMINAL_TAIL_AUTHORITY', () => subject().buildPrivilegedTerminalPassMarker({
    context, paths: alternatePaths, ...inputs,
  }));
  expectCode('TERMINAL_TAIL_AUTHORITY', () => subject().buildPrivilegedTerminalPassMarker({
    context, paths, ...Object.fromEntries(Object.entries(inputs).filter(([key]) => key !== 'preAnchorBytes')),
  }));
  expectCode('TERMINAL_TAIL_AUTHORITY', () => subject().validatePrivilegedTerminalTransitiveRoots({
    context, paths, ...inputs, verifyAnchorResultBytes: Buffer.from(inputs.verifyAnchorResultBytes).fill(0x20, 4, 5),
  }));
  assert.equal(subject().validatePrivilegedTerminalRootDirectoryEntries({
    terminalEntries: [
      'complete-final-scan.json', 'complete-result.json', 'controller-complete.event.json',
      'controller-journal.final.frame', 'controller-stderr.final.frame', 'controller-stdout.final.frame',
      'pre-anchor.json', 'privileged-authority.receipt.json', 'terminal-final-scan.json',
      'terminal-pass.marker.json', 'terminal-phases', 'terminal-settlement.json', 'writer',
      'writer-output.json',
    ],
    phaseEntries: [
      'invoke-writer.claim.json', 'invoke-writer.receipt.json', 'invoke-writer.result.json',
      'verify-anchor.claim.json', 'verify-anchor.receipt.json', 'verify-anchor.result.json',
    ],
    writerEntries: ['ci3-terminal-anchor-writer'],
  }), true);
  expectCode('TERMINAL_TAIL_AUTHORITY', () => subject().validatePrivilegedTerminalRootDirectoryEntries({
    terminalEntries: ['terminal-pass.marker.json'], phaseEntries: [], writerEntries: [],
  }));
  expectCode('TERMINAL_TAIL_AUTHORITY', () => subject().validatePrivilegedTerminalRootDirectoryEntries({
    terminalEntries: [
      'complete-final-scan.json', 'complete-result.json', 'controller-complete.event.json',
      'controller-journal.final.frame', 'controller-stderr.final.frame', 'controller-stdout.final.frame',
      'pre-anchor.json', 'privileged-authority.receipt.json', 'terminal-final-scan.json',
      'terminal-pass.marker.json', 'terminal-phases', 'terminal-settlement.json', 'writer',
      'writer-output.json',
      'unexpected-normal-root.json',
    ],
    phaseEntries: [
      'invoke-writer.claim.json', 'invoke-writer.receipt.json', 'invoke-writer.result.json',
      'verify-anchor.claim.json', 'verify-anchor.receipt.json', 'verify-anchor.result.json',
    ],
    writerEntries: ['ci3-terminal-anchor-writer'],
  }));
});

test('round-13 common terminal corpus validator rejects self-consistently rehashed semantic mutations', () => {
  const context = baseContext();
  const journalGenerationRoot = '/fixed.invalid/controller-journal/'
    + `${context.authority.commit}/${context.generations.controller}`;
  const paths = subject().derivePrivilegedTerminalPassPaths({ context, journalGenerationRoot });
  const cases = [
    ['authority extra field', { mutateAuthority: (value) => { value.unexpected = false; } }],
    ['authority schema 9', { mutateAuthority: (value) => { value.schema_version = 9; } }],
    ['authority attempt 9', { mutateAuthority: (value) => { value.attempt = 9; } }],
    ['authority retry true', { mutateAuthority: (value) => { value.retry = true; } }],
    ['authority raw true', { mutateAuthority: (value) => { value.raw_values = true; } }],
    ['authority purpose', { mutateAuthority: (value) => { value.purpose = 'WRONG'; } }],
    ['authority generation', { mutateAuthority: (value) => { value.terminal_generation_id = generation('terminal', '0'); } }],
    ['authority manifest', { mutateAuthority: (value) => { value.terminal_manifest_sha256 = digest('1'); } }],
    ['authority source', { mutateAuthority: (value) => { value.writer_source_sha256 = digest('0'); } }],
    ['authority binary', { mutateAuthority: (value) => { value.writer_binary_sha256 = digest('0'); } }],
    ['authority relation', { mutateAuthority: (value) => { value.writer_signature_sha256 = digest('0'); } }],
    ['authority claim', { mutateAuthority: (value) => { value.privileged_claim_sha256 = digest('0'); } }],
    ['authority path', { mutateAuthority: (value) => { value.authority_path_sha256 = digest('0'); } }],
    ['anchor path', { mutateAuthority: (value) => { value.anchor_path_sha256 = digest('0'); } }],
    ['manifest path', { mutateAuthority: (value) => { value.terminal_manifest_path_sha256 = digest('0'); } }],
    ['writer path', { mutateAuthority: (value) => { value.writer_executable_path_sha256 = digest('0'); } }],
    ['writer identity', { mutateAuthority: (value) => { value.writer_executable_identity_sha256 = digest('0'); } }],
    ['writer owner', { mutateAuthority: (value) => { value.writer_executable_uid = 501; } }],
    ['writer mode', { mutateAuthority: (value) => { value.writer_executable_mode = '0755'; } }],
    ['writer flag', { mutateAuthority: (value) => { value.writer_executable_immutable_flag = 'NONE'; } }],
    ['pre-anchor extra field', { mutatePreAnchor: (value) => { value.unexpected = false; } }],
    ['pre-anchor schema 9', { mutatePreAnchor: (value) => { value.schema_version = 9; } }],
    ['pre-anchor raw true', { mutatePreAnchor: (value) => { value.raw_values = true; } }],
    ['pre-anchor purpose', { mutatePreAnchor: (value) => { value.purpose = 'WRONG'; } }],
    ['pre-anchor timestamp', { mutatePreAnchor: (value) => { value.created_at_utc = 'not-utc'; } }],
    ['pre-anchor relation', { mutatePreAnchor: (value) => { value.authority_tree = oid('0'); } }],
    ['pre-anchor generation', { mutatePreAnchor: (value) => { value.generations.remote = generation('remote', '0'); } }],
    ['pre-anchor component', { mutatePreAnchor: (value) => { value.components.writer.sha256 = digest('0'); } }],
    ['pre-anchor source', { mutatePreAnchor: (value) => { value.writer_source_sha256 = digest('0'); } }],
    ['pre-anchor binary', { mutatePreAnchor: (value) => { value.writer_binary_sha256 = digest('0'); } }],
    ['pre-anchor signature', { mutatePreAnchor: (value) => { value.writer_signature_sha256 = digest('0'); } }],
    ['pre-anchor claim', { mutatePreAnchor: (value) => { value.privileged_claim_sha256 = digest('0'); } }],
    ['pre-anchor authority path', { mutatePreAnchor: (value) => { value.writer_authority_path_sha256 = digest('0'); } }],
    ['pre-anchor external root and rehash', { mutatePreAnchor: (value) => {
      value.external_authority_roots[0].sha256 = digest('0');
      value.external_authority_roots_sha256 = subject().sha256(subject().canonicalJson(value.external_authority_roots));
    } }],
    ['pre-anchor phase target and rehash', { mutatePreAnchor: (value) => {
      value.phase_target_roots[0].targets_sha256 = digest('0');
      value.phase_target_roots_sha256 = subject().sha256(subject().canonicalJson(value.phase_target_roots));
    } }],
    ['pre-anchor scan receipt', { mutatePreAnchor: (value) => { value.scan_receipts[0].sha256 = digest('0'); } }],
    ['pre-anchor scan id', { mutatePreAnchor: (value) => { value.scan_ids[0] = 'runtime'; } }],
    ['pre-anchor finding', { mutatePreAnchor: (value) => { value.important_finding_ids[0] = 'WRONG'; } }],
    ['pre-anchor evidence chain', { mutatePreAnchor: (value) => { value.evidence_chain_sha256 = digest('0'); } }],
    ['pre-anchor secret policy', { mutatePreAnchor: (value) => { value.secret_read = true; } }],
    ['pre-anchor privilege policy', { mutatePreAnchor: (value) => { value.privilege_mode = 'NORMAL'; } }],
    ['pre-anchor append policy', { mutatePreAnchor: (value) => { value.append_only = false; } }],
    ['settlement extra field', { mutateSettlement: (value) => { value.unexpected = false; } }],
    ['settlement schema 9', { mutateSettlement: (value) => { value.schema_version = 9; } }],
    ['settlement raw true', { mutateSettlement: (value) => { value.raw_values = true; } }],
    ['settlement result', { mutateSettlement: (value) => { value.terminal_state = 'PRE_ANCHOR'; } }],
    ['settlement relation', { mutateSettlement: (value) => { value.pre_anchor_sha256 = digest('0'); } }],
  ];
  for (const [label, options] of cases) {
    const inputs = terminalTransitiveInputs(context, paths, options);
    assert.throws(() => subject().validatePrivilegedTerminalTransitiveRoots({
      context, paths, ...inputs,
    }), (error) => error?.code === 'TERMINAL_TAIL_AUTHORITY', label);
  }
  const positive = terminalTransitiveInputs(context, paths);
  const marker = subject().buildPrivilegedTerminalPassMarker({ context, paths, ...positive });
  assert.equal(subject().validatePrivilegedTerminalPassCorpus({
    marker, context, paths, ...positive,
  }), true);
  assert.equal(subject().validatePrivilegedTerminalPassCorpus({
    marker, context, paths, ...positive,
  }), true, 'exact-existing revalidation stays deterministic');
  for (const mutateMarker of [
    (value) => { value.unexpected = false; },
    (value) => { value.schema_version = 9; },
    (value) => { value.raw_values = true; },
    (value) => { value.purpose = 'WRONG'; },
    (value) => { value.terminal_state = 'PENDING_VERIFICATION'; },
    (value) => { value.terminal_settlement_sha256 = digest('0'); },
  ]) {
    const forgedMarker = structuredClone(marker);
    mutateMarker(forgedMarker);
    expectCode('TERMINAL_TAIL_AUTHORITY', () => subject().validatePrivilegedTerminalPassCorpus({
      marker: forgedMarker, context, paths, ...positive,
    }));
  }
});

test('round-13 status resume and terminal tail all use the canonical terminal corpus validator', async () => {
  const context = baseContext();
  const journalGenerationRoot = '/fixed.invalid/controller-journal/'
    + `${context.authority.commit}/${context.generations.controller}`;
  const paths = subject().derivePrivilegedTerminalPassPaths({ context, journalGenerationRoot });
  const observed = (options = {}) => {
    const inputs = terminalTransitiveInputs(context, paths, options);
    return {
      marker: subject().buildPrivilegedTerminalPassMarker({ context, paths, ...inputs }),
      paths, inputs,
    };
  };
  let current = observed();
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round13-common-reader-'));
  try {
    const journal = await subject().createVersionedJournal({
      root, authoritySha: context.authority.commit,
      controllerGenerationId: context.generations.controller,
      terminalAuthority: { context, readMarker: async () => current },
    });
    for (const event of [
      'VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH',
      'READ_RECEIPT', 'READ_CONFIG', 'READ_CREDENTIAL', 'PUBLISH_LOCAL',
      'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS', 'INVOKE_WRITER',
      'VERIFY_ANCHOR', 'COMPLETE',
    ]) await journal.append({ event });
    assert.deepEqual(await subject().dispatchControllerMode({
      mode: 'status', adapters: {}, context, journal,
    }), { mode: 'status', state: 'TERMINAL_PASS', raw_values: false });
    const resumeFixture = operationalSyntheticFixture();
    resumeFixture.journal.terminalStatus = journal.terminalStatus;
    assert.deepEqual(await subject().dispatchControllerMode({
      mode: 'resume', adapters: resumeFixture.adapters,
      context: resumeFixture.context, journal: resumeFixture.journal,
    }), { mode: 'resume', state: 'TERMINAL_PASS', raw_values: false });
    const emitted = [];
    const tail = await subject().createOperationalTerminalTailAdapter({
      runtime: { context, journal, terminalAuthority: { readMarker: async () => current } },
      emit: async (bytes) => { emitted.push(Buffer.from(bytes)); },
    });
    assert.equal((await tail.terminalizeTail()).terminal_state, 'TERMINAL_PASS');
    assert.deepEqual(emitted, [current.inputs.stdoutBytes]);
    current = observed({ mutateAuthority: (value) => { value.attempt = 9; } });
    await rejectCode('TERMINAL_TAIL_AUTHORITY', () => subject().dispatchControllerMode({
      mode: 'status', adapters: {}, context, journal,
    }));
    await rejectCode('TERMINAL_TAIL_AUTHORITY', () => tail.terminalizeTail());
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-14 canonical corpus rejects ADVERSESARIAL_PHASE_CONTRACTS disconnected from RUN_SCANS', () => {
  const context = baseContext();
  const journalGenerationRoot = '/fixed.invalid/controller-journal/'
    + `${context.authority.commit}/${context.generations.controller}`;
  const paths = subject().derivePrivilegedTerminalPassPaths({ context, journalGenerationRoot });
  const inputs = terminalTransitiveInputs(context, paths);
  const runScansResultSha256 = digest('0');
  const terminalSettlementContracts = subject().buildTerminalSettlementContracts({
    authoritySha: context.authority.commit,
    controllerGenerationId: context.generations.controller,
    terminalGenerationId: context.generations.terminal,
    runScansResultSha256,
  });
  const semanticEvidenceReceipt = {
    schema_version: 1,
    purpose: 'CI3_TERMINAL_SEMANTIC_VALIDATION_RECEIPT_V1',
    authority_sha: context.authority.commit,
    generations: structuredClone(context.generations),
    terminal_manifest_sha256: inputs.authorityExpected.terminalManifestSha256,
    run_scans_result_sha256: runScansResultSha256,
    terminal_settlement_contracts: terminalSettlementContracts,
    terminal_settlement_contracts_sha256: subject().sha256(subject().canonicalJson(terminalSettlementContracts)),
    evidence_count: 71,
    scan_receipt_count: 6,
    raw_values: false,
  };
  assert.throws(() => subject().validatePrivilegedTerminalTransitiveRoots({
    context, paths, ...inputs, semanticEvidenceReceipt,
  }), (error) => error?.code === 'TERMINAL_TAIL_AUTHORITY', 'ADVERSESARIAL_PHASE_CONTRACTS=ACCEPTED');
});

test('round-14 operational reader executes the Git-bound writer semantic validator over all 71 roles', async () => {
  if (process.platform !== 'darwin') {
    const source = await readFile(new URL('./ci3-terminal-anchor-writer.swift', import.meta.url), 'utf8');
    assert.match(source, /CI3_TERMINAL_SEMANTIC_VALIDATION_RECEIPT_V1/);
    assert.match(source, /evidence_count/);
    assert.match(source, /scan_receipt_count/);
    return;
  }
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round14-operational-reader-'));
  try {
    const scenarioId = 'VERIFY_AUTHORITY:before-claim';
    const scenarioSha256 = subject().sha256(Buffer.from(scenarioId));
    const protocolStatePath = path.join(root, 'protocol-state.json');
    await writeFile(protocolStatePath, subject().canonicalJson({
      records: [], events: [], claims: [], results: [], scenario_trace: [], crash_observed: false,
      phase_claims: [], phase_receipts: [], phase_results: [], phase_produced: [],
      phase_effect_counts: [], phase_paths: [],
    }), { mode: 0o600 });
    const descriptorPath = path.join(root, 'fixture.json');
    const materialized = spawnSync(process.execPath, [
      new URL('./ci3-terminal-anchor-writer.test.mjs', import.meta.url).pathname,
      '--materialize-synthetic-fixture',
    ], {
      encoding: 'utf8', timeout: 60000,
      env: {
        HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin',
        CI3_SYNTHETIC_WRITER_BINARY: descriptorHelperPath,
        CI3_SYNTHETIC_WRITER_SHA256: descriptorHelperSha256,
        CI3_SYNTHETIC_FIXTURE_DESCRIPTOR: descriptorPath,
        CI3_SYNTHETIC_FIXTURE_PARENT: root,
        CI3_SYNTHETIC_PROTOCOL_STATE_PATH: protocolStatePath,
        CI3_SYNTHETIC_E2E_SCENARIO: scenarioId,
        CI3_SYNTHETIC_SCENARIO_SHA256: scenarioSha256,
      },
    });
    assert.equal(materialized.status, 0, materialized.stderr);
    const descriptor = JSON.parse(await readFile(descriptorPath, 'utf8'));
    const writerStat = await lstat(descriptorHelperPath, { bigint: true });
    const writerIdentitySha256 = subject().sha256(Buffer.from([
      `uid=${writerStat.uid}`, `gid=${writerStat.gid}`, `mode=${writerStat.mode & 0o777n}`,
      `nlink=${writerStat.nlink}`, `size=${writerStat.size}`, `mtime=${writerStat.mtimeNs}`,
      `dev=${writerStat.dev}`, `ino=${writerStat.ino}`,
    ].join(';')));
    const context = baseContext();
    context.authority.commit = descriptor.authority;
    context.generations = descriptor.generations;
    const receipt = subject().validateTerminalManifestEvidenceWithCanonicalWriter({
      writerPath: descriptorHelperPath,
      manifestPath: descriptor.manifest_path,
      context,
      expectedManifestSha256: subject().sha256(await readFile(descriptor.manifest_path)),
      expectedWriterBinarySha256: descriptorHelperSha256,
      expectedWriterSignatureSha256: subject().sha256(Buffer.from('SYNTHETIC_TEST_BUILD')),
      expectedWriterIdentitySha256: writerIdentitySha256,
    });
    assert.equal(receipt.evidence_count, 71);
    assert.equal(receipt.scan_receipt_count, 6);
    assert.equal(receipt.semantic_roots.phase_target_roots.length, 8);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-15 Node and Swift serialize the same exact BigInt physical identity at sub-millisecond mtime', async () => {
  if (process.platform !== 'darwin') {
    const source = await readFile(new URL('./ci3-terminal-anchor-writer.swift', import.meta.url), 'utf8');
    assert.match(source, /mtime_ns/);
    assert.match(source, /st_mtimespec/);
    const observed = {
      uid: 0n, gid: 0n, mode: 0o100555n, nlink: 1n, size: 1n,
      mtimeNs: 1_788_176_481_711_164_293n, dev: 2n, ino: 3n,
    };
    assert.match(subject().physicalIdentityFromBigIntStat(observed).identity_sha256, /^[0-9a-f]{64}$/);
    return;
  }
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round15-physical-identity-'));
  try {
    const writerPath = path.join(root, 'ci3-terminal-anchor-writer');
    const compiled = spawnSync('/usr/bin/xcrun', [
      'swiftc', '-parse-as-library', '-D', 'CI3_SYNTHETIC_TEST',
      new URL('./ci3-terminal-anchor-writer.swift', import.meta.url).pathname, '-o', writerPath,
    ], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 120000 });
    assert.equal(compiled.status, 0, compiled.stderr);
    const writerSha256 = subject().sha256(await readFile(writerPath));
    const nonMillisecondSeconds = 1_788_176_481.711_164_3;
    await utimes(writerPath, nonMillisecondSeconds, nonMillisecondSeconds);
    const writerStat = await lstat(writerPath, { bigint: true });
    assert.notEqual(writerStat.mtimeNs % 1_000_000n, 0n, `mtime_ns=${writerStat.mtimeNs}`);

    const protocolStatePath = path.join(root, 'protocol-state.json');
    await writeFile(protocolStatePath, subject().canonicalJson({
      records: [], events: [], claims: [], results: [], scenario_trace: [], crash_observed: false,
      phase_claims: [], phase_receipts: [], phase_results: [], phase_produced: [],
      phase_effect_counts: [], phase_paths: [],
    }), { mode: 0o600 });
    const descriptorPath = path.join(root, 'fixture.json');
    const scenarioId = 'VERIFY_AUTHORITY:before-claim';
    const materialized = spawnSync(process.execPath, [
      new URL('./ci3-terminal-anchor-writer.test.mjs', import.meta.url).pathname,
      '--materialize-synthetic-fixture',
    ], {
      encoding: 'utf8', timeout: 60000,
      env: {
        HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin',
        CI3_SYNTHETIC_WRITER_BINARY: writerPath,
        CI3_SYNTHETIC_WRITER_SHA256: writerSha256,
        CI3_SYNTHETIC_FIXTURE_DESCRIPTOR: descriptorPath,
        CI3_SYNTHETIC_FIXTURE_PARENT: root,
        CI3_SYNTHETIC_PROTOCOL_STATE_PATH: protocolStatePath,
        CI3_SYNTHETIC_E2E_SCENARIO: scenarioId,
        CI3_SYNTHETIC_SCENARIO_SHA256: subject().sha256(Buffer.from(scenarioId)),
      },
    });
    assert.equal(materialized.status, 0, materialized.stderr);
    const descriptor = JSON.parse(await readFile(descriptorPath, 'utf8'));
    const validated = spawnSync(writerPath, [
      '--validate-manifest', descriptor.manifest_path, descriptor.authority,
      descriptor.generations.remote, descriptor.generations.controller,
      descriptor.generations.simulator, descriptor.generations.terminal,
    ], { encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' }, timeout: 60000 });
    assert.equal(validated.status, 0, validated.stderr);
    const swiftReceipt = JSON.parse(validated.stdout.trim());

    const numberStat = await lstat(writerPath);
    const roundedIdentitySha256 = subject().sha256(Buffer.from([
      `uid=${numberStat.uid}`, `gid=${numberStat.gid}`, `mode=${numberStat.mode & 0o777}`,
      `nlink=${numberStat.nlink}`, `size=${numberStat.size}`,
      `mtime=${String(BigInt(Math.trunc(numberStat.mtimeMs * 1e6)))}`,
      `dev=${String(numberStat.dev)}`, `ino=${String(numberStat.ino)}`,
    ].join(';')));
    const nodeIdentity = typeof subject().physicalIdentityFromBigIntStat === 'function'
      ? subject().physicalIdentityFromBigIntStat(writerStat)
      : { identity_sha256: roundedIdentitySha256 };
    const equal = nodeIdentity.identity_sha256 === swiftReceipt.writer_executable_identity_sha256;
    assert.equal(equal, true, `equal=${equal} mtime_ns=${writerStat.mtimeNs}`);

    const mutated = subject().physicalIdentityFromBigIntStat({ ...writerStat, mtimeNs: writerStat.mtimeNs + 1n });
    assert.notEqual(mutated.identity_sha256, swiftReceipt.writer_executable_identity_sha256);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-15 physical identity preserves every BigInt field without Number conversion', () => {
  const observed = {
    uid: 4_294_967_293n, gid: 4_294_967_291n, mode: 0o100555n, nlink: 65_533n,
    size: 9_007_199_254_740_993n, mtimeNs: 1_788_176_481_711_164_293n,
    dev: 9_007_199_254_740_997n, ino: 9_007_199_254_741_001n,
  };
  const expected = subject().sha256(Buffer.from([
    `uid=${observed.uid}`, `gid=${observed.gid}`, `mode=${observed.mode & 0o777n}`,
    `nlink=${observed.nlink}`, `size=${observed.size}`, `mtime=${observed.mtimeNs}`,
    `dev=${observed.dev}`, `ino=${observed.ino}`,
  ].join(';')));
  assert.equal(subject().physicalIdentityFromBigIntStat(observed).identity_sha256, expected);
  for (const field of ['uid', 'gid', 'mode', 'nlink', 'size', 'mtimeNs', 'dev', 'ino']) {
    const mutated = { ...observed, [field]: observed[field] + 1n };
    assert.notEqual(subject().physicalIdentityFromBigIntStat(mutated).identity_sha256, expected, field);
  }
});

test('round-16 local promotion rejects adjacent exact BigInt directory identities that Number collapses', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round16-promotion-'));
  try {
    const stagingRoot = path.join(root, '.staging');
    const finalRoot = path.join(root, 'published');
    await mkdir(stagingRoot, { mode: 0o700 });
    for (const name of ['mobile-staging-config.json', 'synthetic-patient.credentials.json', 'local-bridge.receipt.json']) {
      await writeFile(path.join(stagingRoot, name), `${name}\n`, { mode: 0o600 });
    }
    const exactA = 9_007_199_254_740_992n;
    const exactB = exactA + 1n;
    const legacyEqual = Number(exactA) === Number(exactB);
    assert.equal(legacyEqual, true, 'promotionDevInoEqual=true');
    const withIdentity = (observed, dev, ino) => new Proxy(observed, {
      get(target, property) {
        if (property === 'dev') return dev;
        if (property === 'ino') return ino;
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    const exactLstat = async (candidate, options) => {
      assert.deepEqual(options, { bigint: true });
      const observed = await lstat(candidate, options);
      if (candidate === root) return withIdentity(observed, exactA, observed.ino);
      if (candidate === stagingRoot) return withIdentity(observed, exactA, exactA);
      if (candidate === finalRoot) return withIdentity(observed, exactB, exactB);
      return observed;
    };
    await assert.rejects(subject().promoteDirectoryNoReplace({
      stagingRoot, finalRoot, lstatFn: exactLstat,
      exclusiveRename: ({ source, destination }) => rename(source, destination),
    }), (error) => error?.code === 'LOCAL_PUBLICATION_RACE',
    `promotionDevInoEqual=${legacyEqual} exactA=${exactA} exactB=${exactB}`);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-16 simulator observer hashes adjacent exact BigInt identities differently', async () => {
  const exactA = 9_007_199_254_740_992n;
  const exactB = exactA + 1n;
  const base = {
    uid: 501n, gid: 20n, mode: 0o40700n, nlink: 2n, size: 96n,
    mtimeNs: 1_788_176_481_711_164_293n,
  };
  const legacyHash = (exact) => subject().sha256(subject().canonicalJson({
    dev: String(Number(exact)), ino: String(Number(exact)), mode: Number(base.mode & 0o777n),
  }));
  const simulatorHashEqual = legacyHash(exactA) === legacyHash(exactB);
  assert.equal(simulatorHashEqual, true, 'simulatorHashEqual=true');
  assert.equal(typeof subject().observeSimulatorContainerIdentity, 'function',
    `simulatorHashEqual=${simulatorHashEqual} exactA=${exactA} exactB=${exactB}`);
  const observe = async (exact, expectedPath) => subject().observeSimulatorContainerIdentity(expectedPath, {
    lstatFn: async (candidate, options) => {
      assert.equal(candidate, expectedPath);
      assert.deepEqual(options, { bigint: true });
      return {
        ...base, dev: exact, ino: exact,
        isDirectory: () => true, isSymbolicLink: () => false,
      };
    },
  });
  const first = await observe(exactA, '/synthetic/round16/container-a');
  const second = await observe(exactB, '/synthetic/round16/container-b');
  const expectedFirst = subject().sha256(Buffer.from([
    `uid=${base.uid}`, `gid=${base.gid}`, `mode=${base.mode & 0o777n}`,
    `nlink=${base.nlink}`, `size=${base.size}`, `mtime=${base.mtimeNs}`,
    `dev=${exactA}`, `ino=${exactA}`,
  ].join(';')));
  assert.equal(first.identity_sha256, expectedFirst);
  assert.notEqual(first.identity_sha256, second.identity_sha256);
});

test('round-9 terminal emission uses the already scanned retained bytes across a pathname swap', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round9-retained-output-'));
  try {
    const outputPath = path.join(root, 'controller.final-output');
    const displacedPath = path.join(root, 'controller.scanned-output');
    const clean = Buffer.from('CONTROLLER RESUME TERMINAL_PASS state=TERMINAL_PASS raw_values=false\n');
    await writeFile(outputPath, clean, { mode: 0o600 });
    const emitted = [];
    const result = await subject().emitRetainedScannedTerminalBytes({
      filePath: outputPath,
      expectedSha256: subject().sha256(clean),
      emit: async (bytes) => emitted.push(Buffer.from(bytes)),
      scheduler: {
        afterScan: async () => {
          await rename(outputPath, displacedPath);
          await writeFile(outputPath, 'token=unscanned-replacement\n', { mode: 0o600 });
        },
      },
    });
    assert.deepEqual(Buffer.concat(emitted), clean);
    assert.equal(result.sha256, subject().sha256(clean));
    assert.match(await readFile(outputPath, 'utf8'), /unscanned-replacement/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-9 terminal journal frame contains the actual reversible bytes and rejects a dirty late object', async () => {
  const context = baseContext();
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round9-journal-frame-'));
  const generationRoot = path.join(root, context.authority.commit, context.generations.controller);
  const eventRoot = path.join(generationRoot, 'events');
  const destinationPath = path.join(root, 'controller-durable-state-root.json');
  try {
    await mkdir(eventRoot, { recursive: true, mode: 0o700 });
    const completeBytes = Buffer.from('{"event":"COMPLETE","state":"COMPLETE"}\n');
    await writeFile(path.join(eventRoot, 'COMPLETE.json'), completeBytes, { mode: 0o600 });
    const observed = await subject().materializeActualJournalFrame({ generationRoot, destinationPath, context });
    assert.ok(observed.frame.includes(completeBytes));
    assert.equal(observed.receipt.object_count, 1);
    assert.equal(observed.receipt.objects[0].sha256, subject().sha256(completeBytes));
    assert.equal(Buffer.from(observed.receipt.frame_base64, 'base64').equals(observed.frame), true);

    await writeFile(path.join(eventRoot, 'LATE.json'), 'token=late-unscanned-value\n', { mode: 0o600 });
    await rejectCode('TERMINAL_JOURNAL_FRAME', () => subject().materializeActualJournalFrame({
      generationRoot, destinationPath: path.join(root, 'dirty-frame.json'), context,
    }));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-9 Publisher 1 adapter builds only the fixed descriptor transaction and has no pathname installer', async () => {
  const context = baseContext();
  const receiverManifestSha256 = digest('9');
  const receiverRoot = `/private/var/tmp/agentempp-ci3-publisher1/${context.authority.commit}/receiver/`
    + `${context.generations.remote}/${context.generations.controller}/${receiverManifestSha256}`;
  const installation = subject().buildPublisherInstallationContract({
    authoritySha: context.authority.commit,
    controllerGenerationId: context.generations.controller,
  });
  const shaByRole = Object.fromEntries(Object.keys(installation.targets).map(
    (role, index) => [role, digest(String((index % 9) + 1))],
  ));
  const sourceObservationsByRole = Object.fromEntries(Object.keys(installation.targets).map(
    (role, index) => [role, {
      role, path: `${receiverRoot}/${role}.payload`,
      path_sha256: subject().sha256(Buffer.from(`${receiverRoot}/${role}.payload`)),
      sha256: shaByRole[role], uid: 501, gid: 20, mode: 0o600, nlink: 1,
      size: 100 + index, mtime_ns: String(200 + index), dev: '300', ino: String(400 + index),
      identity_sha256: subject().sha256(Buffer.from(
        `uid=501;gid=20;mode=384;nlink=1;size=${100 + index};mtime=${200 + index};dev=300;ino=${400 + index}`,
      )),
    }],
  ));
  const request = subject().buildPublisher1TransactionRequest({
    context, receiverRoot, receiverManifestSha256, shaByRole, sourceObservationsByRole,
  });
  assert.equal(request.purpose, 'CI3_PUBLISHER1_DESCRIPTOR_TRANSACTION_V1');
  assert.equal(request.entries.length, 16);
  assert.deepEqual(request.entries.map(({ role }) => role), Object.keys(installation.targets));
  assert.equal(request.entries[0].source_path, `${receiverRoot}/node-runtime.payload`);
  assert.equal(request.entries[0].source_uid, 501);
  assert.equal(request.entries[0].source_mode, 0o600);
  assert.equal(request.entries[0].source_identity_sha256, sourceObservationsByRole['node-runtime'].identity_sha256);
  assert.equal(request.destination_parent, '/Library/Application Support/Agentempp/ci3-controller-authority');
  assert.equal(request.state_root, `/Library/Application Support/Agentempp/ci3-publisher1-state/`
    + `${context.authority.commit}/${context.generations.controller}`);

  const controllerSource = await readFile(new URL('./ci3-bridge-controller.mjs', import.meta.url), 'utf8');
  const publisherSource = controllerSource.slice(
    controllerSource.indexOf('export async function createOperationAuthorityPublisher'),
    controllerSource.indexOf('\nfunction syntheticContext()', controllerSource.indexOf('export async function createOperationAuthorityPublisher')),
  );
  assert.doesNotMatch(publisherSource, /\/usr\/bin\/install|readRootImmutableFile\(targetPath/);
  assert.match(publisherSource, /--publisher1-transaction/);
});

test('round-10 terminalization seals COMPLETE once before one privileged writer and performs no normal write afterwards', async () => {
  const fixture = operationalSyntheticFixture();
  const trace = [];
  const originalAppend = fixture.journal.append;
  fixture.journal.append = async (record) => {
    trace.push(`journal:${record.event ?? record.phase ?? record.purpose}`);
    return originalAppend(record);
  };
  fixture.adapters.finalizeTerminalEvidence = async () => { trace.push('journal:sealed'); };
  fixture.adapters.invokeWriter = async () => {
    trace.push('privileged:writer');
    return {
      pre_anchor_sha256: digest('6'),
      settlement: subject().buildTerminalSettlementReceipt({
        authoritySha: fixture.context.authority.commit,
        generations: fixture.context.generations,
        preAnchorSha256: digest('6'),
        invokeWriter: { claim_sha256: digest('1'), receipt_sha256: digest('2'), result_sha256: digest('3') },
        verifyAnchor: { claim_sha256: digest('4'), receipt_sha256: digest('5'), result_sha256: digest('6') },
        settlementAuthoritySha256: digest('b'),
        terminalSettlementContractsSha256: digest('c'),
        terminalPhaseGraphSha256: digest('d'),
        terminalFinalScanSha256: digest('e'),
      }),
      complete_sha256: digest('7'),
      marker_sha256: digest('9'), marker_verified: true,
      terminal_state: 'TERMINAL_PASS',
    };
  };
  fixture.adapters.verifyAnchor = async () => { trace.push('normal:verify-after-writer'); return { verified: true }; };
  fixture.adapters.settleTerminal = async () => { trace.push('normal:settle-after-writer'); return null; };

  const outcome = await subject().runProtocol({
    adapters: fixture.adapters, context: fixture.context, journal: fixture.journal,
  });
  assert.equal(outcome.state, 'COMPLETE');
  assert.equal(trace.filter((entry) => entry === 'journal:sealed').length, 1);
  assert.equal(trace.filter((entry) => entry === 'privileged:writer').length, 1);
  assert.ok(trace.indexOf('journal:COMPLETE') < trace.indexOf('journal:sealed'));
  assert.ok(trace.indexOf('journal:sealed') < trace.indexOf('privileged:writer'));
  assert.deepEqual(trace.slice(trace.indexOf('privileged:writer') + 1), []);
});

test('round-10 Publisher 1 controller restart reobserves a settled root transaction without a second admin child', async () => {
  const expected = {
    authority_sha: oid('a'), controller_generation_id: generation('controller', 'b'),
    request_sha256: digest('1'), receiver_root_sha256: digest('2'),
  };
  let settled = null;
  let adminChildren = 0;
  let normalReceipts = 0;
  const observe = async () => settled ?? { state: 'ABSENT' };
  const invokeAdmin = async () => {
    adminChildren += 1;
    settled = {
      state: 'SETTLED', ...expected, claim_sha256: digest('3'), result_sha256: digest('4'),
      tree_verified: true, raw_values: false,
    };
  };
  await assert.rejects(subject().runPublisher1ControllerTransaction({
    expected, observe, invokeAdmin,
    afterAdmin: async () => { throw new Error('SYNTHETIC_PARENT_CRASH'); },
    persistReceipt: async () => { normalReceipts += 1; },
  }), /SYNTHETIC_PARENT_CRASH/);
  const recovered = await subject().runPublisher1ControllerTransaction({
    expected, observe, invokeAdmin,
    persistReceipt: async () => { normalReceipts += 1; },
  });
  assert.deepEqual(recovered, { status: 'EXISTS_RECOVERED', raw_values: false });
  assert.equal(adminChildren, 1);
  assert.equal(normalReceipts, 1);
});

test('round-10 Publisher 1 materializer authority binds the exact request and receiver roots, not a suffix collision', () => {
  const receiverLeaves = Array.from({ length: 16 }, (_, index) => ({
    role: `role-${index}`, path_sha256: digest(String((index % 9) + 1)),
    sha256: digest(String(((index + 1) % 9) + 1)), uid: 501, gid: 20,
    mode: 0o600, nlink: 1, size: 100 + index, mtime_ns: String(200 + index),
    dev: '300', ino: String(400 + index), identity_sha256: subject().sha256(Buffer.from(
      `uid=501;gid=20;mode=384;nlink=1;size=${100 + index};mtime=${200 + index};dev=300;ino=${400 + index}`,
    )),
  }));
  const expected = {
    authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b'),
    requestPath: '/private/var/fixed.invalid/ci3/publisher1.request.json',
    requestSha256: digest('1'), requestIdentitySha256: digest('2'),
    requestUid: 501, requestGid: 20,
    receiverRoot: '/private/var/fixed.invalid/ci3/receiver/root',
    receiverRootIdentitySha256: digest('3'),
    receiverLeaves,
  };
  const authority = {
    schema_version: 2, purpose: 'CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2',
    authority_sha: expected.authoritySha,
    controller_generation_id: expected.controllerGenerationId,
    request_path_sha256: subject().sha256(Buffer.from(expected.requestPath)),
    request_sha256: expected.requestSha256,
    request_identity_sha256: expected.requestIdentitySha256,
    request_uid: expected.requestUid, request_gid: expected.requestGid,
    request_mode: 0o600, request_nlink: 1,
    receiver_root_path_sha256: subject().sha256(Buffer.from(expected.receiverRoot)),
    receiver_root_identity_sha256: expected.receiverRootIdentitySha256,
    receiver_leaves: structuredClone(receiverLeaves),
    normal_executor_authorized: false, raw_values: false,
  };
  assert.equal(subject().validatePublisher1MaterializerAuthorityBinding(authority, expected), true);
  const collision = structuredClone(authority);
  collision.receiver_root_path_sha256 = subject().sha256(Buffer.from(`/alternate${expected.receiverRoot}`));
  expectCode('STOP_PRE_AUTHORITY', () => subject().validatePublisher1MaterializerAuthorityBinding(collision, expected));
});

test('round-11 Publisher 1 authority rejects every physical receiver-leaf drift before privilege', () => {
  const receiverLeaves = Array.from({ length: 16 }, (_, index) => ({
    role: `role-${index}`, path_sha256: digest(String((index % 9) + 1)),
    sha256: digest(String(((index + 1) % 9) + 1)), uid: 501, gid: 20,
    mode: 0o600, nlink: 1, size: 100 + index, mtime_ns: String(200 + index),
    dev: '300', ino: String(400 + index), identity_sha256: subject().sha256(Buffer.from(
      `uid=501;gid=20;mode=384;nlink=1;size=${100 + index};mtime=${200 + index};dev=300;ino=${400 + index}`,
    )),
  }));
  const expected = {
    authoritySha: oid('a'), controllerGenerationId: generation('controller', 'b'),
    requestPath: '/private/var/fixed.invalid/ci3/publisher1.request.json',
    requestSha256: digest('1'), requestIdentitySha256: digest('2'), requestUid: 501, requestGid: 20,
    receiverRoot: '/private/var/fixed.invalid/ci3/receiver/root', receiverRootIdentitySha256: digest('3'),
    receiverLeaves,
  };
  const authority = {
    schema_version: 2, purpose: 'CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2',
    authority_sha: expected.authoritySha, controller_generation_id: expected.controllerGenerationId,
    request_path_sha256: subject().sha256(Buffer.from(expected.requestPath)),
    request_sha256: expected.requestSha256, request_identity_sha256: expected.requestIdentitySha256,
    request_uid: 501, request_gid: 20, request_mode: 0o600, request_nlink: 1,
    receiver_root_path_sha256: subject().sha256(Buffer.from(expected.receiverRoot)),
    receiver_root_identity_sha256: expected.receiverRootIdentitySha256,
    receiver_leaves: structuredClone(receiverLeaves), normal_executor_authorized: false, raw_values: false,
  };
  assert.equal(subject().validatePublisher1MaterializerAuthorityBinding(authority, expected), true);
  for (const [field, value] of [
    ['role', 'wrong-role'], ['path_sha256', digest('f')], ['sha256', digest('e')],
    ['uid', 502], ['gid', 21], ['mode', 0o644], ['nlink', 2], ['size', 999],
    ['mtime_ns', '999'], ['dev', '999'], ['ino', '999'], ['identity_sha256', digest('d')],
  ]) {
    const drifted = structuredClone(authority);
    drifted.receiver_leaves[7][field] = value;
    expectCode('STOP_PRE_AUTHORITY', () => subject().validatePublisher1MaterializerAuthorityBinding(drifted, expected));
  }
});

test('round-11 protocol refuses internal terminal PASS without the exact privileged marker proof', async () => {
  const fixture = operationalSyntheticFixture();
  const originalWriter = fixture.adapters.invokeWriter;
  fixture.adapters.invokeWriter = async (...args) => {
    const writer = await originalWriter(...args);
    delete writer.marker_sha256;
    delete writer.marker_verified;
    return writer;
  };
  await rejectCode('TERMINAL_TAIL_AUTHORITY', () => subject().runProtocol({
    adapters: fixture.adapters, context: fixture.context, journal: fixture.journal,
  }));
});

test('round-11 controller crash waits for one transient authorized supervisor and settles only after marker', async () => {
  let state = 'RECOVERABLE';
  let recoveryCalls = 0;
  let effectExecutions = 1;
  let adminPrompts = 1;
  const markerSha256 = digest('a');
  const result = await subject().runPrivilegedTerminalRecovery({
    recovery: true,
    observe: async () => state === 'SETTLED'
      ? { state, marker_sha256: markerSha256, marker_verified: true, terminal_state: 'TERMINAL_PASS' }
      : { state, marker_verified: false, terminal_state: 'PRE_TERMINAL_UNPUBLISHED' },
    waitForAuthorizedSupervisor: async ({ recovery }) => {
      assert.equal(recovery, true);
      recoveryCalls += 1;
      state = 'SETTLED';
      return { effect_executions: 0, admin_prompts: 0 };
    },
  });
  effectExecutions += result.effect_executions;
  adminPrompts += result.admin_prompts;
  assert.equal(recoveryCalls, 1);
  assert.equal(effectExecutions, 1);
  assert.equal(adminPrompts, 1);
  assert.equal(result.marker_sha256, markerSha256);
  assert.equal(result.marker_verified, true);
  assert.equal(result.terminal_state, 'TERMINAL_PASS');
});

test('round-11 resume reports terminal PASS only after terminalStatus validates the privileged marker', async () => {
  const fixture = operationalSyntheticFixture();
  fixture.journal.terminalStatus = async () => ({
    state: 'TERMINAL_PASS', raw_values: false,
  });
  const result = await subject().dispatchControllerMode({ mode: 'resume', ...fixture });
  assert.deepEqual(result, { mode: 'resume', state: 'TERMINAL_PASS', raw_values: false });
});

test('round-11 controller recovery stops pre-authority when the one root supervisor died without a marker', async () => {
  await rejectCode('STOP_PRE_AUTHORITY', () => subject().runPrivilegedTerminalRecovery({
    recovery: true,
    observe: async () => ({
      state: 'RECOVERABLE', marker_verified: false,
      terminal_state: 'PRE_TERMINAL_UNPUBLISHED',
    }),
    waitForAuthorizedSupervisor: async () => ({ effect_executions: 0, admin_prompts: 0 }),
  }));
});
