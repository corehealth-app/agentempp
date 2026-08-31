import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  ARCHITECTURE, CLOSURE_ALGORITHM, BASELINE, RECEIPT_KEYS,
  parseMode, parseLddOutput, validateLoaderPath, normalizeSymlinkTarget,
  identity, physicalIdentitySha256, assertStableIdentity,
  resolveClosureEntryNoFollow, buildClosureManifest, publicClosureProjection,
  revalidateClosureCapture,
  classifyCreationStateV2, buildReceiptV2, validateReceiptV2,
  runCapabilityProbeSequence, runDurableCapabilityProbeSequence, runClaimCaptureStateMachine,
  runReceiptLastPublicationSequence,
  inspectRealBaselineReadOnly, sanitizeError, sha256,
} from './create-immutable-node-runtime-capsule-v2.mjs';

const S = (kind, overrides = {}) => ({
  uid: 0n, gid: 0n, mode: kind === 'dir' ? 0o40755n : kind === 'link' ? 0o120777n : 0o100555n,
  nlink: 1n, size: kind === 'file' ? 3n : 0n, mtimeNs: 1n, ctimeNs: 2n,
  dev: 3n, ino: BigInt(overrides.ino ?? (kind === 'dir' ? 10 : kind === 'link' ? 20 : 30)),
  isDirectory: () => kind === 'dir', isSymbolicLink: () => kind === 'link', isFile: () => kind === 'file',
  ...overrides,
  ino: BigInt(overrides.ino ?? (kind === 'dir' ? 10 : kind === 'link' ? 20 : 30)),
});

function adapter(entries) {
  return {
    lstat(p) { const x = entries[p]; if (!x) { const e = new Error('missing'); e.code = 'ENOENT'; throw e; } return x.stat; },
    readlink(p) { return entries[p].target; },
    openReadNoFollow(p) {
      const x = entries[p];
      if (!x || x.stat.isSymbolicLink()) throw Object.assign(new Error('nofollow'), { code: 'ELOOP' });
      return { statBefore: x.stat, bytes: Buffer.from(x.bytes ?? 'abc'), statAfter: x.stat, close() {} };
    },
  };
}

function directFixture() {
  return adapter({
    '/lib': { stat: S('dir', { ino: 11 }) },
    '/lib/a.so': { stat: S('file', { ino: 31 }), bytes: 'abc' },
  });
}

function intermediateFixture() {
  return adapter({
    '/lib': { stat: S('link', { ino: 21 }), target: '/usr/lib' },
    '/usr': { stat: S('dir', { ino: 12 }) },
    '/usr/lib': { stat: S('dir', { ino: 13 }) },
    '/usr/lib/a.so': { stat: S('file', { ino: 31 }), bytes: 'abc' },
  });
}

function finalFixture() {
  return adapter({
    '/lib': { stat: S('dir', { ino: 11 }) },
    '/lib/a.so': { stat: S('link', { ino: 22 }), target: 'real.so' },
    '/lib/real.so': { stat: S('file', { ino: 32 }), bytes: 'abc' },
  });
}

test('V2 architecture and full-path algorithm are exact', () => {
  assert.equal(ARCHITECTURE, 'PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V2');
  assert.equal(CLOSURE_ALGORITHM, 'NOFOLLOW_COMPONENT_CANONICALIZATION_V1');
});

for (const mode of ['--self-test', '--create', '--verify']) test(`closed CLI accepts ${mode}`, () => assert.equal(parseMode([mode]), mode.slice(2)));
for (const argv of [[], ['--bad'], ['--create', 'again'], ['create'], ['--verify', 'x']]) test(`closed CLI rejects ${JSON.stringify(argv)}`, () => assert.throws(() => parseMode(argv)));

test('parser handles arrow and direct loader entries and ignores addresses', () => {
  assert.deepEqual(parseLddOutput('liba.so.1 => /lib/a.so (0x1)\n/lib/b.so (0x2)\nlinux-vdso.so.1 (0x3)\n'), ['/lib/a.so', '/lib/b.so']);
});
for (const bad of ['a => not found\n', 'garbage\n', '/lib/a.so (0x1)\n/lib/a.so (0x2)\n', '/lib/a.so (0x1)\ngarbage => /lib/b.so (0x2)\n']) test(`parser rejects malformed or duplicate list ${sha256(Buffer.from(bad)).slice(0, 8)}`, () => assert.throws(() => parseLddOutput(bad)));
for (let i = 0; i < 20; i++) test(`parser ignores address variation ${i}`, () => assert.deepEqual(parseLddOutput(`/lib/a.so (0x${(i + 1).toString(16)})\n`), ['/lib/a.so']));

for (const good of ['/a', '/usr/lib/a.so', '/a-b/c_d.so']) test(`loader path accepts normalized absolute ${good}`, () => assert.deepEqual(validateLoaderPath(good), good.slice(1).split('/')));
for (const bad of ['', 'a', '/', '/a/', '/a//b', '/a/./b', '/a/../b', `/a\0b`, `/${'a'.repeat(4097)}`]) test(`loader path rejects invalid input ${sha256(Buffer.from(bad)).slice(0, 8)}`, () => assert.throws(() => validateLoaderPath(bad)));

for (const [base, target, want] of [[['a'], 'b', ['a', 'b']], [['a'], '/b', ['b']], [['a', 'b'], '../c', ['a', 'c']], [[], './a', ['a']]]) test(`target normalization ${base.join('.')}:${target}`, () => assert.deepEqual(normalizeSymlinkTarget(base, target), want));
for (const target of ['', '\0', '../a', '/../../a', 'a\0b', 'a'.repeat(4097)]) test(`target rejects unsafe ${sha256(Buffer.from(target)).slice(0, 8)}`, () => assert.throws(() => normalizeSymlinkTarget([], target)));

test('direct regular target traverses zero symlinks', () => {
  const x = resolveClosureEntryNoFollow('/lib/a.so', directFixture());
  assert.equal(x.traverses_any_symlink, false); assert.equal(x.final_component_regular, true); assert.equal(x.symlink_hop_count, 0);
});
test('intermediate symlink is not direct under full-path semantics', () => {
  const x = resolveClosureEntryNoFollow('/lib/a.so', intermediateFixture());
  assert.equal(x.traverses_any_symlink, true); assert.equal(x.final_component_symlink, false); assert.equal(x.intermediate_only_symlink, true); assert.equal(x.symlink_hop_count, 1);
});
test('final component symlink is classified independently', () => {
  const x = resolveClosureEntryNoFollow('/lib/a.so', finalFixture());
  assert.equal(x.traverses_any_symlink, true); assert.equal(x.final_component_symlink, true); assert.equal(x.intermediate_only_symlink, false); assert.equal(x.symlink_hop_count, 1);
});
test('symlink cycle is rejected', () => {
  const a=adapter({'/a':{stat:S('link',{ino:41}),target:'/b'},'/b':{stat:S('link',{ino:42}),target:'/a'}}); assert.throws(()=>resolveClosureEntryNoFollow('/a',a));
});
test('group writable parent is rejected', () => {
  const a=adapter({'/lib':{stat:S('dir',{mode:0o40775n})},'/lib/a.so':{stat:S('file'),bytes:'abc'}}); assert.throws(()=>resolveClosureEntryNoFollow('/lib/a.so',a));
});
test('hardlinked final target is rejected', () => {
  const a=adapter({'/lib':{stat:S('dir')},'/lib/a.so':{stat:S('file',{nlink:2n}),bytes:'abc'}}); assert.throws(()=>resolveClosureEntryNoFollow('/lib/a.so',a));
});
test('non-root symlink is rejected', () => {
  const a=adapter({'/lib':{stat:S('link',{uid:1n}),target:'/usr/lib'},'/usr':{stat:S('dir')},'/usr/lib':{stat:S('dir')},'/usr/lib/a.so':{stat:S('file'),bytes:'abc'}}); assert.throws(()=>resolveClosureEntryNoFollow('/lib/a.so',a));
});

for (const field of Object.keys(BASELINE)) test(`corrected baseline freezes ${field}`, () => assert.notEqual(BASELINE[field], undefined));
test('corrected dimensions obey independent arithmetic', () => {
  assert.equal(BASELINE.loader_entry_count, BASELINE.traverses_any_symlink_count + BASELINE.traverses_zero_symlink_count);
  assert.equal(BASELINE.loader_entry_count, BASELINE.final_component_symlink_count + BASELINE.final_component_regular_count);
  assert.equal(BASELINE.loader_entry_count, BASELINE.final_component_symlink_count + BASELINE.intermediate_only_symlink_count);
});

for (let i = 0; i < 45; i++) test(`BigInt identity detects physical drift ${i}`, () => {
  const a = S('file', { ino: 100 + i }); const b = S('file', { ino: 101 + i });
  assert.notEqual(physicalIdentitySha256(a), physicalIdentitySha256(b));
  assert.throws(() => assertStableIdentity(a, b));
});

test('closure projection omits raw paths', () => {
  const c = buildClosureManifest(['/lib/a.so'], directFixture());
  const p = publicClosureProjection(c);
  assert.equal(JSON.stringify(p).includes('/lib/'), false);
});
test('duplicate canonical identity is rejected', () => {
  const a = directFixture(); assert.throws(() => buildClosureManifest(['/lib/a.so', '/lib/a.so'], a));
});
test('captured closure revalidation detects physical drift without ldd', () => {
  const a=directFixture(),capture=buildClosureManifest(['/lib/a.so'],a); assert.equal(revalidateClosureCapture(capture,a),true);
  capture.closure_manifest_sha256='0'.repeat(64); assert.throws(()=>revalidateClosureCapture(capture,a));
});

for (const state of [
  [{ claim: false, capture: false, final: false, staging: false, probe: false }, 'FRESH'],
  [{ claim: true, capture: true, final: true, staging: false, probe: false }, 'VERIFY_EXACT_EXISTING'],
  [{ claim: true, capture: true, final: false, staging: false, probe: false }, 'RESUME_CAPTURED'],
]) test(`creation state ${state[1]}`, () => assert.equal(classifyCreationStateV2(state[0]), state[1]));
for (const s of [
  { claim: false, capture: true, final: false, staging: false, probe: false },
  { claim: true, capture: false, final: false, staging: false, probe: false },
  { claim: false, capture: false, final: true, staging: false, probe: false },
]) test(`unsafe creation state is terminal ${JSON.stringify(s)}`, () => assert.throws(() => classifyCreationStateV2(s)));

const receiptFixture = () => buildReceiptV2({ authority: 'a'.repeat(40), tree: 'b'.repeat(40), builderBlob: 'c'.repeat(40), builderHash: 'd'.repeat(64), claimHash: 'e'.repeat(64), captureHash: 'f'.repeat(64), nodeIdentity: '1'.repeat(64), receiptTime: '2099-01-01T00:00:00.000Z' });
test('receipt V2 validates exact schema and corrected terminology', () => assert.equal(validateReceiptV2(receiptFixture()), true));
for (const key of RECEIPT_KEYS) test(`receipt rejects mutation of ${key}`, () => {
  const r = structuredClone(receiptFixture()); delete r[key]; assert.throws(() => validateReceiptV2(r));
});
test('receipt rejects ambiguous direct_entry_count spelling', () => {
  const r = { ...receiptFixture(), direct_entry_count: 5 }; assert.throws(() => validateReceiptV2(r));
});
for (const key of ['source_path_sha256','source_sha256','capsule_node_sha256','capsule_uid','capsule_gid','capsule_mode','capsule_nlink']) test(`receipt rejects valid-looking static binding drift in ${key}`, () => {
  const r=structuredClone(receiptFixture());r[key]=typeof r[key]==='string'&&r[key].length===64?'f'.repeat(64):typeof r[key]==='number'?r[key]+1:'0444';assert.throws(()=>validateReceiptV2(r));
});

test('capability probe enforces immutable denial sequence', async () => {
  const calls=[]; const reject=async()=>{calls.push('deny');throw Error('denied')};
  const r=await runCapabilityProbeSequence({create:async()=>calls.push('create'),setImmutable:async()=>calls.push('set'),readAttrs:async()=>'----i',openWrite:reject,unlink:reject,rename:reject,clearImmutable:async()=>calls.push('clear'),remove:async()=>calls.push('remove')});
  assert.equal(r.cleaned, true); assert.deepEqual(calls, ['create','set','deny','deny','deny','clear','remove']);
});
test('durable capability receipt precedes cleanup and closes the retry window', async () => {
  const calls=[];const reject=async()=>{calls.push('deny');throw Error('denied')};
  const result=await runDurableCapabilityProbeSequence({create:async()=>calls.push('create'),setImmutable:async()=>calls.push('set'),readAttrs:async()=>'----i',openWrite:reject,unlink:reject,rename:reject,writeReceipt:async()=>calls.push('receipt'),fsyncReceipt:async()=>calls.push('receipt-fsync'),clearImmutable:async()=>calls.push('clear'),remove:async()=>calls.push('remove'),fsyncCleanup:async()=>calls.push('cleanup-fsync')});
  assert.equal(result.rename_rejected,true);assert.deepEqual(calls,['create','set','deny','deny','deny','receipt','receipt-fsync','clear','remove','cleanup-fsync']);
});
test('publication freezes the final Node identity before writing receipt last', async () => {
  const calls=[];
  await runReceiptLastPublicationSequence({linkNode:async()=>calls.push('link'),unlinkStaged:async()=>calls.push('unlink-staged'),freezeNode:async()=>calls.push('freeze-node'),readNodeIdentity:async()=>{calls.push('identity');return 'id'},buildReceipt:async identity=>{assert.equal(identity,'id');calls.push('build-receipt');return 'receipt'},writeReceipt:async receipt=>{assert.equal(receipt,'receipt');calls.push('write-receipt')},fsyncReceipt:async()=>calls.push('receipt-fsync'),removeStaging:async()=>calls.push('remove-staging'),freezeReceipt:async()=>calls.push('freeze-receipt'),sealDirectory:async()=>calls.push('seal-directory'),fsyncParent:async()=>calls.push('parent-fsync')});
  assert.deepEqual(calls,['link','unlink-staged','freeze-node','identity','build-receipt','write-receipt','receipt-fsync','remove-staging','freeze-receipt','seal-directory','parent-fsync']);
});

test('claim and parent fsync happen before operational ldd and durable capture', async () => {
  const calls=[];
  await runClaimCaptureStateMachine({
    writeClaim: async()=>calls.push('claim'), fsyncClaim:async()=>calls.push('claim-fsync'),
    spawnLdd:async()=>{calls.push('ldd');return 'x'}, buildCapture:async()=>{calls.push('canonicalize');return {ok:true}},
    writeCapture:async()=>calls.push('capture'), fsyncCapture:async()=>calls.push('capture-fsync'),
  });
  assert.deepEqual(calls, ['claim','claim-fsync','ldd','canonicalize','capture','capture-fsync']);
});
test('claim failure prevents operational ldd', async () => {
  let ldd=0; await assert.rejects(runClaimCaptureStateMachine({writeClaim:async()=>{throw Error('collision')},fsyncClaim:async()=>{},spawnLdd:async()=>{ldd++;},buildCapture:async()=>{},writeCapture:async()=>{},fsyncCapture:async()=>{}})); assert.equal(ldd,0);
});

test('real read-only closure reproduces corrected baseline without raw terminal paths', () => {
  const result = inspectRealBaselineReadOnly();
  for (const [key,value] of Object.entries(BASELINE)) assert.equal(result[key], value);
  assert.equal(JSON.stringify(publicClosureProjection(result)).includes('/lib'), false);
});

for (const sourcePattern of [
  /realpath\s*\(/, /readlink\s+-f/, /\/proc\/self\/fd/, /node:(http|https|net|tls|dns)/,
  /direct_entry_count\s*:/, /chattr[^\n]*\/usr\/bin\/node/,
]) test(`source excludes forbidden pattern ${sourcePattern}`, () => {
  const source = fs.readFileSync(new URL('./create-immutable-node-runtime-capsule-v2.mjs', import.meta.url), 'utf8'); assert.equal(sourcePattern.test(source), false);
});

for (let i = 0; i < 35; i++) test(`digest binding mutation ${i}`, () => {
  const value = { a: i, b: 'x', c: true }; const changed = { ...value, a: i + 1 };
  assert.notEqual(sha256(Buffer.from(JSON.stringify(value))), sha256(Buffer.from(JSON.stringify(changed))));
});

test('sanitized error never exposes message', () => assert.equal(sanitizeError(Object.assign(new Error('/secret/path'), { code: 'SAFE_CODE' })), 'ERROR SAFE_CODE'));
