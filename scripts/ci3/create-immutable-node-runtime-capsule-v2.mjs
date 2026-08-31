import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const ARCHITECTURE = 'PRIVATE_VERSIONED_IMMUTABLE_NODE_RUNTIME_CAPSULE_V2';
export const CLOSURE_ALGORITHM = 'NOFOLLOW_COMPONENT_CANONICALIZATION_V1';
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

const AUTHORITY_PARENT = 'bd2ffd96e3742474ed0126845f5e6192f3bacb01';
const AUTHORITY_SUBJECT = 'build(ops): authorize full-path no-follow Node closure capsule';
const V1_AUTHORITY = 'f039fe38b35084a33a4b7a3649b1112f26a93fb2';
const V1_STOP = AUTHORITY_PARENT;
const BRIDGE_AUTHORITY = 'ba8473799a19aec586b0fe706bb7d4084589c86c';
const BOOTSTRAP = '/usr/bin/node';
const BOOTSTRAP_SHA = '6295488653f0d93b0a157841746fef7e72cc4328cfb60c4bbe0ca2668a836ffd';
const RUNTIME_ROOT = '/root/.config/agentempp/runtimes/node';
const BUILDER_REL = 'scripts/ci3/create-immutable-node-runtime-capsule-v2.mjs';
const SCRIPT_PATH = fileURLToPath(import.meta.url);
const F = fs.constants;
const MAX_PATH_BYTES = 4096;
const MAX_FILE_BYTES = 256 * 1024 * 1024;
const MAX_HOPS = 40;
const SHA40 = /^[0-9a-f]{40}$/;
const SHA64 = /^[0-9a-f]{64}$/;
const AUTHORITY_PATHS = Object.freeze([
  'docs/handoffs/2026-08-20-better-ahead-contexto-completo-e-finalizacao.md',
  'docs/superpowers/evidence/2026-08-31-ci3-node-runtime-canonical-closure-v2-authority.md',
  'docs/superpowers/specs/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-29-ci3-versioned-bridge-bundle.md',
  'docs/superpowers/plans/2026-08-20-naming-neutral-core-integration.md',
  BUILDER_REL,
  'scripts/ci3/create-immutable-node-runtime-capsule-v2.test.mjs',
]);
const TOOL_PATHS = Object.freeze(['/usr/bin/node','/usr/bin/ldd','/usr/bin/chattr','/usr/bin/lsattr','/usr/bin/git','/usr/bin/findmnt','/usr/bin/readelf','/usr/bin/sha256sum','/usr/bin/stat']);

class CapsuleError extends Error { constructor(code) { super(code); this.code = code; } }
const fail = (code) => { throw new CapsuleError(code); };
export const sha256 = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');
const jsonBytes = (value) => `${JSON.stringify(value, null, 2)}\n`;
const gitBlobOid = (bytes) => crypto.createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`), bytes])).digest('hex');

export function sanitizeError(error) {
  const code = typeof error?.code === 'string' && /^[A-Z0-9_]+$/.test(error.code) ? error.code : 'UNEXPECTED';
  return `ERROR ${code}`;
}

export function parseMode(argv) {
  if (!Array.isArray(argv) || argv.length !== 1 || !['--self-test','--create','--verify'].includes(argv[0])) fail('ARGV');
  return argv[0].slice(2);
}

const toBig = (v) => typeof v === 'bigint' ? v : typeof v === 'string' && /^\d+$/.test(v) ? BigInt(v) : fail('IDENTITY');
export function identity(s) {
  return { uid:toBig(s.uid),gid:toBig(s.gid),mode:toBig(s.mode),nlink:toBig(s.nlink),size:toBig(s.size),mtimeNs:toBig(s.mtimeNs),ctimeNs:toBig(s.ctimeNs),dev:toBig(s.dev),ino:toBig(s.ino) };
}
const identityText = (s) => { const x=identity(s); return `${x.uid};${x.gid};${x.mode};${x.nlink};${x.size};${x.mtimeNs};${x.ctimeNs};${x.dev};${x.ino}`; };
export const physicalIdentitySha256 = (s) => sha256(Buffer.from(identityText(s)));
export function assertStableIdentity(a,b,code='IDENTITY_DRIFT') { if (identityText(a)!==identityText(b)) fail(code); return true; }
const safe = (v,code='INTEGER') => { const b=toBig(v),n=Number(b); if(!Number.isSafeInteger(n)||BigInt(n)!==b)fail(code); return n; };

export function validateLoaderPath(input) {
  if (typeof input !== 'string' || Buffer.from(input).toString('utf8') !== input || !input.startsWith('/') || input.endsWith('/') || input.includes('\0') || Buffer.byteLength(input)>MAX_PATH_BYTES) fail('LOADER_PATH');
  const parts=input.slice(1).split('/'); if(!parts.length||parts.some(x=>!x||x==='.'||x==='..'))fail('LOADER_PATH'); return parts;
}
export function normalizeSymlinkTarget(base,target) {
  if(typeof target!=='string'||Buffer.from(target).toString('utf8')!==target||!target||target.includes('\0')||Buffer.byteLength(target)>MAX_PATH_BYTES)fail('DYNAMIC_CLOSURE_CANONICALIZATION');
  const out=target.startsWith('/')?[]:[...base]; for(const x of target.split('/')){if(!x||x==='.')continue;if(x==='..'){if(!out.length)fail('DYNAMIC_CLOSURE_CANONICALIZATION');out.pop();}else out.push(x);} if(!out.length)fail('DYNAMIC_CLOSURE_CANONICALIZATION'); return out;
}

export function parseLddOutput(text) {
  const value=String(text); if(/=>\s+not found/.test(value))fail('DYNAMIC_CLOSURE'); const paths=[];
  for(const line of value.split('\n')){const trimmed=line.trim();if(!trimmed)continue;const a=trimmed.match(/^[^\s/]+\.so[^\s]*\s+=>\s+(\/[^\s]+)\s+\(0x[0-9a-f]+\)$/i),d=trimmed.match(/^(\/[^\s]+)\s+\(0x[0-9a-f]+\)$/i),p=a?.[1]??d?.[1];if(p)paths.push(p);else if(!/^[^\s/]+\s+\(0x[0-9a-f]+\)$/i.test(trimmed))fail('DYNAMIC_CLOSURE');}
  if(!paths.length||new Set(paths).size!==paths.length)fail('DYNAMIC_CLOSURE'); return paths.sort();
}

function realAdapter() {
  return {
    lstat: (p) => fs.lstatSync(p,{bigint:true}),
    readlink: (p) => fs.readlinkSync(p,'utf8'),
    openReadNoFollow(p) {
      const fd=fs.openSync(p,F.O_RDONLY|F.O_NOFOLLOW); let closed=false;
      return { statBefore:fs.fstatSync(fd,{bigint:true}), bytes:fs.readFileSync(fd), statAfter:fs.fstatSync(fd,{bigint:true}), close(){if(!closed){fs.closeSync(fd);closed=true;}} };
    },
  };
}

function requireRoot(metadata,code) { if(toBig(metadata.uid)!==0n||toBig(metadata.gid)!==0n)fail(code); }
function requireTrustedDirectory(s){requireRoot(s,'DYNAMIC_CLOSURE_CANONICALIZATION');if(!s.isDirectory?.()||s.isSymbolicLink?.()||(toBig(s.mode)&0o022n)!==0n)fail('DYNAMIC_CLOSURE_CANONICALIZATION');}

export function resolveClosureEntryNoFollow(loaderPath, adapter=realAdapter()) {
  let pending=validateLoaderPath(loaderPath),resolved=[],hops=0,finalLink=false; const seen=new Set(),records=[],links=[],parents=[];
  while(pending.length){
    const component=pending.shift(),candidate=`/${[...resolved,component].join('/')}`; let before;
    try{before=adapter.lstat(candidate);}catch{fail('DYNAMIC_CLOSURE_CANONICALIZATION');} requireRoot(before,'DYNAMIC_CLOSURE_CANONICALIZATION');
    if(before.isSymbolicLink?.()){
      if(toBig(before.nlink)!==1n)fail('DYNAMIC_CLOSURE_CANONICALIZATION'); if(pending.length===0)finalLink=true;
      let target1,target2,after; try{target1=adapter.readlink(candidate);after=adapter.lstat(candidate);target2=adapter.readlink(candidate);}catch{fail('DYNAMIC_CLOSURE_CANONICALIZATION');}
      assertStableIdentity(before,after,'DYNAMIC_CLOSURE_CANONICALIZATION'); if(target1!==target2)fail('DYNAMIC_CLOSURE_CANONICALIZATION');
      if(++hops>MAX_HOPS)fail('DYNAMIC_CLOSURE_CANONICALIZATION'); const targetHash=sha256(Buffer.from(target1)),cycle=`${before.dev};${before.ino};${targetHash}`; if(seen.has(cycle))fail('DYNAMIC_CLOSURE_CANONICALIZATION');seen.add(cycle);
      const rec={kind:'link',path:candidate,identity:identityText(before),target:target1};records.push(rec);links.push([sha256(Buffer.from(candidate)),targetHash,physicalIdentitySha256(before)]);
      pending=[...normalizeSymlinkTarget(resolved,target1),...pending];resolved=[];continue;
    }
    if(pending.length){requireTrustedDirectory(before);records.push({kind:'dir',path:candidate,identity:identityText(before)});parents.push([sha256(Buffer.from(candidate)),physicalIdentitySha256(before)]);resolved.push(component);continue;}
    if(!before.isFile?.()||before.isSymbolicLink?.()||toBig(before.nlink)!==1n||(toBig(before.mode)&0o022n)!==0n)fail('DYNAMIC_CLOSURE_CANONICALIZATION');
    let opened;try{opened=adapter.openReadNoFollow(candidate);}catch{fail('DYNAMIC_CLOSURE_CANONICALIZATION');}
    try{assertStableIdentity(before,opened.statBefore,'DYNAMIC_CLOSURE_CANONICALIZATION');if(toBig(opened.statBefore.size)>BigInt(MAX_FILE_BYTES)||BigInt(opened.bytes.length)!==toBig(opened.statBefore.size))fail('DYNAMIC_CLOSURE_CANONICALIZATION');assertStableIdentity(opened.statBefore,opened.statAfter,'DYNAMIC_CLOSURE_CANONICALIZATION');}finally{opened.close();}
    const end=adapter.lstat(candidate);assertStableIdentity(opened.statAfter,end,'DYNAMIC_CLOSURE_CANONICALIZATION');
    for(const rec of records){const current=adapter.lstat(rec.path);if(identityText(current)!==rec.identity)fail('DYNAMIC_CLOSURE_CANONICALIZATION');if(rec.kind==='link'&&adapter.readlink(rec.path)!==rec.target)fail('DYNAMIC_CLOSURE_CANONICALIZATION');}
    const canonicalPath=candidate;
    return {
      original_loader_path:loaderPath, original_loader_path_sha256:sha256(Buffer.from(loaderPath)), canonical_path:canonicalPath, canonical_path_sha256:sha256(Buffer.from(canonicalPath)),
      traverses_any_symlink:hops>0, traverses_zero_symlink:hops===0, final_component_symlink:finalLink, final_component_regular:!finalLink, intermediate_only_symlink:hops>0&&!finalLink,
      symlink_hop_count:hops, ordered_symlink_chain:links, symlink_chain_sha256:sha256(Buffer.from(JSON.stringify(links))), parent_chain:parents, parent_chain_sha256:sha256(Buffer.from(JSON.stringify(parents))),
      canonical_content_sha256:sha256(opened.bytes), canonical_identity_sha256:physicalIdentitySha256(opened.statAfter), canonical_identity_key:`${opened.statAfter.dev}:${opened.statAfter.ino}`,
      bytes:safe(opened.statAfter.size), mode:(safe(opened.statAfter.mode)&0o777).toString(8).padStart(4,'0'), uid:safe(opened.statAfter.uid), gid:safe(opened.statAfter.gid), nlink:safe(opened.statAfter.nlink), algorithm:CLOSURE_ALGORITHM,
      compatibility_projection:{original:sha256(Buffer.from(loaderPath)),canonical:sha256(Buffer.from(canonicalPath)),classification:hops?'symlink':'direct',hops,links:sha256(Buffer.from(JSON.stringify(links))),parents:sha256(Buffer.from(JSON.stringify(parents))),content:sha256(opened.bytes),identity:physicalIdentitySha256(opened.statAfter)},
    };
  }
  fail('DYNAMIC_CLOSURE_CANONICALIZATION');
}

export function buildClosureManifest(paths,adapter=realAdapter()) {
  if(!Array.isArray(paths)||!paths.length||new Set(paths).size!==paths.length)fail('DYNAMIC_CLOSURE'); const sorted=[...paths].sort(),entries=sorted.map(p=>resolveClosureEntryNoFollow(p,adapter)),ids=entries.map(e=>e.canonical_identity_key);
  if(new Set(ids).size!==ids.length)fail('DYNAMIC_CLOSURE'); const compatibility=entries.map(e=>e.compatibility_projection).sort((a,b)=>a.original.localeCompare(b.original));
  return {
    loader_entry_count:entries.length,
    traverses_any_symlink_count:entries.filter(e=>e.traverses_any_symlink).length,
    traverses_zero_symlink_count:entries.filter(e=>e.traverses_zero_symlink).length,
    final_component_symlink_count:entries.filter(e=>e.final_component_symlink).length,
    final_component_regular_count:entries.filter(e=>e.final_component_regular).length,
    intermediate_only_symlink_count:entries.filter(e=>e.intermediate_only_symlink).length,
    total_symlink_hops:entries.reduce((n,e)=>n+e.symlink_hop_count,0),max_symlink_hops:Math.max(...entries.map(e=>e.symlink_hop_count)),canonical_regular_target_count:new Set(ids).size,
    duplicate_loader_path_count:paths.length-new Set(paths).size,duplicate_canonical_identity_count:ids.length-new Set(ids).size,
    closure_path_list_sha256:sha256(Buffer.from(`${sorted.join('\n')}\n`)),closure_manifest_sha256:sha256(Buffer.from(JSON.stringify(compatibility))),closure_content_set_sha256:sha256(Buffer.from(`${[...new Set(entries.map(e=>e.canonical_content_sha256))].sort().join('\n')}\n`)),
    entries,
  };
}

export function revalidateClosureCapture(capture,adapter=realAdapter()) {
  if(!capture||!Array.isArray(capture.entries)||!capture.entries.length)fail('CAPTURE');
  const loaderPaths=capture.entries.map(entry=>entry?.original_loader_path);
  if(loaderPaths.some(value=>typeof value!=='string')||new Set(loaderPaths).size!==loaderPaths.length)fail('CAPTURE');
  const rebuilt=buildClosureManifest(loaderPaths,adapter),projection=publicClosureProjection(rebuilt);
  for(const [key,value] of Object.entries(projection))if(JSON.stringify(capture[key])!==JSON.stringify(value))fail('CAPTURE_DRIFT');
  if(JSON.stringify(capture.entries)!==JSON.stringify(rebuilt.entries))fail('CAPTURE_DRIFT');
  return true;
}

export function publicClosureProjection(closure) { const out={...closure};delete out.entries;return out; }
function assertBaseline(c){for(const [k,v] of Object.entries(BASELINE))if(c[k]!==v)fail('DYNAMIC_CLOSURE_BASELINE');return true;}

export function inspectRealBaselineReadOnly() {
  const raw=run('/usr/bin/ldd',[BOOTSTRAP],{code:'DYNAMIC_CLOSURE',encoding:'utf8'}).stdout; const closure=buildClosureManifest(parseLddOutput(raw));assertBaseline(closure);return publicClosureProjection(closure);
}

export function classifyCreationStateV2(s){for(const k of ['claim','capture','final','staging','probe'])if(typeof s?.[k]!=='boolean')fail('CREATION_STATE');if(!s.claim&&!s.capture&&!s.final&&!s.staging&&!s.probe)return'FRESH';if(s.claim&&s.capture&&s.final&&!s.staging&&!s.probe)return'VERIFY_EXACT_EXISTING';if(s.claim&&s.capture&&!s.final&&!s.staging&&!s.probe)return'RESUME_CAPTURED';if(!s.claim)fail('UNCLAIMED_STATE');if(s.claim&&!s.capture)fail('CLAIM_CONSUMED_CLOSURE_NOT_CAPTURED');fail('PARTIAL_STATE');}

export async function runClaimCaptureStateMachine(a){for(const k of ['writeClaim','fsyncClaim','spawnLdd','buildCapture','writeCapture','fsyncCapture'])if(typeof a?.[k]!=='function')fail('CLAIM_CAPTURE');await a.writeClaim();await a.fsyncClaim();const raw=await a.spawnLdd();const capture=await a.buildCapture(raw);await a.writeCapture(capture);await a.fsyncCapture();return capture;}
export async function runCapabilityProbeSequence(a){for(const k of ['create','setImmutable','readAttrs','openWrite','unlink','rename','clearImmutable','remove'])if(typeof a?.[k]!=='function')fail('IMMUTABLE_CAPABILITY');await a.create();await a.setImmutable();if(!String(await a.readAttrs()).split(/\s+/)[0].includes('i'))fail('IMMUTABLE_CAPABILITY');for(const op of [a.openWrite,a.unlink,a.rename]){let denied=false;try{await op();}catch{denied=true;}if(!denied)fail('IMMUTABLE_CAPABILITY');}await a.clearImmutable();await a.remove();return{attempted:1,immutable_set:true,write_rejected:true,unlink_rejected:true,rename_rejected:true,cleaned:true};}
export async function runDurableCapabilityProbeSequence(a){for(const k of ['create','setImmutable','readAttrs','openWrite','unlink','rename','writeReceipt','fsyncReceipt','clearImmutable','remove','fsyncCleanup'])if(typeof a?.[k]!=='function')fail('IMMUTABLE_CAPABILITY');await a.create();await a.setImmutable();if(!String(await a.readAttrs()).split(/\s+/)[0].includes('i'))fail('IMMUTABLE_CAPABILITY');for(const op of [a.openWrite,a.unlink,a.rename]){let denied=false;try{await op();}catch{denied=true;}if(!denied)fail('IMMUTABLE_CAPABILITY');}const result={attempted:1,immutable_set:true,write_rejected:true,unlink_rejected:true,rename_rejected:true};await a.writeReceipt(result);await a.fsyncReceipt();await a.clearImmutable();await a.remove();await a.fsyncCleanup();return result;}
export async function runReceiptLastPublicationSequence(a){for(const k of ['linkNode','unlinkStaged','freezeNode','readNodeIdentity','buildReceipt','writeReceipt','fsyncReceipt','removeStaging','freezeReceipt','sealDirectory','fsyncParent'])if(typeof a?.[k]!=='function')fail('PUBLICATION');await a.linkNode();await a.unlinkStaged();await a.freezeNode();const nodeIdentity=await a.readNodeIdentity(),receipt=await a.buildReceipt(nodeIdentity);await a.writeReceipt(receipt);await a.fsyncReceipt();await a.removeStaging();await a.freezeReceipt();await a.sealDirectory();await a.fsyncParent();return{nodeIdentity,receipt};}

export const RECEIPT_KEYS = Object.freeze([
  'architecture','authority_manifest_sha256','builder_blob_oid','builder_sha256','canonical_regular_target_count','capability_probe','capsule_directory_immutable','capsule_generation_id','capsule_gid','capsule_mode','capsule_nlink','capsule_node_identity_sha256','capsule_node_immutable','capsule_node_path_sha256','capsule_node_sha256','capsule_receipt_immutable','capsule_uid','chattr_sha256','closure_algorithm','closure_capture_sha256','closure_claim_sha256','closure_content_set_sha256','closure_manifest_sha256','closure_path_list_sha256','created_at_utc','duplicate_canonical_identity_count','duplicate_loader_path_count','dynamic_closure_count','dynamic_closure_revalidated','dynamic_closure_sha256','filesystem_descriptor_sha256','final_component_regular_count','final_component_symlink_count','intermediate_only_symlink_count','loader_entry_count','lsattr_sha256','max_symlink_hops','network_calls','nofollow_final_open','nvm_modified','package_manager_write','parent_chain_group_other_writable','parent_chain_root_owned','purpose','raw_paths_reported','raw_values_reported','readlink_f_used','realpath_used','runtime_authority_commit','runtime_authority_parent','runtime_authority_subject','runtime_authority_tree','runtime_v1_attempt_consumed','runtime_v1_authority_sha','runtime_v1_stop_sha','runtime_v2_attempt','runtime_v2_retry','schema_version','secrets_read','source_and_capsule_closure_match','source_identity_sha256','source_immutable','source_parent_chain_sha256','source_path','source_path_sha256','source_process_versions_sha256','source_role','source_sha256','source_version','stat_follow_used','system_node_modified','tool_manifest_sha256','total_symlink_hops','traverses_any_symlink_count','traverses_zero_symlink_count',
].sort());

export function buildReceiptV2({authority,tree,builderBlob,builderHash,claimHash,captureHash,nodeIdentity,receiptTime,extra={}}){
  const r={schema_version:2,purpose:'CI3_PRIVATE_IMMUTABLE_NODE_RUNTIME_CAPSULE_V2',architecture:ARCHITECTURE,closure_algorithm:CLOSURE_ALGORITHM,runtime_authority_commit:authority,runtime_authority_parent:AUTHORITY_PARENT,runtime_authority_tree:tree,runtime_authority_subject:AUTHORITY_SUBJECT,authority_manifest_sha256:extra.authority_manifest_sha256??'2'.repeat(64),builder_blob_oid:builderBlob,builder_sha256:builderHash,runtime_v1_authority_sha:V1_AUTHORITY,runtime_v1_stop_sha:V1_STOP,runtime_v1_attempt_consumed:true,runtime_v2_attempt:1,runtime_v2_retry:false,closure_claim_sha256:claimHash,closure_capture_sha256:captureHash,source_path:BOOTSTRAP,source_path_sha256:sha256(Buffer.from(BOOTSTRAP)),source_sha256:BOOTSTRAP_SHA,source_version:extra.source_version??'v20.20.2',source_identity_sha256:extra.source_identity_sha256??'3'.repeat(64),source_parent_chain_sha256:extra.source_parent_chain_sha256??'4'.repeat(64),source_process_versions_sha256:extra.source_process_versions_sha256??'5'.repeat(64),source_immutable:false,source_role:'bootstrap_only',...BASELINE,dynamic_closure_count:BASELINE.loader_entry_count,dynamic_closure_sha256:BASELINE.closure_manifest_sha256,dynamic_closure_revalidated:true,source_and_capsule_closure_match:true,parent_chain_root_owned:true,parent_chain_group_other_writable:false,nofollow_final_open:true,realpath_used:false,readlink_f_used:false,stat_follow_used:false,raw_paths_reported:false,capsule_generation_id:`node-${BOOTSTRAP_SHA}`,capsule_node_path_sha256:extra.capsule_node_path_sha256??'6'.repeat(64),capsule_node_sha256:BOOTSTRAP_SHA,capsule_node_identity_sha256:nodeIdentity,capsule_uid:0,capsule_gid:0,capsule_mode:'0555',capsule_nlink:1,capsule_node_immutable:true,capsule_receipt_immutable:true,capsule_directory_immutable:true,capability_probe:extra.capability_probe??{attempted:1,immutable_set:true,write_rejected:true,unlink_rejected:true,rename_rejected:true},chattr_sha256:extra.chattr_sha256??'7'.repeat(64),lsattr_sha256:extra.lsattr_sha256??'8'.repeat(64),filesystem_descriptor_sha256:extra.filesystem_descriptor_sha256??'9'.repeat(64),tool_manifest_sha256:extra.tool_manifest_sha256??'a'.repeat(64),secrets_read:false,network_calls:0,package_manager_write:false,system_node_modified:false,nvm_modified:false,raw_values_reported:false,created_at_utc:receiptTime};return Object.freeze(r);
}
export function validateReceiptV2(r){if(!r||Object.keys(r).length!==RECEIPT_KEYS.length)fail('RECEIPT_SCHEMA');const keys=Object.keys(r).sort();for(let i=0;i<keys.length;i++)if(keys[i]!==RECEIPT_KEYS[i])fail('RECEIPT_SCHEMA');if(r.schema_version!==2||r.architecture!==ARCHITECTURE||r.closure_algorithm!==CLOSURE_ALGORITHM||r.runtime_authority_parent!==AUTHORITY_PARENT||r.runtime_v1_authority_sha!==V1_AUTHORITY||r.runtime_v1_stop_sha!==V1_STOP||r.runtime_v1_attempt_consumed!==true||r.runtime_v2_attempt!==1||r.runtime_v2_retry!==false||r.source_path!==BOOTSTRAP||r.source_path_sha256!==sha256(Buffer.from(BOOTSTRAP))||r.source_sha256!==BOOTSTRAP_SHA||r.source_role!=='bootstrap_only'||r.capsule_generation_id!==`node-${BOOTSTRAP_SHA}`||r.capsule_node_sha256!==BOOTSTRAP_SHA||r.capsule_uid!==0||r.capsule_gid!==0||r.capsule_mode!=='0555'||r.capsule_nlink!==1)fail('RECEIPT_SCHEMA');for(const k of ['runtime_authority_commit','runtime_authority_tree','builder_blob_oid'])if(!SHA40.test(r[k]))fail('RECEIPT_SCHEMA');for(const k of ['authority_manifest_sha256','builder_sha256','closure_claim_sha256','closure_capture_sha256','source_sha256','source_identity_sha256','source_parent_chain_sha256','source_process_versions_sha256','capsule_node_path_sha256','capsule_node_sha256','capsule_node_identity_sha256','chattr_sha256','lsattr_sha256','filesystem_descriptor_sha256','tool_manifest_sha256'])if(!SHA64.test(r[k]))fail('RECEIPT_SCHEMA');const capabilityKeys=['attempted','immutable_set','rename_rejected','unlink_rejected','write_rejected'].sort();if(!r.capability_probe||JSON.stringify(Object.keys(r.capability_probe).sort())!==JSON.stringify(capabilityKeys)||r.capability_probe.attempted!==1||Object.entries(r.capability_probe).some(([k,v])=>k!=='attempted'&&v!==true))fail('RECEIPT_SCHEMA');assertBaseline(r);if(r.dynamic_closure_count!==BASELINE.loader_entry_count||r.dynamic_closure_sha256!==BASELINE.closure_manifest_sha256)fail('RECEIPT_SCHEMA');for(const k of ['dynamic_closure_revalidated','source_and_capsule_closure_match','parent_chain_root_owned','nofollow_final_open','capsule_node_immutable','capsule_receipt_immutable','capsule_directory_immutable'])if(r[k]!==true)fail('RECEIPT_POLICY');for(const k of ['parent_chain_group_other_writable','realpath_used','readlink_f_used','stat_follow_used','raw_paths_reported','source_immutable','secrets_read','package_manager_write','system_node_modified','nvm_modified','raw_values_reported'])if(r[k]!==false)fail('RECEIPT_POLICY');if(r.network_calls!==0)return fail('RECEIPT_POLICY');return true;}

function run(exe,args,{code='TOOL_FAILED',encoding=null,env={HOME:'/var/empty',LANG:'C',LC_ALL:'C',PATH:'/usr/bin:/bin'},cwd,maxBuffer=32*1024*1024}={}){const r=spawnSync(exe,args,{encoding,env,cwd,maxBuffer});if(r.error||r.status!==0||r.signal)fail(code);return r;}
async function writeExclusive(p,bytes,mode){const h=await fsp.open(p,F.O_WRONLY|F.O_CREAT|F.O_EXCL|F.O_NOFOLLOW,mode);try{await h.writeFile(bytes);await h.chmod(mode);await h.sync();}finally{await h.close();}}
async function syncDir(p){const h=await fsp.open(p,F.O_RDONLY|F.O_DIRECTORY|F.O_NOFOLLOW);try{await h.sync();}finally{await h.close();}}
const exists=async p=>{try{await fsp.lstat(p,{bigint:true});return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}};
const attrs=p=>run('/usr/bin/lsattr',['-d',p],{code:'IMMUTABLE_FLAG',encoding:'utf8'}).stdout;
const immutable=p=>String(attrs(p)).trim().split(/\s+/)[0].includes('i');
const chattr=(flag,p)=>run('/usr/bin/chattr',[flag,'--',p],{code:'IMMUTABLE_CAPABILITY'});

function git(args){return run('/usr/bin/git',args,{code:'GIT_AUTHORITY',encoding:'utf8'}).stdout.trim();}
function readAuthority(){const commit=git(['rev-parse','HEAD']),parent=git(['rev-parse','HEAD^']),tree=git(['rev-parse','HEAD^{tree}']),subject=git(['show','-s','--format=%s','HEAD']);if(!SHA40.test(commit)||parent!==AUTHORITY_PARENT||!SHA40.test(tree)||subject!==AUTHORITY_SUBJECT||git(['status','--porcelain=v1','-uall'])!=='')fail('GIT_AUTHORITY');const changed=git(['diff-tree','--no-commit-id','--name-only','-r','HEAD']).split('\n').filter(Boolean).sort();if(JSON.stringify(changed)!==JSON.stringify([...AUTHORITY_PATHS].sort()))fail('GIT_AUTHORITY');const manifest=[];for(const p of AUTHORITY_PATHS){const line=git(['ls-tree','HEAD','--',p]),m=line.match(/^100644 blob ([0-9a-f]{40})\t/);if(!m)fail('GIT_AUTHORITY');const bytes=run('/usr/bin/git',['cat-file','blob',`HEAD:${p}`],{code:'GIT_AUTHORITY'}).stdout;if(gitBlobOid(bytes)!==m[1])fail('GIT_AUTHORITY');manifest.push({path:p,blob_oid:m[1],sha256:sha256(bytes)});}const b=manifest.find(x=>x.path===BUILDER_REL);return{commit,parent,tree,subject,builderBlob:b.blob_oid,builderHash:b.sha256,manifestHash:sha256(Buffer.from(jsonBytes(manifest)))};}
function validateTrustedDirectoryChain(directory){const absolute=path.resolve(directory);let current='/';requireTrustedDirectory(fs.lstatSync(current,{bigint:true}));for(const component of absolute.slice(1).split('/').filter(Boolean)){current=path.join(current,component);requireTrustedDirectory(fs.lstatSync(current,{bigint:true}));}return true;}
function validateSnapshot(a){const expected=path.join(RUNTIME_ROOT,'.builders',a.commit,path.basename(BUILDER_REL));if(path.resolve(SCRIPT_PATH)!==expected)fail('BUILDER_SNAPSHOT');validateTrustedDirectoryChain(path.dirname(expected));const s=fs.lstatSync(expected,{bigint:true});if(!s.isFile()||s.isSymbolicLink()||s.uid!==0n||s.gid!==0n||(s.mode&0o777n)!==0o600n||s.nlink!==1n)fail('BUILDER_SNAPSHOT');const fd=fs.openSync(expected,F.O_RDONLY|F.O_NOFOLLOW);let bytes;try{bytes=fs.readFileSync(fd);}finally{fs.closeSync(fd);}if(sha256(bytes)!==a.builderHash||gitBlobOid(bytes)!==a.builderBlob)fail('BUILDER_SNAPSHOT');}
function sourceSnapshot(){const e=resolveClosureEntryNoFollow(BOOTSTRAP);if(e.canonical_content_sha256!==BOOTSTRAP_SHA||e.final_component_symlink)fail('BOOTSTRAP');const version=run(BOOTSTRAP,['--version'],{code:'BOOTSTRAP',encoding:'utf8'}).stdout.trim(),processVersions=run(BOOTSTRAP,['-e','const c=require("node:crypto");const x=Object.keys(process.versions).sort().map(k=>`${k}:${process.versions[k]}`).join("\\n")+"\\n";process.stdout.write(c.createHash("sha256").update(x).digest("hex"))'],{code:'BOOTSTRAP',encoding:'utf8'}).stdout.trim();if(!SHA64.test(processVersions))fail('BOOTSTRAP');return{entry:e,version,processVersions};}
function toolSnapshot(){const entries=TOOL_PATHS.map(p=>{const e=resolveClosureEntryNoFollow(p);return{name:path.basename(p),path_sha256:sha256(Buffer.from(p)),content_sha256:e.canonical_content_sha256,identity_sha256:e.canonical_identity_sha256};});return{entries,hash:sha256(Buffer.from(jsonBytes(entries))) };}
function filesystemDescriptor(target){return sha256(Buffer.from(run('/usr/bin/findmnt',['-T',target,'-n','-o','TARGET,FSTYPE,OPTIONS'],{code:'FILESYSTEM',encoding:'utf8'}).stdout.trim()));}

async function capabilityProbeDurable(a,p){return runDurableCapabilityProbeSequence({create:()=>writeExclusive(p.transientProbe,Buffer.from('probe\n'),0o555),setImmutable:()=>chattr('+i',p.transientProbe),readAttrs:()=>attrs(p.transientProbe),openWrite:async()=>{const h=await fsp.open(p.transientProbe,F.O_WRONLY|F.O_NOFOLLOW);await h.close();},unlink:()=>fsp.unlink(p.transientProbe),rename:()=>fsp.rename(p.transientProbe,p.transientProbeRenamed),writeReceipt:(result)=>writeExclusive(p.probeReceipt,Buffer.from(jsonBytes({schema_version:2,authority:a.commit,...result})),0o600),fsyncReceipt:()=>syncDir(RUNTIME_ROOT),clearImmutable:()=>chattr('-i',p.transientProbe),remove:()=>fsp.unlink(p.transientProbe),fsyncCleanup:()=>syncDir(RUNTIME_ROOT)});}

function pathsFor(a){const final=path.join(RUNTIME_ROOT,a.commit,BOOTSTRAP_SHA),transientProbe=path.join(RUNTIME_ROOT,`.probe-v2-${a.commit}`);return{claim:path.join(RUNTIME_ROOT,`${a.commit}.claim.v2.json`),capture:path.join(RUNTIME_ROOT,`${a.commit}.closure.capture.v2.json`),probeReceipt:path.join(RUNTIME_ROOT,`${a.commit}.probe.receipt.v2.json`),transientProbe,transientProbeRenamed:`${transientProbe}.renamed`,staging:path.join(RUNTIME_ROOT,`.staging-v2-${a.commit}-${BOOTSTRAP_SHA}`),root:path.join(RUNTIME_ROOT,a.commit),final,node:path.join(final,'node'),receipt:path.join(final,'runtime.receipt.v2.json')};}
async function readJsonNoFollow(p,mode){const first=fs.lstatSync(p,{bigint:true});if(!first.isFile()||first.isSymbolicLink()||(first.mode&0o777n)!==BigInt(mode)||first.uid!==0n||first.gid!==0n||first.nlink!==1n||first.size>16n*1024n*1024n)fail('STATE_FILE');const fd=fs.openSync(p,F.O_RDONLY|F.O_NOFOLLOW);try{const before=fs.fstatSync(fd,{bigint:true});assertStableIdentity(first,before,'STATE_FILE');const bytes=fs.readFileSync(fd),after=fs.fstatSync(fd,{bigint:true});assertStableIdentity(before,after,'STATE_FILE');if(BigInt(bytes.length)!==after.size)fail('STATE_FILE');const end=fs.lstatSync(p,{bigint:true});assertStableIdentity(after,end,'STATE_FILE');return{bytes,value:JSON.parse(bytes.toString('utf8'))};}finally{fs.closeSync(fd);}}

function buildClaimV2(a,source,tools){return{schema_version:2,purpose:'CI3_NODE_RUNTIME_CAPSULE_V2_CLAIM',architecture:ARCHITECTURE,closure_algorithm:CLOSURE_ALGORITHM,authority:a.commit,authority_tree:a.tree,builder_blob_oid:a.builderBlob,builder_sha256:a.builderHash,bootstrap_sha256:BOOTSTRAP_SHA,bootstrap_identity_sha256:source.entry.canonical_identity_sha256,tool_manifest_sha256:tools.hash,baseline:BASELINE,runtime_v1_authority_sha:V1_AUTHORITY,runtime_v1_stop_sha:V1_STOP,runtime_v1_attempt_consumed:true,attempt:1,retry:false,raw_paths_reported:false,secrets_read:false};}
async function validateClaimCapture(a,p,source,tools){
  const expectedClaim=Buffer.from(jsonBytes(buildClaimV2(a,source,tools))),claim=await readJsonNoFollow(p.claim,0o600),capture=await readJsonNoFollow(p.capture,0o600);
  if(!crypto.timingSafeEqual(sha256Buffer(claim.bytes),sha256Buffer(expectedClaim))||claim.bytes.length!==expectedClaim.length)fail('CLAIM_DRIFT');
  const c=capture.value,expectedKeys=['schema_version','authority','claim_sha256','source_identity_sha256','ldd_tool_manifest_sha256','closure_algorithm',...Object.keys(BASELINE),'entries','created_at_utc','raw_values_reported','secrets_read'].sort();
  if(!c||JSON.stringify(Object.keys(c).sort())!==JSON.stringify(expectedKeys))fail('CAPTURE');
  if(c?.schema_version!==2||c.authority!==a.commit||c.claim_sha256!==sha256(expectedClaim)||c.source_identity_sha256!==source.entry.canonical_identity_sha256||c.ldd_tool_manifest_sha256!==tools.hash||c.closure_algorithm!==CLOSURE_ALGORITHM||c.raw_values_reported!==false||c.secrets_read!==false||typeof c.created_at_utc!=='string')fail('CAPTURE');
  revalidateClosureCapture(c);
  assertBaseline(c);
  return{claim,capture,claimBytes:expectedClaim,closure:c};
}
function sha256Buffer(bytes){return crypto.createHash('sha256').update(bytes).digest();}
async function readProbeReceipt(a,p){const probe=await readJsonNoFollow(p.probeReceipt,0o600),v=probe.value,keys=['attempted','authority','immutable_set','rename_rejected','schema_version','unlink_rejected','write_rejected'].sort();if(!v||JSON.stringify(Object.keys(v).sort())!==JSON.stringify(keys)||v.schema_version!==2||v.authority!==a.commit||v.attempted!==1||v.immutable_set!==true||v.write_rejected!==true||v.unlink_rejected!==true||v.rename_rejected!==true)fail('IMMUTABLE_CAPABILITY');return v;}

async function verifyPublished(a,p){
  const source=sourceSnapshot(),tools=toolSnapshot(),captured=await validateClaimCapture(a,p,source,tools),probe=await readProbeReceipt(a,p),receipt=await readJsonNoFollow(p.receipt,0o444),r=receipt.value;
  if(sha256(captured.claim.bytes)!==r.closure_claim_sha256||sha256(captured.capture.bytes)!==r.closure_capture_sha256)fail('CAPSULE_BINDING');validateReceiptV2(r);
  const node=resolveClosureEntryNoFollow(p.node),nodeStat=fs.lstatSync(p.node,{bigint:true}),finalStat=fs.lstatSync(p.final,{bigint:true});
  if(node.canonical_content_sha256!==BOOTSTRAP_SHA||node.canonical_identity_sha256!==r.capsule_node_identity_sha256||nodeStat.uid!==0n||nodeStat.gid!==0n||(nodeStat.mode&0o777n)!==0o555n||nodeStat.nlink!==1n||!immutable(p.node)||!immutable(p.receipt)||!immutable(p.final))fail('CAPSULE_VERIFY');
  if(finalStat.uid!==0n||finalStat.gid!==0n||(finalStat.mode&0o777n)!==0o555n||!finalStat.isDirectory()||finalStat.isSymbolicLink())fail('CAPSULE_VERIFY');
  const chattrHash=tools.entries.find(entry=>entry.name==='chattr')?.content_sha256,lsattrHash=tools.entries.find(entry=>entry.name==='lsattr')?.content_sha256;
  if(r.runtime_authority_commit!==a.commit||r.runtime_authority_tree!==a.tree||r.runtime_authority_subject!==a.subject||r.authority_manifest_sha256!==a.manifestHash||r.builder_blob_oid!==a.builderBlob||r.builder_sha256!==a.builderHash||r.source_version!==source.version||r.source_identity_sha256!==source.entry.canonical_identity_sha256||r.source_parent_chain_sha256!==source.entry.parent_chain_sha256||r.source_process_versions_sha256!==source.processVersions||r.tool_manifest_sha256!==tools.hash||r.chattr_sha256!==chattrHash||r.lsattr_sha256!==lsattrHash||r.capsule_node_path_sha256!==sha256(Buffer.from(p.node))||r.filesystem_descriptor_sha256!==filesystemDescriptor(p.final)||JSON.stringify(r.capability_probe)!==JSON.stringify(({schema_version:_schema,authority:_authority,...rest})=>rest)(probe))fail('CAPSULE_BINDING');
  const version=run(p.node,['--version'],{code:'CAPSULE_VERIFY',encoding:'utf8'}).stdout.trim();if(version!==source.version)fail('CAPSULE_EXECUTION');
  const sourceAfter=sourceSnapshot();if(source.entry.canonical_identity_sha256!==sourceAfter.entry.canonical_identity_sha256||sourceAfter.entry.canonical_content_sha256!==BOOTSTRAP_SHA)fail('BOOTSTRAP_DRIFT');
  return{receiptSha:sha256(receipt.bytes),nodeIdentity:node.canonical_identity_sha256,capture:captured.capture.value};
}

async function createCapsule(){
  if(process.getuid?.()!==0||process.platform!=='linux')fail('VPS_REQUIRED');const a=readAuthority();validateSnapshot(a);const source=sourceSnapshot(),tools=toolSnapshot(),p=pathsFor(a);await fsp.mkdir(RUNTIME_ROOT,{recursive:true,mode:0o700});validateTrustedDirectoryChain(RUNTIME_ROOT);
  const hasClaim=await exists(p.claim),hasProbeReceipt=await exists(p.probeReceipt),hasTransientProbe=await exists(p.transientProbe)||await exists(p.transientProbeRenamed),state=classifyCreationStateV2({claim:hasClaim,capture:await exists(p.capture),final:await exists(p.final),staging:await exists(p.staging),probe:hasTransientProbe});if(!hasClaim&&hasProbeReceipt)fail('UNCLAIMED_STATE');
  if(state==='VERIFY_EXACT_EXISTING'){const v=await verifyPublished(a,p);process.stdout.write(`CREATE PASS status=EXISTS_VERIFIED authority_sha=${a.commit} receipt_sha256=${v.receiptSha} closure_manifest_sha256=${v.capture.closure_manifest_sha256}\n`);return;}
  const claimBytes=Buffer.from(jsonBytes(buildClaimV2(a,source,tools))),fresh=state==='FRESH';
  if(fresh)await runClaimCaptureStateMachine({writeClaim:()=>writeExclusive(p.claim,claimBytes,0o600),fsyncClaim:()=>syncDir(RUNTIME_ROOT),spawnLdd:()=>run('/usr/bin/ldd',[BOOTSTRAP],{code:'DYNAMIC_CLOSURE',encoding:'utf8'}).stdout,buildCapture:(raw)=>{const closure=buildClosureManifest(parseLddOutput(raw));assertBaseline(closure);return{schema_version:2,authority:a.commit,claim_sha256:sha256(claimBytes),source_identity_sha256:source.entry.canonical_identity_sha256,ldd_tool_manifest_sha256:tools.hash,closure_algorithm:CLOSURE_ALGORITHM,...publicClosureProjection(closure),entries:closure.entries,created_at_utc:new Date().toISOString(),raw_values_reported:false,secrets_read:false};},writeCapture:(c)=>writeExclusive(p.capture,Buffer.from(jsonBytes(c)),0o600),fsyncCapture:()=>syncDir(RUNTIME_ROOT)});
  const captured=await validateClaimCapture(a,p,source,tools),capture=captured.capture,closure=captured.closure;
  if(await exists(p.root))fail('PARTIAL_STATE');
  let probeResult;if(hasProbeReceipt)probeResult=await readProbeReceipt(a,p);else probeResult=await capabilityProbeDurable(a,p);
  const capability=(({schema_version:_schema,authority:_authority,...rest})=>rest)(probeResult);
  await fsp.mkdir(p.root,{mode:0o700});await fsp.mkdir(p.staging,{mode:0o700});const staged=path.join(p.staging,'node');const srcFd=fs.openSync(BOOTSTRAP,F.O_RDONLY|F.O_NOFOLLOW);let bytes,before,after;try{before=fs.fstatSync(srcFd,{bigint:true});bytes=fs.readFileSync(srcFd);after=fs.fstatSync(srcFd,{bigint:true});assertStableIdentity(before,after,'BOOTSTRAP_DRIFT');}finally{fs.closeSync(srcFd);}if(sha256(bytes)!==BOOTSTRAP_SHA)fail('BOOTSTRAP_DRIFT');await writeExclusive(staged,bytes,0o555);run(staged,['--version'],{code:'CAPSULE_EXECUTION'});
  const capsuleClosure=buildClosureManifest(parseLddOutput(run('/usr/bin/ldd',[staged],{code:'DYNAMIC_CLOSURE',encoding:'utf8'}).stdout));assertBaseline(capsuleClosure);for(const k of Object.keys(BASELINE))if(capsuleClosure[k]!==closure[k])fail('CLOSURE_MISMATCH');
  const sourceBeforePublish=sourceSnapshot();if(source.entry.canonical_identity_sha256!==sourceBeforePublish.entry.canonical_identity_sha256)fail('BOOTSTRAP_DRIFT');await fsp.mkdir(p.final,{mode:0o700});const chattrHash=tools.entries.find(entry=>entry.name==='chattr')?.content_sha256,lsattrHash=tools.entries.find(entry=>entry.name==='lsattr')?.content_sha256;
  await runReceiptLastPublicationSequence({linkNode:()=>fsp.link(staged,p.node),unlinkStaged:()=>fsp.unlink(staged),freezeNode:()=>chattr('+i',p.node),readNodeIdentity:()=>resolveClosureEntryNoFollow(p.node).canonical_identity_sha256,buildReceipt:(nodeIdentity)=>buildReceiptV2({authority:a.commit,tree:a.tree,builderBlob:a.builderBlob,builderHash:a.builderHash,claimHash:sha256(claimBytes),captureHash:sha256(capture.bytes),nodeIdentity,receiptTime:new Date().toISOString(),extra:{authority_manifest_sha256:a.manifestHash,source_version:source.version,source_identity_sha256:source.entry.canonical_identity_sha256,source_parent_chain_sha256:source.entry.parent_chain_sha256,source_process_versions_sha256:source.processVersions,capsule_node_path_sha256:sha256(Buffer.from(p.node)),capability_probe:capability,chattr_sha256:chattrHash,lsattr_sha256:lsattrHash,filesystem_descriptor_sha256:filesystemDescriptor(p.final),tool_manifest_sha256:tools.hash}}),writeReceipt:(receipt)=>writeExclusive(p.receipt,Buffer.from(jsonBytes(receipt)),0o444),fsyncReceipt:()=>syncDir(p.final),removeStaging:()=>fsp.rmdir(p.staging),freezeReceipt:()=>chattr('+i',p.receipt),sealDirectory:async()=>{await fsp.chmod(p.final,0o555);chattr('+i',p.final);},fsyncParent:()=>syncDir(p.root)});
  const verified=await verifyPublished(a,p);process.stdout.write(`CREATE PASS status=CREATED authority_sha=${a.commit} receipt_sha256=${verified.receiptSha} closure_manifest_sha256=${verified.capture.closure_manifest_sha256} entry_count=${verified.capture.loader_entry_count} total_hops=${verified.capture.total_symlink_hops}\n`);
}

async function verifyCapsule(){const a=readAuthority();validateSnapshot(a);const p=pathsFor(a),v=await verifyPublished(a,p);process.stdout.write(`VERIFY PASS authority_sha=${a.commit} receipt_sha256=${v.receiptSha} closure_manifest_sha256=${v.capture.closure_manifest_sha256}\n`);}
async function selfTest(){let n=0;if(parseMode(['--self-test'])!=='self-test')fail('SELF_TEST');n++;if(BASELINE.loader_entry_count!==7||BASELINE.traverses_any_symlink_count!==7||BASELINE.final_component_symlink_count!==2)fail('SELF_TEST');n++;if(!SHA64.test(BASELINE.closure_manifest_sha256))fail('SELF_TEST');n++;if(parseLddOutput('/a (0x1)\n').length!==1)fail('SELF_TEST');n++;if(sanitizeError(new CapsuleError('SELF_TEST'))!=='ERROR SELF_TEST')fail('SELF_TEST');n++;if(AUTHORITY_PATHS.length!==7)fail('SELF_TEST');n++;if(RECEIPT_KEYS.includes('direct_entry_count'))fail('SELF_TEST');n++;if(BRIDGE_AUTHORITY.length!==40)fail('SELF_TEST');n++;process.stdout.write(`SELF_TEST PASS tests=${n} network_calls=0 real_chattr_calls=0 secret_input_opens=0 raw_paths_reported=0\n`);}

async function main(){try{const mode=parseMode(process.argv.slice(2));if(mode==='self-test')await selfTest();else if(mode==='create')await createCapsule();else await verifyCapsule();}catch(e){process.stderr.write(`${sanitizeError(e)}\n`);process.exitCode=1;}}
if(process.argv[1]&&path.resolve(process.argv[1])===SCRIPT_PATH)await main();
