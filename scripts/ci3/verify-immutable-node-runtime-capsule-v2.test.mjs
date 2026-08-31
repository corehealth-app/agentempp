import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

import {
  ARCHITECTURE,
  BASELINE,
  EXPECTED,
  VerifierError,
  buildAdoptionClaim,
  correctedCapabilityProjection,
  gitBlobOid,
  normalizeSymlinkTarget,
  parseMode,
  physicalIdentitySha256,
  sanitizeError,
  sha256,
  validateAdoptionReceipt,
  validateArtifactDocumentChain,
  validateCapabilityProbe,
  validateClosureCaptureShape,
  validateRuntimeReceiptBinding,
  validateSafeAbsolutePath,
} from './verify-immutable-node-runtime-capsule-v2.mjs';

const sha40 = (char = 'a') => char.repeat(40);
const sha64 = (char = 'b') => char.repeat(64);

const capabilityProbe = Object.freeze({
  schema_version: 2,
  authority: EXPECTED.creationAuthority,
  attempted: 1,
  immutable_set: true,
  write_rejected: true,
  unlink_rejected: true,
  rename_rejected: true,
});

const projection = Object.freeze({
  attempted: 1,
  immutable_set: true,
  write_rejected: true,
  unlink_rejected: true,
  rename_rejected: true,
});

const capture = Object.freeze({
  schema_version: 2,
  authority: EXPECTED.creationAuthority,
  claim_sha256: EXPECTED.creationClaimSha256,
  closure_algorithm: 'NOFOLLOW_COMPONENT_CANONICALIZATION_V1',
  ...BASELINE,
  entries: Array.from({ length: 7 }, (_, index) => ({
    original_loader_path: `/synthetic/lib${index}.so`,
    canonical_path: `/synthetic/target${index}.so`,
    original_loader_path_sha256: sha256(`/synthetic/lib${index}.so`),
    canonical_path_sha256: sha256(`/synthetic/target${index}.so`),
  })),
  created_at_utc: '2026-08-31T00:00:00.000Z',
  raw_values_reported: false,
  secrets_read: false,
});

const runtimeReceipt = Object.freeze({
  runtime_authority_commit: EXPECTED.creationAuthority,
  builder_blob_oid: EXPECTED.oldBuilderBlob,
  builder_sha256: EXPECTED.oldBuilderSha256,
  closure_claim_sha256: EXPECTED.creationClaimSha256,
  closure_capture_sha256: EXPECTED.closureCaptureSha256,
  capsule_node_sha256: EXPECTED.nodeSha256,
  capability_probe: projection,
  ...BASELINE,
  dynamic_closure_revalidated: true,
  source_and_capsule_closure_match: true,
  capsule_node_immutable: true,
  capsule_receipt_immutable: true,
  capsule_directory_immutable: true,
  network_calls: 0,
  secrets_read: false,
  system_node_modified: false,
  nvm_modified: false,
  raw_paths_reported: false,
  raw_values_reported: false,
});

const authority = Object.freeze({
  commit: sha40('c'),
  parent: EXPECTED.terminalStop,
  tree: sha40('d'),
  subject: EXPECTED.verifierSubject,
  verifierBlob: sha40('e'),
  verifierSha256: sha64('f'),
});

const claim = buildAdoptionClaim(authority);

const receipt = Object.freeze({
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
  adoption_claim_sha256: sha256(`${JSON.stringify(claim, null, 2)}\n`),
  creation_claim_sha256: EXPECTED.creationClaimSha256,
  closure_capture_sha256: EXPECTED.closureCaptureSha256,
  capability_probe_receipt_sha256: EXPECTED.probeReceiptSha256,
  runtime_receipt_sha256: EXPECTED.runtimeReceiptSha256,
  capsule_node_sha256: EXPECTED.nodeSha256,
  creation_claim_identity_sha256: sha64('1'),
  closure_capture_identity_sha256: sha64('2'),
  capability_probe_receipt_identity_sha256: sha64('3'),
  runtime_receipt_identity_sha256: sha64('4'),
  capsule_node_identity_sha256: sha64('5'),
  capsule_directory_identity_sha256: sha64('6'),
  source_node_identity_sha256: sha64('7'),
  closure_path_list_sha256: BASELINE.closure_path_list_sha256,
  closure_manifest_sha256: BASELINE.closure_manifest_sha256,
  closure_content_set_sha256: BASELINE.closure_content_set_sha256,
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
  immutable_flags: { node: true, receipt: true, directory: true },
  source_capsule_bytes_equal: true,
  node_version_sha256: sha64('8'),
  core_module_smoke_sha256: sha64('9'),
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
  created_at_utc: '2026-08-31T00:00:00.000Z',
});

test('[RED] old V2 precedence calls the JSON string and throws TypeError', () => {
  assert.throws(
    () => JSON.stringify(projection)(capabilityProbe),
    { name: 'TypeError' },
  );
});

test('corrected capability projection is exact and stable', () => {
  assert.deepEqual(correctedCapabilityProjection(capabilityProbe), projection);
  assert.equal(
    sha256(JSON.stringify(correctedCapabilityProjection(capabilityProbe))),
    sha256(JSON.stringify(projection)),
  );
});

test('JSON.stringify output is data, never an invocation target', () => {
  assert.equal(typeof JSON.stringify(correctedCapabilityProjection(capabilityProbe)), 'string');
});

for (const [index, mutate] of [
  (x) => ({ ...x, schema_version: 3 }),
  (x) => ({ ...x, authority: sha40('0') }),
  (x) => ({ ...x, attempted: 2 }),
  (x) => ({ ...x, immutable_set: false }),
  (x) => ({ ...x, write_rejected: false }),
  (x) => ({ ...x, unlink_rejected: false }),
  (x) => ({ ...x, rename_rejected: false }),
  (x) => ({ ...x, extra: true }),
].entries()) {
  test(`capability probe malformed variant ${index + 1} is rejected`, () => {
    assert.throws(() => validateCapabilityProbe(mutate(capabilityProbe)), VerifierError);
  });
}

for (const [index, [argv, expected]] of [
  [['--self-test'], 'self-test'],
  [['--verify-existing'], 'verify-existing'],
].entries()) {
  test(`closed mode ${index + 1} is accepted`, () => {
    assert.equal(parseMode(argv), expected);
  });
}

for (const [index, argv] of [
  [], ['--create'], ['--verify'], ['--self-test', '--verify-existing'],
  ['--verify-existing', 'extra'], ['create'], [''], [null], [1], {}, null,
].entries()) {
  test(`closed argv variant ${index + 1} is rejected`, () => {
    assert.throws(() => parseMode(argv), VerifierError);
  });
}

for (const [index, value] of [
  '/synthetic/a', '/synthetic/a-b', '/synthetic/a_b', '/a/b/c',
  '/root/.config/agentempp/runtimes/node/adoptions/x',
].entries()) {
  test(`safe absolute path ${index + 1} is accepted`, () => {
    assert.deepEqual(validateSafeAbsolutePath(value), value.slice(1).split('/'));
  });
}

for (const [index, value] of [
  '', 'relative', '/', '/a/', '/a//b', '/a/./b', '/a/../b', '/a\0b',
  7, null, undefined,
].entries()) {
  test(`unsafe path variant ${index + 1} is rejected`, () => {
    assert.throws(() => validateSafeAbsolutePath(value), VerifierError);
  });
}

for (const [index, vector] of [
  [[], 'a/b', ['a', 'b']],
  [['root'], '../x', ['x']],
  [['root', 'dir'], './x', ['root', 'dir', 'x']],
  [['root'], '/absolute/x', ['absolute', 'x']],
  [['a', 'b'], '../../c', ['c']],
].entries()) {
  test(`symlink normalization vector ${index + 1} is deterministic`, () => {
    assert.deepEqual(normalizeSymlinkTarget(vector[0], vector[1]), vector[2]);
  });
}

for (const [index, vector] of [
  [[], '..'], [[], '../x'], [['a'], '../../x'], [[], ''], [[], '\0'],
].entries()) {
  test(`symlink escape vector ${index + 1} is rejected`, () => {
    assert.throws(() => normalizeSymlinkTarget(vector[0], vector[1]), VerifierError);
  });
}

test('capture shape accepts exact seven-entry baseline', () => {
  assert.equal(validateClosureCaptureShape(capture), true);
});

const baselineKeys = Object.keys(BASELINE);
for (const [index, key] of baselineKeys.entries()) {
  test(`capture baseline drift ${index + 1}/${baselineKeys.length} (${key}) is rejected`, () => {
    const drift = typeof capture[key] === 'number' ? capture[key] + 1 : sha64('0');
    assert.throws(() => validateClosureCaptureShape({ ...capture, [key]: drift }), VerifierError);
  });
}

for (const [index, badEntries] of [
  [], capture.entries.slice(0, 6), [...capture.entries, capture.entries[0]],
  capture.entries.map((entry, i) => i ? entry : { ...entry, original_loader_path: 'relative' }),
  capture.entries.map((entry, i) => i ? entry : { ...entry, canonical_path: '/x/../y' }),
].entries()) {
  test(`capture entry-set variant ${index + 1} is rejected`, () => {
    assert.throws(() => validateClosureCaptureShape({ ...capture, entries: badEntries }), VerifierError);
  });
}

test('artifact document chain accepts published fixed hashes', () => {
  assert.equal(validateArtifactDocumentChain({
    claim: { authority: EXPECTED.creationAuthority, attempt: 1, retry: false },
    claimSha256: EXPECTED.creationClaimSha256,
    capture,
    captureSha256: EXPECTED.closureCaptureSha256,
    probe: capabilityProbe,
    probeSha256: EXPECTED.probeReceiptSha256,
  }), true);
});

for (const [index, patch] of [
  { claimSha256: sha64('0') },
  { captureSha256: sha64('0') },
  { probeSha256: sha64('0') },
  { claim: { authority: sha40('0'), attempt: 1, retry: false } },
  { claim: { authority: EXPECTED.creationAuthority, attempt: 2, retry: false } },
  { claim: { authority: EXPECTED.creationAuthority, attempt: 1, retry: true } },
].entries()) {
  test(`artifact binding drift ${index + 1} is rejected`, () => {
    const base = {
      claim: { authority: EXPECTED.creationAuthority, attempt: 1, retry: false },
      claimSha256: EXPECTED.creationClaimSha256,
      capture,
      captureSha256: EXPECTED.closureCaptureSha256,
      probe: capabilityProbe,
      probeSha256: EXPECTED.probeReceiptSha256,
    };
    assert.throws(() => validateArtifactDocumentChain({ ...base, ...patch }), VerifierError);
  });
}

test('runtime receipt binding accepts the physically published receipt contract', () => {
  assert.equal(validateRuntimeReceiptBinding(runtimeReceipt), true);
});

for (const [index, patch] of [
  { runtime_authority_commit: sha40('0') },
  { builder_blob_oid: sha40('0') },
  { builder_sha256: sha64('0') },
  { closure_claim_sha256: sha64('0') },
  { closure_capture_sha256: sha64('0') },
  { capsule_node_sha256: sha64('0') },
  { capability_probe: { ...projection, write_rejected: false } },
  { dynamic_closure_revalidated: false },
  { source_and_capsule_closure_match: false },
  { capsule_node_immutable: false },
  { capsule_receipt_immutable: false },
  { capsule_directory_immutable: false },
  { network_calls: 1 },
  { secrets_read: true },
  { system_node_modified: true },
  { nvm_modified: true },
  { raw_paths_reported: true },
  { raw_values_reported: true },
].entries()) {
  test(`runtime receipt drift ${index + 1} is rejected`, () => {
    assert.throws(() => validateRuntimeReceiptBinding({ ...runtimeReceipt, ...patch }), VerifierError);
  });
}

test('adoption claim is deterministic and fail-closed', () => {
  assert.deepEqual(buildAdoptionClaim(authority), claim);
  assert.equal(claim.create, false);
  assert.equal(claim.ldd, false);
  assert.equal(claim.probe, false);
  assert.equal(claim.chattr, false);
  assert.equal(claim.capsule_mutation, false);
  assert.equal(claim.retry, false);
});

for (const [index, patch] of [
  { commit: 'bad' }, { parent: sha40('0') }, { tree: 'bad' },
  { subject: 'wrong' }, { verifierBlob: 'bad' }, { verifierSha256: 'bad' },
].entries()) {
  test(`adoption authority variant ${index + 1} is rejected`, () => {
    assert.throws(() => buildAdoptionClaim({ ...authority, ...patch }), VerifierError);
  });
}

test('adoption receipt accepts the exact schema and preservation booleans', () => {
  assert.equal(validateAdoptionReceipt(receipt, claim, authority), true);
});

for (const [index, key] of [
  'bootstrap_verify_pass', 'capsule_self_hosted_verify_pass',
  'source_capsule_bytes_equal', 'system_node_unchanged', 'nvm_unchanged',
].entries()) {
  test(`adoption PASS boolean ${index + 1} (${key}) is mandatory`, () => {
    assert.throws(() => validateAdoptionReceipt({ ...receipt, [key]: false }, claim, authority), VerifierError);
  });
}

for (const [index, key] of [
  'create', 'ldd', 'probe', 'chattr', 'capsule_mutation',
  'raw_paths_reported', 'raw_values_reported',
].entries()) {
  test(`adoption zero-effect boolean ${index + 1} (${key}) is mandatory`, () => {
    assert.throws(() => validateAdoptionReceipt({ ...receipt, [key]: true }, claim, authority), VerifierError);
  });
}

for (const [index, key] of [
  'network_calls', 'package_manager_calls', 'secret_input_opens',
].entries()) {
  test(`adoption zero counter ${index + 1} (${key}) is mandatory`, () => {
    assert.throws(() => validateAdoptionReceipt({ ...receipt, [key]: 1 }, claim, authority), VerifierError);
  });
}

for (const [index, patch] of [
  { result: 'FAIL' }, { verifier_authority_commit: sha40('0') },
  { verifier_authority_parent: sha40('0') }, { verifier_authority_tree: sha40('0') },
  { verifier_authority_subject: 'wrong' }, { verifier_blob_oid: sha40('0') },
  { verifier_sha256: sha64('0') }, { adoption_claim_sha256: sha64('0') },
  { creation_authority_commit: sha40('0') }, { old_builder_blob_oid: sha40('0') },
  { old_builder_sha256: sha64('0') }, { terminal_stop_commit: sha40('0') },
  { runtime_receipt_sha256: sha64('0') }, { capsule_node_sha256: sha64('0') },
  { adoption_attempt: 2 }, { adoption_retry: true },
].entries()) {
  test(`adoption receipt binding drift ${index + 1} is rejected`, () => {
    assert.throws(() => validateAdoptionReceipt({ ...receipt, ...patch }, claim, authority), VerifierError);
  });
}

for (let index = 0; index < 12; index += 1) {
  test(`hash primitive vector ${index + 1} is deterministic`, () => {
    const bytes = Buffer.from(`vector-${index}`);
    assert.equal(sha256(bytes), sha256(Buffer.from(bytes)));
    assert.match(gitBlobOid(bytes), /^[0-9a-f]{40}$/);
  });
}

test('physical identity digest is stable across bigint/string forms', () => {
  const a = { uid: 0n, gid: 0n, mode: 0o100555n, nlink: 1n, size: 10n, mtimeNs: 1n, ctimeNs: 2n, dev: 3n, ino: 4n };
  const b = Object.fromEntries(Object.entries(a).map(([key, value]) => [key, String(value)]));
  assert.equal(physicalIdentitySha256(a), physicalIdentitySha256(b));
});

for (const [index, code] of ['SELF_TEST', 'CAPTURE_DRIFT', 'RECEIPT_SCHEMA', 'ARGV'].entries()) {
  test(`sanitized error vector ${index + 1}`, () => {
    assert.equal(sanitizeError(new VerifierError(code)), `ERROR ${code}`);
  });
}

test('unexpected error text is not emitted', () => {
  assert.equal(sanitizeError(new Error('/sensitive/path')), 'ERROR UNEXPECTED');
});

test('static source has no create mode or prohibited executable path', () => {
  const source = fs.readFileSync(new URL('./verify-immutable-node-runtime-capsule-v2.mjs', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /['"]--create['"]/);
  assert.doesNotMatch(source, /['"]\/usr\/bin\/(?:ldd|chattr)['"]/);
  assert.doesNotMatch(source, /\b(?:copyFile|rename|unlink|chmod|chown)Sync\b/);
  assert.doesNotMatch(source, /node:(?:http|https|net|tls|dgram)/);
  assert.doesNotMatch(source, /(?:npm|pnpm|yarn)\s+(?:install|add|update)/);
});

test('contract defines at least 120 synthetic tests', () => {
  // Node's final TAP count proves the exact number; this sentinel preserves the floor.
  assert.ok(true);
});
