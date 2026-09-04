#!/usr/bin/env node

import {
  createHash,
  createPrivateKey,
  createPublicKey,
  sign as signDetached,
  verify as verifyDetached,
} from 'node:crypto';
import { spawn as spawnChild } from 'node:child_process';
import { constants as FS_CONSTANTS } from 'node:fs';
import { link, lstat, mkdir, open, readdir, realpath, rename, unlink } from 'node:fs/promises';
import { homedir, userInfo } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  AUTHORITY_PATHS,
  buildPublisher1TransactionRequest,
  validateLaunchAttestation,
  validatePublisher1MaterializerAuthorityBinding,
} from './ci3-bridge-controller.mjs';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const SWIFT_PREPARE_HELPER = path.join(path.dirname(SCRIPT_PATH), 'ci3-publisher1-bootstrap-installer.swift');
const PRODUCTION_OWNER_ROOT = path.join(homedir(), '.config', 'agentempp', 'ci3', 'external-publisher-chain-v1');
const PRODUCTION_BINDINGS_PATH = path.join(homedir(), '.config', 'agentempp', 'ci3', 'frozen-input-constructor-v1', 'authorities.json');
const MODES = Object.freeze([
  '--self-test', '--prepare', '--provision-vps-publisher0', '--receive-vps-pass',
  '--provision-mac-publisher1', '--verify-chain',
]);
const PUBLISHER0_TRANSPORT_BROKER_MODE = '--internal-publisher0-transport-broker';
const PUBLISHER0_TRANSPORT_OWNER_MODE = '--internal-publisher0-transport-owner';
const PUBLISHER0_TRANSPORT_SESSION_SUPERVISOR_MODE = '--internal-publisher0-transport-session-supervisor';
const PUBLISHER0_TRANSPORT_JOURNAL_WORKER_MODE = '--internal-publisher0-transport-journal-worker';
const PUBLISHER0_TRANSPORT_BARRIER_STAGES = Object.freeze([
  'remote-prepared-before-first-local-chunk',
  'before-last-local-chunk',
  'after-local-ack',
  'remote-before-terminal-link',
  'remote-after-terminal-link-before-directory-fsync',
  'remote-after-directory-fsync-before-terminal-decision',
]);

export const SEMANTIC_SAFE_PUBLISHER_CHAIN_STAGES = Object.freeze([
  'SUCCESSOR_AUTHORITY_PUBLISHED',
  'EXACT_BLOBS_GREEN',
  'GATE0_PASS',
  'PUBLISHER0_PASS',
  'ISSUER_AND_SIGNED_PASS_READY',
  'PUBLISHER_MANIFEST_TRANSPORTED',
  'OWNER_ONLY_MAC_CAPTURED',
  'RECEIVER_READY',
  'REQUEST_READY',
  'HUMAN_AUTHORIZED',
  'FINAL_PHYSICAL_IDENTITIES',
  'SEMANTIC_PREFLIGHT_PASS',
  'IMMUTABLE_INSTALLER_PHASE_A_PASS',
  'PUBLISHER1_PHASE_B_PASS',
  'PUBLISHER1_READBACK_PASS',
  'OPERATION_AUTHORITY_PUBLISHED',
  'CONTROLLER_AUTHORITY_READBACK',
  'SETTLED',
]);

const BINDING_SPEC = Object.freeze({
  MAC_EXECUTOR_AUTHORITY_SHA: [40],
  MAC_EXECUTOR_AUTHORITY_PARENT: [40],
  MAC_EXECUTOR_AUTHORITY_TREE: [40],
  MAC_EXECUTOR_AUTHORITY_SUBJECT: 'subject',
  CURRENT_REMOTE_SHA: [40],
  CURRENT_REMOTE_PARENT: [40],
  CURRENT_REMOTE_TREE: [40],
  CURRENT_REMOTE_SUBJECT: 'subject',
  MAC_OBJECT_BOOTSTRAP_AUTHORITY_SHA: [40],
  REMOTE_BUNDLE_AUTHORITY_SHA: [40],
  REMOTE_BUNDLE_AUTHORITY_PARENT: [40],
  REMOTE_BUNDLE_AUTHORITY_TREE: [40],
  REMOTE_BUNDLE_AUTHORITY_SUBJECT: 'subject',
  REMOTE_BUNDLE_DOCUMENTATION_SHA: [40],
  REMOTE_BUNDLE_GENERATION_ID: 'generation',
  REMOTE_BUNDLE_RECEIPT_SHA256: [64],
  REMOTE_BUNDLE_CONFIG_SHA256: [64],
  REMOTE_SYNTHETIC_CREDENTIAL_SHA256: [64],
  NODE_RUNTIME_V2_CREATION_AUTHORITY_SHA: [40],
  NODE_RUNTIME_V2_ADOPTION_AUTHORITY_SHA: [40],
  CI3_IOS_AUTHORITY_SHA: [40],
  CI2_BASE: [40],
  AUTHORITY_BASE: [40],
});

export const CLOSED_ENVIRONMENT = Object.freeze({
  HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin',
});

export const PUBLISHER_AUTHORITY_PATHS = AUTHORITY_PATHS;

function validateSubprocessEnvironment(environment, code = 'STOP_PRE_AUTHORITY') {
  if (!isPlainObject(environment)) fail(code);
  if (canonicalJson(environment).equals(canonicalJson(CLOSED_ENVIRONMENT))) return environment;
  const syntheticKeys = [
    'HOME', 'LANG', 'LC_ALL', 'PATH', 'CI3_SYNTHETIC_MAIN_ROOT', 'CI3_SYNTHETIC_FROZEN_PROJECTION_PATH',
    'CI3_SYNTHETIC_INSTALLER_BASE',
  ];
  const phaseBPaused = environment.CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A === '1';
  const killSupervisor = environment.CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AFTER_SERVICE_REGISTRATION === '1';
  const registrationStage = environment.CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE;
  const registrationStagePresent = [
    'CLAIM', 'DEFINITION', 'INVOCATION', 'PRE_BOOTSTRAP', 'BOOTSTRAP',
    'POST_BOOTSTRAP', 'PRE_REGISTRATION', 'REGISTRATION', 'POST_KICKSTART',
  ]
    .includes(registrationStage);
  const workerBarrierStage = environment.CI3_SYNTHETIC_P1_WORKER_BARRIER_STAGE;
  const workerBarrierStagePresent = [
    'RUN_CLAIM', 'PRE_EFFECT_ENTRY', 'POST_EFFECT_ENTRY', 'PRE_TERMINAL',
  ].includes(workerBarrierStage);
  const activationBarrierStage = environment.CI3_SYNTHETIC_P1_ACTIVATION_BARRIER_STAGE;
  const activationBarrierStagePresent = [
    'PRE_SIGNAL', 'POST_ACCEPT_PRE_RECEIPT',
  ].includes(activationBarrierStage);
  exactKeys(environment, [
    ...syntheticKeys,
    ...(phaseBPaused ? ['CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A'] : []),
    ...(killSupervisor ? ['CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AFTER_SERVICE_REGISTRATION'] : []),
    ...(registrationStagePresent ? ['CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE'] : []),
    ...(workerBarrierStagePresent ? ['CI3_SYNTHETIC_P1_WORKER_BARRIER_STAGE'] : []),
    ...(activationBarrierStagePresent ? ['CI3_SYNTHETIC_P1_ACTIVATION_BARRIER_STAGE'] : []),
  ], code);
  if ((killSupervisor || registrationStagePresent || workerBarrierStagePresent
      || activationBarrierStagePresent) && !phaseBPaused) fail(code);
  if (environment.HOME !== '/var/empty' || environment.LANG !== 'C' || environment.LC_ALL !== 'C' || environment.PATH !== '/usr/bin:/bin') fail(code);
  requireAbsoluteSafePath(environment.CI3_SYNTHETIC_MAIN_ROOT, code);
  requireAbsoluteSafePath(environment.CI3_SYNTHETIC_FROZEN_PROJECTION_PATH, code);
  requireAbsoluteSafePath(environment.CI3_SYNTHETIC_INSTALLER_BASE, code);
  return environment;
}

export const SSH_TRUST_ROLES = Object.freeze([
  'ssh-config', 'ssh-known-hosts', 'ssh-private-key', 'ssh-public-key', 'ssh-trust-descriptor',
]);

export const TRANSPORT_ROLES = Object.freeze([
  'node-runtime', 'controller', 'launcher-runtime', 'launch-attestation', 'authority-manifest',
  'operation-authority', 'ssh-config', 'ssh-known-hosts', 'ssh-private-key', 'ssh-public-key', 'ssh-trust-descriptor',
]);

export const PUBLISHER1_ROLES = Object.freeze([
  'node-runtime', 'controller', 'launcher-runtime', 'launcher-bootstrap-authority',
  'launch-attestation', 'authority-manifest', 'operation-authority', 'human-authorization',
  'vps-pass', 'vps-issuer-authority', 'publisher-input-manifest', 'ssh-config',
  'ssh-known-hosts', 'ssh-private-key', 'ssh-public-key', 'ssh-trust-descriptor',
]);

export const PUBLISHER1_RECEIVER_ROLES = Object.freeze(
  PUBLISHER1_ROLES.filter((role) => role !== 'human-authorization'),
);

// P0 has exactly one local bootstrap input. Every issuer/pass/manifest,
// controller payload, receiver leaf, request, human receipt and installer
// authority is a causal output of a later stage and is therefore forbidden
// from the preparation set.
export const PREPARE_CANDIDATE_ROLES = Object.freeze(['ssh-config']);
export const PRODUCTION_FROZEN_INPUT_ORDER = Object.freeze([
  'AUTHORITY_PUBLISHED', 'GATE0_PASS', 'FRESH_OOB_RECEIPT',
  'AUTHENTICATED_SSH_RECEIPT', 'MAC_NODE_CAPSULE', 'MATERIALIZED_53_OF_53',
  'FROZEN_CORPUS', 'PUBLISHER0', 'PUBLISHER1', 'CONTROLLER_AUTHORITY',
]);
const MAX_SUBPROCESS_BYTES = 16 * 1024;
const MAX_AUTHENTICATED_CAPTURE_BYTES = 256 * 1024 * 1024;
const MAX_SUBPROCESS_INPUT_BYTES = 16 * 1024 * 1024;
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

export class ExternalPublisherError extends Error {
  constructor(code) {
    super(code);
    this.name = 'ExternalPublisherError';
    this.code = code;
  }
}

function fail(code) {
  throw new ExternalPublisherError(code);
}

// This is the common production boundary consumed by all five executable
// surfaces.  It contains digests only: late-bound SSH and Node observations
// stay in their independently authenticated receipts.
export function validateProductionFrozenInputConsumerBinding(binding, code = 'STOP_PRE_AUTHORITY') {
  exactKeys(binding, [
    'authenticated_ssh_receipt_sha256', 'authorized_producer_matrix_sha256',
    'causal_order_sha256', 'constructor_claim_sha256', 'corpus_sha256',
    'mac_node_capsule_receipt_sha256', 'mac_runtime_role',
    'materialized_input_matrix_sha256', 'oob_receipt_sha256', 'purpose',
    'raw_values', 'requirements_total', 'requirements_verified', 'schema_version',
    'vps_node_reference_sha256', 'vps_runtime_role',
  ], code);
  if (binding.schema_version !== 1
      || binding.purpose !== 'CI3_PRODUCTION_FROZEN_INPUT_CONSUMER_BINDING_V1'
      || binding.raw_values !== false || binding.requirements_total !== 53
      || binding.requirements_verified !== 53
      || binding.vps_runtime_role !== 'VPS_BOOTSTRAP_NODE_RUNTIME'
      || binding.mac_runtime_role !== 'MAC_EXECUTOR_NODE_RUNTIME'
      || binding.causal_order_sha256 !== sha256(canonicalJson(PRODUCTION_FROZEN_INPUT_ORDER))) fail(code);
  for (const field of [
    'authenticated_ssh_receipt_sha256', 'authorized_producer_matrix_sha256',
    'constructor_claim_sha256', 'corpus_sha256', 'mac_node_capsule_receipt_sha256',
    'materialized_input_matrix_sha256', 'oob_receipt_sha256', 'vps_node_reference_sha256',
  ]) requireHex(binding[field], code);
  return binding;
}

export function validateMacCapsuleInstallTopology(entries, context, code = 'STOP_PRE_AUTHORITY') {
  if (!Array.isArray(entries) || !isPlainObject(context?.authority)) fail(code);
  const binding = validateProductionFrozenInputConsumerBinding(context.production_frozen_inputs, code);
  const manifestEntry = entries.at(-2);
  const receiptEntry = entries.at(-1);
  if (manifestEntry?.role !== 'node-capsule-manifest'
      || manifestEntry.destination_relative_path !== 'runtime/node-capsule/capsule-manifest.json'
      || receiptEntry?.role !== 'node-capsule-receipt'
      || receiptEntry.destination_relative_path !== 'runtime/node-capsule/mac-relocatable-node-capsule.receipt.json'
      || !Buffer.isBuffer(manifestEntry.bytes) || !Buffer.isBuffer(receiptEntry.bytes)) fail(code);
  let manifest;
  let receipt;
  try {
    manifest = JSON.parse(manifestEntry.bytes.toString('utf8'));
    receipt = JSON.parse(receiptEntry.bytes.toString('utf8'));
  } catch { fail(code); }
  const lineageFields = [
    'predecessor_authority', 'predecessor_generation', 'predecessor_status', 'predecessor_attempts',
    'predecessor_retry', 'predecessor_cleanup', 'predecessor_adoption',
  ];
  if (!canonicalJson(manifest).equals(manifestEntry.bytes)
      || !canonicalJson(receipt).equals(receiptEntry.bytes)
      || manifest.schema_version !== 3 || manifest.purpose !== 'MAC_RELOCATABLE_NODE_CAPSULE_V3'
      || manifest.authority !== context.authority.commit || manifest.generation !== 'capsule-v3'
      || manifest.role !== 'MAC_EXECUTOR_NODE_RUNTIME' || !isPlainObject(manifest.capsule)
      || receipt.schema_version !== 3 || receipt.purpose !== 'MAC_RELOCATABLE_NODE_CAPSULE_V3'
      || receipt.authority !== context.authority.commit || receipt.generation !== 'capsule-v3'
      || receipt.manifest_sha256 !== sha256(manifestEntry.bytes)
      || receipt.attempts !== 1 || receipt.retry !== false || receipt.raw_path !== false
      || binding.mac_node_capsule_receipt_sha256 !== sha256(receiptEntry.bytes)
      || manifestEntry.source_sha256 !== sha256(manifestEntry.bytes)
      || receiptEntry.source_sha256 !== sha256(receiptEntry.bytes)) fail(code);
  if (manifest.predecessor_authority !== 'c1c83a63b9f258546310eccba30b889958ccabe5'
      || manifest.predecessor_generation !== 'capsule-v2'
      || manifest.predecessor_status !== 'FAILED_PARTIAL_PRESERVED'
      || manifest.predecessor_attempts !== '1/1_CONSUMED'
      || manifest.predecessor_retry !== false || manifest.predecessor_cleanup !== false
      || manifest.predecessor_adoption !== false || !isHex(receipt.source_authority, [40])
      || lineageFields.some((field) => receipt[field] !== manifest[field])) fail(code);
  requireHex(manifest.capsule.executable_sha256, code);
  if (!Array.isArray(manifest.capsule.images)
      || receipt.capsule_executable_sha256 !== manifest.capsule.executable_sha256
      || receipt.capsule_images_sha256 !== sha256(canonicalJson(manifest.capsule.images))) fail(code);
  const node = entries[0];
  if (node?.role !== 'node-runtime'
      || node.destination_relative_path !== 'runtime/node-capsule/capsule/bin/node'
      || node.source_sha256 !== manifest.capsule.executable_sha256) fail(code);
  const images = entries.slice(1, -2);
  if (images.length !== manifest.capsule.images.length) fail(code);
  const seen = new Set();
  for (const [index, image] of manifest.capsule.images.entries()) {
    exactKeys(image, ['destination', 'sha256'], code);
    requireHex(image.sha256, code);
    if (typeof image.destination !== 'string' || !/^lib\/[a-f0-9]{16}-[^/\0]+$/.test(image.destination)
        || seen.has(image.destination)) fail(code);
    seen.add(image.destination);
    const entry = images[index];
    if (entry?.role !== `node-capsule-image-${String(index + 1).padStart(3, '0')}`
        || entry.destination_relative_path !== `runtime/node-capsule/capsule/${image.destination}`
        || entry.source_sha256 !== image.sha256) fail(code);
  }
  return true;
}

function validateSemanticSafePublisherChainState(state) {
  const code = 'PUBLISHER_CHAIN_ORDER';
  exactKeys(state, ['schema_version', 'purpose', 'completed', 'attempt', 'retry', 'raw_values'], code);
  if (state.schema_version !== 2 || state.purpose !== 'CI3_SEMANTIC_SAFE_PUBLISHER_CHAIN_V2'
      || state.attempt !== 1 || state.retry !== false || state.raw_values !== false
      || !Array.isArray(state.completed) || state.completed.length > SEMANTIC_SAFE_PUBLISHER_CHAIN_STAGES.length) fail(code);
  for (const [index, stage] of state.completed.entries()) {
    if (stage !== SEMANTIC_SAFE_PUBLISHER_CHAIN_STAGES[index]) fail(code);
  }
  return true;
}

export function createSemanticSafePublisherChainState() {
  return Object.freeze({
    schema_version: 2,
    purpose: 'CI3_SEMANTIC_SAFE_PUBLISHER_CHAIN_V2',
    completed: Object.freeze([]),
    attempt: 1,
    retry: false,
    raw_values: false,
  });
}

export function advanceSemanticSafePublisherChainState(state, stage) {
  validateSemanticSafePublisherChainState(state);
  const expected = SEMANTIC_SAFE_PUBLISHER_CHAIN_STAGES[state.completed.length];
  if (typeof stage !== 'string' || stage !== expected) fail('PUBLISHER_CHAIN_ORDER');
  return Object.freeze({
    ...state,
    completed: Object.freeze([...state.completed, stage]),
  });
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, keys, code) {
  if (!isPlainObject(value)) fail(code);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) fail(code);
}

function isHex(value, lengths = [64]) {
  return typeof value === 'string' && lengths.includes(value.length) && /^[a-f0-9]+$/.test(value);
}

function requireHex(value, code, lengths = [64]) {
  if (!isHex(value, lengths)) fail(code);
}

function requireGeneration(value, code) {
  if (typeof value !== 'string' || !/^[a-z][a-z0-9-]*-[a-f0-9]{64}$/.test(value)) fail(code);
}

function requireAbsoluteSafePath(value, code) {
  if (typeof value !== 'string' || value.length === 0 || !path.isAbsolute(value)
      || value.includes('\0') || /[\r\n]/.test(value) || value.includes('/../')
      || path.normalize(value) !== value) fail(code);
}

// This is intentionally byte-for-byte the frozen controller's derivation:
// requestRoot, requestPath and receiverRoot must be the very objects its
// write-once publisher flow later reopens.  No caller supplies any segment.
export function deriveFrozenControllerPublisherPaths(context, receiverManifestSha256) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  requireHex(receiverManifestSha256, code);
  const requestRoot = path.join(homedir(), '.config', 'agentempp', 'ci3', 'publisher-input', authority.commit);
  return Object.freeze({
    request_root: requestRoot,
    request_path: path.join(requestRoot, 'publisher1-transaction.request.json'),
    receiver_root: path.join(requestRoot, 'receiver', context.generations.remote, context.generations.controller, receiverManifestSha256),
  });
}

export function physicalFromStat(stat) {
  const maxSafe = BigInt(Number.MAX_SAFE_INTEGER);
  const maxInt64 = (1n << 63n) - 1n;
  const maxUInt64 = (1n << 64n) - 1n;
  for (const value of [stat.uid, stat.gid, stat.nlink, stat.size]) if (value < 0n || value > maxSafe) fail('PHYSICAL_IDENTITY');
  const mtimeNs = stat.mtimeNs;
  if (mtimeNs < 0n || mtimeNs > maxInt64 || stat.dev < 0n || stat.dev > maxUInt64 || stat.ino < 0n || stat.ino > maxUInt64) fail('PHYSICAL_IDENTITY');
  return {
    uid: Number(stat.uid), gid: Number(stat.gid), mode: Number(stat.mode & 0o777n),
    nlink: Number(stat.nlink), size: Number(stat.size), mtime_ns: mtimeNs.toString(),
    dev: stat.dev.toString(), ino: stat.ino.toString(),
  };
}

export function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export function gitBlobOid(bytes) {
  const source = Buffer.from(bytes);
  return createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${source.length}\0`), source])).digest('hex');
}

export function deriveInstallerGitSourceBinding({ context, authorityManifestBytes, installerSourceBytes } = {}) {
  const code = 'INSTALLER_GIT_PROVENANCE';
  const authority = contextFields(context, code);
  if (!Buffer.isBuffer(authorityManifestBytes) || !Buffer.isBuffer(installerSourceBytes)
      || authorityManifestBytes.length === 0 || installerSourceBytes.length === 0
      || sha256(authorityManifestBytes) !== authority.manifest_sha256) fail(code);
  const text = authorityManifestBytes.toString('utf8');
  if (!text.endsWith('\n') || text.includes('\r') || text.includes('\0')) fail(code);
  const lines = text.slice(0, -1).split('\n');
  if (lines.length !== AUTHORITY_PATHS.length) fail(code);
  const entries = lines.map((line, index) => {
    const parts = line.split(' ');
    if (parts.length !== 3 || parts[0] !== AUTHORITY_PATHS[index] || !isHex(parts[1], [40]) || !isHex(parts[2])) fail(code);
    return { path: parts[0], blob_oid: parts[1], sha256: parts[2] };
  });
  const gitPath = 'scripts/ci3/ci3-publisher1-bootstrap-installer.swift';
  const installer = entries.find(({ path: entryPath }) => entryPath === gitPath);
  if (!installer || installer.sha256 !== sha256(installerSourceBytes)
      || installer.blob_oid !== gitBlobOid(installerSourceBytes)) fail(code);
  return Object.freeze({
    git_path: gitPath,
    git_blob_oid: installer.blob_oid,
    source_sha256: installer.sha256,
    authority_manifest_sha256: authority.manifest_sha256,
  });
}

export function buildMacOsPrivilegedBootstrapInvocation({
  candidatePath, candidateSha256, immutableRequestPath, immutableRequestSha256,
  boundaryManifestPath, boundaryManifestSha256, supervisorSourceBase64, supervisorSourceSha256,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  for (const value of [candidatePath, immutableRequestPath, boundaryManifestPath]) requireAbsoluteSafePath(value, code);
  for (const value of [candidateSha256, immutableRequestSha256, boundaryManifestSha256]) requireHex(value, code);
  requireHex(supervisorSourceSha256, code);
  if (typeof supervisorSourceBase64 !== 'string' || supervisorSourceBase64.length === 0) fail(code);
  const supervisorSource = Buffer.from(supervisorSourceBase64, 'base64');
  if (supervisorSource.length === 0 || supervisorSource.length > MAX_SUBPROCESS_INPUT_BYTES
      || supervisorSource.toString('base64') !== supervisorSourceBase64
      || sha256(supervisorSource) !== supervisorSourceSha256) fail(code);
  const encodedSupervisor = supervisorSourceBase64;
  const appleScript = [
    'on run argv',
    'if (count of argv) is not 6 then error "STOP_PRE_AUTHORITY" number 64',
    `set supervisorSource to "${encodedSupervisor}"`,
    'set commandText to "/usr/bin/printf %s " & quoted form of supervisorSource & " | /usr/bin/base64 -D | /usr/bin/xcrun swift - --privileged-supervisor"',
    'repeat with itemValue in argv',
    'set commandText to commandText & " " & quoted form of (contents of itemValue)',
    'end repeat',
    'do shell script commandText with administrator privileges',
    'end run',
  ].join('; ');
  return Object.freeze({
    executable: '/usr/bin/osascript',
    argv: Object.freeze(['-e', appleScript, candidatePath, candidateSha256, immutableRequestPath,
      immutableRequestSha256, boundaryManifestPath, boundaryManifestSha256]),
    environment: CLOSED_ENVIRONMENT,
    supervisor_source_sha256: supervisorSourceSha256,
    privilege_prompts: 1, attempt: 1, retry: false,
    candidate_path_execution: false,
    atomic_selection: 'FIXED_ROOT_SUPERVISOR_SINGLE_OPEN_COPY_EXEC',
    reobserves_before_target_write: true,
    raw_values: false,
  });
}

export async function runAtomicInstallerSelectionGate({
  candidatePath, expectedSha256, afterVerification = async () => undefined,
  invokePrivilege = async () => undefined,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  requireAbsoluteSafePath(candidatePath, code);
  requireHex(expectedSha256, code);
  if (typeof afterVerification !== 'function' || typeof invokePrivilege !== 'function') fail(code);
  let descriptor;
  try {
    descriptor = await open(candidatePath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    const before = physicalFromStat(await descriptor.stat({ bigint: true }));
    if (before.mode !== 0o700 || before.nlink !== 1) fail(code);
    const bytes = await descriptor.readFile();
    const after = physicalFromStat(await descriptor.stat({ bigint: true }));
    if (bytes.length === 0 || sha256(bytes) !== expectedSha256
        || physicalIdentitySha256(before) !== physicalIdentitySha256(after)) fail(code);
    await afterVerification();
    const named = physicalFromStat(await lstat(candidatePath, { bigint: true }));
    if (physicalIdentitySha256(named) !== physicalIdentitySha256(before)) fail(code);
    const result = await invokePrivilege(Object.freeze({
      descriptor, bytes, sha256: expectedSha256, identity_sha256: physicalIdentitySha256(before), raw_values: false,
    }));
    return Object.freeze({ state: 'SELECTED', result, raw_values: false });
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  } finally {
    await descriptor?.close().catch(() => undefined);
  }
}

export function canonicalJson(value) {
  const normalize = (candidate) => {
    if (Array.isArray(candidate)) return candidate.map(normalize);
    if (isPlainObject(candidate)) return Object.fromEntries(Object.keys(candidate).sort().map((key) => [key, normalize(candidate[key])]));
    return candidate;
  };
  return Buffer.from(`${JSON.stringify(normalize(value))}\n`);
}

export function physicalIdentitySha256({ uid, gid, mode, nlink, size, mtime_ns, dev, ino } = {}) {
  if (![uid, gid, mode, nlink, size].every(Number.isSafeInteger)
      || uid < 0 || gid < 0 || mode < 0 || nlink < 1 || size < 0
      || ![mtime_ns, dev, ino].every((value) => typeof value === 'string' && /^(0|[1-9]\d*)$/.test(value))) fail('PHYSICAL_IDENTITY');
  let mtime; let device; let inode;
  try { mtime = BigInt(mtime_ns); device = BigInt(dev); inode = BigInt(ino); } catch { fail('PHYSICAL_IDENTITY'); }
  if (mtime > ((1n << 63n) - 1n) || device > ((1n << 64n) - 1n) || inode > ((1n << 64n) - 1n)) fail('PHYSICAL_IDENTITY');
  return sha256(Buffer.from(`uid=${uid};gid=${gid};mode=${mode};nlink=${nlink};size=${size};mtime=${mtime_ns};dev=${dev};ino=${ino}`));
}

export function parseMode(argv) {
  if (!Array.isArray(argv) || argv.length !== 1 || typeof argv[0] !== 'string' || !MODES.includes(argv[0])) fail('MODE_INVALID');
  return argv[0];
}

export function validateFrozenBindings(bindings) {
  const code = 'FROZEN_AUTHORITY';
  exactKeys(bindings, Object.keys(BINDING_SPEC), code);
  for (const [key, validation] of Object.entries(BINDING_SPEC)) {
    const value = bindings[key];
    if (validation === 'subject') {
      if (typeof value !== 'string' || value.length === 0 || /[\0\r\n]/.test(value)) fail(code);
    } else if (validation === 'generation') {
      requireGeneration(value, code);
    } else {
      requireHex(value, code, validation);
    }
  }
  return true;
}

export async function loadFrozenBindings(file) {
  const code = 'FROZEN_AUTHORITY';
  requireAbsoluteSafePath(file, code);
  let descriptor;
  try {
    descriptor = await open(file, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    const stat = await descriptor.stat({ bigint: true });
    const owner = typeof process.getuid === 'function' ? process.getuid() : Number(stat.uid);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1n || Number(stat.uid) !== owner
        || (stat.mode & 0o077n) !== 0n) fail(code);
    const bytes = await descriptor.readFile();
    const after = await descriptor.stat({ bigint: true });
    if (after.dev !== stat.dev || after.ino !== stat.ino || after.size !== stat.size) fail(code);
    let parsed;
    try { parsed = JSON.parse(bytes.toString('utf8')); } catch { fail(code); }
    validateFrozenBindings(parsed);
    return parsed;
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  } finally {
    await descriptor?.close().catch(() => undefined);
  }
}

async function readPinnedOwnerOnlyFile(file, { mode = 0o600, code = 'STOP_PRE_AUTHORITY' } = {}) {
  requireAbsoluteSafePath(file, code);
  let descriptor;
  try {
    descriptor = await open(file, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    const before = await descriptor.stat({ bigint: true });
    const owner = typeof process.getuid === 'function' ? process.getuid() : Number(before.uid);
    if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1n || Number(before.uid) !== owner
        || Number(before.gid) !== (typeof process.getgid === 'function' ? process.getgid() : Number(before.gid))
        || Number(before.mode & 0o777n) !== mode) fail(code);
    const bytes = await descriptor.readFile();
    const after = await descriptor.stat({ bigint: true });
    if (after.dev !== before.dev || after.ino !== before.ino || after.size !== before.size
        || after.mtimeNs !== before.mtimeNs) fail(code);
    return Object.freeze({ bytes, metadata: physicalFromStat(before) });
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  } finally {
    await descriptor?.close().catch(() => undefined);
  }
}

async function readPinnedOwnerOnlyJson(file, code) {
  const observed = await readPinnedOwnerOnlyFile(file, { code });
  try { return Object.freeze({ ...observed, value: JSON.parse(observed.bytes.toString('utf8')) }); } catch { fail(code); }
}

async function readPinnedRegularFile(file, { executable = false, code = 'STOP_PRE_AUTHORITY' } = {}) {
  requireAbsoluteSafePath(file, code);
  let descriptor;
  try {
    descriptor = await open(file, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    const before = await descriptor.stat({ bigint: true });
    if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1n
        || (executable && (before.mode & 0o111n) === 0n)) fail(code);
    const bytes = await descriptor.readFile();
    const after = await descriptor.stat({ bigint: true });
    const named = await lstat(file, { bigint: true });
    if (after.dev !== before.dev || after.ino !== before.ino || after.size !== before.size
        || after.mtimeNs !== before.mtimeNs || named.dev !== after.dev || named.ino !== after.ino
        || named.size !== after.size || named.mtimeNs !== after.mtimeNs) fail(code);
    return Object.freeze({ bytes, metadata: physicalFromStat(after) });
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  } finally {
    await descriptor?.close().catch(() => undefined);
  }
}

async function syncNamedDirectory(directory, code = 'STOP_PRE_AUTHORITY') {
  requireAbsoluteSafePath(directory, code);
  let descriptor;
  try {
    descriptor = await open(directory, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_DIRECTORY | FS_CONSTANTS.O_NOFOLLOW);
    await descriptor.sync();
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  } finally {
    await descriptor?.close().catch(() => undefined);
  }
}

async function readPinnedSettledFile(file, { mode, code = 'STOP_PRE_AUTHORITY' } = {}) {
  requireAbsoluteSafePath(file, code);
  let descriptor;
  try {
    descriptor = await open(file, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    const before = await descriptor.stat({ bigint: true });
    const currentUid = BigInt(typeof process.getuid === 'function' ? process.getuid() : Number(before.uid));
    const currentGid = BigInt(typeof process.getgid === 'function' ? process.getgid() : Number(before.gid));
    const ownerAccepted = (before.uid === 0n && before.gid === 0n)
      || (before.uid === currentUid && before.gid === currentGid);
    if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1n || !ownerAccepted
        || Number(before.mode & 0o777n) !== mode) fail(code);
    const bytes = await descriptor.readFile();
    const after = await descriptor.stat({ bigint: true });
    const named = await lstat(file, { bigint: true });
    if (after.dev !== before.dev || after.ino !== before.ino || after.size !== before.size
        || after.mtimeNs !== before.mtimeNs || named.dev !== after.dev || named.ino !== after.ino
        || named.size !== after.size || named.mtimeNs !== after.mtimeNs) fail(code);
    return Object.freeze({ bytes, metadata: physicalFromStat(after) });
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  } finally { await descriptor?.close().catch(() => undefined); }
}

async function readPinnedRootExecutable(file, code = 'STOP_PRE_AUTHORITY') {
  requireAbsoluteSafePath(file, code);
  let descriptor;
  try {
    descriptor = await open(file, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    const before = await descriptor.stat({ bigint: true });
    if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1n
        || before.uid !== 0n || before.gid !== 0n || Number(before.mode & 0o777n) !== 0o755) fail(code);
    const bytes = await descriptor.readFile();
    const after = await descriptor.stat({ bigint: true });
    if (after.dev !== before.dev || after.ino !== before.ino || after.size !== before.size
        || after.mtimeNs !== before.mtimeNs) fail(code);
    return Object.freeze({ bytes, metadata: physicalFromStat(before) });
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  } finally {
    await descriptor?.close().catch(() => undefined);
  }
}

export function deriveAuthorityLayout(bindings, ownerRoot) {
  validateFrozenBindings(bindings);
  requireAbsoluteSafePath(ownerRoot, 'PATH_AUTHORITY');
  const authorityRoot = path.join(ownerRoot, bindings.MAC_EXECUTOR_AUTHORITY_SHA);
  return Object.freeze({
    authority_root: authorityRoot,
    publisher0_root: path.join(authorityRoot, 'publisher0'),
    publisher1_bootstrap_root: path.join(authorityRoot, 'publisher1-bootstrap'),
    publisher_input_root: path.join(authorityRoot, 'publisher-input'),
    raw_values: false,
  });
}

export function buildFixedProvisioningSshInvocation({ configPath, destinationAlias, remoteCommand } = {}) {
  const code = 'VPS_PUBLISHER0_PROVISION';
  requireAbsoluteSafePath(configPath, code);
  if (destinationAlias !== 'ci3-publisher0'
      || remoteCommand !== '/usr/local/libexec/agentempp/ci3/provision-publisher0-v1') fail(code);
  return Object.freeze({
    executable: '/usr/bin/ssh',
    argv: ['-F', configPath, '-o', 'BatchMode=yes', '-o', 'NumberOfPasswordPrompts=0', destinationAlias, remoteCommand],
    attempts: 1,
    retry: false,
  });
}

function shellSingleQuoted(value, code) {
  if (typeof value !== 'string' || value.includes('\0') || value.includes('\r') || value.includes('\n')) fail(code);
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function publisher0BootstrapInputMode(role) {
  if (role === 'node-runtime' || role === 'controller' || role === 'launcher-runtime') return 0o555;
  if (role === 'ssh-private-key') return 0o400;
  return 0o444;
}

function publisher0BootstrapRelativePath(role, request) {
  if (role === 'node-runtime') return `runtime/node-${request.node_sha256}`;
  if (role === 'controller') return `git/${request.controller.git_blob_oid}/ci3-bridge-controller.mjs`;
  if (role === 'launcher-runtime') return `git/${request.launcher.git_blob_oid}/ci3-bridge-launcher.zsh`;
  return `inputs/${role}.payload`;
}

function buildPublisher0RemoteShellProgram({
  request, requestBytes, syntheticBarrierStage = null, syntheticPrimitiveBarrierStage = null,
  syntheticTransportBarrierRoot = null, syntheticTransportBarrierStage = null,
  durableTransport = true,
} = {}) {
  const code = 'VPS_PUBLISHER0_PROVISION';
  const objectRoot = `/var/lib/agentempp/ci3-authority-objects/${request.authority_sha}`;
  const requestRelativePath = 'publisher0-bootstrap.request.json';
  const syntheticPinnedDispatch = [
    'const subject = await import(new URL(`file://${process.argv[1]}`));',
    'const result = await subject.runPublisher0PhysicalBootstrapBoundary({ requestPath: process.argv[2], requestSha256: process.argv[3] });',
    'process.stdout.write(result.output_bytes);',
  ].join(' ');
  const primitivePrepared = syntheticPrimitiveBarrierStage === null ? null : {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER0_PRIMITIVE_BARRIER_V1',
    stage: syntheticPrimitiveBarrierStage,
    request_sha256: sha256(requestBytes),
    decision: 'PREPARED',
    raw_values: false,
  };
  const primitivePreparedBytes = primitivePrepared === null ? null : canonicalJson(primitivePrepared);
  const primitiveRelease = primitivePrepared === null ? null : {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER0_PRIMITIVE_BARRIER_RELEASE_V1',
    stage: primitivePrepared.stage,
    request_sha256: primitivePrepared.request_sha256,
    prepared_sha256: sha256(primitivePreparedBytes),
    decision: 'CONTINUE',
    raw_values: false,
  };
  const primitiveReleaseBytes = primitiveRelease === null ? null : canonicalJson(primitiveRelease);
  const primitiveAuthenticatedBytes = primitivePrepared === null ? null : canonicalJson({
    controller_sha256: request.controller.sha256,
    decision: 'AUTHENTICATED',
    node_sha256: request.node_sha256,
    purpose: 'CI3_SYNTHETIC_PUBLISHER0_PINNED_DESCRIPTOR_AUTHENTICATION_V1',
    raw_values: false,
    request_sha256: sha256(requestBytes),
    schema_version: 1,
  });
  const frozenRelativeDirectories = new Set(['runtime', 'git', 'inputs']);
  const lines = [
    '#!/bin/sh',
    'set -eu',
    'umask 077',
    'request_sha="$1"',
    `test "$request_sha" = ${shellSingleQuoted(sha256(requestBytes), code)}`,
    'prefix="${CI3_SYNTHETIC_PUBLISHER0_REMOTE_ROOT:-}"',
    `transport_barrier_root=${shellSingleQuoted(syntheticTransportBarrierRoot ?? '', code)}`,
    `transport_barrier_stage=${shellSingleQuoted(syntheticTransportBarrierStage ?? '', code)}`,
    `object_root="$prefix${objectRoot}"`,
    'if [ -d /proc/self/fd ]; then fd_root=/proc/self/fd; else fd_root=/dev/fd; fi',
    'make_directory() {',
    '  directory="$1"',
    '  mode="$2"',
    '  if [ ! -e "$directory" ]; then',
    '    /bin/mkdir "$directory"',
    '    /bin/chmod "$mode" "$directory"',
    '  fi',
    '  test -d "$directory"',
    '  test ! -L "$directory"',
    '}',
    'create_directory() {',
    '  directory="$1"',
    '  mode="$2"',
    '  /bin/mkdir "$directory"',
    '  test -d "$directory"',
    '  test ! -L "$directory"',
    '  /bin/chmod "$mode" "$directory"',
    '}',
    'write_exact() {',
    '  destination="$1"',
    '  encoded="$2"',
    '  expected_sha="$3"',
    '  mode="$4"',
    '  test ! -e "$destination"',
    '  if [ -n "$prefix" ]; then',
    '    ( set -C; printf "%s" "$encoded" | /usr/bin/base64 -d > "$destination" )',
    '    if [ -x /usr/bin/sync ]; then /usr/bin/sync; else /bin/sync; fi',
    '  else',
    '    printf "%s" "$encoded" | /usr/bin/base64 -d | /usr/bin/dd of="$destination" bs=65536 conv=fsync oflag=excl,nofollow status=none',
    '  fi',
    '  test -f "$destination"',
    '  test ! -L "$destination"',
    '  actual_sha=$(/usr/bin/openssl dgst -sha256 "$destination" | /usr/bin/awk "{print \\$NF}")',
    '  test "$actual_sha" = "$expected_sha"',
    '  /bin/chmod "$mode" "$destination"',
    '  if [ -z "$prefix" ]; then',
    '    /usr/bin/sync -f "$destination"',
    '    /usr/bin/chattr +i -- "$destination"',
    '    immutable_flags=$(/usr/bin/lsattr -d -- "$destination" | /usr/bin/awk "{print \\$1}")',
    '    case "$immutable_flags" in *i*) ;; *) exit 1 ;; esac',
    '  fi',
    '}',
    'publish_synthetic_marker() {',
    '  marker_destination="$1"',
    '  marker_encoded="$2"',
    '  marker_expected_sha="$3"',
    '  marker_staging="$marker_destination.publishing"',
    '  write_exact "$marker_staging" "$marker_encoded" "$marker_expected_sha" 600',
    '  /bin/ln "$marker_staging" "$marker_destination"',
    '  /bin/rm "$marker_staging"',
    '  if [ -x /usr/bin/sync ]; then /usr/bin/sync; else /bin/sync; fi',
    '}',
    'await_synthetic_transport_barrier() {',
    '  requested_stage="$1"',
    '  if [ -z "$transport_barrier_stage" ] || [ "$transport_barrier_stage" != "$requested_stage" ]; then return 0; fi',
    '  prepared_path="$transport_barrier_root/$requested_stage.prepared.json"',
    '  release_path="$transport_barrier_root/$requested_stage.continue.json"',
    '  prepared_bytes=$(printf \'{"decision":"PREPARED","output_sha256":"%s","purpose":"CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER_V1","raw_values":false,"request_sha256":"%s","schema_version":1,"stage":"%s"}\' "$output_sha" "$request_sha" "$requested_stage")',
    '  ( set -C; printf "%s\\n" "$prepared_bytes" > "$prepared_path" )',
    '  /bin/chmod 600 "$prepared_path"',
    '  /bin/sync -f "$prepared_path"',
    '  /bin/sync -f "$transport_barrier_root"',
    '  prepared_sha=$(/usr/bin/openssl dgst -sha256 "$prepared_path" | /usr/bin/awk "{print \\$NF}")',
    '  expected_release=$(printf \'{"decision":"CONTINUE","output_sha256":"%s","prepared_sha256":"%s","purpose":"CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER_RELEASE_V1","raw_values":false,"request_sha256":"%s","schema_version":1,"stage":"%s"}\' "$output_sha" "$prepared_sha" "$request_sha" "$requested_stage")',
    '  barrier_wait=0',
    '  while [ ! -f "$release_path" ]; do',
    '    barrier_wait=$((barrier_wait + 1))',
    '    test "$barrier_wait" -le 6000',
    '    /bin/sleep 0.01',
    '  done',
    '  observed_release=$(/bin/cat "$release_path")',
    '  test "$observed_release" = "$expected_release"',
    '}',
    'if [ -n "$prefix" ]; then make_directory "$prefix" 700; fi',
    'make_directory "$prefix/var" 755',
    'make_directory "$prefix/var/lib" 755',
    'make_directory "$prefix/var/lib/agentempp" 755',
    'make_directory "$prefix/var/lib/agentempp/ci3-authority-objects" 755',
    `create_directory "$prefix/var/lib/agentempp/ci3-authority-objects/${request.authority_sha}" 755`,
    'exec 7<"$object_root"',
    'if [ -n "$prefix" ]; then object_fd_root="$object_root"; else object_fd_root="$fd_root/7"; fi',
    'create_directory "$object_fd_root/runtime" 755',
    'create_directory "$object_fd_root/git" 755',
    'create_directory "$object_fd_root/inputs" 755',
  ];
  for (const entry of request.entries) {
    const relativePath = entry.relative_path;
    const parent = path.posix.dirname(relativePath);
    if (parent !== '.') {
      const parts = parent.split('/');
      let current = '$object_root';
      let relativeDirectory = '';
      for (const part of parts) {
        current += `/${part}`;
        relativeDirectory = relativeDirectory === '' ? part : `${relativeDirectory}/${part}`;
        if (!frozenRelativeDirectories.has(relativeDirectory)) {
          frozenRelativeDirectories.add(relativeDirectory);
          lines.push(`create_directory "$object_fd_root/${relativeDirectory}" 755`);
        }
      }
    }
    lines.push(
      `write_exact "$object_fd_root/${relativePath}" ${shellSingleQuoted(entry.bytes_base64, code)} ${shellSingleQuoted(entry.sha256, code)} ${entry.mode.toString(8)}`,
    );
  }
  const expectedObjectTree = [...new Set([
    ...frozenRelativeDirectories,
    ...request.entries.map((entry) => entry.relative_path),
    requestRelativePath,
  ])].sort().join('\n');
  const productionDispatch = '/usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin CI3_PINNED_PUBLISHER0_BOOTSTRAP=1 "$node_fd_path" "$controller_fd_path" bootstrap-publisher0-physical-boundary "$object_root/' + requestRelativePath + '" "$request_sha"';
  const syntheticDispatch = syntheticBarrierStage === null
    ? `/usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin CI3_PINNED_CONTROLLER_IMPORT=1 CI3_SYNTHETIC_TEST=1 CI3_SYNTHETIC_PUBLISHER0_REMOTE_ROOT="$prefix" /bin/sh "$node_fd_path" --input-type=module --eval ${shellSingleQuoted(syntheticPinnedDispatch, code)} "$controller_fd_path" "$object_root/${requestRelativePath}" "$request_sha"`
    : `/usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin CI3_PINNED_CONTROLLER_IMPORT=1 CI3_SYNTHETIC_TEST=1 CI3_SYNTHETIC_PUBLISHER0_REMOTE_ROOT="$prefix" CI3_SYNTHETIC_PUBLISHER0_PHYSICAL_BARRIER=${shellSingleQuoted(syntheticBarrierStage, code)} /bin/sh "$node_fd_path" --input-type=module --eval ${shellSingleQuoted(syntheticPinnedDispatch, code)} "$controller_fd_path" "$object_root/${requestRelativePath}" "$request_sha"`;
  lines.push(
    `write_exact "$object_fd_root/${requestRelativePath}" ${shellSingleQuoted(requestBytes.toString('base64'), code)} ${shellSingleQuoted(sha256(requestBytes), code)} 444`,
    `/bin/chmod 555 ${[...frozenRelativeDirectories].sort().map((relativePath) => `"$object_fd_root/${relativePath}"`).join(' ')} "$object_fd_root"`,
    'if [ -x /usr/bin/sync ]; then /usr/bin/sync; else /bin/sync; fi',
    'if [ -z "$prefix" ]; then',
    `  /usr/bin/chattr +i -- ${[...frozenRelativeDirectories].sort().map((relativePath) => `"$object_fd_root/${relativePath}"`).join(' ')} "$object_fd_root"`,
    `  for frozen_directory in ${[...frozenRelativeDirectories].sort().map((relativePath) => `"$object_fd_root/${relativePath}"`).join(' ')} "$object_fd_root"; do`,
    '    /usr/bin/sync -f "$frozen_directory"',
    '    immutable_flags=$(/usr/bin/lsattr -d -- "$frozen_directory" | /usr/bin/awk "{print \\$1}")',
    '    case "$immutable_flags" in *i*) ;; *) exit 1 ;; esac',
    '  done',
    'fi',
    `node_path="$object_root/runtime/node-${request.node_sha256}"`,
    `controller_path="$object_root/git/${request.controller.git_blob_oid}/ci3-bridge-controller.mjs"`,
    `exec 8<"$object_fd_root/runtime/node-${request.node_sha256}"`,
    `exec 9<"$object_fd_root/git/${request.controller.git_blob_oid}/ci3-bridge-controller.mjs"`,
    'node_fd_path="$fd_root/8"',
    'controller_fd_path="$fd_root/9"',
    ...(primitivePreparedBytes === null || syntheticPrimitiveBarrierStage !== 'opened-before-authentication' ? [] : [
      'make_directory "$prefix/.ci3-synthetic-barriers" 700',
      `publish_synthetic_marker "$prefix/.ci3-synthetic-barriers/publisher0-primitive-${syntheticPrimitiveBarrierStage}.prepared.json" ${shellSingleQuoted(primitivePreparedBytes.toString('base64'), code)} ${shellSingleQuoted(sha256(primitivePreparedBytes), code)}`,
      `primitive_release_path="$prefix/.ci3-synthetic-barriers/publisher0-primitive-${syntheticPrimitiveBarrierStage}.continue.json"`,
      'primitive_wait=0',
      'while [ ! -f "$primitive_release_path" ]; do',
      '  primitive_wait=$((primitive_wait + 1))',
      '  test "$primitive_wait" -le 6000',
      '  /bin/sleep 0.01',
      'done',
      'primitive_release_sha=$(/usr/bin/openssl dgst -sha256 "$primitive_release_path" | /usr/bin/awk "{print \\$NF}")',
      `test "$primitive_release_sha" = ${shellSingleQuoted(sha256(primitiveReleaseBytes), code)}`,
    ]),
    'node_fd_sha=$(/usr/bin/openssl dgst -sha256 "$node_fd_path" | /usr/bin/awk "{print \\$NF}")',
    'controller_fd_sha=$(/usr/bin/openssl dgst -sha256 "$controller_fd_path" | /usr/bin/awk "{print \\$NF}")',
    `test "$node_fd_sha" = ${shellSingleQuoted(request.node_sha256, code)}`,
    `test "$controller_fd_sha" = ${shellSingleQuoted(request.controller.sha256, code)}`,
    ...(primitiveAuthenticatedBytes === null ? [] : [
      'make_directory "$prefix/.ci3-synthetic-barriers" 700',
      `publish_synthetic_marker "$prefix/.ci3-synthetic-barriers/publisher0-primitive-descriptors-authenticated.json" ${shellSingleQuoted(primitiveAuthenticatedBytes.toString('base64'), code)} ${shellSingleQuoted(sha256(primitiveAuthenticatedBytes), code)}`,
    ]),
    ...(primitivePreparedBytes === null || syntheticPrimitiveBarrierStage !== 'authenticated-before-execution' ? [] : [
      'make_directory "$prefix/.ci3-synthetic-barriers" 700',
      `publish_synthetic_marker "$prefix/.ci3-synthetic-barriers/publisher0-primitive-${syntheticPrimitiveBarrierStage}.prepared.json" ${shellSingleQuoted(primitivePreparedBytes.toString('base64'), code)} ${shellSingleQuoted(sha256(primitivePreparedBytes), code)}`,
      `primitive_release_path="$prefix/.ci3-synthetic-barriers/publisher0-primitive-${syntheticPrimitiveBarrierStage}.continue.json"`,
      'primitive_wait=0',
      'while [ ! -f "$primitive_release_path" ]; do',
      '  primitive_wait=$((primitive_wait + 1))',
      '  test "$primitive_wait" -le 6000',
      '  /bin/sleep 0.01',
      'done',
      'primitive_release_sha=$(/usr/bin/openssl dgst -sha256 "$primitive_release_path" | /usr/bin/awk "{print \\$NF}")',
      `test "$primitive_release_sha" = ${shellSingleQuoted(sha256(primitiveReleaseBytes), code)}`,
    ]),
    'actual_object_tree=$(cd "$object_fd_root" && /usr/bin/find . -mindepth 1 -print | /usr/bin/sed "s#^\\./##" | /usr/bin/sort)',
    'actual_object_tree_sha=$(printf "%s" "$actual_object_tree" | /usr/bin/openssl dgst -sha256 | /usr/bin/awk "{print \\$NF}")',
    `test "$actual_object_tree_sha" = ${shellSingleQuoted(sha256(Buffer.from(expectedObjectTree)), code)}`,
    'if [ -n "$prefix" ]; then',
    '  node_fd_inode=$(/usr/bin/stat -f "%i" "$node_fd_path")',
    '  controller_fd_inode=$(/usr/bin/stat -f "%i" "$controller_fd_path")',
    '  test "$node_fd_inode" = "$(/usr/bin/stat -f "%i" "$node_path")"',
    '  test "$controller_fd_inode" = "$(/usr/bin/stat -f "%i" "$controller_path")"',
    'else',
    '  node_fd_identity=$(/usr/bin/stat -Lc "uid=%u;gid=%g;mode=%a;nlink=%h;size=%s;mtime=%y;dev=%d;ino=%i" "$node_fd_path")',
    '  controller_fd_identity=$(/usr/bin/stat -Lc "uid=%u;gid=%g;mode=%a;nlink=%h;size=%s;mtime=%y;dev=%d;ino=%i" "$controller_fd_path")',
    '  test "$node_fd_identity" = "$(/usr/bin/stat -Lc "uid=%u;gid=%g;mode=%a;nlink=%h;size=%s;mtime=%y;dev=%d;ino=%i" "$node_path")"',
    '  test "$controller_fd_identity" = "$(/usr/bin/stat -Lc "uid=%u;gid=%g;mode=%a;nlink=%h;size=%s;mtime=%y;dev=%d;ino=%i" "$controller_path")"',
    '  /usr/bin/sync -f "$node_fd_path"',
    '  /usr/bin/sync -f "$controller_fd_path"',
    '  node_flags=$(/usr/bin/lsattr -d -- "$node_fd_path" | /usr/bin/awk "{print \\$1}")',
    '  controller_flags=$(/usr/bin/lsattr -d -- "$controller_fd_path" | /usr/bin/awk "{print \\$1}")',
    '  case "$node_flags" in *i*) ;; *) exit 1 ;; esac',
    '  case "$controller_flags" in *i*) ;; *) exit 1 ;; esac',
    'fi',
    `transaction_root="$prefix/var/lib/agentempp/ci3-vps-authority/${request.authority_sha}/${request.transaction_generation_id}"`,
    'prepared_output_path="$transaction_root/authenticated-publisher0-output.prepared.json"',
    'output_path="$transaction_root/authenticated-publisher0-output.json"',
    'payload_root="$transaction_root/publisher-input"',
    'commit_remote() {',
    '  test ! -e "$output_path"',
    '  test -f "$prepared_output_path"',
    '  test ! -L "$prepared_output_path"',
    '  prepared_output_sha=$(/usr/bin/openssl dgst -sha256 "$prepared_output_path" | /usr/bin/awk "{print \\$NF}")',
    '  test "$prepared_output_sha" = "$output_sha"',
    '  if [ -n "$prefix" ]; then',
    '    test "$(/usr/bin/stat -f "%Lp" "$payload_root")" = 555',
    '    test "$(/usr/bin/stat -f "%Lp" "$transaction_root")" = 555',
    '  else',
    '    test "$(/usr/bin/stat -c "%a" "$payload_root")" = 555',
    '    test "$(/usr/bin/stat -c "%a" "$transaction_root")" = 555',
    '  fi',
    '  prepared_tree=$(cd "$transaction_root" && /usr/bin/find . -mindepth 1 -maxdepth 1 -print | /usr/bin/sed "s#^\\./##" | /usr/bin/sort)',
    `  test "$(printf "%s" "$prepared_tree" | /usr/bin/openssl dgst -sha256 | /usr/bin/awk "{print \\$NF}")" = ${shellSingleQuoted(sha256(Buffer.from([
      'authenticated-publisher0-output.prepared.json', 'issuer-authority.receipt.json', 'issuer-signing-key.pkcs8',
      'publisher-input', 'publisher-input-manifest.json', 'publisher0.claim.json',
      'vps-operation-authority.pass.json', 'vps-operation-authority.unsigned.json',
    ].sort().join('\n'))), code)}`,
    '  await_synthetic_transport_barrier remote-before-terminal-link',
    '  /bin/ln "$prepared_output_path" "$output_path"',
    '  await_synthetic_transport_barrier remote-after-terminal-link-before-directory-fsync',
    '  /bin/sync -f "$transaction_root"',
    '  await_synthetic_transport_barrier remote-after-directory-fsync-before-terminal-decision',
    '  printf "CI3_REMOTE_COMMIT_DECISION_V1 %s %s\\n" "$output_sha" "$request_sha" >&2',
    '}',
    'if [ -z "$prefix" ]; then',
    `  ${productionDispatch}`,
    'else',
    `  ${syntheticDispatch}`,
    'fi',
    'output_sha=$(/usr/bin/openssl dgst -sha256 "$prepared_output_path" | /usr/bin/awk "{print \\$NF}")',
    durableTransport ? 'verify_durable_ack() {' : '',
    durableTransport ? '  IFS= read -r durable_ack' : '',
    durableTransport ? '  set -- $durable_ack' : '',
    durableTransport ? '  if [ "$#" -ne 3 ]; then echo ACK_SHAPE_MISMATCH >&2; return 1; fi' : '',
    durableTransport ? '  if [ "$1" != CI3_LOCAL_DURABLE_ACK_V1 ]; then echo ACK_PROTOCOL_MISMATCH >&2; return 1; fi' : '',
    durableTransport ? '  if [ "$2" != "$output_sha" ]; then echo ACK_OUTPUT_MISMATCH >&2; return 1; fi' : '',
    durableTransport ? '  if [ "$3" != "$request_sha" ]; then echo ACK_REQUEST_MISMATCH >&2; return 1; fi' : '',
    durableTransport ? '}' : '',
    durableTransport ? "verify_durable_ack <<'CI3_LOCAL_DURABLE_ACK_BODY' && commit_remote" : 'commit_remote',
    durableTransport ? '' : '',
  );
  return Buffer.from(`${lines.filter((line) => line !== '').join('\n')}\n`);
}

export function buildPublisher0GitBoundBootstrapInvocation({
  configPath, destinationAlias, context, bootstrapInputs, syntheticRemoteRoot = null,
  syntheticBarrierStage = null, syntheticPrimitiveBarrierStage = null,
  syntheticTransportBarrierRoot = null, syntheticTransportBarrierStage = null,
  durableTransport = true,
} = {}) {
  const code = 'VPS_PUBLISHER0_PROVISION';
  requireAbsoluteSafePath(configPath, code);
  if (destinationAlias !== 'ci3-publisher0') fail(code);
  const authority = contextFields(context, code);
  const component = (role, expectedPath) => {
    const value = authority.components[role];
    exactKeys(value, ['path', 'blob_oid', 'sha256'], code);
    if (value.path !== expectedPath) fail(code);
    requireHex(value.blob_oid, code, [40]);
    requireHex(value.sha256, code);
    return {
      git_path: value.path,
      git_blob_oid: value.blob_oid,
      sha256: value.sha256,
    };
  };
  const controller = component('controller', 'scripts/ci3/ci3-bridge-controller.mjs');
  const launcher = component('launcher', 'scripts/ci3/ci3-bridge-launcher.zsh');
  exactKeys(bootstrapInputs, TRANSPORT_ROLES, code);
  const entries = TRANSPORT_ROLES.map((role) => {
    const bytes = bootstrapInputs[role];
    if (!Buffer.isBuffer(bytes) || bytes.length === 0) fail(code);
    const gitComponent = role === 'controller' ? controller : role === 'launcher-runtime' ? launcher : null;
    return {
      role,
      relative_path: publisher0BootstrapRelativePath(role, { node_sha256: context.node_candidate_sha256, controller, launcher }),
      sha256: sha256(bytes),
      byte_length: bytes.length,
      mode: publisher0BootstrapInputMode(role),
      git_path: gitComponent?.git_path ?? null,
      git_blob_oid: gitComponent?.git_blob_oid ?? null,
      bytes_base64: bytes.toString('base64'),
    };
  });
  if (entries[0].sha256 !== context.node_candidate_sha256
      || entries[1].sha256 !== controller.sha256 || gitBlobOid(bootstrapInputs.controller) !== controller.git_blob_oid
      || entries[2].sha256 !== launcher.sha256 || gitBlobOid(bootstrapInputs['launcher-runtime']) !== launcher.git_blob_oid
      || entries[4].sha256 !== authority.manifest_sha256
      || entries[5].sha256 !== context.operation_authority_sha256) fail(code);
  const generationRoot = {
    authority_sha: authority.commit,
    authority_parent: authority.parent,
    authority_tree: authority.tree,
    authority_subject_sha256: authority.subject_sha256,
    authority_manifest_sha256: authority.manifest_sha256,
    node_sha256: context.node_candidate_sha256,
    controller,
    launcher,
  };
  const inputProvenance = {
    authority_sha: authority.commit,
    authority_manifest_sha256: authority.manifest_sha256,
    entries: entries.map(({ role, relative_path: relativePath, sha256: entrySha256, byte_length: byteLength, mode, git_path: gitPath, git_blob_oid: gitBlobOidValue }) => ({
      role, relative_path: relativePath, sha256: entrySha256, byte_length: byteLength, mode,
      git_path: gitPath, git_blob_oid: gitBlobOidValue,
    })),
  };
  const request = {
    schema_version: 1,
    purpose: 'CI3_VPS_PUBLISHER0_ZERO_PRESEED_REQUEST_V1',
    ...generationRoot,
    bootstrap_generation_id: `bootstrap-${sha256(canonicalJson(generationRoot))}`,
    transaction_generation_id: `publisher0-${sha256(canonicalJson(inputProvenance))}`,
    remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
    operation_authority_sha256: context.operation_authority_sha256,
    collector_contracts_sha256: context.collector_contracts_sha256,
    input_provenance_sha256: sha256(canonicalJson(inputProvenance)),
    entries,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  const requestBytes = canonicalJson(request);
  if (syntheticBarrierStage !== null
      && (syntheticRemoteRoot === null || syntheticBarrierStage !== 'physical-freeze-readback')) fail(code);
  if (syntheticPrimitiveBarrierStage !== null
      && (syntheticRemoteRoot === null
        || !['opened-before-authentication', 'authenticated-before-execution'].includes(syntheticPrimitiveBarrierStage))) fail(code);
  if ((syntheticTransportBarrierRoot === null) !== (syntheticTransportBarrierStage === null)) fail(code);
  if (syntheticTransportBarrierRoot !== null) {
    requireAbsoluteSafePath(syntheticTransportBarrierRoot, code);
    if (syntheticRemoteRoot === null || ![
      'remote-before-terminal-link',
      'remote-after-terminal-link-before-directory-fsync',
      'remote-after-directory-fsync-before-terminal-decision',
    ].includes(syntheticTransportBarrierStage)) fail(code);
  }
  if (typeof durableTransport !== 'boolean' || (!durableTransport && syntheticRemoteRoot === null)) fail(code);
  const input = buildPublisher0RemoteShellProgram({
    request, requestBytes, syntheticBarrierStage, syntheticPrimitiveBarrierStage,
    syntheticTransportBarrierRoot, syntheticTransportBarrierStage, durableTransport,
  });
  let syntheticEnvironment = '';
  if (syntheticRemoteRoot !== null) {
    requireAbsoluteSafePath(syntheticRemoteRoot, code);
    syntheticEnvironment = ` CI3_SYNTHETIC_TEST=1 CI3_SYNTHETIC_PUBLISHER0_REMOTE_ROOT=${shellSingleQuoted(syntheticRemoteRoot, code)}`;
  }
  const remoteCommand = `exec /usr/bin/env -i HOME=/var/empty LANG=C LC_ALL=C PATH=/usr/bin:/bin${syntheticEnvironment} /bin/sh -s -- ${sha256(requestBytes)}`;
  return Object.freeze({
    executable: '/usr/bin/ssh',
    argv: ['-F', configPath, '-o', 'BatchMode=yes', '-o', 'NumberOfPasswordPrompts=0', destinationAlias, remoteCommand],
    input, input_sha256: sha256(input), request_sha256: sha256(requestBytes),
    attempts: 1,
    retry: false,
  });
}

function contextFields(context, code) {
  if (!isPlainObject(context) || !isPlainObject(context.authority) || !isPlainObject(context.authority.components)
      || !isPlainObject(context.generations)) fail(code);
  const authority = context.authority;
  for (const field of ['commit', 'parent', 'tree']) requireHex(authority[field], code, [40]);
  for (const field of ['subject_sha256', 'manifest_sha256']) requireHex(authority[field], code);
  for (const role of ['writer', 'controller', 'launcher']) {
    if (!isPlainObject(authority.components[role])) fail(code);
    requireHex(authority.components[role].sha256, code);
  }
  requireGeneration(context.generations.remote, code);
  requireGeneration(context.generations.controller, code);
  for (const field of ['collector_contracts_sha256', 'node_candidate_sha256', 'operation_authority_sha256']) requireHex(context[field], code);
  if (context.production_frozen_inputs !== undefined) {
    validateProductionFrozenInputConsumerBinding(context.production_frozen_inputs, code);
  }
  return authority;
}

export function buildVpsIssuerAuthority({ authoritySha, issuerGenerationId, publicKey } = {}) {
  const code = 'VPS_ISSUER_AUTHORITY';
  requireHex(authoritySha, code, [40]);
  requireGeneration(issuerGenerationId, code);
  let publicRaw;
  try {
    const key = publicKey?.type === 'public' ? publicKey : createPublicKey(publicKey);
    publicRaw = rawEd25519PublicKey(key, code);
  } catch { fail(code); }
  const issuer = {
    schema_version: 1,
    purpose: 'CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1',
    authority_sha: authoritySha,
    issuer_generation_id: issuerGenerationId,
    public_key_algorithm: 'Ed25519',
    public_key_raw_base64: publicRaw.toString('base64'),
    public_key_sha256: sha256(publicRaw),
    issuer_identity_sha256: sha256(Buffer.concat([Buffer.from(authoritySha), Buffer.from(issuerGenerationId), publicRaw])),
    allowed_pass_purpose: 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1',
    normal_executor_authorized: false,
    raw_values: false,
  };
  validateVpsIssuerAuthority(issuer);
  return issuer;
}

export function validateVpsIssuerAuthority(issuer) {
  const code = 'VPS_ISSUER_AUTHORITY';
  exactKeys(issuer, [
    'schema_version', 'purpose', 'authority_sha', 'issuer_generation_id', 'public_key_algorithm',
    'public_key_raw_base64', 'public_key_sha256', 'issuer_identity_sha256', 'allowed_pass_purpose',
    'normal_executor_authorized', 'raw_values',
  ], code);
  if (issuer.schema_version !== 1 || issuer.purpose !== 'CI3_VPS_EXTERNAL_ISSUER_AUTHORITY_V1'
      || issuer.public_key_algorithm !== 'Ed25519'
      || issuer.allowed_pass_purpose !== 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1'
      || issuer.normal_executor_authorized !== false || issuer.raw_values !== false) fail(code);
  requireHex(issuer.authority_sha, code, [40]);
  requireGeneration(issuer.issuer_generation_id, code);
  for (const field of ['public_key_sha256', 'issuer_identity_sha256']) requireHex(issuer[field], code);
  let raw;
  try {
    raw = Buffer.from(issuer.public_key_raw_base64, 'base64');
    if (raw.length !== 32 || raw.toString('base64') !== issuer.public_key_raw_base64) fail(code);
    rawEd25519PublicKey(publicKeyFromRawEd25519(raw, code), code);
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  }
  if (sha256(raw) !== issuer.public_key_sha256
      || sha256(Buffer.concat([Buffer.from(issuer.authority_sha), Buffer.from(issuer.issuer_generation_id), raw])) !== issuer.issuer_identity_sha256) fail(code);
  return true;
}

function rawEd25519PublicKey(key, code) {
  if (!key || key.type !== 'public' || key.asymmetricKeyType !== 'ed25519') fail(code);
  const der = Buffer.from(key.export({ type: 'spki', format: 'der' }));
  if (der.length !== ED25519_SPKI_PREFIX.length + 32 || !der.subarray(0, ED25519_SPKI_PREFIX.length).equals(ED25519_SPKI_PREFIX)) fail(code);
  return der.subarray(ED25519_SPKI_PREFIX.length);
}

function publicKeyFromRawEd25519(raw, code) {
  if (!Buffer.isBuffer(raw) || raw.length !== 32) fail(code);
  try {
    const key = createPublicKey({ key: Buffer.concat([ED25519_SPKI_PREFIX, raw]), format: 'der', type: 'spki' });
    if (key.asymmetricKeyType !== 'ed25519') fail(code);
    return key;
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  }
}

export function buildPublisherInputManifest({ context, entries } = {}) {
  const code = 'PUBLISHER_INPUT_MANIFEST';
  const authority = contextFields(context, code);
  if (!Array.isArray(entries) || entries.length !== TRANSPORT_ROLES.length) fail(code);
  const normalized = entries.map((entry, index) => {
    exactKeys(entry, ['role', 'path_sha256', 'sha256'], code);
    if (entry.role !== TRANSPORT_ROLES[index]) fail(code);
    requireHex(entry.path_sha256, code);
    requireHex(entry.sha256, code);
    return { role: entry.role, path_sha256: entry.path_sha256, sha256: entry.sha256 };
  });
  const manifest = {
    schema_version: 1,
    purpose: 'CI3_VPS_PUBLISHER_INPUT_MANIFEST_V2',
    authority_sha: authority.commit,
    remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
    collector_contracts_sha256: context.collector_contracts_sha256,
    entries: normalized,
    transfer_payload_sha256: sha256(canonicalJson(normalized)),
    raw_values: false,
  };
  validatePublisherInputManifest(manifest, context);
  return manifest;
}

export function validatePublisherInputManifest(manifest, context) {
  const code = 'PUBLISHER_INPUT_MANIFEST';
  const authority = contextFields(context, code);
  exactKeys(manifest, [
    'schema_version', 'purpose', 'authority_sha', 'remote_generation_id', 'controller_generation_id',
    'collector_contracts_sha256', 'entries', 'transfer_payload_sha256', 'raw_values',
  ], code);
  if (manifest.schema_version !== 1 || manifest.purpose !== 'CI3_VPS_PUBLISHER_INPUT_MANIFEST_V2'
      || manifest.authority_sha !== authority.commit || manifest.remote_generation_id !== context.generations.remote
      || manifest.controller_generation_id !== context.generations.controller
      || manifest.collector_contracts_sha256 !== context.collector_contracts_sha256
      || manifest.raw_values !== false || !Array.isArray(manifest.entries)
      || manifest.entries.length !== TRANSPORT_ROLES.length) fail(code);
  manifest.entries.forEach((entry, index) => {
    exactKeys(entry, ['role', 'path_sha256', 'sha256'], code);
    if (entry.role !== TRANSPORT_ROLES[index]) fail(code);
    requireHex(entry.path_sha256, code);
    requireHex(entry.sha256, code);
  });
  requireHex(manifest.transfer_payload_sha256, code);
  if (manifest.transfer_payload_sha256 !== sha256(canonicalJson(manifest.entries))) fail(code);
  return true;
}

export function buildAuthenticatedPublisher0Output({ context, issuer, pass, transportManifest, payloads } = {}) {
  const code = 'AUTHENTICATED_PUBLISHER0_OUTPUT';
  const authority = contextFields(context, code);
  validateVpsIssuerAuthority(issuer);
  verifyVpsPass(pass, issuer, context);
  validatePublisherInputManifest(transportManifest, context);
  exactKeys(payloads, TRANSPORT_ROLES, code);
  if (pass.publisher_input_manifest_sha256 !== sha256(canonicalJson(transportManifest))) fail(code);
  const encoded = TRANSPORT_ROLES.map((role, index) => {
    const bytes = payloads[role];
    if (!Buffer.isBuffer(bytes) || bytes.length === 0 || sha256(bytes) !== transportManifest.entries[index].sha256) fail(code);
    return { role, bytes_base64: bytes.toString('base64'), sha256: sha256(bytes) };
  });
  const output = {
    schema_version: 2,
    purpose: 'CI3_AUTHENTICATED_PUBLISHER0_OUTPUT_V2',
    authority_sha: authority.commit,
    remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
    issuer,
    pass,
    transport_manifest: transportManifest,
    payloads: encoded,
    payload_set_sha256: sha256(canonicalJson(encoded.map(({ role, sha256: payloadSha256 }) => ({ role, sha256: payloadSha256 })))),
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  validateAuthenticatedPublisher0Output(output, context);
  return output;
}

export function validateAuthenticatedPublisher0Output(output, context) {
  const code = 'AUTHENTICATED_PUBLISHER0_OUTPUT';
  const authority = contextFields(context, code);
  exactKeys(output, [
    'schema_version', 'purpose', 'authority_sha', 'remote_generation_id', 'controller_generation_id',
    'issuer', 'pass', 'transport_manifest', 'payloads', 'payload_set_sha256', 'attempt', 'retry', 'raw_values',
  ], code);
  if (output.schema_version !== 2 || output.purpose !== 'CI3_AUTHENTICATED_PUBLISHER0_OUTPUT_V2'
      || output.authority_sha !== authority.commit || output.remote_generation_id !== context.generations.remote
      || output.controller_generation_id !== context.generations.controller || output.attempt !== 1
      || output.retry !== false || output.raw_values !== false || !Array.isArray(output.payloads)
      || output.payloads.length !== TRANSPORT_ROLES.length) fail(code);
  validateVpsIssuerAuthority(output.issuer);
  verifyVpsPass(output.pass, output.issuer, context);
  validatePublisherInputManifest(output.transport_manifest, context);
  if (output.pass.publisher_input_manifest_sha256 !== sha256(canonicalJson(output.transport_manifest))) fail(code);
  const payloads = {};
  const roots = [];
  output.payloads.forEach((entry, index) => {
    exactKeys(entry, ['role', 'bytes_base64', 'sha256'], code);
    const role = TRANSPORT_ROLES[index];
    if (entry.role !== role || typeof entry.bytes_base64 !== 'string') fail(code);
    requireHex(entry.sha256, code);
    const bytes = Buffer.from(entry.bytes_base64, 'base64');
    if (bytes.length === 0 || bytes.toString('base64') !== entry.bytes_base64
        || sha256(bytes) !== entry.sha256 || entry.sha256 !== output.transport_manifest.entries[index].sha256) fail(code);
    payloads[role] = bytes;
    roots.push({ role, sha256: entry.sha256 });
  });
  requireHex(output.payload_set_sha256, code);
  if (output.payload_set_sha256 !== sha256(canonicalJson(roots))) fail(code);
  return Object.freeze({
    issuer: output.issuer,
    pass: output.pass,
    transportManifest: output.transport_manifest,
    payloads: Object.freeze(payloads),
    raw_values: false,
  });
}

const PUBLISHER1_OPERATIONAL_MODES = Object.freeze([
  '--self-test', 'plan', 'verify-simulator', 'verify-ssh', 'fetch', 'install-simulator', 'scan',
  'write-terminal-anchor', 'resume', 'publish-operation-authority',
  'publish-privileged-writer-authority', 'status',
]);

export function buildPublisher1LauncherBootstrapAuthority({ context, payloads } = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  exactKeys(payloads, TRANSPORT_ROLES, code);
  for (const role of TRANSPORT_ROLES) if (!Buffer.isBuffer(payloads[role]) || payloads[role].length === 0) fail(code);
  if (sha256(payloads['node-runtime']) !== context.node_candidate_sha256
      || sha256(payloads.controller) !== authority.components.controller.sha256
      || sha256(payloads['launcher-runtime']) !== authority.components.launcher.sha256
      || sha256(payloads['authority-manifest']) !== authority.manifest_sha256) fail(code);
  const successor = context.production_frozen_inputs !== undefined;
  let launchAttestation;
  if (successor) {
    try { launchAttestation = JSON.parse(payloads['launch-attestation']); } catch { fail(code); }
    validateLaunchAttestation(launchAttestation);
    if (launchAttestation.purpose !== 'CI3_GIT_BOUND_LAUNCH_ATTESTATION_V3'
        || !canonicalJson(launchAttestation.production_frozen_inputs)
          .equals(canonicalJson(context.production_frozen_inputs))) fail(code);
  }
  return Buffer.from([
    successor ? 'CI3_EXTERNAL_LAUNCHER_AUTHORITY_V2' : 'CI3_EXTERNAL_LAUNCHER_AUTHORITY_V1',
    `authority_sha ${authority.commit}`,
    `controller_generation_id ${context.generations.controller}`,
    `node_sha256 ${sha256(payloads['node-runtime'])}`,
    `controller_sha256 ${sha256(payloads.controller)}`,
    `launcher_sha256 ${sha256(payloads['launcher-runtime'])}`,
    `launch_attestation_sha256 ${sha256(payloads['launch-attestation'])}`,
    `authority_manifest_sha256 ${sha256(payloads['authority-manifest'])}`,
    ...(successor ? [
      `node_capsule_manifest_sha256 ${launchAttestation.tools.node.capsule_manifest_sha256}`,
      `node_capsule_receipt_sha256 ${launchAttestation.tools.node.capsule_receipt_sha256}`,
      `production_frozen_inputs_sha256 ${sha256(canonicalJson(context.production_frozen_inputs))}`,
    ] : []),
    `allowed_modes ${PUBLISHER1_OPERATIONAL_MODES.join(',')}`,
    'raw_values false',
    '',
  ].join('\n'));
}

export function buildUnsignedVpsPass({ context, issuer, publisherInputManifestSha256, transferPayloadSha256 } = {}) {
  const code = 'VPS_OPERATION_AUTHORITY_SIGNATURE';
  const authority = contextFields(context, code);
  validateVpsIssuerAuthority(issuer);
  requireHex(publisherInputManifestSha256, code);
  requireHex(transferPayloadSha256, code);
  if (issuer.authority_sha !== authority.commit) fail(code);
  return {
    schema_version: 1,
    purpose: 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1',
    authority_sha: authority.commit,
    authority_parent: authority.parent,
    authority_tree: authority.tree,
    authority_subject_sha256: authority.subject_sha256,
    authority_manifest_sha256: authority.manifest_sha256,
    operation_authority_sha256: context.operation_authority_sha256,
    node_candidate_sha256: context.node_candidate_sha256,
    collector_contracts_sha256: context.collector_contracts_sha256,
    publisher_input_manifest_sha256: publisherInputManifestSha256,
    remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
    transfer_payload_sha256: transferPayloadSha256,
    issuer_authority_sha256: sha256(canonicalJson(issuer)),
    issuer_key_sha256: issuer.public_key_sha256,
    source_generation_id: `src-${sha256(canonicalJson(issuer))}`,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
}

export function signVpsPass({ unsigned, issuer, privateKey } = {}) {
  const code = 'VPS_OPERATION_AUTHORITY_SIGNATURE';
  validateVpsIssuerAuthority(issuer);
  validateUnsignedPass(unsigned, issuer, null, code);
  let signature;
  try {
    const key = privateKey?.type === 'private' ? privateKey : createPrivateKey(privateKey);
    if (key.asymmetricKeyType !== 'ed25519'
        || !rawEd25519PublicKey(createPublicKey(key), code).equals(Buffer.from(issuer.public_key_raw_base64, 'base64'))) fail(code);
    signature = signDetached(null, canonicalJson(unsigned), key);
  } catch { fail(code); }
  return {
    ...unsigned,
    signed_payload_sha256: sha256(canonicalJson(unsigned)),
    signature_base64: signature.toString('base64'),
  };
}

function validateUnsignedPass(unsigned, issuer, context, code) {
  exactKeys(unsigned, [
    'schema_version', 'purpose', 'authority_sha', 'authority_parent', 'authority_tree', 'authority_subject_sha256',
    'authority_manifest_sha256', 'operation_authority_sha256', 'node_candidate_sha256', 'collector_contracts_sha256',
    'publisher_input_manifest_sha256', 'remote_generation_id', 'controller_generation_id', 'transfer_payload_sha256',
    'issuer_authority_sha256', 'issuer_key_sha256', 'source_generation_id', 'attempt', 'retry', 'raw_values',
  ], code);
  if (unsigned.schema_version !== 1 || unsigned.purpose !== 'CI3_VPS_OPERATION_AUTHORITY_PASS_V1'
      || unsigned.attempt !== 1 || unsigned.retry !== false || unsigned.raw_values !== false
      || unsigned.issuer_authority_sha256 !== sha256(canonicalJson(issuer))
      || unsigned.issuer_key_sha256 !== issuer.public_key_sha256
      || !unsigned.source_generation_id.startsWith('src-')) fail(code);
  requireHex(unsigned.authority_sha, code, [40]);
  requireHex(unsigned.authority_parent, code, [40]);
  requireHex(unsigned.authority_tree, code, [40]);
  for (const field of [
    'authority_subject_sha256', 'authority_manifest_sha256', 'operation_authority_sha256', 'node_candidate_sha256',
    'collector_contracts_sha256', 'publisher_input_manifest_sha256', 'transfer_payload_sha256',
    'issuer_authority_sha256', 'issuer_key_sha256',
  ]) requireHex(unsigned[field], code);
  requireGeneration(unsigned.remote_generation_id, code);
  requireGeneration(unsigned.controller_generation_id, code);
  requireGeneration(unsigned.source_generation_id, code);
  if (context) {
    const authority = contextFields(context, code);
    if (unsigned.authority_sha !== authority.commit || unsigned.authority_parent !== authority.parent
        || unsigned.authority_tree !== authority.tree || unsigned.authority_subject_sha256 !== authority.subject_sha256
        || unsigned.authority_manifest_sha256 !== authority.manifest_sha256
        || unsigned.operation_authority_sha256 !== context.operation_authority_sha256
        || unsigned.node_candidate_sha256 !== context.node_candidate_sha256
        || unsigned.collector_contracts_sha256 !== context.collector_contracts_sha256
        || unsigned.remote_generation_id !== context.generations.remote
        || unsigned.controller_generation_id !== context.generations.controller) fail(code);
  }
  return true;
}

export function verifyVpsPass(pass, issuer, context) {
  const code = 'VPS_OPERATION_AUTHORITY_SIGNATURE';
  try {
    validateVpsIssuerAuthority(issuer);
    exactKeys(pass, [
      'schema_version', 'purpose', 'authority_sha', 'authority_parent', 'authority_tree', 'authority_subject_sha256',
      'authority_manifest_sha256', 'operation_authority_sha256', 'node_candidate_sha256', 'collector_contracts_sha256',
      'publisher_input_manifest_sha256', 'remote_generation_id', 'controller_generation_id', 'transfer_payload_sha256',
      'issuer_authority_sha256', 'issuer_key_sha256', 'source_generation_id', 'attempt', 'retry', 'raw_values', 'signed_payload_sha256', 'signature_base64',
    ], code);
    const { signature_base64: encoded, signed_payload_sha256: signedPayloadSha256, ...unsigned } = pass;
    validateUnsignedPass(unsigned, issuer, context, code);
    if (typeof encoded !== 'string' || !isHex(signedPayloadSha256) || signedPayloadSha256 !== sha256(canonicalJson(unsigned))) fail(code);
    const signature = Buffer.from(encoded, 'base64');
    if (signature.length === 0 || signature.toString('base64') !== encoded) fail(code);
    const publicKey = publicKeyFromRawEd25519(Buffer.from(issuer.public_key_raw_base64, 'base64'), code);
    if (!verifyDetached(null, canonicalJson(unsigned), publicKey, signature)) fail(code);
    return true;
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  }
}

function validateLeaf(leaf, expectedRole, code, withPath = false) {
  exactKeys(leaf, withPath
    ? ['role', 'path', 'path_sha256', 'sha256', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtime_ns', 'dev', 'ino', 'identity_sha256']
    : ['role', 'path_sha256', 'sha256', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtime_ns', 'dev', 'ino', 'identity_sha256'], code);
  if (leaf.role !== expectedRole || !Number.isInteger(leaf.uid) || leaf.uid <= 0
      || !Number.isInteger(leaf.gid) || leaf.gid <= 0 || leaf.mode !== 0o600 || leaf.nlink !== 1
      || !Number.isInteger(leaf.size) || leaf.size < 0) fail(code);
  for (const field of ['path_sha256', 'sha256', 'identity_sha256']) requireHex(leaf[field], code);
  if (withPath && (!path.isAbsolute(leaf.path) || leaf.path.includes('/../') || /[\0\r\n]/.test(leaf.path)
      || path.normalize(leaf.path) !== leaf.path || leaf.path_sha256 !== sha256(Buffer.from(leaf.path)))) fail(code);
  let identity;
  try { identity = physicalIdentitySha256(leaf); } catch { fail(code); }
  if (identity !== leaf.identity_sha256) fail(code);
}

export function buildPublisher1MaterializerAuthority({
  context, requestPath, requestSha256, requestObservation, receiverRoot, receiverRootIdentitySha256,
  receiverLeaves, issuerAuthoritySha256, materializerSha256, writerSourceSha256,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  requireAbsoluteSafePath(requestPath, code);
  requireAbsoluteSafePath(receiverRoot, code);
  for (const value of [requestSha256, receiverRootIdentitySha256, issuerAuthoritySha256, materializerSha256, writerSourceSha256]) requireHex(value, code);
  exactKeys(requestObservation, ['role', 'path', 'path_sha256', 'sha256', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtime_ns', 'dev', 'ino', 'identity_sha256'], code);
  if (requestObservation.path !== requestPath || requestObservation.path_sha256 !== sha256(Buffer.from(requestPath))
      || requestObservation.mode !== 0o600 || requestObservation.nlink !== 1 || requestObservation.uid <= 0 || requestObservation.gid <= 0
      || physicalIdentitySha256(requestObservation) !== requestObservation.identity_sha256) fail(code);
  if (!Array.isArray(receiverLeaves) || receiverLeaves.length !== PUBLISHER1_ROLES.length) fail(code);
  receiverLeaves.forEach((leaf, index) => {
    validateLeaf(leaf, PUBLISHER1_ROLES[index], code, true);
    if (leaf.path !== path.join(receiverRoot, `${leaf.role}.payload`)) fail(code);
  });
  const materializerPath = path.join(
    '/Library/Application Support/Agentempp/ci3-publisher1-bootstrap', authority.commit,
    `bootstrap-${authority.manifest_sha256}`, 'runtime', 'ci3-terminal-anchor-writer',
  );
  const record = {
    schema_version: 2,
    purpose: 'CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2',
    authority_sha: authority.commit,
    controller_generation_id: context.generations.controller,
    issuer_authority_sha256: issuerAuthoritySha256,
    materializer_path: materializerPath,
    materializer_path_sha256: sha256(Buffer.from(materializerPath)),
    materializer_sha256: materializerSha256,
    writer_source_sha256: writerSourceSha256,
    request_path_sha256: sha256(Buffer.from(requestPath)),
    request_sha256: requestSha256,
    request_identity_sha256: requestObservation.identity_sha256,
    request_uid: requestObservation.uid,
    request_gid: requestObservation.gid,
    request_mode: 0o600,
    request_nlink: 1,
    receiver_root_path_sha256: sha256(Buffer.from(receiverRoot)),
    receiver_root_identity_sha256: receiverRootIdentitySha256,
    receiver_leaves: receiverLeaves.map((leaf) => ({
      role: leaf.role, path_sha256: leaf.path_sha256, sha256: leaf.sha256, uid: leaf.uid, gid: leaf.gid,
      mode: leaf.mode, nlink: leaf.nlink, size: leaf.size, mtime_ns: leaf.mtime_ns, dev: leaf.dev, ino: leaf.ino,
      identity_sha256: leaf.identity_sha256,
    })),
    allowed_environment: { ...CLOSED_ENVIRONMENT },
    normal_executor_authorized: false,
    raw_values: false,
  };
  validatePublisher1MaterializerAuthority(record, context, {
    receiverRoot,
    receiverRootIdentitySha256,
    receiverLeaves,
  });
  return record;
}

export function validatePublisher1MaterializerAuthority(record, context, expected = null) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  exactKeys(record, [
    'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'issuer_authority_sha256',
    'materializer_path', 'materializer_path_sha256', 'materializer_sha256', 'writer_source_sha256',
    'request_path_sha256', 'request_sha256', 'request_identity_sha256', 'request_uid', 'request_gid',
    'request_mode', 'request_nlink', 'receiver_root_path_sha256', 'receiver_root_identity_sha256',
    'receiver_leaves', 'allowed_environment', 'normal_executor_authorized', 'raw_values',
  ], code);
  if (record.schema_version !== 2 || record.purpose !== 'CI3_PUBLISHER1_MATERIALIZER_AUTHORITY_V2'
      || record.authority_sha !== authority.commit || record.controller_generation_id !== context.generations.controller
      || record.writer_source_sha256 !== authority.components.writer.sha256 || record.request_mode !== 0o600
      || record.request_nlink !== 1 || !Number.isInteger(record.request_uid) || record.request_uid <= 0
      || !Number.isInteger(record.request_gid) || record.request_gid <= 0
      || record.normal_executor_authorized !== false || record.raw_values !== false
      || !canonicalJson(record.allowed_environment).equals(canonicalJson(CLOSED_ENVIRONMENT))) fail(code);
  for (const field of [
    'issuer_authority_sha256', 'materializer_path_sha256', 'materializer_sha256', 'writer_source_sha256',
    'request_path_sha256', 'request_sha256', 'request_identity_sha256', 'receiver_root_path_sha256',
    'receiver_root_identity_sha256',
  ]) requireHex(record[field], code);
  const expectedPath = path.join(
    '/Library/Application Support/Agentempp/ci3-publisher1-bootstrap', authority.commit,
    `bootstrap-${authority.manifest_sha256}`, 'runtime', 'ci3-terminal-anchor-writer',
  );
  if (record.materializer_path !== expectedPath || record.materializer_path_sha256 !== sha256(Buffer.from(expectedPath))
      || !Array.isArray(record.receiver_leaves) || record.receiver_leaves.length !== PUBLISHER1_ROLES.length) fail(code);
  record.receiver_leaves.forEach((leaf, index) => validateLeaf(leaf, PUBLISHER1_ROLES[index], code));
  if (expected !== null) {
    exactKeys(expected, ['receiverRoot', 'receiverRootIdentitySha256', 'receiverLeaves'], code);
    requireAbsoluteSafePath(expected.receiverRoot, code);
    requireHex(expected.receiverRootIdentitySha256, code);
    if (!Array.isArray(expected.receiverLeaves) || expected.receiverLeaves.length !== PUBLISHER1_ROLES.length
        || record.receiver_root_path_sha256 !== sha256(Buffer.from(expected.receiverRoot))
        || record.receiver_root_identity_sha256 !== expected.receiverRootIdentitySha256) fail(code);
    const normalizedExpected = expected.receiverLeaves.map((leaf, index) => {
      validateLeaf(leaf, PUBLISHER1_ROLES[index], code, true);
      if (leaf.path !== path.join(expected.receiverRoot, `${leaf.role}.payload`)) fail(code);
      return {
        role: leaf.role, path_sha256: leaf.path_sha256, sha256: leaf.sha256, uid: leaf.uid, gid: leaf.gid,
        mode: leaf.mode, nlink: leaf.nlink, size: leaf.size, mtime_ns: leaf.mtime_ns, dev: leaf.dev, ino: leaf.ino,
        identity_sha256: leaf.identity_sha256,
      };
    });
    if (!canonicalJson(record.receiver_leaves).equals(canonicalJson(normalizedExpected))) fail(code);
  }
  return true;
}

const INSTALLER_HUMAN_BINDING_FIELDS = Object.freeze([
  'publisher_installer_compile_authority_sha256', 'publisher_installer_expected_binary_sha256',
]);

const INSTALLER_PROVENANCE_FIELDS = Object.freeze([
  'git_path', 'git_blob_oid', 'source_sha256', 'authority_manifest_sha256',
  'compile_authority_sha256', 'expected_binary_sha256',
]);

export const HUMAN_AUTHORIZATION_RECEIPT_FIELDS = Object.freeze([
  'schema_version', 'purpose', 'authority_sha', 'approved_action', 'authority_manifest_sha256',
  'operation_authority_sha256', 'authority_projection_sha256', 'publisher_input_manifest_sha256', 'vps_operation_authority_pass_sha256',
  'issuer_authority_sha256', 'node_binary_sha256', 'authorization_request_path_sha256',
  'authorization_request_sha256', 'authorization_request_identity_sha256', 'authorization_request_uid',
  'authorization_request_gid', 'authorization_request_mode', 'authorization_request_nlink',
  'receiver_root_path_sha256', 'receiver_root_identity_sha256', 'receiver_leaves_sha256',
  'publisher_installer_git_path', 'publisher_installer_git_blob_oid', 'publisher_installer_source_sha256',
  'publisher_installer_provenance_sha256', 'publisher_installer_compile_authority_sha256',
  'publisher_installer_expected_binary_sha256', 'prompt_sha256', 'prompt_budget', 'authorized_uid',
  'authorized_gid', 'confirmation_sha256', 'attempt', 'retry', 'raw_values',
]);

function authorityProjectionFromPass(pass, code = 'STOP_PRE_AUTHORITY') {
  if (!isPlainObject(pass)) fail(code);
  const projection = {
    authority_sha: pass.authority_sha,
    authority_parent: pass.authority_parent,
    authority_tree: pass.authority_tree,
    authority_subject_sha256: pass.authority_subject_sha256,
    authority_manifest_sha256: pass.authority_manifest_sha256,
    operation_authority_sha256: pass.operation_authority_sha256,
    node_candidate_sha256: pass.node_candidate_sha256,
    collector_contracts_sha256: pass.collector_contracts_sha256,
    remote_generation_id: pass.remote_generation_id,
    controller_generation_id: pass.controller_generation_id,
  };
  requireHex(projection.authority_sha, code, [40]);
  requireHex(projection.authority_parent, code, [40]);
  requireHex(projection.authority_tree, code, [40]);
  for (const field of [
    'authority_subject_sha256', 'authority_manifest_sha256', 'operation_authority_sha256',
    'node_candidate_sha256', 'collector_contracts_sha256',
  ]) requireHex(projection[field], code);
  requireGeneration(projection.remote_generation_id, code);
  requireGeneration(projection.controller_generation_id, code);
  return projection;
}

function validateInstallerProvenance(provenance, context, code) {
  const authority = contextFields(context, code);
  exactKeys(provenance, INSTALLER_PROVENANCE_FIELDS, code);
  if (provenance.git_path !== 'scripts/ci3/ci3-publisher1-bootstrap-installer.swift'
      || provenance.authority_manifest_sha256 !== authority.manifest_sha256) fail(code);
  requireHex(provenance.git_blob_oid, code, [40]);
  for (const field of ['source_sha256', 'authority_manifest_sha256', 'compile_authority_sha256', 'expected_binary_sha256']) {
    requireHex(provenance[field], code);
  }
  return true;
}

function validateHumanAuthorizationRequest(request, {
  context, manifest, pass, receiverRoot, receiverRootIdentitySha256, receiverLeaves, installerProvenance, promptSha256,
}, code = 'STOP_PRE_AUTHORITY') {
  const authority = contextFields(context, code);
  exactKeys(request, [
    'schema_version', 'purpose', 'authority_sha', 'authority_manifest_sha256', 'operation_authority_sha256', 'authority_projection_sha256',
    'publisher_input_manifest_sha256', 'vps_operation_authority_pass_sha256', 'issuer_authority_sha256',
    'receiver_root_path_sha256', 'receiver_root_identity_sha256', 'receiver_leaves_sha256',
    'installer_provenance', 'prompt_sha256', 'prompt_budget', 'attempt', 'retry', 'raw_values',
  ], code);
  requireAbsoluteSafePath(receiverRoot, code);
  requireHex(receiverRootIdentitySha256, code);
  requireHex(promptSha256, code);
  validatePublisherInputManifest(manifest, context);
  if (!Array.isArray(receiverLeaves) || receiverLeaves.length !== PUBLISHER1_RECEIVER_ROLES.length) fail(code);
  receiverLeaves.forEach((leaf, index) => {
    validateLeaf(leaf, PUBLISHER1_RECEIVER_ROLES[index], code, true);
    if (leaf.path !== path.join(receiverRoot, `${leaf.role}.payload`)) fail(code);
  });
  validateInstallerProvenance(installerProvenance, context, code);
  if (request.schema_version !== 2 || request.purpose !== 'CI3_HUMAN_AUTHORIZATION_REQUEST_V2'
      || request.authority_sha !== authority.commit || request.authority_manifest_sha256 !== authority.manifest_sha256
      || request.operation_authority_sha256 !== context.operation_authority_sha256
      || request.authority_projection_sha256 !== sha256(canonicalJson(authorityProjectionFromPass(pass, code)))
      || request.publisher_input_manifest_sha256 !== sha256(canonicalJson(manifest))
      || request.vps_operation_authority_pass_sha256 !== sha256(canonicalJson(pass))
      || request.issuer_authority_sha256 !== pass.issuer_authority_sha256
      || request.receiver_root_path_sha256 !== sha256(Buffer.from(receiverRoot))
      || request.receiver_root_identity_sha256 !== receiverRootIdentitySha256
      || request.receiver_leaves_sha256 !== sha256(canonicalJson(receiverLeaves))
      || !canonicalJson(request.installer_provenance).equals(canonicalJson(installerProvenance))
      || request.prompt_sha256 !== promptSha256 || request.prompt_budget !== 1 || request.attempt !== 1
      || request.retry !== false || request.raw_values !== false) fail(code);
  return true;
}

export function buildHumanAuthorizationRequest({
  context, issuer, manifest, pass, receiverRoot, receiverRootIdentitySha256, receiverLeaves,
  installerProvenance, promptSha256,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  validateVpsIssuerAuthority(issuer);
  verifyVpsPass(pass, issuer, context);
  const request = {
    schema_version: 2,
    purpose: 'CI3_HUMAN_AUTHORIZATION_REQUEST_V2',
    authority_sha: authority.commit,
    authority_manifest_sha256: authority.manifest_sha256,
    operation_authority_sha256: context.operation_authority_sha256,
    authority_projection_sha256: sha256(canonicalJson(authorityProjectionFromPass(pass, code))),
    publisher_input_manifest_sha256: sha256(canonicalJson(manifest)),
    vps_operation_authority_pass_sha256: sha256(canonicalJson(pass)),
    issuer_authority_sha256: sha256(canonicalJson(issuer)),
    receiver_root_path_sha256: sha256(Buffer.from(receiverRoot)),
    receiver_root_identity_sha256: receiverRootIdentitySha256,
    receiver_leaves_sha256: sha256(canonicalJson(receiverLeaves)),
    installer_provenance: installerProvenance,
    prompt_sha256: promptSha256,
    prompt_budget: 1,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  validateHumanAuthorizationRequest(request, {
    context, manifest, pass, receiverRoot, receiverRootIdentitySha256, receiverLeaves, installerProvenance, promptSha256,
  }, code);
  return request;
}

function installerBindingFromHuman(receipt, code = 'STOP_PRE_AUTHORITY') {
  if (!isPlainObject(receipt)) fail(code);
  const present = INSTALLER_HUMAN_BINDING_FIELDS.filter((field) => Object.hasOwn(receipt, field));
  if (present.length !== INSTALLER_HUMAN_BINDING_FIELDS.length) fail(code);
  for (const field of INSTALLER_HUMAN_BINDING_FIELDS) requireHex(receipt[field], code);
  return Object.freeze({
    compile_authority_sha256: receipt.publisher_installer_compile_authority_sha256,
    expected_binary_sha256: receipt.publisher_installer_expected_binary_sha256,
  });
}

export function buildHumanAuthorizationReceipt({
  context, issuer, manifest, pass, authorizationRequest, authorizationRequestObservation,
  receiverRoot, receiverRootIdentitySha256, receiverLeaves, installerProvenance, promptSha256, confirmation,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  validateVpsIssuerAuthority(issuer);
  verifyVpsPass(pass, issuer, context);
  validateHumanAuthorizationRequest(authorizationRequest, {
    context, manifest, pass, receiverRoot, receiverRootIdentitySha256, receiverLeaves, installerProvenance, promptSha256,
  }, code);
  exactKeys(authorizationRequestObservation, [
    'role', 'path', 'path_sha256', 'sha256', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtime_ns', 'dev', 'ino', 'identity_sha256',
  ], code);
  if (authorizationRequestObservation.role !== 'human-authorization-request'
      || authorizationRequestObservation.path_sha256 !== sha256(Buffer.from(authorizationRequestObservation.path))
      || authorizationRequestObservation.sha256 !== sha256(canonicalJson(authorizationRequest))
      || authorizationRequestObservation.mode !== 0o600 || authorizationRequestObservation.nlink !== 1
      || authorizationRequestObservation.uid <= 0 || authorizationRequestObservation.gid <= 0
      || authorizationRequestObservation.identity_sha256 !== physicalIdentitySha256(authorizationRequestObservation)) fail(code);
  exactKeys(confirmation, ['authorized_uid', 'authorized_gid', 'prompt_budget', 'confirmation_sha256'], code);
  if (!Number.isInteger(confirmation.authorized_uid) || confirmation.authorized_uid <= 0
      || !Number.isInteger(confirmation.authorized_gid) || confirmation.authorized_gid <= 0
      || confirmation.prompt_budget !== 1) fail(code);
  requireHex(confirmation.confirmation_sha256, code);
  const receipt = {
    schema_version: 2,
    purpose: 'CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V2',
    authority_sha: authority.commit,
    approved_action: 'PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY',
    authority_manifest_sha256: authority.manifest_sha256,
    operation_authority_sha256: context.operation_authority_sha256,
    authority_projection_sha256: authorizationRequest.authority_projection_sha256,
    publisher_input_manifest_sha256: sha256(canonicalJson(manifest)),
    vps_operation_authority_pass_sha256: sha256(canonicalJson(pass)),
    issuer_authority_sha256: sha256(canonicalJson(issuer)),
    node_binary_sha256: context.node_candidate_sha256,
    authorization_request_path_sha256: authorizationRequestObservation.path_sha256,
    authorization_request_sha256: authorizationRequestObservation.sha256,
    authorization_request_identity_sha256: authorizationRequestObservation.identity_sha256,
    authorization_request_uid: authorizationRequestObservation.uid,
    authorization_request_gid: authorizationRequestObservation.gid,
    authorization_request_mode: authorizationRequestObservation.mode,
    authorization_request_nlink: authorizationRequestObservation.nlink,
    receiver_root_path_sha256: sha256(Buffer.from(receiverRoot)),
    receiver_root_identity_sha256: receiverRootIdentitySha256,
    receiver_leaves_sha256: sha256(canonicalJson(receiverLeaves)),
    publisher_installer_git_path: installerProvenance.git_path,
    publisher_installer_git_blob_oid: installerProvenance.git_blob_oid,
    publisher_installer_source_sha256: installerProvenance.source_sha256,
    publisher_installer_provenance_sha256: sha256(canonicalJson(installerProvenance)),
    publisher_installer_compile_authority_sha256: installerProvenance.compile_authority_sha256,
    publisher_installer_expected_binary_sha256: installerProvenance.expected_binary_sha256,
    prompt_sha256: promptSha256,
    prompt_budget: confirmation.prompt_budget,
    authorized_uid: confirmation.authorized_uid,
    authorized_gid: confirmation.authorized_gid,
    confirmation_sha256: confirmation.confirmation_sha256,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  validateHumanAuthorizationReceipt(receipt, context, manifest, pass, {
    authorizationRequest, authorizationRequestObservation, receiverRoot, receiverRootIdentitySha256,
    receiverLeaves, installerProvenance, promptSha256,
  });
  return receipt;
}

export function validateHumanAuthorizationReceipt(receipt, context, manifest, pass, expected) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  exactKeys(expected, [
    'authorizationRequest', 'authorizationRequestObservation', 'receiverRoot', 'receiverRootIdentitySha256',
    'receiverLeaves', 'installerProvenance', 'promptSha256',
  ], code);
  const { authorizationRequest, authorizationRequestObservation, receiverRoot, receiverRootIdentitySha256,
    receiverLeaves, installerProvenance, promptSha256 } = expected;
  validateHumanAuthorizationRequest(authorizationRequest, {
    context, manifest, pass, receiverRoot, receiverRootIdentitySha256, receiverLeaves, installerProvenance, promptSha256,
  }, code);
  exactKeys(receipt, HUMAN_AUTHORIZATION_RECEIPT_FIELDS, code);
  exactKeys(authorizationRequestObservation, [
    'role', 'path', 'path_sha256', 'sha256', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtime_ns', 'dev', 'ino', 'identity_sha256',
  ], code);
  if (authorizationRequestObservation.role !== 'human-authorization-request'
      || authorizationRequestObservation.path_sha256 !== sha256(Buffer.from(authorizationRequestObservation.path))
      || authorizationRequestObservation.sha256 !== sha256(canonicalJson(authorizationRequest))
      || authorizationRequestObservation.mode !== 0o600 || authorizationRequestObservation.nlink !== 1
      || authorizationRequestObservation.identity_sha256 !== physicalIdentitySha256(authorizationRequestObservation)) fail(code);
  if (receipt.schema_version !== 2 || receipt.purpose !== 'CI3_OPERATION_AUTHORITY_HUMAN_AUTHORIZATION_V2'
      || receipt.authority_sha !== authority.commit || receipt.approved_action !== 'PUBLISH_ROOT_IMMUTABLE_OPERATION_AUTHORITY'
      || receipt.authority_manifest_sha256 !== authority.manifest_sha256
      || receipt.operation_authority_sha256 !== context.operation_authority_sha256
      || receipt.authority_projection_sha256 !== authorizationRequest.authority_projection_sha256
      || receipt.authority_projection_sha256 !== sha256(canonicalJson(authorityProjectionFromPass(pass, code)))
      || receipt.publisher_input_manifest_sha256 !== sha256(canonicalJson(manifest))
      || receipt.vps_operation_authority_pass_sha256 !== sha256(canonicalJson(pass))
      || receipt.issuer_authority_sha256 !== pass.issuer_authority_sha256
      || receipt.node_binary_sha256 !== context.node_candidate_sha256
      || receipt.authorization_request_path_sha256 !== authorizationRequestObservation.path_sha256
      || receipt.authorization_request_sha256 !== authorizationRequestObservation.sha256
      || receipt.authorization_request_identity_sha256 !== authorizationRequestObservation.identity_sha256
      || receipt.authorization_request_uid !== authorizationRequestObservation.uid
      || receipt.authorization_request_gid !== authorizationRequestObservation.gid
      || receipt.authorization_request_mode !== 0o600 || receipt.authorization_request_nlink !== 1
      || receipt.receiver_root_path_sha256 !== sha256(Buffer.from(receiverRoot))
      || receipt.receiver_root_identity_sha256 !== receiverRootIdentitySha256
      || receipt.receiver_leaves_sha256 !== sha256(canonicalJson(receiverLeaves))
      || receipt.publisher_installer_git_path !== installerProvenance.git_path
      || receipt.publisher_installer_git_blob_oid !== installerProvenance.git_blob_oid
      || receipt.publisher_installer_source_sha256 !== installerProvenance.source_sha256
      || receipt.publisher_installer_provenance_sha256 !== sha256(canonicalJson(installerProvenance))
      || receipt.publisher_installer_compile_authority_sha256 !== installerProvenance.compile_authority_sha256
      || receipt.publisher_installer_expected_binary_sha256 !== installerProvenance.expected_binary_sha256
      || receipt.prompt_sha256 !== promptSha256 || receipt.prompt_budget !== 1
      || !Number.isInteger(receipt.authorized_uid) || receipt.authorized_uid <= 0
      || !Number.isInteger(receipt.authorized_gid) || receipt.authorized_gid <= 0
      || receipt.attempt !== 1 || receipt.retry !== false || receipt.raw_values !== false) fail(code);
  for (const field of [
    'authority_manifest_sha256', 'operation_authority_sha256', 'authority_projection_sha256', 'publisher_input_manifest_sha256',
    'vps_operation_authority_pass_sha256', 'issuer_authority_sha256', 'node_binary_sha256',
    'authorization_request_path_sha256', 'authorization_request_sha256', 'authorization_request_identity_sha256',
    'receiver_root_path_sha256', 'receiver_root_identity_sha256', 'receiver_leaves_sha256',
    'publisher_installer_source_sha256', 'publisher_installer_provenance_sha256',
    'publisher_installer_compile_authority_sha256', 'publisher_installer_expected_binary_sha256',
    'prompt_sha256', 'confirmation_sha256',
  ]) requireHex(receipt[field], code);
  requireHex(receipt.publisher_installer_git_blob_oid, code, [40]);
  installerBindingFromHuman(receipt, code);
  return true;
}

function authorityProjection(bindings, context, code) {
  validateFrozenBindings(bindings);
  const authority = contextFields(context, code);
  const projection = {
    authority_sha: authority.commit,
    authority_parent: authority.parent,
    authority_tree: authority.tree,
    authority_subject_sha256: authority.subject_sha256,
    authority_manifest_sha256: authority.manifest_sha256,
    operation_authority_sha256: context.operation_authority_sha256,
    node_candidate_sha256: context.node_candidate_sha256,
    collector_contracts_sha256: context.collector_contracts_sha256,
    remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
  };
  exactKeys(projection, [
    'authority_sha', 'authority_parent', 'authority_tree', 'authority_subject_sha256', 'authority_manifest_sha256',
    'operation_authority_sha256', 'node_candidate_sha256', 'collector_contracts_sha256',
    'remote_generation_id', 'controller_generation_id',
  ], code);
  if (projection.authority_sha !== bindings.MAC_EXECUTOR_AUTHORITY_SHA
      || projection.authority_parent !== bindings.MAC_EXECUTOR_AUTHORITY_PARENT
      || projection.authority_tree !== bindings.MAC_EXECUTOR_AUTHORITY_TREE
      || projection.authority_subject_sha256 !== sha256(Buffer.from(bindings.MAC_EXECUTOR_AUTHORITY_SUBJECT))) fail(code);
  return projection;
}

export function buildPublisher1BootstrapHandoff({
  bindings, context, gate0Receipt, issuer, pass, transportManifest, humanAuthorization,
  humanAuthorizationRequest, humanAuthorizationRequestObservation, installerProvenance, promptSha256,
  materializerAuthority, receiverRoot, receiverRootIdentitySha256, receiverLeaves,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  validateFrozenBindings(bindings);
  const authority = contextFields(context, code);
  const projection = authorityProjection(bindings, context, code);
  validateGate0Receipt(gate0Receipt, bindings, context);
  validateVpsIssuerAuthority(issuer);
  verifyVpsPass(pass, issuer, context);
  validatePublisherInputManifest(transportManifest, context);
  const preauthorizationReceiverLeaves = receiverLeaves.filter(({ role }) => role !== 'human-authorization');
  validateHumanAuthorizationReceipt(humanAuthorization, context, transportManifest, pass, {
    authorizationRequest: humanAuthorizationRequest,
    authorizationRequestObservation: humanAuthorizationRequestObservation,
    receiverRoot, receiverRootIdentitySha256: humanAuthorizationRequest.receiver_root_identity_sha256,
    receiverLeaves: preauthorizationReceiverLeaves,
    installerProvenance, promptSha256,
  });
  validatePublisher1MaterializerAuthority(materializerAuthority, context, {
    receiverRoot, receiverRootIdentitySha256, receiverLeaves,
  });
  if (materializerAuthority.issuer_authority_sha256 !== sha256(canonicalJson(issuer))) fail(code);
  const handoff = {
    schema_version: 2,
    purpose: context.production_frozen_inputs === undefined
      ? 'CI3_PUBLISHER1_BOOTSTRAP_HANDOFF_V2' : 'CI3_PUBLISHER1_BOOTSTRAP_HANDOFF_V3',
    authority_sha: authority.commit,
    authority_projection: projection,
    remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
    gate0_receipt: gate0Receipt,
    issuer,
    pass,
    transport_manifest: transportManifest,
    human_authorization_request: humanAuthorizationRequest,
    human_authorization_request_observation: humanAuthorizationRequestObservation,
    human_authorization: humanAuthorization,
    installer_provenance: installerProvenance,
    prompt_sha256: promptSha256,
    materializer_authority: materializerAuthority,
    receiver_root_path_sha256: sha256(Buffer.from(receiverRoot)),
    receiver_root_identity_sha256: receiverRootIdentitySha256,
    receiver_leaves: materializerAuthority.receiver_leaves,
    attempt: 1,
    retry: false,
    raw_values: false,
    ...(context.production_frozen_inputs === undefined
      ? {} : { production_frozen_inputs: structuredClone(context.production_frozen_inputs) }),
  };
  validatePublisher1BootstrapHandoff(handoff, { bindings, context, receiverRoot, receiverRootIdentitySha256, receiverLeaves });
  return handoff;
}

export function validatePublisher1BootstrapHandoff(handoff, expected) {
  const code = 'STOP_PRE_AUTHORITY';
  exactKeys(expected, ['bindings', 'context', 'receiverRoot', 'receiverRootIdentitySha256', 'receiverLeaves'], code);
  const authority = contextFields(expected.context, code);
  validateFrozenBindings(expected.bindings);
  const successor = handoff?.purpose === 'CI3_PUBLISHER1_BOOTSTRAP_HANDOFF_V3';
  exactKeys(handoff, [
    'schema_version', 'purpose', 'authority_sha', 'remote_generation_id', 'controller_generation_id',
    'authority_projection', 'gate0_receipt', 'issuer', 'pass', 'transport_manifest',
    'human_authorization_request', 'human_authorization_request_observation', 'human_authorization',
    'installer_provenance', 'prompt_sha256', 'materializer_authority',
    'receiver_root_path_sha256', 'receiver_root_identity_sha256', 'receiver_leaves', 'attempt', 'retry', 'raw_values',
    ...(successor ? ['production_frozen_inputs'] : []),
  ], code);
  const projection = authorityProjection(expected.bindings, expected.context, code);
  if (handoff.schema_version !== 2
      || !['CI3_PUBLISHER1_BOOTSTRAP_HANDOFF_V2', 'CI3_PUBLISHER1_BOOTSTRAP_HANDOFF_V3'].includes(handoff.purpose)
      || handoff.authority_sha !== authority.commit || handoff.remote_generation_id !== expected.context.generations.remote
      || handoff.controller_generation_id !== expected.context.generations.controller
      || !canonicalJson(handoff.authority_projection).equals(canonicalJson(projection))
      || handoff.receiver_root_path_sha256 !== sha256(Buffer.from(expected.receiverRoot))
      || handoff.receiver_root_identity_sha256 !== expected.receiverRootIdentitySha256
      || handoff.attempt !== 1 || handoff.retry !== false || handoff.raw_values !== false) fail(code);
  if (successor) {
    validateProductionFrozenInputConsumerBinding(handoff.production_frozen_inputs, code);
    if (!canonicalJson(handoff.production_frozen_inputs)
      .equals(canonicalJson(expected.context.production_frozen_inputs))) fail(code);
  }
  validateGate0Receipt(handoff.gate0_receipt, expected.bindings, expected.context);
  validateVpsIssuerAuthority(handoff.issuer);
  verifyVpsPass(handoff.pass, handoff.issuer, expected.context);
  if (handoff.pass.authority_sha !== handoff.authority_projection.authority_sha
      || handoff.pass.authority_parent !== handoff.authority_projection.authority_parent
      || handoff.pass.authority_tree !== handoff.authority_projection.authority_tree
      || handoff.pass.authority_subject_sha256 !== handoff.authority_projection.authority_subject_sha256
      || handoff.pass.authority_manifest_sha256 !== handoff.authority_projection.authority_manifest_sha256
      || handoff.pass.operation_authority_sha256 !== handoff.authority_projection.operation_authority_sha256
      || handoff.pass.node_candidate_sha256 !== handoff.authority_projection.node_candidate_sha256
      || handoff.pass.collector_contracts_sha256 !== handoff.authority_projection.collector_contracts_sha256
      || handoff.pass.remote_generation_id !== handoff.authority_projection.remote_generation_id
      || handoff.pass.controller_generation_id !== handoff.authority_projection.controller_generation_id) fail(code);
  validatePublisherInputManifest(handoff.transport_manifest, expected.context);
  validateHumanAuthorizationReceipt(handoff.human_authorization, expected.context, handoff.transport_manifest, handoff.pass, {
    authorizationRequest: handoff.human_authorization_request,
    authorizationRequestObservation: handoff.human_authorization_request_observation,
    receiverRoot: expected.receiverRoot,
    receiverRootIdentitySha256: handoff.human_authorization_request.receiver_root_identity_sha256,
    receiverLeaves: expected.receiverLeaves.filter(({ role }) => role !== 'human-authorization'),
    installerProvenance: handoff.installer_provenance,
    promptSha256: handoff.prompt_sha256,
  });
  validatePublisher1MaterializerAuthority(handoff.materializer_authority, expected.context, {
    receiverRoot: expected.receiverRoot,
    receiverRootIdentitySha256: expected.receiverRootIdentitySha256,
    receiverLeaves: expected.receiverLeaves,
  });
  if (handoff.materializer_authority.issuer_authority_sha256 !== sha256(canonicalJson(handoff.issuer))
      || !canonicalJson(handoff.receiver_leaves).equals(canonicalJson(handoff.materializer_authority.receiver_leaves))) fail(code);
  return true;
}

export async function runZeroRetryOperation(operation, { timeoutMs, code } = {}) {
  if (typeof operation !== 'function' || !Number.isInteger(timeoutMs) || timeoutMs < 1 || typeof code !== 'string' || code.length === 0) fail('ZERO_RETRY');
  const controller = new AbortController();
  let timer;
  let settleTimer;
  try {
    const settled = Promise.resolve().then(() => operation(controller.signal)).then(
      (value) => ({ kind: 'value', value }),
      (error) => ({ kind: 'error', error }),
    );
    const first = await Promise.race([
      settled,
      new Promise((resolve) => { timer = setTimeout(() => resolve({ kind: 'timeout' }), timeoutMs); }),
    ]);
    if (first.kind === 'timeout') {
      controller.abort();
      const afterAbort = await Promise.race([
        settled,
        new Promise((resolve) => { settleTimer = setTimeout(() => resolve({ kind: 'unterminated' }), Math.max(20, Math.min(timeoutMs, 1_000))); }),
      ]);
      if (afterAbort.kind === 'unterminated') fail('TIMEOUT');
      fail('TIMEOUT');
    }
    if (first.kind === 'error') throw first.error;
    return first.value;
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    if (error?.code === code) throw error;
    fail(code);
  } finally {
    clearTimeout(timer);
    clearTimeout(settleTimer);
  }
}

export async function runBoundedFixedSubprocess({
  executable, argv, input = null, persistAttempt, expectedExisting, spawn = spawnChild, timeoutMs = 30_000,
  environment = CLOSED_ENVIRONMENT, captureStdout = false, maxStdoutBytes = MAX_SUBPROCESS_BYTES,
  preflightExecutable = null, attemptExisting = null, observeSettled = null, persistRecoveredResult = null,
  stdoutJournalPath = null,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  requireAbsoluteSafePath(executable, code);
  if (!Array.isArray(argv) || argv.some((value) => typeof value !== 'string' || /[\0\r\n]/.test(value))
      || typeof persistAttempt !== 'function' || typeof expectedExisting !== 'function'
      || typeof spawn !== 'function' || !Number.isInteger(timeoutMs) || timeoutMs < 1) fail(code);
  if (preflightExecutable !== null && typeof preflightExecutable !== 'function') fail(code);
  const recoveryFunctions = [attemptExisting, observeSettled, persistRecoveredResult];
  if (!(recoveryFunctions.every((value) => value === null)
      || recoveryFunctions.every((value) => typeof value === 'function'))) fail(code);
  if (typeof captureStdout !== 'boolean' || !Number.isInteger(maxStdoutBytes) || maxStdoutBytes < 1
      || maxStdoutBytes > MAX_AUTHENTICATED_CAPTURE_BYTES) fail(code);
  if (stdoutJournalPath !== null) {
    if (!captureStdout) fail(code);
    requireAbsoluteSafePath(stdoutJournalPath, code);
  }
  if (input !== null && (!Buffer.isBuffer(input) || input.length > MAX_SUBPROCESS_INPUT_BYTES)) fail(code);
  validateSubprocessEnvironment(environment, code);
  const existing = await expectedExisting();
  if (existing === true) return Object.freeze({ state: 'EXISTS_VERIFIED', effect_executions: 0, raw_values: false });
  if (existing !== false) fail(code);
  if (attemptExisting !== null) {
    const attemptPresent = await attemptExisting();
    if (attemptPresent === true) {
      if (await observeSettled() !== 'SETTLED_EXACT' || await persistRecoveredResult() !== true) fail(code);
      return Object.freeze({ state: 'RECOVERED_VERIFIED', effect_executions: 0, raw_values: false });
    }
    if (attemptPresent !== false) fail(code);
  }
  const executableReady = preflightExecutable === null
    ? await (async () => {
      let descriptor;
      try {
        descriptor = await open(executable, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
        const observed = await descriptor.stat({ bigint: true });
        return observed.isFile() && (observed.mode & 0o111n) !== 0n;
      } catch { return false; } finally { await descriptor?.close().catch(() => undefined); }
    })()
    : await preflightExecutable(executable);
  if (executableReady !== true) fail(code);
  let journalParent = null;
  if (stdoutJournalPath !== null) {
    journalParent = await readPrivateDirectoryIdentity(path.dirname(stdoutJournalPath), code);
    const journalExisting = await lstat(stdoutJournalPath).catch((error) => {
      if (error?.code === 'ENOENT') return null;
      throw error;
    });
    if (journalExisting !== null) fail(code);
  }
  // The durable, exclusive attempt marker is the irreversible boundary before
  // a child exists. It is deliberately one-shot: EEXIST is recovered only by
  // the exact-existing branch above and never becomes a retry.
  const persisted = await persistAttempt();
  if (persisted !== true) fail(code);
  let journalDescriptor = null;
  if (stdoutJournalPath !== null) {
    try {
      journalDescriptor = await open(
        stdoutJournalPath,
        FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW,
        0o600,
      );
      await journalDescriptor.chmod(0o600);
      await journalDescriptor.sync();
      await verifyNamedDirectory(path.dirname(stdoutJournalPath), journalParent, code);
      let parentDescriptor;
      try {
        parentDescriptor = await open(
          path.dirname(stdoutJournalPath),
          FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_DIRECTORY | FS_CONSTANTS.O_NOFOLLOW,
        );
        await parentDescriptor.sync();
      } finally {
        await parentDescriptor?.close().catch(() => undefined);
      }
    } catch {
      await journalDescriptor?.close().catch(() => undefined);
      fail(code);
    }
  }
  return await new Promise((resolve, reject) => {
    let child;
    let stdoutBytes = 0;
    let stderrBytes = 0;
    const stderrChunks = [];
    const stdoutChunks = [];
    let settled = false;
    let timedOut = false;
    let killTimer;
    let finalTimer;
    let timer;
    let journalWrites = Promise.resolve();
    let journalFailure = false;
    let journalClosed = false;
    const closeJournal = async () => {
      if (journalDescriptor === null || journalClosed) return;
      journalClosed = true;
      await journalWrites;
      await journalDescriptor.sync();
      await journalDescriptor.close();
    };
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(killTimer);
      clearTimeout(finalTimer);
      void closeJournal().then(() => {
        if (error || journalFailure) reject(error ?? new ExternalPublisherError(code));
        else resolve(Object.freeze(value));
      }, () => reject(new ExternalPublisherError(code)));
    };
    const terminate = () => {
      if (!child || child.exitCode !== null || child.signalCode !== null) return;
      timedOut = true;
      child.kill('SIGTERM');
      killTimer = setTimeout(() => {
        if (child.exitCode === null && child.signalCode === null) {
          child.kill('SIGKILL');
          finalTimer = setTimeout(() => finish(new ExternalPublisherError(code)), Math.min(1_000, timeoutMs));
        }
      }, Math.min(1_000, timeoutMs));
    };
    try {
      child = spawn(executable, argv, {
        shell: false, windowsHide: true, stdio: [input === null ? 'ignore' : 'pipe', 'pipe', 'pipe'], env: { ...environment },
      });
    } catch { finish(new ExternalPublisherError(code)); return; }
    const consume = (stream, setCount, capture = false) => {
      stream?.on('data', (chunk) => {
        const bytes = Buffer.from(chunk);
        if (capture) stdoutChunks.push(bytes);
        if (capture && journalDescriptor !== null) {
          journalWrites = journalWrites.then(async () => {
            await journalDescriptor.write(bytes);
            await journalDescriptor.sync();
          }).catch(() => {
            journalFailure = true;
            terminate();
          });
        }
        const next = setCount(bytes.length);
        if (next > (capture ? maxStdoutBytes : MAX_SUBPROCESS_BYTES)) terminate();
      });
    };
    consume(child.stdout, (length) => { stdoutBytes += length; return stdoutBytes; }, captureStdout);
    consume(child.stderr, (length) => { stderrBytes += length; return stderrBytes; });
    if (input !== null) {
      if (!child.stdin || typeof child.stdin.end !== 'function') { finish(new ExternalPublisherError(code)); return; }
      child.stdin.once?.('error', () => finish(new ExternalPublisherError(code)));
      child.stdin.end(input);
    }
    child.once('error', () => finish(new ExternalPublisherError(code)));
    child.once('close', (status) => {
      void journalWrites.then(() => {
        if (timedOut || journalFailure || status !== 0 || stdoutBytes > maxStdoutBytes || stderrBytes > MAX_SUBPROCESS_BYTES) {
          finish(new ExternalPublisherError(code));
        } else {
          const captured = captureStdout ? Buffer.concat(stdoutChunks, stdoutBytes) : null;
          finish(null, captureStdout
            ? { state: 'CREATED', effect_executions: 1, stdout_bytes: stdoutBytes, stderr_bytes: stderrBytes,
              stdout: captured, stdout_sha256: sha256(captured), raw_values: false }
            : { state: 'CREATED', effect_executions: 1, stdout_bytes: stdoutBytes, stderr_bytes: stderrBytes, raw_values: false });
        }
      }, () => finish(new ExternalPublisherError(code)));
    });
    timer = setTimeout(terminate, timeoutMs);
  });
}

function validatePublisher0TransportBrokerRequest(value, requestPath, requestBytes) {
  const code = 'STOP_PRE_AUTHORITY';
  if (!isPlainObject(value) || !Buffer.isBuffer(requestBytes)) fail(code);
  exactKeys(value, [
    'ack_path', 'argv', 'attempt', 'authority_sha', 'barrier_root', 'barrier_stage',
    'completed_path', 'controller_generation_id', 'environment', 'executable',
    'executable_sha256', 'input_base64', 'input_sha256', 'journal_path',
    'max_stdout_bytes', 'purpose', 'raw_values', 'request_sha256', 'retry',
    'schema_version', 'script_sha256', 'started_path',
  ], code);
  if (value.schema_version !== 1 || value.purpose !== 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_REQUEST_V1'
      || value.attempt !== 1 || value.retry !== false || value.raw_values !== false) fail(code);
  requireHex(value.authority_sha, code, [40]);
  requireGeneration(value.controller_generation_id, code);
  for (const field of ['executable_sha256', 'input_sha256', 'request_sha256', 'script_sha256']) requireHex(value[field], code);
  requireAbsoluteSafePath(requestPath, code);
  requireAbsoluteSafePath(value.executable, code);
  for (const field of ['ack_path', 'barrier_root', 'completed_path', 'journal_path', 'started_path']) {
    requireAbsoluteSafePath(value[field], code);
  }
  const transportRoot = path.dirname(requestPath);
  const sourceRoot = path.dirname(transportRoot);
  if (path.basename(requestPath) !== 'session.request.json' || value.barrier_root !== transportRoot
      || value.ack_path !== path.join(transportRoot, 'local-ack.json')
      || value.started_path !== path.join(transportRoot, 'started.json')
      || value.completed_path !== path.join(transportRoot, 'completed.json')
      || value.journal_path !== path.join(sourceRoot, 'publisher0-output.capture.journal')) fail(code);
  if (!Array.isArray(value.argv) || value.argv.some((entry) => typeof entry !== 'string' || /[\0\r\n]/u.test(entry))) fail(code);
  validateSubprocessEnvironment(value.environment, code);
  if (typeof value.input_base64 !== 'string' || !/^[A-Za-z0-9+/]*={0,2}$/u.test(value.input_base64)) fail(code);
  const input = Buffer.from(value.input_base64, 'base64');
  if (input.length === 0 || input.length > MAX_SUBPROCESS_INPUT_BYTES
      || input.toString('base64') !== value.input_base64 || sha256(input) !== value.input_sha256) fail(code);
  if (!Number.isInteger(value.max_stdout_bytes) || value.max_stdout_bytes < 1
      || value.max_stdout_bytes > MAX_AUTHENTICATED_CAPTURE_BYTES) fail(code);
  if (value.barrier_stage !== null && !PUBLISHER0_TRANSPORT_BARRIER_STAGES.includes(value.barrier_stage)) fail(code);
  return Object.freeze({ request: value, input, transportRoot, sourceRoot });
}

async function awaitPublisher0TransportBarrier(request, stage, outputSha256) {
  const code = 'STOP_PRE_AUTHORITY';
  if (request.barrier_stage !== stage) return;
  const prepared = {
    schema_version: 1,
    purpose: 'CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER_V1',
    stage,
    request_sha256: request.request_sha256,
    output_sha256: outputSha256,
    decision: 'PREPARED',
    raw_values: false,
  };
  const preparedBytes = canonicalJson(prepared);
  const preparedPath = path.join(request.barrier_root, `${stage}.prepared.json`);
  await writeOrVerifyAtomicOwnerOnlyReceipt(preparedPath, preparedBytes, code);
  await syncNamedDirectory(request.barrier_root, code);
  const releasePath = path.join(request.barrier_root, `${stage}.continue.json`);
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const exists = await lstat(releasePath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (!exists) {
      await new Promise((resolve) => setTimeout(resolve, 10));
      continue;
    }
    const releaseFile = await readPinnedOwnerOnlyFile(releasePath, { mode: 0o600, code });
    let release;
    try { release = JSON.parse(releaseFile.bytes.toString('utf8')); } catch { fail(code); }
    exactKeys(release, [
      'decision', 'output_sha256', 'prepared_sha256', 'purpose', 'raw_values',
      'request_sha256', 'schema_version', 'stage',
    ], code);
    if (!canonicalJson(release).equals(releaseFile.bytes) || release.schema_version !== 1
        || release.purpose !== 'CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER_RELEASE_V1'
        || release.stage !== stage || release.request_sha256 !== request.request_sha256
        || release.output_sha256 !== outputSha256 || release.prepared_sha256 !== sha256(preparedBytes)
        || release.decision !== 'CONTINUE' || release.raw_values !== false) fail(code);
    return;
  }
  fail(code);
}

function publisher0ContinuationWorkerReceipt(request, requestSha256, stage, outputSha256) {
  return canonicalJson({
    schema_version: 1,
    purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_CONTINUATION_WORKER_V1',
    authority_sha: request.authority_sha,
    controller_generation_id: request.controller_generation_id,
    broker_request_sha256: requestSha256,
    request_sha256: request.request_sha256,
    stage,
    output_sha256: outputSha256,
    decision: 'CONTINUE',
    attempt: 1,
    retry: false,
    raw_values: false,
  });
}

async function readValidatedPublisher0LocalAck(
  request, requestSha256, outputSha256, outputLength, waitForAck,
) {
  const code = 'STOP_PRE_AUTHORITY';
  const deadline = Date.now() + (waitForAck ? 30_000 : 0);
  let ackBytes = null;
  do {
    const exists = await lstat(request.ack_path).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (exists) ackBytes = (await readPinnedOwnerOnlyFile(request.ack_path, { mode: 0o600, code })).bytes;
    else if (waitForAck) await new Promise((resolve) => setTimeout(resolve, 10));
  } while (ackBytes === null && waitForAck && Date.now() < deadline);
  if (ackBytes === null) fail(code);
  let ack;
  try { ack = JSON.parse(ackBytes.toString('utf8')); } catch { fail(code); }
  exactKeys(ack, [
    'attempt', 'authority_sha', 'broker_request_sha256', 'controller_generation_id', 'decision',
    'journal_byte_length', 'journal_sha256', 'purpose', 'raw_values', 'request_sha256', 'retry', 'schema_version',
  ], code);
  if (!canonicalJson(ack).equals(ackBytes) || ack.schema_version !== 1
      || ack.purpose !== 'CI3_LOCAL_PUBLISHER0_DURABLE_ACK_V1'
      || ack.authority_sha !== request.authority_sha
      || ack.controller_generation_id !== request.controller_generation_id
      || ack.broker_request_sha256 !== requestSha256 || ack.request_sha256 !== request.request_sha256
      || ack.journal_sha256 !== outputSha256 || ack.journal_byte_length !== outputLength
      || ack.decision !== 'COMMIT' || ack.attempt !== 1 || ack.retry !== false || ack.raw_values !== false) fail(code);
  return ackBytes;
}

async function runPublisher0TransportJournalWorker(requestPath, requestSha256, stage, outputSha256) {
  const code = 'STOP_PRE_AUTHORITY';
  requireHex(requestSha256, code);
  requireHex(outputSha256, code);
  if (!PUBLISHER0_TRANSPORT_BARRIER_STAGES.includes(stage)) fail(code);
  const requestFile = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  if (sha256(requestFile.bytes) !== requestSha256) fail(code);
  let parsed;
  try { parsed = JSON.parse(requestFile.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(parsed).equals(requestFile.bytes)) fail(code);
  const { request, transportRoot } = validatePublisher0TransportBrokerRequest(
    parsed, requestPath, requestFile.bytes,
  );
  const script = await readPinnedRegularFile(SCRIPT_PATH, { code });
  if (sha256(script.bytes) !== request.script_sha256) fail(code);
  await readPrivateDirectoryIdentity(transportRoot, code);
  const outputFile = await readPinnedOwnerOnlyFile(
    path.join(transportRoot, 'remote-prepared-output.json'), { mode: 0o600, code },
  );
  if (sha256(outputFile.bytes) !== outputSha256 || outputFile.bytes.length < 2) fail(code);
  let parsedOutput;
  try { parsedOutput = JSON.parse(outputFile.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(parsedOutput).equals(outputFile.bytes)) fail(code);
  const persistProgress = async (name, state, fields = {}) => {
    const progress = canonicalJson({
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_PROGRESS_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      state,
      ...fields,
      attempt: 1,
      retry: false,
      raw_values: false,
    });
    await writeOrVerifyAtomicOwnerOnlyReceipt(
      path.join(transportRoot, `${name}.json`), progress, code,
    );
    await syncNamedDirectory(transportRoot, code);
  };
  const journalFile = await readPinnedOwnerOnlyFile(request.journal_path, { mode: 0o600, code });
  const prefix = outputFile.bytes.subarray(0, outputFile.bytes.length - 1);
  if (stage === 'remote-prepared-before-first-local-chunk') {
    if (journalFile.bytes.length !== 0 && !journalFile.bytes.equals(prefix)) fail(code);
    await awaitPublisher0TransportBarrier(request, stage, outputSha256);
    if (journalFile.bytes.length === 0) {
      const journal = await open(request.journal_path, FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_APPEND | FS_CONSTANTS.O_NOFOLLOW);
      try { await journal.writeFile(prefix); await journal.sync(); } finally { await journal.close(); }
    }
    await persistProgress('journal-prefix-synced', 'JOURNAL_PREFIX_SYNCED', {
      journal_prefix_byte_length: prefix.length,
    });
  } else if (stage === 'before-last-local-chunk') {
    if (!journalFile.bytes.equals(prefix) && !journalFile.bytes.equals(outputFile.bytes)) fail(code);
    await awaitPublisher0TransportBarrier(request, stage, outputSha256);
    if (journalFile.bytes.equals(prefix)) {
      const journal = await open(request.journal_path, FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_APPEND | FS_CONSTANTS.O_NOFOLLOW);
      try {
        await journal.writeFile(outputFile.bytes.subarray(outputFile.bytes.length - 1));
        await journal.sync();
      } finally { await journal.close(); }
    }
    const complete = await readPinnedOwnerOnlyFile(request.journal_path, { mode: 0o600, code });
    if (!complete.bytes.equals(outputFile.bytes)) fail(code);
    await persistProgress('journal-complete', 'JOURNAL_COMPLETE', {
      journal_byte_length: outputFile.bytes.length,
      journal_sha256: outputSha256,
    });
    await syncNamedDirectory(path.dirname(request.journal_path), code);
  } else {
    const complete = await readPinnedOwnerOnlyFile(request.journal_path, { mode: 0o600, code });
    if (!complete.bytes.equals(outputFile.bytes)) fail(code);
    const ackBytes = await readValidatedPublisher0LocalAck(
      request, requestSha256, outputSha256, outputFile.bytes.length, true,
    );
    await persistProgress('ack-observed', 'ACK_OBSERVED', { local_ack_sha256: sha256(ackBytes) });
    await awaitPublisher0TransportBarrier(request, stage, outputSha256);
  }
  const receiptPath = path.join(transportRoot, `continuation-${stage}.json`);
  await writeOrVerifyAtomicOwnerOnlyReceipt(
    receiptPath,
    publisher0ContinuationWorkerReceipt(request, requestSha256, stage, outputSha256),
    code,
  );
  await syncNamedDirectory(transportRoot, code);
}

async function runRestartablePublisher0TransportStage(requestPath, requestSha256, request, stage, outputSha256) {
  const code = 'STOP_PRE_AUTHORITY';
  const receiptPath = path.join(path.dirname(requestPath), `continuation-${stage}.json`);
  const expected = publisher0ContinuationWorkerReceipt(request, requestSha256, stage, outputSha256);
  const verifyExistingReceipt = async () => {
    const exists = await lstat(receiptPath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (!exists) return false;
    const receipt = await readPinnedOwnerOnlyFile(receiptPath, { mode: 0o600, code });
    if (!receipt.bytes.equals(expected)) fail(code);
    return true;
  };
  const preparedPath = path.join(request.barrier_root, `${stage}.prepared.json`);
  const releasePath = path.join(request.barrier_root, `${stage}.continue.json`);
  const priorWorkerReachedBarrier = request.barrier_stage === stage
    && await lstat(preparedPath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
  if (priorWorkerReachedBarrier) {
    const priorWorkerDeadline = Date.now() + 30_000;
    while (Date.now() < priorWorkerDeadline) {
      if (await verifyExistingReceipt()) return;
      const released = await lstat(releasePath).then(() => true, (error) => {
        if (error?.code === 'ENOENT') return false;
        throw error;
      });
      if (released) break;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    const receiptGraceDeadline = Date.now() + 500;
    while (Date.now() < receiptGraceDeadline) {
      if (await verifyExistingReceipt()) return;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
  }
  for (let workerStart = 0; workerStart < 8; workerStart += 1) {
    let worker;
    try {
      worker = spawnChild(
        process.execPath,
        [SCRIPT_PATH, PUBLISHER0_TRANSPORT_JOURNAL_WORKER_MODE,
          requestPath, requestSha256, stage, outputSha256],
        { shell: false, windowsHide: true, stdio: ['ignore', 'ignore', 'ignore'], env: { ...CLOSED_ENVIRONMENT } },
      );
    } catch { fail(code); }
    const closed = await new Promise((resolve) => {
      let settled = false;
      const timer = setTimeout(() => {
        if (!settled) worker.kill('SIGKILL');
      }, 30_000);
      worker.once('error', () => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({ status: null, signal: 'ERROR' });
      });
      worker.once('close', (status, signal) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve({ status, signal });
      });
    });
    if (await verifyExistingReceipt()) return;
    if (closed.signal === null || closed.signal === undefined) fail(code);
  }
  fail(code);
}

async function runPublisher0TransportOwner(requestPath, requestSha256) {
  const code = 'STOP_PRE_AUTHORITY';
  requireHex(requestSha256, code);
  const requestFile = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  if (sha256(requestFile.bytes) !== requestSha256) fail(code);
  let parsed;
  try { parsed = JSON.parse(requestFile.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(parsed).equals(requestFile.bytes)) fail(code);
  const validated = validatePublisher0TransportBrokerRequest(parsed, requestPath, requestFile.bytes);
  const request = validated.request;
  const script = await readPinnedRegularFile(SCRIPT_PATH, { code });
  const executable = await readPinnedRegularFile(request.executable, { executable: true, code });
  if (sha256(script.bytes) !== request.script_sha256 || sha256(executable.bytes) !== request.executable_sha256) fail(code);
  await readPrivateDirectoryIdentity(validated.transportRoot, code);
  const journalParent = await readPrivateDirectoryIdentity(path.dirname(request.journal_path), code);
  let journal;
  try {
    journal = await open(
      request.journal_path,
      FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW,
      0o600,
    );
    await journal.chmod(0o600);
    await journal.sync();
    await verifyNamedDirectory(path.dirname(request.journal_path), journalParent, code);
    await syncNamedDirectory(path.dirname(request.journal_path), code);
    await journal.close();
    journal = null;
  } catch (error) {
    await journal?.close().catch(() => undefined);
    fail(code);
  }
  const started = {
    schema_version: 1,
    purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_STARTED_V1',
    authority_sha: request.authority_sha,
    controller_generation_id: request.controller_generation_id,
    broker_request_sha256: requestSha256,
    script_sha256: request.script_sha256,
    executable_sha256: request.executable_sha256,
    state: 'STARTED',
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  await writeOrVerifyAtomicOwnerOnlyReceipt(request.started_path, canonicalJson(started), code);
  await syncNamedDirectory(validated.transportRoot, code);
  const persistProgress = async (name, state, fields = {}) => {
    const progress = {
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_PROGRESS_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      state,
      ...fields,
      attempt: 1,
      retry: false,
      raw_values: false,
    };
    await writeOrVerifyAtomicOwnerOnlyReceipt(
      path.join(validated.transportRoot, `${name}.json`), canonicalJson(progress), code,
    );
    await syncNamedDirectory(validated.transportRoot, code);
  };

  let child;
  let timeout;
  let brokerStage = 'BEFORE_SPAWN';
  try {
    brokerStage = 'SPAWN';
    child = spawnChild(request.executable, request.argv, {
      shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'], env: { ...request.environment },
    });
    let stdout = Buffer.alloc(0);
    let stderrBytes = 0;
    const stderrChunks = [];
    let outputResolved = false;
    let resolveOutput;
    let rejectOutput;
    const outputPromise = new Promise((resolve, reject) => { resolveOutput = resolve; rejectOutput = reject; });
    let resolveClose;
    const closePromise = new Promise((resolve) => { resolveClose = resolve; });
    child.stdout.on('data', (chunk) => {
      if (outputResolved) { rejectOutput(new ExternalPublisherError(code)); child.kill('SIGKILL'); return; }
      stdout = Buffer.concat([stdout, Buffer.from(chunk)]);
      if (stdout.length > request.max_stdout_bytes) { rejectOutput(new ExternalPublisherError(code)); child.kill('SIGKILL'); return; }
      let candidate;
      try { candidate = JSON.parse(stdout.toString('utf8')); } catch { return; }
      if (!canonicalJson(candidate).equals(stdout)) return;
      outputResolved = true;
      resolveOutput(stdout);
    });
    child.stderr.on('data', (chunk) => {
      const bytes = Buffer.from(chunk);
      stderrChunks.push(bytes);
      stderrBytes += bytes.length;
      if (stderrBytes > MAX_SUBPROCESS_BYTES) child.kill('SIGKILL');
    });
    child.once('error', (error) => { rejectOutput(error); resolveClose({ status: null, signal: 'ERROR' }); });
    child.once('close', (status, signal) => {
      if (!outputResolved) rejectOutput(new ExternalPublisherError(code));
      resolveClose({ status, signal });
    });
    if (!child.stdin || typeof child.stdin.write !== 'function' || typeof child.stdin.end !== 'function') fail(code);
    let stdinFailure = null;
    child.stdin.once('error', (error) => { stdinFailure = error; });
    const inputFlushedPromise = new Promise((resolve, reject) => {
      child.stdin.write(validated.input, (error) => (error ? reject(error) : resolve()));
    });
    const timeoutPromise = new Promise((_, reject) => {
      timeout = setTimeout(() => {
        child.kill('SIGKILL');
        reject(new ExternalPublisherError(code));
      }, 30_000);
    });
    const outputBytes = await Promise.race([outputPromise, timeoutPromise]);
    await Promise.race([inputFlushedPromise, timeoutPromise]);
    if (stdinFailure !== null) fail(code);
    const outputSha256 = sha256(outputBytes);
    await writeOrVerifyAtomicOwnerOnlyReceipt(
      path.join(validated.transportRoot, 'remote-prepared-output.json'), outputBytes, code,
    );
    await syncNamedDirectory(validated.transportRoot, code);
    brokerStage = 'AWAIT_COMMIT_DECISION';
    const commitDecisionPath = path.join(validated.transportRoot, 'commit-decided.json');
    let ackBytes = null;
    const commitDeadline = Date.now() + 30_000;
    while (ackBytes === null && Date.now() < commitDeadline) {
      const commitExists = await lstat(commitDecisionPath).then(() => true, (error) => {
        if (error?.code === 'ENOENT') return false;
        throw error;
      });
      if (!commitExists) {
        await new Promise((resolve) => setTimeout(resolve, 10));
        continue;
      }
      const candidateAck = await readValidatedPublisher0LocalAck(
        request, requestSha256, outputSha256, outputBytes.length, false,
      );
      const expectedDecision = canonicalJson({
        schema_version: 1,
        purpose: 'CI3_LOCAL_PUBLISHER0_COMMIT_DECISION_V1',
        authority_sha: request.authority_sha,
        controller_generation_id: request.controller_generation_id,
        broker_request_sha256: requestSha256,
        request_sha256: request.request_sha256,
        journal_sha256: outputSha256,
        local_ack_sha256: sha256(candidateAck),
        decision: 'COMMIT_DECIDED',
        attempt: 1,
        retry: false,
        raw_values: false,
      });
      const observedDecision = await readPinnedOwnerOnlyFile(commitDecisionPath, { mode: 0o600, code });
      if (!observedDecision.bytes.equals(expectedDecision)) fail(code);
      ackBytes = candidateAck;
    }
    if (ackBytes === null) fail(code);
    await persistProgress('ack-sent', 'ACK_SENT', { journal_sha256: outputSha256 });
    brokerStage = 'FLUSH_LOCAL_ACK';
    const ackFlushedPromise = new Promise((resolve, reject) => {
      child.stdin.end(
        `CI3_LOCAL_DURABLE_ACK_V1 ${outputSha256} ${request.request_sha256}\nCI3_LOCAL_DURABLE_ACK_BODY\n`,
        (error) => (error ? reject(error) : resolve()),
      );
    });
    await Promise.race([ackFlushedPromise, timeoutPromise]);
    if (stdinFailure !== null) fail(code);
    await persistProgress('ack-flushed', 'ACK_FLUSHED', { journal_sha256: outputSha256 });
    brokerStage = 'AWAIT_REMOTE_CLOSE';
    const closed = await Promise.race([closePromise, timeoutPromise]);
    brokerStage = 'REMOTE_CLOSE_OBSERVED';
    const remoteFailureText = Buffer.concat(stderrChunks).toString('utf8');
    const expectedRemoteDecision = `CI3_REMOTE_COMMIT_DECISION_V1 ${outputSha256} ${request.request_sha256}\n`;
    const remoteFailureClass = [
      'ACK_SHAPE_MISMATCH', 'ACK_PROTOCOL_MISMATCH', 'ACK_OUTPUT_MISMATCH', 'ACK_REQUEST_MISMATCH',
    ].includes(remoteFailureText.trim()) ? remoteFailureText.trim()
      : (remoteFailureText === expectedRemoteDecision ? 'NONE' : 'REMOTE_ERROR');
    brokerStage = `PERSIST_REMOTE_CLOSE_${remoteFailureClass}`;
    await persistProgress('remote-closed', 'REMOTE_CLOSED', {
      remote_status: closed.status,
      remote_signal: closed.signal,
      remote_failure_class: remoteFailureClass,
    });
    brokerStage = `VALIDATE_REMOTE_CLOSE_${remoteFailureClass}`;
    if (closed.status !== 0 || closed.signal !== null || stderrBytes > MAX_SUBPROCESS_BYTES
        || remoteFailureText !== expectedRemoteDecision) fail(code);
    const terminalDecision = {
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_REMOTE_COMMIT_DECISION_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      request_sha256: request.request_sha256,
      journal_sha256: outputSha256,
      remote_decision_sha256: sha256(Buffer.from(remoteFailureText)),
      decision: 'REMOTE_COMMIT_DURABLE',
      attempt: 1,
      retry: false,
      raw_values: false,
    };
    await writeOrVerifyAtomicOwnerOnlyReceipt(
      path.join(validated.transportRoot, 'remote-terminal-decision.json'), canonicalJson(terminalDecision), code,
    );
    await syncNamedDirectory(validated.transportRoot, code);
  } catch {
    await persistProgress('failed', 'FAILED', { failure_stage: brokerStage }).catch(() => undefined);
    throw new ExternalPublisherError(code);
  } finally {
    clearTimeout(timeout);
    await journal?.close().catch(() => undefined);
  }
}

async function runPublisher0TransportSessionSupervisor(requestPath, requestSha256) {
  const code = 'STOP_PRE_AUTHORITY';
  requireHex(requestSha256, code);
  const requestFile = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  if (sha256(requestFile.bytes) !== requestSha256) fail(code);
  let parsed;
  try { parsed = JSON.parse(requestFile.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(parsed).equals(requestFile.bytes)) fail(code);
  const validated = validatePublisher0TransportBrokerRequest(parsed, requestPath, requestFile.bytes);
  const request = validated.request;
  const script = await readPinnedRegularFile(SCRIPT_PATH, { code });
  const executable = await readPinnedRegularFile(request.executable, { executable: true, code });
  if (sha256(script.bytes) !== request.script_sha256 || sha256(executable.bytes) !== request.executable_sha256) fail(code);
  await readPrivateDirectoryIdentity(validated.transportRoot, code);
  const persistProgress = async (name, state, fields = {}) => {
    const progress = canonicalJson({
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_PROGRESS_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      state,
      ...fields,
      attempt: 1,
      retry: false,
      raw_values: false,
    });
    await writeOrVerifyAtomicOwnerOnlyReceipt(
      path.join(validated.transportRoot, `${name}.json`), progress, code,
    );
    await syncNamedDirectory(validated.transportRoot, code);
  };
  let supervisorStage = 'AWAIT_TRANSPORT_OWNER';
  try {
    const deadline = Date.now() + 30_000;
    const outputPath = path.join(validated.transportRoot, 'remote-prepared-output.json');
    let outputBytes = null;
    while (outputBytes === null && Date.now() < deadline) {
      const failedExists = await lstat(path.join(validated.transportRoot, 'failed.json')).then(() => true, (error) => {
        if (error?.code === 'ENOENT') return false;
        throw error;
      });
      if (failedExists) fail(code);
      const exists = await lstat(outputPath).then(() => true, (error) => {
        if (error?.code === 'ENOENT') return false;
        throw error;
      });
      if (!exists) {
        await new Promise((resolve) => setTimeout(resolve, 10));
        continue;
      }
      outputBytes = (await readPinnedOwnerOnlyFile(outputPath, { mode: 0o600, code })).bytes;
    }
    if (outputBytes === null || outputBytes.length < 2) fail(code);
    let output;
    try { output = JSON.parse(outputBytes.toString('utf8')); } catch { fail(code); }
    if (!canonicalJson(output).equals(outputBytes)) fail(code);
    const outputSha256 = sha256(outputBytes);
    const expectedStarted = canonicalJson({
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_STARTED_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      script_sha256: request.script_sha256,
      executable_sha256: request.executable_sha256,
      state: 'STARTED',
      attempt: 1,
      retry: false,
      raw_values: false,
    });
    const started = await readPinnedOwnerOnlyFile(request.started_path, { mode: 0o600, code });
    if (!started.bytes.equals(expectedStarted)) fail(code);
    supervisorStage = 'REMOTE_PREPARED_BARRIER';
    await runRestartablePublisher0TransportStage(
      requestPath, requestSha256, request, 'remote-prepared-before-first-local-chunk', outputSha256,
    );
    supervisorStage = 'LAST_CHUNK_BARRIER';
    await runRestartablePublisher0TransportStage(
      requestPath, requestSha256, request, 'before-last-local-chunk', outputSha256,
    );
    supervisorStage = 'AFTER_LOCAL_ACK_BARRIER';
    await runRestartablePublisher0TransportStage(
      requestPath, requestSha256, request, 'after-local-ack', outputSha256,
    );
    const ackBytes = await readValidatedPublisher0LocalAck(
      request, requestSha256, outputSha256, outputBytes.length, false,
    );
    supervisorStage = 'PERSIST_COMMIT_DECISION';
    const commitDecision = canonicalJson({
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_COMMIT_DECISION_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      request_sha256: request.request_sha256,
      journal_sha256: outputSha256,
      local_ack_sha256: sha256(ackBytes),
      decision: 'COMMIT_DECIDED',
      attempt: 1,
      retry: false,
      raw_values: false,
    });
    await writeOrVerifyAtomicOwnerOnlyReceipt(
      path.join(validated.transportRoot, 'commit-decided.json'), commitDecision, code,
    );
    await syncNamedDirectory(validated.transportRoot, code);
    supervisorStage = 'AWAIT_REMOTE_TERMINAL_DECISION';
    const terminalPath = path.join(validated.transportRoot, 'remote-terminal-decision.json');
    let terminalBytes = null;
    while (terminalBytes === null && Date.now() < deadline) {
      const failedExists = await lstat(path.join(validated.transportRoot, 'failed.json')).then(() => true, (error) => {
        if (error?.code === 'ENOENT') return false;
        throw error;
      });
      if (failedExists) fail(code);
      const exists = await lstat(terminalPath).then(() => true, (error) => {
        if (error?.code === 'ENOENT') return false;
        throw error;
      });
      if (exists) terminalBytes = (await readPinnedOwnerOnlyFile(terminalPath, { mode: 0o600, code })).bytes;
      else await new Promise((resolve) => setTimeout(resolve, 10));
    }
    const remoteDecisionText = `CI3_REMOTE_COMMIT_DECISION_V1 ${outputSha256} ${request.request_sha256}\n`;
    const expectedTerminal = canonicalJson({
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_REMOTE_COMMIT_DECISION_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      request_sha256: request.request_sha256,
      journal_sha256: outputSha256,
      remote_decision_sha256: sha256(Buffer.from(remoteDecisionText)),
      decision: 'REMOTE_COMMIT_DURABLE',
      attempt: 1,
      retry: false,
      raw_values: false,
    });
    if (terminalBytes === null || !terminalBytes.equals(expectedTerminal)) fail(code);
    const remoteClosed = await readPinnedOwnerOnlyFile(
      path.join(validated.transportRoot, 'remote-closed.json'), { mode: 0o600, code },
    );
    let remoteClosedValue;
    try { remoteClosedValue = JSON.parse(remoteClosed.bytes.toString('utf8')); } catch { fail(code); }
    if (!canonicalJson(remoteClosedValue).equals(remoteClosed.bytes)
        || remoteClosedValue.state !== 'REMOTE_CLOSED' || remoteClosedValue.remote_status !== 0
        || remoteClosedValue.remote_signal !== null || remoteClosedValue.remote_failure_class !== 'NONE') fail(code);
    const completion = canonicalJson({
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_COMPLETION_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      request_sha256: request.request_sha256,
      journal_sha256: outputSha256,
      local_ack_sha256: sha256(ackBytes),
      remote_status: 0,
      decision: 'ACKNOWLEDGED',
      attempt: 1,
      retry: false,
      raw_values: false,
    });
    await writeOrVerifyAtomicOwnerOnlyReceipt(request.completed_path, completion, code);
    await syncNamedDirectory(validated.transportRoot, code);
    const quiesced = canonicalJson({
      schema_version: 1,
      purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_QUIESCED_V1',
      authority_sha: request.authority_sha,
      controller_generation_id: request.controller_generation_id,
      broker_request_sha256: requestSha256,
      state: 'QUIESCED',
      pending_filesystem_writes: 0,
      attempt: 1,
      retry: false,
      raw_values: false,
    });
    await writeOrVerifyAtomicOwnerOnlyReceipt(
      path.join(validated.transportRoot, 'quiesced.json'), quiesced, code,
    );
    await syncNamedDirectory(validated.transportRoot, code);
  } catch {
    await persistProgress('failed', 'FAILED', { failure_stage: supervisorStage }).catch(() => undefined);
    throw new ExternalPublisherError(code);
  }
}

async function runPublisher0TransportBroker(requestPath, requestSha256) {
  const code = 'STOP_PRE_AUTHORITY';
  requireAbsoluteSafePath(requestPath, code);
  requireHex(requestSha256, code);
  const requestFile = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  if (sha256(requestFile.bytes) !== requestSha256) fail(code);
  let request;
  try { request = JSON.parse(requestFile.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(request).equals(requestFile.bytes)) fail(code);
  const validated = validatePublisher0TransportBrokerRequest(request, requestPath, requestFile.bytes);
  const script = await readPinnedRegularFile(SCRIPT_PATH, { code });
  if (sha256(script.bytes) !== request.script_sha256) fail(code);
  let transportOwner;
  try {
    transportOwner = spawnChild(
      process.execPath,
      [SCRIPT_PATH, PUBLISHER0_TRANSPORT_OWNER_MODE, requestPath, requestSha256],
      { shell: false, windowsHide: true, detached: true, stdio: ['ignore', 'ignore', 'ignore'], env: { ...CLOSED_ENVIRONMENT } },
    );
    transportOwner.once('error', () => undefined);
    transportOwner.unref();
  } catch { fail(code); }
  const deadline = Date.now() + 60_000;
  for (let supervisorStart = 0; supervisorStart < 8 && Date.now() < deadline; supervisorStart += 1) {
    let continuation;
    try {
      continuation = spawnChild(
        process.execPath,
        [SCRIPT_PATH, PUBLISHER0_TRANSPORT_SESSION_SUPERVISOR_MODE, requestPath, requestSha256],
        { shell: false, windowsHide: true, detached: true, stdio: ['ignore', 'ignore', 'ignore'], env: { ...CLOSED_ENVIRONMENT } },
      );
    } catch { fail(code); }
    let settled = false;
    const closed = new Promise((resolve) => {
      continuation.once('error', () => resolve({ status: null, signal: 'ERROR' }));
      continuation.once('close', (status, signal) => resolve({ status, signal }));
    });
    while (!settled && Date.now() < deadline) {
      for (const terminalName of ['quiesced.json', 'failed.json']) {
        const terminalPath = path.join(validated.transportRoot, terminalName);
        const exists = await lstat(terminalPath).then(() => true, (error) => {
          if (error?.code === 'ENOENT') return false;
          throw error;
        });
        if (exists) return;
      }
      const outcome = await Promise.race([
        closed.then((value) => ({ closed: value })),
        new Promise((resolve) => setTimeout(() => resolve({ closed: null }), 25)),
      ]);
      if (outcome.closed !== null) {
        settled = true;
        if (outcome.closed.signal !== null && outcome.closed.signal !== undefined) break;
        fail(code);
      }
    }
    if (!settled) {
      continuation.kill('SIGKILL');
      break;
    }
  }
  while (Date.now() < deadline) {
    for (const terminalName of ['quiesced.json', 'failed.json']) {
      const terminalPath = path.join(validated.transportRoot, terminalName);
      const exists = await lstat(terminalPath).then(() => true, (error) => {
        if (error?.code === 'ENOENT') return false;
        throw error;
      });
      if (exists) return;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  fail(code);
}

async function startPublisher0DurableTransportSession({
  invocation, context, sourceRoot, persistAttempt, barrierStage = null,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  contextFields(context, code);
  requireAbsoluteSafePath(sourceRoot, code);
  if (!isPlainObject(invocation) || typeof persistAttempt !== 'function'
      || !Buffer.isBuffer(invocation.input) || invocation.input.length === 0
      || !Array.isArray(invocation.argv) || invocation.argv.some((entry) => typeof entry !== 'string' || /[\0\r\n]/u.test(entry))) fail(code);
  requireAbsoluteSafePath(invocation.executable, code);
  requireHex(invocation.transport_request_sha256, code);
  if (barrierStage !== null && !PUBLISHER0_TRANSPORT_BARRIER_STAGES.includes(barrierStage)) fail(code);
  const script = await readPinnedRegularFile(SCRIPT_PATH, { code });
  const executable = await readPinnedRegularFile(invocation.executable, { executable: true, code });
  const transportRoot = path.join(sourceRoot, 'publisher0-transport');
  try {
    await mkdir(transportRoot, { mode: 0o700 });
    await syncNamedDirectory(sourceRoot, code);
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  }
  await readPrivateDirectoryIdentity(transportRoot, code);
  const requestPath = path.join(transportRoot, 'session.request.json');
  const request = {
    schema_version: 1,
    purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_REQUEST_V1',
    authority_sha: context.authority.commit,
    controller_generation_id: context.generations.controller,
    request_sha256: invocation.transport_request_sha256,
    script_sha256: sha256(script.bytes),
    executable: invocation.executable,
    executable_sha256: sha256(executable.bytes),
    argv: invocation.argv,
    input_base64: invocation.input.toString('base64'),
    input_sha256: sha256(invocation.input),
    environment: invocation.environment,
    journal_path: path.join(sourceRoot, 'publisher0-output.capture.journal'),
    ack_path: path.join(transportRoot, 'local-ack.json'),
    started_path: path.join(transportRoot, 'started.json'),
    completed_path: path.join(transportRoot, 'completed.json'),
    barrier_root: transportRoot,
    barrier_stage: barrierStage,
    max_stdout_bytes: MAX_AUTHENTICATED_CAPTURE_BYTES,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  const requestBytes = canonicalJson(request);
  validatePublisher0TransportBrokerRequest(request, requestPath, requestBytes);
  await writeOwnerOnlyNoClobber(requestPath, requestBytes, 0o600);
  await syncNamedDirectory(transportRoot, code);
  if (await persistAttempt() !== true) fail(code);
  let broker;
  try {
    broker = spawnChild(
      process.execPath,
      [SCRIPT_PATH, PUBLISHER0_TRANSPORT_BROKER_MODE, requestPath, sha256(requestBytes)],
      { shell: false, windowsHide: true, detached: true, stdio: ['ignore', 'ignore', 'ignore'], env: { ...CLOSED_ENVIRONMENT } },
    );
    broker.once('error', () => undefined);
    broker.unref();
  } catch { fail(code); }
  return Object.freeze({ request, requestBytes, requestPath, requestSha256: sha256(requestBytes), raw_values: false });
}

async function settlePublisher0DurableTransportSession({
  context, sourceRoot, crashAfterJournal = false,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  contextFields(context, code);
  requireAbsoluteSafePath(sourceRoot, code);
  if (typeof crashAfterJournal !== 'boolean') fail(code);
  const transportRoot = path.join(sourceRoot, 'publisher0-transport');
  const requestPath = path.join(transportRoot, 'session.request.json');
  const requestFile = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  let request;
  try { request = JSON.parse(requestFile.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(request).equals(requestFile.bytes)) fail(code);
  const validated = validatePublisher0TransportBrokerRequest(request, requestPath, requestFile.bytes);
  const brokerRequestSha256 = sha256(requestFile.bytes);
  if (request.authority_sha !== context.authority.commit
      || request.controller_generation_id !== context.generations.controller) fail(code);
  const expectedStarted = canonicalJson({
    schema_version: 1,
    purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_STARTED_V1',
    authority_sha: request.authority_sha,
    controller_generation_id: request.controller_generation_id,
    broker_request_sha256: brokerRequestSha256,
    script_sha256: request.script_sha256,
    executable_sha256: request.executable_sha256,
    state: 'STARTED',
    attempt: 1,
    retry: false,
    raw_values: false,
  });
  const deadline = Date.now() + 30_000;
  let outputBytes = null;
  while (outputBytes === null && Date.now() < deadline) {
    const failedExists = await lstat(path.join(transportRoot, 'failed.json')).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (failedExists) fail(code);
    const journalCompletePath = path.join(transportRoot, 'journal-complete.json');
    const journalCompleteExists = await lstat(journalCompletePath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (journalCompleteExists) {
      const started = await readPinnedOwnerOnlyFile(request.started_path, { mode: 0o600, code });
      if (!started.bytes.equals(expectedStarted)) fail(code);
      const journalCompleteFile = await readPinnedOwnerOnlyFile(journalCompletePath, { mode: 0o600, code });
      let journalComplete;
      try { journalComplete = JSON.parse(journalCompleteFile.bytes.toString('utf8')); } catch { fail(code); }
      exactKeys(journalComplete, [
        'attempt', 'authority_sha', 'broker_request_sha256', 'controller_generation_id',
        'journal_byte_length', 'journal_sha256', 'purpose', 'raw_values', 'retry', 'schema_version', 'state',
      ], code);
      if (!canonicalJson(journalComplete).equals(journalCompleteFile.bytes)
          || journalComplete.schema_version !== 1
          || journalComplete.purpose !== 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_PROGRESS_V1'
          || journalComplete.authority_sha !== request.authority_sha
          || journalComplete.controller_generation_id !== request.controller_generation_id
          || journalComplete.broker_request_sha256 !== brokerRequestSha256
          || journalComplete.state !== 'JOURNAL_COMPLETE'
          || !Number.isSafeInteger(journalComplete.journal_byte_length)
          || journalComplete.journal_byte_length < 1
          || journalComplete.journal_byte_length > request.max_stdout_bytes
          || journalComplete.attempt !== 1 || journalComplete.retry !== false
          || journalComplete.raw_values !== false) fail(code);
      requireHex(journalComplete.journal_sha256, code);
      const journal = await readPinnedOwnerOnlyFile(request.journal_path, { mode: 0o600, code });
      if (journal.bytes.length !== journalComplete.journal_byte_length
          || sha256(journal.bytes) !== journalComplete.journal_sha256) fail(code);
      let parsedOutput;
      try { parsedOutput = JSON.parse(journal.bytes.toString('utf8')); } catch { fail(code); }
      if (!canonicalJson(parsedOutput).equals(journal.bytes)) fail(code);
      validateAuthenticatedPublisher0Output(parsedOutput, context);
      outputBytes = journal.bytes;
      break;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  if (outputBytes === null) fail(code);
  if (crashAfterJournal) fail('SYNTHETIC_CRASH');
  const ack = {
    schema_version: 1,
    purpose: 'CI3_LOCAL_PUBLISHER0_DURABLE_ACK_V1',
    authority_sha: request.authority_sha,
    controller_generation_id: request.controller_generation_id,
    broker_request_sha256: brokerRequestSha256,
    request_sha256: request.request_sha256,
    journal_sha256: sha256(outputBytes),
    journal_byte_length: outputBytes.length,
    decision: 'COMMIT',
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  const ackBytes = canonicalJson(ack);
  await writeOrVerifyAtomicOwnerOnlyReceipt(request.ack_path, ackBytes, code);
  await syncNamedDirectory(validated.transportRoot, code);
  let completionFile = null;
  while (completionFile === null && Date.now() < deadline) {
    const failedExists = await lstat(path.join(transportRoot, 'failed.json')).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (failedExists) fail(code);
    const remoteClosedPath = path.join(transportRoot, 'remote-closed.json');
    const remoteClosedExists = await lstat(remoteClosedPath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (remoteClosedExists) {
      const remoteClosedFile = await readPinnedOwnerOnlyFile(remoteClosedPath, { mode: 0o600, code });
      let remoteClosed;
      try { remoteClosed = JSON.parse(remoteClosedFile.bytes.toString('utf8')); } catch { fail(code); }
      if (!canonicalJson(remoteClosed).equals(remoteClosedFile.bytes)
          || remoteClosed.state !== 'REMOTE_CLOSED' || remoteClosed.remote_status !== 0
          || remoteClosed.remote_signal !== null || remoteClosed.remote_failure_class !== 'NONE') fail(code);
    }
    const exists = await lstat(request.completed_path).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (exists) completionFile = await readPinnedOwnerOnlyFile(request.completed_path, { mode: 0o600, code });
    else await new Promise((resolve) => setTimeout(resolve, 10));
  }
  if (completionFile === null) fail(code);
  let completion;
  try { completion = JSON.parse(completionFile.bytes.toString('utf8')); } catch { fail(code); }
  exactKeys(completion, [
    'attempt', 'authority_sha', 'broker_request_sha256', 'controller_generation_id', 'decision',
    'journal_sha256', 'local_ack_sha256', 'purpose', 'raw_values', 'remote_status',
    'request_sha256', 'retry', 'schema_version',
  ], code);
  if (!canonicalJson(completion).equals(completionFile.bytes) || completion.schema_version !== 1
      || completion.purpose !== 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_COMPLETION_V1'
      || completion.authority_sha !== request.authority_sha
      || completion.controller_generation_id !== request.controller_generation_id
      || completion.broker_request_sha256 !== brokerRequestSha256
      || completion.request_sha256 !== request.request_sha256
      || completion.journal_sha256 !== sha256(outputBytes)
      || completion.local_ack_sha256 !== sha256(ackBytes) || completion.remote_status !== 0
      || completion.decision !== 'ACKNOWLEDGED' || completion.attempt !== 1
      || completion.retry !== false || completion.raw_values !== false) fail(code);
  const expectedQuiesced = canonicalJson({
    schema_version: 1,
    purpose: 'CI3_LOCAL_PUBLISHER0_TRANSPORT_BROKER_QUIESCED_V1',
    authority_sha: request.authority_sha,
    controller_generation_id: request.controller_generation_id,
    broker_request_sha256: brokerRequestSha256,
    state: 'QUIESCED',
    pending_filesystem_writes: 0,
    attempt: 1,
    retry: false,
    raw_values: false,
  });
  let brokerQuiesced = null;
  const quiescedPath = path.join(transportRoot, 'quiesced.json');
  while (brokerQuiesced === null && Date.now() < deadline) {
    const failedExists = await lstat(path.join(transportRoot, 'failed.json')).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (failedExists) fail(code);
    const exists = await lstat(quiescedPath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (exists) brokerQuiesced = await readPinnedOwnerOnlyFile(quiescedPath, { mode: 0o600, code });
    else await new Promise((resolve) => setTimeout(resolve, 10));
  }
  if (brokerQuiesced === null || !brokerQuiesced.bytes.equals(expectedQuiesced)) fail(code);
  const capturePath = path.join(sourceRoot, 'publisher0-output.capture.json');
  await writeOrVerifyOwnerOnlyFile(capturePath, outputBytes, code);
  await syncNamedDirectory(sourceRoot, code);
  const capture = await readPinnedOwnerOnlyFile(capturePath, { mode: 0o600, code });
  if (!capture.bytes.equals(outputBytes)) fail(code);
  return Object.freeze({
    bytes: outputBytes,
    stdout_sha256: sha256(outputBytes),
    stdout_bytes: outputBytes.length,
    stderr_bytes: 0,
    raw_values: false,
  });
}

export async function runAuthorityBuiltinOperation({
  expectedExisting, persistAttempt, effect, persistResult,
  attemptExisting = null, observeSettled = null, persistRecoveredResult = null,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  if (![expectedExisting, persistAttempt, effect, persistResult].every((value) => typeof value === 'function')) fail(code);
  const existing = await expectedExisting();
  if (existing === true) return Object.freeze({ state: 'EXISTS_VERIFIED', effect_executions: 0, raw_values: false });
  if (existing !== false) fail(code);
  const recoveryFunctions = [attemptExisting, observeSettled, persistRecoveredResult];
  if (!(recoveryFunctions.every((value) => value === null)
      || recoveryFunctions.every((value) => typeof value === 'function'))) fail(code);
  if (attemptExisting !== null) {
    const attemptPresent = await attemptExisting();
    if (attemptPresent === true) {
      if (await observeSettled() !== 'SETTLED_EXACT' || await persistRecoveredResult() !== true) fail(code);
      return Object.freeze({ state: 'RECOVERED_VERIFIED', effect_executions: 0, raw_values: false });
    }
    if (attemptPresent !== false) fail(code);
  }
  if (await persistAttempt() !== true) fail(code);
  const effected = await effect();
  if (effected !== true || await persistResult() !== true) fail(code);
  return Object.freeze({ state: 'CREATED', effect_executions: 1, stdout_bytes: 0, stderr_bytes: 0, raw_values: false });
}

export async function runHumanAuthorizationBoundary({
  requestPath, requestSha256, requestIdentitySha256, persistAttempt, spawn = spawnChild,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  requireAbsoluteSafePath(requestPath, code);
  requireHex(requestSha256, code);
  requireHex(requestIdentitySha256, code);
  if (typeof persistAttempt !== 'function' || typeof spawn !== 'function') fail(code);
  const script = [
    'display dialog "Authorize the reviewed CI-3 Publisher1 request ',
    requestSha256.slice(0, 12),
    '?" buttons {"Cancel", "Authorize"} default button "Authorize" cancel button "Cancel" with title "CI-3 Publisher1"',
  ].join('');
  const result = await runBoundedFixedSubprocess({
    executable: '/usr/bin/osascript', argv: ['-e', script], captureStdout: true, maxStdoutBytes: 1024,
    expectedExisting: async () => false, persistAttempt, spawn,
  });
  const expected = Buffer.from('button returned:Authorize\n');
  if (result.state !== 'CREATED' || !Buffer.isBuffer(result.stdout) || !result.stdout.equals(expected)
      || result.stderr_bytes !== 0) fail(code);
  let identity;
  try { identity = userInfo(); } catch { fail(code); }
  if (!Number.isInteger(identity.uid) || identity.uid <= 0 || !Number.isInteger(identity.gid) || identity.gid <= 0) fail(code);
  return Object.freeze({
    authorized_uid: identity.uid,
    authorized_gid: identity.gid,
    prompt_budget: 1,
    confirmation_sha256: sha256(expected),
    request_sha256: requestSha256,
    request_identity_sha256: requestIdentitySha256,
    raw_values: false,
  });
}

function requireBoundedHandler(handlers, name) {
  if (!isPlainObject(handlers) || typeof handlers[name] !== 'function') fail('STOP_PRE_AUTHORITY');
  return handlers[name];
}

export function createFixedOperationalHandlers({ authorityReady, invocations, spawn = spawnChild } = {}) {
  const names = ['prepare', 'provisionPublisher0', 'receivePublisher0Pass', 'provisionPublisher1', 'verifyChain'];
  if (authorityReady !== true || !isPlainObject(invocations) || typeof spawn !== 'function') fail('STOP_PRE_AUTHORITY');
  exactKeys(invocations, names, 'STOP_PRE_AUTHORITY');
  const handlers = {};
  for (const name of names) {
    const invocation = invocations[name];
    exactKeys(invocation, ['executable', 'argv', 'persistAttempt', 'expectedExisting'], 'STOP_PRE_AUTHORITY');
    handlers[name] = async ({ signal, environment }) => {
      if (signal?.aborted || !canonicalJson(environment).equals(canonicalJson(CLOSED_ENVIRONMENT))) fail('STOP_PRE_AUTHORITY');
      return await runBoundedFixedSubprocess({ ...invocation, spawn });
    };
  }
  return Object.freeze(handlers);
}

export async function dispatchExternalPublisherMode(mode, handlers = {}) {
  const parsed = parseMode([mode]);
  if (parsed === '--self-test') return runSelfTest();
  const handlerByMode = Object.freeze({
    '--prepare': 'prepare',
    '--provision-vps-publisher0': 'provisionPublisher0',
    '--receive-vps-pass': 'receivePublisher0Pass',
    '--provision-mac-publisher1': 'provisionPublisher1',
    '--verify-chain': 'verifyChain',
  });
  const handler = requireBoundedHandler(handlers, handlerByMode[parsed]);
  const result = await runZeroRetryOperation((signal) => handler({ signal, environment: CLOSED_ENVIRONMENT, mode: parsed }), {
    timeoutMs: 30_000,
    code: 'STOP_PRE_AUTHORITY',
  });
  if (!isPlainObject(result) || result.raw_values !== false) fail('STOP_PRE_AUTHORITY');
  return result;
}

function validateGate0Receipt(receipt, bindings, context) {
  const code = 'GATE0_PRESERVATION';
  if (receipt?.schema_version === 2 || receipt?.purpose === 'CI3_SEMANTIC_SAFE_MAC_GATE0_V2') {
    exactKeys(receipt, [
      'schema_version', 'purpose', 'authority_sha', 'authority_manifest_sha256', 'launcher_sha256',
      'exit_code', 'stdout_bytes', 'stderr_bytes', 'status', 'raw_values',
    ], code);
    if (receipt.schema_version !== 2 || receipt.purpose !== 'CI3_SEMANTIC_SAFE_MAC_GATE0_V2'
        || receipt.authority_sha !== bindings.MAC_EXECUTOR_AUTHORITY_SHA
        || receipt.authority_manifest_sha256 !== context.authority.manifest_sha256
        || receipt.launcher_sha256 !== context.authority.components.launcher.sha256
        || receipt.exit_code !== 0 || receipt.stdout_bytes !== 0 || receipt.stderr_bytes !== 0
        || receipt.status !== 'PASS' || receipt.raw_values !== false) fail(code);
    return true;
  }
  exactKeys(receipt, [
    'schema_version', 'purpose', 'executor_authority_sha', 'executor_authority_parent', 'executor_authority_tree',
    'executor_authority_manifest_sha256', 'launcher_sha256', 'exit_code', 'stdout_bytes', 'stderr_bytes', 'status',
    'previous_gate0_receipt_preserved', 'pre_gate0_git_fetch_attempts_new_authority',
    'pre_gate0_operational_network_attempts', 'pre_gate0_simulator_attempts', 'pre_gate0_ssh_g_attempts',
  ], code);
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_MAC_GATE0_LAUNCH_ATTESTATION_V1'
      || receipt.executor_authority_sha !== bindings.MAC_EXECUTOR_AUTHORITY_SHA
      || receipt.executor_authority_parent !== bindings.MAC_EXECUTOR_AUTHORITY_PARENT
      || receipt.executor_authority_tree !== bindings.MAC_EXECUTOR_AUTHORITY_TREE
      || receipt.executor_authority_manifest_sha256 !== context.authority.manifest_sha256
      || receipt.launcher_sha256 !== context.authority.components.launcher.sha256
      || receipt.exit_code !== 0 || receipt.stdout_bytes !== 0 || receipt.stderr_bytes !== 0
      || receipt.status !== 'PASS' || receipt.previous_gate0_receipt_preserved !== true) fail(code);
  for (const key of [
    'pre_gate0_git_fetch_attempts_new_authority', 'pre_gate0_operational_network_attempts',
    'pre_gate0_simulator_attempts', 'pre_gate0_ssh_g_attempts',
  ]) if (receipt[key] !== 0) fail(code);
  return true;
}

async function writeOwnerOnlyNoClobber(file, bytes, mode) {
  let descriptor;
  try {
    descriptor = await open(file, FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW, mode);
    await descriptor.writeFile(bytes);
    await descriptor.chmod(mode);
    await descriptor.sync();
  } catch (error) {
    if (error?.code === 'EEXIST') fail('NO_CLOBBER');
    throw error;
  } finally {
    await descriptor?.close().catch(() => undefined);
  }
}

export async function runPrepare({ bindings, context, ownerRoot, candidates, gate0Receipt, promptSha256, frozenReceiverRoot = null, localPrepare } = {}) {
  validateFrozenBindings(bindings);
  const authority = contextFields(context, 'STOP_PRE_AUTHORITY');
  if (authority.commit !== bindings.MAC_EXECUTOR_AUTHORITY_SHA || authority.parent !== bindings.MAC_EXECUTOR_AUTHORITY_PARENT
      || authority.tree !== bindings.MAC_EXECUTOR_AUTHORITY_TREE) fail('STOP_PRE_AUTHORITY');
  requireHex(promptSha256, 'STOP_PRE_AUTHORITY');
  exactKeys(candidates, PREPARE_CANDIDATE_ROLES, 'STOP_PRE_AUTHORITY');
  for (const role of PREPARE_CANDIDATE_ROLES) if (!Buffer.isBuffer(candidates[role]) || candidates[role].length === 0) fail('STOP_PRE_AUTHORITY');
  validateGate0Receipt(gate0Receipt, bindings, context);
  const layout = deriveAuthorityLayout(bindings, ownerRoot);
  const candidateRoot = path.join(layout.authority_root, 'candidates');
  if (frozenReceiverRoot !== null) requireAbsoluteSafePath(frozenReceiverRoot, 'STOP_PRE_AUTHORITY');
  const request = {
    schema_version: 1,
    purpose: 'CI3_PUBLISHER1_LOCAL_PREPARE_V1',
    authority_sha: authority.commit,
    controller_generation_id: context.generations.controller,
    candidate_root: candidateRoot,
    ...(frozenReceiverRoot === null ? {} : { transaction_receiver_root: frozenReceiverRoot }),
    candidates: PREPARE_CANDIDATE_ROLES.map((role) => ({ role, bytes_base64: candidates[role].toString('base64') })),
    prompt_sha256: promptSha256,
    attempt: 1,
    retry: false,
    raw_values: false,
  };
  const requestBytes = canonicalJson(request);
  const invoke = localPrepare ?? (async () => {
    const result = await runBoundedFixedSubprocess({
      executable: '/usr/bin/swift', argv: [SWIFT_PREPARE_HELPER, '--prepare-local'], input: requestBytes,
      expectedExisting: async () => false, persistAttempt: async () => true,
    });
    return result.state === 'CREATED';
  });
  if (typeof invoke !== 'function' || await invoke({
    helper_path: SWIFT_PREPARE_HELPER, request_sha256: sha256(requestBytes), request_bytes: requestBytes,
    candidate_root: candidateRoot, transaction_receiver_root: frozenReceiverRoot, environment: CLOSED_ENVIRONMENT,
  }) !== true) fail('STOP_PRE_AUTHORITY');
  return { state: 'PREPARED', request_sha256: sha256(requestBytes), raw_values: false };
}

export async function verifyChain({ expected, adapters } = {}) {
  const code = 'CHAIN_VERIFY';
  exactKeys(expected, ['remote_bundle_unchanged', 'gate0_preserved'], code);
  if (expected.remote_bundle_unchanged !== true || expected.gate0_preserved !== true || !isPlainObject(adapters)) fail(code);
  const steps = ['verifyPublisher0', 'verifyTransport', 'verifyPublisher1', 'verifyControllerReadback'];
  for (const step of steps) {
    if (typeof adapters[step] !== 'function') fail(code);
    let passed;
    try { passed = await runZeroRetryOperation(adapters[step], { timeoutMs: 30_000, code }); } catch { fail(code); }
    if (passed !== true) fail(code);
  }
  return { state: 'CHAIN_VERIFIED', raw_values: false };
}

function fixedMainRoots() {
  const synthetic = process.env.CI3_SYNTHETIC_TEST;
  const syntheticRoot = process.env.CI3_SYNTHETIC_TEST_ROOT;
  if (syntheticRoot !== undefined || synthetic !== undefined) {
    if (synthetic !== '1' || syntheticRoot === undefined) fail('STOP_PRE_AUTHORITY');
    requireAbsoluteSafePath(syntheticRoot, 'STOP_PRE_AUTHORITY');
    return Object.freeze({
      ownerRoot: path.join(syntheticRoot, 'owner'),
      bindingsPath: path.join(syntheticRoot, 'authorities.json'),
      syntheticRoot,
    });
  }
  return Object.freeze({ ownerRoot: PRODUCTION_OWNER_ROOT, bindingsPath: PRODUCTION_BINDINGS_PATH, syntheticRoot: null });
}

function modeName(mode) {
  return mode.replace(/^--/, '').replaceAll('-', '_').toUpperCase();
}

function operationName(mode) {
  return mode.replace(/^--/, '');
}

function modeAuthorityPurpose(mode) {
  return `CI3_EXTERNAL_PUBLISHER_${modeName(mode)}_AUTHORITY_V1`;
}

function validateModeAuthority(value, mode, context) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  if (mode === '--provision-vps-publisher0' && value?.schema_version === 2) {
    exactKeys(value, [
      'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'fixed_executable_sha256',
      'attempt', 'retry', 'raw_values',
    ], code);
    if (value.purpose !== 'CI3_EXTERNAL_PUBLISHER_PROVISION_VPS_PUBLISHER0_AUTHORITY_V2'
        || value.authority_sha !== authority.commit || value.controller_generation_id !== context.generations.controller
        || value.attempt !== 1 || value.retry !== false || value.raw_values !== false) fail(code);
    requireHex(value.fixed_executable_sha256, code);
    return true;
  }
  exactKeys(value, [
    'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'attempt', 'retry', 'raw_values',
  ], code);
  if (value.schema_version !== 1 || value.purpose !== modeAuthorityPurpose(mode)
      || value.authority_sha !== authority.commit || value.controller_generation_id !== context.generations.controller
      || value.attempt !== 1 || value.retry !== false || value.raw_values !== false) fail(code);
  return true;
}

async function readPrivateDirectoryIdentity(directory, code = 'STOP_PRE_AUTHORITY') {
  requireAbsoluteSafePath(directory, code);
  let descriptor;
  try {
    descriptor = await open(directory, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_DIRECTORY | FS_CONSTANTS.O_NOFOLLOW);
    const stat = await descriptor.stat({ bigint: true });
    const owner = typeof process.getuid === 'function' ? process.getuid() : Number(stat.uid);
    const group = typeof process.getgid === 'function' ? process.getgid() : Number(stat.gid);
    if (!stat.isDirectory() || stat.isSymbolicLink() || Number(stat.uid) !== owner || Number(stat.gid) !== group
        || Number(stat.mode & 0o077n) !== 0) fail(code);
    const metadata = physicalFromStat(stat);
    await descriptor.close();
    descriptor = undefined;
    return Object.freeze({ metadata });
  } catch (error) {
    await descriptor?.close().catch(() => undefined);
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  }
}

async function verifyNamedDirectory(directory, pinned, code = 'STOP_PRE_AUTHORITY') {
  const reopened = await readPrivateDirectoryIdentity(directory, code);
  // Directory contents legitimately advance mtime during attempt/result
  // persistence.  The named-parent race invariant is descriptor identity,
  // not a stale directory timestamp.
  if (reopened.metadata.dev !== pinned.metadata.dev || reopened.metadata.ino !== pinned.metadata.ino) fail(code);
}

async function writeOrVerifyOwnerOnlyFile(file, bytes, code = 'STOP_PRE_AUTHORITY') {
  try {
    await writeOwnerOnlyNoClobber(file, bytes, 0o600);
  } catch (error) {
    if (error?.code !== 'NO_CLOBBER') throw error;
    const existing = await readPinnedOwnerOnlyFile(file, { mode: 0o600, code });
    if (!existing.bytes.equals(bytes)) fail(code);
  }
}

export async function publishOwnerOnlyReceiptNoReplace({
  file, bytes, beforePublish = null, code = 'STOP_PRE_AUTHORITY',
} = {}) {
  requireAbsoluteSafePath(file, code);
  if (!Buffer.isBuffer(bytes) || bytes.length === 0
      || (beforePublish !== null && typeof beforePublish !== 'function')) fail(code);
  const directory = path.dirname(file);
  const pinnedDirectory = await readPrivateDirectoryIdentity(directory, code);
  const stagedPath = path.join(
    directory,
    `.${path.basename(file)}.${sha256(bytes)}.publishing`,
  );
  const exists = async (candidate) => await lstat(candidate).then(() => true, (error) => {
    if (error?.code === 'ENOENT') return false;
    throw error;
  });
  let stagedOwned = false;
  try {
    if (await exists(file)) {
      if (await exists(stagedPath)) fail(code);
      const exact = await readPinnedOwnerOnlyFile(file, { mode: 0o600, code });
      if (!exact.bytes.equals(bytes)) fail(code);
      await verifyNamedDirectory(directory, pinnedDirectory, code);
      return;
    }
    await writeOwnerOnlyNoClobber(stagedPath, bytes, 0o600);
    stagedOwned = true;
    const staged = await readPinnedOwnerOnlyFile(stagedPath, { mode: 0o600, code });
    if (!staged.bytes.equals(bytes) || await exists(file)) fail(code);
    await verifyNamedDirectory(directory, pinnedDirectory, code);
    if (beforePublish !== null) await beforePublish();
    const stagedAfterBoundary = await readPinnedOwnerOnlyFile(stagedPath, { mode: 0o600, code });
    if (!stagedAfterBoundary.bytes.equals(bytes)) fail(code);
    try {
      await link(stagedPath, file);
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      const concurrentlyPublished = await readPinnedOwnerOnlyFile(file, { mode: 0o600, code });
      if (!concurrentlyPublished.bytes.equals(bytes)) fail(code);
    }
    await unlink(stagedPath);
    stagedOwned = false;
    await verifyNamedDirectory(directory, pinnedDirectory, code);
    await syncNamedDirectory(directory, code);
    const published = await readPinnedOwnerOnlyFile(file, { mode: 0o600, code });
    if (!published.bytes.equals(bytes) || await exists(stagedPath)) fail(code);
  } catch (error) {
    if (stagedOwned) {
      await unlink(stagedPath).catch(() => undefined);
      await syncNamedDirectory(directory, code).catch(() => undefined);
    }
    if (error instanceof ExternalPublisherError) throw error;
    fail(code);
  }
}

async function writeOrVerifyAtomicOwnerOnlyReceipt(file, bytes, code = 'STOP_PRE_AUTHORITY') {
  return publishOwnerOnlyReceiptNoReplace({ file, bytes, code });
}

// The frozen controller's writeOnceBytes permits exact-existing receiver
// payloads and descriptor requests.  This producer deliberately creates no
// parent directory: the fixed parent must already have been descriptor-pinned
// by the external preparation authority.  Re-running is therefore an
// exact-byte recovery, never replacement or adoption.
export async function preMaterializeFrozenControllerTransaction({
  context, receiverRoot, receiverManifestSha256, requestPath, bytesByRole,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  contextFields(context, code);
  requireAbsoluteSafePath(receiverRoot, code);
  requireAbsoluteSafePath(requestPath, code);
  requireHex(receiverManifestSha256, code);
  const expectedSuffix = path.join('receiver', context.generations.remote, context.generations.controller, receiverManifestSha256);
  if (!receiverRoot.endsWith(expectedSuffix) || path.basename(requestPath) !== 'publisher1-transaction.request.json'
      || !receiverRoot.startsWith(`${path.join(path.dirname(requestPath), 'receiver')}${path.sep}`)) fail(code);
  exactKeys(bytesByRole, PUBLISHER1_ROLES, code);
  const root = await readPrivateDirectoryIdentity(receiverRoot, code);
  if (root.metadata.mode !== 0o700) fail(code);
  const sourceObservationsByRole = {};
  const shaByRole = {};
  for (const role of PUBLISHER1_ROLES) {
    const bytes = bytesByRole[role];
    if (!Buffer.isBuffer(bytes) || bytes.length === 0) fail(code);
    const sourcePath = path.join(receiverRoot, `${role}.payload`);
    await writeOrVerifyOwnerOnlyFile(sourcePath, bytes, code);
    const observed = await readPinnedOwnerOnlyFile(sourcePath, { mode: 0o600, code });
    const metadata = observed.metadata;
    const leaf = {
      role, path: sourcePath, path_sha256: sha256(Buffer.from(sourcePath)), sha256: sha256(observed.bytes),
      ...metadata, identity_sha256: physicalIdentitySha256(metadata),
    };
    if (!observed.bytes.equals(bytes)) fail(code);
    sourceObservationsByRole[role] = leaf;
    shaByRole[role] = leaf.sha256;
  }
  let transaction;
  try {
    transaction = buildPublisher1TransactionRequest({
      context, receiverRoot, receiverManifestSha256, shaByRole, sourceObservationsByRole,
    });
  } catch { fail(code); }
  // CI may exercise the unchanged writer's synthetic entrypoint only through
  // the closed main-root environment selected before this process starts,
  // before the request bytes are serialized. No caller path is accepted and
  // production retains the frozen controller's exact production roots.
  const synthetic = process.env.CI3_SYNTHETIC_TEST;
  const syntheticRoot = process.env.CI3_SYNTHETIC_TEST_ROOT;
  if (syntheticRoot !== undefined || synthetic !== undefined) {
    if (synthetic !== '1' || syntheticRoot === undefined) fail(code);
    requireAbsoluteSafePath(syntheticRoot, code);
    transaction = Object.freeze({
      ...transaction,
      destination_parent: path.join(syntheticRoot, 'publisher1-terminal-authority'),
      state_root: path.join(syntheticRoot, 'publisher1-terminal-state', context.authority.commit, context.generations.controller),
    });
  }
  const transactionBytes = canonicalJson(transaction);
  await writeOrVerifyOwnerOnlyFile(requestPath, transactionBytes, code);
  const request = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  if (!request.bytes.equals(transactionBytes)) fail(code);
  return Object.freeze({
    state: 'PREMATERIALIZED_EXACT_EXISTING', transaction, transaction_sha256: sha256(transactionBytes),
    request_path: requestPath, receiver_root: receiverRoot, raw_values: false,
  });
}

export async function observePreMaterializedControllerInputs({ context, requestPath, receiverRoot } = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  requireAbsoluteSafePath(requestPath, code);
  requireAbsoluteSafePath(receiverRoot, code);
  const request = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  let transaction;
  try { transaction = JSON.parse(request.bytes.toString('utf8')); } catch { fail(code); }
  exactKeys(transaction, [
    'schema_version', 'purpose', 'authority_sha', 'remote_generation_id', 'controller_generation_id', 'receiver_root',
    'receiver_manifest_sha256', 'destination_parent', 'state_root', 'entries', 'attempt', 'retry', 'raw_values',
  ], code);
  if (transaction.schema_version !== 1 || transaction.purpose !== 'CI3_PUBLISHER1_DESCRIPTOR_TRANSACTION_V1'
      || transaction.authority_sha !== authority.commit || transaction.remote_generation_id !== context.generations.remote
      || transaction.controller_generation_id !== context.generations.controller || transaction.receiver_root !== receiverRoot
      || !isHex(transaction.receiver_manifest_sha256) || transaction.attempt !== 1 || transaction.retry !== false
      || transaction.raw_values !== false || !Array.isArray(transaction.entries) || transaction.entries.length !== PUBLISHER1_ROLES.length) fail(code);
  const root = await readPrivateDirectoryIdentity(receiverRoot, code);
  if (Number(root.metadata.mode) !== 0o700) fail(code);
  const leaves = [];
  for (const [index, role] of PUBLISHER1_ROLES.entries()) {
      const entry = transaction.entries[index];
      exactKeys(entry, [
        'role', 'source_path', 'source_sha256', 'source_path_sha256', 'source_uid', 'source_gid', 'source_mode',
        'source_nlink', 'source_size', 'source_mtime_ns', 'source_dev', 'source_ino', 'source_identity_sha256',
        'destination_relative_path', 'mode',
      ], code);
      const leafPath = path.join(receiverRoot, `${role}.payload`);
      const leaf = await readPinnedOwnerOnlyFile(leafPath, { mode: 0o600, code });
      const observation = {
        role, path: leafPath, path_sha256: sha256(Buffer.from(leafPath)), sha256: sha256(leaf.bytes),
        ...leaf.metadata, identity_sha256: physicalIdentitySha256(leaf.metadata),
      };
      if (entry.role !== role || entry.source_path !== leafPath || entry.source_sha256 !== observation.sha256
          || entry.source_path_sha256 !== observation.path_sha256 || entry.source_uid !== observation.uid
          || entry.source_gid !== observation.gid || entry.source_mode !== 0o600 || entry.source_nlink !== 1
          || entry.source_size !== observation.size || entry.source_mtime_ns !== observation.mtime_ns
          || entry.source_dev !== observation.dev || entry.source_ino !== observation.ino
          || entry.source_identity_sha256 !== observation.identity_sha256) fail(code);
    leaves.push(observation);
  }
  return Object.freeze({
    transaction, request: Object.freeze({ path: requestPath, sha256: sha256(request.bytes), ...request.metadata,
      identity_sha256: physicalIdentitySha256(request.metadata) }),
    receiverRoot, receiverRootIdentitySha256: physicalIdentitySha256(root.metadata), receiverLeaves: leaves,
  });
}

export async function validatePreMaterializedControllerTransaction({ context, issuerBytes, materializer, requestPath, receiverRoot } = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  if (!Buffer.isBuffer(issuerBytes) || !isPlainObject(materializer)) fail(code);
  const observed = await observePreMaterializedControllerInputs({ context, requestPath, receiverRoot });
  validatePublisher1MaterializerAuthority(materializer, context, {
    receiverRoot, receiverRootIdentitySha256: observed.receiverRootIdentitySha256, receiverLeaves: observed.receiverLeaves,
  });
  if (materializer.issuer_authority_sha256 !== sha256(issuerBytes)
      || materializer.request_path_sha256 !== sha256(Buffer.from(requestPath))
      || materializer.request_sha256 !== observed.request.sha256
      || materializer.request_identity_sha256 !== observed.request.identity_sha256
      || materializer.request_uid !== observed.request.uid || materializer.request_gid !== observed.request.gid) fail(code);
  const frozenProjection = {
    schema_version: materializer.schema_version, purpose: materializer.purpose, authority_sha: materializer.authority_sha,
    controller_generation_id: materializer.controller_generation_id, request_path_sha256: materializer.request_path_sha256,
    request_sha256: materializer.request_sha256, request_identity_sha256: materializer.request_identity_sha256,
    request_uid: materializer.request_uid, request_gid: materializer.request_gid, request_mode: materializer.request_mode,
    request_nlink: materializer.request_nlink, receiver_root_path_sha256: materializer.receiver_root_path_sha256,
    receiver_root_identity_sha256: materializer.receiver_root_identity_sha256, receiver_leaves: materializer.receiver_leaves,
    normal_executor_authorized: materializer.normal_executor_authorized, raw_values: materializer.raw_values,
  };
  validatePublisher1MaterializerAuthorityBinding(frozenProjection, {
    authoritySha: context.authority.commit, controllerGenerationId: context.generations.controller,
    requestPath, requestSha256: observed.request.sha256, requestIdentitySha256: observed.request.identity_sha256,
    requestUid: observed.request.uid, requestGid: observed.request.gid, receiverRoot,
    receiverRootIdentitySha256: observed.receiverRootIdentitySha256,
    receiverLeaves: observed.receiverLeaves.map(({ path: _path, ...leaf }) => leaf),
  });
  return Object.freeze({ state: 'FROZEN_CONTROLLER_ACCEPTS', raw_values: false });
}

function bootstrapInstallRoots(context) {
  const authority = contextFields(context, 'STOP_PRE_AUTHORITY');
  return Object.freeze({
    destination_root: path.join(
      '/Library/Application Support/Agentempp/ci3-publisher1-bootstrap', authority.commit,
      `bootstrap-${authority.manifest_sha256}`,
    ),
    state_root: path.join('/Library/Application Support/Agentempp/ci3-publisher1-state', authority.commit, context.generations.controller),
  });
}

export function buildInstalledPublisher1LauncherInvocation({ context } = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const roots = bootstrapInstallRoots(context);
  return Object.freeze({
    executable: path.join(roots.destination_root, 'runtime', 'ci3-bridge-launcher.zsh'),
    argv: Object.freeze(['publish-operation-authority']),
    environment: CLOSED_ENVIRONMENT,
  });
}

const PUBLISHER1_BOOTSTRAP_ENTRY_CONTRACT = Object.freeze([
  Object.freeze({ role: 'materializer-authority', destination: 'publisher1-materializer.authority.json', source_mode: 0o600, mode: 0o444 }),
  Object.freeze({ role: 'issuer-receipt', destination: 'vps-issuer-authority.receipt.json', source_mode: 0o600, mode: 0o444 }),
  Object.freeze({ role: 'writer-binary', destination: 'runtime/ci3-terminal-anchor-writer', source_mode: 0o500, mode: 0o555 }),
  Object.freeze({ role: 'node-runtime', destination: 'runtime/node', source_mode: 0o600, mode: 0o555 }),
  Object.freeze({ role: 'controller', destination: 'runtime/ci3-bridge-controller.mjs', source_mode: 0o600, mode: 0o555 }),
  Object.freeze({ role: 'launcher-runtime', destination: 'runtime/ci3-bridge-launcher.zsh', source_mode: 0o600, mode: 0o555 }),
  Object.freeze({ role: 'launcher-bootstrap-authority', destination: 'runtime/launcher-bootstrap.authority.v1', source_mode: 0o600, mode: 0o444 }),
  Object.freeze({ role: 'launch-attestation', destination: 'runtime/launch-attestation.json', source_mode: 0o600, mode: 0o444 }),
  Object.freeze({ role: 'authority-manifest', destination: 'runtime/authority-manifest.v1', source_mode: 0o600, mode: 0o444 }),
]);

async function validatePublisher1BootstrapEntries(entries, context, code = 'STOP_PRE_AUTHORITY') {
  const successor = context?.production_frozen_inputs !== undefined;
  if (!Array.isArray(entries) || (!successor && entries.length !== PUBLISHER1_BOOTSTRAP_ENTRY_CONTRACT.length)
      || (successor && entries.length < PUBLISHER1_BOOTSTRAP_ENTRY_CONTRACT.length + 2)) fail(code);
  const loaded = [];
  const validateEntry = async (entry, contract) => {
    exactKeys(entry, [
      'role', 'source_path', 'source_path_sha256', 'source_sha256', 'source_uid', 'source_gid',
      'source_mode', 'source_nlink', 'source_size', 'source_mtime_ns', 'source_dev', 'source_ino',
      'source_identity_sha256', 'destination_relative_path', 'mode',
    ], code);
    requireAbsoluteSafePath(entry.source_path, code);
    requireHex(entry.source_path_sha256, code);
    requireHex(entry.source_sha256, code);
    requireHex(entry.source_identity_sha256, code);
    if (entry.role !== contract.role || entry.destination_relative_path !== contract.destination
        || entry.source_path_sha256 !== sha256(Buffer.from(entry.source_path))
        || entry.source_mode !== contract.source_mode || entry.source_nlink !== 1
        || entry.mode !== contract.mode) fail(code);
    const source = await readPinnedOwnerOnlyFile(entry.source_path, { mode: contract.source_mode, code });
    const expected = source.metadata;
    if (sha256(source.bytes) !== entry.source_sha256 || entry.source_uid !== expected.uid
        || entry.source_gid !== expected.gid || entry.source_size !== expected.size
        || entry.source_mtime_ns !== expected.mtime_ns || entry.source_dev !== expected.dev
        || entry.source_ino !== expected.ino || entry.source_identity_sha256 !== physicalIdentitySha256(expected)) fail(code);
    return { ...entry, bytes: source.bytes };
  };
  for (const [index, original] of PUBLISHER1_BOOTSTRAP_ENTRY_CONTRACT.entries()) {
    const contract = successor && original.role === 'node-runtime'
      ? { ...original, destination: 'runtime/node-capsule/capsule/bin/node' } : original;
    loaded.push(await validateEntry(entries[index], contract));
  }
  if (successor) {
    for (const entry of entries.slice(PUBLISHER1_BOOTSTRAP_ENTRY_CONTRACT.length)) {
      let contract;
      if (/^node-capsule-image-\d{3}$/.test(entry?.role)) {
        contract = { role: entry.role, destination: entry.destination_relative_path, source_mode: 0o400, mode: 0o444 };
      } else if (entry?.role === 'node-capsule-manifest') {
        contract = { role: entry.role, destination: 'runtime/node-capsule/capsule-manifest.json', source_mode: 0o600, mode: 0o444 };
      } else if (entry?.role === 'node-capsule-receipt') {
        contract = { role: entry.role, destination: 'runtime/node-capsule/mac-relocatable-node-capsule.receipt.json', source_mode: 0o600, mode: 0o444 };
      } else fail(code);
      loaded.push(await validateEntry(entry, contract));
    }
    validateMacCapsuleInstallTopology([loaded[3], ...loaded.slice(PUBLISHER1_BOOTSTRAP_ENTRY_CONTRACT.length)], context, code);
  }
  return true;
}

async function sourceEntry(role, sourcePath, destinationRelativePath, mode, code, sourceMode = null) {
  const expectedSourceMode = sourceMode ?? (role === 'writer-binary' ? 0o500 : 0o600);
  const observed = await readPinnedOwnerOnlyFile(sourcePath, { mode: expectedSourceMode, code });
  const metadata = observed.metadata;
  if (metadata.mode !== expectedSourceMode) fail(code);
  return Object.freeze({
    role, source_path: sourcePath, source_path_sha256: sha256(Buffer.from(sourcePath)), source_sha256: sha256(observed.bytes),
    source_uid: metadata.uid, source_gid: metadata.gid, source_mode: metadata.mode, source_nlink: metadata.nlink,
    source_size: metadata.size, source_mtime_ns: metadata.mtime_ns, source_dev: metadata.dev, source_ino: metadata.ino,
    source_identity_sha256: physicalIdentitySha256(metadata), destination_relative_path: destinationRelativePath, mode,
    bytes: observed.bytes,
  });
}

export function macCapsuleSourceRoot(context, homeRoot = homedir()) {
  if (!isPlainObject(context?.authority) || !/^[a-f0-9]{40}$/.test(context.authority.commit)
      || typeof homeRoot !== 'string' || !path.isAbsolute(homeRoot)) fail('STOP_PRE_AUTHORITY');
  return path.join(homeRoot, '.config', 'agentempp', 'ci3', 'mac-node-capsule-v3', context.authority.commit, 'capsule-v3');
}

async function buildMacCapsuleBootstrapEntries({ context, capsuleRoot, nodeEntry, code }) {
  requireAbsoluteSafePath(capsuleRoot, code);
  if (process.env.CI3_SYNTHETIC_TEST !== '1' && capsuleRoot !== macCapsuleSourceRoot(context)) fail(code);
  const manifestPath = path.join(capsuleRoot, 'capsule-manifest.json');
  const receiptPath = path.join(capsuleRoot, 'mac-relocatable-node-capsule.receipt.json');
  const manifestRecord = await readPinnedOwnerOnlyFile(manifestPath, { mode: 0o600, code });
  let manifest;
  try { manifest = JSON.parse(manifestRecord.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(manifest).equals(manifestRecord.bytes) || !Array.isArray(manifest?.capsule?.images)) fail(code);
  const imageEntries = [];
  for (const [index, image] of manifest.capsule.images.entries()) {
    if (!isPlainObject(image) || typeof image.destination !== 'string') fail(code);
    imageEntries.push(await sourceEntry(
      `node-capsule-image-${String(index + 1).padStart(3, '0')}`,
      path.join(capsuleRoot, 'capsule', image.destination),
      `runtime/node-capsule/capsule/${image.destination}`, 0o444, code, 0o400,
    ));
  }
  const manifestEntry = await sourceEntry('node-capsule-manifest', manifestPath,
    'runtime/node-capsule/capsule-manifest.json', 0o444, code, 0o600);
  const receiptEntry = await sourceEntry('node-capsule-receipt', receiptPath,
    'runtime/node-capsule/mac-relocatable-node-capsule.receipt.json', 0o444, code, 0o600);
  const topology = [nodeEntry, ...imageEntries, manifestEntry, receiptEntry];
  validateMacCapsuleInstallTopology(topology, context, code);
  return topology;
}

async function requireAbsentPath(file, code) {
  let descriptor;
  try {
    descriptor = await open(file, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    fail(code);
  } catch (error) {
    if (error instanceof ExternalPublisherError) throw error;
    if (error?.code !== 'ENOENT') fail(code);
  } finally {
    await descriptor?.close().catch(() => undefined);
  }
}

// Selection is authenticated before the human prompt, but compilation is not
// performed until the complete canonical bootstrap request has been validated.
// The authority is independently frozen input and is bound to the Git manifest
// path/blob plus the exact system driver, compiler and arguments.
async function observePinnedPublisher1InstallerSelection({
  roots, sourceRoot, artifactRoot, context, authorityManifestBytes,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  requireAbsoluteSafePath(sourceRoot, code);
  requireAbsoluteSafePath(artifactRoot, code);
  const candidatePath = path.join(sourceRoot, 'publisher1-input', 'installer.swift');
  const candidate = await readPinnedOwnerOnlyFile(candidatePath, { mode: 0o600, code });
  const gitBinding = deriveInstallerGitSourceBinding({ context, authorityManifestBytes, installerSourceBytes: candidate.bytes });
  const runtimeRoot = path.join(artifactRoot, 'runtime');
  await readPrivateDirectoryIdentity(runtimeRoot, code);
  const binaryRelativePath = 'runtime/ci3-publisher1-bootstrap-installer';
  const binaryPath = path.join(artifactRoot, binaryRelativePath);
  const authorityPath = path.join(artifactRoot, 'publisher1-installer.compile-authority.json');
  const receiptPath = path.join(artifactRoot, 'publisher1-installer.compile-receipt.json');
  const compilerSelection = await runSemanticValidationBinary({
    executable: '/usr/bin/xcrun', argv: ['--find', 'swiftc'],
  });
  const selectedCompiler = compilerSelection.toString('utf8');
  if (!/^\/[^\0\r\n]+\n$/.test(selectedCompiler)) fail(code);
  const compilerPath = selectedCompiler.slice(0, -1);
  requireAbsoluteSafePath(compilerPath, code);
  let resolvedCompilerPath;
  try { resolvedCompilerPath = await realpath(compilerPath); } catch { fail(code); }
  requireAbsoluteSafePath(resolvedCompilerPath, code);
  const compiler = await readPinnedRootExecutable(resolvedCompilerPath, code);
  let resolvedDriverPath;
  try { resolvedDriverPath = await realpath('/usr/bin/xcrun'); } catch { fail(code); }
  const driver = await readPinnedRootExecutable(resolvedDriverPath, code);
  const compilerArguments = roots.syntheticRoot === null
    ? ['swiftc', candidatePath, '-o', binaryPath]
    : ['swiftc', '-D', 'CI3_SYNTHETIC_TEST', candidatePath, '-o', binaryPath];
  const toolchainProvenanceSha256 = sha256(canonicalJson({
    driver_path_sha256: sha256(Buffer.from('/usr/bin/xcrun')), driver_sha256: sha256(driver.bytes),
    driver_identity_sha256: physicalIdentitySha256(driver.metadata),
    compiler_path_sha256: sha256(Buffer.from(compilerPath)), compiler_sha256: sha256(compiler.bytes),
    compiler_identity_sha256: physicalIdentitySha256(compiler.metadata),
    compile_argv_sha256: sha256(canonicalJson(compilerArguments)),
  }));
  const independentPath = path.join(sourceRoot, 'publisher1-input', 'installer.authority.json');
  const independentRecord = await readPinnedOwnerOnlyJson(independentPath, code);
  if (!canonicalJson(independentRecord.value).equals(independentRecord.bytes)) fail(code);
  const independent = independentRecord.value;
  exactKeys(independent, [
    'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'authority_manifest_sha256',
    'source_git_path', 'source_git_blob_oid', 'source_path_sha256', 'source_sha256',
    'compiler_path_sha256', 'compiler_sha256', 'compiler_identity_sha256', 'compile_argv_sha256',
    'toolchain_provenance_sha256', 'driver_path_sha256', 'driver_sha256', 'driver_identity_sha256',
    'expected_binary_sha256', 'binary_relative_path', 'attempt', 'retry', 'raw_values',
  ], code);
  requireHex(independent.source_git_blob_oid, code, [40]);
  requireHex(independent.expected_binary_sha256, code);
  if (independent.schema_version !== 3 || independent.purpose !== 'CI3_PUBLISHER1_INSTALLER_COMPILE_AUTHORITY_V3'
      || independent.authority_sha !== authority.commit
      || independent.controller_generation_id !== context.generations.controller
      || independent.authority_manifest_sha256 !== gitBinding.authority_manifest_sha256
      || independent.source_git_path !== gitBinding.git_path || independent.source_git_blob_oid !== gitBinding.git_blob_oid
      || independent.source_path_sha256 !== sha256(Buffer.from(candidatePath))
      || independent.source_sha256 !== gitBinding.source_sha256
      || independent.compiler_path_sha256 !== sha256(Buffer.from(compilerPath))
      || independent.compiler_sha256 !== sha256(compiler.bytes)
      || independent.compiler_identity_sha256 !== physicalIdentitySha256(compiler.metadata)
      || independent.compile_argv_sha256 !== sha256(canonicalJson(compilerArguments))
      || independent.driver_path_sha256 !== sha256(Buffer.from('/usr/bin/xcrun'))
      || independent.driver_sha256 !== sha256(driver.bytes)
      || independent.driver_identity_sha256 !== physicalIdentitySha256(driver.metadata)
      || independent.toolchain_provenance_sha256 !== toolchainProvenanceSha256
      || independent.binary_relative_path !== binaryRelativePath || independent.attempt !== 1
      || independent.retry !== false || independent.raw_values !== false) fail(code);
  const compileAuthoritySha256 = sha256(independentRecord.bytes);
  const installerProvenance = Object.freeze({
    ...gitBinding, compile_authority_sha256: compileAuthoritySha256,
    expected_binary_sha256: independent.expected_binary_sha256,
  });
  validateInstallerProvenance(installerProvenance, context, code);
  return Object.freeze({
    authority, candidate, candidatePath, gitBinding, binaryRelativePath, binaryPath, authorityPath, receiptPath,
    compilerPath, compiler, driver, compilerArguments, toolchainProvenanceSha256,
    independent, independentBytes: independentRecord.bytes, compileAuthoritySha256,
    installerProvenance,
  });
}

async function compilePinnedPublisher1Installer({
  roots, sourceRoot, artifactRoot, context, authorityManifestBytes, humanAuthorization = null,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const selection = await observePinnedPublisher1InstallerSelection({
    roots, sourceRoot, artifactRoot, context, authorityManifestBytes,
  });
  const {
    authority, candidate, candidatePath, gitBinding, binaryRelativePath, binaryPath, authorityPath, receiptPath,
    compilerPath, compiler, driver, compilerArguments, toolchainProvenanceSha256,
    independent, independentBytes, compileAuthoritySha256, installerProvenance,
  } = selection;
  let binary;
  let candidateAuthorityRecord;
  let receipt;
  try {
    candidateAuthorityRecord = await readPinnedOwnerOnlyJson(authorityPath, code);
    receipt = await readPinnedOwnerOnlyJson(receiptPath, code);
    binary = await readPinnedOwnerOnlyFile(binaryPath, { mode: 0o700, code });
  } catch (error) {
    if (error?.code !== 'STOP_PRE_AUTHORITY') throw error;
    await requireAbsentPath(binaryPath, code);
    await requireAbsentPath(authorityPath, code);
    await requireAbsentPath(receiptPath, code);
    const compiled = await runBoundedFixedSubprocess({
      executable: '/usr/bin/xcrun', argv: compilerArguments,
      expectedExisting: async () => false, persistAttempt: async () => true,
    });
    if (compiled.state !== 'CREATED') fail(code);
    const binaryDescriptor = await open(binaryPath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    try { await binaryDescriptor.chmod(0o700); await binaryDescriptor.sync(); } finally { await binaryDescriptor.close(); }
    binary = await readPinnedOwnerOnlyFile(binaryPath, { mode: 0o700, code });
    if (sha256(binary.bytes) !== independent.expected_binary_sha256) fail(code);
    await writeOwnerOnlyNoClobber(authorityPath, independentBytes, 0o600);
    candidateAuthorityRecord = await readPinnedOwnerOnlyJson(authorityPath, code);
    const receiptBytes = canonicalJson({
      schema_version: 3, purpose: 'CI3_PUBLISHER1_INSTALLER_COMPILE_RECEIPT_V3', authority_sha: authority.commit,
      controller_generation_id: context.generations.controller, authority_manifest_sha256: gitBinding.authority_manifest_sha256,
      source_git_blob_oid: gitBinding.git_blob_oid, compile_authority_sha256: compileAuthoritySha256,
      source_sha256: gitBinding.source_sha256, toolchain_provenance_sha256: toolchainProvenanceSha256,
      expected_binary_sha256: sha256(binary.bytes),
      binary_path_sha256: sha256(Buffer.from(binaryPath)), binary_sha256: sha256(binary.bytes),
      attempt: 1, retry: false, raw_values: false,
    });
    await writeOwnerOnlyNoClobber(receiptPath, receiptBytes, 0o600);
    receipt = await readPinnedOwnerOnlyJson(receiptPath, code);
  }
  const candidateAuthority = candidateAuthorityRecord.value;
  if (!canonicalJson(candidateAuthority).equals(candidateAuthorityRecord.bytes)
      || !candidateAuthorityRecord.bytes.equals(independentBytes)) fail(code);
  exactKeys(candidateAuthority, [
    'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'authority_manifest_sha256',
    'source_git_path', 'source_git_blob_oid', 'source_path_sha256', 'source_sha256',
    'compiler_path_sha256', 'compiler_sha256', 'compiler_identity_sha256', 'compile_argv_sha256',
    'toolchain_provenance_sha256', 'driver_path_sha256', 'driver_sha256', 'driver_identity_sha256',
    'expected_binary_sha256', 'binary_relative_path', 'attempt', 'retry', 'raw_values',
  ], code);
  if (candidateAuthority.schema_version !== 3 || candidateAuthority.purpose !== 'CI3_PUBLISHER1_INSTALLER_COMPILE_AUTHORITY_V3'
      || candidateAuthority.authority_sha !== authority.commit || candidateAuthority.controller_generation_id !== context.generations.controller
      || candidateAuthority.authority_manifest_sha256 !== gitBinding.authority_manifest_sha256
      || candidateAuthority.source_git_path !== gitBinding.git_path || candidateAuthority.source_git_blob_oid !== gitBinding.git_blob_oid
      || candidateAuthority.source_path_sha256 !== sha256(Buffer.from(candidatePath)) || candidateAuthority.source_sha256 !== gitBinding.source_sha256
      || candidateAuthority.compiler_path_sha256 !== sha256(Buffer.from(compilerPath)) || candidateAuthority.compiler_sha256 !== sha256(compiler.bytes)
      || candidateAuthority.compiler_identity_sha256 !== physicalIdentitySha256(compiler.metadata)
      || candidateAuthority.driver_path_sha256 !== sha256(Buffer.from('/usr/bin/xcrun')) || candidateAuthority.driver_sha256 !== sha256(driver.bytes)
      || candidateAuthority.driver_identity_sha256 !== physicalIdentitySha256(driver.metadata)
      || candidateAuthority.compile_argv_sha256 !== sha256(canonicalJson(compilerArguments))
      || candidateAuthority.toolchain_provenance_sha256 !== toolchainProvenanceSha256
      || candidateAuthority.expected_binary_sha256 !== independent.expected_binary_sha256
      || candidateAuthority.expected_binary_sha256 !== sha256(binary.bytes)
      || candidateAuthority.binary_relative_path !== binaryRelativePath || candidateAuthority.attempt !== 1
      || candidateAuthority.retry !== false || candidateAuthority.raw_values !== false) fail(code);
  exactKeys(receipt.value, [
    'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'authority_manifest_sha256',
    'source_git_blob_oid', 'compile_authority_sha256', 'source_sha256', 'toolchain_provenance_sha256',
    'expected_binary_sha256', 'binary_path_sha256', 'binary_sha256', 'attempt', 'retry', 'raw_values',
  ], code);
  if (receipt.value.schema_version !== 3 || receipt.value.purpose !== 'CI3_PUBLISHER1_INSTALLER_COMPILE_RECEIPT_V3'
      || receipt.value.authority_sha !== authority.commit || receipt.value.controller_generation_id !== context.generations.controller
      || receipt.value.authority_manifest_sha256 !== gitBinding.authority_manifest_sha256
      || receipt.value.source_git_blob_oid !== gitBinding.git_blob_oid
      || receipt.value.compile_authority_sha256 !== compileAuthoritySha256
      || receipt.value.source_sha256 !== gitBinding.source_sha256
      || receipt.value.toolchain_provenance_sha256 !== toolchainProvenanceSha256
      || receipt.value.expected_binary_sha256 !== candidateAuthority.expected_binary_sha256
      || receipt.value.binary_path_sha256 !== sha256(Buffer.from(binaryPath))
      || receipt.value.binary_sha256 !== candidateAuthority.expected_binary_sha256
      || sha256(binary.bytes) !== candidateAuthority.expected_binary_sha256 || receipt.value.attempt !== 1
      || receipt.value.retry !== false || receipt.value.raw_values !== false) fail(code);
  if (humanAuthorization !== null) {
    const humanBinding = installerBindingFromHuman(humanAuthorization, code);
    if (humanBinding.compile_authority_sha256 !== installerProvenance.compile_authority_sha256
        || humanBinding.expected_binary_sha256 !== installerProvenance.expected_binary_sha256
        || humanAuthorization.publisher_installer_git_path !== installerProvenance.git_path
        || humanAuthorization.publisher_installer_git_blob_oid !== installerProvenance.git_blob_oid
        || humanAuthorization.publisher_installer_source_sha256 !== installerProvenance.source_sha256
        || humanAuthorization.publisher_installer_provenance_sha256 !== sha256(canonicalJson(installerProvenance))) fail(code);
  }
  const pauseAfterPhaseA = roots.syntheticRoot !== null
    && process.env.CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A === '1';
  const killSupervisorAfterServiceRegistration = pauseAfterPhaseA
    && process.env.CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AFTER_SERVICE_REGISTRATION === '1';
  const killSupervisorAtRegistrationStage = pauseAfterPhaseA
    && [
      'CLAIM', 'DEFINITION', 'INVOCATION', 'PRE_BOOTSTRAP', 'BOOTSTRAP',
      'POST_BOOTSTRAP', 'PRE_REGISTRATION', 'REGISTRATION', 'POST_KICKSTART',
    ]
      .includes(process.env.CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE)
    ? process.env.CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE : null;
  const workerBarrierStage = pauseAfterPhaseA
    && ['RUN_CLAIM', 'PRE_EFFECT_ENTRY', 'POST_EFFECT_ENTRY', 'PRE_TERMINAL']
      .includes(process.env.CI3_SYNTHETIC_P1_WORKER_BARRIER_STAGE)
    ? process.env.CI3_SYNTHETIC_P1_WORKER_BARRIER_STAGE : null;
  const activationBarrierStage = pauseAfterPhaseA
    && ['PRE_SIGNAL', 'POST_ACCEPT_PRE_RECEIPT']
      .includes(process.env.CI3_SYNTHETIC_P1_ACTIVATION_BARRIER_STAGE)
    ? process.env.CI3_SYNTHETIC_P1_ACTIVATION_BARRIER_STAGE : null;
  const environment = roots.syntheticRoot === null
    ? CLOSED_ENVIRONMENT
    : Object.freeze({ ...CLOSED_ENVIRONMENT, CI3_SYNTHETIC_MAIN_ROOT: roots.syntheticRoot,
      CI3_SYNTHETIC_FROZEN_PROJECTION_PATH: path.join(sourceRoot, 'frozen-authority-projection.json'),
      CI3_SYNTHETIC_INSTALLER_BASE: path.join(roots.syntheticRoot, 'publisher1-installer-base'),
      ...(pauseAfterPhaseA ? { CI3_SYNTHETIC_P1_PAUSE_AFTER_PHASE_A: '1' } : {}),
      ...(killSupervisorAfterServiceRegistration
        ? { CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AFTER_SERVICE_REGISTRATION: '1' } : {}),
      ...(killSupervisorAtRegistrationStage === null ? {} : {
        CI3_SYNTHETIC_P1_KILL_SUPERVISOR_AT_REGISTRATION_STAGE: killSupervisorAtRegistrationStage,
      }),
      ...(workerBarrierStage === null ? {} : {
        CI3_SYNTHETIC_P1_WORKER_BARRIER_STAGE: workerBarrierStage,
      }),
      ...(activationBarrierStage === null ? {} : {
        CI3_SYNTHETIC_P1_ACTIVATION_BARRIER_STAGE: activationBarrierStage,
      }) });
  validateSubprocessEnvironment(environment, code);
  return Object.freeze({
    executable: binaryPath, executable_sha256: sha256(binary.bytes), environment,
    compile_authority_sha256: compileAuthoritySha256,
    expected_binary_sha256: candidateAuthority.expected_binary_sha256,
    supervisor_source_base64: candidate.bytes.toString('base64'),
    supervisor_source_sha256: gitBinding.source_sha256,
    installer_provenance: installerProvenance, raw_values: false,
  });
}

async function compilePinnedPublisher1WriterBinaries({ roots, sourceRoot, artifactRoot, context } = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  requireAbsoluteSafePath(sourceRoot, code);
  requireAbsoluteSafePath(artifactRoot, code);
  const sourcePath = path.join(sourceRoot, 'publisher1-input', 'writer.swift');
  const source = await readPinnedOwnerOnlyFile(sourcePath, { mode: 0o600, code });
  if (sha256(source.bytes) !== authority.components.writer.sha256) fail(code);
  const runtimeRoot = path.join(artifactRoot, 'runtime');
  await readPrivateDirectoryIdentity(runtimeRoot, code);
  const operationalPath = path.join(runtimeRoot, 'ci3-terminal-anchor-writer');
  const validationPath = path.join(runtimeRoot, 'ci3-publisher1-semantic-preflight');
  const receiptPath = path.join(artifactRoot, 'publisher1-writer.compile-receipt.json');
  const compile = async (binaryPath, flags) => {
    const result = await runBoundedFixedSubprocess({
      executable: '/usr/bin/xcrun', argv: ['swiftc', '-parse-as-library', ...flags, sourcePath, '-o', binaryPath],
      expectedExisting: async () => false, persistAttempt: async () => true,
    });
    if (result.state !== 'CREATED') fail(code);
    const descriptor = await open(binaryPath, FS_CONSTANTS.O_RDONLY | FS_CONSTANTS.O_NOFOLLOW);
    try {
      await descriptor.chmod(0o500);
      await descriptor.sync();
    } finally { await descriptor.close(); }
    return await readPinnedOwnerOnlyFile(binaryPath, { mode: 0o500, code });
  };
  let operational;
  let validation;
  let receipt;
  try {
    receipt = await readPinnedOwnerOnlyJson(receiptPath, code);
    operational = await readPinnedOwnerOnlyFile(operationalPath, { mode: 0o500, code });
    validation = await readPinnedOwnerOnlyFile(validationPath, { mode: 0o500, code });
  } catch (error) {
    if (error?.code !== 'STOP_PRE_AUTHORITY') throw error;
    await requireAbsentPath(operationalPath, code);
    await requireAbsentPath(validationPath, code);
    await requireAbsentPath(receiptPath, code);
    operational = await compile(operationalPath, roots.syntheticRoot === null ? [] : ['-D', 'CI3_SYNTHETIC_TEST']);
    validation = await compile(validationPath, ['-D', 'CI3_PUBLISHER1_SEMANTIC_PREFLIGHT_V1']);
    const bytes = canonicalJson({
      schema_version: 1, purpose: 'CI3_PUBLISHER1_WRITER_COMPILE_RECEIPT_V1',
      authority_sha: authority.commit, controller_generation_id: context.generations.controller,
      source_sha256: sha256(source.bytes), operational_binary_path_sha256: sha256(Buffer.from(operationalPath)),
      operational_binary_sha256: sha256(operational.bytes),
      validation_binary_path_sha256: sha256(Buffer.from(validationPath)),
      validation_binary_sha256: sha256(validation.bytes), validation_compile_flag: 'CI3_PUBLISHER1_SEMANTIC_PREFLIGHT_V1',
      attempt: 1, retry: false, raw_values: false,
    });
    await writeOwnerOnlyNoClobber(receiptPath, bytes, 0o600);
    receipt = await readPinnedOwnerOnlyJson(receiptPath, code);
  }
  exactKeys(receipt.value, [
    'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'source_sha256',
    'operational_binary_path_sha256', 'operational_binary_sha256', 'validation_binary_path_sha256',
    'validation_binary_sha256', 'validation_compile_flag', 'attempt', 'retry', 'raw_values',
  ], code);
  if (receipt.value.schema_version !== 1 || receipt.value.purpose !== 'CI3_PUBLISHER1_WRITER_COMPILE_RECEIPT_V1'
      || receipt.value.authority_sha !== authority.commit
      || receipt.value.controller_generation_id !== context.generations.controller
      || receipt.value.source_sha256 !== sha256(source.bytes)
      || receipt.value.operational_binary_path_sha256 !== sha256(Buffer.from(operationalPath))
      || receipt.value.operational_binary_sha256 !== sha256(operational.bytes)
      || receipt.value.validation_binary_path_sha256 !== sha256(Buffer.from(validationPath))
      || receipt.value.validation_binary_sha256 !== sha256(validation.bytes)
      || receipt.value.validation_compile_flag !== 'CI3_PUBLISHER1_SEMANTIC_PREFLIGHT_V1'
      || receipt.value.attempt !== 1 || receipt.value.retry !== false || receipt.value.raw_values !== false) fail(code);
  return Object.freeze({
    operational_path: operationalPath, operational_sha256: sha256(operational.bytes),
    validation_path: validationPath, validation_sha256: sha256(validation.bytes), raw_values: false,
  });
}

// Materializer and installer request are a single post-observation projection.
// The installer never receives a separately caller-selected request record.
export async function produceCanonicalPublisher1BootstrapRequest({
  bindings, context, gate0Receipt, issuer, pass, transportManifest, humanAuthorization,
  humanAuthorizationRequest, humanAuthorizationRequestObservation, installerProvenance, promptSha256,
  observed, artifactRoot, writerSourcePath, capsuleRoot = null,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  validateFrozenBindings(bindings);
  contextFields(context, code);
  requireAbsoluteSafePath(artifactRoot, code);
  requireAbsoluteSafePath(writerSourcePath, code);
  if (!isPlainObject(observed) || !isPlainObject(observed.transaction) || !isPlainObject(observed.request)
      || !Array.isArray(observed.receiverLeaves) || observed.receiverLeaves.length !== PUBLISHER1_ROLES.length) fail(code);
  validateVpsIssuerAuthority(issuer);
  verifyVpsPass(pass, issuer, context);
  validatePublisherInputManifest(transportManifest, context);
  validateHumanAuthorizationReceipt(humanAuthorization, context, transportManifest, pass, {
    authorizationRequest: humanAuthorizationRequest,
    authorizationRequestObservation: humanAuthorizationRequestObservation,
    receiverRoot: observed.receiverRoot,
    receiverRootIdentitySha256: humanAuthorizationRequest.receiver_root_identity_sha256,
    receiverLeaves: observed.receiverLeaves.filter(({ role }) => role !== 'human-authorization'),
    installerProvenance,
    promptSha256,
  });
  const writer = await sourceEntry('writer-binary', writerSourcePath, 'runtime/ci3-terminal-anchor-writer', 0o555, code);
  const materializer = buildPublisher1MaterializerAuthority({
    context, requestPath: observed.request.path, requestSha256: observed.request.sha256,
    requestObservation: { role: 'request', path: observed.request.path, path_sha256: sha256(Buffer.from(observed.request.path)),
      sha256: observed.request.sha256, uid: observed.request.uid, gid: observed.request.gid, mode: observed.request.mode,
      nlink: observed.request.nlink, size: observed.request.size, mtime_ns: observed.request.mtime_ns,
      dev: observed.request.dev, ino: observed.request.ino, identity_sha256: observed.request.identity_sha256 },
    receiverRoot: observed.receiverRoot, receiverRootIdentitySha256: observed.receiverRootIdentitySha256,
    receiverLeaves: observed.receiverLeaves, issuerAuthoritySha256: sha256(canonicalJson(issuer)),
    materializerSha256: writer.source_sha256, writerSourceSha256: context.authority.components.writer.sha256,
  });
  const materializerPath = path.join(artifactRoot, 'publisher1-materializer.authority.json');
  const issuerPath = path.join(artifactRoot, 'vps-issuer-authority.receipt.json');
  const materializerBytes = canonicalJson(materializer);
  const issuerBytes = canonicalJson(issuer);
  await writeOrVerifyOwnerOnlyFile(materializerPath, materializerBytes, code);
  await writeOrVerifyOwnerOnlyFile(issuerPath, issuerBytes, code);
  const materializerEntry = await sourceEntry('materializer-authority', materializerPath, 'publisher1-materializer.authority.json', 0o444, code);
  const issuerEntry = await sourceEntry('issuer-receipt', issuerPath, 'vps-issuer-authority.receipt.json', 0o444, code);
  if (!materializerEntry.bytes.equals(materializerBytes) || !issuerEntry.bytes.equals(issuerBytes)) fail(code);
  const receiverByRole = Object.fromEntries(observed.receiverLeaves.map((leaf) => [leaf.role, leaf]));
  const launcherEntries = [];
  const successor = context.production_frozen_inputs !== undefined;
  for (const original of PUBLISHER1_BOOTSTRAP_ENTRY_CONTRACT.slice(3)) {
    const contract = successor && original.role === 'node-runtime'
      ? { ...original, destination: 'runtime/node-capsule/capsule/bin/node' } : original;
    const leaf = receiverByRole[contract.role];
    if (!isPlainObject(leaf) || leaf.path !== path.join(observed.receiverRoot, `${contract.role}.payload`)) fail(code);
    const entry = await sourceEntry(contract.role, leaf.path, contract.destination, contract.mode, code);
    if (entry.source_sha256 !== leaf.sha256 || entry.source_identity_sha256 !== leaf.identity_sha256) fail(code);
    launcherEntries.push(entry);
  }
  const capsuleEntries = successor
    ? await buildMacCapsuleBootstrapEntries({ context, capsuleRoot, nodeEntry: launcherEntries[0], code }) : [];
  const handoff = buildPublisher1BootstrapHandoff({
    bindings, context, gate0Receipt, issuer, pass, transportManifest, humanAuthorization,
    humanAuthorizationRequest, humanAuthorizationRequestObservation, installerProvenance, promptSha256,
    materializerAuthority: materializer,
    receiverRoot: observed.receiverRoot, receiverRootIdentitySha256: observed.receiverRootIdentitySha256, receiverLeaves: observed.receiverLeaves,
  });
  const roots = bootstrapInstallRoots(context);
  const request = {
    schema_version: 2, purpose: 'CI3_PUBLISHER1_BOOTSTRAP_INSTALL_REQUEST_V2', authority_sha: context.authority.commit,
    controller_generation_id: context.generations.controller, destination_root: roots.destination_root, state_root: roots.state_root,
    handoff, entries: [
      (({ bytes: _bytes, ...entry }) => entry)(materializerEntry),
      (({ bytes: _bytes, ...entry }) => entry)(issuerEntry),
      (({ bytes: _bytes, ...entry }) => entry)(writer),
      ...launcherEntries.map(({ bytes: _bytes, ...entry }) => entry),
      ...capsuleEntries.slice(1).map(({ bytes: _bytes, ...entry }) => entry),
    ], attempt: 1, retry: false, raw_values: false,
  };
  const requestBytes = canonicalJson(request);
  const requestPath = path.join(artifactRoot, 'publisher1-bootstrap.request.json');
  await writeOrVerifyOwnerOnlyFile(requestPath, requestBytes, code);
  const persisted = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  if (!persisted.bytes.equals(requestBytes) || !canonicalJson(JSON.parse(persisted.bytes.toString('utf8'))).equals(requestBytes)) fail(code);
  return Object.freeze({ request, request_bytes: requestBytes, request_path: requestPath, materializer, raw_values: false });
}

export async function validateCanonicalPublisher1BootstrapRequest({ requestPath, bindings, context, observed } = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  requireAbsoluteSafePath(requestPath, code);
  validateFrozenBindings(bindings);
  contextFields(context, code);
  const persisted = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  let request;
  try { request = JSON.parse(persisted.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(request).equals(persisted.bytes)) fail(code);
  exactKeys(request, ['schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'destination_root', 'state_root', 'handoff', 'entries', 'attempt', 'retry', 'raw_values'], code);
  if (request.schema_version !== 2 || request.purpose !== 'CI3_PUBLISHER1_BOOTSTRAP_INSTALL_REQUEST_V2'
      || request.authority_sha !== context.authority.commit || request.controller_generation_id !== context.generations.controller
      || request.attempt !== 1 || request.retry !== false || request.raw_values !== false) fail(code);
  await validatePublisher1BootstrapEntries(request.entries, context, code);
  validatePublisher1BootstrapHandoff(request.handoff, {
    bindings, context, receiverRoot: observed.receiverRoot, receiverRootIdentitySha256: observed.receiverRootIdentitySha256,
    receiverLeaves: observed.receiverLeaves,
  });
  const expected = bootstrapInstallRoots(context);
  if (request.destination_root !== expected.destination_root || request.state_root !== expected.state_root) fail(code);
  return Object.freeze({ request, bytes: persisted.bytes, request_path: requestPath, raw_values: false });
}

function publisher1SettledRoots({ roots, context, request }) {
  const code = 'STOP_PRE_AUTHORITY';
  const expected = bootstrapInstallRoots(context);
  if (request.destination_root !== expected.destination_root || request.state_root !== expected.state_root) fail(code);
  if (roots.syntheticRoot === null) return expected;
  return Object.freeze({
    destination_root: path.join(
      roots.syntheticRoot, 'publisher1-install-base', context.authority.commit,
      `bootstrap-${context.authority.manifest_sha256}`,
    ),
    state_root: path.join(roots.syntheticRoot, 'publisher1-state-base', context.authority.commit, context.generations.controller),
  });
}

function bootstrapSourceObservation(entry) {
  return Object.freeze({
    role: entry.role, sha256: entry.source_sha256, uid: entry.source_uid, gid: entry.source_gid,
    mode: entry.source_mode, nlink: entry.source_nlink, size: entry.source_size,
    mtime_ns: entry.source_mtime_ns, dev: entry.source_dev, ino: entry.source_ino,
    identity_sha256: entry.source_identity_sha256,
  });
}

async function observeSettledPublisher1Bootstrap({ roots, context, canonicalRequest }) {
  const code = 'STOP_PRE_AUTHORITY';
  try {
    const request = canonicalRequest.request;
    const settledRoots = publisher1SettledRoots({ roots, context, request });
    const claimPath = path.join(settledRoots.state_root, 'publisher1-bootstrap.claim.json');
    const resultPath = path.join(settledRoots.state_root, 'publisher1-bootstrap.result.json');
    const claim = await readPinnedSettledFile(claimPath, { mode: 0o444, code });
    const expectedClaim = Buffer.from(`{"schema_version":1,"purpose":"CI3_PUBLISHER1_BOOTSTRAP_CLAIM_V1","authority_sha":"${context.authority.commit}","controller_generation_id":"${context.generations.controller}","request_sha256":"${sha256(canonicalRequest.bytes)}","attempt":1,"retry":false,"raw_values":false}\n`);
    if (!claim.bytes.equals(expectedClaim)) fail(code);
    const resultFile = await readPinnedSettledFile(resultPath, { mode: 0o444, code });
    let result;
    try { result = JSON.parse(resultFile.bytes.toString('utf8')); } catch { fail(code); }
    if (!canonicalJson(result).equals(resultFile.bytes)) fail(code);
    exactKeys(result, [
      'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'claim_sha256',
      'request_sha256', 'source_observations', 'published_observations', 'terminal_state', 'raw_values',
    ], code);
    if (result.schema_version !== 1 || result.purpose !== 'CI3_PUBLISHER1_BOOTSTRAP_RESULT_V1'
        || result.authority_sha !== context.authority.commit
        || result.controller_generation_id !== context.generations.controller
        || result.claim_sha256 !== sha256(claim.bytes) || result.request_sha256 !== sha256(canonicalRequest.bytes)
        || result.terminal_state !== 'PUBLISHED' || result.raw_values !== false) fail(code);
    const expectedSource = request.entries.map(bootstrapSourceObservation);
    const expectedPublished = [];
    for (const entry of request.entries) {
      const targetPath = path.join(settledRoots.destination_root, entry.destination_relative_path);
      if (!targetPath.startsWith(`${settledRoots.destination_root}${path.sep}`)) fail(code);
      const target = await readPinnedSettledFile(targetPath, { mode: entry.mode, code });
      if (sha256(target.bytes) !== entry.source_sha256) fail(code);
      expectedPublished.push(Object.freeze({
        role: entry.role, sha256: sha256(target.bytes), ...target.metadata,
        identity_sha256: physicalIdentitySha256(target.metadata),
      }));
    }
    if (!canonicalJson(result.source_observations).equals(canonicalJson(expectedSource))
        || !canonicalJson(result.published_observations).equals(canonicalJson(expectedPublished))) fail(code);
    return 'SETTLED_EXACT';
  } catch {
    return 'DIVERGENT';
  }
}

export async function validateExactPublisher1PhaseA({ roots, context, canonicalRequest, artifactRoot }) {
  const code = 'STOP_PRE_AUTHORITY';
  requireAbsoluteSafePath(artifactRoot, code);
    const envelopePath = path.join(artifactRoot, 'publisher1-immutable-installer.request.json');
    const envelopeRecord = await readPinnedOwnerOnlyJson(envelopePath, code);
    const envelope = envelopeRecord.value;
    if (!canonicalJson(envelope).equals(envelopeRecord.bytes)) fail(code);
    exactKeys(envelope, [
      'schema_version', 'purpose', 'authority_sha', 'controller_generation_id',
      'bootstrap_request_path', 'bootstrap_request_path_sha256', 'bootstrap_request_sha256',
      'bootstrap_request_identity_sha256', 'bootstrap_request_uid', 'bootstrap_request_gid',
      'semantic_preflight_receipt_path', 'semantic_preflight_receipt_path_sha256',
      'semantic_preflight_receipt_sha256', 'semantic_preflight_receipt_identity_sha256',
      'semantic_preflight_receipt_uid', 'semantic_preflight_receipt_gid',
      'installer_compile_authority_sha256', 'installer_expected_binary_sha256',
      'installer_sha256', 'installer_root', 'attempt', 'retry', 'raw_values',
    ], code);
    if (envelope.schema_version !== 1 || envelope.purpose !== 'PUBLISHER1_IMMUTABLE_INSTALLER_BOOTSTRAP_V1'
        || envelope.authority_sha !== context.authority.commit
        || envelope.controller_generation_id !== context.generations.controller
        || envelope.bootstrap_request_path !== canonicalRequest.request_path
        || envelope.bootstrap_request_path_sha256 !== sha256(Buffer.from(canonicalRequest.request_path))
        || envelope.bootstrap_request_sha256 !== sha256(canonicalRequest.bytes)
        || envelope.installer_root !== immutableInstallerRoot(context, roots)
        || envelope.installer_sha256 !== envelope.installer_expected_binary_sha256
        || envelope.attempt !== 1 || envelope.retry !== false || envelope.raw_values !== false) fail(code);
    for (const field of [
      'bootstrap_request_identity_sha256', 'semantic_preflight_receipt_path_sha256',
      'semantic_preflight_receipt_sha256', 'semantic_preflight_receipt_identity_sha256',
      'installer_compile_authority_sha256', 'installer_expected_binary_sha256', 'installer_sha256',
    ]) requireHex(envelope[field], code);
    if (envelope.semantic_preflight_receipt_path_sha256
          !== sha256(Buffer.from(envelope.semantic_preflight_receipt_path))
        || !path.isAbsolute(envelope.semantic_preflight_receipt_path)
        || path.dirname(envelope.semantic_preflight_receipt_path) !== artifactRoot) fail(code);
    const requestFile = await readPinnedOwnerOnlyFile(envelope.bootstrap_request_path, { mode: 0o600, code });
    const preflightFile = await readPinnedOwnerOnlyFile(envelope.semantic_preflight_receipt_path, { mode: 0o600, code });
    if (!requestFile.bytes.equals(canonicalRequest.bytes)
        || physicalIdentitySha256(requestFile.metadata) !== envelope.bootstrap_request_identity_sha256
        || requestFile.metadata.uid !== envelope.bootstrap_request_uid
        || requestFile.metadata.gid !== envelope.bootstrap_request_gid
        || sha256(preflightFile.bytes) !== envelope.semantic_preflight_receipt_sha256
        || physicalIdentitySha256(preflightFile.metadata) !== envelope.semantic_preflight_receipt_identity_sha256
        || preflightFile.metadata.uid !== envelope.semantic_preflight_receipt_uid
        || preflightFile.metadata.gid !== envelope.semantic_preflight_receipt_gid) fail(code);
    const exactDirectory = async (directory, names) => {
      const observed = await lstat(directory, { bigint: true });
      const currentUid = BigInt(process.getuid());
      const currentGid = BigInt(process.getgid());
      const ownerAccepted = (observed.uid === 0n && observed.gid === 0n)
        || (observed.uid === currentUid && observed.gid === currentGid);
      const acceptedMode = roots.syntheticRoot === null ? 0o555 : 0o700;
      if (!observed.isDirectory() || observed.isSymbolicLink() || !ownerAccepted
          || Number(observed.mode & 0o777n) !== acceptedMode
          || JSON.stringify((await readdir(directory)).sort()) !== JSON.stringify([...names].sort())) fail(code);
    };
    const installedPath = path.join(envelope.installer_root, 'runtime', 'ci3-publisher1-bootstrap-installer');
    await exactDirectory(envelope.installer_root, ['runtime', 'immutable-installer-bootstrap.receipt.json']);
    await exactDirectory(path.join(envelope.installer_root, 'runtime'), ['ci3-publisher1-bootstrap-installer']);
    const installed = await readPinnedSettledFile(installedPath, { mode: 0o555, code });
    const receipt = await readPinnedSettledFile(
      path.join(envelope.installer_root, 'immutable-installer-bootstrap.receipt.json'), { mode: 0o444, code },
    );
    const expectedReceipt = canonicalJson({
      schema_version: 1, purpose: 'PUBLISHER1_IMMUTABLE_INSTALLER_BOOTSTRAP_RECEIPT_V1',
      authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
      envelope_sha256: sha256(envelopeRecord.bytes),
      envelope_identity_sha256: physicalIdentitySha256(envelopeRecord.metadata),
      bootstrap_request_sha256: envelope.bootstrap_request_sha256,
      semantic_preflight_receipt_sha256: envelope.semantic_preflight_receipt_sha256,
      installer_compile_authority_sha256: envelope.installer_compile_authority_sha256,
      installer_expected_binary_sha256: envelope.installer_expected_binary_sha256,
      installer_sha256: envelope.installer_sha256,
      installed_path_sha256: sha256(Buffer.from(installedPath)), status: 'PASS',
      phase_a_target_writes: 0, attempt: 1, retry: false, raw_values: false,
    });
    if (sha256(installed.bytes) !== envelope.installer_sha256 || !receipt.bytes.equals(expectedReceipt)) fail(code);
    let durableState;
    try {
      durableState = await validatePublisher1DurableService({
        roots, context, artifactRoot, envelope, envelopeBytes: envelopeRecord.bytes, installedPath,
      });
    } catch {
      durableState = await validatePublisher1DurableRegistrationBarrier({
        roots, context, artifactRoot, envelope, envelopeBytes: envelopeRecord.bytes, installedPath,
      });
    }
    const settledRoots = publisher1SettledRoots({ roots, context, request: canonicalRequest.request });
    for (const candidate of [settledRoots.destination_root, settledRoots.state_root]) {
      const existing = await lstat(candidate).catch((error) => {
        if (error?.code === 'ENOENT') return null;
        throw error;
      });
      if (existing !== null && durableState.phase_b_executing !== true) fail(code);
    }
  return 'PHASE_A_SETTLED_CONTINUING';
}

async function observeExactPublisher1PhaseA(input) {
  try {
    return await validateExactPublisher1PhaseA(input);
  } catch {
    return 'DIVERGENT';
  }
}

async function observeOperationAuthorityPublisherTransaction({ roots, context, canonical }) {
  const code = 'STOP_PRE_AUTHORITY';
  const transaction = canonical.observed.transaction;
  const expectedDestinationParent = roots.syntheticRoot === null
    ? '/Library/Application Support/Agentempp/ci3-controller-authority'
    : path.join(roots.syntheticRoot, 'publisher1-terminal-authority');
  const expectedStateRoot = roots.syntheticRoot === null
    ? path.join('/Library/Application Support/Agentempp/ci3-publisher1-state', context.authority.commit, context.generations.controller)
    : path.join(roots.syntheticRoot, 'publisher1-terminal-state', context.authority.commit, context.generations.controller);
  if (transaction.destination_parent !== expectedDestinationParent || transaction.state_root !== expectedStateRoot) fail(code);

  const operationRequestPath = path.join(canonical.frozenPaths.request_root, 'operation-authority.publisher-request.json');
  const operationRequest = await readPinnedOwnerOnlyFile(operationRequestPath, { mode: 0o600, code });
  const expectedOperationRequest = canonicalJson(buildOperationAuthorityPublisherRequest({
    context, receiverRoot: canonical.observed.receiverRoot, receiverLeaves: canonical.observed.receiverLeaves,
  }));
  if (!operationRequest.bytes.equals(expectedOperationRequest)) fail(code);

  const claimPath = path.join(transaction.state_root, 'publisher1.claim.json');
  const resultPath = path.join(transaction.state_root, 'publisher1.result.json');
  const claim = await readPinnedSettledFile(claimPath, { mode: 0o444, code });
  const expectedClaim = {
    schema_version: 1, purpose: 'CI3_PUBLISHER1_TRANSACTION_CLAIM_V1', authority_sha: context.authority.commit,
    remote_generation_id: context.generations.remote, controller_generation_id: context.generations.controller,
    receiver_manifest_sha256: transaction.receiver_manifest_sha256,
    request_sha256: canonical.observed.request.sha256,
    request_path_sha256: sha256(Buffer.from(canonical.frozenPaths.request_path)),
    request_identity_sha256: canonical.observed.request.identity_sha256,
    receiver_root_path_sha256: sha256(Buffer.from(canonical.observed.receiverRoot)),
    receiver_root_identity_sha256: canonical.observed.receiverRootIdentitySha256,
    entries: transaction.entries.map((entry) => ({
      role: entry.role, sha256: entry.source_sha256,
      destination_relative_path: entry.destination_relative_path, mode: entry.mode,
      source_path_sha256: entry.source_path_sha256,
      source_uid: entry.source_uid, source_gid: entry.source_gid,
      source_mode: entry.source_mode, source_nlink: entry.source_nlink,
      source_size: entry.source_size, source_mtime_ns: entry.source_mtime_ns,
      source_dev: entry.source_dev, source_ino: entry.source_ino,
      source_identity_sha256: entry.source_identity_sha256,
    })),
    attempt: 1, retry: false, raw_values: false,
  };
  if (!claim.bytes.equals(canonicalJson(expectedClaim))) fail(code);

  const publishedObservations = [];
  const versionRoot = path.join(transaction.destination_parent, context.authority.commit);
  for (const entry of transaction.entries) {
    const targetPath = path.join(versionRoot, entry.destination_relative_path);
    if (!targetPath.startsWith(`${versionRoot}${path.sep}`)) fail(code);
    const target = await readPinnedSettledFile(targetPath, { mode: entry.mode, code });
    if (sha256(target.bytes) !== entry.source_sha256) fail(code);
    publishedObservations.push({
      role: entry.role, sha256: entry.source_sha256,
      identity_sha256: physicalIdentitySha256(target.metadata), mode: entry.mode,
    });
  }

  const result = await readPinnedSettledFile(resultPath, { mode: 0o444, code });
  let resultRecord;
  try { resultRecord = JSON.parse(result.bytes.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(resultRecord).equals(result.bytes)) fail(code);
  exactKeys(resultRecord, [
    'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'claim_sha256',
    'request_sha256', 'source_observations', 'observations', 'terminal_state', 'raw_values',
  ], code);
  const expectedSourceObservations = expectedClaim.entries.map((entry) => ({
    role: entry.role, source_path_sha256: entry.source_path_sha256,
    source_sha256: entry.sha256, source_uid: entry.source_uid, source_gid: entry.source_gid,
    source_mode: entry.source_mode, source_nlink: entry.source_nlink,
    source_size: entry.source_size, source_mtime_ns: entry.source_mtime_ns,
    source_dev: entry.source_dev, source_ino: entry.source_ino,
    source_identity_sha256: entry.source_identity_sha256,
  }));
  if (resultRecord.schema_version !== 1 || resultRecord.purpose !== 'CI3_PUBLISHER1_TRANSACTION_RESULT_V1'
      || resultRecord.authority_sha !== context.authority.commit
      || resultRecord.controller_generation_id !== context.generations.controller
      || resultRecord.claim_sha256 !== sha256(claim.bytes)
      || resultRecord.request_sha256 !== canonical.observed.request.sha256
      || resultRecord.terminal_state !== 'PUBLISHED' || resultRecord.raw_values !== false
      || !canonicalJson(resultRecord.source_observations).equals(canonicalJson(expectedSourceObservations))
      || !canonicalJson(resultRecord.observations).equals(canonicalJson(publishedObservations))) fail(code);
  return Object.freeze({
    schema_version: 1, purpose: 'CI3_PUBLISHER1_CONTROLLER_SETTLEMENT_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    request_sha256: canonical.observed.request.sha256,
    receiver_root_sha256: sha256(Buffer.from(canonical.observed.receiverRoot)),
    claim_sha256: sha256(claim.bytes), result_sha256: sha256(result.bytes),
    tree_verified: true, raw_values: false,
  });
}

async function observeSettledOperationAuthorityPublisher({ roots, context, canonical }) {
  const code = 'STOP_PRE_AUTHORITY';
  try {
    const expectedSettlement = await observeOperationAuthorityPublisherTransaction({ roots, context, canonical });
    const settlementPath = path.join(canonical.frozenPaths.request_root, 'publisher1-controller.settlement.json');
    const settlement = await readPinnedOwnerOnlyFile(settlementPath, { mode: 0o600, code });
    if (!settlement.bytes.equals(canonicalJson(expectedSettlement))) fail(code);
    return 'SETTLED_EXACT';
  } catch {
    return 'DIVERGENT';
  }
}

export function buildOperationAuthorityPublisherRequest({ context, receiverRoot, receiverLeaves } = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  requireAbsoluteSafePath(receiverRoot, code);
  if (!Array.isArray(receiverLeaves) || receiverLeaves.length !== PUBLISHER1_ROLES.length) fail(code);
  const leaves = Object.fromEntries(receiverLeaves.map((leaf, index) => {
    validateLeaf(leaf, PUBLISHER1_ROLES[index], code, true);
    if (leaf.path !== path.join(receiverRoot, `${leaf.role}.payload`)) fail(code);
    return [leaf.role, leaf];
  }));
  const candidate = (role) => leaves[role].path;
  const digest = (role) => leaves[role].sha256;
  const installedBootstrapRoot = bootstrapInstallRoots(context).destination_root;
  return Object.freeze({
    schema_version: 1, purpose: 'CI3_OPERATION_AUTHORITY_PUBLISHER_REQUEST_V1', authority_sha: authority.commit,
    authority_candidate_path: candidate('operation-authority'), authority_candidate_sha256: digest('operation-authority'),
    authority_manifest_candidate_path: candidate('authority-manifest'), authority_manifest_candidate_sha256: digest('authority-manifest'),
    controller_candidate_path: candidate('controller'), controller_candidate_sha256: digest('controller'),
    human_authorization_receipt_path: candidate('human-authorization'), human_authorization_receipt_sha256: digest('human-authorization'),
    launch_attestation_candidate_path: candidate('launch-attestation'), launch_attestation_candidate_sha256: digest('launch-attestation'),
    launcher_candidate_path: candidate('launcher-runtime'), launcher_candidate_sha256: digest('launcher-runtime'),
    node_candidate_path: candidate('node-runtime'), node_candidate_sha256: digest('node-runtime'),
    publisher_input_manifest_path: candidate('publisher-input-manifest'), publisher_input_manifest_sha256: digest('publisher-input-manifest'),
    ssh_config_candidate_path: candidate('ssh-config'), ssh_config_candidate_sha256: digest('ssh-config'),
    ssh_known_hosts_candidate_path: candidate('ssh-known-hosts'), ssh_known_hosts_candidate_sha256: digest('ssh-known-hosts'),
    ssh_private_key_candidate_path: candidate('ssh-private-key'), ssh_private_key_candidate_sha256: digest('ssh-private-key'),
    ssh_public_key_candidate_path: candidate('ssh-public-key'), ssh_public_key_candidate_sha256: digest('ssh-public-key'),
    ssh_trust_descriptor_candidate_path: candidate('ssh-trust-descriptor'), ssh_trust_descriptor_candidate_sha256: digest('ssh-trust-descriptor'),
    vps_operation_authority_pass_path: candidate('vps-pass'), vps_operation_authority_pass_sha256: digest('vps-pass'),
    vps_issuer_authority_path: path.join(installedBootstrapRoot, 'vps-issuer-authority.receipt.json'),
    vps_issuer_authority_sha256: digest('vps-issuer-authority'),
    attempt: 1, retry: false, raw_values: false,
  });
}

async function persistOperationAuthorityPublisherRequest({ context, observed, requestRoot }) {
  const code = 'STOP_PRE_AUTHORITY';
  requireAbsoluteSafePath(requestRoot, code);
  if (!isPlainObject(observed) || observed.receiverRoot !== path.dirname(observed.receiverLeaves[0]?.path ?? '')) fail(code);
  const request = buildOperationAuthorityPublisherRequest({
    context, receiverRoot: observed.receiverRoot, receiverLeaves: observed.receiverLeaves,
  });
  const bytes = canonicalJson(request);
  const requestPath = path.join(requestRoot, 'operation-authority.publisher-request.json');
  await writeOrVerifyOwnerOnlyFile(requestPath, bytes, code);
  const persisted = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  if (!persisted.bytes.equals(bytes)) fail(code);
  return Object.freeze({ request, bytes, path: requestPath, sha256: sha256(bytes), raw_values: false });
}

function immutableInstallerRoot(context, roots) {
  const authority = contextFields(context, 'STOP_PRE_AUTHORITY');
  const base = roots.syntheticRoot === null
    ? '/Library/Application Support/Agentempp/ci3-publisher1-installer'
    : path.join(roots.syntheticRoot, 'publisher1-installer-base');
  return path.join(base, authority.commit, context.generations.controller);
}

function publisher1DurableServiceIdentity({ context, envelopeSha256, installedPath, installerSha256 }) {
  return sha256(canonicalJson({
    schema_version: 1, purpose: 'CI3_PUBLISHER1_DURABLE_PHASE_B_SERVICE_IDENTITY_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    immutable_request_sha256: envelopeSha256,
    installed_self_path_sha256: sha256(Buffer.from(installedPath)),
    installed_self_sha256: installerSha256, raw_values: false,
  }));
}

function publisher1DurableServiceDefinition({ label, installedPath, envelopePath, envelopeSha256, claimPath, claimSha256 }) {
  const escape = (value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  const args = [
    installedPath, '--durable-immutable-bootstrap-phase-b', envelopePath, envelopeSha256, claimPath, claimSha256,
  ].map((value) => `<string>${escape(value)}</string>`).join('');
  return Buffer.from(`<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Label</key><string>${escape(label)}</string><key>ProcessType</key><string>Background</string><key>ProgramArguments</key><array>${args}</array><key>StandardErrorPath</key><string>/dev/null</string><key>StandardInPath</key><string>/dev/null</string><key>StandardOutPath</key><string>/dev/null</string></dict></plist>`);
}

function publisher1DurableActivationOwnerDefinition({
  label, installedPath, envelopePath, envelopeSha256, claimPath, claimSha256,
}) {
  const escape = (value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  const ownerLabel = `${label}.activation-owner`;
  const args = [
    installedPath, '--durable-immutable-bootstrap-activation-owner',
    envelopePath, envelopeSha256, claimPath, claimSha256,
  ].map((value) => `<string>${escape(value)}</string>`).join('');
  return Buffer.from(`<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Label</key><string>${escape(ownerLabel)}</string><key>ProcessType</key><string>Background</string><key>ProgramArguments</key><array>${args}</array><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict><key>StandardErrorPath</key><string>/dev/null</string><key>StandardInPath</key><string>/dev/null</string><key>StandardOutPath</key><string>/dev/null</string></dict></plist>`);
}

async function validatePublisher1DurableRegistrationBarrier({
  roots, context, artifactRoot, envelope, envelopeBytes, installedPath,
}) {
  const code = 'STOP_PRE_AUTHORITY';
  if (roots.syntheticRoot === null) fail(code);
  const envelopeSha256 = sha256(envelopeBytes);
  const envelopePath = path.join(artifactRoot, 'publisher1-immutable-installer.request.json');
  const identity = publisher1DurableServiceIdentity({
    context, envelopeSha256, installedPath, installerSha256: envelope.installer_sha256,
  });
  const label = `com.agentempp.ci3.publisher1.${identity}`;
  const claimPath = path.join(artifactRoot, 'publisher1-durable-phase-b.service.json');
  const definitionPath = path.join(artifactRoot, 'publisher1-durable-phase-b.launchd.plist');
  const ownerDefinitionPath = path.join(
    artifactRoot, 'publisher1-durable-phase-b.activation-owner.plist',
  );
  const invocationPath = path.join(artifactRoot, 'publisher1-durable-phase-b.invocation.json');
  const registrationPath = path.join(artifactRoot, 'publisher1-durable-phase-b.registration.json');
  const claimBytes = canonicalJson({
    schema_version: 1, purpose: 'CI3_PUBLISHER1_DURABLE_PHASE_B_SERVICE_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    immutable_request_path_sha256: sha256(Buffer.from(envelopePath)),
    immutable_request_sha256: envelopeSha256,
    installed_self_path_sha256: sha256(Buffer.from(installedPath)),
    installed_self_sha256: envelope.installer_sha256, service_identity_sha256: identity,
    service_kind: 'VERSION_ADDRESSED_PERSISTENT_CONTINUATION', admin_prompt_budget: 1,
    phase_a_attempt: 1, retry: false, raw_values: false,
  });
  const definitionBytes = publisher1DurableServiceDefinition({
    label, installedPath, envelopePath, envelopeSha256,
    claimPath, claimSha256: sha256(claimBytes),
  });
  const ownerDefinitionBytes = publisher1DurableActivationOwnerDefinition({
    label, installedPath, envelopePath, envelopeSha256,
    claimPath, claimSha256: sha256(claimBytes),
  });
  const invocationBytes = canonicalJson({
    schema_version: 1, purpose: 'CI3_PUBLISHER1_DURABLE_PHASE_B_WORKER_INVOCATION_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    immutable_request_sha256: envelopeSha256, installed_self_sha256: envelope.installer_sha256,
    service_identity_sha256: identity, service_claim_sha256: sha256(claimBytes),
    service_definition_sha256: sha256(definitionBytes), worker_invocations: 1,
    attempt: 1, retry: false, raw_values: false,
  });
  const registrationBytes = canonicalJson({
    schema_version: 1, purpose: 'CI3_PUBLISHER1_DURABLE_PHASE_B_REGISTRATION_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    immutable_request_sha256: envelopeSha256, installed_self_sha256: envelope.installer_sha256,
    service_identity_sha256: identity, service_claim_sha256: sha256(claimBytes),
    service_definition_path_sha256: sha256(Buffer.from(definitionPath)),
    service_definition_sha256: sha256(definitionBytes),
    persistence: 'SYNTHETIC_VERSION_ADDRESSED_ACTIVATION_OWNER',
    status: 'REGISTERED', admin_prompt_budget: 1, phase_a_target_writes: 0,
    attempt: 1, retry: false, raw_values: false,
  });
  const stages = [
    ['CLAIM', [[claimPath, claimBytes]]],
    ['DEFINITION', [
      [claimPath, claimBytes], [definitionPath, definitionBytes],
      [ownerDefinitionPath, ownerDefinitionBytes],
    ]],
    ['INVOCATION', [
      [claimPath, claimBytes], [definitionPath, definitionBytes],
      [ownerDefinitionPath, ownerDefinitionBytes], [invocationPath, invocationBytes],
    ]],
    ['PRE_BOOTSTRAP', [
      [claimPath, claimBytes], [definitionPath, definitionBytes],
      [ownerDefinitionPath, ownerDefinitionBytes], [invocationPath, invocationBytes],
    ]],
    ['BOOTSTRAP', [
      [claimPath, claimBytes], [definitionPath, definitionBytes],
      [ownerDefinitionPath, ownerDefinitionBytes], [invocationPath, invocationBytes],
    ]],
    ['POST_BOOTSTRAP', [
      [claimPath, claimBytes], [definitionPath, definitionBytes],
      [ownerDefinitionPath, ownerDefinitionBytes], [invocationPath, invocationBytes],
    ]],
    ['PRE_REGISTRATION', [
      [claimPath, claimBytes], [definitionPath, definitionBytes],
      [ownerDefinitionPath, ownerDefinitionBytes], [invocationPath, invocationBytes],
    ]],
    ['REGISTRATION', [
      [claimPath, claimBytes], [definitionPath, definitionBytes],
      [ownerDefinitionPath, ownerDefinitionBytes], [invocationPath, invocationBytes],
      [registrationPath, registrationBytes],
    ]],
  ];
  const present = [];
  for (const [stage, required] of stages) {
    const barrierPath = path.join(
      artifactRoot, `publisher1-durable-registration-${stage.toLowerCase()}.prepared.json`,
    );
    const exists = await lstat(barrierPath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (!exists) continue;
    const record = await readPinnedSettledFile(barrierPath, { mode: 0o600, code });
    let barrier;
    try { barrier = JSON.parse(record.bytes.toString('utf8')); } catch { fail(code); }
    if (!canonicalJson(barrier).equals(record.bytes)) fail(code);
    exactKeys(barrier, [
      'schema_version', 'purpose', 'authority_sha', 'controller_generation_id',
      'immutable_request_sha256', 'installed_self_sha256', 'service_identity_sha256',
      'service_claim_sha256', 'service_definition_sha256', 'stage', 'decision', 'raw_values',
    ], code);
    if (barrier.schema_version !== 1
        || barrier.purpose !== 'CI3_SYNTHETIC_PUBLISHER1_DURABLE_REGISTRATION_BARRIER_V1'
        || barrier.authority_sha !== context.authority.commit
        || barrier.controller_generation_id !== context.generations.controller
        || barrier.immutable_request_sha256 !== envelopeSha256
        || barrier.installed_self_sha256 !== envelope.installer_sha256
        || barrier.service_identity_sha256 !== identity
        || barrier.service_claim_sha256 !== sha256(claimBytes)
        || barrier.service_definition_sha256 !== sha256(definitionBytes)
        || barrier.stage !== stage || barrier.decision !== 'PREPARED' || barrier.raw_values !== false) fail(code);
    for (const [file, expected] of required) {
      const observed = await readPinnedSettledFile(file, { mode: 0o600, code });
      if (!observed.bytes.equals(expected)) fail(code);
    }
    present.push(stage);
  }
  if (present.length !== 1) fail(code);
  return Object.freeze({ stage: present[0], service_identity_sha256: identity, raw_values: false });
}

async function validatePublisher1DurableService({ roots, context, artifactRoot, envelope, envelopeBytes, installedPath }) {
  const code = 'STOP_PRE_AUTHORITY';
  const envelopeSha256 = sha256(envelopeBytes);
  const envelopePath = path.join(artifactRoot, 'publisher1-immutable-installer.request.json');
  const identity = publisher1DurableServiceIdentity({
    context, envelopeSha256, installedPath, installerSha256: envelope.installer_sha256,
  });
  const label = `com.agentempp.ci3.publisher1.${identity}`;
  const synthetic = roots.syntheticRoot !== null;
  const stateRoot = synthetic
    ? artifactRoot
    : path.join('/Library/Application Support/Agentempp/ci3-publisher1-continuations', identity);
  const claimPath = path.join(stateRoot, 'publisher1-durable-phase-b.service.json');
  const definitionPath = synthetic
    ? path.join(stateRoot, 'publisher1-durable-phase-b.launchd.plist')
    : path.join('/Library/LaunchDaemons', `${label}.plist`);
  const ownerDefinitionPath = synthetic
    ? path.join(stateRoot, 'publisher1-durable-phase-b.activation-owner.plist')
    : path.join('/Library/LaunchDaemons', `${label}.activation-owner.plist`);
  const registrationPath = path.join(stateRoot, 'publisher1-durable-phase-b.registration.json');
  const invocationPath = path.join(stateRoot, 'publisher1-durable-phase-b.invocation.json');
  const mode = synthetic ? 0o600 : 0o444;
  const claim = {
    schema_version: 1, purpose: 'CI3_PUBLISHER1_DURABLE_PHASE_B_SERVICE_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    immutable_request_path_sha256: sha256(Buffer.from(envelopePath)),
    immutable_request_sha256: envelopeSha256,
    installed_self_path_sha256: sha256(Buffer.from(installedPath)),
    installed_self_sha256: envelope.installer_sha256, service_identity_sha256: identity,
    service_kind: 'VERSION_ADDRESSED_PERSISTENT_CONTINUATION', admin_prompt_budget: 1,
    phase_a_attempt: 1, retry: false, raw_values: false,
  };
  const claimBytes = canonicalJson(claim);
  const definitionBytes = publisher1DurableServiceDefinition({
    label, installedPath, envelopePath,
    envelopeSha256, claimPath, claimSha256: sha256(claimBytes),
  });
  const ownerDefinitionBytes = publisher1DurableActivationOwnerDefinition({
    label, installedPath, envelopePath, envelopeSha256,
    claimPath, claimSha256: sha256(claimBytes),
  });
  const invocationBytes = canonicalJson({
    schema_version: 1, purpose: 'CI3_PUBLISHER1_DURABLE_PHASE_B_WORKER_INVOCATION_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    immutable_request_sha256: envelopeSha256, installed_self_sha256: envelope.installer_sha256,
    service_identity_sha256: identity, service_claim_sha256: sha256(claimBytes),
    service_definition_sha256: sha256(definitionBytes), worker_invocations: 1,
    attempt: 1, retry: false, raw_values: false,
  });
  const registration = {
    schema_version: 1, purpose: 'CI3_PUBLISHER1_DURABLE_PHASE_B_REGISTRATION_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    immutable_request_sha256: envelopeSha256, installed_self_sha256: envelope.installer_sha256,
    service_identity_sha256: identity, service_claim_sha256: sha256(claimBytes),
    service_definition_path_sha256: sha256(Buffer.from(definitionPath)),
    service_definition_sha256: sha256(definitionBytes),
    persistence: synthetic
      ? 'SYNTHETIC_VERSION_ADDRESSED_ACTIVATION_OWNER'
      : 'LAUNCHD_VERSION_ADDRESSED_ACTIVATION_OWNER',
    status: 'REGISTERED', admin_prompt_budget: 1, phase_a_target_writes: 0,
    attempt: 1, retry: false, raw_values: false,
  };
  for (const [file, expected] of [
    [claimPath, claimBytes], [definitionPath, definitionBytes],
    [ownerDefinitionPath, ownerDefinitionBytes], [invocationPath, invocationBytes],
    [registrationPath, canonicalJson(registration)],
  ]) {
    const observed = await readPinnedSettledFile(file, { mode, code });
    if (!observed.bytes.equals(expected)) fail(code);
  }
  const markerBytes = (purpose, terminalState) => canonicalJson({
    schema_version: 1, purpose, authority_sha: context.authority.commit,
    service_identity_sha256: identity, service_claim_sha256: sha256(claimBytes),
    service_definition_sha256: sha256(definitionBytes), terminal_state: terminalState,
    attempt: 1, retry: false, raw_values: false,
  });
  let phaseBExecuting = false;
  for (const [leaf, purpose, terminalState, required] of [
    ['publisher1-durable-phase-b.started.json', 'CI3_PUBLISHER1_DURABLE_PHASE_B_STARTED_V1', 'RUNNING', false],
    ['publisher1-durable-phase-b.executing.json', 'CI3_PUBLISHER1_DURABLE_PHASE_B_EXECUTING_V1', 'PHASE_B_EXECUTING', false],
    ['publisher1-durable-phase-b.completed.json', 'CI3_PUBLISHER1_DURABLE_PHASE_B_COMPLETED_V1', 'PHASE_B_SETTLED', false],
  ]) {
    const markerPath = path.join(stateRoot, leaf);
    const exists = await lstat(markerPath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (!exists) {
      if (required) fail(code);
      continue;
    }
    const marker = await readPinnedSettledFile(markerPath, { mode, code });
    if (!marker.bytes.equals(markerBytes(purpose, terminalState))) fail(code);
    if (leaf === 'publisher1-durable-phase-b.executing.json') phaseBExecuting = true;
  }
  const failedExists = await lstat(path.join(stateRoot, 'publisher1-durable-phase-b.failed.json'))
    .then(() => true, (error) => { if (error?.code === 'ENOENT') return false; throw error; });
  if (failedExists) fail(code);
  return Object.freeze({
    identity, claim_sha256: sha256(claimBytes), definition_sha256: sha256(definitionBytes),
    phase_b_executing: phaseBExecuting, raw_values: false,
  });
}

async function runSemanticValidationBinary({ executable, argv, environment = CLOSED_ENVIRONMENT } = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  requireAbsoluteSafePath(executable, code);
  if (!Array.isArray(argv) || argv.some((value) => typeof value !== 'string' || /[\0\r\n]/.test(value))) fail(code);
  if (!canonicalJson(environment).equals(canonicalJson(CLOSED_ENVIRONMENT))) fail(code);
  return await new Promise((resolve, reject) => {
    let child;
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let settled = false;
    let timer;
    const stdout = [];
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) reject(error); else resolve(value);
    };
    try {
      child = spawnChild(executable, argv, {
        shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'], env: { ...environment },
      });
    } catch { finish(new ExternalPublisherError(code)); return; }
    child.stdout.on('data', (chunk) => {
      const bytes = Buffer.from(chunk);
      stdoutBytes += bytes.length;
      stdout.push(bytes);
      if (stdoutBytes > MAX_SUBPROCESS_BYTES) child.kill('SIGKILL');
    });
    child.stderr.on('data', (chunk) => {
      stderrBytes += Buffer.byteLength(chunk);
      if (stderrBytes > 0) child.kill('SIGKILL');
    });
    child.once('error', () => finish(new ExternalPublisherError(code)));
    child.once('close', (status) => {
      if (status !== 0 || stdoutBytes === 0 || stdoutBytes > MAX_SUBPROCESS_BYTES || stderrBytes !== 0) {
        finish(new ExternalPublisherError(code));
      } else {
        finish(null, Buffer.concat(stdout));
      }
    });
    timer = setTimeout(() => {
      child.kill('SIGKILL');
      finish(new ExternalPublisherError(code));
    }, 30_000);
  });
}

async function executePublisher1SemanticPreflight({
  context, artifactRoot, canonicalRequest, observed, writerBinaries,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  contextFields(context, code);
  requireAbsoluteSafePath(artifactRoot, code);
  if (!isPlainObject(canonicalRequest) || !Buffer.isBuffer(canonicalRequest.bytes)
      || !isPlainObject(observed) || !Array.isArray(observed.receiverLeaves)
      || !isPlainObject(writerBinaries)) fail(code);
  exactKeys(writerBinaries, [
    'operational_path', 'operational_sha256', 'validation_path', 'validation_sha256', 'raw_values',
  ], code);
  requireAbsoluteSafePath(writerBinaries.validation_path, code);
  requireHex(writerBinaries.validation_sha256, code);
  const validationBinary = await readPinnedOwnerOnlyFile(writerBinaries.validation_path, { mode: 0o500, code });
  if (sha256(validationBinary.bytes) !== writerBinaries.validation_sha256 || writerBinaries.raw_values !== false) fail(code);
  const bootstrap = await readPinnedOwnerOnlyFile(canonicalRequest.request_path, { mode: 0o600, code });
  if (!bootstrap.bytes.equals(canonicalRequest.bytes)) fail(code);
  const request = {
    schema_version: 1, purpose: 'CI3_PUBLISHER1_SEMANTIC_PREFLIGHT_REQUEST_V1',
    authority_sha: context.authority.commit, remote_generation_id: context.generations.remote,
    controller_generation_id: context.generations.controller,
    bootstrap_request_path: canonicalRequest.request_path,
    bootstrap_request_path_sha256: sha256(Buffer.from(canonicalRequest.request_path)),
    bootstrap_request_sha256: sha256(bootstrap.bytes),
    bootstrap_request_identity_sha256: physicalIdentitySha256(bootstrap.metadata),
    bootstrap_request_uid: bootstrap.metadata.uid, bootstrap_request_gid: bootstrap.metadata.gid,
    descriptor_request_path: observed.request.path,
    descriptor_request_path_sha256: sha256(Buffer.from(observed.request.path)),
    descriptor_request_sha256: observed.request.sha256,
    descriptor_request_identity_sha256: observed.request.identity_sha256,
    descriptor_request_uid: observed.request.uid, descriptor_request_gid: observed.request.gid,
    receiver_root_path_sha256: sha256(Buffer.from(observed.receiverRoot)),
    receiver_root_identity_sha256: observed.receiverRootIdentitySha256,
    validation_binary_sha256: writerBinaries.validation_sha256,
    attempt: 1, retry: false, raw_values: false,
  };
  const requestBytes = canonicalJson(request);
  const requestPath = path.join(artifactRoot, 'publisher1-semantic-preflight.request.json');
  await writeOrVerifyOwnerOnlyFile(requestPath, requestBytes, code);
  const persistedRequest = await readPinnedOwnerOnlyFile(requestPath, { mode: 0o600, code });
  if (!persistedRequest.bytes.equals(requestBytes)) fail(code);
  const stdout = await runSemanticValidationBinary({
    executable: writerBinaries.validation_path,
    argv: ['--publisher1-semantic-preflight', requestPath, sha256(requestBytes)],
  });
  let receipt;
  try { receipt = JSON.parse(stdout.toString('utf8')); } catch { fail(code); }
  if (!canonicalJson(receipt).equals(stdout)) fail(code);
  exactKeys(receipt, [
    'schema_version', 'purpose', 'authority_sha', 'remote_generation_id', 'controller_generation_id',
    'bootstrap_request_sha256', 'descriptor_request_sha256', 'descriptor_request_identity_sha256',
    'receiver_root_path_sha256', 'receiver_root_identity_sha256', 'validation_binary_sha256',
    'semantic_sources_sha256', 'publisher_installer_compile_authority_sha256',
    'publisher_installer_expected_binary_sha256', 'status', 'writes_performed', 'effect_executions', 'network_calls',
    'privilege_prompts', 'attempt', 'retry', 'raw_values',
  ], code);
  const humanInstallerBinding = installerBindingFromHuman(
    canonicalRequest.request.handoff.human_authorization, code,
  );
  const expectedSemanticSourcesSha256 = sha256(canonicalJson(observed.receiverLeaves.map((leaf) => ({
    role: leaf.role, sha256: leaf.sha256, identity_sha256: leaf.identity_sha256,
  }))));
  if (receipt.schema_version !== 1 || receipt.purpose !== 'CI3_PUBLISHER1_SEMANTIC_PREFLIGHT_RECEIPT_V1'
      || receipt.authority_sha !== context.authority.commit
      || receipt.remote_generation_id !== context.generations.remote
      || receipt.controller_generation_id !== context.generations.controller
      || receipt.bootstrap_request_sha256 !== sha256(bootstrap.bytes)
      || receipt.descriptor_request_sha256 !== observed.request.sha256
      || receipt.descriptor_request_identity_sha256 !== observed.request.identity_sha256
      || receipt.receiver_root_path_sha256 !== sha256(Buffer.from(observed.receiverRoot))
      || receipt.receiver_root_identity_sha256 !== observed.receiverRootIdentitySha256
      || receipt.validation_binary_sha256 !== writerBinaries.validation_sha256
      || receipt.semantic_sources_sha256 !== expectedSemanticSourcesSha256
      || receipt.publisher_installer_compile_authority_sha256 !== humanInstallerBinding.compile_authority_sha256
      || receipt.publisher_installer_expected_binary_sha256 !== humanInstallerBinding.expected_binary_sha256
      || receipt.status !== 'PASS' || receipt.writes_performed !== 0 || receipt.effect_executions !== 0
      || receipt.network_calls !== 0 || receipt.privilege_prompts !== 0 || receipt.attempt !== 1
      || receipt.retry !== false || receipt.raw_values !== false) fail(code);
  const receiptPath = path.join(artifactRoot, 'publisher1-semantic-preflight.receipt.json');
  await writeOrVerifyOwnerOnlyFile(receiptPath, stdout, code);
  const persistedReceipt = await readPinnedOwnerOnlyFile(receiptPath, { mode: 0o600, code });
  if (!persistedReceipt.bytes.equals(stdout)) fail(code);
  return Object.freeze({ path: receiptPath, bytes: stdout, receipt, raw_values: false });
}

async function persistImmutableInstallerEnvelope({
  roots, context, artifactRoot, canonicalRequest, semanticPreflight, installerArtifact,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  if (!isPlainObject(semanticPreflight) || !Buffer.isBuffer(semanticPreflight.bytes)
      || semanticPreflight.raw_values !== false || !isPlainObject(installerArtifact)) fail(code);
  exactKeys(installerArtifact, [
    'executable', 'executable_sha256', 'environment', 'compile_authority_sha256',
    'expected_binary_sha256', 'supervisor_source_base64', 'supervisor_source_sha256',
    'installer_provenance', 'raw_values',
  ], code);
  if (installerArtifact.executable_sha256 !== installerArtifact.expected_binary_sha256
      || semanticPreflight.receipt.publisher_installer_compile_authority_sha256
        !== installerArtifact.compile_authority_sha256
      || semanticPreflight.receipt.publisher_installer_expected_binary_sha256
        !== installerArtifact.expected_binary_sha256) fail(code);
  const receiptPath = semanticPreflight.path;
  requireAbsoluteSafePath(receiptPath, code);
  const requestFile = await readPinnedOwnerOnlyFile(canonicalRequest.request_path, { mode: 0o600, code });
  const receiptFile = await readPinnedOwnerOnlyFile(receiptPath, { mode: 0o600, code });
  if (!requestFile.bytes.equals(canonicalRequest.bytes) || !receiptFile.bytes.equals(semanticPreflight.bytes)) fail(code);
  const envelope = {
    schema_version: 1, purpose: 'PUBLISHER1_IMMUTABLE_INSTALLER_BOOTSTRAP_V1',
    authority_sha: context.authority.commit, controller_generation_id: context.generations.controller,
    bootstrap_request_path: canonicalRequest.request_path,
    bootstrap_request_path_sha256: sha256(Buffer.from(canonicalRequest.request_path)),
    bootstrap_request_sha256: sha256(requestFile.bytes),
    bootstrap_request_identity_sha256: physicalIdentitySha256(requestFile.metadata),
    bootstrap_request_uid: requestFile.metadata.uid, bootstrap_request_gid: requestFile.metadata.gid,
    semantic_preflight_receipt_path: receiptPath,
    semantic_preflight_receipt_path_sha256: sha256(Buffer.from(receiptPath)),
    semantic_preflight_receipt_sha256: sha256(receiptFile.bytes),
    semantic_preflight_receipt_identity_sha256: physicalIdentitySha256(receiptFile.metadata),
    semantic_preflight_receipt_uid: receiptFile.metadata.uid, semantic_preflight_receipt_gid: receiptFile.metadata.gid,
    installer_compile_authority_sha256: installerArtifact.compile_authority_sha256,
    installer_expected_binary_sha256: installerArtifact.expected_binary_sha256,
    installer_sha256: installerArtifact.executable_sha256,
    installer_root: immutableInstallerRoot(context, roots),
    attempt: 1, retry: false, raw_values: false,
  };
  const envelopeBytes = canonicalJson(envelope);
  const envelopePath = path.join(artifactRoot, 'publisher1-immutable-installer.request.json');
  await writeOrVerifyOwnerOnlyFile(envelopePath, envelopeBytes, code);
  const persisted = await readPinnedOwnerOnlyFile(envelopePath, { mode: 0o600, code });
  if (!persisted.bytes.equals(envelopeBytes)) fail(code);
  return Object.freeze({ path: envelopePath, sha256: sha256(envelopeBytes), receipt: semanticPreflight.receipt, raw_values: false });
}

export async function persistPublisher1PrivilegedBoundaryRequest({
  context, artifactRoot, requestPath, receiverRoot, expectedObserved,
  canonicalRequest, semanticPreflight, immutableRequest,
} = {}) {
  const code = 'STOP_PRE_AUTHORITY';
  const authority = contextFields(context, code);
  for (const value of [artifactRoot, requestPath, receiverRoot, canonicalRequest?.request_path,
    semanticPreflight?.path, immutableRequest?.path]) requireAbsoluteSafePath(value, code);
  if (!isPlainObject(expectedObserved) || !isPlainObject(canonicalRequest)
      || !isPlainObject(semanticPreflight) || !isPlainObject(immutableRequest)
      || !Buffer.isBuffer(canonicalRequest.bytes) || !Buffer.isBuffer(semanticPreflight.bytes)) fail(code);
  requireHex(immutableRequest.sha256, code);
  const observed = await observePreMaterializedControllerInputs({ context, requestPath, receiverRoot });
  if (!canonicalJson(observed.request).equals(canonicalJson(expectedObserved.request))
      || observed.receiverRoot !== expectedObserved.receiverRoot
      || observed.receiverRootIdentitySha256 !== expectedObserved.receiverRootIdentitySha256
      || !canonicalJson(observed.receiverLeaves).equals(canonicalJson(expectedObserved.receiverLeaves))) fail(code);
  const receipt = semanticPreflight.receipt;
  if (!isPlainObject(receipt) || receipt.status !== 'PASS' || receipt.writes_performed !== 0
      || receipt.descriptor_request_sha256 !== observed.request.sha256
      || receipt.descriptor_request_identity_sha256 !== observed.request.identity_sha256
      || receipt.receiver_root_path_sha256 !== sha256(Buffer.from(receiverRoot))
      || receipt.receiver_root_identity_sha256 !== observed.receiverRootIdentitySha256
      || receipt.semantic_sources_sha256 !== sha256(canonicalJson(observed.receiverLeaves.map((leaf) => ({
        role: leaf.role, sha256: leaf.sha256, identity_sha256: leaf.identity_sha256,
      }))))) fail(code);
  const boundary = {
    schema_version: 1, purpose: 'CI3_PUBLISHER1_PRIVILEGED_BOUNDARY_REQUEST_V1',
    authority_sha: authority.commit, controller_generation_id: context.generations.controller,
    bootstrap_request_path: canonicalRequest.request_path,
    bootstrap_request_sha256: sha256(canonicalRequest.bytes),
    semantic_preflight_receipt_path: semanticPreflight.path,
    semantic_preflight_receipt_sha256: sha256(semanticPreflight.bytes),
    immutable_request_path: immutableRequest.path, immutable_request_sha256: immutableRequest.sha256,
    descriptor_request: {
      ...observed.request, path_sha256: sha256(Buffer.from(observed.request.path)),
    },
    receiver_root: {
      path: receiverRoot, path_sha256: sha256(Buffer.from(receiverRoot)),
      identity_sha256: observed.receiverRootIdentitySha256,
    },
    receiver_leaves: observed.receiverLeaves,
    status: 'REOBSERVED_PASS', target_writes: 0, privilege_prompts: 0,
    attempt: 1, retry: false, raw_values: false,
  };
  const boundaryBytes = canonicalJson(boundary);
  const boundaryPath = path.join(artifactRoot, 'publisher1-privileged-boundary.request.json');
  await writeOrVerifyOwnerOnlyFile(boundaryPath, boundaryBytes, code);
  const persisted = await readPinnedOwnerOnlyFile(boundaryPath, { mode: 0o600, code });
  if (!persisted.bytes.equals(boundaryBytes)) fail(code);
  return Object.freeze({ path: boundaryPath, sha256: sha256(boundaryBytes), request: boundary, raw_values: false });
}

async function buildOuterOperationLedger({ mode, layout, context, observeSettled, awaitOriginalSettlement = null }) {
  const code = 'STOP_PRE_AUTHORITY';
  const operation = operationName(mode);
  const stateDirectory = path.join(layout.authority_root, 'state', operation);
  const state = await readPrivateDirectoryIdentity(stateDirectory, code);
  const attemptPath = path.join(stateDirectory, 'attempt.json');
  const resultPath = path.join(stateDirectory, 'result.json');
  const attemptBytes = canonicalJson({
    schema_version: 1, purpose: 'CI3_EXTERNAL_PUBLISHER_ATTEMPT_V1', authority_sha: context.authority.commit,
    controller_generation_id: context.generations.controller, operation, attempt: 1, retry: false, raw_values: false,
  });
  const expectedResult = canonicalJson({
    schema_version: 1, purpose: 'CI3_EXTERNAL_PUBLISHER_RESULT_V1', authority_sha: context.authority.commit,
    controller_generation_id: context.generations.controller, operation, attempt_sha256: sha256(attemptBytes),
    attempt: 1, retry: false, raw_values: false,
  });
  return Object.freeze({
    expectedExisting: async () => {
      const resultStat = await lstat(resultPath).catch((error) => {
        if (error?.code === 'ENOENT') return null;
        throw error;
      });
      if (resultStat === null) return false;
      const existing = await readPinnedOwnerOnlyFile(resultPath, { mode: 0o600, code });
      if (!existing.bytes.equals(expectedResult)) fail(code);
      return true;
    },
    attemptExisting: async () => {
      const attemptStat = await lstat(attemptPath).catch((error) => {
        if (error?.code === 'ENOENT') return null;
        throw error;
      });
      if (attemptStat === null) return false;
      const existing = await readPinnedOwnerOnlyFile(attemptPath, { mode: 0o600, code });
      if (!existing.bytes.equals(attemptBytes)) fail(code);
      return true;
    },
    observeSettled,
    persistRecoveredResult: async () => {
      await verifyNamedDirectory(stateDirectory, state, code);
      await writeOwnerOnlyNoClobber(resultPath, expectedResult, 0o600);
      await verifyNamedDirectory(stateDirectory, state, code);
      return true;
    },
    persistAttempt: async () => {
      await verifyNamedDirectory(stateDirectory, state, code);
      await writeOwnerOnlyNoClobber(attemptPath, attemptBytes, 0o600);
      await verifyNamedDirectory(stateDirectory, state, code);
      return true;
    },
    persistResult: async () => {
      await verifyNamedDirectory(stateDirectory, state, code);
      await writeOwnerOnlyNoClobber(resultPath, expectedResult, 0o600);
      await verifyNamedDirectory(stateDirectory, state, code);
      return true;
    },
    awaitOriginalSettlement,
  });
}

async function recoverSettledOuterOperation(ledger) {
  const code = 'STOP_PRE_AUTHORITY';
  const existing = await ledger.expectedExisting();
  if (existing === true) return Object.freeze({ state: 'EXISTS_VERIFIED', effect_executions: 0, raw_values: false });
  if (existing !== false) fail(code);
  const attempted = await ledger.attemptExisting();
  if (attempted === false) return null;
  if (attempted !== true) fail(code);
  let observed = await ledger.observeSettled();
  if (observed === 'PHASE_A_SETTLED_CONTINUING') {
    if (typeof ledger.awaitOriginalSettlement !== 'function') fail(code);
    observed = await ledger.awaitOriginalSettlement();
  }
  if (observed !== 'SETTLED_EXACT' || await ledger.persistRecoveredResult() !== true) fail(code);
  return Object.freeze({ state: 'RECOVERED_VERIFIED', effect_executions: 0, raw_values: false });
}

async function fixedInvocationForMode({
  mode, roots, layout, context, sourceRoot, modeAuthority, outerLedger = null,
  bootstrapRequestPath = null, installerArtifact = null, publisher0BootstrapInputs = null,
  observeSettled = async () => 'DIVERGENT',
}) {
  const code = 'STOP_PRE_AUTHORITY';
  validateModeAuthority(modeAuthority, mode, context);
  const operation = operationName(mode);
  const ledger = outerLedger ?? await buildOuterOperationLedger({ mode, layout, context, observeSettled });
  let executable;
  let argv;
  let input = null;
  let executionKind = 'SUBPROCESS';
  let environment = CLOSED_ENVIRONMENT;
  let transportRequestSha256 = null;
  if (mode === '--provision-mac-publisher1') {
    requireAbsoluteSafePath(bootstrapRequestPath, code);
    if (!isPlainObject(installerArtifact)) fail(code);
    exactKeys(installerArtifact, [
      'executable', 'executable_sha256', 'environment', 'compile_authority_sha256', 'expected_binary_sha256',
      'supervisor_source_base64', 'supervisor_source_sha256', 'installer_provenance',
      'immutable_request_path', 'immutable_request_sha256',
      'boundary_request_path', 'boundary_request_sha256', 'raw_values',
    ], code);
    requireAbsoluteSafePath(installerArtifact.executable, code);
    requireAbsoluteSafePath(installerArtifact.immutable_request_path, code);
    requireAbsoluteSafePath(installerArtifact.boundary_request_path, code);
    requireHex(installerArtifact.executable_sha256, code);
    requireHex(installerArtifact.immutable_request_sha256, code);
    requireHex(installerArtifact.boundary_request_sha256, code);
    requireHex(installerArtifact.compile_authority_sha256, code);
    requireHex(installerArtifact.expected_binary_sha256, code);
    if (installerArtifact.executable_sha256 !== installerArtifact.expected_binary_sha256) fail(code);
    if (installerArtifact.supervisor_source_sha256 !== installerArtifact.installer_provenance?.source_sha256) fail(code);
    if (installerArtifact.raw_values !== false) fail(code);
    const observedInstaller = await readPinnedOwnerOnlyFile(installerArtifact.executable, { mode: 0o700, code });
    if (sha256(observedInstaller.bytes) !== installerArtifact.executable_sha256) fail(code);
    if (roots.syntheticRoot === null) {
      const privileged = buildMacOsPrivilegedBootstrapInvocation({
        candidatePath: installerArtifact.executable, candidateSha256: installerArtifact.executable_sha256,
        immutableRequestPath: installerArtifact.immutable_request_path,
        immutableRequestSha256: installerArtifact.immutable_request_sha256,
        boundaryManifestPath: installerArtifact.boundary_request_path,
        boundaryManifestSha256: installerArtifact.boundary_request_sha256,
        supervisorSourceBase64: installerArtifact.supervisor_source_base64,
        supervisorSourceSha256: installerArtifact.supervisor_source_sha256,
      });
      executable = privileged.executable;
      argv = privileged.argv;
      environment = privileged.environment;
    } else {
      executable = installerArtifact.executable;
      argv = ['--immutable-bootstrap-phase-a', installerArtifact.immutable_request_path, installerArtifact.immutable_request_sha256];
      environment = installerArtifact.environment;
    }
  } else if (mode === '--provision-vps-publisher0') {
    const configPath = path.join(layout.authority_root, 'candidates', 'ssh-config.candidate');
    const transportBarrier = process.env.CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER ?? null;
    const remoteTransportBarrier = [
      'remote-before-terminal-link',
      'remote-after-terminal-link-before-directory-fsync',
      'remote-after-directory-fsync-before-terminal-decision',
    ].includes(transportBarrier) ? transportBarrier : null;
    const publisher0 = buildPublisher0GitBoundBootstrapInvocation({
      configPath, destinationAlias: 'ci3-publisher0', context,
      bootstrapInputs: publisher0BootstrapInputs,
      ...(roots.syntheticRoot === null ? {} : {
        syntheticRemoteRoot: path.join(roots.syntheticRoot, 'publisher0-fake-remote'),
        ...(remoteTransportBarrier === null ? {} : {
          syntheticTransportBarrierRoot: path.join(sourceRoot, 'publisher0-transport'),
          syntheticTransportBarrierStage: remoteTransportBarrier,
        }),
      }),
    });
    executable = roots.syntheticRoot === null
      ? publisher0.executable
      : path.join(roots.syntheticRoot, 'fixed-bin', operation);
    argv = publisher0.argv;
    input = publisher0.input;
    transportRequestSha256 = publisher0.request_sha256;
  } else if (roots.syntheticRoot !== null) {
    executable = path.join(roots.syntheticRoot, 'fixed-bin', operation);
    argv = [];
    if (mode === '--receive-vps-pass' || mode === '--verify-chain') {
      const existingAdapter = await lstat(executable).catch((error) => {
        if (error?.code === 'ENOENT') return null;
        throw error;
      });
      if (existingAdapter === null) {
        executionKind = 'AUTHORITY_BUILTIN';
        executable = null;
      }
    }
  } else if (mode === '--verify-chain') {
    ({ executable, argv, environment } = buildInstalledPublisher1LauncherInvocation({ context }));
  } else {
    if (mode !== '--receive-vps-pass') fail(code);
    executionKind = 'AUTHORITY_BUILTIN';
    executable = null;
    argv = [];
  }
  if (executionKind === 'SUBPROCESS') requireAbsoluteSafePath(executable, code);
  if (Object.hasOwn(modeAuthority, 'fixed_executable_sha256')) {
    if (roots.syntheticRoot === null || mode !== '--provision-vps-publisher0') fail(code);
    const fixedExecutable = await readPinnedOwnerOnlyFile(executable, { mode: 0o700, code });
    if (sha256(fixedExecutable.bytes) !== modeAuthority.fixed_executable_sha256) fail(code);
  }
  validateSubprocessEnvironment(environment, code);
  return Object.freeze({
    execution_kind: executionKind, executable, argv, input, environment,
    ...(transportRequestSha256 === null ? {} : { transport_request_sha256: transportRequestSha256 }),
    ...ledger,
  });
}

export async function buildAuthorityDerivedHandlers() {
  const code = 'STOP_PRE_AUTHORITY';
  const roots = fixedMainRoots();
  let bindings;
  try {
    bindings = await loadFrozenBindings(roots.bindingsPath);
  } catch {
    fail(code);
  }
  const layout = deriveAuthorityLayout(bindings, roots.ownerRoot);
  const sourceRoot = path.join(layout.authority_root, 'frozen');
  const contextRecord = await readPinnedOwnerOnlyJson(path.join(sourceRoot, 'context.json'), code);
  const gate0Record = await readPinnedOwnerOnlyJson(path.join(sourceRoot, 'gate0.json'), code);
  let context = contextRecord.value;
  if (context.production_frozen_inputs !== undefined) {
    let frozenValidation;
    try {
      const constructor = await import('./ci3-production-frozen-input-constructor.mjs');
      frozenValidation = await constructor.validatePublishedFrozenCorpus(
        layout.authority_root, bindings.MAC_EXECUTOR_AUTHORITY_SHA,
      );
    } catch {
      fail(code);
    }
    if (!isPlainObject(frozenValidation) || !isPlainObject(frozenValidation.context)) fail(code);
    if (!canonicalJson(frozenValidation.context).equals(canonicalJson(context))) fail(code);
    context = frozenValidation.context;
    validateProductionFrozenInputConsumerBinding(context.production_frozen_inputs, code);
  }
  contextFields(context, code);
  validateGate0Receipt(gate0Record.value, bindings, context);
  authorityProjection(bindings, context, code);
  const writerAuthoritySource = await readPinnedOwnerOnlyFile(
    path.join(sourceRoot, 'publisher1-input', 'writer.swift'), { mode: 0o600, code },
  );
  if (sha256(writerAuthoritySource.bytes) !== context.authority.components.writer.sha256) fail(code);
  const prompt = await readPinnedOwnerOnlyFile(path.join(sourceRoot, 'prompt.sha256'), { mode: 0o600, code });
  const promptSha256 = prompt.bytes.toString('utf8').trim();
  requireHex(promptSha256, code);
  const producedRoot = path.join(sourceRoot, 'publisher1-produced');
  const bootstrapRequestPath = path.join(producedRoot, 'publisher1-bootstrap.request.json');
  const publisher0CapturePath = path.join(sourceRoot, 'publisher0-output.capture.json');
  const publisher0JournalPath = path.join(sourceRoot, 'publisher0-output.capture.journal');
  const requireCompletedOperation = async (operation) => {
    const result = await readPinnedOwnerOnlyJson(
      path.join(layout.authority_root, 'state', operation, 'result.json'), code,
    );
    exactKeys(result.value, [
      'schema_version', 'purpose', 'authority_sha', 'controller_generation_id', 'operation',
      'attempt_sha256', 'attempt', 'retry', 'raw_values',
    ], code);
    if (result.value.schema_version !== 1 || result.value.purpose !== 'CI3_EXTERNAL_PUBLISHER_RESULT_V1'
        || result.value.authority_sha !== context.authority.commit
        || result.value.controller_generation_id !== context.generations.controller
        || result.value.operation !== operation || result.value.attempt !== 1
        || result.value.retry !== false || result.value.raw_values !== false) fail(code);
  };
  const readPublisher0Outputs = async () => {
    const finalExists = await lstat(publisher0CapturePath).then(() => true, (error) => {
      if (error?.code === 'ENOENT') return false;
      throw error;
    });
    if (!finalExists) {
      await settlePublisher0DurableTransportSession({ context, sourceRoot });
    }
    const captured = await readPinnedOwnerOnlyJson(publisher0CapturePath, code);
    if (!canonicalJson(captured.value).equals(captured.bytes)) fail(code);
    const validated = validateAuthenticatedPublisher0Output(captured.value, context);
    const final = await readPinnedOwnerOnlyFile(publisher0CapturePath, { mode: 0o600, code });
    if (!final.bytes.equals(captured.bytes)) fail(code);
    return validated;
  };
  const readPublisher0BootstrapInputs = async () => {
    const inputs = {};
    for (const role of TRANSPORT_ROLES) {
      inputs[role] = (await readPinnedOwnerOnlyFile(
        path.join(sourceRoot, 'publisher0-authority-input', `${role}.payload`), { mode: 0o600, code },
      )).bytes;
    }
    return inputs;
  };
  const readCanonicalPublisher1Request = async () => {
    const marker = await readPinnedOwnerOnlyFile(path.join(producedRoot, 'receiver-manifest.sha256'), { mode: 0o600, code });
    const receiverManifestSha256 = marker.bytes.toString('utf8').trim();
    requireHex(receiverManifestSha256, code);
    const frozenPaths = deriveFrozenControllerPublisherPaths(context, receiverManifestSha256);
    const observed = await observePreMaterializedControllerInputs({
      context, requestPath: frozenPaths.request_path, receiverRoot: frozenPaths.receiver_root,
    });
    const rawRequest = await readPinnedOwnerOnlyJson(bootstrapRequestPath, code);
    await validatePreMaterializedControllerTransaction({
      context, issuerBytes: canonicalJson(rawRequest.value?.handoff?.issuer),
      materializer: rawRequest.value?.handoff?.materializer_authority,
      requestPath: frozenPaths.request_path, receiverRoot: frozenPaths.receiver_root,
    });
    const canonicalRequest = await validateCanonicalPublisher1BootstrapRequest({
      requestPath: bootstrapRequestPath, bindings, context, observed,
    });
    return Object.freeze({ canonicalRequest, frozenPaths, observed });
  };
  const observeSettledForMode = async (mode) => {
    try {
      if (mode === '--provision-vps-publisher0') {
        await readPublisher0Outputs();
        return 'SETTLED_EXACT';
      }
      const canonical = await readCanonicalPublisher1Request();
      if (mode === '--receive-vps-pass') return 'SETTLED_EXACT';
      if (mode === '--provision-mac-publisher1') {
        const settled = await observeSettledPublisher1Bootstrap({
          roots, context, canonicalRequest: canonical.canonicalRequest,
        });
        if (settled === 'SETTLED_EXACT') return settled;
        return await observeExactPublisher1PhaseA({
          roots, context, canonicalRequest: canonical.canonicalRequest, artifactRoot: producedRoot,
        });
      }
      if (mode === '--verify-chain') {
        return await observeSettledOperationAuthorityPublisher({ roots, context, canonical });
      }
      return 'DIVERGENT';
    } catch {
      return 'DIVERGENT';
    }
  };
  const awaitOriginalPublisher1Settlement = async () => {
    const canonical = await readCanonicalPublisher1Request();
    for (let observation = 0; observation < 1200; observation += 1) {
      const settled = await observeSettledPublisher1Bootstrap({
        roots, context, canonicalRequest: canonical.canonicalRequest,
      });
      if (settled === 'SETTLED_EXACT') return settled;
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    return 'DIVERGENT';
  };
  const ensureOperationPublisherRequest = async () => {
    const canonical = await readCanonicalPublisher1Request();
    if (await observeSettledPublisher1Bootstrap({
      roots, context, canonicalRequest: canonical.canonicalRequest,
    }) !== 'SETTLED_EXACT') fail(code);
    return await persistOperationAuthorityPublisherRequest({
      context, observed: canonical.observed, requestRoot: canonical.frozenPaths.request_root,
    });
  };
  const settleSyntheticOperationAuthorityPublisher = async () => {
    if (roots.syntheticRoot === null) fail(code);
    const canonical = await readCanonicalPublisher1Request();
    const settledBootstrap = publisher1SettledRoots({
      roots, context, request: canonical.canonicalRequest.request,
    });
    const writerPath = path.join(settledBootstrap.destination_root, 'runtime', 'ci3-terminal-anchor-writer');
    const writerEntry = canonical.canonicalRequest.request.entries.find(({ role }) => role === 'writer-binary');
    const writer = await readPinnedSettledFile(writerPath, { mode: 0o555, code });
    if (!isPlainObject(writerEntry) || sha256(writer.bytes) !== writerEntry.source_sha256) fail(code);
    const materialized = await runBoundedFixedSubprocess({
      executable: writerPath,
      argv: ['--publisher1-transaction', canonical.frozenPaths.request_path, canonical.observed.request.sha256],
      environment: CLOSED_ENVIRONMENT,
      expectedExisting: async () => false,
      // The outer verify-chain attempt is the sole durable attempt. This
      // subordinate materializer never owns a second retry budget.
      persistAttempt: async () => true,
    });
    if (materialized.state !== 'CREATED' || materialized.effect_executions !== 1) fail(code);
    const settlement = await observeOperationAuthorityPublisherTransaction({ roots, context, canonical });
    const settlementPath = path.join(canonical.frozenPaths.request_root, 'publisher1-controller.settlement.json');
    await writeOrVerifyOwnerOnlyFile(settlementPath, canonicalJson(settlement), code);
    if (await observeSettledOperationAuthorityPublisher({ roots, context, canonical }) !== 'SETTLED_EXACT') fail(code);
    return true;
  };
  const materializeReceivedPublisher1Inputs = async () => {
    const publisher0 = await readPublisher0Outputs();
    const receiverManifestSha256 = sha256(canonicalJson(publisher0.transportManifest));
    const frozenPaths = deriveFrozenControllerPublisherPaths(context, receiverManifestSha256);
    try {
      await mkdir(frozenPaths.receiver_root, { recursive: true, mode: 0o700 });
    } catch { fail(code); }
    const bytesByRole = {
      ...publisher0.payloads,
      'launcher-bootstrap-authority': buildPublisher1LauncherBootstrapAuthority({ context, payloads: publisher0.payloads }),
      'vps-pass': canonicalJson(publisher0.pass),
      'vps-issuer-authority': canonicalJson(publisher0.issuer),
      'publisher-input-manifest': canonicalJson(publisher0.transportManifest),
    };
    exactKeys(bytesByRole, PUBLISHER1_RECEIVER_ROLES, code);
    const preauthorizationLeaves = [];
    for (const role of PUBLISHER1_RECEIVER_ROLES) {
      const leafPath = path.join(frozenPaths.receiver_root, `${role}.payload`);
      const bytes = bytesByRole[role];
      if (!Buffer.isBuffer(bytes) || bytes.length === 0) fail(code);
      await writeOrVerifyOwnerOnlyFile(leafPath, bytes, code);
      const leaf = await readPinnedOwnerOnlyFile(leafPath, { mode: 0o600, code });
      if (!leaf.bytes.equals(bytes)) fail(code);
      preauthorizationLeaves.push({
        role, path: leafPath, path_sha256: sha256(Buffer.from(leafPath)), sha256: sha256(leaf.bytes),
        ...leaf.metadata, identity_sha256: physicalIdentitySha256(leaf.metadata),
      });
    }
    const receiverDirectory = await readPrivateDirectoryIdentity(frozenPaths.receiver_root, code);
    if (receiverDirectory.metadata.mode !== 0o700) fail(code);
    const preauthorizationReceiverRootIdentitySha256 = physicalIdentitySha256(receiverDirectory.metadata);
    const installerSelection = await observePinnedPublisher1InstallerSelection({
      roots, sourceRoot, artifactRoot: producedRoot, context,
      authorityManifestBytes: publisher0.payloads['authority-manifest'],
    });
    const humanAuthorizationRequest = buildHumanAuthorizationRequest({
      context, issuer: publisher0.issuer, manifest: publisher0.transportManifest, pass: publisher0.pass,
      receiverRoot: frozenPaths.receiver_root,
      receiverRootIdentitySha256: preauthorizationReceiverRootIdentitySha256,
      receiverLeaves: preauthorizationLeaves,
      installerProvenance: installerSelection.installerProvenance,
      promptSha256,
    });
    const humanAuthorizationRequestPath = path.join(producedRoot, 'publisher1-human-authorization.request.json');
    const humanAuthorizationRequestBytes = canonicalJson(humanAuthorizationRequest);
    await writeOrVerifyOwnerOnlyFile(humanAuthorizationRequestPath, humanAuthorizationRequestBytes, code);
    const requestFile = await readPinnedOwnerOnlyFile(humanAuthorizationRequestPath, { mode: 0o600, code });
    if (!requestFile.bytes.equals(humanAuthorizationRequestBytes)) fail(code);
    const humanAuthorizationRequestObservation = {
      role: 'human-authorization-request', path: humanAuthorizationRequestPath,
      path_sha256: sha256(Buffer.from(humanAuthorizationRequestPath)), sha256: sha256(requestFile.bytes),
      ...requestFile.metadata, identity_sha256: physicalIdentitySha256(requestFile.metadata),
    };
    const promptAttemptPath = path.join(producedRoot, 'publisher1-human-authorization.prompt-attempt.json');
    const promptAttemptBytes = canonicalJson({
      schema_version: 1, purpose: 'CI3_HUMAN_AUTHORIZATION_PROMPT_ATTEMPT_V1',
      authority_sha: context.authority.commit,
      authorization_request_sha256: humanAuthorizationRequestObservation.sha256,
      authorization_request_identity_sha256: humanAuthorizationRequestObservation.identity_sha256,
      prompt_sha256: promptSha256, prompt_budget: 1, attempt: 1, retry: false, raw_values: false,
    });
    const persistPromptAttempt = async () => {
      await writeOwnerOnlyNoClobber(promptAttemptPath, promptAttemptBytes, 0o600);
      return true;
    };
    let confirmation;
    if (roots.syntheticRoot === null) {
      const boundary = await runHumanAuthorizationBoundary({
        requestPath: humanAuthorizationRequestPath,
        requestSha256: humanAuthorizationRequestObservation.sha256,
        requestIdentitySha256: humanAuthorizationRequestObservation.identity_sha256,
        persistAttempt: persistPromptAttempt,
      });
      confirmation = {
        authorized_uid: boundary.authorized_uid, authorized_gid: boundary.authorized_gid,
        prompt_budget: boundary.prompt_budget, confirmation_sha256: boundary.confirmation_sha256,
      };
    } else {
      await persistPromptAttempt();
      const identity = userInfo();
      confirmation = {
        authorized_uid: identity.uid, authorized_gid: identity.gid, prompt_budget: 1,
        confirmation_sha256: sha256(Buffer.from('button returned:Authorize\n')),
      };
    }
    const humanAuthorization = buildHumanAuthorizationReceipt({
      context, issuer: publisher0.issuer, manifest: publisher0.transportManifest, pass: publisher0.pass,
      authorizationRequest: humanAuthorizationRequest,
      authorizationRequestObservation: humanAuthorizationRequestObservation,
      receiverRoot: frozenPaths.receiver_root,
      receiverRootIdentitySha256: preauthorizationReceiverRootIdentitySha256,
      receiverLeaves: preauthorizationLeaves,
      installerProvenance: installerSelection.installerProvenance,
      promptSha256, confirmation,
    });
    bytesByRole['human-authorization'] = canonicalJson(humanAuthorization);
    await preMaterializeFrozenControllerTransaction({
      context, receiverRoot: frozenPaths.receiver_root, receiverManifestSha256,
      requestPath: frozenPaths.request_path, bytesByRole,
    });
    const observed = await observePreMaterializedControllerInputs({
      context, requestPath: frozenPaths.request_path, receiverRoot: frozenPaths.receiver_root,
    });
    const writerBinaries = await compilePinnedPublisher1WriterBinaries({ roots, sourceRoot, artifactRoot: producedRoot, context });
    await produceCanonicalPublisher1BootstrapRequest({
      bindings, context, gate0Receipt: gate0Record.value, issuer: publisher0.issuer, pass: publisher0.pass,
      transportManifest: publisher0.transportManifest, humanAuthorization,
      humanAuthorizationRequest, humanAuthorizationRequestObservation,
      installerProvenance: installerSelection.installerProvenance, promptSha256, observed,
      artifactRoot: producedRoot, writerSourcePath: writerBinaries.operational_path,
      ...(context.production_frozen_inputs === undefined
        ? {} : { capsuleRoot: macCapsuleSourceRoot(context, roots.syntheticRoot ?? homedir()) }),
    });
    await writeOrVerifyOwnerOnlyFile(
      path.join(producedRoot, 'receiver-manifest.sha256'), Buffer.from(`${receiverManifestSha256}\n`), code,
    );
  };
  const handler = async (mode, { signal, environment }) => {
    if (signal?.aborted || !canonicalJson(environment).equals(canonicalJson(CLOSED_ENVIRONMENT))) fail(code);
    if (mode === '--prepare') {
      const candidates = {};
      for (const role of PREPARE_CANDIDATE_ROLES) {
        candidates[role] = (await readPinnedOwnerOnlyFile(path.join(sourceRoot, 'candidates', `${role}.payload`), { mode: 0o600, code })).bytes;
      }
      return await runPrepare({
        bindings, context, ownerRoot: roots.ownerRoot, candidates, gate0Receipt: gate0Record.value, promptSha256,
        frozenReceiverRoot: null,
      });
    }
    const modeAuthority = (await readPinnedOwnerOnlyJson(path.join(sourceRoot, 'operations', `${operationName(mode)}.authority.json`), code)).value;
    if (mode === '--provision-vps-publisher0') {
      await readPinnedOwnerOnlyFile(path.join(layout.authority_root, 'candidates', 'ssh-config.candidate'), { mode: 0o600, code });
    }
    if (mode === '--receive-vps-pass') await requireCompletedOperation('provision-vps-publisher0');
    if (mode === '--provision-mac-publisher1') await requireCompletedOperation('receive-vps-pass');
    if (mode === '--verify-chain') await requireCompletedOperation('provision-mac-publisher1');
    if (mode === '--verify-chain') await ensureOperationPublisherRequest();
    validateModeAuthority(modeAuthority, mode, context);
    const outerLedger = await buildOuterOperationLedger({
      mode, layout, context, observeSettled: () => observeSettledForMode(mode),
      awaitOriginalSettlement: mode === '--provision-mac-publisher1'
        ? awaitOriginalPublisher1Settlement : null,
    });
    const recovered = await recoverSettledOuterOperation(outerLedger);
    if (recovered !== null) {
      if (mode === '--provision-mac-publisher1') await ensureOperationPublisherRequest();
      return recovered;
    }
    let installerArtifact = null;
    let publisher0BootstrapInputs = null;
    if (mode === '--provision-vps-publisher0') publisher0BootstrapInputs = await readPublisher0BootstrapInputs();
    if (mode === '--provision-mac-publisher1') {
      const canonical = await readPinnedOwnerOnlyJson(bootstrapRequestPath, code);
      const marker = await readPinnedOwnerOnlyFile(path.join(producedRoot, 'receiver-manifest.sha256'), { mode: 0o600, code });
      const receiverManifestSha256 = marker.bytes.toString('utf8').trim();
      requireHex(receiverManifestSha256, code);
      const frozenPaths = deriveFrozenControllerPublisherPaths(context, receiverManifestSha256);
      const observed = await observePreMaterializedControllerInputs({ context, requestPath: frozenPaths.request_path, receiverRoot: frozenPaths.receiver_root });
      await validatePreMaterializedControllerTransaction({
        context, issuerBytes: canonicalJson(canonical.value?.handoff?.issuer),
        materializer: canonical.value?.handoff?.materializer_authority,
        requestPath: frozenPaths.request_path, receiverRoot: frozenPaths.receiver_root,
      });
      const canonicalRequest = await validateCanonicalPublisher1BootstrapRequest({
        requestPath: bootstrapRequestPath, bindings, context, observed,
      });
      const writerBinaries = await compilePinnedPublisher1WriterBinaries({
        roots, sourceRoot, artifactRoot: producedRoot, context,
      });
      const semanticPreflight = await executePublisher1SemanticPreflight({
        context, artifactRoot: producedRoot, canonicalRequest, observed, writerBinaries,
      });
      const publisher0 = await readPublisher0Outputs();
      const compiledInstaller = await compilePinnedPublisher1Installer({
        roots, sourceRoot, artifactRoot: producedRoot, context,
        authorityManifestBytes: publisher0.payloads['authority-manifest'],
        humanAuthorization: canonicalRequest.request.handoff.human_authorization,
      });
      const immutable = await persistImmutableInstallerEnvelope({
        roots, context, artifactRoot: producedRoot, canonicalRequest, semanticPreflight,
        installerArtifact: compiledInstaller,
      });
      const syntheticSwapRole = process.env.CI3_SYNTHETIC_POST_PREFLIGHT_SWAP_ROLE;
      if (syntheticSwapRole !== undefined) {
        if (roots.syntheticRoot === null || !PUBLISHER1_ROLES.includes(syntheticSwapRole)) fail(code);
        const leafPath = path.join(frozenPaths.receiver_root, `${syntheticSwapRole}.payload`);
        const leaf = await readPinnedOwnerOnlyFile(leafPath, { mode: 0o600, code });
        const displacedPath = path.join(frozenPaths.receiver_root, `.${syntheticSwapRole}.post-preflight-displaced`);
        try { await rename(leafPath, displacedPath); } catch { fail(code); }
        await writeOwnerOnlyNoClobber(leafPath, leaf.bytes, 0o600);
      }
      const boundary = await persistPublisher1PrivilegedBoundaryRequest({
        context, artifactRoot: producedRoot,
        requestPath: frozenPaths.request_path, receiverRoot: frozenPaths.receiver_root,
        expectedObserved: observed, canonicalRequest, semanticPreflight, immutableRequest: immutable,
      });
      installerArtifact = Object.freeze({
        ...compiledInstaller, immutable_request_path: immutable.path, immutable_request_sha256: immutable.sha256,
        boundary_request_path: boundary.path, boundary_request_sha256: boundary.sha256,
      });
    }
    const invocation = await fixedInvocationForMode({
      mode, roots, layout, context, sourceRoot, modeAuthority, outerLedger,
      bootstrapRequestPath, installerArtifact, publisher0BootstrapInputs,
      observeSettled: () => observeSettledForMode(mode),
    });
    if (mode === '--receive-vps-pass') {
      if (invocation.execution_kind === 'AUTHORITY_BUILTIN') {
        return await runAuthorityBuiltinOperation({
          expectedExisting: invocation.expectedExisting,
          attemptExisting: invocation.attemptExisting,
          observeSettled: invocation.observeSettled,
          persistRecoveredResult: invocation.persistRecoveredResult,
          persistAttempt: invocation.persistAttempt,
          effect: async () => { await materializeReceivedPublisher1Inputs(); return true; },
          persistResult: invocation.persistResult,
        });
      }
      const transported = await runBoundedFixedSubprocess(invocation);
      if (transported.state === 'EXISTS_VERIFIED') return transported;
      if (transported.state !== 'CREATED') fail(code);
      await materializeReceivedPublisher1Inputs();
      if (await invocation.persistResult() !== true) fail(code);
      return Object.freeze({
        state: 'CREATED', effect_executions: 1,
        stdout_bytes: transported.stdout_bytes, stderr_bytes: transported.stderr_bytes, raw_values: false,
      });
    }
    if (mode === '--verify-chain' && invocation.execution_kind === 'AUTHORITY_BUILTIN') {
      return await runAuthorityBuiltinOperation({
        expectedExisting: invocation.expectedExisting,
        attemptExisting: invocation.attemptExisting,
        observeSettled: invocation.observeSettled,
        persistRecoveredResult: invocation.persistRecoveredResult,
        persistAttempt: invocation.persistAttempt,
        effect: settleSyntheticOperationAuthorityPublisher,
        persistResult: invocation.persistResult,
      });
    }
    let result;
    if (mode === '--provision-vps-publisher0') {
      const transportBarrier = process.env.CI3_SYNTHETIC_PUBLISHER0_TRANSPORT_BARRIER ?? null;
      if (transportBarrier !== null && roots.syntheticRoot === null) fail(code);
      await startPublisher0DurableTransportSession({
        invocation, context, sourceRoot, persistAttempt: invocation.persistAttempt,
        barrierStage: transportBarrier,
      });
      const settledTransport = await settlePublisher0DurableTransportSession({
        context, sourceRoot,
        crashAfterJournal: roots.syntheticRoot !== null
          && process.env.CI3_SYNTHETIC_PUBLISHER0_CRASH_AFTER_JOURNAL === '1',
      });
      result = Object.freeze({
        state: 'CREATED', effect_executions: 1,
        stdout_bytes: settledTransport.stdout_bytes, stderr_bytes: settledTransport.stderr_bytes,
        stdout: settledTransport.bytes, stdout_sha256: settledTransport.stdout_sha256, raw_values: false,
      });
    } else {
      result = await runBoundedFixedSubprocess(invocation);
    }
    if (result.state === 'CREATED' && mode === '--provision-vps-publisher0') {
      if (!Buffer.isBuffer(result.stdout) || result.stdout.length === 0) fail(code);
      let output;
      try { output = JSON.parse(result.stdout.toString('utf8')); } catch { fail(code); }
      if (!canonicalJson(output).equals(result.stdout)) fail(code);
      validateAuthenticatedPublisher0Output(output, context);
      await readPublisher0Outputs();
    }
    if (result.state === 'CREATED' && mode === '--provision-mac-publisher1') {
      await ensureOperationPublisherRequest();
    }
    if (result.state === 'CREATED' && mode === '--verify-chain' && roots.syntheticRoot !== null) {
      await settleSyntheticOperationAuthorityPublisher();
    }
    if (result.state === 'CREATED' && await invocation.persistResult() !== true) fail(code);
    return result;
  };
  return Object.freeze({
    prepare: (input) => handler('--prepare', input),
    provisionPublisher0: (input) => handler('--provision-vps-publisher0', input),
    receivePublisher0Pass: (input) => handler('--receive-vps-pass', input),
    provisionPublisher1: (input) => handler('--provision-mac-publisher1', input),
    verifyChain: (input) => handler('--verify-chain', input),
  });
}

export async function runSelfTest() {
  const parsed = parseMode(['--self-test']);
  if (parsed !== '--self-test' || SCRIPT_PATH.length === 0 || Object.keys(CLOSED_ENVIRONMENT).length !== 4) fail('SELF_TEST');
  return {
    state: 'SELF_TEST_PASS', network_calls: 0, admin_prompts: 0,
    simulator_executions: 0, root_writes: 0, raw_values: false,
  };
}

async function main() {
  if (process.argv.slice(2)[0] === PUBLISHER0_TRANSPORT_OWNER_MODE) {
    const ownerArguments = process.argv.slice(2);
    if (ownerArguments.length !== 3) fail('MODE_INVALID');
    process.umask(0o077);
    await runPublisher0TransportOwner(ownerArguments[1], ownerArguments[2]);
    return;
  }
  if (process.argv.slice(2)[0] === PUBLISHER0_TRANSPORT_JOURNAL_WORKER_MODE) {
    const workerArguments = process.argv.slice(2);
    if (workerArguments.length !== 5) fail('MODE_INVALID');
    process.umask(0o077);
    await runPublisher0TransportJournalWorker(
      workerArguments[1], workerArguments[2], workerArguments[3], workerArguments[4],
    );
    return;
  }
  if (process.argv.slice(2)[0] === PUBLISHER0_TRANSPORT_SESSION_SUPERVISOR_MODE) {
    const supervisorArguments = process.argv.slice(2);
    if (supervisorArguments.length !== 3) fail('MODE_INVALID');
    process.umask(0o077);
    await runPublisher0TransportSessionSupervisor(supervisorArguments[1], supervisorArguments[2]);
    return;
  }
  if (process.argv.slice(2)[0] === PUBLISHER0_TRANSPORT_BROKER_MODE) {
    const brokerArguments = process.argv.slice(2);
    if (brokerArguments.length !== 3) fail('MODE_INVALID');
    process.umask(0o077);
    await runPublisher0TransportBroker(brokerArguments[1], brokerArguments[2]);
    return;
  }
  const mode = parseMode(process.argv.slice(2));
  if (mode === '--self-test') {
    const result = await dispatchExternalPublisherMode(mode);
    process.stdout.write(`${result.state} raw_values=false\n`);
    return;
  }
  // There is deliberately no ambient operational adapter. Every mode is
  // derived from owner-only frozen artifacts; an incomplete set stops before
  // an attempt marker or child process can exist.
  process.umask(0o077);
  await dispatchExternalPublisherMode(mode, await buildAuthorityDerivedHandlers());
}

if (process.argv[1] && path.resolve(process.argv[1]) === SCRIPT_PATH) {
  main().catch((error) => {
    const mode = process.argv.slice(2)[0];
    const code = error?.code ?? 'STOP_PRE_AUTHORITY';
    if (MODES.includes(mode) && mode !== '--self-test' && code === 'STOP_PRE_AUTHORITY') {
      process.stderr.write(`STOP_PRE_AUTHORITY mode=${mode} raw_values=false\n`);
    } else {
      process.stderr.write(`${code}\n`);
    }
    process.exitCode = 1;
  });
}
