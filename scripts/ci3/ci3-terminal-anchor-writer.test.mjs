import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, sign as ed25519Sign } from 'node:crypto';
import { chmod, link, lstat, mkdtemp, mkdir, readFile, readdir, realpath, rename, rm, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import nodeTest from 'node:test';

const FIXTURE_HELPER_MODE = process.argv[2] === '--materialize-synthetic-fixture';
const VPS_SOURCE_CONTRACT_MODE = process.platform !== 'darwin' && !FIXTURE_HELPER_MODE;
const test = FIXTURE_HELPER_MODE || VPS_SOURCE_CONTRACT_MODE
  ? Object.assign(() => undefined, { after: () => undefined })
  : nodeTest;

const SOURCE_PATH = new URL('./ci3-terminal-anchor-writer.swift', import.meta.url).pathname;
const SCAN_IDS = Object.freeze(['argv', 'history', 'terminal-log', 'attachment', 'xcresult', 'runtime']);
const FINDING_IDS = Object.freeze([
  'RA1-I-5', 'A4-I-1', 'A4-I-3', 'A5-I-1', 'A5-I-2',
  'RA0-I-4', 'RA0-I-7', 'R2-I-2', 'R5-I-1', 'R5-I-2', 'R5-I-3',
  ...Array.from({ length: 6 }, (_, index) => `RA-FINAL-I-${index + 1}`),
  ...Array.from({ length: 7 }, (_, index) => `RB-FINAL-I-${index + 1}`),
]);
const AUTHORITY = 'a'.repeat(40);
const WRITER_INVOCATION_TIMEOUT_MS = 60000;
const GENERATIONS = Object.freeze({
  remote: `remote-${'b'.repeat(64)}`,
  controller: `controller-${'c'.repeat(64)}`,
  simulator: `simulator-${'d'.repeat(64)}`,
  terminal: `terminal-${'e'.repeat(64)}`,
});
const REMOTE_PATHS = Object.freeze({
  receipt: '/srv/ci3.invalid/generation/bridge.receipt.json',
  config: '/srv/ci3.invalid/generation/mobile-staging-config.json',
  credential: '/srv/ci3.invalid/generation/synthetic-patient.credentials.json',
});
const VPS_ISSUER_KEYPAIR = generateKeyPairSync('ed25519');
const VPS_ISSUER_PUBLIC_KEY_BYTES = Buffer.from(
  VPS_ISSUER_KEYPAIR.publicKey.export({ format: 'jwk' }).x,
  'base64url',
);
const SSH_KEYPAIR = generateKeyPairSync('ed25519');
const SSH_RAW_PUBLIC_KEY = Buffer.from(SSH_KEYPAIR.publicKey.export({ format: 'jwk' }).x, 'base64url');
const sshWireField = (bytes) => {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(bytes.length);
  return Buffer.concat([length, bytes]);
};
const SSH_PUBLIC_KEY_WIRE = Buffer.concat([sshWireField(Buffer.from('ssh-ed25519')), sshWireField(SSH_RAW_PUBLIC_KEY)]);
const SSH_PUBLIC_KEY_BYTES = Buffer.from(`ssh-ed25519 ${SSH_PUBLIC_KEY_WIRE.toString('base64')} ci3.invalid\n`);
const SSH_FINGERPRINT_BYTES = Buffer.from(`256 SHA256:${createHash('sha256').update(SSH_PUBLIC_KEY_WIRE).digest('base64').replace(/=+$/, '')} ci3.invalid (ED25519)\n`);

function sha(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function jsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

async function physicalMetadata(filePath) {
  const observed = await lstat(filePath, { bigint: true });
  return {
    uid: Number(observed.uid),
    gid: Number(observed.gid),
    mode: Number(observed.mode & 0o777n),
    nlink: Number(observed.nlink),
    size: Number(observed.size),
    mtime_ns: String(observed.mtimeNs),
    dev: String(observed.dev),
    ino: String(observed.ino),
  };
}

async function physicalIdentitySha256(filePath) {
  const observed = await physicalMetadata(filePath);
  return sha(Buffer.from([
    `uid=${observed.uid}`, `gid=${observed.gid}`, `mode=${observed.mode}`,
    `nlink=${observed.nlink}`, `size=${observed.size}`, `mtime=${observed.mtime_ns}`,
    `dev=${observed.dev}`, `ino=${observed.ino}`,
  ].join(';')));
}

let buildRoot;
let binaryPath;
let binarySha256;
let sourceSha256;
let setupError;

try {
  sourceSha256 = sha(await readFile(SOURCE_PATH));
  if (FIXTURE_HELPER_MODE) {
    binaryPath = process.env.CI3_SYNTHETIC_WRITER_BINARY;
    if (!path.isAbsolute(binaryPath ?? '')) throw new Error('WRITER_BINARY_REQUIRED');
    binarySha256 = sha(await readFile(binaryPath));
    if (binarySha256 !== process.env.CI3_SYNTHETIC_WRITER_SHA256) throw new Error('WRITER_BINARY_HASH');
  } else if (!VPS_SOURCE_CONTRACT_MODE) {
    buildRoot = await mkdtemp(path.join(tmpdir(), 'ci3-writer-build-'));
    binaryPath = path.join(buildRoot, 'ci3-terminal-anchor-writer-test');
    const compilation = spawnSync('/usr/bin/xcrun', [
      'swiftc', '-parse-as-library', '-D', 'CI3_SYNTHETIC_TEST', SOURCE_PATH, '-o', binaryPath,
    ], {
      encoding: 'utf8',
      env: { PATH: '/usr/bin:/bin' },
      timeout: 120000,
    });
    if (compilation.status !== 0) throw new Error(`SWIFTC_FAILED:${compilation.stderr}`);
    binarySha256 = sha(await readFile(binaryPath));
  }
} catch (error) {
  setupError = error;
}

if (VPS_SOURCE_CONTRACT_MODE) {
  const writerSourceContract = await readFile(SOURCE_PATH, 'utf8');
  nodeTest('[VPS source-contract] writer requires the V2 bounded-reader remote receipt', () => {
    assert.match(writerSourceContract, /VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING/);
    assert.doesNotMatch(writerSourceContract, /VERSIONED_REMOTE_BRIDGE_ARTIFACT_V1/);
  });
  nodeTest('[VPS source-contract] writer requires the Mac-only zsh pre-network gate', () => {
    for (const literal of [
      'launcher_target_environment', 'launcher_runtime_path', 'zsh_syntax_validation_deferred',
      'zsh_syntax_validation_required_environment', 'zsh_syntax_validation_required_before_network',
      'zsh_syntax_validation_status', 'not_executed_on_vps', 'mac_local', '/bin/zsh',
    ]) assert.match(writerSourceContract, new RegExp(literal.replace('/', '\\/')));
  });
  nodeTest('[VPS source-contract] writer requires equal structural skeleton digests', () => {
    assert.match(writerSourceContract, /predecessor_launcher_structural_skeleton_sha256/);
    assert.match(writerSourceContract, /current_launcher_structural_skeleton_sha256/);
    assert.match(writerSourceContract, /launcher_structural_skeleton_equal/);
    assert.match(writerSourceContract, /string\(remoteReceipt\["predecessor_launcher_structural_skeleton_sha256"\].*== string\(remoteReceipt\["current_launcher_structural_skeleton_sha256"\]/s);
  });
  nodeTest('[VPS source-contract] Swift compilation is deferred to the Mac', () => {
    assert.equal(process.platform === 'darwin', false);
    assert.equal(setupError, undefined);
    assert.equal(buildRoot, undefined);
  });
}

function requireBuild() {
  assert.ifError(setupError);
  return binaryPath;
}

test.after(async () => {
  if (buildRoot) await rm(buildRoot, { recursive: true, force: true });
});

function components() {
  return {
    generator: { path: 'scripts/ci3/create-ios-staging-bridge-config.mjs', blob_oid: '1'.repeat(40), sha256: '1'.repeat(64) },
    controller: { path: 'scripts/ci3/ci3-bridge-controller.mjs', blob_oid: '2'.repeat(40), sha256: '2'.repeat(64) },
    launcher: { path: 'scripts/ci3/ci3-bridge-launcher.zsh', blob_oid: '3'.repeat(40), sha256: '3'.repeat(64) },
    writer: { path: 'scripts/ci3/ci3-terminal-anchor-writer.swift', blob_oid: '4'.repeat(40), sha256: sourceSha256 },
  };
}

const EVIDENCE_ROLES = Object.freeze([
  'authority-manifest', 'launch-attestation', 'bootstrap-claim', 'receipt-read-claim', 'receipt-read-result',
  'config-read-claim', 'config-read-result', 'credential-read-claim', 'credential-read-result',
  'remote-receipt', 'local-receipt', 'ssh-provenance', 'simulator-gate',
  'simulator-install', 'input-manifest', 'terminal-receipt', 'controller-durable-state-root', 'writer-source',
  'operation-authority-root', 'vps-pass-root', 'vps-issuer-authority-root',
  'human-authorization-root', 'publisher-input-manifest-root',
  'ssh-trust-descriptor', 'ssh-public-key', 'ssh-public-key-fingerprint',
  ...['SELECT_DEVICE', 'RESOLVE_CONTAINER', 'INSTALL_PROBE', 'LAUNCH_PROBE', 'ACK_PROBE', 'REMOVE_PROBE', 'REOBSERVE']
    .flatMap((phase) => ['claim', 'receipt', 'result'].map((kind) => `simulator-phase-${phase.toLowerCase().replaceAll('_', '-')}-${kind}`)),
  ...['VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH', 'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS']
    .flatMap((phase) => ['claim', 'receipt', 'result'].map((kind) => `controller-phase-${phase.toLowerCase().replaceAll('_', '-')}-${kind}`)),
]);

const AUTHORITY_PATHS = Object.freeze([
  'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md',
  'docs/superpowers/evidence/2026-08-29-ci3-bridge-v3-review-stop.md',
  'docs/superpowers/evidence/2026-08-31-ci3-bridge-git-blob-reader-stop-and-authority.md',
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
]);

function compactJsonBytes(value) {
  const normalize = (candidate) => Array.isArray(candidate)
    ? candidate.map(normalize)
    : candidate && typeof candidate === 'object'
      ? Object.fromEntries(Object.keys(candidate).sort().map((key) => [key, normalize(candidate[key])]))
      : candidate;
  return Buffer.from(`${JSON.stringify(normalize(value))}\n`);
}

function vpsPassSigningPayload(pass) {
  const payload = structuredClone(pass);
  delete payload.signed_payload_sha256;
  delete payload.signature_base64;
  return compactJsonBytes(payload);
}

function observationHash(bytes, metadata) {
  return sha(Buffer.from([
    `bytes=${sha(bytes)}`, `uid=${metadata.uid}`, `gid=${metadata.gid}`, `mode=${metadata.mode & 0o777}`,
    `nlink=${metadata.nlink}`, `size=${metadata.size}`, `mtime=${metadata.mtime_ns}`,
    `dev=${metadata.dev}`, `ino=${metadata.ino}`,
  ].join(';')));
}

function simulatorObservation(phase) {
  if (phase === 'SELECT_DEVICE') return { device_selection_sha256: '1'.repeat(64) };
  if (phase === 'RESOLVE_CONTAINER') return {
    runtime_sha256: '2'.repeat(64), app_installation_sha256: '3'.repeat(64), container_identity_sha256: '5'.repeat(64),
  };
  if (phase === 'INSTALL_PROBE') return { config_sha256: '3'.repeat(64), credential_sha256: '4'.repeat(64) };
  if (phase === 'LAUNCH_PROBE') return {
    launch_contract_sha256: sha(compactJsonBytes({ bundle: 'com.bodyflow.app', device: '1'.repeat(64) })),
  };
  if (phase === 'ACK_PROBE') return { probe_ack_sha256: '8'.repeat(64) };
  if (phase === 'REMOVE_PROBE') return { credential_absent: true, controller_files_removed: true };
  if (phase === 'REOBSERVE') return { config_absent: true, credential_absent: true, ack_absent: true };
  throw new Error(`UNKNOWN_SIMULATOR_PHASE:${phase}`);
}

function fixtureScanContracts() {
  const formats = ['jsonl', 'utf8-lines', 'jsonl', 'jsonl', 'json', 'jsonl'];
  const sourceRoles = [
    'controller-invocation-argv', 'controller-command-history', 'controller-terminal-transcript',
    'controller-evidence-attachments', 'simulator-test-result', 'controller-runtime-environment',
  ];
  const schemaHashes = [
    '45069ac37d719f58b9953aa652edad500e5783de69f1fd78c6338da3e3af9d40',
    'b1c4486ac592208f7500b353c5c83474e6a3150f4c4f85a609f233042402891f',
    '9b881b1b9e5443514a2f7825a9ec7f9a29eb5964d9ad974b2a845bee8e6b08ac',
    '6c64c69fe646bc5b08f8e65d249077b0f4eb781b58ddf1bb3d7f64e6337a78cb',
    'bb8f030b96679ac38caffadd971e259a265170c0748d7ddf94e8b317833da944',
    '53aa749f147360e7e77312ac012c7f595b773ed2248cb12d7165fa729706477a',
  ];
  return SCAN_IDS.map((id, index) => ({
    id, collector_version: `ci3-${id}-collector-v1`, format: formats[index], source_role: sourceRoles[index],
    tool_sha256: components().controller.sha256, contract_sha256: schemaHashes[index],
  }));
}

async function createFixture({
  mutateManifest, mutateClaim, mutateEvidence, mutateOperationAuthority, mutateScanSurface,
  mutatePhaseTargets, rootParent, protocolStatePath, scenarioId = 'STANDALONE_FIXTURE', scenarioSha256,
} = {}) {
  requireBuild();
  const root = await mkdtemp(path.join(rootParent ?? tmpdir(), 'ci3-writer-fixture-'));
  const evidenceRoot = path.join(root, 'evidence');
  const anchorRoot = path.join(root, 'anchors');
  await mkdir(evidenceRoot, { recursive: true, mode: 0o700 });
  await mkdir(anchorRoot, { recursive: true, mode: 0o700 });
  const privilegedGenerationRoot = path.join(anchorRoot, AUTHORITY, GENERATIONS.terminal);
  await mkdir(privilegedGenerationRoot, { recursive: true, mode: 0o700 });
  const authorityReceiptPath = path.join(privilegedGenerationRoot, 'privileged-authority.receipt.json');
  const authorityEntries = AUTHORITY_PATHS.map((entryPath, index) => {
    const component = Object.values(components()).find(({ path: componentPath }) => componentPath === entryPath);
    return {
      path: entryPath,
      blob_oid: component?.blob_oid ?? String((index % 9) + 1).repeat(40),
      sha256: component?.sha256 ?? String((index % 9) + 1).repeat(64),
    };
  });
  const authorityManifestSourceSha256 = sha(Buffer.from(
    authorityEntries.map((entry) => `${entry.path} ${entry.blob_oid} ${entry.sha256}\n`).join(''),
  ));

  const evidence = [];
  const evidencePayloads = new Map();
  const readClaimByKind = new Map();
  const simulatorReceiptHashes = [];
  let simulatorPredecessor = '0'.repeat(64);
  const simulatorPhaseClaims = new Map();
  const simulatorPhaseReceipts = new Map();
  const controllerPhaseClaims = new Map();
  const controllerPhaseReceipts = new Map();
  for (const role of EVIDENCE_ROLES) {
    const evidencePath = path.join(evidenceRoot, `${role}.json`);
    let payload;
    if (role === 'authority-manifest') {
      payload = {
        schema_version: 1, purpose: 'CI3_LITERAL_AUTHORITY_MANIFEST_V1', source_sha256: authorityManifestSourceSha256,
        entries: authorityEntries,
        components: components(), raw_values: false,
      };
    } else if (role === 'launch-attestation') {
      payload = {
        schema_version: 1, purpose: 'CI3_GIT_BOUND_LAUNCH_ATTESTATION_V2', authority_sha: AUTHORITY,
        authority_parent: '9'.repeat(40), authority_tree: 'f'.repeat(40),
        authority_subject_sha256: sha(Buffer.from('build(ops): authorize bounded Git blob reader for CI-3 bridge')), authority_manifest_sha256: authorityManifestSourceSha256,
        components: components(), tools: Object.fromEntries(['node', 'ssh', 'swiftc', 'xcodebuild'].map((name, index) => [name, {
          binary_sha256: String(index + 1).repeat(64), path_sha256: String(index + 2).repeat(64), version_sha256: String(index + 3).repeat(64),
        }])), raw_values: false,
      };
    } else if (role === 'bootstrap-claim') {
      payload = {
        schema_version: 1, purpose: 'CI3_MAC_BRIDGE_BOOTSTRAP_CLAIM_V1', authority_sha: AUTHORITY,
        authority_manifest_sha256: authorityManifestSourceSha256, components: components(),
        remote_bundle_path_sha256: sha(Buffer.from(path.dirname(REMOTE_PATHS.config))),
        remote_receipt_path_sha256: sha(Buffer.from(REMOTE_PATHS.receipt)),
        ssh_executable_sha256: '3'.repeat(64), ssh_code_signature_sha256: '4'.repeat(64),
        ssh_effective_config_sha256: '5'.repeat(64), ssh_trust_descriptor_sha256: '6'.repeat(64),
        simulator_gate_sha256: '7'.repeat(64), controller_generation_id: GENERATIONS.controller,
        remote_generation_id: GENERATIONS.remote, simulator_generation_id: GENERATIONS.simulator,
        terminal_generation_id: GENERATIONS.terminal, attempt: 1, retry: false, raw_values: false,
      };
    } else if (role.endsWith('-read-claim')) {
      const kind = role.split('-')[0];
      const expectedSha256 = kind === 'config' ? '3'.repeat(64) : kind === 'credential' ? '4'.repeat(64) : '2'.repeat(64);
      payload = {
        schema_version: 1, purpose: 'CI3_MAC_BRIDGE_READ_CLAIM_V1', kind,
        bootstrap_claim_sha256: evidence.find(({ role: candidate }) => candidate === 'bootstrap-claim').sha256,
        expected_path_sha256: sha(Buffer.from(REMOTE_PATHS[kind])), expected_sha256: expectedSha256,
        remote_generation_id: kind === 'receipt' ? null : GENERATIONS.remote,
        ssh_executable_sha256: '3'.repeat(64), ssh_effective_config_sha256: '5'.repeat(64),
        ssh_trust_descriptor_sha256: '6'.repeat(64), attempt: 1, retry: false, raw_values: false,
      };
      readClaimByKind.set(kind, jsonBytes(payload));
    } else if (role.endsWith('-read-result')) {
      const kind = role.split('-')[0];
      const captureSha256 = kind === 'config' ? '3'.repeat(64) : kind === 'credential' ? '4'.repeat(64) : '2'.repeat(64);
      payload = {
        schema_version: 1, purpose: 'CI3_MAC_BRIDGE_READ_RESULT_V1', kind,
        claim_sha256: sha(readClaimByKind.get(kind)), capture_sha256: captureSha256,
        capture_identity_sha256: '2'.repeat(64),
        remote_command_sha256: sha(Buffer.from(`exec /usr/bin/cat -- ${REMOTE_PATHS[kind]}`)),
        descriptor_read: true, bytes: 64, exit: 0, stderr_class: 'EMPTY',
        started_at: '2026-08-30T12:00:00.000Z', finished_at: '2026-08-30T12:00:01.000Z',
        ssh_effective_config_sha256: '5'.repeat(64), ssh_trust_descriptor_sha256: '6'.repeat(64),
        remote_generation_id: GENERATIONS.remote, raw_values: false,
      };
    } else if (role === 'remote-receipt') {
      payload = {
        schema_version: 1, purpose: 'VERSIONED_REMOTE_BRIDGE_ARTIFACT_V2_BOUNDED_GIT_BLOB_STREAMING', created_at_utc: '2026-08-30T12:00:00.000Z',
        authority_commit: AUTHORITY, authority_parent: '92cccf3dca21a29d601d2f274a67ea2ba284914b', authority_tree: 'f'.repeat(40), authority_subject: 'build(ops): authorize bounded Git blob reader for CI-3 bridge',
        generator_blob_sha: components().generator.blob_oid, generator_file_sha256: components().generator.sha256,
        controller_blob_oid: components().controller.blob_oid, controller_file_sha256: components().controller.sha256,
        launcher_blob_oid: components().launcher.blob_oid, launcher_file_sha256: components().launcher.sha256,
        launcher_target_environment: 'mac_local', launcher_runtime_path: '/bin/zsh',
        zsh_syntax_validation_deferred: true, zsh_syntax_validation_required_environment: 'mac_local',
        zsh_syntax_validation_required_before_network: true, zsh_syntax_validation_status: 'not_executed_on_vps',
        predecessor_launcher_structural_skeleton_sha256: '8'.repeat(64), current_launcher_structural_skeleton_sha256: '8'.repeat(64),
        launcher_structural_skeleton_equal: true,
        anchor_writer_blob_oid: components().writer.blob_oid, anchor_writer_file_sha256: components().writer.sha256,
        authority_tree_manifest_sha256: authorityManifestSourceSha256, remote_bundle_generation_id: GENERATIONS.remote,
        source_generation_id: `src-${'1'.repeat(64)}`, source_env_descriptor_identity_sha256: '2'.repeat(64),
        env_source_sha256: '3'.repeat(64), env_receipt_sha256: '4'.repeat(64), deployment_receipt_sha256: '5'.repeat(64),
        credential_source_path: '/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json', credential_source_sha256: '4'.repeat(64),
        provisioning_receipt_sha256: '7'.repeat(64), output_config_sha256: '3'.repeat(64),
        output_filenames: ['mobile-staging-config.json', 'bridge.receipt.json'], staging_project_ref: 'syntheticref', implementation_sha: 'e3e1e252b48e42554e75899b950692c05186f60d',
        preview_deployment_count: 1, production_deployment_count: 0, env_preview_count: 3, env_production_count: 0, env_development_count: 0,
        sso_state: null, cleanup_deadline: '2099-08-30T12:00:00.000Z', service_role_emitted: false, token_emitted: false,
        raw_values_reported: false, primary_opened: false, remote_bundle_immutable: true, terminal_scan_ids: SCAN_IDS,
      };
    } else if (role === 'local-receipt') {
      payload = {
        schema_version: 1, purpose: 'CI3_LOCAL_BRIDGE_RECEIPT_V1', authority_sha: AUTHORITY,
        components: components(), generations: GENERATIONS,
        bootstrap_claim_sha256: evidence.find(({ role: candidate }) => candidate === 'bootstrap-claim').sha256,
        read_claim_chain_sha256: '1'.repeat(64), read_result_chain_sha256: '2'.repeat(64),
        remote_receipt_sha256: evidence.find(({ role: candidate }) => candidate === 'remote-receipt').sha256,
        config_sha256: '3'.repeat(64), credential_sha256: '4'.repeat(64), simulator_gate_sha256: '5'.repeat(64),
        ssh_provenance_sha256: '6'.repeat(64), terminal_scan_ids: SCAN_IDS,
        terminal_state: 'PENDING_INSTALL_AND_SCANS', raw_values: false,
      };
    } else if (role === 'ssh-provenance') {
      const result = { provenance: {
        executable_sha256: '3'.repeat(64), code_signature_sha256: '4'.repeat(64), effective_config_sha256: '5'.repeat(64),
        config_sha256: 'a'.repeat(64), known_hosts_sha256: 'b'.repeat(64), identity_public_key_sha256: 'c'.repeat(64),
        identity_public_key_fingerprint_sha256: 'd'.repeat(64), host_key_ed25519_sha256: 'e'.repeat(64),
        destination_sha256: 'f'.repeat(64), version_sha256: '1'.repeat(64), trust_descriptor_sha256: '6'.repeat(64),
      } };
      payload = { event: 'VERIFY_SSH', state: 'SSH_VERIFIED', result, result_sha256: sha(compactJsonBytes(result)) };
    } else if (role === 'simulator-gate') {
      const receipt = {
        schema_version: 1, purpose: 'CI3_SIMULATOR_GATE_RECEIPT_V2', authority_sha: AUTHORITY,
        controller_generation_id: GENERATIONS.controller, simulator_generation_id: GENERATIONS.simulator,
        device_selection_sha256: '1'.repeat(64), runtime_sha256: '2'.repeat(64), app_installation_sha256: '3'.repeat(64), source_commit: '277873755bf29771a10b5f362b522c2e6a6c21d6',
        bundle_id: 'com.bodyflow.app', container_identity_sha256: '5'.repeat(64), probe_config_sha256: '3'.repeat(64),
        probe_credential_sha256: '4'.repeat(64), probe_ack_sha256: '8'.repeat(64), removal_proof_sha256: '9'.repeat(64),
        phases: ['SELECT_DEVICE', 'RESOLVE_CONTAINER', 'INSTALL_PROBE', 'LAUNCH_PROBE', 'ACK_PROBE', 'REMOVE_PROBE', 'REOBSERVE'], phase_receipt_hashes: [],
        attempts: { select: 1, resolve: 1, install: 1, launch: 1, ack: 1, remove: 1, reobserve: 1 },
        raw_container_path_reported: false, terminal_state: 'SIMULATOR_GATE_PASS',
      };
      const result = { receipt };
      payload = { event: 'VERIFY_SIMULATOR', state: 'SIMULATOR_VERIFIED', result, result_sha256: sha(compactJsonBytes(result)) };
    } else if (role === 'simulator-install') {
      payload = {
        schema_version: 1, purpose: 'CI3_SIMULATOR_INSTALL_RECEIPT_V1', authority_sha: AUTHORITY,
        controller_generation_id: GENERATIONS.controller, simulator_generation_id: GENERATIONS.simulator,
        local_bundle_sha256: evidence.find(({ role: candidate }) => candidate === 'local-receipt').sha256,
        install_claim_sha256: '1'.repeat(64), install_executable_sha256: '2'.repeat(64),
        files: [
          ['mobile-staging-config.json', '3'.repeat(64)],
          ['synthetic-patient.credentials.json', '4'.repeat(64)],
        ].map(([name, value], index) => ({ name_sha256: sha(Buffer.from(name)), sha256: value, uid: 501, gid: 20, mode: 0o600, nlink: 1, size: 64, dev: String(index + 1), ino: String(index + 3), mtime_ns: String(index + 4) })),
        raw_values: false,
      };
    } else if (role === 'input-manifest') {
      payload = {
        schema_version: 1, purpose: 'CI3_TERMINAL_INPUT_MANIFEST_V1', authority_sha: AUTHORITY,
        controller_generation_id: GENERATIONS.controller, terminal_generation_id: GENERATIONS.terminal,
        local_bundle_sha256: '0'.repeat(64), simulator_install_sha256: '0'.repeat(64),
        read_commands: [], scan_contracts: fixtureScanContracts(), scan_ids: SCAN_IDS, raw_values: false,
      };
    } else if (role === 'terminal-receipt') {
      payload = {
        schema_version: 1, purpose: 'CI3_TERMINAL_PREPARATION_RECEIPT_V1', authority_sha: AUTHORITY,
        controller_generation_id: GENERATIONS.controller, terminal_generation_id: GENERATIONS.terminal,
        scan_receipt_sha256: [], run_scans_result_sha256: '0'.repeat(64),
        terminal_settlement_contracts_sha256: '0'.repeat(64), writer_source_sha256: sourceSha256,
        writer_binary_sha256: binarySha256, writer_signature_sha256: sha(Buffer.from('SYNTHETIC_TEST_BUILD')),
        privileged_authority_path_sha256: sha(Buffer.from(authorityReceiptPath)), normal_executor_authorized: false,
        finished_at: '2026-08-30T12:00:01.000Z', raw_values: false,
      };
    } else if (role === 'controller-durable-state-root') {
      let snapshot;
      let snapshotPath;
      if (protocolStatePath) {
        snapshotPath = protocolStatePath;
        snapshot = JSON.parse(await readFile(protocolStatePath, 'utf8'));
      } else {
        snapshotPath = '/synthetic/standalone-durable-state.json';
        snapshot = {
          records: [], events: [], claims: [], results: [], scenario_trace: [], crash_observed: false,
          phase_claims: [], phase_receipts: [], phase_results: [], phase_produced: [],
          phase_effect_counts: [], phase_paths: [],
        };
      }
      const boundScenarioSha256 = scenarioSha256 ?? sha(Buffer.from(scenarioId));
      payload = {
        schema_version: 1, purpose: 'CI3_SYNTHETIC_DURABLE_PROTOCOL_STATE_V1',
        scenario_id: scenarioId, scenario_sha256: boundScenarioSha256,
        snapshot_path_sha256: sha(Buffer.from(snapshotPath)),
        snapshot_sha256: sha(compactJsonBytes(snapshot)), snapshot, raw_values: false,
      };
    } else if (role === 'operation-authority-root') {
      payload = {
        schema_version: 1, purpose: 'CI3_MAC_OPERATION_AUTHORITY_V1', raw_values: false,
        context: {
          authority: {
            commit: AUTHORITY, parent: '9'.repeat(40), tree: 'f'.repeat(40),
            subject: 'build(ops): authorize bounded Git blob reader for CI-3 bridge', manifest_sha256: '0'.repeat(64),
            components: components(),
          },
          generations: GENERATIONS,
          remote: {
            bundle_path_sha256: sha(Buffer.from(path.dirname(REMOTE_PATHS.config))),
            receipt_path_sha256: sha(Buffer.from(REMOTE_PATHS.receipt)), receipt_sha256: '3'.repeat(64),
            config_path_sha256: sha(Buffer.from(REMOTE_PATHS.config)), config_sha256: '5'.repeat(64),
            credential_path_sha256: sha(Buffer.from(REMOTE_PATHS.credential)), credential_sha256: '7'.repeat(64),
          },
        },
        scans: Object.fromEntries(fixtureScanContracts().map((entry) => [entry.id, entry])),
        ssh: {
          alias: 'ci3-synthetic', code_signature_sha256: '5'.repeat(64),
          config_path: '/synthetic/config', config_sha256: '3'.repeat(64),
          destination_sha256: '1'.repeat(64), effective_config_sha256: '9'.repeat(64),
          executable_path_sha256: '6'.repeat(64), executable_sha256: '7'.repeat(64),
          host_key_ed25519_sha256: '2'.repeat(64), identity_path: '/synthetic/identity',
          identity_public_key_path: '/synthetic/identity.pub', identity_sha256: 'a'.repeat(64),
          known_hosts_path: '/synthetic/known-hosts', known_hosts_sha256: '4'.repeat(64),
          port: 22, trust_descriptor_path: '/synthetic/trust-descriptor.json',
          trust_descriptor_sha256: '0'.repeat(64), version_sha256: '8'.repeat(64),
          identity_public_key_sha256: sha(SSH_PUBLIC_KEY_BYTES),
          identity_public_key_fingerprint_sha256: sha(SSH_FINGERPRINT_BYTES),
        },
        simulator: {}, worktree: {}, remote: {
          receipt_path: REMOTE_PATHS.receipt, config_path: REMOTE_PATHS.config,
          credential_path: REMOTE_PATHS.credential,
        }, writer: {},
      };
    } else if (role === 'vps-issuer-authority-root') {
      payload = {
        schema_version: 1, purpose: 'CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1', authority_sha: AUTHORITY,
        issuer_generation_id: `issuer-${'7'.repeat(64)}`, issuer_identity_sha256: '8'.repeat(64),
        public_key_algorithm: 'Ed25519', public_key_raw_base64: VPS_ISSUER_PUBLIC_KEY_BYTES.toString('base64'),
        public_key_sha256: sha(VPS_ISSUER_PUBLIC_KEY_BYTES), allowed_pass_purpose: 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1',
        normal_executor_authorized: false, raw_values: false,
      };
    } else if (role === 'vps-pass-root') {
      payload = {
        schema_version: 1, purpose: 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1', authority_sha: AUTHORITY,
        authority_parent: '9'.repeat(40), authority_tree: 'f'.repeat(40),
        authority_subject_sha256: sha(Buffer.from('build(ops): authorize bounded Git blob reader for CI-3 bridge')),
        authority_manifest_sha256: authorityManifestSourceSha256, operation_authority_sha256: '0'.repeat(64),
        node_candidate_sha256: '1'.repeat(64), collector_contracts_sha256: sha(compactJsonBytes(Object.fromEntries(fixtureScanContracts().map((entry) => [entry.id, entry])))),
        publisher_input_manifest_sha256: '0'.repeat(64), source_generation_id: `src-${'2'.repeat(64)}`,
        transfer_payload_sha256: '3'.repeat(64), attempt: 1, retry: false,
        remote_generation_id: GENERATIONS.remote, controller_generation_id: GENERATIONS.controller,
        issuer_authority_sha256: '0'.repeat(64), issuer_key_sha256: sha(VPS_ISSUER_PUBLIC_KEY_BYTES),
        signed_payload_sha256: '0'.repeat(64), signature_base64: 'placeholder', raw_values: false,
      };
    } else if (role === 'human-authorization-root') {
      payload = {
        schema_version: 1, purpose: 'CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V1', authority_sha: AUTHORITY,
        approved_action: 'PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY', authority_manifest_sha256: authorityManifestSourceSha256,
        node_binary_sha256: '1'.repeat(64), operation_authority_sha256: '0'.repeat(64),
        publisher_input_manifest_sha256: '0'.repeat(64), vps_operation_authority_pass_sha256: '0'.repeat(64),
        attempt: 1, retry: false, raw_values: false,
      };
    } else if (role === 'publisher-input-manifest-root') {
      payload = {
        schema_version: 1, purpose: 'CI3_VPS_PUBLISHER_INPUT_MANIFEST_V1', authority_sha: AUTHORITY,
        remote_generation_id: GENERATIONS.remote, controller_generation_id: GENERATIONS.controller,
        collector_contracts_sha256: sha(compactJsonBytes(Object.fromEntries(fixtureScanContracts().map((entry) => [entry.id, entry])))),
        entries: [], transfer_payload_sha256: '0'.repeat(64), raw_values: false,
      };
    } else if (role === 'ssh-trust-descriptor') {
      payload = {
        schema_version: 1, purpose: 'CI3_MAC_SSH_TRUST_DESCRIPTOR_V1', authority_sha: AUTHORITY,
        remote_generation_id: GENERATIONS.remote, identity_public_key_sha256: sha(SSH_PUBLIC_KEY_BYTES),
        identity_public_key_fingerprint_sha256: sha(SSH_FINGERPRINT_BYTES),
        destination_sha256: '1'.repeat(64), host_key_ed25519_fingerprint_sha256: '2'.repeat(64),
        isolated_config_sha256: '3'.repeat(64), known_hosts_sha256: '4'.repeat(64),
        native_key_order: ['hostname'], native_record_count: 1,
        native_records_sha256: sha(compactJsonBytes([{ key: 'hostname', value: 'ci3.invalid', ordinal: 0 }])),
        raw_destination_reported: false, ssh_code_signature_sha256: '5'.repeat(64),
        ssh_executable_path_sha256: '6'.repeat(64), ssh_executable_sha256: '7'.repeat(64),
        ssh_version_sha256: '8'.repeat(64),
      };
    } else if (role === 'ssh-public-key' || role === 'ssh-public-key-fingerprint') {
      payload = null;
    } else if (role.startsWith('simulator-phase-')) {
      const match = /^simulator-phase-(.+)-(claim|receipt|result)$/.exec(role);
      assert.ok(match);
      const phase = match[1].toUpperCase().replaceAll('-', '_');
      const kind = match[2];
      if (kind === 'claim') {
        payload = {
          schema_version: 1, purpose: 'CI3_SIMULATOR_PHASE_CLAIM_V1', phase,
          authority_sha: AUTHORITY, controller_generation_id: GENERATIONS.controller,
          simulator_generation_id: GENERATIONS.simulator, predecessor_result_sha256: simulatorPredecessor,
          attempt: 1, retry: false, raw_values: false,
        };
        simulatorPhaseClaims.set(phase, compactJsonBytes(payload));
      } else if (kind === 'receipt') {
        const observation = simulatorObservation(phase);
        payload = {
          schema_version: 1, purpose: 'CI3_SIMULATOR_PHASE_RECEIPT_V1', phase,
          claim_sha256: sha(simulatorPhaseClaims.get(phase)), observation,
          observation_sha256: sha(compactJsonBytes(observation)), physical_reobservation: true, raw_values: false,
        };
        simulatorPhaseReceipts.set(phase, compactJsonBytes(payload));
      } else {
        const observation = simulatorObservation(phase);
        const receiptRole = `${role.slice(0, -'result'.length)}receipt`;
        const receiptEntry = evidence.find(({ role: candidate }) => candidate === receiptRole);
        const receiptMetadata = receiptEntry.metadata;
        payload = {
          schema_version: 1, purpose: 'CI3_SIMULATOR_PHASE_RESULT_V1', phase,
          claim_sha256: sha(simulatorPhaseClaims.get(phase)), receipt_sha256: receiptEntry.sha256,
          physical_observation_sha256: sha(simulatorPhaseReceipts.get(phase) ? compactJsonBytes(observation) : Buffer.alloc(0)),
          observation, terminal_state: 'PHASE_SETTLED', raw_values: false,
        };
      }
    } else if (role.startsWith('controller-phase-')) {
      const match = /^controller-phase-(.+)-(claim|receipt|result)$/.exec(role);
      assert.ok(match);
      const phase = match[1].toUpperCase().replaceAll('-', '_');
      const kind = match[2];
      if (kind === 'claim') {
        payload = {
          schema_version: 1, purpose: 'CI3_MAC_PHASE_CLAIM_V1', phase,
          authority_sha: AUTHORITY, controller_generation_id: GENERATIONS.controller,
          predecessor_result_sha256: '1'.repeat(64), contract_sha256: '2'.repeat(64),
          attempt: 1, retry: false, raw_values: false,
        };
        controllerPhaseClaims.set(phase, compactJsonBytes(payload));
      } else if (kind === 'receipt') {
        const result = { phase_sha256: sha(Buffer.from(phase)) };
        payload = {
          schema_version: 1, purpose: 'CI3_MAC_PHASE_PHYSICAL_RECEIPT_V1', phase,
          claim_sha256: sha(controllerPhaseClaims.get(phase)), result,
          result_sha256: sha(compactJsonBytes(result)), raw_values: false,
        };
        controllerPhaseReceipts.set(phase, compactJsonBytes(payload));
      } else {
        const receiptRole = `${role.slice(0, -'result'.length)}receipt`;
        const receiptEntry = evidence.find(({ role: candidate }) => candidate === receiptRole);
        payload = {
          schema_version: 1, purpose: 'CI3_MAC_PHASE_RESULT_V1', phase,
          claim_sha256: sha(controllerPhaseClaims.get(phase)), receipt_sha256: receiptEntry.sha256,
          physical_observation_sha256: observationHash(await readFile(receiptEntry.path), receiptEntry.metadata),
          terminal_state: 'PHASE_SETTLED', raw_values: false,
        };
      }
    }
    const bytes = role === 'writer-source'
      ? await readFile(SOURCE_PATH)
      : role === 'ssh-public-key'
        ? SSH_PUBLIC_KEY_BYTES
        : role === 'ssh-public-key-fingerprint'
          ? SSH_FINGERPRINT_BYTES
      : role.startsWith('simulator-phase-') || role.startsWith('controller-phase-')
        ? compactJsonBytes(payload)
        : jsonBytes(payload);
    await writeFile(evidencePath, bytes, { mode: 0o600 });
    evidence.push({ role, path: evidencePath, sha256: sha(bytes), metadata: await physicalMetadata(evidencePath) });
    evidencePayloads.set(role, bytes);
    if (role.startsWith('simulator-phase-') && role.endsWith('-receipt')) simulatorReceiptHashes.push(sha(bytes));
    if (role.startsWith('simulator-phase-') && role.endsWith('-result')) simulatorPredecessor = sha(bytes);
  }

  const authorityManifestRoot = evidence.find(({ role }) => role === 'authority-manifest');
  const sshDescriptorRoot = evidence.find(({ role }) => role === 'ssh-trust-descriptor');
  const issuerRoot = evidence.find(({ role }) => role === 'vps-issuer-authority-root');
  const phaseTargetContracts = ['VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH', 'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS'].map((phase) => {
    let targets;
    if (phase === 'VERIFY_AUTHORITY') targets = [{ role: 'effect-authority-manifest', path: authorityManifestRoot.path, state: 'PRESENT' }];
    else if (phase === 'VERIFY_WORKTREE') targets = [{ role: 'effect-launch-attestation', path: evidence.find(({ role }) => role === 'launch-attestation').path, state: 'PRESENT' }];
    else if (phase === 'VERIFY_SIMULATOR') targets = [{ role: 'effect-simulator-gate', path: evidence.find(({ role }) => role === 'simulator-gate').path, state: 'PRESENT' }];
    else if (phase === 'VERIFY_SSH') targets = [{ role: 'effect-ssh-provenance', path: evidence.find(({ role }) => role === 'ssh-provenance').path, state: 'PRESENT' }];
    else if (phase === 'PUBLISH_LOCAL') targets = [{ role: 'effect-local-receipt', path: evidence.find(({ role }) => role === 'local-receipt').path, state: 'PRESENT' }];
    else if (phase === 'INSTALL_SIMULATOR') targets = [{ role: 'effect-simulator-install', path: evidence.find(({ role }) => role === 'simulator-install').path, state: 'PRESENT' }];
    else if (phase === 'REMOVE_CREDENTIAL') targets = [{ role: 'simulator-credential', path: path.join(evidenceRoot, 'removed-credential.json'), state: 'ABSENT' }];
    else targets = SCAN_IDS.map((id) => ({ role: `effect-${id}`, path: path.join(evidenceRoot, `scan-${id}.json`), state: 'PRESENT' }));
    return {
      phase,
      targets: targets.map((target) => ({
        role: target.role, state: target.state, path_sha256: sha(Buffer.from(target.path)),
        modes: target.state === 'PRESENT' ? [0o600] : [], allowed_uids: [process.getuid()],
        allowed_gids: [process.getgid()], immutable: false,
      })),
    };
  });
  const operationRootRewrite = await rewriteEvidenceObject(evidence, 'operation-authority-root', (object) => {
    object.context.authority.manifest_sha256 = authorityManifestSourceSha256;
    object.context.remote.receipt_sha256 = evidence.find(({ role }) => role === 'remote-receipt').sha256;
    object.context.remote.config_sha256 = '3'.repeat(64);
    object.context.remote.credential_sha256 = '4'.repeat(64);
    object.ssh.trust_descriptor_sha256 = sshDescriptorRoot.sha256;
    object.writer = {
      authority_path: authorityReceiptPath,
      manifest_path: path.join(evidenceRoot, 'terminal-manifest.json'),
      phase_target_contracts: phaseTargetContracts,
    };
    mutateOperationAuthority?.(object);
  });
  const publisherRewrite = await rewriteEvidenceObject(evidence, 'publisher-input-manifest-root', (object) => {
    object.entries = [
      { role: 'operation-authority', path_sha256: '4'.repeat(64), sha256: operationRootRewrite.entry.sha256 },
      { role: 'node-runtime', path_sha256: '5'.repeat(64), sha256: '1'.repeat(64) },
    ];
    object.transfer_payload_sha256 = sha(compactJsonBytes(object.entries));
  });
  const passRewrite = await rewriteEvidenceObject(evidence, 'vps-pass-root', (object) => {
    object.authority_manifest_sha256 = authorityManifestSourceSha256;
    object.operation_authority_sha256 = operationRootRewrite.entry.sha256;
    object.publisher_input_manifest_sha256 = publisherRewrite.entry.sha256;
    object.transfer_payload_sha256 = publisherRewrite.object.transfer_payload_sha256;
    object.issuer_authority_sha256 = issuerRoot.sha256;
    const payloadBytes = vpsPassSigningPayload(object);
    object.signed_payload_sha256 = sha(payloadBytes);
    object.signature_base64 = ed25519Sign(null, payloadBytes, VPS_ISSUER_KEYPAIR.privateKey).toString('base64');
  });
  const humanRewrite = await rewriteEvidenceObject(evidence, 'human-authorization-root', (object) => {
    object.operation_authority_sha256 = operationRootRewrite.entry.sha256;
    object.publisher_input_manifest_sha256 = publisherRewrite.entry.sha256;
    object.vps_operation_authority_pass_sha256 = passRewrite.entry.sha256;
  });
  const sshRewrite = await rewriteEvidenceObject(evidence, 'ssh-provenance', (object) => {
    object.result.provenance.identity_public_key_sha256 = sha(SSH_PUBLIC_KEY_BYTES);
    object.result.provenance.identity_public_key_fingerprint_sha256 = sha(SSH_FINGERPRINT_BYTES);
    object.result.provenance.trust_descriptor_sha256 = sshDescriptorRoot.sha256;
    object.result_sha256 = sha(compactJsonBytes(object.result));
  });

  const simulatorGateEntry = evidence.find(({ role }) => role === 'simulator-gate');
  const simulatorGatePayload = JSON.parse(evidencePayloads.get('simulator-gate'));
  simulatorGatePayload.result.receipt.phase_receipt_hashes = simulatorReceiptHashes;
  simulatorGatePayload.result_sha256 = sha(compactJsonBytes(simulatorGatePayload.result));
  const simulatorGateBytes = jsonBytes(simulatorGatePayload);
  await writeFile(simulatorGateEntry.path, simulatorGateBytes, { mode: 0o600 });
  simulatorGateEntry.sha256 = sha(simulatorGateBytes);
  simulatorGateEntry.metadata = await physicalMetadata(simulatorGateEntry.path);
  evidencePayloads.set('simulator-gate', simulatorGateBytes);

  const evidenceSha = (role) => evidence.find((entry) => entry.role === role).sha256;
  const localBundleSha256 = evidenceSha('local-receipt');
  const simulatorInstallSha256 = evidenceSha('simulator-install');

  const scanReceipts = [];
  for (const scanId of SCAN_IDS) {
    const inputPath = path.join(evidenceRoot, `input-${scanId}.txt`);
    const inputBytes = Buffer.from(`synthetic clean ${scanId}\n`);
    await writeFile(inputPath, inputBytes, { mode: 0o600 });
    const scanPath = path.join(evidenceRoot, `scan-${scanId}.json`);
    const bytes = jsonBytes({
      schema_version: 1,
      purpose: 'CI3_TERMINAL_SCAN_RECEIPT_V1',
      scan_id: scanId,
      authority_sha: AUTHORITY,
      controller_generation_id: GENERATIONS.controller,
      remote_generation_id: GENERATIONS.remote,
      simulator_generation_id: GENERATIONS.simulator,
      terminal_generation_id: GENERATIONS.terminal,
      local_bundle_sha256: localBundleSha256,
      simulator_install_sha256: simulatorInstallSha256,
      worktree_diff_sha256: '3'.repeat(64),
      input_manifest_sha256: '4'.repeat(64),
      input_observations: [{ path: inputPath, path_sha256: sha(Buffer.from(inputPath)), sha256: sha(inputBytes), metadata: await physicalMetadata(inputPath) }],
      tool_sha256: '5'.repeat(64),
      command_sha256: '6'.repeat(64),
      scanner_schema_sha256: '8'.repeat(64),
      counters: { secret: 0, pii: 0, jwt: 0, token: 0, raw_destination: 0 },
      started_at: '2026-08-30T12:00:00.000Z',
      finished_at: '2026-08-30T12:00:01.000Z',
      result: 'CLEAN',
      match_count: 0,
      output_sha256: '7'.repeat(64),
      redaction: true,
      input_stable_after_scan: true,
    });
    await writeFile(scanPath, bytes, { mode: 0o600 });
    scanReceipts.push({ id: scanId, path: scanPath, sha256: sha(bytes), metadata: await physicalMetadata(scanPath) });
  }

  const remoteEntry = evidence.find(({ role }) => role === 'remote-receipt');
  const simulatorEntry = evidence.find(({ role }) => role === 'simulator-gate');
  const sshEntry = evidence.find(({ role }) => role === 'ssh-provenance');
  const bootstrapRewrite = await rewriteEvidenceObject(evidence, 'bootstrap-claim', (object) => {
    object.simulator_gate_sha256 = simulatorEntry.sha256;
    object.ssh_trust_descriptor_sha256 = sshDescriptorRoot.sha256;
  });
  const finalizedClaims = [];
  const finalizedResults = [];
  for (const kind of ['receipt', 'config', 'credential']) {
    const expectedSha256 = kind === 'receipt' ? remoteEntry.sha256 : kind === 'config' ? '3'.repeat(64) : '4'.repeat(64);
    const claimRewrite = await rewriteEvidenceObject(evidence, `${kind}-read-claim`, (object) => {
      object.bootstrap_claim_sha256 = bootstrapRewrite.entry.sha256;
      object.expected_sha256 = expectedSha256;
      object.ssh_trust_descriptor_sha256 = sshDescriptorRoot.sha256;
    });
    const resultRewrite = await rewriteEvidenceObject(evidence, `${kind}-read-result`, (object) => {
      object.claim_sha256 = claimRewrite.entry.sha256;
      object.capture_sha256 = expectedSha256;
      object.ssh_trust_descriptor_sha256 = sshDescriptorRoot.sha256;
    });
    finalizedClaims.push(claimRewrite.object);
    finalizedResults.push(resultRewrite.object);
  }
  const localRewrite = await rewriteEvidenceObject(evidence, 'local-receipt', (object) => {
    object.bootstrap_claim_sha256 = bootstrapRewrite.entry.sha256;
    object.remote_receipt_sha256 = remoteEntry.sha256;
    object.read_claim_chain_sha256 = sha(compactJsonBytes(finalizedClaims));
    object.read_result_chain_sha256 = sha(compactJsonBytes(finalizedResults));
    object.simulator_gate_sha256 = simulatorEntry.sha256;
    object.ssh_provenance_sha256 = sshEntry.sha256;
  });
  const installRewrite = await rewriteEvidenceObject(evidence, 'simulator-install', (object) => {
    object.local_bundle_sha256 = localRewrite.entry.sha256;
  });
  const readCommands = ['receipt', 'config', 'credential'].map((kind, index) => ({
    kind,
    expected_path_sha256: finalizedClaims[index].expected_path_sha256,
    expected_sha256: finalizedClaims[index].expected_sha256,
    capture_sha256: finalizedResults[index].capture_sha256,
    remote_command_sha256: finalizedResults[index].remote_command_sha256,
  }));
  const scanContracts = fixtureScanContracts();
  const finalSourcesRoot = path.join(evidenceRoot, 'final-sources');
  await mkdir(finalSourcesRoot, { mode: 0o700 });
  const sourceParentIdentitySha256 = await physicalIdentitySha256(finalSourcesRoot);
  const scanSourceById = new Map();
  for (const scanId of SCAN_IDS) {
    const sourcePath = path.join(finalSourcesRoot, `${scanId}.surface`);
    if (scanId === 'xcresult') {
      const body = {
        schema_version: 1, purpose: 'CI3_TERMINAL_SCAN_SOURCE_OBSERVATION_V1', scan_id: scanId,
        source_semantics: scanId, state: 'ABSENT', path: sourcePath, path_sha256: sha(Buffer.from(sourcePath)),
        content_sha256: null, identity_sha256: null, metadata: null, byte_range: null,
        parent_identity_sha256: sourceParentIdentitySha256, raw_values: false,
      };
      scanSourceById.set(scanId, {
        path: sourcePath, bytes: Buffer.alloc(0),
        observation: { ...body, absence_observation_sha256: sha(compactJsonBytes(body)) },
      });
      continue;
    }
    const bytes = compactJsonBytes({ schema_version: 1, purpose: `CI3_SYNTHETIC_${scanId.toUpperCase().replaceAll('-', '_')}_SURFACE_V1`, raw_values: false });
    await writeFile(sourcePath, bytes, { mode: 0o600 });
    const metadata = await physicalMetadata(sourcePath);
    scanSourceById.set(scanId, {
      path: sourcePath, bytes,
      observation: {
        schema_version: 1, purpose: 'CI3_TERMINAL_SCAN_SOURCE_OBSERVATION_V1', scan_id: scanId,
        source_semantics: scanId, state: 'PRESENT', path: sourcePath, path_sha256: sha(Buffer.from(sourcePath)),
        content_sha256: sha(bytes), identity_sha256: await physicalIdentitySha256(sourcePath), metadata,
        byte_range: { start: 0, end: bytes.length }, parent_identity_sha256: sourceParentIdentitySha256,
        absence_observation_sha256: null, raw_values: false,
      },
    });
  }
  const finalSourceParentIdentitySha256 = await physicalIdentitySha256(finalSourcesRoot);
  for (const source of scanSourceById.values()) {
    source.observation.parent_identity_sha256 = finalSourceParentIdentitySha256;
    if (source.observation.state === 'ABSENT') {
      const { absence_observation_sha256: _old, ...body } = source.observation;
      source.observation.absence_observation_sha256 = sha(compactJsonBytes(body));
    }
  }
  const inputRewrite = await rewriteEvidenceObject(evidence, 'input-manifest', (object) => {
    object.local_bundle_sha256 = localRewrite.entry.sha256;
    object.simulator_install_sha256 = installRewrite.entry.sha256;
    object.read_commands = readCommands;
    object.scan_contracts = scanContracts;
  });
  for (let index = 0; index < scanReceipts.length; index += 1) {
    const scanEntry = scanReceipts[index];
    const contract = scanContracts[index];
    const inputPath = path.join(evidenceRoot, `input-${scanEntry.id}.txt`);
    const source = scanSourceById.get(scanEntry.id);
    const contentBytes = source.bytes;
    const surfaceBytes = compactJsonBytes({
      schema_version: 1, purpose: 'CI3_FINAL_OPERATION_SCAN_SURFACE_V1', scan_id: scanEntry.id,
      collector_version: contract.collector_version, source_role: contract.source_role,
      authority_sha: AUTHORITY, controller_generation_id: GENERATIONS.controller,
      terminal_generation_id: GENERATIONS.terminal,
      source_roots: [{
        role: contract.source_role, sha256: sha(contentBytes),
        identity_sha256: source.observation.identity_sha256 ?? source.observation.absence_observation_sha256,
      }],
      source_observation: source.observation,
      content_base64: contentBytes.toString('base64'), content_byte_length: contentBytes.length,
      content_sha256: sha(contentBytes),
      raw_values: false,
    });
    await writeFile(inputPath, surfaceBytes, { mode: 0o600 });
    const inputMetadata = await physicalMetadata(inputPath);
    const inputSha256 = sha(surfaceBytes);
    const receiptObject = JSON.parse(await readFile(scanEntry.path, 'utf8'));
    receiptObject.local_bundle_sha256 = localRewrite.entry.sha256;
    receiptObject.simulator_install_sha256 = installRewrite.entry.sha256;
    receiptObject.input_manifest_sha256 = inputRewrite.entry.sha256;
    receiptObject.input_observations = [{
      path: inputPath, path_sha256: sha(Buffer.from(inputPath)), sha256: inputSha256, metadata: inputMetadata,
    }];
    receiptObject.tool_sha256 = contract.tool_sha256;
    receiptObject.scanner_schema_sha256 = contract.contract_sha256;
    receiptObject.command_sha256 = sha(compactJsonBytes({
      scan_id: scanEntry.id, collector_version: contract.collector_version,
      contract_sha256: contract.contract_sha256, source_role: contract.source_role,
      tool_sha256: contract.tool_sha256,
    }));
    receiptObject.output_sha256 = sha(compactJsonBytes([{ byte_length: contentBytes.length, sha256: sha(contentBytes) }]));
    const receiptBytes = compactJsonBytes(receiptObject);
    await writeFile(scanEntry.path, receiptBytes, { mode: 0o600 });
    scanEntry.sha256 = sha(receiptBytes);
    scanEntry.metadata = await physicalMetadata(scanEntry.path);
  }

  const controllerPhases = ['VERIFY_AUTHORITY', 'VERIFY_WORKTREE', 'VERIFY_SIMULATOR', 'VERIFY_SSH', 'PUBLISH_LOCAL', 'INSTALL_SIMULATOR', 'REMOVE_CREDENTIAL', 'RUN_SCANS'];
  let controllerPredecessor = '0'.repeat(64);
  let runScansResultSha256;
  for (const phase of controllerPhases) {
    const prefix = `controller-phase-${phase.toLowerCase().replaceAll('_', '-')}`;
    if (phase === 'RUN_SCANS') {
      for (let index = 0; index < scanReceipts.length; index += 1) {
        const scanEntry = scanReceipts[index];
        const contract = scanContracts[index];
        const inputPath = path.join(evidenceRoot, `input-${scanEntry.id}.txt`);
        const source = scanSourceById.get(scanEntry.id);
        const contentBytes = source.bytes;
        const surfaceObject = {
          schema_version: 1, purpose: 'CI3_FINAL_OPERATION_SCAN_SURFACE_V1', scan_id: scanEntry.id,
          collector_version: contract.collector_version, source_role: contract.source_role,
          authority_sha: AUTHORITY, controller_generation_id: GENERATIONS.controller,
          terminal_generation_id: GENERATIONS.terminal,
          source_roots: [{
            role: contract.source_role, sha256: sha(contentBytes),
            identity_sha256: source.observation.identity_sha256 ?? source.observation.absence_observation_sha256,
          }],
          source_observation: source.observation,
          content_base64: contentBytes.toString('base64'), content_byte_length: contentBytes.length,
          content_sha256: sha(contentBytes), raw_values: false,
        };
        if (mutateScanSurface) await mutateScanSurface(surfaceObject, scanEntry.id);
        const surfaceBytes = compactJsonBytes(surfaceObject);
        await writeFile(inputPath, surfaceBytes, { mode: 0o600 });
        const receiptObject = JSON.parse(await readFile(scanEntry.path, 'utf8'));
        receiptObject.input_observations = [{
          path: inputPath, path_sha256: sha(Buffer.from(inputPath)), sha256: sha(surfaceBytes), metadata: await physicalMetadata(inputPath),
        }];
        const finalContent = Buffer.from(surfaceObject.content_base64, 'base64');
        receiptObject.output_sha256 = sha(compactJsonBytes([{ byte_length: finalContent.length, sha256: sha(finalContent) }]));
        const receiptBytes = compactJsonBytes(receiptObject);
        await writeFile(scanEntry.path, receiptBytes, { mode: 0o600 });
        scanEntry.sha256 = sha(receiptBytes);
        scanEntry.metadata = await physicalMetadata(scanEntry.path);
      }
    }
    let targetEntries;
    if (phase === 'VERIFY_AUTHORITY') targetEntries = [evidence.find(({ role }) => role === 'authority-manifest')];
    else if (phase === 'VERIFY_WORKTREE') targetEntries = [evidence.find(({ role }) => role === 'launch-attestation')];
    else if (phase === 'VERIFY_SIMULATOR') targetEntries = [simulatorEntry];
    else if (phase === 'VERIFY_SSH') targetEntries = [sshEntry];
    else if (phase === 'PUBLISH_LOCAL') targetEntries = [localRewrite.entry];
    else if (phase === 'INSTALL_SIMULATOR') targetEntries = [installRewrite.entry];
    else if (phase === 'RUN_SCANS') targetEntries = scanReceipts;
    else targetEntries = [];
    const targets = await Promise.all(targetEntries.map(async (entry) => ({
      role: `effect-${entry.role ?? entry.id}`, state: 'PRESENT', path: entry.path, path_sha256: sha(Buffer.from(entry.path)),
      sha256: entry.sha256, identity_sha256: await physicalIdentitySha256(entry.path), metadata: entry.metadata,
    })));
    if (phase === 'REMOVE_CREDENTIAL') targets.push({
      role: 'simulator-credential', state: 'ABSENT', path: path.join(evidenceRoot, 'removed-credential.json'),
      path_sha256: sha(Buffer.from(path.join(evidenceRoot, 'removed-credential.json'))),
      sha256: null, identity_sha256: null, metadata: null,
    });
    if (mutatePhaseTargets) await mutatePhaseTargets({ phase, targets, evidenceRoot });
    const observationBody = {
      schema_version: 1, purpose: 'CI3_MAC_PHASE_EFFECT_OBSERVATION_V1', phase, targets, raw_values: false,
    };
    const observation = { ...observationBody, observation_sha256: sha(compactJsonBytes(observationBody)) };
    const contractSha256 = sha(compactJsonBytes({
      event: phase, authority_sha: AUTHORITY, controller_generation_id: GENERATIONS.controller,
      generations: GENERATIONS, predecessor_result_sha256: controllerPredecessor,
    }));
    const claimRewrite = await rewriteEvidenceObject(evidence, `${prefix}-claim`, (object) => {
      object.predecessor_result_sha256 = controllerPredecessor;
      object.contract_sha256 = contractSha256;
    });
    const receiptRewrite = await rewriteEvidenceObject(evidence, `${prefix}-receipt`, (object) => {
      object.claim_sha256 = claimRewrite.entry.sha256;
      object.observation = observation;
    });
    const resultRewrite = await rewriteEvidenceObject(evidence, `${prefix}-result`, (object) => {
      object.claim_sha256 = claimRewrite.entry.sha256;
      object.receipt_sha256 = receiptRewrite.entry.sha256;
      object.physical_observation_sha256 = observation.observation_sha256;
    });
    controllerPredecessor = resultRewrite.entry.sha256;
    if (phase === 'RUN_SCANS') runScansResultSha256 = resultRewrite.entry.sha256;
  }
  const terminalSettlementContracts = [];
  let settlementPredecessor = runScansResultSha256;
  for (const phase of ['INVOKE_WRITER', 'VERIFY_ANCHOR']) {
    const contract = {
      schema_version: 1, purpose: 'CI3_TERMINAL_SETTLEMENT_CONTRACT_V1', phase,
      authority_sha: AUTHORITY, controller_generation_id: GENERATIONS.controller,
      terminal_generation_id: GENERATIONS.terminal, predecessor_contract_sha256: settlementPredecessor,
      effect_authorized: phase === 'INVOKE_WRITER' ? 'PRIVILEGED_WRITER_ON_FROZEN_MANIFEST' : 'REOPEN_ROOT_ANCHOR',
      raw_values: false,
    };
    terminalSettlementContracts.push(contract);
    settlementPredecessor = sha(compactJsonBytes(contract));
  }
  await rewriteEvidenceObject(evidence, 'terminal-receipt', (object) => {
    object.scan_receipt_sha256 = scanReceipts.map(({ id, sha256: value }) => ({ id, sha256: value }));
    object.run_scans_result_sha256 = runScansResultSha256;
    object.terminal_settlement_contracts_sha256 = sha(compactJsonBytes(terminalSettlementContracts));
  });

  if (mutateEvidence) await mutateEvidence({ evidence, scanReceipts });

  const manifest = {
    schema_version: 1,
    purpose: 'CI3_TERMINAL_ANCHOR_MANIFEST_V1',
    authority_sha: AUTHORITY,
    authority_tree: 'f'.repeat(40),
    authority_manifest_sha256: authorityManifestSourceSha256,
    bootstrap_claim_sha256: evidenceSha('bootstrap-claim'),
    claim_result_chain_sha256: sha(Buffer.from([
      'receipt-read-claim', 'receipt-read-result', 'config-read-claim',
      'config-read-result', 'credential-read-claim', 'credential-read-result',
    ].map(evidenceSha).join(':'))),
    remote_bundle_sha256: evidenceSha('remote-receipt'),
    local_bundle_sha256: evidenceSha('local-receipt'),
    ssh_provenance_sha256: evidenceSha('ssh-provenance'),
    simulator_gate_sha256: evidenceSha('simulator-gate'),
    simulator_install_sha256: evidenceSha('simulator-install'),
    writer_authority_path_sha256: sha(Buffer.from(authorityReceiptPath)),
    components: components(),
    writer_source_sha256: sourceSha256,
    writer_binary_sha256: binarySha256,
    writer_signature_sha256: sha(Buffer.from('SYNTHETIC_TEST_BUILD')),
    generations: structuredClone(GENERATIONS),
    evidence,
    scan_receipts: scanReceipts,
    terminal_settlement_contracts: terminalSettlementContracts,
    important_finding_ids: [...FINDING_IDS],
    anchor_relative_path: `${AUTHORITY}/${GENERATIONS.terminal}/pre-anchor.json`,
    terminal_state: 'PRE_ANCHOR_PENDING_SETTLEMENT',
    created_at_utc: '2026-08-30T12:00:00.000Z',
    raw_values: false,
    secret_read: false,
    privilege_mode: 'MACOS_ROOT_SINGLE_ADMIN_PROMPT',
  };
  if (mutateManifest) await mutateManifest(manifest);
  const manifestPath = path.join(evidenceRoot, 'terminal-manifest.json');
  const manifestBytes = jsonBytes(manifest);
  await writeFile(manifestPath, manifestBytes, { mode: 0o600 });

  const anchorPath = path.join(anchorRoot, manifest.anchor_relative_path);
  const claim = {
    schema_version: 1,
    purpose: 'CI3_PRIVILEGED_TERMINAL_ANCHOR_CLAIM_V1',
    authority_sha: AUTHORITY,
    terminal_generation_id: GENERATIONS.terminal,
    terminal_manifest_sha256: sha(manifestBytes),
    writer_source_sha256: sourceSha256,
    writer_binary_sha256: binarySha256,
    anchor_path_sha256: sha(Buffer.from(anchorPath)),
    attempt: 1,
    retry: false,
    uid: 0,
    gid: 0,
    file_mode: '0444',
    immutable_flag: 'UF_IMMUTABLE',
    normal_executor_authorized: false,
  };
  if (mutateClaim) await mutateClaim(claim);
  const claimPath = path.join(evidenceRoot, 'privileged-anchor.claim.json');
  const claimBytes = jsonBytes(claim);
  await writeFile(claimPath, claimBytes, { mode: 0o600 });

  const authorityReceipt = {
    schema_version: 1,
    purpose: 'CI3_PRIVILEGED_TERMINAL_ANCHOR_WRITER_AUTHORITY_V1',
    authority_sha: AUTHORITY,
    terminal_generation_id: GENERATIONS.terminal,
    terminal_manifest_sha256: sha(manifestBytes),
    terminal_manifest_path_sha256: sha(Buffer.from(manifestPath)),
    writer_source_sha256: sourceSha256,
    writer_binary_sha256: binarySha256,
    writer_signature_sha256: sha(Buffer.from('SYNTHETIC_TEST_BUILD')),
    writer_executable_path_sha256: sha(Buffer.from(binaryPath)),
    writer_executable_identity_sha256: await physicalIdentitySha256(binaryPath),
    writer_executable_uid: 0,
    writer_executable_gid: 0,
    writer_executable_mode: '0555',
    writer_executable_immutable_flag: 'UF_IMMUTABLE',
    privileged_claim_sha256: sha(claimBytes),
    authority_path_sha256: sha(Buffer.from(authorityReceiptPath)),
    anchor_path_sha256: sha(Buffer.from(anchorPath)),
    normal_executor_authorized: false,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  await writeFile(authorityReceiptPath, jsonBytes(authorityReceipt), { mode: 0o600 });

  return { anchorPath, anchorRoot, authorityReceipt, authorityReceiptPath, claim, claimPath, evidenceRoot, manifest, manifestPath, root };
}

function invoke(fixture, extraArgs = [], extraEnv = {}) {
  const result = spawnSync(requireBuild(), [
    '--write', fixture.manifestPath, fixture.authorityReceiptPath, AUTHORITY,
    GENERATIONS.remote, GENERATIONS.controller, GENERATIONS.simulator, GENERATIONS.terminal,
    ...extraArgs,
  ], {
    encoding: 'utf8',
    env: {
      PATH: '/usr/bin:/bin',
      CI3_SYNTHETIC_ANCHOR_ROOT: fixture.anchorRoot,
      ...extraEnv,
    },
    timeout: WRITER_INVOCATION_TIMEOUT_MS,
  });
  assert.ifError(result.error);
  assert.equal(result.signal, null, `writer invocation was terminated by signal ${result.signal ?? 'unknown'}`);
  assert.notEqual(result.status, null, 'writer invocation ended without an exit status');
  return result;
}

function validateFixture(fixture) {
  const result = spawnSync(requireBuild(), [
    '--validate-manifest', fixture.manifestPath, AUTHORITY,
    GENERATIONS.remote, GENERATIONS.controller, GENERATIONS.simulator, GENERATIONS.terminal,
  ], {
    encoding: 'utf8',
    env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
    timeout: WRITER_INVOCATION_TIMEOUT_MS,
  });
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  return result;
}

async function cleanupFixture(fixture) {
  spawnSync('/usr/bin/chflags', ['-R', 'nouchg', fixture.root], {
    encoding: 'utf8', env: { PATH: '/usr/bin:/bin' },
  });
  for (const candidate of [
    fixture.anchorPath,
    path.join(path.dirname(fixture.anchorPath), 'terminal-phases'),
    path.dirname(fixture.anchorPath),
    path.dirname(path.dirname(fixture.anchorPath)),
  ]) {
    await chmod(candidate, 0o700).catch(() => {});
  }
  await rm(fixture.root, { recursive: true, force: true });
}

async function expectFixtureFailure(options) {
  const fixture = await createFixture(options);
  try {
    const result = invoke(fixture);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^ERROR [A-Z0-9_]+\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
}

async function rewriteEvidenceObject(evidence, role, transform) {
  const entry = evidence.find((candidate) => candidate.role === role);
  assert.ok(entry, role);
  const object = JSON.parse(await readFile(entry.path, 'utf8'));
  await transform(object);
  const bytes = compactJsonBytes(object);
  await writeFile(entry.path, bytes, { mode: 0o600 });
  entry.sha256 = sha(bytes);
  entry.metadata = await physicalMetadata(entry.path);
  return { entry, object, bytes };
}

test('round-3 writer rejects a hash-valid read chain whose capture does not equal the original expected bytes', async () => {
  await expectFixtureFailure({
    mutateEvidence: async ({ evidence }) => {
      const claim = await rewriteEvidenceObject(evidence, 'config-read-claim', (object) => {
        object.expected_sha256 = '9'.repeat(64);
      });
      await rewriteEvidenceObject(evidence, 'config-read-result', (object) => {
        object.claim_sha256 = claim.entry.sha256;
        object.capture_sha256 = '8'.repeat(64);
      });
    },
  });
});

test('round-3 writer rejects a hash-valid controller claim chain with a disconnected predecessor', async () => {
  await expectFixtureFailure({
    mutateEvidence: async ({ evidence }) => {
      const claim = await rewriteEvidenceObject(evidence, 'controller-phase-verify-worktree-claim', (object) => {
        object.predecessor_result_sha256 = 'f'.repeat(64);
      });
      const receipt = await rewriteEvidenceObject(evidence, 'controller-phase-verify-worktree-receipt', (object) => {
        object.claim_sha256 = claim.entry.sha256;
      });
      await rewriteEvidenceObject(evidence, 'controller-phase-verify-worktree-result', (object) => {
        object.claim_sha256 = claim.entry.sha256;
        object.receipt_sha256 = receipt.entry.sha256;
        object.physical_observation_sha256 = observationHash(receipt.bytes, receipt.entry.metadata);
      });
    },
  });
});

test('round-3 writer rejects schema-valid input and terminal receipts disconnected from scans and terminal phases', async () => {
  await expectFixtureFailure({
    mutateEvidence: async ({ evidence }) => {
      await rewriteEvidenceObject(evidence, 'input-manifest', (object) => {
        object.scan_ids = [...SCAN_IDS].reverse();
      });
      await rewriteEvidenceObject(evidence, 'terminal-receipt', (object) => {
        object.authority_sha = '0'.repeat(40);
      });
    },
  });
});

test('round-3 writer rejects simulator observations that merely self-label a phase without binding its actual effect roots', async () => {
  await expectFixtureFailure({
    mutateEvidence: async ({ evidence }) => {
      const receipt = await rewriteEvidenceObject(evidence, 'simulator-phase-install-probe-receipt', (object) => {
        object.observation = { phase_sha256: 'f'.repeat(64) };
        object.observation_sha256 = sha(compactJsonBytes(object.observation));
      });
      await rewriteEvidenceObject(evidence, 'simulator-phase-install-probe-result', (object) => {
        object.receipt_sha256 = receipt.entry.sha256;
        object.observation = receipt.object.observation;
        object.physical_observation_sha256 = observationHash(receipt.bytes, receipt.entry.metadata);
      });
    },
  });
});

test('round-3 writer rescans embedded current-generation surface bytes instead of trusting clean counters', async () => {
  await expectFixtureFailure({
    mutateScanSurface: async (surface, scanId) => {
      if (scanId !== 'runtime') return;
      const dirty = Buffer.from('TOKEN=synthetic-sensitive-value\n');
      surface.content_base64 = dirty.toString('base64');
      surface.content_byte_length = dirty.length;
      surface.content_sha256 = sha(dirty);
    },
  });
});

for (const [scanId, dirtyText] of [
  ['history', 'export PASSWORD=synthetic-sensitive-value\n'],
  ['terminal-log', 'Authorization: Bearer synthetic-sensitive-value\n'],
  ['attachment', '{"service_role":"synthetic-sensitive-value"}'],
]) {
  test(`round-6 writer decodes and scans raw ${scanId} payload before accepting its Base64 frame`, async () => {
    await expectFixtureFailure({
      mutateScanSurface: async (surface, candidateId) => {
        if (candidateId !== scanId) return;
        const dirty = Buffer.from(dirtyText);
        const frame = compactJsonBytes([{
          path_sha256: sha(Buffer.from(`/synthetic/${scanId}`)),
          content_sha256: sha(dirty), content_byte_length: dirty.length,
          content_base64: dirty.toString('base64'),
        }]);
        surface.content_base64 = frame.toString('base64');
        surface.content_byte_length = frame.length;
        surface.content_sha256 = sha(frame);
      },
    });
  });
}

test('unchanged production writer source compiles with the exact parse-as-library gate and has a valid entrypoint', async () => {
  const productionBuildRoot = await mkdtemp(path.join(tmpdir(), 'ci3-writer-production-compile-'));
  try {
    const productionBinary = path.join(productionBuildRoot, 'ci3-terminal-anchor-writer');
    const compilation = spawnSync('/usr/bin/xcrun', [
      'swiftc', '-parse-as-library', '-o', productionBinary, SOURCE_PATH,
    ], {
      encoding: 'utf8',
      env: { PATH: '/usr/bin:/bin' },
      timeout: 120000,
    });
    assert.equal(compilation.status, 0, compilation.stderr);
    const selfTest = spawnSync(productionBinary, ['--self-test'], {
      encoding: 'utf8',
      env: { PATH: '/usr/bin:/bin' },
      timeout: 15000,
    });
    assert.equal(selfTest.status, 0, selfTest.stderr);
    assert.match(selfTest.stdout, /^WRITER_SELF_TEST PASS checks=5 network_calls=0 privilege_prompts=0 semantic_phases=10 scan_surfaces=6\n$/);
  } finally {
    await rm(productionBuildRoot, { recursive: true, force: true });
  }
});

test('anchor writer synthetic self-test uses no privilege prompt or network', () => {
  assert.ok(requireBuild());
  assert.match(binarySha256, /^[a-f0-9]{64}$/);
  const result = spawnSync(requireBuild(), ['--self-test'], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' } });
  assert.equal(result.status, 0);
  assert.match(result.stdout, /^WRITER_SELF_TEST PASS checks=5 network_calls=0 privilege_prompts=0 semantic_phases=10 scan_surfaces=6\n$/);
});

test('round-14 canonical writer validates all manifest evidence without publishing an anchor', async () => {
  const fixture = await createFixture();
  try {
    const result = spawnSync(requireBuild(), [
      '--validate-manifest', fixture.manifestPath, AUTHORITY,
      GENERATIONS.remote, GENERATIONS.controller, GENERATIONS.simulator, GENERATIONS.terminal,
    ], {
      encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
      timeout: WRITER_INVOCATION_TIMEOUT_MS,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    const receipt = JSON.parse(result.stdout);
    assert.equal(receipt.purpose, 'CI3_TERMINAL_SEMANTIC_VALIDATION_RECEIPT_V1');
    assert.equal(receipt.run_scans_result_sha256,
      fixture.manifest.terminal_settlement_contracts[0].predecessor_contract_sha256);
    await assert.rejects(readFile(fixture.anchorPath), { code: 'ENOENT' });
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-14 read-only semantic validator rejects rehashed mutations across every evidence role class', async () => {
  const roleClasses = [
    ['authority-manifest', 'authority-manifest'],
    ['launch-attestation', 'launch-attestation'],
    ['bootstrap-and-reads', 'bootstrap-claim'],
    ['remote-receipt', 'remote-receipt'],
    ['local-receipt', 'local-receipt'],
    ['ssh-provenance', 'ssh-provenance'],
    ['simulator-gate', 'simulator-gate'],
    ['simulator-install', 'simulator-install'],
    ['input-manifest', 'input-manifest'],
    ['terminal-receipt', 'terminal-receipt'],
    ['durable-state', 'controller-durable-state-root'],
    ['external-authority', 'operation-authority-root'],
    ['simulator-phase', 'simulator-phase-select-device-claim'],
    ['controller-phase-claim', 'controller-phase-verify-authority-claim'],
    ['controller-phase-receipt', 'controller-phase-verify-authority-receipt'],
    ['controller-phase-result', 'controller-phase-verify-authority-result'],
  ];
  for (const [label, role] of roleClasses) {
    const fixture = await createFixture({
      mutateEvidence: async ({ evidence }) => {
        await rewriteEvidenceObject(evidence, role, (object) => { object.unexpected_round14 = label; });
      },
    });
    try {
      const result = validateFixture(fixture);
      assert.notEqual(result.status, 0, `${label}=ACCEPTED`);
      assert.equal(result.stdout, '');
      assert.match(result.stderr, /^ERROR [A-Z0-9_]+\n$/);
      await assert.rejects(readFile(fixture.anchorPath), { code: 'ENOENT' });
    } finally {
      await cleanupFixture(fixture);
    }
  }
  const scanFixture = await createFixture({
    mutateEvidence: async ({ scanReceipts }) => {
      const entry = scanReceipts[0];
      const object = JSON.parse(await readFile(entry.path, 'utf8'));
      object.unexpected_round14 = 'scan-receipt';
      const rewritten = jsonBytes(object);
      await writeFile(entry.path, rewritten, { mode: 0o600 });
      entry.sha256 = sha(rewritten);
      entry.metadata = await physicalMetadata(entry.path);
    },
  });
  try {
    const result = validateFixture(scanFixture);
    assert.notEqual(result.status, 0, 'scan-receipt=ACCEPTED');
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^ERROR [A-Z0-9_]+\n$/);
  } finally {
    await cleanupFixture(scanFixture);
  }
});

test('writer refuses write mode without a separately supplied privileged authority receipt', async () => {
  const fixture = await createFixture();
  try {
    const result = spawnSync(requireBuild(), [
      '--write', fixture.manifestPath, AUTHORITY,
      GENERATIONS.remote, GENERATIONS.controller, GENERATIONS.simulator, GENERATIONS.terminal,
    ], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin', CI3_SYNTHETIC_ANCHOR_ROOT: fixture.anchorRoot }, timeout: 15000,
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR PRIVILEGED_AUTHORITY\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('writer creates the exact version-addressed terminal anchor once', async () => {
  const fixture = await createFixture();
  try {
    const result = invoke(fixture);
    assert.equal(result.status, 0, `stderr=${result.stderr}`);
    assert.equal((await stat(fixture.anchorPath)).nlink, 1);
    assert.equal((await stat(fixture.anchorPath)).mode & 0o777, 0o444);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('writer exact-existing accepts only byte-identical anchor with original claim', async () => {
  const fixture = await createFixture();
  try {
    assert.equal(invoke(fixture).status, 0);
    const before = await readFile(fixture.anchorPath);
    const second = invoke(fixture);
    assert.equal(second.status, 0);
    assert.deepEqual(await readFile(fixture.anchorPath), before);
    assert.match(second.stdout, /status=EXISTS_VERIFIED/);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('writer refuses a divergent existing anchor without overwrite', async () => {
  const fixture = await createFixture();
  try {
    assert.equal(invoke(fixture).status, 0);
    await chmod(fixture.anchorPath, 0o600);
    await writeFile(fixture.anchorPath, '{"divergent":true}\n');
    const second = invoke(fixture);
    assert.notEqual(second.status, 0);
    assert.equal(await readFile(fixture.anchorPath, 'utf8'), '{"divergent":true}\n');
  } finally {
    await cleanupFixture(fixture);
  }
});

test('writer rejects arbitrary output path arguments before filesystem mutation', async () => {
  const fixture = await createFixture();
  try {
    const result = invoke(fixture, ['/tmp/arbitrary-anchor']);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR MODE_INVALID\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('production promotion helper performs one dirfd-relative exclusive directory rename', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-writer-promote-'));
  const staging = path.join(root, '.staging-generation');
  const finalRoot = path.join(root, 'remote-generation');
  try {
    await mkdir(staging, { mode: 0o700 });
    for (const name of ['mobile-staging-config.json', 'synthetic-patient.credentials.json', 'local-bridge.receipt.json']) {
      await writeFile(path.join(staging, name), `${name}\n`, { mode: 0o600 });
    }
    const before = await stat(staging);
    const result = spawnSync(requireBuild(), ['--promote-directory', staging, finalRoot], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 15000,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'PROMOTE PASS\n');
    const after = await stat(finalRoot);
    assert.equal(String(after.ino), String(before.ino));
    await assert.rejects(lstat(staging), (error) => error?.code === 'ENOENT');
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('production promotion helper preserves staging when destination wins the no-clobber race', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-writer-promote-race-'));
  const staging = path.join(root, '.staging-generation');
  const finalRoot = path.join(root, 'remote-generation');
  try {
    await mkdir(staging, { mode: 0o700 });
    await mkdir(finalRoot, { mode: 0o700 });
    const result = spawnSync(requireBuild(), ['--promote-directory', staging, finalRoot], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 15000,
    });
    assert.notEqual(result.status, 0);
    assert.ok((await stat(staging)).isDirectory());
    assert.ok((await stat(finalRoot)).isDirectory());
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-8 authorized Swift helper performs descriptor-relative read and exclusive create without an extra runtime', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-writer-descriptor-'));
  try {
    await mkdir(path.join(root, 'authority'), { mode: 0o700 });
    await mkdir(path.join(root, 'authority', 'runtime'), { mode: 0o700 });
    await writeFile(path.join(root, 'authority', 'runtime', 'node'), 'synthetic-node', { mode: 0o600 });
    const invokeDescriptor = (request) => spawnSync(requireBuild(), ['--descriptor-transaction'], {
      input: Buffer.from(JSON.stringify(request)), encoding: 'utf8',
      env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' }, timeout: 15000,
    });
    const common = {
      schema_version: 1, purpose: 'CI3_DESCRIPTOR_RELATIVE_TRANSACTION_V1', root,
      expected_uid: process.getuid(), expected_gid: process.getgid(),
      allowed_directory_modes: [0o700], require_immutable: false, make_immutable: false,
    };
    const read = invokeDescriptor({
      ...common, operation: 'read', relative_path: 'authority/runtime/node',
      expected_mode: 0o600, bytes_base64: '',
    });
    assert.equal(read.status, 0, read.stderr);
    assert.equal(Buffer.from(JSON.parse(read.stdout).bytes_base64, 'base64').toString(), 'synthetic-node');
    const createRequest = {
      ...common, operation: 'create-exclusive', relative_path: 'authority/pass.json',
      expected_mode: 0o600, bytes_base64: Buffer.from('synthetic-pass').toString('base64'),
    };
    const created = invokeDescriptor(createRequest);
    assert.equal(created.status, 0, created.stderr);
    assert.equal(await readFile(path.join(root, 'authority', 'pass.json'), 'utf8'), 'synthetic-pass');
    const collision = invokeDescriptor(createRequest);
    assert.notEqual(collision.status, 0);
    assert.match(collision.stderr, /^ERROR DESCRIPTOR_NO_CLOBBER\n$/);
    await symlink(path.join(root, 'authority', 'runtime'), path.join(root, 'linked-runtime'));
    const linked = invokeDescriptor({
      ...common, operation: 'read', relative_path: 'linked-runtime/node',
      expected_mode: 0o600, bytes_base64: '',
    });
    assert.notEqual(linked.status, 0);
    assert.match(linked.stderr, /^ERROR DESCRIPTOR_CHAIN\n$/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

const REQUIRED_MANIFEST_FIELDS = Object.freeze([
  'schema_version', 'purpose', 'authority_sha', 'authority_tree', 'authority_manifest_sha256',
  'bootstrap_claim_sha256', 'claim_result_chain_sha256', 'remote_bundle_sha256',
  'local_bundle_sha256', 'ssh_provenance_sha256', 'simulator_gate_sha256',
  'simulator_install_sha256', 'writer_authority_path_sha256',
  'components', 'writer_source_sha256', 'writer_binary_sha256', 'writer_signature_sha256',
  'generations', 'evidence', 'scan_receipts', 'terminal_settlement_contracts', 'important_finding_ids',
]);

for (const field of REQUIRED_MANIFEST_FIELDS) {
  test(`writer rejects manifest missing required field ${field}`, async () => {
    await expectFixtureFailure({ mutateManifest: (manifest) => { delete manifest[field]; } });
  });
}

const HASH_FIELDS = Object.freeze([
  'authority_manifest_sha256', 'writer_source_sha256', 'writer_binary_sha256', 'writer_signature_sha256',
]);

for (const field of HASH_FIELDS) {
  test(`writer rejects malformed manifest hash ${field}`, async () => {
    await expectFixtureFailure({ mutateManifest: (manifest) => { manifest[field] = 'bad'; } });
  });
}

for (const role of EVIDENCE_ROLES.slice(0, 9)) {
  test(`writer rejects changed-after-scan evidence ${role}`, async () => {
    await expectFixtureFailure({
      mutateEvidence: async ({ evidence }) => {
        const entry = evidence.find((candidate) => candidate.role === role);
        await writeFile(entry.path, jsonBytes({ changed_after_scan: true }), { mode: 0o600 });
      },
    });
  });
}

for (const scanId of SCAN_IDS) {
  test(`writer rejects missing exact scan ${scanId}`, async () => {
    await expectFixtureFailure({ mutateManifest: (manifest) => { manifest.scan_receipts = manifest.scan_receipts.filter(({ id }) => id !== scanId); } });
  });
}

for (const scanId of SCAN_IDS) {
  test(`writer rejects changed-after-scan receipt ${scanId}`, async () => {
    await expectFixtureFailure({
      mutateEvidence: async ({ scanReceipts }) => {
        const entry = scanReceipts.find(({ id }) => id === scanId);
        await writeFile(entry.path, jsonBytes({ changed_after_scan: true }), { mode: 0o600 });
      },
    });
  });
}

for (const findingId of FINDING_IDS) {
  test(`writer rejects terminal manifest missing finding ${findingId}`, async () => {
    await expectFixtureFailure({ mutateManifest: (manifest) => { manifest.important_finding_ids = manifest.important_finding_ids.filter((id) => id !== findingId); } });
  });
}

for (const generationName of ['remote', 'controller', 'simulator', 'terminal']) {
  test(`writer rejects ${generationName} generation mismatch`, async () => {
    await expectFixtureFailure({ mutateManifest: (manifest) => { manifest.generations[generationName] = `${generationName}-${'0'.repeat(64)}`; } });
  });
}

for (const componentName of ['generator', 'controller', 'launcher', 'writer']) {
  test(`writer rejects missing component ${componentName}`, async () => {
    await expectFixtureFailure({ mutateManifest: (manifest) => { delete manifest.components[componentName]; } });
  });
}

for (const componentName of ['generator', 'controller', 'launcher', 'writer']) {
  for (const field of ['path', 'blob_oid', 'sha256']) {
    test(`writer rejects ${componentName} ${field} drift`, async () => {
      await expectFixtureFailure({ mutateManifest: (manifest) => { manifest.components[componentName][field] = 'bad'; } });
    });
  }
}

const CLAIM_MUTATIONS = Object.freeze([
  ['purpose', 'WRONG'], ['authority_sha', '0'.repeat(40)], ['terminal_generation_id', `terminal-${'0'.repeat(64)}`],
  ['terminal_manifest_sha256', '0'.repeat(64)], ['writer_source_sha256', '0'.repeat(64)],
  ['writer_binary_sha256', '0'.repeat(64)], ['anchor_path_sha256', '0'.repeat(64)],
  ['attempt', 2], ['retry', true], ['normal_executor_authorized', true],
]);

for (const [field, replacement] of CLAIM_MUTATIONS) {
  test(`writer rejects privileged claim mutation ${field}`, async () => {
    await expectFixtureFailure({ mutateClaim: (claim) => { claim[field] = replacement; } });
  });
}

test('writer rejects symlinked terminal receipt evidence', async () => {
  await expectFixtureFailure({
    mutateEvidence: async ({ evidence }) => {
      const entry = evidence.find(({ role }) => role === 'terminal-receipt');
      await rm(entry.path);
      await symlink('/dev/null', entry.path);
    },
  });
});

test('writer rejects hardlinked terminal receipt evidence', async () => {
  await expectFixtureFailure({
    mutateEvidence: async ({ evidence }) => {
      const entry = evidence.find(({ role }) => role === 'terminal-receipt');
      await link(entry.path, `${entry.path}.hardlink`);
    },
  });
});

test('writer rejects permissive terminal receipt evidence mode', async () => {
  await expectFixtureFailure({
    mutateEvidence: async ({ evidence }) => {
      const entry = evidence.find(({ role }) => role === 'terminal-receipt');
      await chmod(entry.path, 0o644);
    },
  });
});

test('writer rejects unclaimed exact-existing anchor', async () => {
  const fixture = await createFixture();
  try {
    assert.equal(invoke(fixture).status, 0);
    await rm(fixture.claimPath);
    assert.notEqual(invoke(fixture).status, 0);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('writer rejects a noncanonical anchor relative path', async () => {
  await expectFixtureFailure({ mutateManifest: (manifest) => { manifest.anchor_relative_path = '../pre-anchor.json'; } });
});

test('writer rejects terminal state before scans are complete', async () => {
  await expectFixtureFailure({ mutateManifest: (manifest) => { manifest.terminal_state = 'PRE_TERMINAL'; } });
});

test('writer rejects a manifest that claims raw values', async () => {
  await expectFixtureFailure({ mutateManifest: (manifest) => { manifest.raw_values = true; } });
});

const SENSITIVE_FIELDS = Object.freeze(['origin', 'credential', 'password', 'token', 'authorization', 'service_role']);

for (const field of SENSITIVE_FIELDS) {
  test(`writer rejects sensitive manifest field ${field}`, async () => {
    await expectFixtureFailure({ mutateManifest: (manifest) => { manifest[field] = 'synthetic-sensitive-value'; } });
  });
}

test('round-4 writer emits only a PENDING_VERIFICATION pre-anchor before controller readback', async () => {
  const fixture = await createFixture();
  try {
    const result = invoke(fixture);
    assert.equal(result.status, 0, result.stderr);
    const preAnchor = JSON.parse(await readFile(fixture.anchorPath, 'utf8'));
    assert.equal(preAnchor.purpose, 'CI3_PRE_TERMINAL_ANCHOR_V1');
    assert.equal(preAnchor.terminal_state, 'PENDING_VERIFICATION');
    assert.notEqual(preAnchor.terminal_state, 'TERMINAL_PASS');
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-4 writer rejects a transcript missing independently reopened publisher and VPS issuer roots', async () => {
  const fixture = await createFixture({
    mutateEvidence: async ({ evidence }) => {
      await rewriteEvidenceObject(evidence, 'vps-issuer-authority-root', (object) => {
        object.public_key_sha256 = 'f'.repeat(64);
      });
    },
  });
  try {
    const result = invoke(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR TERMINAL_EXTERNAL_AUTHORITY\n$/);
    await assert.rejects(readFile(fixture.anchorPath), (error) => error?.code === 'ENOENT');
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-4 writer rejects phase observations that omit authority-fixed target paths', async () => {
  const fixture = await createFixture({
    mutateEvidence: async ({ evidence }) => {
      await rewriteEvidenceObject(evidence, 'controller-phase-verify-authority-receipt', (object) => {
        delete object.observation.targets[0].path;
        const { observation_sha256: _old, ...body } = object.observation;
        object.observation.observation_sha256 = sha(compactJsonBytes(body));
      });
    },
  });
  try {
    const result = invoke(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR TERMINAL_PHASE_TARGET\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-5 writer rejects a fully rehashed alternate phase target outside the external authority contract', async () => {
  const fixture = await createFixture({
    mutatePhaseTargets: async ({ phase, targets, evidenceRoot }) => {
      if (phase !== 'VERIFY_AUTHORITY') return;
      const alternatePath = path.join(evidenceRoot, 'alternate-authority-manifest.json');
      const bytes = await readFile(targets[0].path);
      await writeFile(alternatePath, bytes, { mode: 0o600 });
      targets[0].path = alternatePath;
      targets[0].path_sha256 = sha(Buffer.from(alternatePath));
      targets[0].sha256 = sha(bytes);
      targets[0].metadata = await physicalMetadata(alternatePath);
      targets[0].identity_sha256 = await physicalIdentitySha256(alternatePath);
    },
  });
  try {
    const result = invoke(fixture);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^ERROR TERMINAL_PHASE_TARGET\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-4 writer refuses SSH provenance without descriptor public-key and fingerprint-output evidence roots', async () => {
  const fixture = await createFixture({
    mutateEvidence: async ({ evidence }) => {
      await rewriteEvidenceObject(evidence, 'ssh-trust-descriptor', (object) => {
        object.identity_public_key_fingerprint_sha256 = 'f'.repeat(64);
      });
    },
  });
  try {
    const result = invoke(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /^ERROR TERMINAL_SSH_ROOTS\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-5 legacy separate settlement invocation cannot replace the single privileged transaction', async () => {
  const fixture = await createFixture();
  try {
    const preAnchorResult = invoke(fixture);
    assert.equal(preAnchorResult.status, 0, preAnchorResult.stderr);
    const preAnchorBytes = await readFile(fixture.anchorPath);
    const settlementPath = path.join(fixture.anchorRoot, AUTHORITY, GENERATIONS.terminal, 'terminal-settlement.json');
    const settlementBefore = await readFile(settlementPath);
    const settlementManifestPath = path.join(fixture.evidenceRoot, 'terminal-settlement.manifest.json');
    const triples = Object.fromEntries(['invoke_writer', 'verify_anchor'].map((name) => [name, {
      claim_path: path.join(fixture.evidenceRoot, `${name}.claim.json`), claim_sha256: '',
      receipt_path: path.join(fixture.evidenceRoot, `${name}.receipt.json`), receipt_sha256: '',
      result_path: path.join(fixture.evidenceRoot, `${name}.result.json`), result_sha256: '',
    }]));
    for (const [name, triple] of Object.entries(triples)) {
      for (const kind of ['claim', 'receipt', 'result']) {
        const bytes = jsonBytes({ schema_version: 1, purpose: `CI3_SYNTHETIC_${kind.toUpperCase()}_V1`, phase: name.toUpperCase(), raw_values: false });
        await writeFile(triple[`${kind}_path`], bytes, { mode: 0o600 });
        triple[`${kind}_sha256`] = sha(bytes);
      }
    }
    const settlementManifest = {
      schema_version: 1, purpose: 'CI3_TERMINAL_SETTLEMENT_MANIFEST_V1',
      authority_sha: AUTHORITY, terminal_generation_id: GENERATIONS.terminal,
      pre_anchor_path: fixture.anchorPath, pre_anchor_sha256: sha(preAnchorBytes),
      invoke_writer: triples.invoke_writer, verify_anchor: triples.verify_anchor,
      settlement_authority_sha256: sha(jsonBytes(fixture.authorityReceipt)), raw_values: false,
    };
    await writeFile(settlementManifestPath, jsonBytes(settlementManifest), { mode: 0o600 });
    const settled = spawnSync(requireBuild(), [
      '--settle', settlementManifestPath, fixture.authorityReceiptPath, AUTHORITY,
      GENERATIONS.remote, GENERATIONS.controller, GENERATIONS.simulator, GENERATIONS.terminal,
    ], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin', CI3_SYNTHETIC_ANCHOR_ROOT: fixture.anchorRoot },
      timeout: WRITER_INVOCATION_TIMEOUT_MS,
    });
    assert.notEqual(settled.status, 0);
    assert.equal(settled.stdout, '');
    assert.match(settled.stderr, /^ERROR MODE_INVALID\n$/);
    assert.deepEqual(await readFile(settlementPath), settlementBefore);
    const receipt = JSON.parse(settlementBefore);
    assert.equal(receipt.pre_anchor_sha256, sha(preAnchorBytes));
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-5 one privileged --write invocation publishes pending pre-anchor and terminal settlement from one transaction', async () => {
  const fixture = await createFixture();
  try {
    const written = invoke(fixture);
    assert.equal(written.status, 0, written.stderr);
    assert.match(written.stdout, /^WRITER_TRANSACTION PASS status=CREATED pre_anchor_sha256=[a-f0-9]{64} settlement_sha256=[a-f0-9]{64}\n$/);
    const generationRoot = path.join(fixture.anchorRoot, AUTHORITY, GENERATIONS.terminal);
    const preAnchorBytes = await readFile(path.join(generationRoot, 'pre-anchor.json'));
    const settlement = JSON.parse(await readFile(path.join(generationRoot, 'terminal-settlement.json'), 'utf8'));
    assert.equal(settlement.terminal_state, 'TERMINAL_PASS');
    assert.match(settlement.terminal_final_scan_sha256, /^[a-f0-9]{64}$/);
    assert.equal(settlement.pre_anchor_sha256, sha(preAnchorBytes));
    assert.deepEqual(settlement.generations, GENERATIONS);
    assert.match(settlement.terminal_settlement_contracts_sha256, /^[a-f0-9]{64}$/);
    assert.match(settlement.terminal_phase_graph_sha256, /^[a-f0-9]{64}$/);
    for (const phase of ['INVOKE_WRITER', 'VERIFY_ANCHOR']) {
      const prefix = phase.toLowerCase().replaceAll('_', '-');
      for (const kind of ['claim', 'receipt', 'result']) {
        const itemPath = path.join(generationRoot, 'terminal-phases', `${prefix}.${kind}.json`);
        const item = JSON.parse(await readFile(itemPath, 'utf8'));
        assert.equal(item.phase, phase);
        assert.equal(item.raw_values, false);
      }
    }
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-6 privileged transaction scans the final settlement and publishes a COMPLETE marker last', async () => {
  const fixture = await createFixture();
  try {
    const written = invoke(fixture);
    assert.equal(written.status, 0, written.stderr);
    const generationRoot = path.join(fixture.anchorRoot, AUTHORITY, GENERATIONS.terminal);
    const scanBytes = await readFile(path.join(generationRoot, 'terminal-final-scan.json'));
    const complete = JSON.parse(await readFile(path.join(generationRoot, 'complete-result.json'), 'utf8'));
    const completeScan = JSON.parse(await readFile(path.join(generationRoot, 'complete-final-scan.json'), 'utf8'));
    const settlementBytes = await readFile(path.join(generationRoot, 'terminal-settlement.json'));
    assert.equal(complete.purpose, 'CI3_TERMINAL_COMPLETE_RESULT_V1');
    assert.equal(complete.terminal_state, 'COMPLETE');
    assert.equal(complete.terminal_final_scan_sha256, sha(scanBytes));
    assert.equal(complete.terminal_settlement_sha256, sha(settlementBytes));
    assert.equal(complete.raw_values, false);
    assert.deepEqual(completeScan.surface_roles, ['complete-result']);
    assert.equal(completeScan.input_sha256, sha(await readFile(path.join(generationRoot, 'complete-result.json'))));
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-5 standalone --settle is not a public writer mode after the single privileged transaction', async () => {
  const fixture = await createFixture();
  try {
    const written = invoke(fixture);
    assert.equal(written.status, 0, written.stderr);
    const attemptedSecondInvocation = spawnSync(requireBuild(), [
      '--settle', fixture.manifestPath, fixture.authorityReceiptPath, AUTHORITY,
      GENERATIONS.remote, GENERATIONS.controller, GENERATIONS.simulator, GENERATIONS.terminal,
    ], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin', CI3_SYNTHETIC_ANCHOR_ROOT: fixture.anchorRoot },
      timeout: WRITER_INVOCATION_TIMEOUT_MS,
    });
    assert.notEqual(attemptedSecondInvocation.status, 0);
    assert.equal(attemptedSecondInvocation.stdout, '');
    assert.match(attemptedSecondInvocation.stderr, /^ERROR MODE_INVALID\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-5 exact-existing transaction reopens every privileged terminal phase object before returning PASS', async () => {
  const fixture = await createFixture();
  try {
    const first = invoke(fixture);
    assert.equal(first.status, 0, first.stderr);
    const generationRoot = path.join(fixture.anchorRoot, AUTHORITY, GENERATIONS.terminal);
    const invokeResultPath = path.join(generationRoot, 'terminal-phases', 'invoke-writer.result.json');
    await chmod(invokeResultPath, 0o600);
    const rewritten = JSON.parse(await readFile(invokeResultPath, 'utf8'));
    rewritten.physical_observation_sha256 = '0'.repeat(64);
    await writeFile(invokeResultPath, jsonBytes(rewritten), { mode: 0o600 });
    const second = invoke(fixture);
    assert.notEqual(second.status, 0);
    assert.equal(second.stdout, '');
    assert.match(second.stderr, /^ERROR TERMINAL_SETTLEMENT\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
});

for (const field of ['receipt_sha256', 'config_sha256', 'credential_sha256']) {
  test(`round-6 writer rejects operation-authority remote content drift in ${field}`, async () => {
    const fixture = await createFixture({
      mutateOperationAuthority: (authority) => { authority.context.remote[field] = '0'.repeat(64); },
    });
    try {
      const result = invoke(fixture);
      assert.notEqual(result.status, 0);
      assert.equal(result.stdout, '');
      assert.match(result.stderr, /^ERROR TERMINAL_REMOTE_ROOTS\n$/);
    } finally {
      await cleanupFixture(fixture);
    }
  });
}

const PUBLISHER1_TARGETS = Object.freeze({
  'node-runtime': ['runtime/node', 0o555],
  controller: ['runtime/ci3-bridge-controller.mjs', 0o555],
  'launcher-runtime': ['runtime/ci3-bridge-launcher.zsh', 0o555],
  'launcher-bootstrap-authority': ['runtime/launcher-bootstrap.authority.v1', 0o444],
  'launch-attestation': ['runtime/launch-attestation.json', 0o444],
  'authority-manifest': ['runtime/authority-manifest.v1', 0o444],
  'operation-authority': ['mac-operation-authority.v1.json', 0o444],
  'human-authorization': ['human-authorization.receipt.json', 0o444],
  'vps-pass': ['vps-operation-authority.pass.json', 0o444],
  'vps-issuer-authority': ['vps-issuer-authority.receipt.json', 0o444],
  'publisher-input-manifest': ['publisher-input.manifest.json', 0o444],
  'ssh-config': [`ssh-snapshots/${GENERATIONS.controller}/ssh_config`, 0o444],
  'ssh-known-hosts': [`ssh-snapshots/${GENERATIONS.controller}/known_hosts`, 0o444],
  'ssh-private-key': [`ssh-snapshots/${GENERATIONS.controller}/id_ed25519`, 0o400],
  'ssh-public-key': [`ssh-snapshots/${GENERATIONS.controller}/id_ed25519.pub`, 0o444],
  'ssh-trust-descriptor': [`ssh-snapshots/${GENERATIONS.controller}/trust-descriptor.json`, 0o444],
});

test('round-9 single privileged write publishes the fixed terminal PASS marker and output frames last', async () => {
  const fixture = await createFixture();
  try {
    const result = invoke(fixture);
    assert.equal(result.status, 0, result.stderr);
    const terminalRoot = path.dirname(fixture.anchorPath);
    const markerPath = path.join(terminalRoot, 'terminal-pass.marker.json');
    const stdoutPath = path.join(terminalRoot, 'controller-stdout.final.frame');
    const stderrPath = path.join(terminalRoot, 'controller-stderr.final.frame');
    const journalPath = path.join(terminalRoot, 'controller-journal.final.frame');
    const marker = JSON.parse(await readFile(markerPath, 'utf8'));
    const stdoutBytes = await readFile(stdoutPath);
    const stderrBytes = await readFile(stderrPath);
    const journalBytes = await readFile(journalPath);
    assert.equal(marker.purpose, 'CI3_PRIVILEGED_TERMINAL_PASS_MARKER_V1');
    assert.equal(marker.authority_sha, AUTHORITY);
    assert.deepEqual(marker.generations, GENERATIONS);
    assert.equal(marker.controller_sha256, components().controller.sha256);
    assert.equal(marker.launcher_sha256, components().launcher.sha256);
    assert.equal(marker.stdout_sha256, sha(stdoutBytes));
    assert.equal(marker.stderr_sha256, sha(stderrBytes));
    assert.equal(marker.journal_frame_sha256, sha(journalBytes));
    assert.equal(marker.normal_executor_authorized, false);
    assert.equal(marker.receipt_is_commit_marker, true);
    assert.equal(marker.terminal_state, 'TERMINAL_PASS');
    assert.equal(stdoutBytes.toString('utf8'), 'CONTROLLER RESUME TERMINAL_PASS state=TERMINAL_PASS raw_values=false\n');
    assert.equal(stderrBytes.length, 0);
    const markerStat = await stat(markerPath, { bigint: true });
    for (const framePath of [stdoutPath, stderrPath, journalPath]) {
      assert.ok(markerStat.mtimeNs >= (await stat(framePath, { bigint: true })).mtimeNs);
    }
  } finally {
    await cleanupFixture(fixture);
  }
});

test('round-11 privileged terminal artifact and freeze crashes recover the same marker without divergence', async () => {
  for (const boundary of ['COMPLETE_FINAL_SCAN', 'FINAL_FRAMES', 'MARKER_READBACK', 'DIRECTORY_FREEZE']) {
    const fixture = await createFixture();
    try {
      const recovered = invoke(fixture, [], { CI3_SYNTHETIC_TERMINAL_CRASH_AFTER: boundary });
      assert.equal(recovered.status, 0, `${boundary}: ${recovered.stderr}`);
      assert.equal(recovered.stderr, '');
      assert.match(recovered.stdout, /^WRITER_TRANSACTION PASS status=(?:CREATED|EXISTS_VERIFIED) /);
      const terminalRoot = path.dirname(fixture.anchorPath);
      const markerPath = path.join(terminalRoot, 'terminal-pass.marker.json');
      const marker = JSON.parse(await readFile(markerPath, 'utf8'));
      assert.equal(marker.terminal_state, 'TERMINAL_PASS');
      assert.equal(marker.receipt_is_commit_marker, true);
      assert.equal((await readdir(terminalRoot)).filter((name) => name === 'terminal-pass.marker.json').length, 1);
      assert.equal((await stat(terminalRoot)).mode & 0o777, 0o555);
      const exactExisting = invoke(fixture);
      assert.equal(exactExisting.status, 0, exactExisting.stderr);
      assert.match(exactExisting.stdout, /^WRITER_TRANSACTION PASS status=EXISTS_VERIFIED /);
    } finally {
      await cleanupFixture(fixture);
    }
  }
});

test('round-12 privileged claim adopts an exact 0444 anchor interrupted immediately around immutable flags', async () => {
  for (const boundary of ['BEFORE_FLAGS', 'AFTER_FLAGS']) {
    const fixture = await createFixture();
    try {
      const recovered = invoke(fixture, [], {
        CI3_SYNTHETIC_REAL_IMMUTABLE: '1',
        CI3_SYNTHETIC_WRITE_ANCHOR_CRASH_AFTER: `terminal-pass.marker.json:${boundary}`,
      });
      assert.equal(recovered.status, 0, `${boundary}: ${recovered.stderr}`);
      assert.equal(recovered.stderr, '');
      assert.match(recovered.stdout, /^WRITER_TRANSACTION PASS status=(?:CREATED|EXISTS_VERIFIED) /);
      const markerPath = path.join(path.dirname(fixture.anchorPath), 'terminal-pass.marker.json');
      const flags = spawnSync('/usr/bin/stat', ['-f', '%Sf', markerPath], {
        encoding: 'utf8', env: { PATH: '/usr/bin:/bin' },
      });
      assert.equal(flags.status, 0, flags.stderr);
      assert.match(flags.stdout, /uchg/, `${boundary}: marker must be UF_IMMUTABLE after recovery`);
      const exactExisting = invoke(fixture, [], { CI3_SYNTHETIC_REAL_IMMUTABLE: '1' });
      assert.equal(exactExisting.status, 0, `${boundary}: ${exactExisting.stderr}`);
      assert.match(exactExisting.stdout, /^WRITER_TRANSACTION PASS status=EXISTS_VERIFIED /);
    } finally {
      await cleanupFixture(fixture);
    }
  }
});

test('round-12 exact nonimmutable preexisting anchor remains rejected when its original privileged claim is absent', async () => {
  const fixture = await createFixture();
  try {
    const first = invoke(fixture);
    assert.equal(first.status, 0, first.stderr);
    await rm(fixture.claimPath);
    const denied = invoke(fixture, [], { CI3_SYNTHETIC_REAL_IMMUTABLE: '1' });
    assert.notEqual(denied.status, 0);
    assert.equal(denied.stdout, '');
    assert.match(denied.stderr, /^ERROR PRIVILEGED_CLAIM\n$/);
  } finally {
    await cleanupFixture(fixture);
  }
});

async function publisher1Fixture() {
  const root = await realpath(await mkdtemp(path.join(tmpdir(), 'ci3-round9-publisher1-')));
  const receiverRoot = path.join(root, 'receiver');
  const destinationParent = path.join(root, 'installed');
  const stateRoot = path.join(root, 'state', AUTHORITY, GENERATIONS.controller);
  await mkdir(receiverRoot, { recursive: true, mode: 0o700 });
  await mkdir(destinationParent, { recursive: true, mode: 0o700 });
  await mkdir(stateRoot, { recursive: true, mode: 0o700 });
  const entries = [];
  for (const [role, [relativePath, mode]] of Object.entries(PUBLISHER1_TARGETS)) {
    const sourcePath = path.join(receiverRoot, `${role}.payload`);
    const bytes = Buffer.from(`publisher1:${role}:authenticated\n`);
    await writeFile(sourcePath, bytes, { mode: 0o600 });
    const sourceMetadata = await physicalMetadata(sourcePath);
    entries.push({
      role, source_path: sourcePath, source_sha256: sha(bytes),
      source_path_sha256: sha(Buffer.from(sourcePath)),
      source_uid: sourceMetadata.uid, source_gid: sourceMetadata.gid,
      source_mode: sourceMetadata.mode, source_nlink: sourceMetadata.nlink,
      source_size: sourceMetadata.size, source_mtime_ns: sourceMetadata.mtime_ns,
      source_dev: sourceMetadata.dev, source_ino: sourceMetadata.ino,
      source_identity_sha256: await physicalIdentitySha256(sourcePath),
      destination_relative_path: relativePath, mode,
    });
  }
  const request = {
    schema_version: 1, purpose: 'CI3_PUBLISHER1_DESCRIPTOR_TRANSACTION_V1',
    authority_sha: AUTHORITY, remote_generation_id: GENERATIONS.remote,
    controller_generation_id: GENERATIONS.controller,
    receiver_root: receiverRoot, receiver_manifest_sha256: '1'.repeat(64),
    destination_parent: destinationParent, state_root: stateRoot,
    entries, attempt: 1, retry: false, raw_values: false,
  };
  return { root, receiverRoot, destinationParent, stateRoot, entries, request };
}

async function cleanupPublisher1Fixture(root) {
  const makeWritable = async (directory) => {
    let entries = [];
    try { entries = await readdir(directory, { withFileTypes: true }); } catch { return; }
    await chmod(directory, 0o700).catch(() => undefined);
    for (const entry of entries) {
      if (entry.isDirectory() && !entry.isSymbolicLink()) {
        await makeWritable(path.join(directory, entry.name));
      }
    }
  };
  await makeWritable(root);
  await rm(root, { recursive: true, force: true });
}

function invokePublisher1(request, extraEnvironment = {}) {
  return spawnSync(requireBuild(), ['--publisher1-transaction'], {
    input: compactJsonBytes(request), encoding: 'utf8', timeout: WRITER_INVOCATION_TIMEOUT_MS,
    env: { PATH: '/usr/bin:/bin', ...extraEnvironment },
  });
}

test('round-9 Publisher 1 privileged entrypoint opens one hash-bound request descriptor', async () => {
  const fixture = await publisher1Fixture();
  const requestPath = path.join(fixture.root, 'publisher1.request.json');
  const requestBytes = compactJsonBytes(fixture.request);
  try {
    await writeFile(requestPath, requestBytes, { mode: 0o600 });
    const accepted = spawnSync(requireBuild(), [
      '--publisher1-transaction', requestPath, sha(requestBytes),
    ], {
      encoding: 'utf8', timeout: WRITER_INVOCATION_TIMEOUT_MS,
      env: { PATH: '/usr/bin:/bin' },
    });
    assert.equal(accepted.status, 0, accepted.stderr);
    assert.match(accepted.stdout, /^PUBLISHER1_TRANSACTION PASS status=CREATED effect_executions=1\n$/);

    const rejected = spawnSync(requireBuild(), [
      '--publisher1-transaction', requestPath, '0'.repeat(64),
    ], {
      encoding: 'utf8', timeout: WRITER_INVOCATION_TIMEOUT_MS,
      env: { PATH: '/usr/bin:/bin' },
    });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /^ERROR PUBLISHER1_TRANSACTION\n$/);
  } finally {
    await cleanupPublisher1Fixture(fixture.root);
  }
});

test('round-9 Publisher 1 installs one descriptor-bound tree and exact-existing only reobserves', async () => {
  const fixture = await publisher1Fixture();
  try {
    const created = invokePublisher1(fixture.request);
    assert.equal(created.status, 0, created.stderr);
    assert.match(created.stdout, /^PUBLISHER1_TRANSACTION PASS status=CREATED effect_executions=1\n$/);
    const finalRoot = path.join(fixture.destinationParent, AUTHORITY);
    for (const entry of fixture.entries) {
      assert.equal(sha(await readFile(path.join(finalRoot, entry.destination_relative_path))), entry.source_sha256);
      assert.equal((await lstat(path.join(finalRoot, entry.destination_relative_path))).mode & 0o777, entry.mode);
    }
    for (const directory of [
      finalRoot, path.join(finalRoot, 'runtime'), path.join(finalRoot, 'ssh-snapshots'),
      path.join(finalRoot, 'ssh-snapshots', GENERATIONS.controller),
    ]) assert.equal((await lstat(directory)).mode & 0o777, 0o555);
    const recovered = invokePublisher1(fixture.request);
    assert.equal(recovered.status, 0, recovered.stderr);
    assert.match(recovered.stdout, /^PUBLISHER1_TRANSACTION PASS status=EXISTS_VERIFIED effect_executions=0\n$/);
    assert.deepEqual((await readdir(fixture.stateRoot)).sort(), ['publisher1.claim.json', 'publisher1.result.json']);
    const claim = JSON.parse(await readFile(path.join(fixture.stateRoot, 'publisher1.claim.json'), 'utf8'));
    const result = JSON.parse(await readFile(path.join(fixture.stateRoot, 'publisher1.result.json'), 'utf8'));
    assert.equal(claim.entries.length, 16);
    assert.deepEqual(claim.entries.map(({ source_identity_sha256 }) => source_identity_sha256),
      fixture.entries.map(({ source_identity_sha256 }) => source_identity_sha256));
    assert.deepEqual(result.source_observations, claim.entries.map((entry) => ({
      role: entry.role, source_path_sha256: entry.source_path_sha256,
      source_sha256: entry.sha256, source_uid: entry.source_uid, source_gid: entry.source_gid,
      source_mode: entry.source_mode, source_nlink: entry.source_nlink, source_size: entry.source_size,
      source_mtime_ns: entry.source_mtime_ns, source_dev: entry.source_dev, source_ino: entry.source_ino,
      source_identity_sha256: entry.source_identity_sha256,
    })));
  } finally {
    await cleanupPublisher1Fixture(fixture.root);
  }
});

test('round-11 Publisher 1 rejects a source pathname swap after descriptor authentication and before claim', async () => {
  const fixture = await publisher1Fixture();
  try {
    const result = invokePublisher1(fixture.request, {
      CI3_SYNTHETIC_PUBLISHER1_SWAP_SOURCE_ROLE: 'controller',
    });
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^ERROR PUBLISHER1_SOURCE_DRIFT\n$/);
    await assert.rejects(readFile(path.join(fixture.stateRoot, 'publisher1.claim.json')), { code: 'ENOENT' });
  } finally {
    await cleanupPublisher1Fixture(fixture.root);
  }
});

test('round-9 Publisher 1 recovers a promoted tree without replay after result-boundary crash', async () => {
  const fixture = await publisher1Fixture();
  try {
    const crashed = invokePublisher1(fixture.request, {
      CI3_SYNTHETIC_PUBLISHER1_CRASH_AFTER: 'PROMOTION',
    });
    assert.notEqual(crashed.status, 0);
    assert.equal(crashed.stdout, '');
    assert.match(crashed.stderr, /^ERROR SYNTHETIC_CRASH\n$/);
    const recovered = invokePublisher1(fixture.request);
    assert.equal(recovered.status, 0, recovered.stderr);
    assert.match(recovered.stdout, /^PUBLISHER1_TRANSACTION PASS status=EXISTS_RECOVERED effect_executions=0\n$/);
  } finally {
    await cleanupPublisher1Fixture(fixture.root);
  }
});

test('round-9 Publisher 1 stops when a retained destination ancestor is swapped before promotion', async () => {
  const fixture = await publisher1Fixture();
  try {
    const result = invokePublisher1(fixture.request, {
      CI3_SYNTHETIC_PUBLISHER1_SWAP_DESTINATION: '1',
    });
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^ERROR PUBLISHER1_DESTINATION_DRIFT\n$/);
  } finally {
    await cleanupPublisher1Fixture(fixture.root);
  }
});

test('round-10 production Publisher 1 rejects stdin and requires the exact path plus SHA entrypoint', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round10-prod-entrypoint-'));
  const productionBinary = path.join(root, 'ci3-terminal-anchor-writer-production');
  try {
    const compilation = spawnSync('/usr/bin/xcrun', [
      'swiftc', '-parse-as-library', SOURCE_PATH, '-o', productionBinary,
    ], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 120000 });
    assert.equal(compilation.status, 0, compilation.stderr);
    const rejected = spawnSync(productionBinary, ['--publisher1-transaction'], {
      input: '{}\n', encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: WRITER_INVOCATION_TIMEOUT_MS,
    });
    assert.notEqual(rejected.status, 0);
    assert.equal(rejected.stdout, '');
    assert.match(rejected.stderr, /^ERROR MODE_INVALID\n$/);
    const source = await readFile(SOURCE_PATH, 'utf8');
    assert.doesNotMatch(source, /receiverRoot\.hasSuffix\(/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('round-10 Darwin production-order probe promotes before freezing and reobserves real immutable flags', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'ci3-round10-promotion-probe-'));
  const probeBinary = path.join(root, 'ci3-terminal-anchor-writer-promotion-probe');
  const transactionRoot = path.join(root, 'transaction');
  try {
    const compilation = spawnSync('/usr/bin/xcrun', [
      'swiftc', '-parse-as-library', '-D', 'CI3_DARWIN_PROMOTION_PROBE', SOURCE_PATH, '-o', probeBinary,
    ], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: 120000 });
    assert.equal(compilation.status, 0, compilation.stderr);
    const result = spawnSync(probeBinary, ['--publisher1-promotion-probe', transactionRoot], {
      encoding: 'utf8', env: { PATH: '/usr/bin:/bin' }, timeout: WRITER_INVOCATION_TIMEOUT_MS,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /^PUBLISHER1_PROMOTION_PROBE PASS status=CREATED recovery=EXISTS_VERIFIED no_clobber=REJECTED\n$/);
    const finalRoot = path.join(transactionRoot, 'final');
    assert.equal((await lstat(finalRoot)).mode & 0o777, 0o555);
    assert.match(spawnSync('/usr/bin/stat', ['-f', '%Sf', finalRoot], { encoding: 'utf8' }).stdout, /uchg/);
  } finally {
    spawnSync('/usr/bin/chflags', ['-R', 'nouchg', root], { encoding: 'utf8' });
    await cleanupPublisher1Fixture(root);
  }
});

test('round-11 Publisher 1 rejects wrong source owner or mode before its durable claim', async () => {
  for (const mutation of [
    (entry) => { entry.source_uid += 1; },
    (entry) => { entry.source_gid += 1; },
    (entry) => { entry.source_mode = 0o644; },
  ]) {
    const fixture = await publisher1Fixture();
    try {
      mutation(fixture.request.entries[4]);
      const rejected = invokePublisher1(fixture.request);
      assert.notEqual(rejected.status, 0);
      assert.equal(rejected.stdout, '');
      assert.match(rejected.stderr, /^ERROR PUBLISHER1_SOURCE_AUTHORITY\n$/);
      await assert.rejects(readFile(path.join(fixture.stateRoot, 'publisher1.claim.json')), { code: 'ENOENT' });
    } finally {
      await cleanupPublisher1Fixture(fixture.root);
    }
  }
});

test('round-11 Publisher 1 rejects a same-bytes receiver leaf inode swap before claim', async () => {
  const fixture = await publisher1Fixture();
  try {
    const entry = fixture.request.entries[5];
    const bytes = await readFile(entry.source_path);
    await rename(entry.source_path, `${entry.source_path}.original`);
    await writeFile(entry.source_path, bytes, { mode: 0o600 });
    const rejected = invokePublisher1(fixture.request);
    assert.notEqual(rejected.status, 0);
    assert.equal(rejected.stdout, '');
    assert.match(rejected.stderr, /^ERROR PUBLISHER1_SOURCE_AUTHORITY\n$/);
    await assert.rejects(readFile(path.join(fixture.stateRoot, 'publisher1.claim.json')), { code: 'ENOENT' });
  } finally {
    await cleanupPublisher1Fixture(fixture.root);
  }
});

test('round-11 Publisher 1 rejects a hardlinked receiver leaf before claim', async () => {
  const fixture = await publisher1Fixture();
  try {
    const entry = fixture.request.entries[6];
    await link(entry.source_path, `${entry.source_path}.hardlink`);
    const rejected = invokePublisher1(fixture.request);
    assert.notEqual(rejected.status, 0);
    assert.equal(rejected.stdout, '');
    assert.match(rejected.stderr, /^ERROR PUBLISHER1_SOURCE_AUTHORITY\n$/);
    await assert.rejects(readFile(path.join(fixture.stateRoot, 'publisher1.claim.json')), { code: 'ENOENT' });
  } finally {
    await cleanupPublisher1Fixture(fixture.root);
  }
});

if (FIXTURE_HELPER_MODE) {
  const outputPath = process.env.CI3_SYNTHETIC_FIXTURE_DESCRIPTOR;
  const rootParent = process.env.CI3_SYNTHETIC_FIXTURE_PARENT;
  if (!path.isAbsolute(outputPath ?? '') || !path.isAbsolute(rootParent ?? '')) throw new Error('FIXTURE_HELPER_PATH');
  const protocolStatePath = process.env.CI3_SYNTHETIC_PROTOCOL_STATE_PATH;
  const scenarioId = process.env.CI3_SYNTHETIC_E2E_SCENARIO;
  const scenarioSha256 = process.env.CI3_SYNTHETIC_SCENARIO_SHA256;
  if (!path.isAbsolute(protocolStatePath ?? '') || !scenarioId || !/^[a-f0-9]{64}$/.test(scenarioSha256 ?? '')) {
    throw new Error('FIXTURE_HELPER_PROTOCOL_STATE');
  }
  const fixture = await createFixture({ rootParent, protocolStatePath, scenarioId, scenarioSha256 });
  const protocolEvidencePath = path.join(fixture.evidenceRoot, 'controller-durable-state-root.json');
  const descriptor = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_WRITER_FIXTURE_V1',
    authority: AUTHORITY,
    generations: GENERATIONS,
    root: fixture.root,
    anchor_root: fixture.anchorRoot,
    anchor_path: fixture.anchorPath,
    manifest_path: fixture.manifestPath,
    authority_receipt_path: fixture.authorityReceiptPath,
    evidence_root: fixture.evidenceRoot,
    protocol_state_path_sha256: sha(Buffer.from(protocolStatePath)),
    protocol_state_sha256: sha(await readFile(protocolEvidencePath)),
    raw_values: false,
  };
  await writeFile(outputPath, jsonBytes(descriptor), { flag: 'wx', mode: 0o600 });
}
