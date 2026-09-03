import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync } from 'node:crypto';
import { chmod, lstat, mkdir, mkdtemp, readFile, realpath, rm, symlink, link, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test, { after, before } from 'node:test';
import { fileURLToPath } from 'node:url';

import * as chain from './ci3-external-publisher-chain.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SOURCE = path.join(HERE, 'ci3-publisher1-bootstrap-installer.swift');
const SHA = (bytes) => createHash('sha256').update(bytes).digest('hex');
const AUTHORITY = 'a'.repeat(40);
const GENERATION = `controller-${'b'.repeat(64)}`;
let buildRoot;
let binary;

function canonical(value) {
  const normalize = (candidate) => {
    if (Array.isArray(candidate)) return candidate.map(normalize);
    if (candidate && typeof candidate === 'object') return Object.fromEntries(Object.keys(candidate).sort().map((key) => [key, normalize(candidate[key])]));
    return candidate;
  };
  return Buffer.from(`${JSON.stringify(normalize(value))}\n`);
}

function identity(stat) {
  const metadata = {
    uid: Number(stat.uid), gid: Number(stat.gid), mode: Number(stat.mode & 0o777n), nlink: Number(stat.nlink), size: Number(stat.size),
    mtime_ns: `${stat.mtimeNs}`, dev: `${stat.dev}`, ino: `${stat.ino}`,
  };
  return { ...metadata, identity_sha256: SHA(Buffer.from(`uid=${metadata.uid};gid=${metadata.gid};mode=${metadata.mode};nlink=${metadata.nlink};size=${metadata.size};mtime=${metadata.mtime_ns};dev=${metadata.dev};ino=${metadata.ino}`)) };
}

function buildCanonicalHandoff(writerBytes, installerExpectedBinarySha256, receiverLeafOverrides = null) {
  const bindings = {
    MAC_EXECUTOR_AUTHORITY_SHA: AUTHORITY, MAC_EXECUTOR_AUTHORITY_PARENT: 'e'.repeat(40), MAC_EXECUTOR_AUTHORITY_TREE: 'f'.repeat(40), MAC_EXECUTOR_AUTHORITY_SUBJECT: 'synthetic executor',
    CURRENT_REMOTE_SHA: '1'.repeat(40), CURRENT_REMOTE_PARENT: '2'.repeat(40), CURRENT_REMOTE_TREE: '3'.repeat(40), CURRENT_REMOTE_SUBJECT: 'synthetic remote',
    MAC_OBJECT_BOOTSTRAP_AUTHORITY_SHA: '4'.repeat(40), REMOTE_BUNDLE_AUTHORITY_SHA: '5'.repeat(40), REMOTE_BUNDLE_AUTHORITY_PARENT: '6'.repeat(40), REMOTE_BUNDLE_AUTHORITY_TREE: '7'.repeat(40), REMOTE_BUNDLE_AUTHORITY_SUBJECT: 'synthetic bundle',
    REMOTE_BUNDLE_DOCUMENTATION_SHA: '8'.repeat(40), REMOTE_BUNDLE_GENERATION_ID: `rb-${'9'.repeat(64)}`,
    REMOTE_BUNDLE_RECEIPT_SHA256: 'a'.repeat(64), REMOTE_BUNDLE_CONFIG_SHA256: 'b'.repeat(64), REMOTE_SYNTHETIC_CREDENTIAL_SHA256: 'c'.repeat(64),
    NODE_RUNTIME_V2_CREATION_AUTHORITY_SHA: 'd'.repeat(40), NODE_RUNTIME_V2_ADOPTION_AUTHORITY_SHA: 'e'.repeat(40), CI3_IOS_AUTHORITY_SHA: 'f'.repeat(40), CI2_BASE: '1'.repeat(40), AUTHORITY_BASE: '2'.repeat(40),
  };
  const context = {
    authority: {
      commit: AUTHORITY, parent: 'e'.repeat(40), tree: 'f'.repeat(40), subject_sha256: SHA(Buffer.from('synthetic executor')), manifest_sha256: '2'.repeat(64),
      components: { writer: { sha256: SHA(writerBytes) }, controller: { sha256: '3'.repeat(64) }, launcher: { sha256: '4'.repeat(64) } },
    },
    generations: { remote: `remote-${'5'.repeat(64)}`, controller: GENERATION },
    collector_contracts_sha256: '6'.repeat(64), node_candidate_sha256: '7'.repeat(64), operation_authority_sha256: '8'.repeat(64),
  };
  const receiverRoot = receiverLeafOverrides?.receiverRoot ?? '/private/var/folders/ci3-synthetic/receiver';
  const receiverLeaves = chain.PUBLISHER1_ROLES.map((role, index) => {
    const overridden = receiverLeafOverrides?.leaves?.[role];
    if (overridden) return overridden;
    const pathValue = path.join(receiverRoot, `${role}.payload`);
    const physical = { uid: 501, gid: 20, mode: 0o600, nlink: 1, size: index + 1, mtime_ns: `${1_700_000_000_000_000_000n + BigInt(index)}`, dev: `${100n + BigInt(index)}`, ino: `${1000n + BigInt(index)}` };
    return { role, path: pathValue, path_sha256: chain.sha256(Buffer.from(pathValue)), sha256: String((index % 9) + 1).repeat(64), ...physical, identity_sha256: chain.physicalIdentitySha256(physical) };
  });
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const issuer = chain.buildVpsIssuerAuthority({ authoritySha: AUTHORITY, issuerGenerationId: `issuer-${'9'.repeat(64)}`, publicKey });
  const transport = chain.buildPublisherInputManifest({
    context,
    entries: chain.TRANSPORT_ROLES.map((role, index) => ({ role, path_sha256: String((index % 8) + 1).repeat(64), sha256: String(((index + 2) % 8) + 1).repeat(64) })),
  });
  const pass = chain.signVpsPass({ unsigned: chain.buildUnsignedVpsPass({ context, issuer, publisherInputManifestSha256: chain.sha256(chain.canonicalJson(transport)), transferPayloadSha256: transport.transfer_payload_sha256 }), issuer, privateKey });
  const requestPath = '/private/var/folders/ci3-synthetic/transaction.request.json';
  const requestPhysical = { uid: 501, gid: 20, mode: 0o600, nlink: 1, size: 99, mtime_ns: '1700000000000000099', dev: '199', ino: '1999' };
  const materializer = chain.buildPublisher1MaterializerAuthority({
    context, requestPath, requestSha256: 'a'.repeat(64),
    requestObservation: { role: 'request', path: requestPath, path_sha256: chain.sha256(Buffer.from(requestPath)), sha256: 'a'.repeat(64), ...requestPhysical, identity_sha256: chain.physicalIdentitySha256(requestPhysical) },
    receiverRoot, receiverRootIdentitySha256: 'b'.repeat(64), receiverLeaves,
    issuerAuthoritySha256: chain.sha256(chain.canonicalJson(issuer)), materializerSha256: SHA(writerBytes), writerSourceSha256: SHA(writerBytes),
  });
  const installerProvenance = {
    git_path: 'scripts/ci3/ci3-publisher1-bootstrap-installer.swift', git_blob_oid: '6'.repeat(40),
    source_sha256: '7'.repeat(64), authority_manifest_sha256: context.authority.manifest_sha256,
    compile_authority_sha256: '7'.repeat(64), expected_binary_sha256: installerExpectedBinarySha256,
  };
  const promptSha256 = 'f'.repeat(64);
  const preauthorizationLeaves = receiverLeaves.filter(({ role }) => role !== 'human-authorization');
  const humanAuthorizationRequest = chain.buildHumanAuthorizationRequest({
    context, issuer, manifest: transport, pass, receiverRoot,
    receiverRootIdentitySha256: 'c'.repeat(64), receiverLeaves: preauthorizationLeaves,
    installerProvenance, promptSha256,
  });
  const humanAuthorizationRequestBytes = chain.canonicalJson(humanAuthorizationRequest);
  const humanAuthorizationRequestPath = '/private/var/folders/ci3-synthetic/human-authorization.request.json';
  const humanRequestPhysical = {
    uid: 501, gid: 20, mode: 0o600, nlink: 1, size: humanAuthorizationRequestBytes.length,
    mtime_ns: '1700000000000000100', dev: '200', ino: '2000',
  };
  const humanAuthorizationRequestObservation = {
    role: 'human-authorization-request', path: humanAuthorizationRequestPath,
    path_sha256: chain.sha256(Buffer.from(humanAuthorizationRequestPath)),
    sha256: chain.sha256(humanAuthorizationRequestBytes), ...humanRequestPhysical,
    identity_sha256: chain.physicalIdentitySha256(humanRequestPhysical),
  };
  const humanAuthorization = chain.buildHumanAuthorizationReceipt({
    context, issuer, manifest: transport, pass, authorizationRequest: humanAuthorizationRequest,
    authorizationRequestObservation: humanAuthorizationRequestObservation,
    receiverRoot, receiverRootIdentitySha256: 'c'.repeat(64), receiverLeaves: preauthorizationLeaves,
    installerProvenance, promptSha256,
    confirmation: { authorized_uid: 501, authorized_gid: 20, prompt_budget: 1, confirmation_sha256: '9'.repeat(64) },
  });
  return chain.buildPublisher1BootstrapHandoff({
    bindings, context,
    gate0Receipt: {
      schema_version: 2, purpose: 'CI3_SEMANTIC_SAFE_MAC_GATE0_V2', authority_sha: AUTHORITY,
      authority_manifest_sha256: context.authority.manifest_sha256, launcher_sha256: context.authority.components.launcher.sha256,
      exit_code: 0, stdout_bytes: 0, stderr_bytes: 0, status: 'PASS', raw_values: false,
    },
    issuer, pass, transportManifest: transport, humanAuthorization,
    humanAuthorizationRequest, humanAuthorizationRequestObservation, installerProvenance, promptSha256,
    materializerAuthority: materializer, receiverRoot, receiverRootIdentitySha256: 'b'.repeat(64), receiverLeaves,
  });
}

async function createFixture(label) {
  const root = await realpath(await mkdtemp(path.join(await realpath(tmpdir()), `ci3-publisher1-installer-${label}-`)));
  const sourceRoot = path.join(root, 'sources');
  const installBase = path.join(root, 'install-base');
  const stateBase = path.join(root, 'state-base');
  await mkdir(sourceRoot, { mode: 0o700 });
  await mkdir(installBase, { mode: 0o700 });
  await mkdir(stateBase, { mode: 0o700 });
  const writerBytes = Buffer.from('#!/bin/sh\nexit 0\n');
  const launcherSourceSpecs = [
    ['node-runtime', 'runtime/node', 0o555, Buffer.from('synthetic-bootstrap-node\n')],
    ['controller', 'runtime/ci3-bridge-controller.mjs', 0o555, Buffer.from('synthetic-bootstrap-controller\n')],
    ['launcher-runtime', 'runtime/ci3-bridge-launcher.zsh', 0o555, Buffer.from('synthetic-bootstrap-launcher\n')],
    ['launcher-bootstrap-authority', 'runtime/launcher-bootstrap.authority.v1', 0o444, Buffer.from('synthetic-bootstrap-launcher-authority\n')],
    ['launch-attestation', 'runtime/launch-attestation.json', 0o444, Buffer.from('synthetic-bootstrap-attestation\n')],
    ['authority-manifest', 'runtime/authority-manifest.v1', 0o444, Buffer.from('synthetic-bootstrap-manifest\n')],
  ];
  const launcherLeaves = {};
  for (const [role, _destination, _mode, bytes] of launcherSourceSpecs) {
    const source = path.join(sourceRoot, `${role}.payload`);
    await writeFile(source, bytes, { flag: 'wx', mode: 0o600 });
    const observed = identity(await lstat(source, { bigint: true }));
    launcherLeaves[role] = {
      role, path: source, path_sha256: SHA(Buffer.from(source)), sha256: SHA(bytes),
      uid: Number(observed.uid), gid: Number(observed.gid), mode: Number(observed.mode),
      nlink: Number(observed.nlink), size: Number(observed.size), mtime_ns: observed.mtime_ns,
      dev: observed.dev, ino: observed.ino, identity_sha256: observed.identity_sha256,
    };
  }
  const handoff = buildCanonicalHandoff(writerBytes, SHA(await readFile(binary)), {
    receiverRoot: sourceRoot, leaves: launcherLeaves,
  });
  const sourceSpecs = [
    ['materializer-authority', 'publisher1-materializer.authority.json', 0o444, chain.canonicalJson(handoff.materializer_authority)],
    ['issuer-receipt', 'vps-issuer-authority.receipt.json', 0o444, chain.canonicalJson(handoff.issuer)],
    ['writer-binary', 'runtime/ci3-terminal-anchor-writer', 0o555, writerBytes],
    ...launcherSourceSpecs,
  ];
  const entries = [];
  for (const [role, destination, mode, bytes] of sourceSpecs) {
    const source = path.join(sourceRoot, `${role}.payload`);
    if (!launcherLeaves[role]) await writeFile(source, bytes, { flag: 'wx', mode: role === 'writer-binary' ? 0o500 : 0o600 });
    const observed = identity(await lstat(source, { bigint: true }));
    entries.push({
      role, source_path: source, source_path_sha256: SHA(Buffer.from(source)), source_sha256: SHA(bytes),
      source_uid: Number(observed.uid), source_gid: Number(observed.gid), source_mode: Number(observed.mode),
      source_nlink: Number(observed.nlink), source_size: Number(observed.size), source_mtime_ns: observed.mtime_ns,
      source_dev: observed.dev, source_ino: observed.ino, source_identity_sha256: observed.identity_sha256,
      destination_relative_path: destination, mode,
    });
  }
  const destinationRoot = path.join(
    installBase, AUTHORITY, `bootstrap-${handoff.authority_projection.authority_manifest_sha256}`,
  );
  const stateRoot = path.join(stateBase, AUTHORITY, GENERATION);
  const request = {
    schema_version: 2, purpose: 'CI3_PUBLISHER1_BOOTSTRAP_INSTALL_REQUEST_V2',
    authority_sha: AUTHORITY, controller_generation_id: GENERATION,
    destination_root: destinationRoot, state_root: stateRoot, handoff, entries,
    attempt: 1, retry: false, raw_values: false,
  };
  const requestBytes = canonical(request);
  const requestPath = path.join(root, 'publisher1-bootstrap.request.json');
  const frozenProjectionPath = path.join(root, 'frozen-authority-projection.json');
  await writeFile(requestPath, requestBytes, { flag: 'wx', mode: 0o600 });
  await writeFile(frozenProjectionPath, canonical(handoff.authority_projection), { flag: 'wx', mode: 0o600 });
  return { root, sourceRoot, installBase, stateBase, destinationRoot, stateRoot, request, requestBytes, requestPath, frozenProjectionPath };
}

async function createImmutableBootstrapFixture(label) {
  const fixture = await createFixture(`immutable-${label}`);
  const installerBase = path.join(fixture.root, 'installer-base');
  await mkdir(installerBase, { mode: 0o700 });
  const installerBytes = await readFile(binary);
  const installerCompileAuthoritySha256 = '7'.repeat(64);
  const installerExpectedBinarySha256 = SHA(installerBytes);
  const preflightReceipt = {
    schema_version: 1, purpose: 'CI3_PUBLISHER1_SEMANTIC_PREFLIGHT_RECEIPT_V1', authority_sha: AUTHORITY,
    remote_generation_id: fixture.request.handoff.remote_generation_id, controller_generation_id: GENERATION,
    bootstrap_request_sha256: SHA(fixture.requestBytes), descriptor_request_sha256: '1'.repeat(64),
    descriptor_request_identity_sha256: '2'.repeat(64), receiver_root_path_sha256: '3'.repeat(64),
    receiver_root_identity_sha256: '4'.repeat(64), validation_binary_sha256: '5'.repeat(64),
    semantic_sources_sha256: '6'.repeat(64),
    publisher_installer_compile_authority_sha256: installerCompileAuthoritySha256,
    publisher_installer_expected_binary_sha256: installerExpectedBinarySha256,
    status: 'PASS', writes_performed: 0, effect_executions: 0,
    network_calls: 0, privilege_prompts: 0, attempt: 1, retry: false, raw_values: false,
  };
  const preflightReceiptBytes = canonical(preflightReceipt);
  const preflightReceiptPath = path.join(fixture.root, 'publisher1-semantic-preflight.receipt.json');
  await writeFile(preflightReceiptPath, preflightReceiptBytes, { flag: 'wx', mode: 0o600 });
  const requestMetadata = identity(await lstat(fixture.requestPath, { bigint: true }));
  const preflightMetadata = identity(await lstat(preflightReceiptPath, { bigint: true }));
  const installerRoot = path.join(installerBase, AUTHORITY, GENERATION);
  const envelope = {
    schema_version: 1, purpose: 'PUBLISHER1_IMMUTABLE_INSTALLER_BOOTSTRAP_V1', authority_sha: AUTHORITY,
    controller_generation_id: GENERATION,
    bootstrap_request_path: fixture.requestPath, bootstrap_request_path_sha256: SHA(Buffer.from(fixture.requestPath)),
    bootstrap_request_sha256: SHA(fixture.requestBytes), bootstrap_request_identity_sha256: requestMetadata.identity_sha256,
    bootstrap_request_uid: requestMetadata.uid, bootstrap_request_gid: requestMetadata.gid,
    semantic_preflight_receipt_path: preflightReceiptPath,
    semantic_preflight_receipt_path_sha256: SHA(Buffer.from(preflightReceiptPath)),
    semantic_preflight_receipt_sha256: SHA(preflightReceiptBytes),
    semantic_preflight_receipt_identity_sha256: preflightMetadata.identity_sha256,
    semantic_preflight_receipt_uid: preflightMetadata.uid, semantic_preflight_receipt_gid: preflightMetadata.gid,
    installer_compile_authority_sha256: installerCompileAuthoritySha256,
    installer_expected_binary_sha256: installerExpectedBinarySha256,
    installer_sha256: installerExpectedBinarySha256, installer_root: installerRoot,
    attempt: 1, retry: false, raw_values: false,
  };
  const envelopeBytes = canonical(envelope);
  const envelopePath = path.join(fixture.root, 'publisher1-immutable-installer.request.json');
  await writeFile(envelopePath, envelopeBytes, { flag: 'wx', mode: 0o600 });
  return {
    ...fixture, installerBase, installerRoot, installerBytes, preflightReceipt, preflightReceiptBytes,
    preflightReceiptPath, envelope, envelopeBytes, envelopePath,
  };
}

function immutableEnvironment(fixture, extra = {}) {
  return {
    HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin',
    CI3_SYNTHETIC_INSTALL_BASE: fixture.installBase,
    CI3_SYNTHETIC_STATE_BASE: fixture.stateBase,
    CI3_SYNTHETIC_INSTALLER_BASE: fixture.installerBase,
    CI3_SYNTHETIC_FROZEN_PROJECTION_PATH: fixture.frozenProjectionPath,
    ...extra,
  };
}

function invokeImmutablePhaseA(fixture, extra = {}) {
  return spawnSync(binary, ['--immutable-bootstrap-phase-a', fixture.envelopePath, SHA(fixture.envelopeBytes)], {
    encoding: 'utf8', env: immutableEnvironment(fixture, extra), timeout: 10_000, maxBuffer: 64 * 1024,
  });
}

function invokeMutablePhaseB(fixture, extra = {}) {
  return spawnSync(binary, ['--immutable-bootstrap-phase-b', fixture.envelopePath, SHA(fixture.envelopeBytes)], {
    encoding: 'utf8', env: immutableEnvironment(fixture, extra), timeout: 10_000, maxBuffer: 64 * 1024,
  });
}

async function createLocalPrepareFixture(label) {
  const root = await realpath(await mkdtemp(path.join(await realpath(tmpdir()), `ci3-local-prepare-${label}-`)));
  const candidateRoot = path.join(root, AUTHORITY, 'candidates');
  const request = {
    schema_version: 1, purpose: 'CI3_PUBLISHER1_LOCAL_PREPARE_V1', authority_sha: AUTHORITY,
    controller_generation_id: GENERATION, candidate_root: candidateRoot,
    candidates: chain.PREPARE_CANDIDATE_ROLES.map((role, index) => ({ role, bytes_base64: Buffer.from(`synthetic-${index}\n`).toString('base64') })),
    prompt_sha256: 'f'.repeat(64), attempt: 1, retry: false, raw_values: false,
  };
  const bytes = canonical(request);
  const requestPath = path.join(root, 'publisher1.local-prepare.json');
  await writeFile(requestPath, bytes, { flag: 'wx', mode: 0o600 });
  return { root, candidateRoot, requestPath, bytes };
}

function invoke(fixture, extraEnvironment = {}, request = fixture.request, requestBytes = canonical(request)) {
  if (!requestBytes.equals(fixture.requestBytes)) {
    const replacement = path.join(fixture.root, `request-${Math.random().toString(16).slice(2)}.json`);
    const created = spawnSync('/usr/bin/env', ['python3', '-c', 'import os,sys; p=sys.argv[1]; d=sys.stdin.buffer.read(); fd=os.open(p, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600); os.write(fd,d); os.fsync(fd); os.close(fd)', replacement], { input: requestBytes });
    assert.equal(created.status, 0);
    return spawnSync(binary, ['--install', replacement, SHA(requestBytes)], {
      encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin', CI3_SYNTHETIC_INSTALL_BASE: fixture.installBase, CI3_SYNTHETIC_STATE_BASE: fixture.stateBase, CI3_SYNTHETIC_FROZEN_PROJECTION_PATH: fixture.frozenProjectionPath, ...extraEnvironment },
      timeout: 10_000, maxBuffer: 64 * 1024,
    });
  }
  return spawnSync(binary, ['--install', fixture.requestPath, SHA(fixture.requestBytes)], {
    encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin', CI3_SYNTHETIC_INSTALL_BASE: fixture.installBase, CI3_SYNTHETIC_STATE_BASE: fixture.stateBase, CI3_SYNTHETIC_FROZEN_PROJECTION_PATH: fixture.frozenProjectionPath, ...extraEnvironment },
    timeout: 10_000, maxBuffer: 64 * 1024,
  });
}

async function cleanup(root) {
  spawnSync('/usr/bin/chflags', ['-R', 'nouchg', root], { stdio: 'ignore' });
  spawnSync('/bin/chmod', ['-R', 'u+rwX', root], { stdio: 'ignore' });
  await rm(root, { recursive: true, force: true });
}

before(async () => {
  buildRoot = await realpath(await mkdtemp(path.join(await realpath(tmpdir()), 'ci3-publisher1-installer-build-')));
  binary = path.join(buildRoot, 'ci3-publisher1-bootstrap-installer');
  const compiled = spawnSync('/usr/bin/swiftc', ['-D', 'CI3_SYNTHETIC_TEST', SOURCE, '-o', binary], { encoding: 'utf8', timeout: 120_000, maxBuffer: 1024 * 1024 });
  assert.equal(compiled.status, 0, `${compiled.stdout}\n${compiled.stderr}`);
});

after(async () => { if (buildRoot) await cleanup(buildRoot); });

function productionFrozenInputs() {
  const order = [
    'AUTHORITY_PUBLISHED', 'GATE0_PASS', 'FRESH_OOB_RECEIPT',
    'AUTHENTICATED_SSH_RECEIPT', 'MAC_NODE_CAPSULE', 'MATERIALIZED_53_OF_53',
    'FROZEN_CORPUS', 'PUBLISHER0', 'PUBLISHER1', 'CONTROLLER_AUTHORITY',
  ];
  return {
    schema_version: 1, purpose: 'CI3_PRODUCTION_FROZEN_INPUT_CONSUMER_BINDING_V1',
    constructor_claim_sha256: '1'.repeat(64), corpus_sha256: '2'.repeat(64),
    authorized_producer_matrix_sha256: '3'.repeat(64), materialized_input_matrix_sha256: '4'.repeat(64),
    oob_receipt_sha256: '5'.repeat(64), authenticated_ssh_receipt_sha256: '6'.repeat(64),
    vps_node_reference_sha256: '7'.repeat(64), mac_node_capsule_receipt_sha256: '8'.repeat(64),
    requirements_total: 53, requirements_verified: 53,
    vps_runtime_role: 'VPS_BOOTSTRAP_NODE_RUNTIME', mac_runtime_role: 'MAC_EXECUTOR_NODE_RUNTIME',
    causal_order_sha256: SHA(Buffer.from(`${JSON.stringify(order)}\n`)), raw_values: false,
  };
}

async function addCapsuleTopology(fixture, request) {
  request.handoff.purpose = 'CI3_PUBLISHER1_BOOTSTRAP_HANDOFF_V3';
  request.entries[3].destination_relative_path = 'runtime/node-capsule/capsule/bin/node';
  const imageBytes = Buffer.from('synthetic-capsule-image\n');
  const image = { destination: 'lib/0123456789abcdef-libx.dylib', sha256: SHA(imageBytes) };
  const manifest = {
    schema_version: 2, purpose: 'MAC_RELOCATABLE_NODE_CAPSULE_V2', authority: AUTHORITY,
    generation: 'capsule-v2', role: 'MAC_EXECUTOR_NODE_RUNTIME',
    predecessor_authority: 'd'.repeat(40), predecessor_generation: 'generation-v1',
    predecessor_status: 'FAILED_PARTIAL_PRESERVED', predecessor_attempts: '1/1_CONSUMED',
    predecessor_retry: false, predecessor_cleanup: false, predecessor_adoption: false,
    plan: { fixed: true }, source_hash: 'c'.repeat(64),
    capsule: { executable_sha256: request.entries[3].source_sha256, images: [image] },
  };
  const manifestBytes = canonical(manifest);
  const receipt = {
    schema_version: 2, purpose: 'MAC_RELOCATABLE_NODE_CAPSULE_V2', authority: AUTHORITY,
    generation: 'capsule-v2', role: 'MAC_EXECUTOR_NODE_RUNTIME', platform: 'darwin', architecture: 'arm64',
    version: 'v22.1.0', source_identity_hash: '1'.repeat(64), closure_hash: '2'.repeat(64),
    relocation_plan_hash: '3'.repeat(64), move_probes: '2/2_PASS', loader_probes: '2/2_PASS',
    copied_non_system_images_consumed: true, source_authority: 'b'.repeat(40),
    predecessor_authority: 'd'.repeat(40), predecessor_generation: 'generation-v1',
    predecessor_status: 'FAILED_PARTIAL_PRESERVED', predecessor_attempts: '1/1_CONSUMED',
    predecessor_retry: false, predecessor_cleanup: false, predecessor_adoption: false,
    manifest_sha256: SHA(manifestBytes),
    capsule_executable_sha256: manifest.capsule.executable_sha256,
    capsule_images_sha256: SHA(canonical(manifest.capsule.images)),
    attempts: 1, retry: false, raw_path: false,
  };
  const receiptBytes = canonical(receipt);
  request.handoff.production_frozen_inputs = {
    ...productionFrozenInputs(), mac_node_capsule_receipt_sha256: SHA(receiptBytes),
  };
  const append = async (role, destination, bytes, sourceMode, mode) => {
    const source = path.join(fixture.sourceRoot, `${role}.payload`);
    try { await writeFile(source, bytes, { flag: 'wx', mode: sourceMode }); }
    catch (error) {
      if (error?.code !== 'EEXIST' || !(await readFile(source)).equals(bytes)) throw error;
    }
    const observed = identity(await lstat(source, { bigint: true }));
    request.entries.push({
      role, source_path: source, source_path_sha256: SHA(Buffer.from(source)), source_sha256: SHA(bytes),
      source_uid: Number(observed.uid), source_gid: Number(observed.gid), source_mode: Number(observed.mode),
      source_nlink: Number(observed.nlink), source_size: Number(observed.size), source_mtime_ns: observed.mtime_ns,
      source_dev: observed.dev, source_ino: observed.ino, source_identity_sha256: observed.identity_sha256,
      destination_relative_path: destination, mode,
    });
  };
  await append('node-capsule-image-001', `runtime/node-capsule/capsule/${image.destination}`, imageBytes, 0o400, 0o444);
  await append('node-capsule-manifest', 'runtime/node-capsule/capsule-manifest.json', manifestBytes, 0o600, 0o444);
  await append('node-capsule-receipt', 'runtime/node-capsule/mac-relocatable-node-capsule.receipt.json', receiptBytes, 0o600, 0o444);
  return { manifest, receipt };
}

async function replaceEntrySource(fixture, entry, leaf, bytes, mode) {
  const source = path.join(fixture.sourceRoot, leaf);
  await writeFile(source, bytes, { flag: 'wx', mode });
  const observed = identity(await lstat(source, { bigint: true }));
  Object.assign(entry, {
    source_path: source, source_path_sha256: SHA(Buffer.from(source)), source_sha256: SHA(bytes),
    source_uid: Number(observed.uid), source_gid: Number(observed.gid), source_mode: Number(observed.mode),
    source_nlink: Number(observed.nlink), source_size: Number(observed.size), source_mtime_ns: observed.mtime_ns,
    source_dev: observed.dev, source_ino: observed.ino, source_identity_sha256: observed.identity_sha256,
  });
}

test('[PRODUCTION-CONSUMER-2-RED/GREEN] installer validates the 53/53 corpus and authenticated SSH binding before target publication', async () => {
  const fixture = await createFixture('production-binding');
  try {
    const request = structuredClone(fixture.request);
    await addCapsuleTopology(fixture, request);
    const pass = invoke(fixture, {}, request);
    assert.equal(pass.status, 0, pass.stderr);

    const rejectedRequest = structuredClone(fixture.request);
    await addCapsuleTopology(fixture, rejectedRequest);
    rejectedRequest.handoff.production_frozen_inputs.requirements_verified = 52;
    const rejected = invoke(fixture, {}, rejectedRequest);
    assert.notEqual(rejected.status, 0);
    assert.equal(rejected.stdout, '');
    assert.match(rejected.stderr, /^ERROR PUBLISHER1_BOOTSTRAP\n$/);
  } finally {
    await cleanup(fixture.root);
  }
});

test('successor installer rejects an incomplete capsule closure before target publication', async () => {
  const fixture = await createFixture('capsule-incomplete');
  try {
    const request = structuredClone(fixture.request);
    await addCapsuleTopology(fixture, request);
    request.entries.splice(-3, 1);
    const rejected = invoke(fixture, {}, request);
    assert.notEqual(rejected.status, 0);
    assert.equal(rejected.stdout, '');
    assert.match(rejected.stderr, /^ERROR PUBLISHER1_BOOTSTRAP\n$/);
  } finally { await cleanup(fixture.root); }
});

test('successor installer rejects rebound receipt bytes with divergent predecessor lineage', async () => {
  const fixture = await createFixture('capsule-lineage-drift');
  try {
    const request = structuredClone(fixture.request);
    const { receipt } = await addCapsuleTopology(fixture, request);
    const changed = { ...receipt, predecessor_status: 'PASS' };
    const changedBytes = canonical(changed);
    await replaceEntrySource(fixture, request.entries.at(-1), 'node-capsule-receipt-drift.payload', changedBytes, 0o600);
    request.handoff.production_frozen_inputs.mac_node_capsule_receipt_sha256 = SHA(changedBytes);
    const rejected = invoke(fixture, {}, request);
    assert.notEqual(rejected.status, 0);
    assert.equal(rejected.stdout, '');
    assert.match(rejected.stderr, /^ERROR PUBLISHER1_BOOTSTRAP\n$/);
  } finally { await cleanup(fixture.root); }
});

test('round5 durable Phase B production service is version-addressed and launchd-persistent inside the original supervisor protocol', async () => {
  const source = await readFile(SOURCE, 'utf8');
  const workerDefinition = source.slice(
    source.indexOf('private func durablePhaseBDefinition('),
    source.indexOf('private func durablePhaseBActivationOwnerDefinition('),
  );
  const activationOwnerDefinition = source.slice(
    source.indexOf('private func durablePhaseBActivationOwnerDefinition('),
    source.indexOf('private func durablePhaseBService('),
  );
  assert.match(source, /\/Library\/LaunchDaemons\/\\\(label\)\.plist/u);
  assert.match(source, /child\.executableURL = URL\(fileURLWithPath: "\/bin\/launchctl"\)/u);
  assert.match(source, /child\.arguments = \["bootstrap", "system", service\.definitionPath\]/u);
  assert.doesNotMatch(workerDefinition, /<key>RunAtLoad<\/key>/u);
  assert.doesNotMatch(workerDefinition, /<key>KeepAlive<\/key>/u);
  assert.doesNotMatch(workerDefinition, /<key>SuccessfulExit<\/key>/u);
  assert.equal(source.includes('launchctl.arguments = ["bootout", "system/\\(service.label)"]'), true);
  assert.match(activationOwnerDefinition, /<key>KeepAlive<\/key><dict><key>SuccessfulExit<\/key><false\/><\/dict>/u);
});

test('round6 durable Phase B launchd definition is one-shot and cannot retry an unsuccessful worker', async () => {
  const source = await readFile(SOURCE, 'utf8');
  const workerDefinition = source.slice(
    source.indexOf('private func durablePhaseBDefinition('),
    source.indexOf('private func durablePhaseBActivationOwnerDefinition('),
  );
  assert.doesNotMatch(workerDefinition, /<key>RunAtLoad<\/key>/u);
  assert.doesNotMatch(workerDefinition, /<key>KeepAlive<\/key>/u);
  assert.doesNotMatch(workerDefinition, /<key>SuccessfulExit<\/key>/u);
  assert.match(source, /"retry": false/u);
});

test('round7 durable Phase B is explicitly kickstarted once and terminally guarded against reload or reinvocation', async () => {
  const source = await readFile(SOURCE, 'utf8');
  const workerDefinition = source.slice(
    source.indexOf('private func durablePhaseBDefinition('),
    source.indexOf('private func durablePhaseBActivationOwnerDefinition('),
  );
  assert.doesNotMatch(workerDefinition, /<key>RunAtLoad<\/key>/u);
  assert.doesNotMatch(workerDefinition, /<key>KeepAlive<\/key>/u);
  assert.equal(source.includes('child.arguments = ["kickstart", "system/\\(service.label)"]'), true);
  assert.match(source, /publisher1-durable-phase-b\.run-claim\.json/u);
  assert.match(source, /publisher1-durable-phase-b\.(?:completed|failed)\.json/u);
  assert.match(source, /TERMINAL_ALREADY_SETTLED/u);
});

for (const durableLeaf of [
  'publisher1-durable-phase-b.service.json',
  'publisher1-durable-phase-b.launchd.plist',
  'publisher1-durable-phase-b.invocation.json',
  'publisher1-durable-phase-b.registration.json',
  'publisher1-durable-phase-b.started.json',
  'publisher1-durable-phase-b.executing.json',
  'publisher1-durable-phase-b.completed.json',
  'publisher1-durable-phase-b.failed.json',
]) {
  test(`round6 durable control rejects exact-existing mutable ${durableLeaf}`, async () => {
    const root = await realpath(await mkdtemp(path.join(await realpath(tmpdir()), 'ci3-round6-durable-control-')));
    const file = path.join(root, durableLeaf);
    const bytes = Buffer.from(`durable-control:${durableLeaf}\n`);
    try {
      const create = spawnSync(binary, ['--synthetic-durable-control-probe', file, bytes.toString('base64')], {
        encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
        timeout: 10_000, maxBuffer: 64 * 1024,
      });
      assert.equal(create.status, 0, create.stderr);
      assert.equal(spawnSync('/usr/bin/stat', ['-f', '%Sf', file], { encoding: 'utf8' }).stdout.includes('uchg'), true);
      assert.equal(spawnSync('/usr/bin/chflags', ['nouchg', file]).status, 0);
      const exactMutable = spawnSync(binary, ['--synthetic-durable-control-probe', file, bytes.toString('base64')], {
        encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
        timeout: 10_000, maxBuffer: 64 * 1024,
      });
      assert.notEqual(exactMutable.status, 0);
      assert.deepEqual(await readFile(file), bytes);
    } finally {
      await cleanup(root);
    }
  });
}

for (const durableLeaf of [
  'publisher1-durable-phase-b.service.json',
  'publisher1-durable-phase-b.launchd.plist',
  'publisher1-durable-phase-b.invocation.json',
  'publisher1-durable-phase-b.registration.json',
]) {
  test(`round6 durable control crash before freeze leaves ${durableLeaf} unadoptable`, async () => {
    const root = await realpath(await mkdtemp(path.join(await realpath(tmpdir()), 'ci3-round6-durable-crash-')));
    const file = path.join(root, durableLeaf);
    const bytes = Buffer.from(`durable-crash:${durableLeaf}\n`);
    try {
      const crashed = spawnSync(binary, ['--synthetic-durable-control-probe', file, bytes.toString('base64')], {
        encoding: 'utf8', env: {
          HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin',
          CI3_SYNTHETIC_DURABLE_CRASH_AFTER_EXCLUSIVE_WRITE: durableLeaf,
        }, timeout: 10_000, maxBuffer: 64 * 1024,
      });
      assert.notEqual(crashed.status, 0);
      assert.deepEqual(await readFile(file), bytes);
      assert.equal(spawnSync('/usr/bin/stat', ['-f', '%Sf', file], { encoding: 'utf8' }).stdout.includes('uchg'), false);
      const recovery = spawnSync(binary, ['--synthetic-durable-control-probe', file, bytes.toString('base64')], {
        encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' },
        timeout: 10_000, maxBuffer: 64 * 1024,
      });
      assert.notEqual(recovery.status, 0);
      assert.deepEqual(await readFile(file), bytes);
    } finally {
      await cleanup(root);
    }
  });
}

test('successor immutable installer Phase A freezes exact self and receipt without Publisher1 target capability', async () => {
  const fixture = await createImmutableBootstrapFixture('phase-a-only');
  try {
    const result = invokeImmutablePhaseA(fixture, { CI3_SYNTHETIC_IMMUTABLE_CRASH_AFTER: 'PHASE_A' });
    assert.notEqual(result.status, 0);
    const installed = path.join(fixture.installerRoot, 'runtime', 'ci3-publisher1-bootstrap-installer');
    assert.equal(await readFile(installed).then(SHA), SHA(fixture.installerBytes));
    assert.equal((await lstat(installed)).mode & 0o777, 0o555);
    assert.equal((await lstat(installed)).nlink, 1);
    assert.equal((await lstat(path.join(fixture.installerRoot, 'immutable-installer-bootstrap.receipt.json'))).mode & 0o777, 0o444);
    await assert.rejects(lstat(fixture.destinationRoot), { code: 'ENOENT' });
    await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json')), { code: 'ENOENT' });
  } finally { await cleanup(fixture.root); }
});

test('successor immutable installer transfers from Phase A to root self Phase B and publishes receipt last', async () => {
  const fixture = await createImmutableBootstrapFixture('phase-a-b');
  try {
    const result = invokeImmutablePhaseA(fixture);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /PUBLISHER1_BOOTSTRAP_INSTALL PASS status=CREATED effect_executions=1/);
    assert.equal((await lstat(fixture.destinationRoot)).isDirectory(), true);
    assert.equal((await lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.result.json'))).mode & 0o777, 0o444);
  } finally { await cleanup(fixture.root); }
});

test('round3 immutable installer authenticates the handoff projection with fixed projection roots absent', async () => {
  const fixture = await createImmutableBootstrapFixture('projection-without-fixed-root');
  try {
    const environment = immutableEnvironment(fixture);
    delete environment.CI3_SYNTHETIC_FROZEN_PROJECTION_PATH;
    const result = spawnSync(binary, [
      '--immutable-bootstrap-phase-a', fixture.envelopePath, SHA(fixture.envelopeBytes),
    ], {
      encoding: 'utf8', env: environment, timeout: 10_000, maxBuffer: 64 * 1024,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /PUBLISHER1_BOOTSTRAP_INSTALL PASS status=CREATED effect_executions=1/);
  } finally { await cleanup(fixture.root); }
});

test('successor Phase A authenticates the loaded image and does not trust caller-controlled argv0', async () => {
  const fixture = await createImmutableBootstrapFixture('loaded-image-not-argv0');
  try {
    const result = spawnSync(binary, [
      '--immutable-bootstrap-phase-a', fixture.envelopePath, SHA(fixture.envelopeBytes),
    ], {
      argv0: '/private/synthetic/replaced-argv0', encoding: 'utf8',
      env: immutableEnvironment(fixture), timeout: 10_000, maxBuffer: 64 * 1024,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /PUBLISHER1_BOOTSTRAP_INSTALL PASS status=CREATED effect_executions=1/);
  } finally { await cleanup(fixture.root); }
});

test('successor immutable installer rejects Phase B from the mutable candidate path before claim or target', async () => {
  const fixture = await createImmutableBootstrapFixture('mutable-phase-b');
  try {
    const result = invokeMutablePhaseB(fixture);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    await assert.rejects(lstat(fixture.destinationRoot), { code: 'ENOENT' });
    await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json')), { code: 'ENOENT' });
  } finally { await cleanup(fixture.root); }
});

for (const boundary of ['BEFORE_SELF_FREEZE', 'AFTER_SELF_FREEZE', 'PHASE_A']) {
  test(`successor immutable installer crash boundary ${boundary} never reaches a Publisher1 target`, async () => {
    const fixture = await createImmutableBootstrapFixture(`crash-${boundary}`);
    try {
      const result = invokeImmutablePhaseA(fixture, { CI3_SYNTHETIC_IMMUTABLE_CRASH_AFTER: boundary });
      assert.notEqual(result.status, 0);
      await assert.rejects(lstat(fixture.destinationRoot), { code: 'ENOENT' });
      await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json')), { code: 'ENOENT' });
    } finally { await cleanup(fixture.root); }
  });
}

for (const boundary of ['BEFORE_SELF_FREEZE', 'AFTER_SELF_FREEZE']) {
  test(`successor Phase A deterministically resumes exact staging after ${boundary} without cleanup refetch or a new attempt`, async () => {
    const fixture = await createImmutableBootstrapFixture(`recover-${boundary}`);
    try {
      const crashed = invokeImmutablePhaseA(fixture, { CI3_SYNTHETIC_IMMUTABLE_CRASH_AFTER: boundary });
      assert.notEqual(crashed.status, 0);
      const recovered = invokeImmutablePhaseA(fixture);
      assert.equal(recovered.status, 0, recovered.stderr);
      assert.match(recovered.stdout, /PUBLISHER1_BOOTSTRAP_INSTALL PASS status=CREATED effect_executions=1/);
      assert.equal((await lstat(fixture.installerRoot)).isDirectory(), true);
      assert.equal(fixture.envelope.attempt, 1);
      assert.equal(fixture.envelope.retry, false);
    } finally { await cleanup(fixture.root); }
  });
}

test('round3 Phase A recovers exact promotion before directory freeze without cleanup refetch retry or second target effect', async () => {
  const fixture = await createImmutableBootstrapFixture('recover-after-promotion-before-directory-freeze');
  try {
    const crashed = invokeImmutablePhaseA(fixture, {
      CI3_SYNTHETIC_IMMUTABLE_CRASH_AFTER: 'AFTER_PROMOTION_BEFORE_DIRECTORY_FREEZE',
    });
    assert.notEqual(crashed.status, 0);
    assert.equal((await lstat(fixture.installerRoot)).isDirectory(), true);
    assert.equal((await lstat(fixture.installerRoot)).mode & 0o777, 0o700);
    await assert.rejects(lstat(fixture.destinationRoot), { code: 'ENOENT' });
    await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json')), { code: 'ENOENT' });
    const recovered = invokeImmutablePhaseA(fixture);
    assert.equal(recovered.status, 0, recovered.stderr);
    assert.match(recovered.stdout, /PUBLISHER1_BOOTSTRAP_INSTALL PASS status=CREATED effect_executions=1/);
    assert.equal(fixture.envelope.attempt, 1);
    assert.equal(fixture.envelope.retry, false);
  } finally { await cleanup(fixture.root); }
});

for (const [label, replace] of [
  ['bootstrap request bytes', async (fixture) => { await writeFile(fixture.requestPath, Buffer.from('{}\n')); }],
  ['semantic preflight receipt bytes', async (fixture) => { await writeFile(fixture.preflightReceiptPath, Buffer.from('{}\n')); }],
]) {
  test(`successor immutable installer rejects swapped ${label} before self receipt or target`, async () => {
    const fixture = await createImmutableBootstrapFixture(`swap-${label.replaceAll(' ', '-')}`);
    try {
      await replace(fixture);
      const result = invokeImmutablePhaseA(fixture);
      assert.notEqual(result.status, 0);
      await assert.rejects(lstat(path.join(fixture.installerRoot, 'immutable-installer-bootstrap.receipt.json')), { code: 'ENOENT' });
      await assert.rejects(lstat(fixture.destinationRoot), { code: 'ENOENT' });
    } finally { await cleanup(fixture.root); }
  });
}

test('successor immutable installer rejects an independently bound candidate digest mismatch before self root', async () => {
  const fixture = await createImmutableBootstrapFixture('candidate-digest');
  try {
    fixture.envelope.installer_sha256 = '0'.repeat(64);
    fixture.envelopeBytes = canonical(fixture.envelope);
    await rm(fixture.envelopePath);
    await writeFile(fixture.envelopePath, fixture.envelopeBytes, { flag: 'wx', mode: 0o600 });
    const result = invokeImmutablePhaseA(fixture);
    assert.notEqual(result.status, 0);
    await assert.rejects(lstat(fixture.installerRoot), { code: 'ENOENT' });
    await assert.rejects(lstat(fixture.destinationRoot), { code: 'ENOENT' });
  } finally { await cleanup(fixture.root); }
});

test('successor immutable installer refuses divergent exact-existing self without cleanup or target effect', async () => {
  const fixture = await createImmutableBootstrapFixture('divergent-self');
  try {
    await mkdir(path.join(fixture.installerRoot, 'runtime'), { recursive: true, mode: 0o700 });
    await writeFile(path.join(fixture.installerRoot, 'runtime', 'ci3-publisher1-bootstrap-installer'), 'divergent\n', { flag: 'wx', mode: 0o555 });
    const result = invokeImmutablePhaseA(fixture);
    assert.notEqual(result.status, 0);
    assert.equal((await readFile(path.join(fixture.installerRoot, 'runtime', 'ci3-publisher1-bootstrap-installer'))).toString(), 'divergent\n');
    await assert.rejects(lstat(fixture.destinationRoot), { code: 'ENOENT' });
  } finally { await cleanup(fixture.root); }
});

test('round2 local prepare helper materializes only fixed candidates through its pinned directory descriptor', async () => {
  const fixture = await createLocalPrepareFixture('pinned');
  try {
    const result = spawnSync(binary, ['--prepare-local'], {
      input: fixture.bytes, encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' }, timeout: 10_000,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'CI3_PUBLISHER1_LOCAL_PREPARE PASS raw_values=false\n');
    for (const role of chain.PREPARE_CANDIDATE_ROLES) {
      const observed = await lstat(path.join(fixture.candidateRoot, `${role}.candidate`));
      assert.equal(observed.isFile(), true);
      assert.equal(observed.mode & 0o777, 0o600);
      assert.equal(observed.nlink, 1);
    }
  } finally { await cleanup(fixture.root); }
});

test('round2 local prepare detects a synthetic parent swap and does not populate the replacement path', async () => {
  const fixture = await createLocalPrepareFixture('parent-swap');
  try {
    const result = spawnSync(binary, ['--prepare-local'], {
      input: fixture.bytes, encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin', CI3_SYNTHETIC_PREPARE_SWAP_PARENT: '1' }, timeout: 10_000,
    });
    assert.notEqual(result.status, 0);
    await assert.rejects(lstat(path.join(fixture.candidateRoot, `${chain.PREPARE_CANDIDATE_ROLES[0]}.candidate`)));
  } finally { await cleanup(fixture.root); }
});

test('installer creates the exact three-leaf immutable bootstrap and receipt last', async () => {
  const fixture = await createFixture('create');
  try {
    const result = invoke(fixture);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'CI3_PUBLISHER1_BOOTSTRAP_INSTALL PASS status=CREATED effect_executions=1\n');
    assert.equal(result.stderr, '');
    for (const [relative, mode] of [['publisher1-materializer.authority.json', 0o444], ['vps-issuer-authority.receipt.json', 0o444], ['runtime/ci3-terminal-anchor-writer', 0o555]]) {
      const observed = await lstat(path.join(fixture.destinationRoot, relative));
      assert.equal(observed.mode & 0o777, mode);
      assert.equal(observed.nlink, 1);
    }
    assert.equal((await lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.result.json'))).mode & 0o777, 0o444);
  } finally { await cleanup(fixture.root); }
});

test('round3 production-metadata seam freezes and revalidates the complete published and receipt trees', async () => {
  const fixture = await createFixture('production-metadata');
  try {
    const environment = { CI3_SYNTHETIC_PRODUCTION_METADATA: '1' };
    const created = invoke(fixture, environment);
    assert.equal(created.status, 0, created.stderr);
    const recovered = invoke(fixture, environment);
    assert.equal(recovered.status, 0, recovered.stderr);
    assert.equal(recovered.stdout, 'CI3_PUBLISHER1_BOOTSTRAP_INSTALL PASS status=EXISTS_VERIFIED effect_executions=0\n');
  } finally { await cleanup(fixture.root); }
});

test('round3 installer rejects a CFBoolean where the request schema requires an integer', async () => {
  const fixture = await createFixture('cfboolean');
  try {
    const request = structuredClone(fixture.request);
    request.schema_version = true;
    const result = invoke(fixture, {}, request);
    assert.notEqual(result.status, 0);
    await assert.rejects(lstat(fixture.destinationRoot));
  } finally { await cleanup(fixture.root); }
});

test('installer verifies exact-existing only with its original claim and no repeated effect', async () => {
  const fixture = await createFixture('existing');
  try {
    assert.equal(invoke(fixture).status, 0);
    const recovered = invoke(fixture);
    assert.equal(recovered.status, 0, recovered.stderr);
    assert.equal(recovered.stdout, 'CI3_PUBLISHER1_BOOTSTRAP_INSTALL PASS status=EXISTS_VERIFIED effect_executions=0\n');
  } finally { await cleanup(fixture.root); }
});

test('round4 installer pins the authority projection to the authenticated signed pass and ignores an ambient projection file', async () => {
  const fixture = await createFixture('independent-frozen-projection');
  try {
    const projection = structuredClone(fixture.request.handoff.authority_projection);
    projection.authority_parent = '0'.repeat(40);
    await writeFile(fixture.frozenProjectionPath, canonical(projection), { flag: 'w', mode: 0o600 });
    const result = invoke(fixture);
    assert.equal(result.status, 0, result.stderr);
    assert.equal((await lstat(fixture.destinationRoot)).isDirectory(), true);
    assert.equal((await lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json'))).mode & 0o777, 0o444);
  } finally { await cleanup(fixture.root); }
});

for (const [label, addExtra] of [
  ['published root', async (fixture) => writeFile(path.join(fixture.destinationRoot, 'unexpected'), 'x\n', { flag: 'wx', mode: 0o444 })],
  ['runtime directory', async (fixture) => writeFile(path.join(fixture.destinationRoot, 'runtime', 'unexpected'), 'x\n', { flag: 'wx', mode: 0o444 })],
  ['state receipt directory', async (fixture) => writeFile(path.join(fixture.stateRoot, 'unexpected'), 'x\n', { flag: 'wx', mode: 0o444 })],
]) {
  test(`round3 exact-existing rejects an extra ${label} member`, async () => {
    const fixture = await createFixture(`extra-${label.replaceAll(/[^a-z0-9]+/gi, '-')}`);
    try {
      assert.equal(invoke(fixture).status, 0);
      await addExtra(fixture);
      assert.notEqual(invoke(fixture).status, 0);
    } finally { await cleanup(fixture.root); }
  });
}

test('round2 installer rejects the legacy unbound V1 request before any claim or destination effect', async () => {
  const fixture = await createFixture('legacy-v1');
  try {
    const legacy = structuredClone(fixture.request);
    legacy.schema_version = 1;
    legacy.purpose = 'CI3_PUBLISHER1_BOOTSTRAP_INSTALL_REQUEST_V1';
    delete legacy.handoff;
    const result = invoke(fixture, {}, legacy);
    assert.notEqual(result.status, 0);
    await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json')));
    await assert.rejects(lstat(fixture.destinationRoot));
  } finally { await cleanup(fixture.root); }
});

const requestMutationCases = [
  ['schema_version', 1], ['purpose', 'OTHER'], ['authority_sha', 'f'.repeat(40)],
  ['controller_generation_id', `controller-${'f'.repeat(64)}`], ['attempt', 2], ['retry', true], ['raw_values', true],
  ['destination_root', '/Library/Application Support/Agentempp/escape'], ['state_root', '/Library/Application Support/Agentempp/escape-state'],
];

for (const [field, value] of requestMutationCases) {
  test(`installer rejects request mutation ${field}`, async () => {
    const fixture = await createFixture(`request-${field}`);
    try {
      const request = structuredClone(fixture.request);
      request[field] = value;
      const result = invoke(fixture, {}, request);
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /PUBLISHER1_BOOTSTRAP/);
      assert.equal(result.stdout, '');
    } finally { await cleanup(fixture.root); }
  });
}

for (const [index, role] of ['materializer-authority', 'issuer-receipt', 'writer-binary'].entries()) {
  test(`installer rejects missing role ${role}`, async () => {
    const fixture = await createFixture(`missing-${role}`);
    try {
      const request = structuredClone(fixture.request);
      request.entries.splice(index, 1);
      assert.notEqual(invoke(fixture, {}, request).status, 0);
    } finally { await cleanup(fixture.root); }
  });

  test(`installer rejects duplicate role ${role}`, async () => {
    const fixture = await createFixture(`duplicate-${role}`);
    try {
      const request = structuredClone(fixture.request);
      request.entries[index === 0 ? 1 : 0] = structuredClone(request.entries[index]);
      assert.notEqual(invoke(fixture, {}, request).status, 0);
    } finally { await cleanup(fixture.root); }
  });
}

for (const [index, field, value] of [
  [0, 'destination_relative_path', '../escape'], [0, 'mode', 0o600], [0, 'source_path_sha256', 'f'.repeat(64)],
  [0, 'source_sha256', 'f'.repeat(64)], [0, 'source_uid', 0], [0, 'source_gid', 0], [0, 'source_mode', 0o644],
  [0, 'source_nlink', 2], [0, 'source_size', -1], [0, 'source_mtime_ns', '-1'], [0, 'source_dev', '-1'],
  [0, 'source_ino', '-1'], [0, 'source_identity_sha256', 'f'.repeat(64)], [1, 'role', 'writer-binary'],
]) {
  test(`installer rejects entry authority mutation ${field}`, async () => {
    const fixture = await createFixture(`entry-${field}`);
    try {
      const request = structuredClone(fixture.request);
      request.entries[index][field] = value;
      assert.notEqual(invoke(fixture, {}, request).status, 0);
    } finally { await cleanup(fixture.root); }
  });
}

const handoffMutationCases = [
  ['authority projection parent drift', (h) => { h.authority_projection.authority_parent = '0'.repeat(40); }],
  ['authority projection tree drift', (h) => { h.authority_projection.authority_tree = '0'.repeat(40); }],
  ['authority projection subject drift', (h) => { h.authority_projection.authority_subject_sha256 = '0'.repeat(64); }],
  ['authority projection manifest drift', (h) => { h.authority_projection.authority_manifest_sha256 = '0'.repeat(64); }],
  ['authority projection operation drift', (h) => { h.authority_projection.operation_authority_sha256 = '0'.repeat(64); }],
  ['authority projection node drift', (h) => { h.authority_projection.node_candidate_sha256 = '0'.repeat(64); }],
  ['authority projection collector drift', (h) => { h.authority_projection.collector_contracts_sha256 = '0'.repeat(64); }],
  ['authority projection remote generation drift', (h) => { h.authority_projection.remote_generation_id = `remote-${'0'.repeat(64)}`; }],
  ['authority projection controller generation drift', (h) => { h.authority_projection.controller_generation_id = `controller-${'0'.repeat(64)}`; }],
  ['Gate0 schema version drift', (h) => { h.gate0_receipt.schema_version = 1; }],
  ['Gate0 purpose drift', (h) => { h.gate0_receipt.purpose = 'OTHER'; }],
  ['Gate0 executor drift', (h) => { h.gate0_receipt.executor_authority_sha = '0'.repeat(40); }],
  ['Gate0 nonzero exit', (h) => { h.gate0_receipt.exit_code = 1; }],
  ['Gate0 stdout evidence', (h) => { h.gate0_receipt.stdout_bytes = 1; }],
  ['Gate0 stderr evidence', (h) => { h.gate0_receipt.stderr_bytes = 1; }],
  ['Gate0 failed status', (h) => { h.gate0_receipt.status = 'FAIL'; }],
  ['Gate0 unpreserved previous receipt', (h) => { h.gate0_receipt.previous_gate0_receipt_preserved = false; }],
  ['Gate0 operational network attempt', (h) => { h.gate0_receipt.pre_gate0_operational_network_attempts = 1; }],
  ['Gate0 simulator attempt', (h) => { h.gate0_receipt.pre_gate0_simulator_attempts = 1; }],

  ['issuer schema version drift', (h) => { h.issuer.schema_version = 2; }],
  ['issuer purpose drift', (h) => { h.issuer.purpose = 'OTHER'; }],
  ['issuer authority drift', (h) => { h.issuer.authority_sha = '0'.repeat(40); }],
  ['issuer generation drift', (h) => { h.issuer.issuer_generation_id = `issuer-${'0'.repeat(64)}`; }],
  ['issuer noncanonical algorithm spelling', (h) => { h.issuer.public_key_algorithm = 'ed25519'; }],
  ['issuer truncated raw key', (h) => { h.issuer.public_key_raw_base64 = 'AA=='; }],
  ['issuer public key hash drift', (h) => { h.issuer.public_key_sha256 = '0'.repeat(64); }],
  ['issuer identity hash drift', (h) => { h.issuer.issuer_identity_sha256 = '0'.repeat(64); }],
  ['issuer allowed pass purpose drift', (h) => { h.issuer.allowed_pass_purpose = 'OTHER'; }],
  ['issuer normal executor authorization', (h) => { h.issuer.normal_executor_authorized = true; }],
  ['issuer raw value flag', (h) => { h.issuer.raw_values = true; }],

  ['pass schema version drift', (h) => { h.pass.schema_version = 2; }],
  ['pass purpose drift', (h) => { h.pass.purpose = 'OTHER'; }],
  ['pass authority drift', (h) => { h.pass.authority_sha = '0'.repeat(40); }],
  ['pass remote generation drift', (h) => { h.pass.remote_generation_id = `remote-${'0'.repeat(64)}`; }],
  ['pass controller generation drift', (h) => { h.pass.controller_generation_id = `controller-${'0'.repeat(64)}`; }],
  ['pass issuer authority drift', (h) => { h.pass.issuer_authority_sha256 = '0'.repeat(64); }],
  ['pass issuer key drift', (h) => { h.pass.issuer_key_sha256 = '0'.repeat(64); }],
  ['pass source generation drift', (h) => { h.pass.source_generation_id = `src-${'0'.repeat(64)}`; }],
  ['pass retry attempt', (h) => { h.pass.attempt = 2; }],
  ['pass retry flag', (h) => { h.pass.retry = true; }],
  ['pass raw value flag', (h) => { h.pass.raw_values = true; }],
  ['pass signed payload hash drift', (h) => { h.pass.signed_payload_sha256 = '0'.repeat(64); }],

  ['transport schema version drift', (h) => { h.transport_manifest.schema_version = 2; }],
  ['transport purpose drift', (h) => { h.transport_manifest.purpose = 'OTHER'; }],
  ['transport authority drift', (h) => { h.transport_manifest.authority_sha = '0'.repeat(40); }],
  ['transport remote generation drift', (h) => { h.transport_manifest.remote_generation_id = `remote-${'0'.repeat(64)}`; }],
  ['transport controller generation drift', (h) => { h.transport_manifest.controller_generation_id = `controller-${'0'.repeat(64)}`; }],
  ['transport collector contract drift', (h) => { h.transport_manifest.collector_contracts_sha256 = '0'.repeat(64); }],
  ['transport entry role reorder', (h) => { [h.transport_manifest.entries[0], h.transport_manifest.entries[1]] = [h.transport_manifest.entries[1], h.transport_manifest.entries[0]]; }],
  ['transport entry path hash drift', (h) => { h.transport_manifest.entries[0].path_sha256 = '0'.repeat(64); }],
  ['transport entry content hash drift', (h) => { h.transport_manifest.entries[0].sha256 = '0'.repeat(64); }],
  ['transport payload hash drift', (h) => { h.transport_manifest.transfer_payload_sha256 = '0'.repeat(64); }],
  ['transport raw value flag', (h) => { h.transport_manifest.raw_values = true; }],

  ['human receipt schema drift', (h) => { h.human_authorization.schema_version = 1; }],
  ['human receipt purpose drift', (h) => { h.human_authorization.purpose = 'OTHER'; }],
  ['human receipt authority drift', (h) => { h.human_authorization.authority_sha = '0'.repeat(40); }],
  ['human receipt action drift', (h) => { h.human_authorization.approved_action = 'OTHER'; }],
  ['human receipt manifest drift', (h) => { h.human_authorization.publisher_input_manifest_sha256 = '0'.repeat(64); }],
  ['human receipt pass drift', (h) => { h.human_authorization.vps_operation_authority_pass_sha256 = '0'.repeat(64); }],
  ['human receipt retry attempt', (h) => { h.human_authorization.attempt = 2; }],
  ['human receipt retry flag', (h) => { h.human_authorization.retry = true; }],
  ['human receipt raw value flag', (h) => { h.human_authorization.raw_values = true; }],

  ['materializer schema version drift', (h) => { h.materializer_authority.schema_version = 1; }],
  ['materializer purpose drift', (h) => { h.materializer_authority.purpose = 'OTHER'; }],
  ['materializer authority drift', (h) => { h.materializer_authority.authority_sha = '0'.repeat(40); }],
  ['materializer controller generation drift', (h) => { h.materializer_authority.controller_generation_id = `controller-${'0'.repeat(64)}`; }],
  ['materializer issuer binding drift', (h) => { h.materializer_authority.issuer_authority_sha256 = '0'.repeat(64); }],
  ['materializer self-consistent path drift', (h) => { h.materializer_authority.materializer_path = '/private/synthetic/other-writer'; h.materializer_authority.materializer_path_sha256 = SHA(Buffer.from(h.materializer_authority.materializer_path)); }],
  ['materializer writer binding drift', (h) => { h.materializer_authority.writer_source_sha256 = '0'.repeat(64); }],
  ['materializer request mode drift', (h) => { h.materializer_authority.request_mode = 0o644; }],
  ['materializer request link drift', (h) => { h.materializer_authority.request_nlink = 2; }],
  ['materializer root binding drift', (h) => { h.materializer_authority.receiver_root_identity_sha256 = '0'.repeat(64); }],
  ['materializer receiver leaf hash drift', (h) => { h.materializer_authority.receiver_leaves[0].sha256 = '0'.repeat(64); }],
  ['materializer normal executor authorization', (h) => { h.materializer_authority.normal_executor_authorized = true; }],
  ['materializer raw value flag', (h) => { h.materializer_authority.raw_values = true; }],
];

for (const [label, mutate] of handoffMutationCases) {
  test(`installer rejects canonical handoff mutation: ${label}`, async () => {
    const fixture = await createFixture(`handoff-${label.replaceAll(/[^a-z0-9]+/gi, '-')}`);
    try {
      const request = structuredClone(fixture.request);
      mutate(request.handoff);
      const result = invoke(fixture, {}, request);
      assert.notEqual(result.status, 0);
      await assert.rejects(lstat(fixture.destinationRoot));
      await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json')));
    } finally { await cleanup(fixture.root); }
  });
}

for (const [label, mutate] of [
  ['leading-zero receiver timestamp', (leaf) => { leaf.mtime_ns = '01'; }],
  ['Node-unsafe receiver uid', (leaf) => { leaf.uid = Number.MAX_SAFE_INTEGER + 1; }],
]) {
  test(`round4 installer rejects canonical-looking ${label} before a claim`, async () => {
    const fixture = await createFixture(`round4-receiver-${label.replaceAll(/[^a-z0-9]+/gi, '-')}`);
    try {
      const request = structuredClone(fixture.request);
      mutate(request.handoff.receiver_leaves[0]);
      mutate(request.handoff.materializer_authority.receiver_leaves[0]);
      const materializerEntry = request.entries[0];
      const materializerBytes = chain.canonicalJson(request.handoff.materializer_authority);
      await rm(materializerEntry.source_path);
      await writeFile(materializerEntry.source_path, materializerBytes, { flag: 'wx', mode: 0o600 });
      const observed = identity(await lstat(materializerEntry.source_path, { bigint: true }));
      materializerEntry.source_sha256 = SHA(materializerBytes);
      materializerEntry.source_uid = observed.uid;
      materializerEntry.source_gid = observed.gid;
      materializerEntry.source_mode = observed.mode;
      materializerEntry.source_nlink = observed.nlink;
      materializerEntry.source_size = observed.size;
      materializerEntry.source_mtime_ns = observed.mtime_ns;
      materializerEntry.source_dev = observed.dev;
      materializerEntry.source_ino = observed.ino;
      materializerEntry.source_identity_sha256 = observed.identity_sha256;
      const result = invoke(fixture, {}, request);
      assert.notEqual(result.status, 0);
      await assert.rejects(lstat(fixture.destinationRoot));
      await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json')));
    } finally { await cleanup(fixture.root); }
  });
}

for (const role of ['materializer-authority', 'issuer-receipt', 'writer-binary']) {
  test(`installer rejects same-content replacement of the pinned ${role} source`, async () => {
    const fixture = await createFixture(`source-replacement-${role}`);
    try {
      const entry = fixture.request.entries.find((candidate) => candidate.role === role);
      const bytes = await readFile(entry.source_path);
      const displaced = `${entry.source_path}.original`;
      await writeFile(displaced, bytes, { flag: 'wx', mode: 0o600 });
      await rm(entry.source_path);
      await writeFile(entry.source_path, bytes, { flag: 'wx', mode: 0o600 });
      assert.notEqual(invoke(fixture).status, 0);
    } finally { await cleanup(fixture.root); }
  });
}

for (const role of ['materializer-authority', 'issuer-receipt', 'writer-binary']) {
  test(`installer rejects a hardlinked ${role} source`, async () => {
    const fixture = await createFixture(`hardlink-${role}`);
    try {
      const entry = fixture.request.entries.find((candidate) => candidate.role === role);
      await link(entry.source_path, path.join(fixture.root, `hardlink-${role}`));
      assert.notEqual(invoke(fixture).status, 0);
    } finally { await cleanup(fixture.root); }
  });
}

for (const role of ['materializer-authority', 'issuer-receipt', 'writer-binary']) {
  test(`installer rejects a symlinked ${role} source`, async () => {
    const fixture = await createFixture(`symlink-${role}`);
    try {
      const entry = fixture.request.entries.find((candidate) => candidate.role === role);
      const original = `${entry.source_path}.original`;
      await writeFile(original, await readFile(entry.source_path), { flag: 'wx', mode: 0o600 });
      await rm(entry.source_path);
      await symlink(original, entry.source_path);
      assert.notEqual(invoke(fixture).status, 0);
    } finally { await cleanup(fixture.root); }
  });
}

for (const [label, establish] of [
  ['directory', async (fixture) => { await mkdir(fixture.destinationRoot, { mode: 0o555 }); }],
  ['file', async (fixture) => { await writeFile(fixture.destinationRoot, 'unclaimed\n', { flag: 'wx', mode: 0o444 }); }],
  ['symlink', async (fixture) => { const marker = path.join(fixture.root, 'destination-marker'); await mkdir(marker, { mode: 0o700 }); await symlink(marker, fixture.destinationRoot); }],
  ['nested-leaf', async (fixture) => { await mkdir(fixture.destinationRoot, { mode: 0o700 }); await writeFile(path.join(fixture.destinationRoot, 'unexpected'), 'x\n', { flag: 'wx', mode: 0o444 }); await chmod(fixture.destinationRoot, 0o555); }],
]) {
  test(`installer rejects unclaimed preexisting ${label} destination`, async () => {
    const fixture = await createFixture(`unclaimed-${label}`);
    try {
      await mkdir(path.dirname(fixture.destinationRoot), { recursive: true, mode: 0o700 });
      await establish(fixture);
      assert.notEqual(invoke(fixture).status, 0);
    } finally { await cleanup(fixture.root); }
  });
}

for (const [label, bytes] of [
  ['empty', Buffer.alloc(0)],
  ['malformed-json', Buffer.from('{\n')],
  ['wrong-schema', Buffer.from('{"schema_version":2}\n')],
  ['wrong-authority', Buffer.from('{"authority_sha":"different"}\n')],
]) {
  test(`installer rejects ${label} partial claim without effect`, async () => {
    const fixture = await createFixture(`partial-${label}`);
    try {
      await mkdir(fixture.stateRoot, { recursive: true, mode: 0o700 });
      await writeFile(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json'), bytes, { flag: 'wx', mode: 0o444 });
      assert.notEqual(invoke(fixture).status, 0);
      await assert.rejects(lstat(fixture.destinationRoot));
    } finally { await cleanup(fixture.root); }
  });
}

for (const label of ['claim-bound-request', 'claim-owner-only']) {
  test(`installer persists ${label} before synthetic first effect`, async () => {
    const fixture = await createFixture(`claim-before-effect-${label}`);
    try {
      const result = invoke(fixture, { CI3_SYNTHETIC_CRASH_AFTER: 'CLAIM' });
      assert.notEqual(result.status, 0);
      const claim = await lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.claim.json'));
      assert.equal(claim.isFile(), true);
      if (label === 'claim-owner-only') assert.equal(Number(claim.mode & 0o777), 0o444);
      await assert.rejects(lstat(fixture.destinationRoot));
    } finally { await cleanup(fixture.root); }
  });
}

for (const label of ['promoted-tree', 'absent-result']) {
  test(`installer publishes result receipt last after ${label}`, async () => {
    const fixture = await createFixture(`receipt-last-${label}`);
    try {
      const result = invoke(fixture, { CI3_SYNTHETIC_CRASH_AFTER: 'PROMOTION' });
      assert.notEqual(result.status, 0);
      assert.equal((await lstat(fixture.destinationRoot)).isDirectory(), true);
      await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.result.json')));
    } finally { await cleanup(fixture.root); }
  });
}

for (const [label, environment] of [
  ['destination-parent replacement', { CI3_SYNTHETIC_SWAP_DESTINATION_PARENT: '1' }],
  ['state-parent replacement', { CI3_SYNTHETIC_SWAP_STATE_PARENT: '1' }],
  ['final-name race', { CI3_SYNTHETIC_CREATE_FINAL_NAME: '1' }],
]) {
  test(`round3 installer rejects a deterministic ${label} before receipt publication`, async () => {
    const fixture = await createFixture(`round3-${label.replaceAll(/[^a-z0-9]+/gi, '-')}`);
    try {
      const result = invoke(fixture, environment);
      assert.notEqual(result.status, 0);
      await assert.rejects(lstat(path.join(fixture.stateRoot, 'publisher1-bootstrap.result.json')));
    } finally { await cleanup(fixture.root); }
  });
}

test('installer rejects admin-style arbitrary destination argument', async () => {
  const fixture = await createFixture('arbitrary-argv');
  try {
    const result = spawnSync(binary, ['--install', fixture.requestPath, SHA(fixture.requestBytes), '/tmp/arbitrary'], { encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
  } finally { await cleanup(fixture.root); }
});

test('installer rejects stdin request in production-shaped mode', () => {
  const result = spawnSync(binary, ['--install'], { input: '{}\n', encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, '');
});
