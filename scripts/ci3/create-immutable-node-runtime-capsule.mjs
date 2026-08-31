import { constants as FS } from 'node:fs';
import {
  chmod, lstat, mkdir, open, readdir, rename, rmdir, unlink,
} from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ARCHITECTURE = 'PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V1';
export const BOOTSTRAP_NODE = '/usr/bin/node';
export const BOOTSTRAP_SHA256 = '6295488653f0d93b0a157841746fef7e72cc4328cfb60c4bbe0ca2668a836ffd';
export const BRIDGE_AUTHORITY_SHA = 'ba8473799a19aec586b0fe706bb7d4084589c86c';
export const AUTHORITY_PARENT = BRIDGE_AUTHORITY_SHA;
export const AUTHORITY_SUBJECT = 'build(ops): authorize immutable VPS Node runtime capsule';
export const BUILDER_GIT_PATH = 'scripts/ci3/create-immutable-node-runtime-capsule.mjs';
export const RUNTIME_ROOT = '/root/.config/agentempp/runtimes/node';
export const FORBIDDEN_NVM_PREFIX = '/root/.nvm/';
export const TOOL_PATHS = Object.freeze({
  chattr: '/usr/bin/chattr',
  findmnt: '/usr/bin/findmnt',
  git: '/usr/bin/git',
  ldd: '/usr/bin/ldd',
  lsattr: '/usr/bin/lsattr',
  readelf: '/usr/bin/readelf',
  sha256sum: '/usr/bin/sha256sum',
  stat: '/usr/bin/stat',
});
export const AUTHORITY_PATHS = Object.freeze([
  'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md',
  'docs/superpowers/evidence/2026-08-31-ci3-node-runtime-stop-and-capsule-authority.md',
  'docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md',
  BUILDER_GIT_PATH,
  'scripts/ci3/create-immutable-node-runtime-capsule.test.mjs',
]);
export const SECRET_PATHS = Object.freeze([
  '/root/.config/agentempp/secrets/ci3-staging-mobile-bff.env',
  '/root/.config/agentempp/secrets/ci3-staging-mobile-bff.receipt.json',
  '/root/.config/agentempp/secrets/ci3-dedicated-mobile-bff-deployment.receipt.json',
  '/root/.config/agentempp/secrets/ci3-synthetic-patient.credentials.json',
  '/root/.config/agentempp/secrets/ci3-synthetic-patient.provisioning.receipt.json',
]);
export const RECEIPT_KEYS = Object.freeze([
  'architecture', 'authority_manifest_sha256', 'builder_blob_oid', 'builder_sha256',
  'capability_probe', 'capsule_directory_immutable', 'capsule_generation_id',
  'capsule_gid', 'capsule_mode', 'capsule_nlink', 'capsule_node_identity_sha256',
  'capsule_node_immutable', 'capsule_node_path_sha256', 'capsule_node_sha256',
  'capsule_receipt_immutable', 'capsule_uid', 'chattr_sha256', 'created_at_utc',
  'dynamic_closure_count', 'dynamic_closure_revalidated', 'dynamic_closure_sha256',
  'filesystem_descriptor_sha256', 'lsattr_sha256', 'network_calls', 'nvm_modified',
  'package_manager_write', 'purpose', 'raw_values_reported',
  'runtime_authority_commit', 'runtime_authority_parent', 'runtime_authority_subject',
  'runtime_authority_tree', 'schema_version', 'secrets_read', 'source_identity_sha256',
  'source_immutable', 'source_parent_chain_sha256', 'source_path', 'source_path_sha256',
  'source_process_versions_sha256', 'source_role', 'source_sha256', 'source_version',
  'system_node_modified', 'tool_manifest_sha256',
]);

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const SHA40 = /^[a-f0-9]{40}$/;
const SHA64 = /^[a-f0-9]{64}$/;
const GENERATION = /^node-[a-f0-9]{64}$/;

export class CapsuleError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

export function fail(code) {
  throw new CapsuleError(code);
}

export function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export function gitBlobOid(bytes) {
  const body = Buffer.from(bytes);
  return createHash('sha1').update(Buffer.from(`blob ${body.length}\0`)).update(body).digest('hex');
}

export function canonicalJson(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
}

export function jsonBytes(value) {
  return `${canonicalJson(value)}\n`;
}

export function parseMode(argv) {
  if (argv.length !== 1) fail('MODE_INVALID');
  if (argv[0] === '--self-test') return 'self-test';
  if (argv[0] === '--create') return 'create';
  if (argv[0] === '--verify') return 'verify';
  fail('MODE_INVALID');
}

export function sanitizeError(error) {
  const code = typeof error?.code === 'string' && /^[A-Z0-9_]+$/.test(error.code)
    ? error.code : 'UNEXPECTED';
  return `ERROR ${code}`;
}

function bigint(value, code = 'IDENTITY') {
  if (typeof value === 'bigint') return value;
  if (typeof value === 'string' && /^(0|[1-9][0-9]*)$/.test(value)) return BigInt(value);
  fail(code);
}

export function identity(statValue) {
  const result = {
    uid: bigint(statValue.uid), gid: bigint(statValue.gid), mode: bigint(statValue.mode),
    nlink: bigint(statValue.nlink), size: bigint(statValue.size),
    mtimeNs: bigint(statValue.mtimeNs), ctimeNs: bigint(statValue.ctimeNs),
    dev: bigint(statValue.dev), ino: bigint(statValue.ino),
  };
  return result;
}

export function physicalIdentitySha256(value) {
  const v = identity(value);
  const preimage = `uid=${v.uid};gid=${v.gid};mode=${v.mode & 0o777n};nlink=${v.nlink};size=${v.size};mtime=${v.mtimeNs};dev=${v.dev};ino=${v.ino}`;
  return sha256(Buffer.from(preimage));
}

export function assertStableIdentity(before, after, code = 'IDENTITY_DRIFT') {
  const a = identity(before);
  const b = identity(after);
  for (const key of Object.keys(a)) if (a[key] !== b[key]) fail(code);
  return true;
}

function safeNumber(value, code) {
  const exact = bigint(value, code);
  const number = Number(exact);
  if (!Number.isSafeInteger(number) || BigInt(number) !== exact) fail(code);
  return number;
}

export function validateRegularMetadata(metadata, { mode, uid = 0, gid = 0, code = 'FILE_METADATA' }) {
  if (!metadata.isFile?.() || metadata.isSymbolicLink?.()) fail(code);
  if (safeNumber(metadata.uid, code) !== uid || safeNumber(metadata.gid, code) !== gid) fail(code);
  if (mode !== undefined && mode !== null && (safeNumber(metadata.mode, code) & 0o777) !== mode) fail(code);
  if (safeNumber(metadata.nlink, code) !== 1) fail(code);
  return true;
}

export function validateDirectoryMetadata(metadata, { mode, uid = 0, gid = 0, immutable = null, attrs = '' }) {
  if (!metadata.isDirectory?.() || metadata.isSymbolicLink?.()) fail('DIRECTORY_METADATA');
  if (safeNumber(metadata.uid, 'DIRECTORY_METADATA') !== uid || safeNumber(metadata.gid, 'DIRECTORY_METADATA') !== gid) fail('DIRECTORY_METADATA');
  if ((safeNumber(metadata.mode, 'DIRECTORY_METADATA') & 0o777) !== mode) fail('DIRECTORY_METADATA');
  if (immutable !== null && hasImmutableFlag(attrs) !== immutable) fail('IMMUTABLE_FLAG');
  return true;
}

export function hasImmutableFlag(attrs) {
  if (typeof attrs !== 'string') fail('IMMUTABLE_FLAG');
  const token = attrs.trim().split(/\s+/)[0] ?? '';
  return token.includes('i');
}

export function assertBootstrapPath(candidate) {
  if (candidate !== BOOTSTRAP_NODE || candidate.startsWith(FORBIDDEN_NVM_PREFIX)) fail('BOOTSTRAP_PATH');
  return true;
}

function run(executable, args, { code = 'TOOL_FAILED', encoding = null, env = undefined, cwd = undefined, maxBuffer = 16 * 1024 * 1024 } = {}) {
  const result = spawnSync(executable, args, { encoding, env, cwd, maxBuffer });
  if (result.error || result.status !== 0 || result.signal) fail(code);
  return result;
}

export function parseLddOutput(text) {
  const paths = new Set();
  for (const line of String(text).split('\n')) {
    const arrow = line.match(/=>\s+(\/[^\s]+)\s+/);
    if (arrow) paths.add(arrow[1]);
    else {
      const direct = line.trim().match(/^(\/[^\s]+)\s+/);
      if (direct) paths.add(direct[1]);
    }
  }
  return [...paths].sort();
}

export function closureDigest(entries) {
  if (!Array.isArray(entries) || entries.length === 0) fail('DYNAMIC_CLOSURE');
  const normalized = entries.map((entry) => {
    if (typeof entry?.path !== 'string' || !path.isAbsolute(entry.path) || !SHA64.test(entry.sha256)) fail('DYNAMIC_CLOSURE');
    return `${entry.path}|${entry.sha256}`;
  }).sort();
  if (new Set(normalized.map((entry) => entry.split('|')[0])).size !== normalized.length) fail('DYNAMIC_CLOSURE');
  return { count: normalized.length, sha256: sha256(Buffer.from(`${normalized.join('\n')}\n`)) };
}

async function readStableFile(filename, expected = {}) {
  const entryBefore = await lstat(filename, { bigint: true });
  validateRegularMetadata(entryBefore, { mode: expected.mode, uid: expected.uid ?? 0, gid: expected.gid ?? 0, code: expected.code ?? 'FILE_METADATA' });
  const handle = await open(filename, FS.O_RDONLY | FS.O_NOFOLLOW);
  try {
    const descriptorBefore = await handle.stat({ bigint: true });
    assertStableIdentity(entryBefore, descriptorBefore, expected.code ?? 'FILE_DRIFT');
    const bytes = await handle.readFile();
    const descriptorAfter = await handle.stat({ bigint: true });
    assertStableIdentity(descriptorBefore, descriptorAfter, expected.code ?? 'FILE_DRIFT');
    const entryAfter = await lstat(filename, { bigint: true });
    assertStableIdentity(descriptorAfter, entryAfter, expected.code ?? 'FILE_DRIFT');
    if (expected.sha256 && sha256(bytes) !== expected.sha256) fail(expected.code ?? 'FILE_HASH');
    return { bytes, metadata: identity(descriptorAfter), identitySha256: physicalIdentitySha256(descriptorAfter), sha256: sha256(bytes) };
  } finally {
    await handle.close();
  }
}

async function syncDirectory(directory) {
  const handle = await open(directory, FS.O_RDONLY | FS.O_DIRECTORY | FS.O_NOFOLLOW);
  try { await handle.sync(); } finally { await handle.close(); }
}

async function writeExclusive(filename, bytes, mode) {
  const handle = await open(filename, FS.O_WRONLY | FS.O_CREAT | FS.O_EXCL | FS.O_NOFOLLOW, mode);
  try {
    await handle.writeFile(bytes);
    await handle.chmod(mode);
    await handle.sync();
  } finally {
    await handle.close();
  }
}

export function classifyCreationState({ claim, final, staging, probe, renamedProbe }) {
  if (![claim, final, staging, probe, renamedProbe].every((value) => typeof value === 'boolean')) fail('CREATION_STATE');
  if (!claim && !final && !staging && !probe && !renamedProbe) return 'FRESH';
  if (claim && final && !staging && !probe && !renamedProbe) return 'VERIFY_EXACT_EXISTING';
  if (!claim) fail('UNCLAIMED_EXISTING_STATE');
  fail('CLAIM_CONSUMED_PARTIAL_STATE');
}

function git(args, options = {}) {
  return run(TOOL_PATHS.git, args, { code: 'GIT_AUTHORITY', encoding: 'utf8', ...options }).stdout.trim();
}

export function validateAuthorityPaths(paths) {
  if (!Array.isArray(paths) || paths.length !== AUTHORITY_PATHS.length) fail('AUTHORITY_PATHS');
  const sorted = [...paths].sort();
  const expected = [...AUTHORITY_PATHS].sort();
  for (let i = 0; i < expected.length; i += 1) if (sorted[i] !== expected[i]) fail('AUTHORITY_PATHS');
  return true;
}

async function readAuthority() {
  const commit = git(['rev-parse', 'HEAD']);
  const parent = git(['rev-parse', 'HEAD^']);
  const tree = git(['rev-parse', 'HEAD^{tree}']);
  const subject = git(['show', '-s', '--format=%s', 'HEAD']);
  if (!SHA40.test(commit) || parent !== AUTHORITY_PARENT || !SHA40.test(tree) || subject !== AUTHORITY_SUBJECT) fail('GIT_AUTHORITY');
  const changed = git(['diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD']).split('\n').filter(Boolean);
  validateAuthorityPaths(changed);
  if (git(['status', '--porcelain=v1', '-uall']) !== '') fail('GIT_AUTHORITY');
  const manifest = [];
  for (const authorityPath of AUTHORITY_PATHS) {
    const line = git(['ls-tree', 'HEAD', '--', authorityPath]);
    const match = line.match(/^(100644) blob ([a-f0-9]{40})\t(.+)$/);
    if (!match || match[3] !== authorityPath) fail('GIT_AUTHORITY');
    const bytes = run(TOOL_PATHS.git, ['cat-file', 'blob', `HEAD:${authorityPath}`], { code: 'GIT_AUTHORITY' }).stdout;
    if (gitBlobOid(bytes) !== match[2]) fail('GIT_AUTHORITY');
    manifest.push({ path: authorityPath, mode: match[1], blob_oid: match[2], sha256: sha256(bytes) });
  }
  const builder = manifest.find((entry) => entry.path === BUILDER_GIT_PATH);
  return {
    commit, parent, tree, subject, builder_blob_oid: builder.blob_oid,
    builder_sha256: builder.sha256,
    authority_manifest_sha256: sha256(Buffer.from(jsonBytes(manifest))),
  };
}

async function validateBuilderSnapshot(authority) {
  const expected = path.join(RUNTIME_ROOT, '.builders', authority.commit, path.basename(BUILDER_GIT_PATH));
  if (path.resolve(SCRIPT_PATH) !== expected) fail('BUILDER_SNAPSHOT');
  await validateParentChain(path.dirname(expected), '/root');
  const snapshot = await readStableFile(expected, { mode: 0o600, sha256: authority.builder_sha256, code: 'BUILDER_SNAPSHOT' });
  if (gitBlobOid(snapshot.bytes) !== authority.builder_blob_oid) fail('BUILDER_SNAPSHOT');
  return snapshot;
}

async function validateParentChain(filename, stop = '/') {
  let current = path.resolve(filename);
  const records = [];
  while (true) {
    const metadata = await lstat(current, { bigint: true });
    if (!metadata.isDirectory() || metadata.isSymbolicLink()) fail('PARENT_CHAIN');
    if (safeNumber(metadata.uid, 'PARENT_CHAIN') !== 0 || safeNumber(metadata.gid, 'PARENT_CHAIN') !== 0) fail('PARENT_CHAIN');
    if ((safeNumber(metadata.mode, 'PARENT_CHAIN') & 0o022) !== 0) fail('PARENT_CHAIN');
    records.push({ path: current, identity_sha256: physicalIdentitySha256(metadata) });
    if (current === stop) break;
    const next = path.dirname(current);
    if (next === current) fail('PARENT_CHAIN');
    current = next;
  }
  return records;
}

async function inspectTool(name, executable) {
  const file = await readStableFile(executable, { mode: 0o755, code: 'TOOL_IDENTITY' });
  const version = spawnSync(executable, ['--version'], { encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' } });
  const combined = `${version.stdout ?? ''}${version.stderr ?? ''}`.split('\n').slice(0, 2).join('\n');
  return { name, path: executable, path_sha256: sha256(Buffer.from(executable)), sha256: file.sha256, identity_sha256: file.identitySha256, version_sha256: sha256(Buffer.from(combined)) };
}

async function inspectClosure(executable) {
  const output = run(TOOL_PATHS.ldd, [executable], { code: 'DYNAMIC_CLOSURE', encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' } }).stdout;
  const paths = parseLddOutput(output);
  const entries = [];
  for (const library of paths) entries.push({ path: library, sha256: (await readStableFile(library, { mode: null, code: 'DYNAMIC_CLOSURE' })).sha256 });
  return closureDigest(entries);
}

async function inspectBootstrap() {
  assertBootstrapPath(BOOTSTRAP_NODE);
  if (path.resolve(BOOTSTRAP_NODE) !== BOOTSTRAP_NODE) fail('BOOTSTRAP_PATH');
  const parentChain = await validateParentChain(path.dirname(BOOTSTRAP_NODE));
  const file = await readStableFile(BOOTSTRAP_NODE, { mode: 0o755, sha256: BOOTSTRAP_SHA256, code: 'BOOTSTRAP_IDENTITY' });
  const version = run(BOOTSTRAP_NODE, ['--version'], { code: 'BOOTSTRAP_EXECUTION', encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' } }).stdout.trim();
  const versions = run(BOOTSTRAP_NODE, ['-e', 'const c=require("node:crypto");const x=Object.keys(process.versions).sort().map(k=>`${k}:${process.versions[k]}`).join("\\n")+"\\n";process.stdout.write(c.createHash("sha256").update(x).digest("hex"))'], { code: 'BOOTSTRAP_EXECUTION', encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' } }).stdout;
  const attrs = run(TOOL_PATHS.lsattr, ['-d', BOOTSTRAP_NODE], { code: 'BOOTSTRAP_IDENTITY', encoding: 'utf8' }).stdout;
  const closure = await inspectClosure(BOOTSTRAP_NODE);
  return { ...file, version, process_versions_sha256: versions, source_immutable: hasImmutableFlag(attrs), parent_chain_sha256: sha256(Buffer.from(jsonBytes(parentChain))), closure };
}

function attrsFor(filename) {
  return run(TOOL_PATHS.lsattr, ['-d', filename], { code: 'IMMUTABLE_FLAG', encoding: 'utf8' }).stdout;
}

function chattr(flag, filename, code = 'IMMUTABLE_CAPABILITY') {
  run(TOOL_PATHS.chattr, [flag, '--', filename], { code, env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' } });
}

export async function runCapabilityProbeSequence(adapter) {
  const required = ['create', 'setImmutable', 'readAttrs', 'openWrite', 'unlink', 'rename', 'clearImmutable', 'remove'];
  for (const name of required) if (typeof adapter?.[name] !== 'function') fail('IMMUTABLE_CAPABILITY');
  await adapter.create();
  await adapter.setImmutable();
  if (!hasImmutableFlag(await adapter.readAttrs())) fail('IMMUTABLE_CAPABILITY');
  for (const operation of [adapter.openWrite, adapter.unlink, adapter.rename]) {
    let rejected = false;
    try { await operation.call(adapter); } catch { rejected = true; }
    if (!rejected) fail('IMMUTABLE_CAPABILITY');
  }
  await adapter.clearImmutable();
  await adapter.remove();
  return { attempted: 1, immutable_set: true, write_rejected: true, unlink_rejected: true, rename_rejected: true, cleaned: true };
}

async function capabilityProbe(probePath) {
  if (await pathExists(probePath) || await pathExists(`${probePath}.renamed`)) fail('IMMUTABLE_CAPABILITY');
  return runCapabilityProbeSequence({
    create: () => writeExclusive(probePath, Buffer.from('immutable-capability-probe\n'), 0o555),
    setImmutable: () => chattr('+i', probePath),
    readAttrs: () => attrsFor(probePath),
    openWrite: async () => { const handle = await open(probePath, FS.O_WRONLY | FS.O_NOFOLLOW); await handle.close(); },
    unlink: () => unlink(probePath),
    rename: () => rename(probePath, `${probePath}.renamed`),
    clearImmutable: () => chattr('-i', probePath),
    remove: () => unlink(probePath),
  });
}

export function buildReceipt({ authority, bootstrap, capsule, closureAfter, probe, tools, timestamp }) {
  const receipt = {
    schema_version: 1,
    purpose: 'CI3_PRIVATE_IMMUTABLE_NODE_RUNTIME_CAPSULE_V1',
    architecture: ARCHITECTURE,
    runtime_authority_commit: authority.commit,
    runtime_authority_parent: authority.parent,
    runtime_authority_tree: authority.tree,
    runtime_authority_subject: authority.subject,
    authority_manifest_sha256: authority.authority_manifest_sha256,
    builder_blob_oid: authority.builder_blob_oid,
    builder_sha256: authority.builder_sha256,
    source_path: BOOTSTRAP_NODE,
    source_path_sha256: sha256(Buffer.from(BOOTSTRAP_NODE)),
    source_sha256: bootstrap.sha256,
    source_version: bootstrap.version,
    source_identity_sha256: bootstrap.identitySha256,
    source_parent_chain_sha256: bootstrap.parent_chain_sha256,
    source_process_versions_sha256: bootstrap.process_versions_sha256,
    source_immutable: false,
    source_role: 'bootstrap_only',
    capsule_generation_id: capsule.generationId,
    capsule_node_path_sha256: sha256(Buffer.from(capsule.nodePath)),
    capsule_node_sha256: capsule.sha256,
    capsule_node_identity_sha256: capsule.identitySha256,
    capsule_uid: 0,
    capsule_gid: 0,
    capsule_mode: '0555',
    capsule_nlink: 1,
    capsule_node_immutable: true,
    capsule_receipt_immutable: true,
    capsule_directory_immutable: true,
    chattr_sha256: tools.find((entry) => entry.name === 'chattr')?.sha256,
    lsattr_sha256: tools.find((entry) => entry.name === 'lsattr')?.sha256,
    filesystem_descriptor_sha256: capsule.filesystemDescriptorSha256,
    dynamic_closure_count: bootstrap.closure.count,
    dynamic_closure_sha256: bootstrap.closure.sha256,
    dynamic_closure_revalidated: closureAfter.count === bootstrap.closure.count && closureAfter.sha256 === bootstrap.closure.sha256,
    capability_probe: probe,
    tool_manifest_sha256: sha256(Buffer.from(jsonBytes(tools))),
    secrets_read: false,
    network_calls: 0,
    package_manager_write: false,
    system_node_modified: false,
    nvm_modified: false,
    raw_values_reported: false,
    created_at_utc: timestamp,
  };
  const keys = Object.keys(receipt);
  if (keys.length !== RECEIPT_KEYS.length || Object.values(receipt).some((value) => value === undefined)) fail('RECEIPT_SCHEMA');
  const sortedKeys = [...keys].sort();
  for (let index = 0; index < RECEIPT_KEYS.length; index += 1) if (sortedKeys[index] !== RECEIPT_KEYS[index]) fail('RECEIPT_SCHEMA');
  if (!receipt.dynamic_closure_revalidated) fail('DYNAMIC_CLOSURE_DRIFT');
  return Object.freeze(receipt);
}

export function validateReceipt(receipt, authoritySha) {
  if (!receipt || Object.keys(receipt).length !== RECEIPT_KEYS.length) fail('RECEIPT_SCHEMA');
  const actualKeys = Object.keys(receipt).sort();
  for (let index = 0; index < RECEIPT_KEYS.length; index += 1) if (actualKeys[index] !== RECEIPT_KEYS[index]) fail('RECEIPT_SCHEMA');
  if (receipt?.schema_version !== 1 || receipt?.purpose !== 'CI3_PRIVATE_IMMUTABLE_NODE_RUNTIME_CAPSULE_V1' || receipt?.architecture !== ARCHITECTURE) fail('RECEIPT_SCHEMA');
  if (receipt.runtime_authority_commit !== authoritySha || receipt.runtime_authority_parent !== AUTHORITY_PARENT || receipt.runtime_authority_subject !== AUTHORITY_SUBJECT) fail('RECEIPT_AUTHORITY');
  if (receipt.source_path !== BOOTSTRAP_NODE || receipt.source_sha256 !== BOOTSTRAP_SHA256 || receipt.source_immutable !== false || receipt.source_role !== 'bootstrap_only') fail('RECEIPT_SOURCE');
  if (receipt.capsule_uid !== 0 || receipt.capsule_gid !== 0 || receipt.capsule_mode !== '0555' || receipt.capsule_nlink !== 1) fail('RECEIPT_CAPSULE');
  if (![receipt.capsule_node_immutable, receipt.capsule_receipt_immutable, receipt.capsule_directory_immutable, receipt.dynamic_closure_revalidated].every((value) => value === true)) fail('RECEIPT_CAPSULE');
  if (receipt.secrets_read !== false || receipt.network_calls !== 0 || receipt.package_manager_write !== false || receipt.system_node_modified !== false || receipt.nvm_modified !== false || receipt.raw_values_reported !== false) fail('RECEIPT_POLICY');
  if (!Number.isSafeInteger(receipt.dynamic_closure_count) || receipt.dynamic_closure_count < 1 || !SHA64.test(receipt.dynamic_closure_sha256)) fail('RECEIPT_SCHEMA');
  if (!GENERATION.test(receipt.capsule_generation_id) || !SHA64.test(receipt.capsule_node_sha256) || !SHA64.test(receipt.capsule_node_identity_sha256)) fail('RECEIPT_SCHEMA');
  return true;
}

async function filesystemDescriptor(target) {
  const output = run(TOOL_PATHS.findmnt, ['-T', target, '-n', '-o', 'TARGET,FSTYPE,OPTIONS'], { code: 'FILESYSTEM', encoding: 'utf8' }).stdout.trim();
  return sha256(Buffer.from(output));
}

async function pathExists(filename) {
  try { await lstat(filename, { bigint: true }); return true; }
  catch (error) { if (error?.code === 'ENOENT') return false; throw error; }
}

function validateClaim(claim, authority, bootstrap, tools) {
  const expectedKeys = [
    'architecture', 'attempt', 'authority_manifest_sha256', 'builder_blob_oid',
    'builder_sha256', 'capability_probe_attempt', 'chattr_sha256',
    'lsattr_sha256', 'purpose', 'raw_values_reported', 'retry',
    'runtime_authority_commit', 'runtime_authority_parent',
    'runtime_authority_tree', 'schema_version', 'source_identity_sha256',
    'source_path_sha256', 'source_sha256',
  ].sort();
  if (!claim || Object.keys(claim).length !== expectedKeys.length) fail('ORIGINAL_CLAIM');
  const actual = Object.keys(claim).sort();
  for (let index = 0; index < expectedKeys.length; index += 1) if (actual[index] !== expectedKeys[index]) fail('ORIGINAL_CLAIM');
  if (claim.schema_version !== 1 || claim.purpose !== 'CI3_NODE_RUNTIME_CAPSULE_CREATION_CLAIM_V1' || claim.architecture !== ARCHITECTURE) fail('ORIGINAL_CLAIM');
  if (claim.runtime_authority_commit !== authority.commit || claim.runtime_authority_parent !== authority.parent || claim.runtime_authority_tree !== authority.tree || claim.authority_manifest_sha256 !== authority.authority_manifest_sha256) fail('ORIGINAL_CLAIM');
  if (claim.builder_blob_oid !== authority.builder_blob_oid || claim.builder_sha256 !== authority.builder_sha256) fail('ORIGINAL_CLAIM');
  if (claim.source_path_sha256 !== sha256(Buffer.from(BOOTSTRAP_NODE)) || claim.source_sha256 !== bootstrap.sha256 || claim.source_identity_sha256 !== bootstrap.identitySha256) fail('ORIGINAL_CLAIM');
  if (claim.chattr_sha256 !== tools.find((entry) => entry.name === 'chattr').sha256 || claim.lsattr_sha256 !== tools.find((entry) => entry.name === 'lsattr').sha256) fail('ORIGINAL_CLAIM');
  if (claim.attempt !== 1 || claim.capability_probe_attempt !== 1 || claim.retry !== false || claim.raw_values_reported !== false) fail('ORIGINAL_CLAIM');
  return true;
}

export function buildClaim({ authority, bootstrap, tools }) {
  return Object.freeze({
    schema_version: 1,
    purpose: 'CI3_NODE_RUNTIME_CAPSULE_CREATION_CLAIM_V1',
    architecture: ARCHITECTURE,
    runtime_authority_commit: authority.commit,
    runtime_authority_parent: authority.parent,
    runtime_authority_tree: authority.tree,
    authority_manifest_sha256: authority.authority_manifest_sha256,
    builder_blob_oid: authority.builder_blob_oid,
    builder_sha256: authority.builder_sha256,
    source_path_sha256: sha256(Buffer.from(BOOTSTRAP_NODE)),
    source_sha256: bootstrap.sha256,
    source_identity_sha256: bootstrap.identitySha256,
    chattr_sha256: tools.find((entry) => entry.name === 'chattr')?.sha256,
    lsattr_sha256: tools.find((entry) => entry.name === 'lsattr')?.sha256,
    attempt: 1,
    capability_probe_attempt: 1,
    retry: false,
    raw_values_reported: false,
  });
}

async function verifyPublished(authority, expectedReceiptSha = null, context = {}) {
  const authorityRoot = path.join(RUNTIME_ROOT, authority.commit);
  const finalPath = path.join(authorityRoot, BOOTSTRAP_SHA256);
  const nodePath = path.join(finalPath, 'node');
  const receiptPath = path.join(finalPath, 'runtime.receipt.json');
  const claimPath = path.join(RUNTIME_ROOT, `${authority.commit}.claim.json`);
  const claim = JSON.parse((await readStableFile(claimPath, { mode: 0o600, code: 'ORIGINAL_CLAIM' })).bytes.toString('utf8'));
  if (context.bootstrap && context.tools) validateClaim(claim, authority, context.bootstrap, context.tools);
  const entries = (await readdir(finalPath)).sort();
  if (entries.length !== 2 || entries[0] !== 'node' || entries[1] !== 'runtime.receipt.json') fail('CAPSULE_ENTRIES');
  const node = await readStableFile(nodePath, { mode: 0o555, sha256: BOOTSTRAP_SHA256, code: 'CAPSULE_NODE' });
  const receiptFile = await readStableFile(receiptPath, { mode: 0o444, sha256: expectedReceiptSha, code: 'CAPSULE_RECEIPT' });
  if (!hasImmutableFlag(attrsFor(nodePath)) || !hasImmutableFlag(attrsFor(receiptPath)) || !hasImmutableFlag(attrsFor(finalPath))) fail('IMMUTABLE_FLAG');
  validateDirectoryMetadata(await lstat(finalPath, { bigint: true }), { mode: 0o555, immutable: true, attrs: attrsFor(finalPath) });
  const receipt = JSON.parse(receiptFile.bytes.toString('utf8'));
  validateReceipt(receipt, authority.commit);
  if (receipt.runtime_authority_tree !== authority.tree || receipt.authority_manifest_sha256 !== authority.authority_manifest_sha256 || receipt.builder_blob_oid !== authority.builder_blob_oid || receipt.builder_sha256 !== authority.builder_sha256) fail('CAPSULE_BINDING');
  if (context.bootstrap) {
    if (receipt.source_version !== context.bootstrap.version || receipt.source_identity_sha256 !== context.bootstrap.identitySha256 || receipt.source_parent_chain_sha256 !== context.bootstrap.parent_chain_sha256 || receipt.source_process_versions_sha256 !== context.bootstrap.process_versions_sha256) fail('CAPSULE_BINDING');
    if (receipt.dynamic_closure_count !== context.bootstrap.closure.count || receipt.dynamic_closure_sha256 !== context.bootstrap.closure.sha256) fail('DYNAMIC_CLOSURE_DRIFT');
  }
  if (context.tools) {
    const chattrTool = context.tools.find((entry) => entry.name === 'chattr');
    const lsattrTool = context.tools.find((entry) => entry.name === 'lsattr');
    if (receipt.chattr_sha256 !== chattrTool.sha256 || receipt.lsattr_sha256 !== lsattrTool.sha256 || receipt.tool_manifest_sha256 !== sha256(Buffer.from(jsonBytes(context.tools)))) fail('TOOL_DRIFT');
  }
  if (receipt.capsule_node_path_sha256 !== sha256(Buffer.from(nodePath)) || receipt.filesystem_descriptor_sha256 !== await filesystemDescriptor(finalPath)) fail('CAPSULE_BINDING');
  if (receipt.capsule_node_identity_sha256 !== node.identitySha256 || receipt.capsule_node_sha256 !== node.sha256) fail('CAPSULE_BINDING');
  const closure = await inspectClosure(nodePath);
  if (closure.count !== receipt.dynamic_closure_count || closure.sha256 !== receipt.dynamic_closure_sha256) fail('DYNAMIC_CLOSURE_DRIFT');
  const version = run(nodePath, ['--version'], { code: 'CAPSULE_EXECUTION', encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' } }).stdout.trim();
  if (version !== receipt.source_version) fail('CAPSULE_EXECUTION');
  return { authorityRoot, finalPath, nodePath, receiptPath, receipt, receiptSha256: receiptFile.sha256, node };
}

async function createCapsule() {
  if (process.platform !== 'linux' || process.getuid?.() !== 0) fail('VPS_REQUIRED');
  const authority = await readAuthority();
  await validateBuilderSnapshot(authority);
  const bootstrapBefore = await inspectBootstrap();
  if (bootstrapBefore.source_immutable) fail('BOOTSTRAP_POLICY');
  const tools = [];
  for (const [name, executable] of Object.entries(TOOL_PATHS)) tools.push(await inspectTool(name, executable));
  await mkdir(RUNTIME_ROOT, { recursive: true, mode: 0o700 });
  await chmod(RUNTIME_ROOT, 0o700);
  await validateParentChain(RUNTIME_ROOT, '/root');
  const rootMetadata = await lstat(RUNTIME_ROOT, { bigint: true });
  validateDirectoryMetadata(rootMetadata, { mode: 0o700 });
  const claimPath = path.join(RUNTIME_ROOT, `${authority.commit}.claim.json`);
  const authorityRoot = path.join(RUNTIME_ROOT, authority.commit);
  const finalPath = path.join(authorityRoot, BOOTSTRAP_SHA256);
  const stagingPath = path.join(RUNTIME_ROOT, `.staging-${authority.commit}-${BOOTSTRAP_SHA256}`);
  const existence = {
    claim: await pathExists(claimPath), final: await pathExists(finalPath),
    staging: await pathExists(stagingPath),
    probe: await pathExists(path.join(RUNTIME_ROOT, `.immutable-probe-${authority.commit}`)),
    renamedProbe: await pathExists(path.join(RUNTIME_ROOT, `.immutable-probe-${authority.commit}.renamed`)),
  };
  const state = classifyCreationState(existence);
  if (state === 'VERIFY_EXACT_EXISTING') {
    const claim = JSON.parse((await readStableFile(claimPath, { mode: 0o600, code: 'ORIGINAL_CLAIM' })).bytes.toString('utf8'));
    validateClaim(claim, authority, bootstrapBefore, tools);
    const verified = await verifyPublished(authority, null, { bootstrap: bootstrapBefore, tools });
    process.stdout.write(`CREATE PASS status=EXISTS_VERIFIED authority_sha=${authority.commit} runtime_sha256=${verified.node.sha256} receipt_sha256=${verified.receiptSha256} identity_sha256=${verified.node.identitySha256} closure_count=${verified.receipt.dynamic_closure_count} closure_sha256=${verified.receipt.dynamic_closure_sha256}\n`);
    return;
  }
  if (await pathExists(authorityRoot)) fail('UNCLAIMED_EXISTING_STATE');
  const claim = buildClaim({ authority, bootstrap: bootstrapBefore, tools });
  await writeExclusive(claimPath, Buffer.from(jsonBytes(claim)), 0o600);
  await syncDirectory(RUNTIME_ROOT);
  const probe = await capabilityProbe(path.join(RUNTIME_ROOT, `.immutable-probe-${authority.commit}`));
  await mkdir(authorityRoot, { mode: 0o700 });
  await chmod(authorityRoot, 0o700);
  await mkdir(stagingPath, { mode: 0o700 });
  await chmod(stagingPath, 0o700);
  const nodePathStaging = path.join(stagingPath, 'node');
  await writeExclusive(nodePathStaging, bootstrapBefore.bytes, 0o555);
  const stagedNode = await readStableFile(nodePathStaging, { mode: 0o555, sha256: BOOTSTRAP_SHA256, code: 'CAPSULE_COPY' });
  if (!bootstrapBefore.bytes.equals(stagedNode.bytes)) fail('CAPSULE_COPY');
  const cleanEnv = { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' };
  const stagedVersion = run(nodePathStaging, ['--version'], { code: 'CAPSULE_EXECUTION', encoding: 'utf8', env: cleanEnv }).stdout.trim();
  if (stagedVersion !== bootstrapBefore.version) fail('CAPSULE_EXECUTION');
  run(nodePathStaging, ['-e', 'for(const m of ["node:assert","node:crypto","node:fs","node:path"]){require(m)}'], { code: 'CAPSULE_CORE_SMOKE', env: cleanEnv });
  const syntaxProbe = path.join(stagingPath, '.synthetic-generator.mjs');
  await writeExclusive(syntaxProbe, Buffer.from('import { createHash } from "node:crypto";\nexport const ok = createHash("sha256").update("ci3").digest("hex");\n'), 0o600);
  run(nodePathStaging, ['--check', syntaxProbe], { code: 'CAPSULE_SYNTAX_SMOKE', env: cleanEnv });
  await unlink(syntaxProbe);
  const closureAfter = await inspectClosure(nodePathStaging);
  const capsule = {
    generationId: `node-${BOOTSTRAP_SHA256}`,
    nodePath: path.join(finalPath, 'node'),
    sha256: stagedNode.sha256,
    identitySha256: stagedNode.identitySha256,
    filesystemDescriptorSha256: await filesystemDescriptor(stagingPath),
  };
  const receipt = buildReceipt({ authority, bootstrap: bootstrapBefore, capsule, closureAfter, probe, tools, timestamp: new Date().toISOString() });
  const receiptBytes = Buffer.from(jsonBytes(receipt));
  const receiptPathStaging = path.join(stagingPath, 'runtime.receipt.json');
  await writeExclusive(receiptPathStaging, receiptBytes, 0o444);
  await syncDirectory(stagingPath);
  await mkdir(finalPath, { mode: 0o700 });
  await chmod(finalPath, 0o700);
  await (await import('node:fs/promises')).link(nodePathStaging, path.join(finalPath, 'node'));
  await unlink(nodePathStaging);
  await (await import('node:fs/promises')).link(receiptPathStaging, path.join(finalPath, 'runtime.receipt.json'));
  await unlink(receiptPathStaging);
  await rmdir(stagingPath);
  chattr('+i', path.join(finalPath, 'node'), 'CAPSULE_IMMUTABLE');
  chattr('+i', path.join(finalPath, 'runtime.receipt.json'), 'CAPSULE_IMMUTABLE');
  await chmod(finalPath, 0o555);
  chattr('+i', finalPath, 'CAPSULE_IMMUTABLE');
  await syncDirectory(authorityRoot);
  const verified = await verifyPublished(authority, sha256(receiptBytes), { bootstrap: bootstrapBefore, tools });
  const toolsAfter = [];
  for (const [name, executable] of Object.entries(TOOL_PATHS)) toolsAfter.push(await inspectTool(name, executable));
  if (sha256(Buffer.from(jsonBytes(toolsAfter))) !== sha256(Buffer.from(jsonBytes(tools)))) fail('TOOL_DRIFT');
  const bootstrapAfter = await inspectBootstrap();
  assertStableIdentity(bootstrapBefore.metadata, bootstrapAfter.metadata, 'BOOTSTRAP_DRIFT');
  if (bootstrapAfter.sha256 !== bootstrapBefore.sha256 || bootstrapAfter.closure.sha256 !== bootstrapBefore.closure.sha256) fail('BOOTSTRAP_DRIFT');
  process.stdout.write(`CREATE PASS status=CREATED authority_sha=${authority.commit} runtime_sha256=${verified.node.sha256} receipt_sha256=${verified.receiptSha256} identity_sha256=${verified.node.identitySha256} closure_count=${verified.receipt.dynamic_closure_count} closure_sha256=${verified.receipt.dynamic_closure_sha256}\n`);
}

async function verifyCapsule() {
  if (process.platform !== 'linux' || process.getuid?.() !== 0) fail('VPS_REQUIRED');
  const authority = await readAuthority();
  await validateBuilderSnapshot(authority);
  const before = await inspectBootstrap();
  const tools = [];
  for (const [name, executable] of Object.entries(TOOL_PATHS)) tools.push(await inspectTool(name, executable));
  const verified = await verifyPublished(authority, null, { bootstrap: before, tools });
  const after = await inspectBootstrap();
  assertStableIdentity(before.metadata, after.metadata, 'BOOTSTRAP_DRIFT');
  if (before.sha256 !== after.sha256 || before.closure.sha256 !== after.closure.sha256) fail('BOOTSTRAP_DRIFT');
  process.stdout.write(`VERIFY PASS authority_sha=${authority.commit} runtime_sha256=${verified.node.sha256} receipt_sha256=${verified.receiptSha256} identity_sha256=${verified.node.identitySha256} closure_count=${verified.receipt.dynamic_closure_count} closure_sha256=${verified.receipt.dynamic_closure_sha256}\n`);
}

async function selfTest() {
  let tests = 0;
  if (parseMode(['--self-test']) !== 'self-test') fail('SELF_TEST'); tests += 1;
  if (sha256(Buffer.from('abc')).length !== 64) fail('SELF_TEST'); tests += 1;
  if (!hasImmutableFlag('----i---------e------- synthetic')) fail('SELF_TEST'); tests += 1;
  if (hasImmutableFlag('--------------e------- synthetic')) fail('SELF_TEST'); tests += 1;
  if (parseLddOutput('libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x0)\n/lib64/ld-linux-x86-64.so.2 (0x0)\n').length !== 2) fail('SELF_TEST'); tests += 1;
  if (sanitizeError(new CapsuleError('SELF_TEST')) !== 'ERROR SELF_TEST') fail('SELF_TEST'); tests += 1;
  if (!validateAuthorityPaths([...AUTHORITY_PATHS])) fail('SELF_TEST'); tests += 1;
  if (!validateReceipt(buildReceipt({
    authority: { commit: 'a'.repeat(40), parent: AUTHORITY_PARENT, tree: 'b'.repeat(40), subject: AUTHORITY_SUBJECT, authority_manifest_sha256: 'c'.repeat(64), builder_blob_oid: 'd'.repeat(40), builder_sha256: 'e'.repeat(64) },
    bootstrap: { sha256: BOOTSTRAP_SHA256, version: 'v20.20.2', identitySha256: 'f'.repeat(64), parent_chain_sha256: '1'.repeat(64), process_versions_sha256: '2'.repeat(64), closure: { count: 1, sha256: '3'.repeat(64) } },
    capsule: { generationId: `node-${BOOTSTRAP_SHA256}`, nodePath: `/synthetic/${BOOTSTRAP_SHA256}/node`, sha256: BOOTSTRAP_SHA256, identitySha256: '4'.repeat(64), filesystemDescriptorSha256: '5'.repeat(64) },
    closureAfter: { count: 1, sha256: '3'.repeat(64) }, probe: { attempted: 1 }, tools: [{ name: 'chattr', sha256: '6'.repeat(64) }, { name: 'lsattr', sha256: '7'.repeat(64) }], timestamp: '2099-01-01T00:00:00.000Z',
  }), 'a'.repeat(40))) fail('SELF_TEST'); tests += 1;
  process.stdout.write(`SELF_TEST PASS tests=${tests} network_calls=0 secrets_read=0 system_node_modified=0 nvm_modified=0\n`);
}

async function main() {
  try {
    const mode = parseMode(process.argv.slice(2));
    if (mode === 'self-test') await selfTest();
    else if (mode === 'create') await createCapsule();
    else await verifyCapsule();
  } catch (error) {
    process.stderr.write(`${sanitizeError(error)}\n`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === SCRIPT_PATH) await main();
