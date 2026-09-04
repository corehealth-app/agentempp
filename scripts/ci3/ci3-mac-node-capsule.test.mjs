import test from'node:test';import assert from'node:assert/strict';
import{mkdtemp,lstat,readFile,symlink}from'node:fs/promises';import{tmpdir}from'node:os';import path from'node:path';
import{TOOL_NAME,MODES,RUNTIME_ROLES,CapsuleError,canonical,sha256,isSystemImage,validateContext,capsuleRoot,probeSlot,writableStagingMode,derivePublishedSourceCandidate,resolveDependencyToken,buildClosureGraph,relocationChangeArguments,writeOwnerOnlyExclusive,validateSourceEvidence,relocationPlan,validateProbeSet,capsuleReceipt,syntheticAdapter,auditSource,createCapsule,verifyExisting,runCli}from'./ci3-mac-node-capsule.mjs';
import*as capsule from'./ci3-mac-node-capsule.mjs';
const h=x=>sha256(x),src=(o={})=>({schema_version:1,role:'MAC_EXECUTOR_NODE_RUNTIME',platform:'darwin',architecture:'arm64',version:'v22.1.0',source_path:'/opt/node/bin/node',source_realpath:'/opt/node/bin/node',source_sha256:h('node'),exec_path_hash:h('/opt/node/bin/node'),environment_hash:h('closed'),physical_identity_hash:h('physical'),closure_graph_hash:h('graph'),device:1,inode:2,mode:0o100755,signature:{kind:'codesign-metadata',digest:h('sig')},images:[{path:'/opt/node/bin/node',sha256:h('node'),kind:'non-system'},{path:'/opt/node/lib/libx.dylib',sha256:h('x'),kind:'non-system'},{path:'/usr/lib/libSystem.B.dylib',sha256:h('/usr/lib/libSystem.B.dylib'),kind:'system'}],...o});
const c=(o={})=>({authority:'a'.repeat(40),generation:'capsule-v4',source_authority:'b'.repeat(40),launcher_blob:'c'.repeat(40),source_evidence_hash:h(canonical(validateSourceEvidence(src()))),predecessor_authority:'85a9ebba88722915df56583d29defc253016a5f9',predecessor_generation:'capsule-v3',predecessor_status:'FAILED_PARTIAL_PRESERVED',predecessor_attempts:'1/1_CONSUMED',predecessor_retry:false,predecessor_cleanup:false,predecessor_adoption:false,...o}),err=(x,f)=>assert.throws(f,e=>e instanceof CapsuleError&&e.code===x),aerr=(x,f)=>assert.rejects(f,e=>e instanceof CapsuleError&&e.code===x);
const probes=p=>['move','move','loader','loader'].map((kind,i)=>({kind,location_hash:h(`${kind}${i}`),exit:0,consumed_non_system:p.mappings.map(x=>x.destination),external_non_system:[],source_root_used:false,...(kind==='loader'?{ready_observed:true,stable_observations:'2/2_PASS',independent_source_agreement:true,mandatory_load_set_complete:true,weak_lazy_policy:'PASS',copied_but_unused:0}:{})}));
test('tool identity',()=>assert.equal(TOOL_NAME,'MAC_RELOCATABLE_NODE_CAPSULE_V4'));test('four modes',()=>assert.equal(MODES.length,4));for(const m of ['--self-test','--audit-source','--create','--verify-existing'])test(`mode ${m}`,()=>assert.ok(MODES.includes(m)));
test('successor root is a new V4 namespace',()=>assert.equal(capsuleRoot(c(),'/private-root'),path.join('/private-root','mac-node-capsule-v4','a'.repeat(40),'capsule-v4')));
test('staging copies become owner-writable only for relocation',()=>{assert.equal(writableStagingMode(0o500),0o700);assert.equal(writableStagingMode(0o400),0o600);err('STAGING_MODE_INVALID',()=>writableStagingMode(0o555))});
test('move and loader probes use four independent slots',()=>assert.equal(new Set(['move','loader'].flatMap(kind=>[0,1].map(index=>probeSlot(kind,index)))).size,4));
test('successor rejects predecessor authority reuse',()=>err('PREDECESSOR_REUSE',()=>validateContext(c({authority:c().predecessor_authority}))));
test('successor rejects predecessor generation reuse',()=>err('GENERATION_INVALID',()=>validateContext(c({generation:'generation-v1'}))));
test('V4 context requires the exact consumed V3 authority lineage',()=>err('PREDECESSOR_STATE_INVALID',()=>validateContext(c({predecessor_authority:'d'.repeat(40)}))));
test('V4 context requires the exact consumed V3 generation lineage',()=>err('PREDECESSOR_STATE_INVALID',()=>validateContext(c({predecessor_generation:'generation-v1'}))));
for(const[n,o]of[['status',{predecessor_status:'PASS'}],['attempts',{predecessor_attempts:'0/1'}],['retry',{predecessor_retry:true}],['cleanup',{predecessor_cleanup:true}],['adoption',{predecessor_adoption:true}]])test(`successor rejects invalid predecessor ${n}`,()=>err('PREDECESSOR_STATE_INVALID',()=>validateContext(c(o))));
test('two roles',()=>assert.deepEqual(RUNTIME_ROLES,['VPS_BOOTSTRAP_NODE_RUNTIME','MAC_EXECUTOR_NODE_RUNTIME']));test('canonical sorts',()=>assert.equal(canonical({b:1,a:2}),'{"a":2,"b":1}'));test('digest shape',()=>assert.match(h('x'),/^[a-f0-9]{64}$/));
for(const [n,p,w]of[['usr','/usr/lib/x',true],['system','/System/Library/x',true],['opt','/opt/x',false],['relative','x',false]])test(`system classification ${n}`,()=>assert.equal(isSystemImage(p),w));
test('valid source accepted',()=>assert.equal(validateSourceEvidence(src()).platform,'darwin'));
for(const[n,o,x]of[['extra',{extra:1},'SOURCE_SCHEMA_INVALID'],['linux',{platform:'linux'},'SOURCE_PLATFORM_INVALID'],['generic role',{role:'node-runtime'},'SOURCE_PLATFORM_INVALID'],['bad arch',{architecture:'ppc'},'SOURCE_PLATFORM_INVALID'],['symlink',{source_realpath:'/other'},'SOURCE_NOT_PHYSICAL'],['relative',{source_path:'node',source_realpath:'node'},'SOURCE_PATH_INVALID'],['hash',{source_sha256:'x'},'SOURCE_HASH_INVALID'],['version',{version:'22'},'SOURCE_IDENTITY_INVALID'],['device',{device:'1'},'SOURCE_IDENTITY_INVALID'],['inode',{inode:'2'},'SOURCE_IDENTITY_INVALID'],['mode',{mode:0o100644},'SOURCE_IDENTITY_INVALID'],['writable mode',{mode:0o100775},'SOURCE_IDENTITY_INVALID'],['signature',{signature:null},'SOURCE_SIGNATURE_INVALID'],['empty closure',{images:[]},'SOURCE_CLOSURE_INVALID']])test(`source rejects ${n}`,()=>err(x,()=>validateSourceEvidence(src(o))));
test('source accepts owner executable without requiring owner write',()=>assert.equal(validateSourceEvidence(src({mode:0o100555})).mode,0o100555));
for(const field of ['exec_path_hash','environment_hash','physical_identity_hash','closure_graph_hash'])test(`source rejects invalid ${field}`,()=>err('SOURCE_IDENTITY_INVALID',()=>validateSourceEvidence(src({[field]:'x'}))));
test('source rejects relative image',()=>err('SOURCE_IMAGE_PATH_INVALID',()=>validateSourceEvidence(src({images:[{path:'x',sha256:h('x'),kind:'non-system'}]}))));test('source rejects image hash',()=>err('SOURCE_IMAGE_HASH_INVALID',()=>validateSourceEvidence(src({images:[{path:'/opt/x',sha256:'x',kind:'non-system'}]}))));test('source rejects mislabeled system image',()=>err('SOURCE_IMAGE_INVALID',()=>validateSourceEvidence(src({images:[{path:'/usr/lib/x',sha256:h('x'),kind:'non-system'}]}))));test('source rejects duplicate image',()=>err('SOURCE_IMAGE_INVALID',()=>validateSourceEvidence(src({images:[{path:'/opt/x',sha256:h('x'),kind:'non-system'},{path:'/opt/x',sha256:h('x'),kind:'non-system'}]}))));
const plan=()=>relocationPlan(src());test('plan relocates dependent non-system images only',()=>assert.equal(plan().mappings.length,1));test('plan excludes system image',()=>assert.equal(plan().mappings.some(x=>x.destination.includes('libSystem')),false));test('plan uses loader relative IDs',()=>assert.equal(plan().mappings.every(x=>x.install_name.startsWith('@loader_path/../lib/')),true));test('plan disables DYLD fallback',()=>assert.equal(plan().dyld_fallback,false));test('plan removes source rpaths',()=>assert.equal(plan().remove_source_rpaths,true));test('plan contains no raw source path',()=>assert.equal(plan().mappings.some(x=>Object.hasOwn(x,'source_path')),false));test('plan deterministic',()=>assert.equal(canonical(plan()),canonical(plan())));
test('four probes pass',()=>assert.equal(validateProbeSet(probes(plan()),plan()),true));
for(const[n,mut,x]of[['count',p=>p.slice(0,3),'PROBE_COUNT_INVALID'],['move count',p=>p.map((q,i)=>i===0?{...q,kind:'loader'}:q),'PROBE_INDEPENDENCE_INVALID'],['location',p=>p.map((q,i)=>i===1?{...q,location_hash:p[0].location_hash}:q),'PROBE_INDEPENDENCE_INVALID'],['exit',p=>p.map((q,i)=>i===0?{...q,exit:1}:q),'PROBE_FAILED'],['source fallback',p=>p.map((q,i)=>i===0?{...q,source_root_used:true}:q),'PROBE_FAILED'],['external image',p=>p.map((q,i)=>i===0?{...q,external_non_system:['x']}:q),'PROBE_FAILED'],['copied unused',p=>p.map((q,i)=>i===0?{...q,consumed_non_system:q.consumed_non_system.slice(1)}:q),'COPIED_IMAGE_NOT_CONSUMED']])test(`probes reject ${n}`,()=>err(x,()=>validateProbeSet(mut(probes(plan())),plan())));
test('receipt binds Mac role',()=>assert.equal(capsuleReceipt(src(),plan(),probes(plan()),'a'.repeat(40)).role,'MAC_EXECUTOR_NODE_RUNTIME'));test('receipt proves two moves',()=>assert.equal(capsuleReceipt(src(),plan(),probes(plan()),'a'.repeat(40)).move_probes,'2/2_PASS'));test('receipt proves two loaders',()=>assert.equal(capsuleReceipt(src(),plan(),probes(plan()),'a'.repeat(40)).loader_probes,'2/2_PASS'));test('receipt says copied images consumed',()=>assert.equal(capsuleReceipt(src(),plan(),probes(plan()),'a'.repeat(40)).copied_non_system_images_consumed,true));test('receipt hides raw path',()=>assert.equal(capsuleReceipt(src(),plan(),probes(plan()),'a'.repeat(40)).raw_path,false));test('receipt rejects bad authority',()=>err('AUTHORITY_INVALID',()=>capsuleReceipt(src(),plan(),probes(plan()),'x')));
test('audit returns zero writes',async()=>{const ad=syntheticAdapter({audit:async()=>src()});assert.equal((await auditSource(c(),ad)).writes,0)});test('audit rejects evidence mismatch',async()=>aerr('SOURCE_EVIDENCE_MISMATCH',()=>auditSource({...c(),source_evidence_hash:h('bad')},syntheticAdapter({audit:async()=>src()}))));test('audit rejects generic role',async()=>aerr('SOURCE_PLATFORM_INVALID',()=>auditSource(c(),syntheticAdapter({audit:async()=>src({role:'node-runtime'})}))));
const goodAdapter=()=>{const p=plan();return syntheticAdapter({audit:async()=>src(),probe:async(kind,i)=>probes(p).filter(x=>x.kind===kind)[i]})};
test('create writes canonical V4 manifest and receipt',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);assert.equal(ad.files.has('mac-relocatable-node-capsule.receipt.json'),true);assert.equal(ad.files.has('capsule.receipt.json'),false);assert.equal(JSON.parse(ad.files.get('capsule-manifest.json')).authority,c().authority)});test('create stages before probes',async()=>{let staged=false;const p=plan(),ad=syntheticAdapter({audit:async()=>src(),stage:async()=>{staged=true},probe:async(kind,i)=>{assert.equal(staged,true);return probes(p).filter(x=>x.kind===kind)[i]}});await createCapsule(c(),ad)});test('create invokes two move probes',async()=>{let n=0;const p=plan(),ad=syntheticAdapter({audit:async()=>src(),probe:async(kind,i)=>{if(kind==='move')n++;return probes(p).filter(x=>x.kind===kind)[i]}});await createCapsule(c(),ad);assert.equal(n,2)});test('create invokes two loader probes',async()=>{let n=0;const p=plan(),ad=syntheticAdapter({audit:async()=>src(),probe:async(kind,i)=>{if(kind==='loader')n++;return probes(p).filter(x=>x.kind===kind)[i]}});await createCapsule(c(),ad);assert.equal(n,2)});test('second create rejected',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);await aerr('ATTEMPT_CONSUMED',()=>createCapsule(c(),ad))});test('failed probe leaves no terminal receipt',async()=>{const p=plan(),ad=syntheticAdapter({audit:async()=>src(),probe:async(kind,i)=>({...probes(p).filter(x=>x.kind===kind)[i],exit:1})});await aerr('PROBE_FAILED',()=>createCapsule(c(),ad));assert.equal(ad.files.has('mac-relocatable-node-capsule.receipt.json'),false)});test('verify requires original claim',async()=>aerr('MISSING',()=>verifyExisting(c(),syntheticAdapter())));test('verify accepts complete exact-existing',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);assert.equal((await verifyExisting(c(),ad)).status,'PASS')});test('self-test no context',async()=>assert.deepEqual(await runCli(['--self-test']),{status:'PASS',modes:4,raw_path:false}));test('unknown mode rejected',async()=>aerr('MODE_INVALID',()=>runCli(['--x'])));test('missing mode rejected',async()=>aerr('MODE_INVALID',()=>runCli([])));test('extra arg rejected',async()=>aerr('MODE_INVALID',()=>runCli(['--self-test','x'])));

test('context rejects a free source pathname',()=>err('CONTEXT_INVALID',()=>validateContext({...c(),source_path:'/ambient/node'})));
test('published source derivation requires one candidate',()=>err('SOURCE_CANDIDATE_COUNT',()=>derivePublishedSourceCandidate([])));
test('published source derivation rejects ambiguity',()=>err('SOURCE_CANDIDATE_COUNT',()=>derivePublishedSourceCandidate([{path_hash:h('a')},{path_hash:h('b')}])));
test('published source derivation accepts exact singleton',()=>assert.equal(derivePublishedSourceCandidate([{path_hash:h('a'),evidence_hash:h('b')}]).path_hash,h('a')));
test('system image recognizes sealed cryptex image',()=>assert.equal(isSystemImage('/System/Volumes/Preboot/Cryptexes/OS/usr/lib/libSystem.B.dylib'),true));
test('loader token resolves against loader directory',()=>assert.equal(resolveDependencyToken('@loader_path/../lib/x.dylib','/capsule/lib/y.dylib','/capsule/bin/node',[]),'/capsule/lib/x.dylib'));
test('executable token resolves against executable directory',()=>assert.equal(resolveDependencyToken('@executable_path/../lib/x.dylib','/capsule/lib/y.dylib','/capsule/bin/node',[]),'/capsule/lib/x.dylib'));
test('rpath token requires one resolution',()=>err('SOURCE_CLOSURE_AMBIGUOUS',()=>resolveDependencyToken('@rpath/x.dylib','/a/y','/a/node',['/one','/two'],()=>true)));
test('rpath token rejects no resolution',()=>err('SOURCE_CLOSURE_UNRESOLVED',()=>resolveDependencyToken('@rpath/x.dylib','/a/y','/a/node',[],()=>false)));
test('closure graph walks dependency dependencies',async()=>{const graph=await buildClosureGraph('/x/node',async p=>p==='/x/node'?{dependencies:['/x/lib/a.dylib'],rpaths:[],identity:h('n'),architecture:'arm64'}:{dependencies:p.endsWith('a.dylib')?['/x/lib/b.dylib']:[],rpaths:[],identity:p.endsWith('a.dylib')?h('a'):h('b'),architecture:'arm64'},{exists:()=>true,realpath:p=>p});assert.equal(graph.images.length,3);assert.equal(graph.edges.length,2)});
test('closure graph canonicalizes a non-system edge target',async()=>{const graph=await buildClosureGraph('/x/node',async p=>({dependencies:p==='/x/node'?['/alias/a.dylib']:[],rpaths:[],identity:h(p),architecture:'arm64'}),{exists:()=>true,realpath:p=>p==='/alias/a.dylib'?'/real/a.dylib':p});assert.equal(graph.edges[0].resolved,'/real/a.dylib')});
test('relocation arguments bind each edge resolved target',()=>assert.deepEqual(relocationChangeArguments([{loader:'/x/node',token:'/x/a',resolved:'/x/a'}],'/x/node',new Map([['/x/a',{install_name:'@loader_path/../lib/a'}]])),['-change','/x/a','@loader_path/../lib/a']));
test('relocation excludes executable from dylib mappings',()=>assert.equal(plan().mappings.some(x=>x.source_hash===src().source_sha256),false));
test('probe schema rejects string consumed set',()=>err('PROBE_SCHEMA_INVALID',()=>validateProbeSet(probes(plan()).map((p,i)=>i? p:{...p,consumed_non_system:'all'}),plan())));
test('probe location digest must be valid',()=>err('PROBE_SCHEMA_INVALID',()=>validateProbeSet(probes(plan()).map((p,i)=>i? p:{...p,location_hash:'x'}),plan())));
test('audit result never returns raw source',async()=>assert.equal(Object.hasOwn(await auditSource(c(),syntheticAdapter({audit:async()=>src()})),'source'),false));
test('verify rejects rewritten manifest',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);ad.files.set('capsule-manifest.json',Buffer.from('{}\n'));await aerr('CAPSULE_RECEIPT_INVALID',()=>verifyExisting(c(),ad))});
test('verify rejects self-shaped manifest drift',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);const manifest=JSON.parse(ad.files.get('capsule-manifest.json'));manifest.source_hash=h('drift');ad.files.set('capsule-manifest.json',Buffer.from(`${canonical(manifest)}\n`));await aerr('CAPSULE_RECEIPT_INVALID',()=>verifyExisting(c(),ad))});
test('verify rejects copied claim from another generation',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);const claim=JSON.parse(ad.files.get('create.claim'));claim.generation='other-generation';ad.files.set('create.claim',Buffer.from(`${canonical(claim)}\n`));await aerr('CAPSULE_RECEIPT_INVALID',()=>verifyExisting(c(),ad))});
test('verify rejects predecessor lineage drift in claim',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);const claim=JSON.parse(ad.files.get('create.claim'));claim.predecessor_status='PASS';ad.files.set('create.claim',Buffer.from(`${canonical(claim)}\n`));await aerr('CAPSULE_RECEIPT_INVALID',()=>verifyExisting(c(),ad))});
test('verify rejects predecessor lineage drift in manifest',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);const manifest=JSON.parse(ad.files.get('capsule-manifest.json'));manifest.predecessor_cleanup=true;ad.files.set('capsule-manifest.json',Buffer.from(`${canonical(manifest)}\n`));await aerr('CAPSULE_RECEIPT_INVALID',()=>verifyExisting(c(),ad))});
test('verify rejects predecessor adoption in receipt',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);const name='mac-relocatable-node-capsule.receipt.json',receipt=JSON.parse(ad.files.get(name));receipt.predecessor_adoption=true;ad.files.set(name,Buffer.from(`${canonical(receipt)}\n`));await aerr('CAPSULE_RECEIPT_INVALID',()=>verifyExisting(c(),ad))});
test('real exclusive writer creates owner-only durable bytes',async()=>{const root=await mkdtemp(path.join(tmpdir(),'capsule-test-'));await writeOwnerOnlyExclusive(root,'receipt.json',Buffer.from('ok'));const st=await lstat(path.join(root,'receipt.json'));assert.equal(st.mode&0o777,0o600);assert.equal((await readFile(path.join(root,'receipt.json'))).toString(),'ok')});
test('real exclusive writer rejects overwrite',async()=>{const root=await mkdtemp(path.join(tmpdir(),'capsule-test-'));await writeOwnerOnlyExclusive(root,'receipt.json',Buffer.from('one'));await assert.rejects(writeOwnerOnlyExclusive(root,'receipt.json',Buffer.from('two')))});
test('real exclusive writer rejects symlink target',async()=>{const root=await mkdtemp(path.join(tmpdir(),'capsule-test-'));await symlink(path.join(root,'missing'),path.join(root,'receipt.json'));await assert.rejects(writeOwnerOnlyExclusive(root,'receipt.json',Buffer.from('two')))});

const vmline=p=>`__TEXT 0000000100000000-0000000100010000 [   64K] r-x/r-x SM=COW  ${p}`;
const vmplan=()=>({executable:'bin/node',mappings:[{destination:'lib/libx.dylib'}]});
const observe=(map,aliases={},sourceImagePaths=[])=>capsule.observeVmmapResidency({map,logicalProbeRoot:'/var/folders/probe capsule',plan:vmplan(),sourceImagePaths},{realpath:async p=>{if(Object.hasOwn(aliases,p)){const v=aliases[p];if(v instanceof Error)throw v;return v}return p}});
test('vmmap observation accepts logical temp alias resolved to physical root',async()=>{const root='/private/var/folders/probe capsule',image=`${root}/lib/libx.dylib`,r=await observe(vmline(image),{'/var/folders/probe capsule':root});assert.deepEqual(r.consumed_non_system,['lib/libx.dylib'])});
test('vmmap observation canonicalizes var and private var with realpath',async()=>{const root='/private/var/folders/probe capsule',logical='/var/folders/probe capsule/lib/libx.dylib',r=await observe(vmline(logical),{'/var/folders/probe capsule':root,[logical]:`${root}/lib/libx.dylib`});assert.deepEqual(r.consumed_non_system,['lib/libx.dylib'])});
test('vmmap observation rejects logical alias drift from pre-spawn physical root',async()=>{await aerr('PROBE_ROOT_DRIFT',()=>capsule.observeVmmapResidency({map:vmline('/private/original/lib/libx.dylib'),logicalProbeRoot:'/var/logical',physicalProbeRoot:'/private/original',plan:vmplan(),sourceImagePaths:[]},{realpath:async()=>'/private/changed'}))});
test('vmmap parser preserves image paths containing spaces',async()=>{const root='/private/var/folders/probe capsule',r=await observe(vmline(`${root}/lib/libx.dylib`),{'/var/folders/probe capsule':root});assert.equal(r.external_non_system.length,0)});
test('substring collision outside capsule is rejected as external',async()=>{const outside='/private/var/folders/probe capsule-shadow/lib/libx.dylib',r=await observe(vmline(outside),{'/var/folders/probe capsule':'/private/var/folders/probe capsule'});assert.deepEqual(r.consumed_non_system,[]);assert.equal(r.external_non_system.length,1)});
test('same basename outside capsule is rejected as external',async()=>{const outside='/opt/other/lib/libx.dylib',r=await observe(vmline(outside),{'/var/folders/probe capsule':'/private/var/folders/probe capsule'});assert.deepEqual(r.consumed_non_system,[]);assert.equal(r.external_non_system.length,1)});
test('symlink alias resolving inside capsule is consumed',async()=>{const alias='/tmp/inside-alias.dylib',root='/private/var/folders/probe capsule',r=await observe(vmline(alias),{'/var/folders/probe capsule':root,[alias]:`${root}/lib/libx.dylib`});assert.deepEqual(r.consumed_non_system,['lib/libx.dylib'])});
test('copied but not loaded dylib remains unconsumed and is rejected',async()=>{const r=await observe(vmline('/private/var/folders/probe capsule/bin/node'),{'/var/folders/probe capsule':'/private/var/folders/probe capsule'});assert.deepEqual(r.consumed_non_system,[]);const p=vmplan(),ps=probes(p).map((q,i)=>i===2?{...q,consumed_non_system:r.consumed_non_system}:q);err('COPIED_IMAGE_NOT_CONSUMED',()=>validateProbeSet(ps,p))});
test('loaded external non-system dylib is rejected',async()=>{const r=await observe(vmline('/opt/external/liby.dylib'),{'/var/folders/probe capsule':'/private/var/folders/probe capsule'});assert.equal(r.external_non_system.length,1)});
test('loaded source-root image is detected after canonicalization',async()=>{const source='/opt/node/lib/libx.dylib',r=await observe(vmline('/opt/node-alias/libx.dylib'),{'/var/folders/probe capsule':'/private/var/folders/probe capsule','/opt/node-alias/libx.dylib':source},[source]);assert.equal(r.source_root_used,true)});
test('unparseable vmmap image line fails closed',async()=>{await aerr('VMMAP_IMAGE_PARSE_FAILED',()=>observe('__TEXT 0000000100000000-0000000100010000 malformed /opt/external/libx.dylib',{'/var/folders/probe capsule':'/private/var/folders/probe capsule'}))});
test('vmmap output without image records fails closed',async()=>{await aerr('VMMAP_IMAGE_PARSE_FAILED',()=>observe('REGION TYPE START - END',{'/var/folders/probe capsule':'/private/var/folders/probe capsule'}))});
test('loaded image realpath failure fails closed',async()=>{const image='/opt/missing/libx.dylib';await aerr('VMMAP_IMAGE_REALPATH_FAILED',()=>observe(vmline(image),{'/var/folders/probe capsule':'/private/var/folders/probe capsule',[image]:new Error('missing')}))});
test('system shared-cache image does not require filesystem realpath',async()=>{const image='/System/Library/Frameworks/Example.framework/Example',r=await observe(vmline(image),{'/var/folders/probe capsule':'/private/var/folders/probe capsule',[image]:new Error('shared-cache-only')});assert.deepEqual(r.external_non_system,[])});
test('system-prefix traversal is canonicalized and rejected as external',async()=>{const image='/System/Library/../../opt/external.dylib',r=await observe(vmline(image),{'/var/folders/probe capsule':'/private/var/folders/probe capsule',[image]:'/opt/external.dylib'});assert.equal(r.external_non_system.length,1)});
test('duplicate loaded image is represented once',async()=>{const root='/private/var/folders/probe capsule',line=vmline(`${root}/lib/libx.dylib`),r=await observe(`${line}\n${line}`,{'/var/folders/probe capsule':root});assert.deepEqual(r.consumed_non_system,['lib/libx.dylib'])});
test('V4 context rejects V3 generation reuse',()=>err('GENERATION_INVALID',()=>validateContext(c({generation:'capsule-v3'}))));
test('V4 root does not reuse V2 or V3 namespace or physical path',()=>{const root=capsuleRoot(c(),'/private-root');assert.equal(root.includes('mac-node-capsule-v2'),false);assert.equal(root.includes('mac-node-capsule-v3'),false);assert.equal(root.endsWith('/capsule-v4'),true)});
test('V4 claim binds an independent authority generation and failed V3 lineage',async()=>{const ad=goodAdapter();await createCapsule(c(),ad);const claim=JSON.parse(ad.files.get('create.claim'));assert.equal(claim.generation,'capsule-v4');assert.equal(claim.predecessor_generation,'capsule-v3');assert.notEqual(claim.authority,claim.predecessor_authority)});

const v4c=(o={})=>({...c(),generation:'capsule-v4',predecessor_authority:'85a9ebba88722915df56583d29defc253016a5f9',predecessor_generation:'capsule-v3',...o});
const loadCommandsFixture=`Load command 0
      cmd LC_LOAD_DYLIB
  cmdsize 56
     name @rpath/mandatory.dylib (offset 24)
Load command 1
      cmd LC_LOAD_WEAK_DYLIB
  cmdsize 56
     name @rpath/optional.dylib (offset 24)
Load command 2
      cmd LC_ID_DYLIB
  cmdsize 56
     name @rpath/identity.dylib (offset 24)
Load command 3
      cmd LC_RPATH
  cmdsize 40
     path @loader_path/../lib (offset 12)
`;
const v4plan={executable:'bin/node',mappings:[{destination:'lib/mandatory.dylib'},{destination:'lib/optional.dylib'}]};
const v4policy={mandatory_non_system:['lib/mandatory.dylib'],weak_lazy_non_system:['lib/optional.dylib']};
const loaded=(consumed=['lib/mandatory.dylib','lib/optional.dylib'],over={})=>({location_hash:h('v4-location'),consumed_non_system:consumed,external_non_system:[],source_root_used:false,...over});

test('actual-format sanitized vmmap capture parses mapped TEXT records and ignores summary rows',()=>{
  const fixture=`REGION TYPE                      VIRTUAL
__TEXT                                  16.0M
__TEXT 0000000100000000-0000000100010000 [   64K] r-x/r-x SM=COW  /synthetic/capsule/bin/node
__TEXT 0000000100010000-0000000100020000 [   64K] r-x/r-x SM=COW  /synthetic/capsule/lib/mandatory dylib
`;
  assert.deepEqual(capsule.parseVmmapImagePaths(fixture),['/synthetic/capsule/bin/node','/synthetic/capsule/lib/mandatory dylib']);
});
test('sanitized DYLD telemetry parses only structured loaded-image records',()=>{
  const fixture='diagnostic header\ndyld[123]: <ABC> /synthetic/capsule/bin/node\ndyld[123]: <DEF> /synthetic/capsule/lib/mandatory dylib\n';
  assert.deepEqual(capsule.parseDyldImagePaths(fixture),['/synthetic/capsule/bin/node','/synthetic/capsule/lib/mandatory dylib']);
});
test('DYLD telemetry without loaded-image records fails closed',()=>err('DYLD_IMAGE_PARSE_FAILED',()=>capsule.parseDyldImagePaths('diagnostic header\n')));
test('Mach-O load command parser classifies mandatory weak and identity commands from otool l',()=>{
  const parsed=capsule.parseMachOLoadCommands(loadCommandsFixture);
  assert.deepEqual(parsed.dependencies.map(x=>x.command),['LC_LOAD_DYLIB','LC_LOAD_WEAK_DYLIB']);
  assert.equal(parsed.identities.length,1);assert.deepEqual(parsed.rpaths,['@loader_path/../lib']);
});
test('relocation policy separates mandatory from weak lazy mappings',()=>{
  const policy=capsule.classifyRelocationPolicy([
    {loader:'/synthetic/node',token:'mandatory',resolved:'/synthetic/mandatory',command:'LC_LOAD_DYLIB'},
    {loader:'/synthetic/node',token:'optional',resolved:'/synthetic/optional',command:'LC_LOAD_WEAK_DYLIB'},
  ],new Map([['/synthetic/mandatory',{destination:'lib/mandatory.dylib'}],['/synthetic/optional',{destination:'lib/optional.dylib'}]]));
  assert.deepEqual(policy,v4policy);
});
test('READY is observed before either vmmap observation or independent reconciliation',async()=>{
  const order=[];const result=await capsule.collectStableLoaderProof({
    waitReady:async()=>{order.push('ready');return true},
    observeVmmap:async()=>{order.push('vmmap');assert.equal(order[0],'ready');return loaded()},
    observeIndependent:async()=>{order.push('independent');assert.equal(order[0],'ready');return loaded()},
  },v4plan,v4policy);
  assert.deepEqual(order,['ready','vmmap','vmmap','independent']);assert.equal(result.stable_observations,'2/2_PASS');
});
test('two vmmap observations must be stable',async()=>{
  let count=0;await aerr('LOADER_OBSERVATION_UNSTABLE',()=>capsule.collectStableLoaderProof({waitReady:async()=>true,observeVmmap:async()=>loaded(count++?['lib/mandatory.dylib']:undefined),observeIndependent:async()=>loaded()},v4plan,v4policy));
});
test('vmmap and independent loaded-image source must agree',async()=>{
  await aerr('INDEPENDENT_SOURCE_MISMATCH',()=>capsule.collectStableLoaderProof({waitReady:async()=>true,observeVmmap:async()=>loaded(),observeIndependent:async()=>loaded(['lib/mandatory.dylib'])},v4plan,v4policy));
});
test('missing mandatory mapping is rejected',async()=>{
  await aerr('MANDATORY_IMAGE_NOT_LOADED',()=>capsule.collectStableLoaderProof({waitReady:async()=>true,observeVmmap:async()=>loaded(['lib/optional.dylib']),observeIndependent:async()=>loaded(['lib/optional.dylib'])},v4plan,v4policy));
});
test('copied but unused weak lazy mapping remains rejected',async()=>{
  await aerr('COPIED_IMAGE_NOT_CONSUMED',()=>capsule.collectStableLoaderProof({waitReady:async()=>true,observeVmmap:async()=>loaded(['lib/mandatory.dylib']),observeIndependent:async()=>loaded(['lib/mandatory.dylib'])},v4plan,v4policy));
});
test('stable proof rejects an external non-system image',async()=>{
  await aerr('PROBE_FAILED',()=>capsule.collectStableLoaderProof({waitReady:async()=>true,observeVmmap:async()=>loaded(undefined,{external_non_system:[h('external')]}),observeIndependent:async()=>loaded()},v4plan,v4policy));
});
test('stable proof rejects a source-root dependency',async()=>{
  await aerr('PROBE_FAILED',()=>capsule.collectStableLoaderProof({waitReady:async()=>true,observeVmmap:async()=>loaded(undefined,{source_root_used:true}),observeIndependent:async()=>loaded()},v4plan,v4policy));
});
test('V4 context binds exactly the consumed V3 predecessor',()=>assert.equal(validateContext(v4c()).predecessor_generation,'capsule-v3'));
test('V4 context rejects direct V2 predecessor reuse',()=>err('PREDECESSOR_STATE_INVALID',()=>validateContext(v4c({predecessor_authority:'c1c83a63b9f258546310eccba30b889958ccabe5',predecessor_generation:'capsule-v2'}))));
test('V4 context rejects V3 generation reuse',()=>err('GENERATION_INVALID',()=>validateContext(v4c({generation:'capsule-v3'}))));
test('V4 root claim and generation are independent of V2 and V3',()=>{
  const root=capsuleRoot(v4c(),'/private-root');assert.equal(root,path.join('/private-root','mac-node-capsule-v4','a'.repeat(40),'capsule-v4'));assert.equal(root.includes('capsule-v2'),false);assert.equal(root.includes('capsule-v3'),false);
});
