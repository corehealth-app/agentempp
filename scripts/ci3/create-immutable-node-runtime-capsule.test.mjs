import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import {
  ARCHITECTURE, AUTHORITY_PARENT, AUTHORITY_PATHS, AUTHORITY_SUBJECT,
  BOOTSTRAP_NODE, BOOTSTRAP_SHA256, FORBIDDEN_NVM_PREFIX, SECRET_PATHS,
  assertBootstrapPath, assertStableIdentity, buildReceipt, canonicalJson,
  buildClaim, classifyCreationState, closureDigest, gitBlobOid, hasImmutableFlag, identity, jsonBytes,
  parseLddOutput, parseMode, physicalIdentitySha256, sanitizeError, sha256,
  runCapabilityProbeSequence,
  validateAuthorityPaths, validateDirectoryMetadata, validateReceipt,
  validateRegularMetadata,
} from './create-immutable-node-runtime-capsule.mjs';

function expectCode(code, fn) {
  assert.throws(fn, (error) => error?.code === code);
}

function fileStat(overrides = {}) {
  return {
    uid: 0n, gid: 0n, mode: 0o100755n, nlink: 1n, size: 100n,
    mtimeNs: 11n, ctimeNs: 12n, dev: 13n, ino: 14n,
    isFile: () => true, isDirectory: () => false, isSymbolicLink: () => false,
    ...overrides,
  };
}

function directoryStat(overrides = {}) {
  return {
    uid: 0n, gid: 0n, mode: 0o40555n, nlink: 2n, size: 100n,
    mtimeNs: 11n, ctimeNs: 12n, dev: 13n, ino: 14n,
    isFile: () => false, isDirectory: () => true, isSymbolicLink: () => false,
    ...overrides,
  };
}

function receiptFixture() {
  const authority = {
    commit: 'a'.repeat(40), parent: AUTHORITY_PARENT, tree: 'b'.repeat(40),
    subject: AUTHORITY_SUBJECT, authority_manifest_sha256: 'c'.repeat(64),
    builder_blob_oid: 'd'.repeat(40), builder_sha256: 'e'.repeat(64),
  };
  const bootstrap = {
    sha256: BOOTSTRAP_SHA256, version: 'v20.20.2', identitySha256: 'f'.repeat(64),
    parent_chain_sha256: '1'.repeat(64), process_versions_sha256: '2'.repeat(64),
    closure: { count: 2, sha256: '3'.repeat(64) },
  };
  const capsule = {
    generationId: `node-${BOOTSTRAP_SHA256}`,
    nodePath: `/root/.config/agentempp/runtimes/node/${authority.commit}/${BOOTSTRAP_SHA256}/node`,
    sha256: BOOTSTRAP_SHA256, identitySha256: '4'.repeat(64),
    filesystemDescriptorSha256: '5'.repeat(64),
  };
  const probe = { attempted: 1, immutable_set: true, write_rejected: true, unlink_rejected: true, rename_rejected: true, cleaned: true };
  const tools = [{ name: 'chattr', sha256: '6'.repeat(64) }, { name: 'lsattr', sha256: '7'.repeat(64) }];
  const receipt = buildReceipt({ authority, bootstrap, capsule, closureAfter: { ...bootstrap.closure }, probe, tools, timestamp: '2026-08-31T00:00:00.000Z' });
  return { authority, bootstrap, capsule, probe, tools, receipt };
}

test('architecture is frozen', () => assert.equal(ARCHITECTURE, 'PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V1'));
test('bootstrap path is literal', () => assert.equal(BOOTSTRAP_NODE, '/usr/bin/node'));
test('bootstrap hash is frozen', () => assert.equal(BOOTSTRAP_SHA256.length, 64));
test('authority parent is the bridge authority', () => assert.equal(AUTHORITY_PARENT, 'ba8473799a19aec586b0fe706bb7d4084589c86c'));
test('authority subject is exact', () => assert.equal(AUTHORITY_SUBJECT, 'build(ops): authorize immutable VPS Node runtime capsule'));
test('allowlist has exactly seven paths', () => assert.equal(AUTHORITY_PATHS.length, 7));
test('secret denylist has exactly five paths', () => assert.equal(SECRET_PATHS.length, 5));

for (const [argv, expected] of [[['--self-test'], 'self-test'], [['--create'], 'create'], [['--verify'], 'verify']]) {
  test(`accepts closed mode ${argv[0]}`, () => assert.equal(parseMode(argv), expected));
}
for (const argv of [[], ['--unknown'], ['--create', 'again'], ['--verify', 'path'], ['create']]) {
  test(`rejects invalid argv ${JSON.stringify(argv)}`, () => expectCode('MODE_INVALID', () => parseMode(argv)));
}

test('accepts only the literal bootstrap', () => assert.equal(assertBootstrapPath('/usr/bin/node'), true));
for (const candidate of ['/usr/local/bin/node', '/bin/node', `${FORBIDDEN_NVM_PREFIX}versions/node/v24/bin/node`, '', '/tmp/node']) {
  test(`rejects bootstrap fallback ${candidate || 'empty'}`, () => expectCode('BOOTSTRAP_PATH', () => assertBootstrapPath(candidate)));
}

test('accepts exact bootstrap metadata', () => assert.equal(validateRegularMetadata(fileStat(), { mode: 0o755 }), true));
for (const [name, mutation] of [
  ['wrong uid', { uid: 1n }], ['wrong gid', { gid: 1n }], ['wrong mode', { mode: 0o100775n }],
  ['hardlink', { nlink: 2n }], ['symlink', { isSymbolicLink: () => true }],
  ['directory', { isFile: () => false, isDirectory: () => true }],
]) {
  test(`rejects source ${name}`, () => expectCode('SOURCE_METADATA', () => validateRegularMetadata(fileStat(mutation), { mode: 0o755, code: 'SOURCE_METADATA' })));
}

test('accepts exact final directory metadata and immutable flag', () => assert.equal(validateDirectoryMetadata(directoryStat(), { mode: 0o555, immutable: true, attrs: '----i---------e------- path' }), true));
for (const [name, metadata, attrs] of [
  ['wrong owner', directoryStat({ uid: 1n }), '----i---------e-------'],
  ['wrong group', directoryStat({ gid: 1n }), '----i---------e-------'],
  ['wrong mode', directoryStat({ mode: 0o40755n }), '----i---------e-------'],
  ['not directory', directoryStat({ isDirectory: () => false }), '----i---------e-------'],
  ['symlink', directoryStat({ isSymbolicLink: () => true }), '----i---------e-------'],
  ['missing immutable', directoryStat(), '--------------e-------'],
]) {
  test(`rejects final directory ${name}`, () => assert.throws(() => validateDirectoryMetadata(metadata, { mode: 0o555, immutable: true, attrs })));
}

test('detects immutable i flag', () => assert.equal(hasImmutableFlag('----i---------e------- /x'), true));
test('rejects e flag as immutable', () => assert.equal(hasImmutableFlag('--------------e------- /x'), false));
test('rejects empty attrs as immutable', () => assert.equal(hasImmutableFlag(''), false));
test('rejects non-string attrs', () => expectCode('IMMUTABLE_FLAG', () => hasImmutableFlag(null)));

test('identity retains exact bigint fields', () => assert.deepEqual(identity(fileStat()).size, 100n));
test('identity rejects Number projections', () => assert.throws(() => identity(fileStat({ size: Number(2n ** 53n) }))));
test('physical identity is deterministic', () => assert.equal(physicalIdentitySha256(fileStat()), physicalIdentitySha256(fileStat())));
for (const [field, value] of [
  ['uid', 1n], ['gid', 1n], ['mode', 0o100700n], ['nlink', 2n], ['size', 101n],
  ['mtimeNs', 21n], ['ctimeNs', 22n], ['dev', 23n], ['ino', 24n],
]) {
  test(`stable identity rejects ${field} drift`, () => expectCode('DRIFT', () => assertStableIdentity(fileStat(), fileStat({ [field]: value }), 'DRIFT')));
}
test('stable identity accepts exact copy', () => assert.equal(assertStableIdentity(fileStat(), fileStat()), true));

test('sha256 hashes bytes', () => assert.equal(sha256(Buffer.from('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'));
test('git blob oid uses canonical header', () => assert.equal(gitBlobOid(Buffer.from('test content\n')), 'd670460b4b4aece5915caf5c68d12f560a9fe3e4'));
test('canonical JSON sorts object keys', () => assert.equal(canonicalJson({ b: 1, a: 2 }), '{"a":2,"b":1}'));
test('canonical JSON preserves array order', () => assert.equal(canonicalJson([2, 1]), '[2,1]'));
test('JSON bytes end in newline', () => assert.equal(jsonBytes({ a: 1 }).endsWith('\n'), true));

test('parses arrow-form ldd paths', () => assert.deepEqual(parseLddOutput('libc.so.6 => /lib/libc.so.6 (0x1)\n'), ['/lib/libc.so.6']));
test('parses direct loader path', () => assert.deepEqual(parseLddOutput('/lib64/ld-linux.so.2 (0x1)\n'), ['/lib64/ld-linux.so.2']));
test('deduplicates and sorts closure paths', () => assert.deepEqual(parseLddOutput('x => /z (0x1)\ny => /a (0x2)\nx => /z (0x3)\n'), ['/a', '/z']));
test('ignores virtual vdso', () => assert.deepEqual(parseLddOutput('linux-vdso.so.1 (0x1)\n'), []));

test('closure digest is deterministic', () => {
  const a = [{ path: '/b', sha256: 'a'.repeat(64) }, { path: '/a', sha256: 'b'.repeat(64) }];
  assert.deepEqual(closureDigest(a), closureDigest([...a].reverse()));
});
for (const entries of [[], [{ path: 'relative', sha256: 'a'.repeat(64) }], [{ path: '/a', sha256: 'x' }], [{ path: '/a', sha256: 'a'.repeat(64) }, { path: '/a', sha256: 'b'.repeat(64) }]]) {
  test(`rejects invalid closure ${JSON.stringify(entries).slice(0, 50)}`, () => expectCode('DYNAMIC_CLOSURE', () => closureDigest(entries)));
}

test('accepts exact seven authority paths', () => assert.equal(validateAuthorityPaths([...AUTHORITY_PATHS]), true));
test('accepts reordered exact authority paths', () => assert.equal(validateAuthorityPaths([...AUTHORITY_PATHS].reverse()), true));
test('rejects missing authority path', () => expectCode('AUTHORITY_PATHS', () => validateAuthorityPaths(AUTHORITY_PATHS.slice(1))));
test('rejects extra authority path', () => expectCode('AUTHORITY_PATHS', () => validateAuthorityPaths([...AUTHORITY_PATHS, 'extra'])));
test('rejects duplicate authority path', () => expectCode('AUTHORITY_PATHS', () => validateAuthorityPaths([...AUTHORITY_PATHS.slice(0, 6), AUTHORITY_PATHS[0]])));

test('fresh creation state requires every target absent', () => assert.equal(classifyCreationState({ claim: false, final: false, staging: false, probe: false, renamedProbe: false }), 'FRESH'));
test('exact-existing state requires original claim and complete final only', () => assert.equal(classifyCreationState({ claim: true, final: true, staging: false, probe: false, renamedProbe: false }), 'VERIFY_EXACT_EXISTING'));
test('unclaimed final is rejected', () => expectCode('UNCLAIMED_EXISTING_STATE', () => classifyCreationState({ claim: false, final: true, staging: false, probe: false, renamedProbe: false })));
test('unclaimed staging is rejected', () => expectCode('UNCLAIMED_EXISTING_STATE', () => classifyCreationState({ claim: false, final: false, staging: true, probe: false, renamedProbe: false })));
test('claim-only state is terminal partial state', () => expectCode('CLAIM_CONSUMED_PARTIAL_STATE', () => classifyCreationState({ claim: true, final: false, staging: false, probe: false, renamedProbe: false })));
test('claimed staging is terminal partial state', () => expectCode('CLAIM_CONSUMED_PARTIAL_STATE', () => classifyCreationState({ claim: true, final: false, staging: true, probe: false, renamedProbe: false })));
test('claimed probe is terminal partial state', () => expectCode('CLAIM_CONSUMED_PARTIAL_STATE', () => classifyCreationState({ claim: true, final: false, staging: false, probe: true, renamedProbe: false })));
test('creation state rejects non-booleans', () => expectCode('CREATION_STATE', () => classifyCreationState({ claim: 1, final: false, staging: false, probe: false, renamedProbe: false })));

test('claim is deterministic attempt-one and hash-bound', () => {
  const { authority, bootstrap, tools } = receiptFixture();
  const first = buildClaim({ authority, bootstrap, tools });
  const second = buildClaim({ authority, bootstrap, tools });
  assert.equal(jsonBytes(first), jsonBytes(second));
  assert.equal(first.attempt, 1);
  assert.equal(first.capability_probe_attempt, 1);
  assert.equal(first.retry, false);
  assert.equal(first.source_sha256, BOOTSTRAP_SHA256);
});

test('capability probe enforces ordered immutable semantics', async () => {
  const events = [];
  const result = await runCapabilityProbeSequence({
    create: async () => events.push('create'),
    setImmutable: async () => events.push('set'),
    readAttrs: async () => { events.push('attrs'); return '----i---------e-------'; },
    openWrite: async () => { events.push('write'); throw new Error('EPERM'); },
    unlink: async () => { events.push('unlink'); throw new Error('EPERM'); },
    rename: async () => { events.push('rename'); throw new Error('EPERM'); },
    clearImmutable: async () => events.push('clear'),
    remove: async () => events.push('remove'),
  });
  assert.deepEqual(events, ['create', 'set', 'attrs', 'write', 'unlink', 'rename', 'clear', 'remove']);
  assert.equal(result.cleaned, true);
});
test('capability probe rejects unsupported immutable flag', async () => {
  await assert.rejects(runCapabilityProbeSequence({
    create: async () => {}, setImmutable: async () => {}, readAttrs: async () => '--------------e-------',
    openWrite: async () => { throw new Error('unused'); }, unlink: async () => { throw new Error('unused'); }, rename: async () => { throw new Error('unused'); }, clearImmutable: async () => {}, remove: async () => {},
  }), (error) => error?.code === 'IMMUTABLE_CAPABILITY');
});
for (const allowed of ['openWrite', 'unlink', 'rename']) {
  test(`capability probe rejects when ${allowed} succeeds`, async () => {
    const adapter = {
      create: async () => {}, setImmutable: async () => {}, readAttrs: async () => '----i---------e-------',
      openWrite: async () => { throw new Error('EPERM'); }, unlink: async () => { throw new Error('EPERM'); }, rename: async () => { throw new Error('EPERM'); }, clearImmutable: async () => {}, remove: async () => {},
    };
    adapter[allowed] = async () => {};
    await assert.rejects(runCapabilityProbeSequence(adapter), (error) => error?.code === 'IMMUTABLE_CAPABILITY');
  });
}

test('builds exact redacted receipt', () => {
  const { receipt, authority } = receiptFixture();
  assert.equal(validateReceipt(receipt, authority.commit), true);
  assert.equal(Object.keys(receipt).length, 45);
  assert.equal(JSON.stringify(receipt).includes('service_role'), false);
  assert.equal(JSON.stringify(receipt).includes('token'), false);
  assert.equal(JSON.stringify(receipt).includes('password'), false);
});
test('receipt rejects an extra field even with valid inner values', () => {
  const { receipt, authority } = receiptFixture();
  expectCode('RECEIPT_SCHEMA', () => validateReceipt({ ...receipt, extra: true }, authority.commit));
});
test('receipt rejects a missing field', () => {
  const { receipt, authority } = receiptFixture();
  const changed = { ...receipt };
  delete changed.tool_manifest_sha256;
  expectCode('RECEIPT_SCHEMA', () => validateReceipt(changed, authority.commit));
});

for (const [name, mutate, code] of [
  ['schema', (r) => { r.schema_version = 2; }, 'RECEIPT_SCHEMA'],
  ['purpose', (r) => { r.purpose = 'other'; }, 'RECEIPT_SCHEMA'],
  ['architecture', (r) => { r.architecture = 'other'; }, 'RECEIPT_SCHEMA'],
  ['authority', (r) => { r.runtime_authority_commit = '0'.repeat(40); }, 'RECEIPT_AUTHORITY'],
  ['parent', (r) => { r.runtime_authority_parent = '0'.repeat(40); }, 'RECEIPT_AUTHORITY'],
  ['subject', (r) => { r.runtime_authority_subject = 'other'; }, 'RECEIPT_AUTHORITY'],
  ['source path', (r) => { r.source_path = '/tmp/node'; }, 'RECEIPT_SOURCE'],
  ['source hash', (r) => { r.source_sha256 = '0'.repeat(64); }, 'RECEIPT_SOURCE'],
  ['source immutable', (r) => { r.source_immutable = true; }, 'RECEIPT_SOURCE'],
  ['source role', (r) => { r.source_role = 'runtime'; }, 'RECEIPT_SOURCE'],
  ['uid', (r) => { r.capsule_uid = 1; }, 'RECEIPT_CAPSULE'],
  ['gid', (r) => { r.capsule_gid = 1; }, 'RECEIPT_CAPSULE'],
  ['mode', (r) => { r.capsule_mode = '0755'; }, 'RECEIPT_CAPSULE'],
  ['nlink', (r) => { r.capsule_nlink = 2; }, 'RECEIPT_CAPSULE'],
  ['node immutable', (r) => { r.capsule_node_immutable = false; }, 'RECEIPT_CAPSULE'],
  ['receipt immutable', (r) => { r.capsule_receipt_immutable = false; }, 'RECEIPT_CAPSULE'],
  ['directory immutable', (r) => { r.capsule_directory_immutable = false; }, 'RECEIPT_CAPSULE'],
  ['closure drift', (r) => { r.dynamic_closure_revalidated = false; }, 'RECEIPT_CAPSULE'],
  ['secret read', (r) => { r.secrets_read = true; }, 'RECEIPT_POLICY'],
  ['network', (r) => { r.network_calls = 1; }, 'RECEIPT_POLICY'],
  ['package write', (r) => { r.package_manager_write = true; }, 'RECEIPT_POLICY'],
  ['system mutation', (r) => { r.system_node_modified = true; }, 'RECEIPT_POLICY'],
  ['nvm mutation', (r) => { r.nvm_modified = true; }, 'RECEIPT_POLICY'],
  ['raw values', (r) => { r.raw_values_reported = true; }, 'RECEIPT_POLICY'],
  ['generation', (r) => { r.capsule_generation_id = 'bad'; }, 'RECEIPT_SCHEMA'],
  ['node digest', (r) => { r.capsule_node_sha256 = 'bad'; }, 'RECEIPT_SCHEMA'],
  ['identity digest', (r) => { r.capsule_node_identity_sha256 = 'bad'; }, 'RECEIPT_SCHEMA'],
]) {
  test(`receipt rejects ${name}`, () => {
    const { receipt, authority } = receiptFixture();
    const changed = structuredClone(receipt);
    mutate(changed);
    expectCode(code, () => validateReceipt(changed, authority.commit));
  });
}

test('sanitizeError emits only code', () => assert.equal(sanitizeError(Object.assign(new Error('sensitive'), { code: 'SAFE_CODE' })), 'ERROR SAFE_CODE'));
test('sanitizeError rejects unsafe code text', () => assert.equal(sanitizeError(Object.assign(new Error('sensitive'), { code: 'bad value' })), 'ERROR UNEXPECTED'));

const source = await readFile(new URL('./create-immutable-node-runtime-capsule.mjs', import.meta.url), 'utf8');
test('source never executes a package manager', () => assert.doesNotMatch(source, /(?:npm|pnpm|yarn|apt-get|dnf|yum)\s+(?:install|update)/));
test('source never writes the system Node', () => assert.doesNotMatch(source, /chattr\([^\n]*BOOTSTRAP_NODE/));
test('source never uses NVM runtime', () => assert.doesNotMatch(source, /spawnSync\([^\n]*\.nvm/));
test('source has no network module imports', () => assert.doesNotMatch(source, /node:(?:http|https|net|tls|dns)/));
test('source does not read any real secret path', () => {
  for (const secretPath of SECRET_PATHS) {
    const occurrences = source.split(secretPath).length - 1;
    assert.equal(occurrences, 1, 'secret path may appear only in the frozen denylist');
  }
});
test('source has no mutable current alias', () => assert.doesNotMatch(source, /path\.join\([^\n]*['"](?:current|latest)['"]/));
test('source has exactly one real chattr removal and it targets probe variable', () => {
  const removals = [...source.matchAll(/chattr\('-i',\s*([^,)]+)/g)].map((match) => match[1].trim());
  assert.deepEqual(removals, ['probePath']);
});
test('source never reports raw values', () => assert.doesNotMatch(source, /process\.(?:stdout|stderr)\.write\([^\n]*(?:origin|password|service_role|token)/i));
test('source uses exclusive no-follow claims and files', () => assert.match(source, /FS\.O_EXCL \| FS\.O_NOFOLLOW/));
test('source makes node receipt and directory immutable', () => {
  assert.match(source, /chattr\('\+i', path\.join\(finalPath, 'node'/);
  assert.match(source, /chattr\('\+i', path\.join\(finalPath, 'runtime\.receipt\.json'/);
  assert.match(source, /chattr\('\+i', finalPath/);
});
