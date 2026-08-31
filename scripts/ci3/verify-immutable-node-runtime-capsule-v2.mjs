import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const ARCHITECTURE = 'READ_ONLY_NODE_RUNTIME_CAPSULE_V2_ADOPTION_VERIFIER_V1';
export const BASELINE = Object.freeze({
  loader_entry_count: 7,
  traverses_any_symlink_count: 7,
  traverses_zero_symlink_count: 0,
  final_component_symlink_count: 2,
  final_component_regular_count: 5,
  intermediate_only_symlink_count: 5,
  total_symlink_hops: 9,
  max_symlink_hops: 2,
  canonical_regular_target_count: 7,
  duplicate_loader_path_count: 0,
  duplicate_canonical_identity_count: 0,
  closure_path_list_sha256: '3f971424eee62e6754e5a82b7b5263fd0da4c76b2c5d7decd600f6b38e3da1cd',
  closure_manifest_sha256: '0ea781ac6ad63e50a38756f6e9b61978b91d81a6599f65007a9d0bea0e4f2210',
  closure_content_set_sha256: 'cd118bd931b067611e20fe85400a94b8668ef3773d12c2802cb5cc0cb391d9da',
});

export const EXPECTED = Object.freeze({
  terminalStop: '030aa2be4e2facc5edbcda143c18a8477e727855',
  creationAuthority: 'b08e6326fbd22c96b852ccfe53abdeb254e54bd1',
  creationAuthorityParent: 'bd2ffd96e3742474ed0126845f5e6192f3bacb01',
  creationAuthorityTree: 'b2dc6892cbaa3594cdfd206baf773bcad28278e7',
  oldBuilderBlob: '944f054dea143b766d3b148b91b577bd5b372c7e',
  oldBuilderSha256: 'f7eba34fc042a8e25406e465d94f4b6c45e88072b7a1fb313215fb7e32471043',
  creationClaimSha256: '277d493efa3165d1b65a60bc8b7c925a2a744dab5ee6b456cd1d761896762f6e',
  closureCaptureSha256: '56b666bd561deb7febbd92338d453c10b4c54be37bcc38c2fb400cfe4d2a8cc7',
  probeReceiptSha256: 'fe685e60d53a1d44f966c0374628fc8acc936f24794b2309b04106e6c8b08d7d',
  runtimeReceiptSha256: '577fff150c608bfa848c7e9775e92cd02ed427a83484e859480b3e2607a94744',
  nodeSha256: '6295488653f0d93b0a157841746fef7e72cc4328cfb60c4bbe0ca2668a836ffd',
  verifierSubject: 'build(ops): authorize read-only adoption of Node capsule V2',
});

const BOOTSTRAP = '/usr/bin/node';
const READ_ATTRS = '/usr/bin/lsattr';
const GIT = '/usr/bin/git';
const RUNTIME_ROOT = '/root/.config/agentempp/runtimes/node';
const ADOPTION_ROOT = path.join(RUNTIME_ROOT, 'adoptions');
const VERIFIER_REL = 'scripts/ci3/verify-immutable-node-runtime-capsule-v2.mjs';
const SCRIPT_PATH = fileURLToPath(import.meta.url);
const F = fs.constants;
const MAX_PATH_BYTES = 4096;
const MAX_FILE_BYTES = 256 * 1024 * 1024;
const MAX_JSON_BYTES = 16 * 1024 * 1024;
const MAX_HOPS = 40;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA64 = /^[0-9a-f]{64}$/;
const INTERNAL_PHASE = 'CI3_NODE_CAPSULE_ADOPTION_INTERNAL_PHASE';
const INTERNAL_CLAIM = 'CI3_NODE_CAPSULE_ADOPTION_CLAIM_SHA256';

const AUTHORITY_PATHS = Object.freeze([
  'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md',
  'docs/superpowers/evidence/2026-08-31-ci3-node-runtime-v2-readonly-adoption-authority.md',
  'docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md',
  VERIFIER_REL,
  'scripts/ci3/verify-immutable-node-runtime-capsule-v2.test.mjs',
]);

export class VerifierError extends Error {
  constructor(code) { super(code); this.code = code; }
}

const fail = (code) => { throw new VerifierError(code); };
export const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
export const gitBlobOid = (bytes) => {
  const value = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
  return crypto.createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${value.length}\0`), value])).digest('hex');
};
const jsonBytes = (value) => Buffer.from(`${JSON.stringify(value, null, 2)}\n`);

export function sanitizeError(error) {
  const code = typeof error?.code === 'string' && /^[A-Z0-9_]+$/.test(error.code) ? error.code : 'UNEXPECTED';
  return `ERROR ${code}`;
}

export function parseMode(argv) {
  if (!Array.isArray(argv) || argv.length !== 1 || !['--self-test', '--verify-existing'].includes(argv[0])) fail('ARGV');
  return argv[0].slice(2);
}

const toBig = (value) => {
  if (typeof value === 'bigint') return value;
  if (typeof value === 'string' && /^\d+$/.test(value)) return BigInt(value);
  fail('IDENTITY');
};

const identityText = (stat) => [
  stat.uid, stat.gid, stat.mode, stat.nlink, stat.size,
  stat.mtimeNs, stat.ctimeNs, stat.dev, stat.ino,
].map(toBig).join(';');

export const physicalIdentitySha256 = (stat) => sha256(identityText(stat));
const sameIdentity = (left, right, code = 'IDENTITY_DRIFT') => {
  if (identityText(left) !== identityText(right)) fail(code);
};
const safeNumber = (value) => {
  const big = toBig(value);
  const number = Number(big);
  if (!Number.isSafeInteger(number) || BigInt(number) !== big) fail('IDENTITY');
  return number;
};

export function validateSafeAbsolutePath(value) {
  if (typeof value !== 'string' || !value.startsWith('/') || value === '/' || value.endsWith('/') ||
      value.includes('\0') || Buffer.byteLength(value) > MAX_PATH_BYTES) fail('SAFE_PATH');
  const parts = value.slice(1).split('/');
  if (!parts.length || parts.some((part) => !part || part === '.' || part === '..')) fail('SAFE_PATH');
  return parts;
}

export function normalizeSymlinkTarget(base, target) {
  if (!Array.isArray(base) || typeof target !== 'string' || !target || target.includes('\0') ||
      Buffer.byteLength(target) > MAX_PATH_BYTES) fail('CLOSURE_CANONICALIZATION');
  const output = target.startsWith('/') ? [] : [...base];
  for (const part of target.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') {
      if (!output.length) fail('CLOSURE_CANONICALIZATION');
      output.pop();
    } else output.push(part);
  }
  if (!output.length) fail('CLOSURE_CANONICALIZATION');
  return output;
}

export function correctedCapabilityProjection(probe) {
  validateCapabilityProbe(probe);
  const { schema_version: _schema, authority: _authority, ...result } = probe;
  return result;
}

export function validateCapabilityProbe(probe) {
  const keys = ['attempted', 'authority', 'immutable_set', 'rename_rejected', 'schema_version', 'unlink_rejected', 'write_rejected'].sort();
  if (!probe || JSON.stringify(Object.keys(probe).sort()) !== JSON.stringify(keys) ||
      probe.schema_version !== 2 || probe.authority !== EXPECTED.creationAuthority || probe.attempted !== 1 ||
      probe.immutable_set !== true || probe.write_rejected !== true ||
      probe.unlink_rejected !== true || probe.rename_rejected !== true) fail('CAPABILITY_PROBE');
  return true;
}

function assertBaseline(value, code = 'CLOSURE_BASELINE') {
  for (const [key, expected] of Object.entries(BASELINE)) {
    if (value?.[key] !== expected) fail(code);
  }
}

export function validateClosureCaptureShape(capture) {
  if (!capture || capture.schema_version !== 2 || capture.authority !== EXPECTED.creationAuthority ||
      capture.claim_sha256 !== EXPECTED.creationClaimSha256 ||
      capture.closure_algorithm !== 'NOFOLLOW_COMPONENT_CANONICALIZATION_V1' ||
      capture.raw_values_reported !== false || capture.secrets_read !== false ||
      typeof capture.created_at_utc !== 'string' || !Array.isArray(capture.entries) || capture.entries.length !== 7) fail('CAPTURE_SCHEMA');
  assertBaseline(capture, 'CAPTURE_BASELINE');
  const original = new Set();
  for (const entry of capture.entries) {
    validateSafeAbsolutePath(entry?.original_loader_path);
    validateSafeAbsolutePath(entry?.canonical_path);
    if (!SHA64.test(entry?.original_loader_path_sha256) || !SHA64.test(entry?.canonical_path_sha256) || original.has(entry.original_loader_path)) fail('CAPTURE_ENTRY');
    original.add(entry.original_loader_path);
  }
  return true;
}

export function validateArtifactDocumentChain({ claim, claimSha256, capture, captureSha256, probe, probeSha256 }) {
  if (claimSha256 !== EXPECTED.creationClaimSha256 || captureSha256 !== EXPECTED.closureCaptureSha256 ||
      probeSha256 !== EXPECTED.probeReceiptSha256 || claim?.authority !== EXPECTED.creationAuthority ||
      claim?.attempt !== 1 || claim?.retry !== false) fail('ARTIFACT_CHAIN');
  validateClosureCaptureShape(capture);
  validateCapabilityProbe(probe);
  return true;
}

export function validateRuntimeReceiptBinding(receipt) {
  if (!receipt || receipt.runtime_authority_commit !== EXPECTED.creationAuthority ||
      receipt.builder_blob_oid !== EXPECTED.oldBuilderBlob || receipt.builder_sha256 !== EXPECTED.oldBuilderSha256 ||
      receipt.closure_claim_sha256 !== EXPECTED.creationClaimSha256 ||
      receipt.closure_capture_sha256 !== EXPECTED.closureCaptureSha256 ||
      receipt.capsule_node_sha256 !== EXPECTED.nodeSha256 ||
      JSON.stringify(receipt.capability_probe) !== JSON.stringify(correctedCapabilityProjection({
        schema_version: 2, authority: EXPECTED.creationAuthority, ...receipt.capability_probe,
      }))) fail('RUNTIME_RECEIPT_BINDING');
  assertBaseline(receipt, 'RUNTIME_RECEIPT_BASELINE');
  for (const key of ['dynamic_closure_revalidated', 'source_and_capsule_closure_match', 'capsule_node_immutable', 'capsule_receipt_immutable', 'capsule_directory_immutable']) {
    if (receipt[key] !== true) fail('RUNTIME_RECEIPT_POLICY');
  }
  for (const key of ['secrets_read', 'system_node_modified', 'nvm_modified', 'raw_paths_reported', 'raw_values_reported']) {
    if (receipt[key] !== false) fail('RUNTIME_RECEIPT_POLICY');
  }
  if (receipt.network_calls !== 0) fail('RUNTIME_RECEIPT_POLICY');
  return true;
}

function validateAuthority(authority) {
  if (!authority || !SHA40.test(authority.commit) || authority.parent !== EXPECTED.terminalStop ||
      !SHA40.test(authority.tree) || authority.subject !== EXPECTED.verifierSubject ||
      !SHA40.test(authority.verifierBlob) || !SHA64.test(authority.verifierSha256)) fail('VERIFIER_AUTHORITY');
  return true;
}

export function buildAdoptionClaim(authority) {
  validateAuthority(authority);
  return {
    schema_version: 1,
    purpose: 'CI3_NODE_RUNTIME_CAPSULE_V2_READ_ONLY_ADOPTION_CLAIM',
    architecture: ARCHITECTURE,
    verifier_authority_commit: authority.commit,
    verifier_authority_parent: authority.parent,
    verifier_authority_tree: authority.tree,
    verifier_authority_subject: authority.subject,
    verifier_blob_oid: authority.verifierBlob,
    verifier_sha256: authority.verifierSha256,
    creation_authority_commit: EXPECTED.creationAuthority,
    old_builder_blob_oid: EXPECTED.oldBuilderBlob,
    old_builder_sha256: EXPECTED.oldBuilderSha256,
    terminal_stop_commit: EXPECTED.terminalStop,
    expected_runtime_receipt_sha256: EXPECTED.runtimeReceiptSha256,
    expected_node_sha256: EXPECTED.nodeSha256,
    attempt: 1,
    retry: false,
    create: false,
    ldd: false,
    probe: false,
    chattr: false,
    capsule_mutation: false,
    raw_paths_reported: false,
    raw_values_reported: false,
  };
}

const ADOPTION_RECEIPT_KEYS = Object.freeze([
  'adoption_attempt','adoption_claim_sha256','adoption_retry','architecture','bootstrap_verify_pass',
  'canonical_regular_target_count','capability_probe_receipt_identity_sha256','capability_probe_receipt_sha256',
  'capsule_directory_identity_sha256','capsule_mutation','capsule_node_identity_sha256','capsule_node_sha256',
  'capsule_self_hosted_verify_pass','chattr','closure_capture_identity_sha256','closure_capture_sha256',
  'closure_content_set_sha256','closure_manifest_sha256','closure_path_list_sha256','core_module_smoke_sha256',
  'create','created_at_utc','creation_authority_commit','creation_claim_identity_sha256','creation_claim_sha256',
  'duplicate_canonical_identity_count','duplicate_loader_path_count','final_component_regular_count',
  'final_component_symlink_count','immutable_flags','intermediate_only_symlink_count','ldd','loader_entry_count',
  'max_symlink_hops','network_calls','nvm_unchanged','old_builder_blob_oid','old_builder_sha256',
  'package_manager_calls','probe','purpose','raw_paths_reported','raw_values_reported','result',
  'runtime_receipt_identity_sha256','runtime_receipt_sha256','schema_version','secret_input_opens',
  'source_capsule_bytes_equal','source_node_identity_sha256','system_node_unchanged','terminal_stop_commit',
  'total_symlink_hops','traverses_any_symlink_count','traverses_zero_symlink_count','verifier_authority_commit',
  'verifier_authority_parent','verifier_authority_subject','verifier_authority_tree','verifier_blob_oid',
  'verifier_sha256','node_version_sha256',
].sort());

export function validateAdoptionReceipt(receipt, claim, authority) {
  validateAuthority(authority);
  if (!receipt || JSON.stringify(Object.keys(receipt).sort()) !== JSON.stringify(ADOPTION_RECEIPT_KEYS) ||
      receipt.schema_version !== 1 || receipt.purpose !== 'CI3_NODE_RUNTIME_CAPSULE_V2_READ_ONLY_ADOPTION_RECEIPT' ||
      receipt.architecture !== ARCHITECTURE || receipt.result !== 'PASS' ||
      receipt.verifier_authority_commit !== authority.commit || receipt.verifier_authority_parent !== authority.parent ||
      receipt.verifier_authority_tree !== authority.tree || receipt.verifier_authority_subject !== authority.subject ||
      receipt.verifier_blob_oid !== authority.verifierBlob || receipt.verifier_sha256 !== authority.verifierSha256 ||
      receipt.creation_authority_commit !== EXPECTED.creationAuthority || receipt.old_builder_blob_oid !== EXPECTED.oldBuilderBlob ||
      receipt.old_builder_sha256 !== EXPECTED.oldBuilderSha256 || receipt.terminal_stop_commit !== EXPECTED.terminalStop ||
      receipt.adoption_claim_sha256 !== sha256(jsonBytes(claim)) ||
      receipt.creation_claim_sha256 !== EXPECTED.creationClaimSha256 ||
      receipt.closure_capture_sha256 !== EXPECTED.closureCaptureSha256 ||
      receipt.capability_probe_receipt_sha256 !== EXPECTED.probeReceiptSha256 ||
      receipt.runtime_receipt_sha256 !== EXPECTED.runtimeReceiptSha256 ||
      receipt.capsule_node_sha256 !== EXPECTED.nodeSha256 || receipt.adoption_attempt !== 1 ||
      receipt.adoption_retry !== false || typeof receipt.created_at_utc !== 'string') fail('ADOPTION_RECEIPT');
  assertBaseline(receipt, 'ADOPTION_RECEIPT_BASELINE');
  for (const key of ['creation_claim_identity_sha256','closure_capture_identity_sha256','capability_probe_receipt_identity_sha256','runtime_receipt_identity_sha256','capsule_node_identity_sha256','capsule_directory_identity_sha256','source_node_identity_sha256','node_version_sha256','core_module_smoke_sha256']) {
    if (!SHA64.test(receipt[key])) fail('ADOPTION_RECEIPT');
  }
  if (!receipt.immutable_flags || JSON.stringify(Object.keys(receipt.immutable_flags).sort()) !== JSON.stringify(['directory','node','receipt']) || Object.values(receipt.immutable_flags).some((value) => value !== true)) fail('ADOPTION_RECEIPT');
  for (const key of ['source_capsule_bytes_equal','bootstrap_verify_pass','capsule_self_hosted_verify_pass','system_node_unchanged','nvm_unchanged']) {
    if (receipt[key] !== true) fail('ADOPTION_RECEIPT');
  }
  for (const key of ['create','ldd','probe','chattr','capsule_mutation','raw_paths_reported','raw_values_reported']) {
    if (receipt[key] !== false) fail('ADOPTION_RECEIPT');
  }
  for (const key of ['network_calls','package_manager_calls','secret_input_opens']) {
    if (receipt[key] !== 0) fail('ADOPTION_RECEIPT');
  }
  return true;
}

function requireRootRegular(stat, mode, code) {
  if (!stat.isFile() || stat.isSymbolicLink() || stat.uid !== 0n || stat.gid !== 0n ||
      (stat.mode & 0o777n) !== BigInt(mode) || stat.nlink !== 1n) fail(code);
}

function requireTrustedDirectory(stat, mode = null, code = 'TRUSTED_DIRECTORY') {
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== 0n || stat.gid !== 0n ||
      (stat.mode & 0o022n) !== 0n || (mode !== null && (stat.mode & 0o777n) !== BigInt(mode))) fail(code);
}

function openReadNoFollow(file, { mode = null, maxBytes = MAX_JSON_BYTES, code = 'ARTIFACT' } = {}) {
  const first = fs.lstatSync(file, { bigint: true });
  if (mode !== null) requireRootRegular(first, mode, code);
  else if (!first.isFile() || first.isSymbolicLink() || first.uid !== 0n || first.gid !== 0n || first.nlink !== 1n) fail(code);
  if (first.size > BigInt(maxBytes)) fail(code);
  const fd = fs.openSync(file, F.O_RDONLY | F.O_NOFOLLOW);
  try {
    const before = fs.fstatSync(fd, { bigint: true });
    sameIdentity(first, before, code);
    const bytes = fs.readFileSync(fd);
    const after = fs.fstatSync(fd, { bigint: true });
    sameIdentity(before, after, code);
    if (BigInt(bytes.length) !== after.size) fail(code);
    sameIdentity(after, fs.lstatSync(file, { bigint: true }), code);
    return { bytes, stat: after, sha256: sha256(bytes), identitySha256: physicalIdentitySha256(after) };
  } finally { fs.closeSync(fd); }
}

function readJsonNoFollow(file, options) {
  const result = openReadNoFollow(file, options);
  try { return { ...result, value: JSON.parse(result.bytes.toString('utf8')) }; }
  catch { fail('JSON_ARTIFACT'); }
}

function realClosureAdapter() {
  return {
    lstat: (file) => fs.lstatSync(file, { bigint: true }),
    readlink: (file) => fs.readlinkSync(file, 'utf8'),
    open(file) { return openReadNoFollow(file, { maxBytes: MAX_FILE_BYTES, code: 'CLOSURE_CANONICALIZATION' }); },
  };
}

function resolveClosureEntryNoFollow(loaderPath, adapter = realClosureAdapter()) {
  let pending = validateSafeAbsolutePath(loaderPath);
  let resolved = [];
  let hops = 0;
  let finalLink = false;
  const seen = new Set();
  const records = [];
  const links = [];
  const parents = [];
  while (pending.length) {
    const component = pending.shift();
    const candidate = `/${[...resolved, component].join('/')}`;
    let before;
    try { before = adapter.lstat(candidate); } catch { fail('CLOSURE_CANONICALIZATION'); }
    if (before.uid !== 0n || before.gid !== 0n) fail('CLOSURE_CANONICALIZATION');
    if (before.isSymbolicLink()) {
      if (before.nlink !== 1n) fail('CLOSURE_CANONICALIZATION');
      if (pending.length === 0) finalLink = true;
      let target1; let target2; let after;
      try { target1 = adapter.readlink(candidate); after = adapter.lstat(candidate); target2 = adapter.readlink(candidate); }
      catch { fail('CLOSURE_CANONICALIZATION'); }
      sameIdentity(before, after, 'CLOSURE_CANONICALIZATION');
      if (target1 !== target2 || ++hops > MAX_HOPS) fail('CLOSURE_CANONICALIZATION');
      const cycle = `${before.dev};${before.ino};${sha256(target1)}`;
      if (seen.has(cycle)) fail('CLOSURE_CANONICALIZATION');
      seen.add(cycle);
      records.push({ kind: 'link', path: candidate, identity: identityText(before), target: target1 });
      links.push([sha256(candidate), sha256(target1), physicalIdentitySha256(before)]);
      pending = [...normalizeSymlinkTarget(resolved, target1), ...pending];
      resolved = [];
      continue;
    }
    if (pending.length) {
      requireTrustedDirectory(before, null, 'CLOSURE_CANONICALIZATION');
      records.push({ kind: 'dir', path: candidate, identity: identityText(before) });
      parents.push([sha256(candidate), physicalIdentitySha256(before)]);
      resolved.push(component);
      continue;
    }
    if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1n || (before.mode & 0o022n) !== 0n) fail('CLOSURE_CANONICALIZATION');
    const opened = adapter.open(candidate);
    sameIdentity(before, opened.stat, 'CLOSURE_CANONICALIZATION');
    for (const record of records) {
      const current = adapter.lstat(record.path);
      if (identityText(current) !== record.identity || (record.kind === 'link' && adapter.readlink(record.path) !== record.target)) fail('CLOSURE_CANONICALIZATION');
    }
    const identityKey = `${opened.stat.dev}:${opened.stat.ino}`;
    const compatibility = {
      original: sha256(loaderPath), canonical: sha256(candidate), classification: hops ? 'symlink' : 'direct', hops,
      links: sha256(JSON.stringify(links)), parents: sha256(JSON.stringify(parents)), content: opened.sha256,
      identity: opened.identitySha256,
    };
    return {
      original_loader_path: loaderPath,
      original_loader_path_sha256: sha256(loaderPath),
      canonical_path: candidate,
      canonical_path_sha256: sha256(candidate),
      traverses_any_symlink: hops > 0,
      traverses_zero_symlink: hops === 0,
      final_component_symlink: finalLink,
      final_component_regular: !finalLink,
      intermediate_only_symlink: hops > 0 && !finalLink,
      symlink_hop_count: hops,
      ordered_symlink_chain: links,
      symlink_chain_sha256: sha256(JSON.stringify(links)),
      parent_chain: parents,
      parent_chain_sha256: sha256(JSON.stringify(parents)),
      canonical_content_sha256: opened.sha256,
      canonical_identity_sha256: opened.identitySha256,
      canonical_identity_key: identityKey,
      bytes: safeNumber(opened.stat.size),
      mode: (safeNumber(opened.stat.mode) & 0o777).toString(8).padStart(4, '0'),
      uid: safeNumber(opened.stat.uid), gid: safeNumber(opened.stat.gid), nlink: safeNumber(opened.stat.nlink),
      algorithm: 'NOFOLLOW_COMPONENT_CANONICALIZATION_V1', compatibility_projection: compatibility,
    };
  }
  fail('CLOSURE_CANONICALIZATION');
}

function revalidateCapture(capture) {
  validateClosureCaptureShape(capture);
  const rebuilt = capture.entries.map((entry) => resolveClosureEntryNoFollow(entry.original_loader_path));
  if (JSON.stringify(capture.entries) !== JSON.stringify(rebuilt)) fail('CAPTURE_DRIFT');
  const compatibility = rebuilt.map((entry) => entry.compatibility_projection).sort((a, b) => a.original.localeCompare(b.original));
  const ids = rebuilt.map((entry) => entry.canonical_identity_key);
  const projection = {
    loader_entry_count: rebuilt.length,
    traverses_any_symlink_count: rebuilt.filter((entry) => entry.traverses_any_symlink).length,
    traverses_zero_symlink_count: rebuilt.filter((entry) => entry.traverses_zero_symlink).length,
    final_component_symlink_count: rebuilt.filter((entry) => entry.final_component_symlink).length,
    final_component_regular_count: rebuilt.filter((entry) => entry.final_component_regular).length,
    intermediate_only_symlink_count: rebuilt.filter((entry) => entry.intermediate_only_symlink).length,
    total_symlink_hops: rebuilt.reduce((sum, entry) => sum + entry.symlink_hop_count, 0),
    max_symlink_hops: Math.max(...rebuilt.map((entry) => entry.symlink_hop_count)),
    canonical_regular_target_count: new Set(ids).size,
    duplicate_loader_path_count: rebuilt.length - new Set(rebuilt.map((entry) => entry.original_loader_path)).size,
    duplicate_canonical_identity_count: ids.length - new Set(ids).size,
    closure_path_list_sha256: sha256(`${rebuilt.map((entry) => entry.original_loader_path).sort().join('\n')}\n`),
    closure_manifest_sha256: sha256(JSON.stringify(compatibility)),
    closure_content_set_sha256: sha256(`${[...new Set(rebuilt.map((entry) => entry.canonical_content_sha256))].sort().join('\n')}\n`),
  };
  assertBaseline(projection, 'CAPTURE_DRIFT');
  return projection;
}

function runGit(args) {
  const result = spawnSync(GIT, args, { cwd: process.cwd(), encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' }, maxBuffer: 32 * 1024 * 1024 });
  if (result.error || result.status !== 0 || result.signal) fail('GIT_AUTHORITY');
  return result.stdout.trim();
}

function readAuthority() {
  const commit = runGit(['rev-parse', 'HEAD']);
  const parent = runGit(['rev-parse', 'HEAD^']);
  const tree = runGit(['rev-parse', 'HEAD^{tree}']);
  const subject = runGit(['show', '-s', '--format=%s', 'HEAD']);
  if (parent !== EXPECTED.terminalStop || subject !== EXPECTED.verifierSubject || runGit(['status', '--porcelain=v1', '-uall']) !== '') fail('GIT_AUTHORITY');
  const changed = runGit(['diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD']).split('\n').filter(Boolean).sort();
  if (JSON.stringify(changed) !== JSON.stringify([...AUTHORITY_PATHS].sort())) fail('GIT_AUTHORITY');
  const line = runGit(['ls-tree', 'HEAD', '--', VERIFIER_REL]);
  const match = line.match(/^100644 blob ([0-9a-f]{40})\t/);
  if (!match) fail('GIT_AUTHORITY');
  const bytesResult = spawnSync(GIT, ['cat-file', 'blob', `HEAD:${VERIFIER_REL}`], { cwd: process.cwd(), maxBuffer: 32 * 1024 * 1024 });
  if (bytesResult.error || bytesResult.status !== 0 || bytesResult.signal || gitBlobOid(bytesResult.stdout) !== match[1]) fail('GIT_AUTHORITY');
  const authority = { commit, parent, tree, subject, verifierBlob: match[1], verifierSha256: sha256(bytesResult.stdout) };
  validateAuthority(authority);
  return authority;
}

function validateSnapshot(authority) {
  const expected = path.join(RUNTIME_ROOT, '.verifiers', authority.commit, path.basename(VERIFIER_REL));
  if (path.resolve(SCRIPT_PATH) !== expected) fail('VERIFIER_SNAPSHOT');
  for (const directory of [RUNTIME_ROOT, path.join(RUNTIME_ROOT, '.verifiers'), path.join(RUNTIME_ROOT, '.verifiers', authority.commit)]) {
    requireTrustedDirectory(fs.lstatSync(directory, { bigint: true }), 0o700, 'VERIFIER_SNAPSHOT');
  }
  const opened = openReadNoFollow(expected, { mode: 0o600, maxBytes: 4 * 1024 * 1024, code: 'VERIFIER_SNAPSHOT' });
  if (opened.sha256 !== authority.verifierSha256 || gitBlobOid(opened.bytes) !== authority.verifierBlob) fail('VERIFIER_SNAPSHOT');
}

function pathsFor(authority) {
  const final = path.join(RUNTIME_ROOT, EXPECTED.creationAuthority, EXPECTED.nodeSha256);
  const generation = path.join(ADOPTION_ROOT, authority.commit, EXPECTED.creationAuthority, EXPECTED.nodeSha256);
  return {
    creationClaim: path.join(RUNTIME_ROOT, `${EXPECTED.creationAuthority}.claim.v2.json`),
    capture: path.join(RUNTIME_ROOT, `${EXPECTED.creationAuthority}.closure.capture.v2.json`),
    probeReceipt: path.join(RUNTIME_ROOT, `${EXPECTED.creationAuthority}.probe.receipt.v2.json`),
    final, node: path.join(final, 'node'), runtimeReceipt: path.join(final, 'runtime.receipt.v2.json'),
    generation, adoptionClaim: path.join(generation, 'adoption.claim.json'), adoptionReceipt: path.join(generation, 'adoption.receipt.json'),
  };
}

function hasImmutableFlag(target) {
  const result = spawnSync(READ_ATTRS, ['-d', '--', target], { encoding: 'utf8', env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' }, maxBuffer: 1024 * 1024 });
  if (result.error || result.status !== 0 || result.signal) fail('IMMUTABLE_FLAG');
  return String(result.stdout).trim().split(/\s+/)[0].includes('i');
}

function snapshotDirectory(target, mode, immutable = false) {
  const stat = fs.lstatSync(target, { bigint: true });
  requireTrustedDirectory(stat, mode, 'CAPSULE_DIRECTORY');
  if (immutable && !hasImmutableFlag(target)) fail('IMMUTABLE_FLAG');
  return { identitySha256: physicalIdentitySha256(stat), immutable: immutable ? true : undefined };
}

function artifactSnapshot(paths) {
  const creationClaim = openReadNoFollow(paths.creationClaim, { mode: 0o600, code: 'CREATION_CLAIM' });
  const capture = openReadNoFollow(paths.capture, { mode: 0o600, code: 'CLOSURE_CAPTURE' });
  const probeReceipt = openReadNoFollow(paths.probeReceipt, { mode: 0o600, code: 'PROBE_RECEIPT' });
  const node = openReadNoFollow(paths.node, { mode: 0o555, maxBytes: MAX_FILE_BYTES, code: 'CAPSULE_NODE' });
  const runtimeReceipt = openReadNoFollow(paths.runtimeReceipt, { mode: 0o444, code: 'RUNTIME_RECEIPT' });
  const final = snapshotDirectory(paths.final, 0o555, true);
  if (!hasImmutableFlag(paths.node) || !hasImmutableFlag(paths.runtimeReceipt)) fail('IMMUTABLE_FLAG');
  return { creationClaim, capture, probeReceipt, node, runtimeReceipt, final };
}

function stableArtifactProjection(snapshot) {
  const project = (entry) => ({ sha256: entry.sha256, identitySha256: entry.identitySha256 });
  return JSON.stringify({
    creationClaim: project(snapshot.creationClaim), capture: project(snapshot.capture), probeReceipt: project(snapshot.probeReceipt),
    node: project(snapshot.node), runtimeReceipt: project(snapshot.runtimeReceipt), final: snapshot.final,
  });
}

function runNode(executable, args, env = {}) {
  const result = spawnSync(executable, args, {
    encoding: 'utf8', timeout: 30_000, maxBuffer: 4 * 1024 * 1024,
    env: { HOME: '/var/empty', LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin', ...env },
  });
  if (result.error || result.status !== 0 || result.signal) fail('CAPSULE_EXECUTION');
  return result.stdout.trim();
}

function validateOriginalArtifacts(paths, snapshot) {
  for (const [entry, expected] of [
    [snapshot.creationClaim, EXPECTED.creationClaimSha256], [snapshot.capture, EXPECTED.closureCaptureSha256],
    [snapshot.probeReceipt, EXPECTED.probeReceiptSha256], [snapshot.runtimeReceipt, EXPECTED.runtimeReceiptSha256],
    [snapshot.node, EXPECTED.nodeSha256],
  ]) if (entry.sha256 !== expected) fail('ARTIFACT_HASH');
  const claim = JSON.parse(snapshot.creationClaim.bytes.toString('utf8'));
  const capture = JSON.parse(snapshot.capture.bytes.toString('utf8'));
  const probe = JSON.parse(snapshot.probeReceipt.bytes.toString('utf8'));
  const runtimeReceipt = JSON.parse(snapshot.runtimeReceipt.bytes.toString('utf8'));
  validateArtifactDocumentChain({
    claim, claimSha256: snapshot.creationClaim.sha256, capture, captureSha256: snapshot.capture.sha256,
    probe, probeSha256: snapshot.probeReceipt.sha256,
  });
  validateRuntimeReceiptBinding(runtimeReceipt);
  const closure = revalidateCapture(capture);
  const source = openReadNoFollow(BOOTSTRAP, { mode: 0o755, maxBytes: MAX_FILE_BYTES, code: 'SYSTEM_NODE' });
  if (source.sha256 !== EXPECTED.nodeSha256 || !crypto.timingSafeEqual(source.bytes, snapshot.node.bytes)) fail('SOURCE_CAPSULE_MISMATCH');
  return { claim, capture, probe, runtimeReceipt, closure, source };
}

async function ensureAdoptionDirectories(authority, generation) {
  await fsp.mkdir(ADOPTION_ROOT, { recursive: true, mode: 0o700 });
  await fsp.mkdir(path.join(ADOPTION_ROOT, authority.commit), { mode: 0o700 });
  await fsp.mkdir(path.join(ADOPTION_ROOT, authority.commit, EXPECTED.creationAuthority), { mode: 0o700 });
  await fsp.mkdir(generation, { mode: 0o700 });
  for (const directory of [ADOPTION_ROOT, path.join(ADOPTION_ROOT, authority.commit), path.join(ADOPTION_ROOT, authority.commit, EXPECTED.creationAuthority), generation]) {
    requireTrustedDirectory(fs.lstatSync(directory, { bigint: true }), 0o700, 'ADOPTION_DIRECTORY');
  }
}

async function writeExclusive(file, bytes, mode) {
  const handle = await fsp.open(file, F.O_WRONLY | F.O_CREAT | F.O_EXCL | F.O_NOFOLLOW, mode);
  try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
  const directory = await fsp.open(path.dirname(file), F.O_RDONLY | F.O_DIRECTORY | F.O_NOFOLLOW);
  try { await directory.sync(); } finally { await directory.close(); }
}

function exists(file) {
  try { fs.lstatSync(file); return true; }
  catch (error) { if (error?.code === 'ENOENT') return false; throw error; }
}

function validateClaimFile(paths, claim, authority) {
  const current = readJsonNoFollow(paths.adoptionClaim, { mode: 0o600, code: 'ADOPTION_CLAIM' });
  const expected = jsonBytes(claim);
  if (current.bytes.length !== expected.length || !crypto.timingSafeEqual(current.bytes, expected)) fail('ADOPTION_CLAIM');
  if (current.sha256 !== sha256(expected)) fail('ADOPTION_CLAIM');
  validateAuthority(authority);
  return current;
}

function nvmIdentity() {
  const target = '/root/.nvm';
  try { return physicalIdentitySha256(fs.lstatSync(target, { bigint: true })); }
  catch (error) { if (error?.code === 'ENOENT') return 'ABSENT'; throw error; }
}

function buildReceipt({ authority, claim, artifact, original, versionHash, smokeHash }) {
  return {
    schema_version: 1,
    purpose: 'CI3_NODE_RUNTIME_CAPSULE_V2_READ_ONLY_ADOPTION_RECEIPT',
    architecture: ARCHITECTURE,
    result: 'PASS',
    verifier_authority_commit: authority.commit,
    verifier_authority_parent: authority.parent,
    verifier_authority_tree: authority.tree,
    verifier_authority_subject: authority.subject,
    verifier_blob_oid: authority.verifierBlob,
    verifier_sha256: authority.verifierSha256,
    creation_authority_commit: EXPECTED.creationAuthority,
    old_builder_blob_oid: EXPECTED.oldBuilderBlob,
    old_builder_sha256: EXPECTED.oldBuilderSha256,
    terminal_stop_commit: EXPECTED.terminalStop,
    adoption_claim_sha256: sha256(jsonBytes(claim)),
    creation_claim_sha256: EXPECTED.creationClaimSha256,
    closure_capture_sha256: EXPECTED.closureCaptureSha256,
    capability_probe_receipt_sha256: EXPECTED.probeReceiptSha256,
    runtime_receipt_sha256: EXPECTED.runtimeReceiptSha256,
    capsule_node_sha256: EXPECTED.nodeSha256,
    creation_claim_identity_sha256: artifact.creationClaim.identitySha256,
    closure_capture_identity_sha256: artifact.capture.identitySha256,
    capability_probe_receipt_identity_sha256: artifact.probeReceipt.identitySha256,
    runtime_receipt_identity_sha256: artifact.runtimeReceipt.identitySha256,
    capsule_node_identity_sha256: artifact.node.identitySha256,
    capsule_directory_identity_sha256: artifact.final.identitySha256,
    source_node_identity_sha256: original.source.identitySha256,
    ...BASELINE,
    immutable_flags: { node: true, receipt: true, directory: true },
    source_capsule_bytes_equal: true,
    node_version_sha256: versionHash,
    core_module_smoke_sha256: smokeHash,
    bootstrap_verify_pass: true,
    capsule_self_hosted_verify_pass: true,
    adoption_attempt: 1,
    adoption_retry: false,
    create: false,
    ldd: false,
    probe: false,
    chattr: false,
    capsule_mutation: false,
    network_calls: 0,
    package_manager_calls: 0,
    secret_input_opens: 0,
    system_node_unchanged: true,
    nvm_unchanged: true,
    raw_paths_reported: false,
    raw_values_reported: false,
    created_at_utc: new Date().toISOString(),
  };
}

function verifyExistingReceipt(paths, claim, authority) {
  const current = readJsonNoFollow(paths.adoptionReceipt, { mode: 0o444, code: 'ADOPTION_RECEIPT' });
  validateAdoptionReceipt(current.value, claim, authority);
  return current;
}

async function internalVerify(authority, paths, claim) {
  if (process.env[INTERNAL_CLAIM] !== sha256(jsonBytes(claim))) fail('INTERNAL_BINDING');
  validateClaimFile(paths, claim, authority);
  const before = artifactSnapshot(paths);
  validateOriginalArtifacts(paths, before);
  const after = artifactSnapshot(paths);
  if (stableArtifactProjection(before) !== stableArtifactProjection(after)) fail('CAPSULE_MUTATION');
  process.stdout.write('INTERNAL PASS\n');
}

async function verifyExisting() {
  if (process.getuid?.() !== 0 || process.platform !== 'linux') fail('VPS_REQUIRED');
  const authority = readAuthority();
  validateSnapshot(authority);
  const paths = pathsFor(authority);
  const claim = buildAdoptionClaim(authority);
  if (['bootstrap', 'capsule'].includes(process.env[INTERNAL_PHASE])) {
    await internalVerify(authority, paths, claim);
    return;
  }
  const claimExists = exists(paths.adoptionClaim);
  const receiptExists = exists(paths.adoptionReceipt);
  if (!claimExists && receiptExists) fail('UNCLAIMED_RECEIPT');
  if (claimExists && !receiptExists) fail('ADOPTION_ATTEMPT_CONSUMED');
  if (claimExists && receiptExists) {
    validateClaimFile(paths, claim, authority);
    const before = artifactSnapshot(paths);
    validateOriginalArtifacts(paths, before);
    verifyExistingReceipt(paths, claim, authority);
    const after = artifactSnapshot(paths);
    if (stableArtifactProjection(before) !== stableArtifactProjection(after)) fail('CAPSULE_MUTATION');
    process.stdout.write(`VERIFY_EXISTING PASS status=EXISTS_ADOPTED authority_sha=${authority.commit} receipt_sha256=${sha256(openReadNoFollow(paths.adoptionReceipt, { mode: 0o444 }).bytes)}\n`);
    return;
  }
  await ensureAdoptionDirectories(authority, paths.generation);
  await writeExclusive(paths.adoptionClaim, jsonBytes(claim), 0o600);
  validateClaimFile(paths, claim, authority);
  const nvmBefore = nvmIdentity();
  const before = artifactSnapshot(paths);
  const original = validateOriginalArtifacts(paths, before);
  const version = runNode(paths.node, ['--version']);
  if (!/^v\d+\.\d+\.\d+$/.test(version)) fail('CAPSULE_VERSION');
  const smoke = runNode(paths.node, ['-e', 'const c=require("node:crypto");const f=require("node:fs");if(typeof c.createHash!=="function"||typeof f.openSync!=="function")process.exit(2);process.stdout.write("CORE_OK")']);
  if (smoke !== 'CORE_OK') fail('CAPSULE_SMOKE');
  const internalEnv = { [INTERNAL_CLAIM]: sha256(jsonBytes(claim)) };
  const bootstrapOutput = runNode(BOOTSTRAP, [SCRIPT_PATH, '--verify-existing'], { ...internalEnv, [INTERNAL_PHASE]: 'bootstrap' });
  if (bootstrapOutput !== 'INTERNAL PASS') fail('BOOTSTRAP_VERIFY');
  const capsuleOutput = runNode(paths.node, [SCRIPT_PATH, '--verify-existing'], { ...internalEnv, [INTERNAL_PHASE]: 'capsule' });
  if (capsuleOutput !== 'INTERNAL PASS') fail('SELF_HOSTED_VERIFY');
  const beforeReceipt = artifactSnapshot(paths);
  if (stableArtifactProjection(before) !== stableArtifactProjection(beforeReceipt)) fail('CAPSULE_MUTATION');
  const receipt = buildReceipt({ authority, claim, artifact: before, original, versionHash: sha256(version), smokeHash: sha256(smoke) });
  validateAdoptionReceipt(receipt, claim, authority);
  await writeExclusive(paths.adoptionReceipt, jsonBytes(receipt), 0o444);
  verifyExistingReceipt(paths, claim, authority);
  const after = artifactSnapshot(paths);
  const sourceAfter = openReadNoFollow(BOOTSTRAP, { mode: 0o755, maxBytes: MAX_FILE_BYTES, code: 'SYSTEM_NODE' });
  if (stableArtifactProjection(before) !== stableArtifactProjection(after) || original.source.identitySha256 !== sourceAfter.identitySha256 ||
      original.source.sha256 !== sourceAfter.sha256 || nvmBefore !== nvmIdentity()) fail('PRESERVATION');
  process.stdout.write(`VERIFY_EXISTING PASS status=ADOPTED_READ_ONLY authority_sha=${authority.commit} receipt_sha256=${sha256(jsonBytes(receipt))}\n`);
}

async function selfTest() {
  let count = 0;
  if (parseMode(['--self-test']) !== 'self-test') fail('SELF_TEST'); count += 1;
  if (parseMode(['--verify-existing']) !== 'verify-existing') fail('SELF_TEST'); count += 1;
  if (Object.keys(BASELINE).length !== 14 || BASELINE.loader_entry_count !== 7) fail('SELF_TEST'); count += 1;
  if (!SHA64.test(EXPECTED.runtimeReceiptSha256) || !SHA40.test(EXPECTED.terminalStop)) fail('SELF_TEST'); count += 1;
  if (JSON.stringify(correctedCapabilityProjection({ schema_version: 2, authority: EXPECTED.creationAuthority, attempted: 1, immutable_set: true, write_rejected: true, unlink_rejected: true, rename_rejected: true })) !== JSON.stringify({ attempted: 1, immutable_set: true, write_rejected: true, unlink_rejected: true, rename_rejected: true })) fail('SELF_TEST'); count += 1;
  if (AUTHORITY_PATHS.length !== 7) fail('SELF_TEST'); count += 1;
  if (!ARCHITECTURE.includes('READ_ONLY')) fail('SELF_TEST'); count += 1;
  if (buildAdoptionClaim({ commit: 'a'.repeat(40), parent: EXPECTED.terminalStop, tree: 'b'.repeat(40), subject: EXPECTED.verifierSubject, verifierBlob: 'c'.repeat(40), verifierSha256: 'd'.repeat(64) }).create !== false) fail('SELF_TEST'); count += 1;
  process.stdout.write(`SELF_TEST PASS tests=${count} network_calls=0 ldd_calls=0 chattr_calls=0 create_calls=0 capsule_mutation_calls=0 secret_input_opens=0 raw_paths_reported=0\n`);
}

async function main() {
  try {
    const mode = parseMode(process.argv.slice(2));
    if (mode === 'self-test') await selfTest();
    else await verifyExisting();
  } catch (error) {
    process.stderr.write(`${sanitizeError(error)}\n`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === SCRIPT_PATH) await main();
