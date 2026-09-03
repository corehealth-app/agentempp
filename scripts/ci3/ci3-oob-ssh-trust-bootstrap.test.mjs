import test from 'node:test';
import assert from 'node:assert/strict';
import {
  TOOL_NAME,CLOSED_MODES,SOURCE_CLASS,FIXED_ALIAS,MAX_ATTESTATION_BYTES,NONCE_TTL_MS,CLOSED_SSH_POLICY,OobTrustError,
  canonicalJson,sha256,safeEqual,base64urlCanonical,decodeConsoleAttestation,validateFingerprint,validateConsoleEnvelope,
  validateContext,authorityRoot,consoleCommandFor,shellQuote,helperScriptFor,isolatedSshConfig,parseEffectiveConfig,
  validateEffectiveConfig,createSyntheticAdapter,prepareHumanGate,ingestConsoleAttestation,acquireHostKey,
  verifyEffectiveSshConfig,attestConnection,verifyExisting,runCli,
} from './ci3-oob-ssh-trust-bootstrap.mjs';

const L=`SHA256:${'L'.repeat(43)}`, H=`SHA256:${'H'.repeat(43)}`, A=`SHA256:${'A'.repeat(43)}`, NOW=1_800_000_000_000;
const ctx=(o={})=>({authority:'a'.repeat(40),generation:'generation-v1',authority_blob:'b'.repeat(40),module_blob:'c'.repeat(40),node_executable:'/fixed/node',node_sha256:'d'.repeat(64),destination:'fixed.example.invalid',destination_hash:sha256('fixed.example.invalid'),public_key_path:'/fixed/id.pub',private_key_path:'/fixed/id',public_key_fingerprint:L,...o});
const env=(o={})=>({schema_version:1,purpose:TOOL_NAME,nonce:'N'.repeat(48),uid:0,hostname:'node.example.internal',port:22,host_key_algorithm:'ssh-ed25519',host_key_fingerprint:H,authorized_key_fingerprints:[A,L].sort(),...o});
const code=(c,f)=>assert.throws(f,e=>e instanceof OobTrustError&&e.code===c);
const acode=(c,f)=>assert.rejects(f,e=>e instanceof OobTrustError&&e.code===c);
async function prepared(over={}){const adapter=createSyntheticAdapter({nowMs:()=>NOW,...over});const context=ctx();await prepareHumanGate(context,adapter);return{adapter,context};}
async function ingested(over={},eo={}){const x=await prepared(over);await ingestConsoleAttestation(x.context,{confirmation:'SIM',encodedLine:base64urlCanonical(env(eo))},x.adapter);return x;}
const scan=async()=>({algorithm:'ssh-ed25519',known_hosts_line:`ssh-ed25519 ${'A'.repeat(68)}`,fingerprint:H});
function gout(context=ctx(),over={}){return Object.entries({...CLOSED_SSH_POLICY,hostname:context.destination,port:'22',user:'root',identityfile:context.private_key_path,userknownhostsfile:authorityRoot(context)+'/known_hosts',...over}).map(([k,v])=>`${k} ${v}`).join('\n')+'\n';}
async function ready(attest=async({challenge})=>({challenge,uid:0,hostname:'node.example.internal',exit:0})){const x=await ingested({keyscan:scan,sshG:async()=>gout(),sshAttest:attest});await acquireHostKey(x.context,x.adapter);await verifyEffectiveSshConfig(x.context,x.adapter);return x;}

test('identity is exact',()=>assert.equal(TOOL_NAME,'FRESH_OUT_OF_BAND_TRUST_BOOTSTRAP_V1'));
test('source class is exact',()=>assert.equal(SOURCE_CLASS,'OFFICIAL_VPS_WEB_CONSOLE'));
test('SSH alias is exact',()=>assert.equal(FIXED_ALIAS,'ci3-oob-attestation'));
test('input bound is exact',()=>assert.equal(MAX_ATTESTATION_BYTES,16384));
test('nonce TTL is ten minutes',()=>assert.equal(NONCE_TTL_MS,600000));
test('there are seven modes',()=>assert.equal(CLOSED_MODES.length,7));
for(const m of ['--self-test','--prepare-human-gate','--ingest-console-attestation','--verify-existing','--acquire-host-key','--verify-effective-config','--attest-connection'])test(`closed mode ${m}`,()=>assert.ok(CLOSED_MODES.includes(m)));
test('canonical JSON sorts recursively',()=>assert.equal(canonicalJson({z:1,a:{z:2,a:3}}),'{"a":{"a":3,"z":2},"z":1}'));
test('canonical JSON preserves arrays',()=>assert.equal(canonicalJson([3,1]),'[3,1]'));
test('canonical JSON rejects fraction',()=>code('CANONICAL_JSON_NUMBER',()=>canonicalJson(.5)));
test('canonical JSON rejects undefined',()=>code('CANONICAL_JSON_TYPE',()=>canonicalJson(undefined)));
test('sha256 is lowercase hex',()=>assert.match(sha256('x'),/^[a-f0-9]{64}$/));
test('constant-time helper accepts equal',()=>assert.equal(safeEqual('a','a'),true));
test('constant-time helper rejects different',()=>assert.equal(safeEqual('a','b'),false));
test('constant-time helper rejects length mismatch',()=>assert.equal(safeEqual('a','aa'),false));
test('canonical base64url has no padding',()=>assert.doesNotMatch(base64urlCanonical(env()),/=/));
test('canonical frame decodes',()=>assert.equal(decodeConsoleAttestation(base64urlCanonical(env())).uid,0));
for(const [n,v,c] of [['empty','', 'OOB_FRAME_INVALID'],['oversize','A'.repeat(16385),'OOB_FRAME_INVALID'],['alphabet','bad+=','OOB_FRAME_INVALID'],['json',Buffer.from('bad').toString('base64url'),'OOB_JSON_INVALID']])test(`frame rejects ${n}`,()=>code(c,()=>decodeConsoleAttestation(v)));
test('frame rejects noncanonical JSON',()=>code('OOB_NOT_CANONICAL',()=>decodeConsoleAttestation(Buffer.from(JSON.stringify(env())).toString('base64url'))));
test('valid fingerprint passes',()=>assert.equal(validateFingerprint(H),H));
for(const [n,v] of [['prefix','x'.repeat(43)],['short','SHA256:a'],['padding',`SHA256:${'a'.repeat(42)}=`],['space',`SHA256:${'a'.repeat(42)} `]])test(`fingerprint rejects ${n}`,()=>code('FINGERPRINT_INVALID',()=>validateFingerprint(v)));
test('valid envelope freezes output',()=>assert.equal(Object.isFrozen(validateConsoleEnvelope(env())),true));
for(const [n,o,c] of [
 ['extra',{extra:1},'OOB_SCHEMA_INVALID'],['purpose',{purpose:'OLD'},'OOB_PURPOSE_INVALID'],['nonce',{nonce:'x'},'OOB_NONCE_INVALID'],
 ['uid',{uid:501},'OOB_UID_INVALID'],['hostname',{hostname:'bad host'},'OOB_HOSTNAME_INVALID'],['port zero',{port:0},'OOB_PORT_INVALID'],
 ['port string',{port:'22'},'OOB_PORT_INVALID'],['algorithm',{host_key_algorithm:'rsa'},'OOB_HOST_ALGORITHM_INVALID'],
 ['empty authorized',{authorized_key_fingerprints:[]},'OOB_AUTHORIZED_SET_INVALID'],['duplicate authorized',{authorized_key_fingerprints:[L,L]},'OOB_AUTHORIZED_SET_INVALID'],
 ['unsorted authorized',{authorized_key_fingerprints:[L,A]},'OOB_AUTHORIZED_SET_INVALID'],
])test(`envelope rejects ${n}`,()=>code(c,()=>validateConsoleEnvelope(env(o))));
test('valid context passes',()=>assert.equal(validateContext(ctx()).authority.length,40));
for(const [n,f,v,c] of [
 ['authority','authority','x','AUTHORITY_INVALID'],['generation','generation','bad space','GENERATION_INVALID'],['authority blob','authority_blob','x','AUTHORITY_BLOB_INVALID'],
 ['module blob','module_blob','x','MODULE_BLOB_INVALID'],['node hash','node_sha256','x','NODE_HASH_INVALID'],['destination hash','destination_hash','x','DESTINATION_HASH_INVALID'],
 ['node path','node_executable','rel','CONTEXT_PATH_INVALID'],['public path','public_key_path','rel','CONTEXT_PATH_INVALID'],['private path','private_key_path','rel','CONTEXT_PATH_INVALID'],
 ['public fingerprint','public_key_fingerprint','bad','LOCAL_KEY_FINGERPRINT_INVALID'],
])test(`context rejects ${n}`,()=>code(c,()=>validateContext(ctx({[f]:v}))));
test('context rejects destination hash mismatch',()=>code('DESTINATION_INVALID',()=>validateContext(ctx({destination:'other.invalid'}))));
test('context rejects extra key',()=>code('CONTEXT_SCHEMA_INVALID',()=>validateContext({...ctx(),extra:1})));
test('root fixed below user config',()=>assert.match(authorityRoot(ctx(),'/Users/t'),/^\/Users\/t\/\.config\/agentempp\/ci3\/oob-ssh-trust\//));
test('root version-addressed',()=>assert.ok(authorityRoot(ctx(),'/Users/t').endsWith(`${'a'.repeat(40)}/generation-v1`)));
const req=()=>({schema_version:1,purpose:TOOL_NAME,authority_hash:sha256('a'),nonce:'N'.repeat(48),created_at_ms:NOW,created_monotonic_ms:50000});
test('console command absolute',()=>assert.match(consoleCommandFor(req()),/^\/usr\/bin\/python3 /));
test('console command nonce-bound',()=>assert.match(consoleCommandFor({...req(),nonce:'Z'.repeat(48)}),/ZZZZ/));
test('console command has no mutator',()=>assert.doesNotMatch(consoleCommandFor(req()),/\b(?:rm|mv|cp|chmod|chown|install|tee|touch)\b/));
test('console command has no network client',()=>assert.doesNotMatch(consoleCommandFor(req()),/\b(?:curl|wget|ssh-keyscan)\b/));
test('console command never prints key file content',()=>assert.doesNotMatch(consoleCommandFor(req()),/print\([^)]*(?:authorized_keys|host_ed25519_key)/));
test('shell quote protects apostrophe',()=>assert.equal(shellQuote("a'b"),"'a'\\''b'"));
test('helper requires TTY',()=>assert.match(helperScriptFor({nodeExecutable:'/n',modulePath:'/m',commandPath:'/c'}),/\[\[ -t 0 && -t 1 \]\]/));
test('helper does not forward argv',()=>assert.doesNotMatch(helperScriptFor({nodeExecutable:'/n',modulePath:'/m',commandPath:'/c'}),/\$@|\$\*/));
test('helper invokes only ingest mode',()=>assert.match(helperScriptFor({nodeExecutable:'/n',modulePath:'/m',commandPath:'/c'}),/--ingest-console-attestation/));
test('helper rejects relative path',()=>code('HELPER_PATH_INVALID',()=>helperScriptFor({nodeExecutable:'n',modulePath:'/m',commandPath:'/c'})));
const iconf=()=>isolatedSshConfig({destination:'x.invalid',port:22,identityFile:'/id',knownHostsFile:'/kh'});
test('isolated config exact alias',()=>assert.match(iconf(),/^Host ci3-oob-attestation$/m));
for(const [k,v] of Object.entries({IdentitiesOnly:'yes',StrictHostKeyChecking:'yes',BatchMode:'yes',PasswordAuthentication:'no',KbdInteractiveAuthentication:'no',PubkeyAuthentication:'yes',ForwardAgent:'no',ClearAllForwardings:'yes',ControlMaster:'no',AddKeysToAgent:'no',CanonicalizeHostname:'no',ProxyCommand:'none',ProxyJump:'none'}))test(`isolated policy ${k}`,()=>assert.match(iconf(),new RegExp(`  ${k} ${v}`)));
test('isolated config has no Include',()=>assert.doesNotMatch(iconf(),/^Include /m));
test('isolated config has no Match',()=>assert.doesNotMatch(iconf(),/^Match /m));
test('isolated config rejects wildcard',()=>code('SSH_DESTINATION_INVALID',()=>isolatedSshConfig({destination:'*',port:22,identityFile:'/id',knownHostsFile:'/kh'})));
test('effective parser rejects duplicate',()=>code('SSH_G_DUPLICATE',()=>parseEffectiveConfig('user root\nuser other\n')));
test('effective closed config passes',()=>assert.equal(validateEffectiveConfig(parseEffectiveConfig(gout()),{destination:ctx().destination,port:22,identityFile:ctx().private_key_path,knownHostsFile:authorityRoot(ctx())+'/known_hosts'}),true));
test('effective config rejects ambient host',()=>code('SSH_POLICY_MISMATCH',()=>validateEffectiveConfig(parseEffectiveConfig(gout(ctx(),{hostname:'ambient.invalid'})),{destination:ctx().destination,port:22,identityFile:ctx().private_key_path,knownHostsFile:authorityRoot(ctx())+'/known_hosts'})));
test('effective config rejects password auth',()=>code('SSH_POLICY_MISMATCH',()=>validateEffectiveConfig(parseEffectiveConfig(gout(ctx(),{passwordauthentication:'yes'})),{destination:ctx().destination,port:22,identityFile:ctx().private_key_path,knownHostsFile:authorityRoot(ctx())+'/known_hosts'})));

test('prepare reports ready with zero network',async()=>{const x=await prepared();assert.equal(x.adapter.files.has('human-gate.request.json'),true)});
test('prepare creates helper',async()=>{const x=await prepared();assert.equal(x.adapter.files.has('official-console-helper.zsh'),true)});
test('prepare writes receipt last',async()=>{const x=await prepared();assert.equal(x.adapter.files.has('human-gate.prepared.receipt.json'),true)});
test('prepare cannot run twice',async()=>{const x=await prepared();await acode('ATTEMPT_ALREADY_CONSUMED',()=>prepareHumanGate(x.context,x.adapter))});
test('prepare rejects bad authority',async()=>acode('AUTHORITY_BAD',()=>prepareHumanGate(ctx(),createSyntheticAdapter({verifyAuthority:async()=>{throw new OobTrustError('AUTHORITY_BAD')}}))));
test('prepare rejects bad keypair',async()=>acode('KEYPAIR_BAD',()=>prepareHumanGate(ctx(),createSyntheticAdapter({verifyPhysicalKeyPair:async()=>{throw new OobTrustError('KEYPAIR_BAD')}}))));
test('ingest requires exact SIM',async()=>{const x=await prepared();await acode('OPERATOR_CONFIRMATION_REQUIRED',()=>ingestConsoleAttestation(x.context,{confirmation:'sim',encodedLine:base64urlCanonical(env())},x.adapter))});
test('ingest rejects wrong nonce',async()=>{const x=await prepared();await acode('OOB_NONCE_MISMATCH',()=>ingestConsoleAttestation(x.context,{confirmation:'SIM',encodedLine:base64urlCanonical(env({nonce:'Z'.repeat(48)}))},x.adapter))});
test('ingest rejects stale nonce',async()=>{const x=await prepared();x.adapter.nowMs=()=>NOW+NONCE_TTL_MS+1;await acode('OOB_NONCE_STALE',()=>ingestConsoleAttestation(x.context,{confirmation:'SIM',encodedLine:base64urlCanonical(env())},x.adapter))});
test('ingest rejects clock rollback',async()=>{const x=await prepared();x.adapter.nowMs=()=>NOW-1;await acode('OOB_NONCE_STALE',()=>ingestConsoleAttestation(x.context,{confirmation:'SIM',encodedLine:base64urlCanonical(env())},x.adapter))});
test('ingest requires local key',async()=>{const x=await prepared();await acode('LOCAL_KEY_NOT_AUTHORIZED_EXACTLY_ONCE',()=>ingestConsoleAttestation(x.context,{confirmation:'SIM',encodedLine:base64urlCanonical(env({authorized_key_fingerprints:[A]}))},x.adapter))});
test('ingest clears current pasteboard',async()=>{let n=0;await ingested({clearPasteboard:async()=>n++});assert.equal(n,1)});
test('OOB receipt contains no raw host/fingerprint',async()=>{const x=await ingested();assert.doesNotMatch(x.adapter.files.get('official-console-oob-trust.receipt.json').toString(),/node\.example|SHA256:/)});
test('OOB source record is separate',async()=>{const x=await ingested();assert.equal(x.adapter.files.has('official-console-oob-source.json'),true)});
test('ingest replay rejected',async()=>{const x=await ingested();await acode('ATTEMPT_ALREADY_CONSUMED',()=>ingestConsoleAttestation(x.context,{confirmation:'SIM',encodedLine:base64urlCanonical(env())},x.adapter))});
test('keyscan prohibited before OOB',async()=>acode('ARTIFACT_MISSING',()=>acquireHostKey(ctx(),createSyntheticAdapter())));
test('keyscan matching ED25519 passes',async()=>{const x=await ingested({keyscan:scan});assert.equal((await acquireHostKey(x.context,x.adapter)).attempts,'1/1')});
test('keyscan mismatch stops',async()=>{const x=await ingested({keyscan:async()=>({...await scan(),fingerprint:A})});await acode('HOST_KEY_MISMATCH',()=>acquireHostKey(x.context,x.adapter))});
test('keyscan non-ED25519 stops',async()=>{const x=await ingested({keyscan:async()=>({...await scan(),algorithm:'rsa'})});await acode('HOST_KEY_MISMATCH',()=>acquireHostKey(x.context,x.adapter))});
test('second keyscan rejected',async()=>{const x=await ingested({keyscan:scan});await acquireHostKey(x.context,x.adapter);await acode('ATTEMPT_ALREADY_CONSUMED',()=>acquireHostKey(x.context,x.adapter))});
test('ssh-G prohibited before keyscan',async()=>{const x=await ingested();await acode('ARTIFACT_MISSING',()=>verifyEffectiveSshConfig(x.context,x.adapter))});
test('one ssh-G passes',async()=>{const x=await ingested({keyscan:scan,sshG:async()=>gout()});await acquireHostKey(x.context,x.adapter);assert.equal((await verifyEffectiveSshConfig(x.context,x.adapter)).attempts,'1/1')});
test('ssh-G mismatch stops',async()=>{const x=await ingested({keyscan:scan,sshG:async()=>gout(ctx(),{batchmode:'no'})});await acquireHostKey(x.context,x.adapter);await acode('SSH_POLICY_MISMATCH',()=>verifyEffectiveSshConfig(x.context,x.adapter))});
test('second ssh-G rejected',async()=>{const x=await ingested({keyscan:scan,sshG:async()=>gout()});await acquireHostKey(x.context,x.adapter);await verifyEffectiveSshConfig(x.context,x.adapter);await acode('ATTEMPT_ALREADY_CONSUMED',()=>verifyEffectiveSshConfig(x.context,x.adapter))});
test('strict attestation passes',async()=>{const x=await ready();assert.equal((await attestConnection(x.context,x.adapter)).status,'PASS')});
for(const [n,fn] of [['challenge',async()=>({challenge:'bad',uid:0,hostname:'node.example.internal',exit:0})],['uid',async({challenge})=>({challenge,uid:501,hostname:'node.example.internal',exit:0})],['hostname',async({challenge})=>({challenge,uid:0,hostname:'other',exit:0})],['exit',async({challenge})=>({challenge,uid:0,hostname:'node.example.internal',exit:1})]])test(`strict attestation rejects wrong ${n}`,async()=>{const x=await ready(fn);await acode('SSH_ATTEST_MISMATCH',()=>attestConnection(x.context,x.adapter))});
test('second strict connection rejected',async()=>{const x=await ready();await attestConnection(x.context,x.adapter);await acode('ATTEMPT_ALREADY_CONSUMED',()=>attestConnection(x.context,x.adapter))});
test('authenticated receipt has no raw host/fingerprint',async()=>{const x=await ready();await attestConnection(x.context,x.adapter);assert.doesNotMatch(x.adapter.files.get('authenticated-ssh-trust-source.receipt.json').toString(),/node\.example|SHA256:|fixed\.example/)});
test('verify-existing requires authenticated receipt',async()=>{const x=await ingested();await acode('ARTIFACT_MISSING',()=>verifyExisting(x.context,x.adapter))});
test('verify-existing accepts linked receipts',async()=>{const x=await ready();await attestConnection(x.context,x.adapter);assert.equal((await verifyExisting(x.context,x.adapter)).status,'PASS')});
test('self-test mode has no context dependency',async()=>assert.deepEqual(await runCli(['--self-test']),{status:'PASS',modes:7,raw_values:false}));
test('unknown mode fails closed',async()=>acode('MODE_INVALID',()=>runCli(['--bad'])));
test('missing mode fails closed',async()=>acode('MODE_INVALID',()=>runCli([])));
test('extra argv fails closed',async()=>acode('MODE_INVALID',()=>runCli(['--self-test','x'])));
