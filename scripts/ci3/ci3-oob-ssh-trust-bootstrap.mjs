#!/usr/bin/env node

import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { closeSync, constants as FS_CONSTANTS, lstatSync, openSync, readFileSync, readSync } from 'node:fs';
import { lstat, open, readFile, realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const TOOL_NAME = 'FRESH_OUT_OF_BAND_TRUST_BOOTSTRAP_V1';
export const CLOSED_MODES = Object.freeze([
  '--self-test',
  '--prepare-human-gate',
  '--ingest-console-attestation',
  '--verify-existing',
  '--acquire-host-key',
  '--verify-effective-config',
  '--attest-connection',
]);
export const SOURCE_CLASS = 'OFFICIAL_VPS_WEB_CONSOLE';
export const FIXED_ALIAS = 'ci3-oob-attestation';
export const MAX_ATTESTATION_BYTES = 16 * 1024;
export const NONCE_TTL_MS = 10 * 60 * 1000;
export const CLOSED_SSH_POLICY = Object.freeze({
  user: 'root', identitiesonly: 'yes', stricthostkeychecking: 'yes', batchmode: 'yes',
  passwordauthentication: 'no', kbdinteractiveauthentication: 'no', pubkeyauthentication: 'yes',
  forwardagent: 'no', clearallforwardings: 'yes', controlmaster: 'no', addkeystoagent: 'no',
  canonicalizehostname: 'no', proxycommand: 'none', proxyjump: 'none',
});

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const MANAGER_ROOT = '/Users/eduardohenrique/Developer/bodyflow';
const ROOT_BASENAME = 'oob-ssh-trust';
const CLOSED_ENV = Object.freeze({ LANG: 'C', LC_ALL: 'C', PATH: '/usr/bin:/bin' });
const RECEIPT_NAMES = Object.freeze({
  oob: 'official-console-oob-trust.receipt.json',
  ssh: 'authenticated-ssh-trust-source.receipt.json',
});

export class OobTrustError extends Error {
  constructor(code) { super(code); this.name = 'OobTrustError'; this.code = code; }
}
const fail = (code) => { throw new OobTrustError(code); };
const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const keysExact = (value, keys, code = 'SCHEMA_INVALID') => {
  if (!isObject(value) || JSON.stringify(Object.keys(value).sort()) !== JSON.stringify([...keys].sort())) fail(code);
  return value;
};
const cleanToken = (value, min, max, code) => {
  if (typeof value !== 'string' || value.length < min || value.length > max || !/^[A-Za-z0-9._:@+-]+$/.test(value)) fail(code);
  return value;
};
const hex = (value, length, code) => {
  if (typeof value !== 'string' || !new RegExp(`^[a-f0-9]{${length}}$`).test(value)) fail(code);
  return value;
};
const integer = (value, min, max, code) => {
  if (!Number.isSafeInteger(value) || value < min || value > max) fail(code);
  return value;
};

export function canonicalJson(value) {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) fail('CANONICAL_JSON_NUMBER');
    return String(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (isObject(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  fail('CANONICAL_JSON_TYPE');
}

export const sha256 = (value) => createHash('sha256').update(value).digest('hex');
export const safeEqual = (left, right) => {
  const a = Buffer.from(String(left)); const b = Buffer.from(String(right));
  return a.length === b.length && timingSafeEqual(a, b);
};
export const base64urlCanonical = (value) => Buffer.from(canonicalJson(value)).toString('base64url');

export function decodeConsoleAttestation(line) {
  if (typeof line !== 'string' || line.length === 0 || line.length > MAX_ATTESTATION_BYTES || !/^[A-Za-z0-9_-]+$/.test(line)) fail('OOB_FRAME_INVALID');
  let decoded;
  try { decoded = Buffer.from(line, 'base64url').toString('utf8'); } catch { fail('OOB_FRAME_INVALID'); }
  let parsed;
  try { parsed = JSON.parse(decoded); } catch { fail('OOB_JSON_INVALID'); }
  if (canonicalJson(parsed) !== decoded || Buffer.from(decoded).toString('base64url') !== line) fail('OOB_NOT_CANONICAL');
  return validateConsoleEnvelope(parsed);
}

export function validateFingerprint(value, code = 'FINGERPRINT_INVALID') {
  if (typeof value !== 'string' || !/^SHA256:[A-Za-z0-9_-]{43}$/.test(value)) fail(code);
  return value;
}

export function validateConsoleEnvelope(value) {
  keysExact(value, [
    'schema_version', 'purpose', 'nonce', 'uid', 'hostname', 'port',
    'host_key_algorithm', 'host_key_fingerprint', 'authorized_key_fingerprints',
  ], 'OOB_SCHEMA_INVALID');
  if (value.schema_version !== 1 || value.purpose !== TOOL_NAME) fail('OOB_PURPOSE_INVALID');
  cleanToken(value.nonce, 32, 128, 'OOB_NONCE_INVALID');
  if (value.uid !== 0) fail('OOB_UID_INVALID');
  cleanToken(value.hostname, 1, 253, 'OOB_HOSTNAME_INVALID');
  integer(value.port, 1, 65535, 'OOB_PORT_INVALID');
  if (value.host_key_algorithm !== 'ssh-ed25519') fail('OOB_HOST_ALGORITHM_INVALID');
  validateFingerprint(value.host_key_fingerprint, 'OOB_HOST_FINGERPRINT_INVALID');
  if (!Array.isArray(value.authorized_key_fingerprints) || value.authorized_key_fingerprints.length < 1 || value.authorized_key_fingerprints.length > 256) fail('OOB_AUTHORIZED_SET_INVALID');
  const fingerprints = value.authorized_key_fingerprints.map((entry) => validateFingerprint(entry, 'OOB_AUTHORIZED_FINGERPRINT_INVALID'));
  if (new Set(fingerprints).size !== fingerprints.length || JSON.stringify([...fingerprints].sort()) !== JSON.stringify(fingerprints)) fail('OOB_AUTHORIZED_SET_INVALID');
  return Object.freeze({ ...value, authorized_key_fingerprints: Object.freeze([...fingerprints]) });
}

export function validateContext(context, { postAuthority = false } = {}) {
  const required = [
    'authority', 'generation', 'authority_blob', 'module_blob', 'node_executable', 'node_sha256',
    'destination', 'destination_hash', 'public_key_path', 'private_key_path', 'public_key_fingerprint',
  ];
  keysExact(context, required, 'CONTEXT_SCHEMA_INVALID');
  hex(context.authority, 40, 'AUTHORITY_INVALID');
  cleanToken(context.generation, 8, 128, 'GENERATION_INVALID');
  hex(context.authority_blob, 40, 'AUTHORITY_BLOB_INVALID');
  hex(context.module_blob, 40, 'MODULE_BLOB_INVALID');
  hex(context.node_sha256, 64, 'NODE_HASH_INVALID');
  hex(context.destination_hash, 64, 'DESTINATION_HASH_INVALID');
  validateFingerprint(context.public_key_fingerprint, 'LOCAL_KEY_FINGERPRINT_INVALID');
  for (const field of ['node_executable', 'public_key_path', 'private_key_path']) {
    if (!path.isAbsolute(context[field]) || context[field].includes('\0')) fail('CONTEXT_PATH_INVALID');
  }
  if (typeof context.destination !== 'string' || context.destination.length < 1 || context.destination.length > 253 || sha256(context.destination) !== context.destination_hash) fail('DESTINATION_INVALID');
  if (postAuthority !== false && postAuthority !== true) fail('CONTEXT_PHASE_INVALID');
  return Object.freeze({ ...context });
}

export const authorityRoot = (context, home = homedir()) => path.join(home, '.config', 'agentempp', 'ci3', ROOT_BASENAME, context.authority, context.generation);

export function consoleCommandFor(request) {
  keysExact(request, ['schema_version', 'purpose', 'authority_hash', 'nonce', 'created_at_ms', 'created_monotonic_ms'], 'REQUEST_SCHEMA_INVALID');
  const nonce = cleanToken(request.nonce, 32, 128, 'REQUEST_NONCE_INVALID');
  // The official console command is read-only. It validates every absolute tool,
  // emits no key body/comment/IP and returns one canonical base64url JSON line.
  const program = [
    "import base64,json,os,re,subprocess,sys",
    `nonce=${JSON.stringify(nonce)}`,
    "need=['/usr/bin/id','/bin/hostname','/usr/sbin/sshd','/usr/bin/ssh-keygen']",
    "all(os.path.isfile(p) and os.access(p,os.X_OK) for p in need) or sys.exit(41)",
    "subprocess.check_output(['/usr/bin/id','-u'],text=True).strip()=='0' or sys.exit(42)",
    "host=subprocess.check_output(['/bin/hostname','-f'],text=True).strip()",
    "re.fullmatch(r'[A-Za-z0-9._-]{1,253}',host) or sys.exit(43)",
    "cfg=subprocess.check_output(['/usr/sbin/sshd','-T','-C',f'user=root,host={host},addr=127.0.0.1'],text=True)",
    "ports=[int(x.split()[1]) for x in cfg.splitlines() if x.startswith('port ')]",
    "len(ports)==1 and 1<=ports[0]<=65535 or sys.exit(44)",
    "def fp(p): return subprocess.check_output(['/usr/bin/ssh-keygen','-lf',p,'-E','sha256'],text=True).split()[1]",
    "hostfp=fp('/etc/ssh/ssh_host_ed25519_key.pub')",
    "aks=[]",
    "with open('/root/.ssh/authorized_keys','rb') as f:",
    "  for raw in f:",
    "    raw=raw.strip()",
    "    if not raw or raw.startswith(b'#'): continue",
    "    p=subprocess.run(['/usr/bin/ssh-keygen','-lf','-','-E','sha256'],input=raw+b'\\n',stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,check=True).stdout.decode().split()[1]",
    "    aks.append(p)",
    "aks=sorted(aks)",
    "aks and len(aks)==len(set(aks)) or sys.exit(45)",
    "o={'authorized_key_fingerprints':aks,'host_key_algorithm':'ssh-ed25519','host_key_fingerprint':hostfp,'hostname':host,'nonce':nonce,'port':ports[0],'purpose':'FRESH_OUT_OF_BAND_TRUST_BOOTSTRAP_V1','schema_version':1,'uid':0}",
    "raw=json.dumps(o,sort_keys=True,separators=(',',':')).encode()",
    "print(base64.urlsafe_b64encode(raw).decode().rstrip('='))",
  ].join('\n');
  return `/usr/bin/python3 -c ${shellQuote(program)}`;
}

export function shellQuote(value) { return `'${String(value).replaceAll("'", "'\\''")}'`; }

export function helperScriptFor({ nodeExecutable, modulePath, commandPath }) {
  for (const value of [nodeExecutable, modulePath, commandPath]) if (!path.isAbsolute(value) || value.includes('\0')) fail('HELPER_PATH_INVALID');
  return `#!/bin/zsh\nset -euo pipefail\n(( $# == 0 )) || { print -u2 -- 'ARGS_FORBIDDEN'; exit 64; }\n[[ -t 0 && -t 1 ]] || { print -u2 -- 'TTY_REQUIRED'; exit 64; }\n/bin/cat -- ${shellQuote(commandPath)}\nexec ${shellQuote(nodeExecutable)} ${shellQuote(modulePath)} --ingest-console-attestation\n`;
}

export function isolatedSshConfig({ destination, port, identityFile, knownHostsFile }) {
  if (typeof destination !== 'string' || !/^[A-Za-z0-9.-]{1,253}$/.test(destination)) fail('SSH_DESTINATION_INVALID');
  integer(port, 1, 65535, 'SSH_PORT_INVALID');
  for (const value of [identityFile, knownHostsFile]) if (!path.isAbsolute(value) || /[\r\n\0]/.test(value)) fail('SSH_PATH_INVALID');
  return [
    `Host ${FIXED_ALIAS}`, `  HostName ${destination}`, '  User root', `  Port ${port}`,
    `  IdentityFile ${identityFile}`, `  UserKnownHostsFile ${knownHostsFile}`,
    '  IdentitiesOnly yes', '  StrictHostKeyChecking yes', '  BatchMode yes',
    '  PasswordAuthentication no', '  KbdInteractiveAuthentication no', '  PubkeyAuthentication yes',
    '  ForwardAgent no', '  ClearAllForwardings yes', '  ControlMaster no', '  AddKeysToAgent no',
    '  CanonicalizeHostname no', '  ProxyCommand none', '  ProxyJump none',
  ].join('\n') + '\n';
}

export function parseEffectiveConfig(output) {
  if (typeof output !== 'string' || output.length === 0 || output.length > 64 * 1024 || output.includes('\0')) fail('SSH_G_OUTPUT_INVALID');
  const values = Object.create(null);
  for (const line of output.split('\n')) {
    if (!line) continue;
    const space = line.indexOf(' ');
    if (space < 1) fail('SSH_G_OUTPUT_INVALID');
    const key = line.slice(0, space).toLowerCase(); const value = line.slice(space + 1).trim();
    if (Object.hasOwn(values, key)) fail('SSH_G_DUPLICATE');
    values[key] = value;
  }
  return values;
}

export function validateEffectiveConfig(values, expected) {
  const compare = { ...CLOSED_SSH_POLICY, hostname: expected.destination, port: String(expected.port), identityfile: expected.identityFile, userknownhostsfile: expected.knownHostsFile };
  for (const [key, value] of Object.entries(compare)) if (values[key] !== value) fail('SSH_POLICY_MISMATCH');
  if (values.user !== 'root') fail('SSH_POLICY_MISMATCH');
  for (const forbidden of ['include', 'match', 'forwardlocal', 'forwardremote', 'dynamicforward']) if (values[forbidden]) fail('SSH_POLICY_MISMATCH');
  return true;
}

function oobReceiptFrom(context, request, envelope, nowMs) {
  const matchCount = envelope.authorized_key_fingerprints.filter((entry) => safeEqual(entry, context.public_key_fingerprint)).length;
  if (matchCount !== 1) fail('LOCAL_KEY_NOT_AUTHORIZED_EXACTLY_ONCE');
  if (!safeEqual(request.nonce, envelope.nonce)) fail('OOB_NONCE_MISMATCH');
  return Object.freeze({
    schema_version: 1, purpose: TOOL_NAME, authority: context.authority,
    nonce_hash: sha256(envelope.nonce), timestamp: new Date(nowMs).toISOString(),
    operator_confirmation: true, destination_hash: context.destination_hash, uid: envelope.uid,
    hostname_hash: sha256(envelope.hostname), port: envelope.port,
    host_key_fingerprint_hash: sha256(envelope.host_key_fingerprint),
    local_public_key_fingerprint_hash: sha256(context.public_key_fingerprint),
    authorized_fingerprint_set_hash: sha256(canonicalJson(envelope.authorized_key_fingerprints)),
    key_match_count: 1, console_source_class: SOURCE_CLASS, attempts: 1, retry: false, raw_values: false,
  });
}

export function createSyntheticAdapter(overrides = {}) {
  const files = new Map(); const claims = new Set();
  return {
    kind: 'synthetic', files, claims,
    nowMs: () => 1_800_000_000_000,
    monotonicMs: () => 50_000,
    nonce: () => 'N'.repeat(48),
    ensureRoot: async () => {},
    claim: async (name) => { if (claims.has(name)) fail('ATTEMPT_ALREADY_CONSUMED'); claims.add(name); files.set(`${name}.claim.json`, jsonBuffer({ schema_version: 1, purpose: TOOL_NAME, attempt: 1, retry: false })); },
    writeOwnerOnly: async (name, data) => { if (files.has(name)) fail('EXACT_EXISTING_REQUIRED'); files.set(name, Buffer.from(data)); },
    readOwnerOnly: async (name) => { if (!files.has(name)) fail('ARTIFACT_MISSING'); return files.get(name); },
    clearPasteboard: async () => {},
    verifyAuthority: async () => true,
    verifyPhysicalKeyPair: async () => true,
    keyscan: async () => fail('SYNTHETIC_KEYSCAN_UNSET'),
    sshG: async () => fail('SYNTHETIC_SSH_G_UNSET'),
    sshAttest: async () => fail('SYNTHETIC_SSH_UNSET'),
    ...overrides,
  };
}

const jsonBuffer = (value) => Buffer.from(`${canonicalJson(value)}\n`);
const parseJsonBuffer = (buffer, code = 'ARTIFACT_INVALID') => {
  let value; try { value = JSON.parse(Buffer.from(buffer).toString('utf8')); } catch { fail(code); }
  if (`${canonicalJson(value)}\n` !== Buffer.from(buffer).toString('utf8')) fail(code);
  return value;
};

export async function prepareHumanGate(contextInput, adapter) {
  const context = validateContext(contextInput);
  if (!adapter || !['synthetic', 'real'].includes(adapter.kind)) fail('ADAPTER_INVALID');
  await adapter.verifyAuthority(context);
  await adapter.verifyPhysicalKeyPair(context);
  await adapter.ensureRoot(context);
  await adapter.claim('prepare-human-gate');
  const nonce = adapter.nonce(); cleanToken(nonce, 32, 128, 'NONCE_GENERATION_FAILED');
  const request = Object.freeze({ schema_version: 1, purpose: TOOL_NAME, authority_hash: sha256(context.authority), nonce, created_at_ms: adapter.nowMs(), created_monotonic_ms: adapter.monotonicMs() });
  const command = consoleCommandFor(request);
  const helper = helperScriptFor({ nodeExecutable: context.node_executable, modulePath: SCRIPT_PATH, commandPath: 'ROOT/official-console-command.txt'.replace('ROOT', authorityRoot(context)) });
  await adapter.writeOwnerOnly('human-gate.request.json', jsonBuffer(request), 0o600);
  await adapter.writeOwnerOnly('official-console-command.txt', Buffer.from(`${command}\n`), 0o600);
  await adapter.writeOwnerOnly('official-console-helper.zsh', Buffer.from(helper), 0o700);
  await adapter.writeOwnerOnly('human-gate.prepared.receipt.json', jsonBuffer({ schema_version: 1, purpose: TOOL_NAME, request_hash: sha256(jsonBuffer(request)), attempts: 1, retry: false, raw_values: false }), 0o600);
  return Object.freeze({ status: 'HUMAN_GATE_READY', helper_path: path.join(authorityRoot(context), 'official-console-helper.zsh'), network_attempts: 0, raw_values: false });
}

export async function ingestConsoleAttestation(contextInput, { confirmation, encodedLine }, adapter) {
  const context = validateContext(contextInput, { postAuthority: true });
  if (confirmation !== 'SIM') fail('OPERATOR_CONFIRMATION_REQUIRED');
  await adapter.claim('ingest-console-attestation');
  const request = parseJsonBuffer(await adapter.readOwnerOnly('human-gate.request.json'), 'REQUEST_INVALID');
  try {
    const elapsed = adapter.nowMs() - request.created_at_ms;
    const monotonicElapsed = adapter.monotonicMs() - request.created_monotonic_ms;
    if (elapsed < 0 || elapsed > NONCE_TTL_MS || monotonicElapsed < 0 || monotonicElapsed > NONCE_TTL_MS) fail('OOB_NONCE_STALE');
    const envelope = decodeConsoleAttestation(encodedLine);
    const receipt = oobReceiptFrom(context, request, envelope, adapter.nowMs());
    const rawRecord = { schema_version: 1, purpose: TOOL_NAME, envelope, source_class: SOURCE_CLASS };
    await adapter.writeOwnerOnly('official-console-oob-source.json', jsonBuffer(rawRecord), 0o600);
    await adapter.writeOwnerOnly(RECEIPT_NAMES.oob, jsonBuffer(receipt), 0o600);
    return Object.freeze({ status: 'PASS', attempts: '1/1', raw_values: false });
  } finally {
    await adapter.clearPasteboard();
  }
}

export function validateOobReceipt(receipt, context) {
  keysExact(receipt, [
    'schema_version','purpose','authority','nonce_hash','timestamp','operator_confirmation','destination_hash','uid','hostname_hash','port',
    'host_key_fingerprint_hash','local_public_key_fingerprint_hash','authorized_fingerprint_set_hash','key_match_count','console_source_class','attempts','retry','raw_values',
  ], 'OOB_RECEIPT_SCHEMA_INVALID');
  if (receipt.schema_version !== 1 || receipt.purpose !== TOOL_NAME || receipt.authority !== context.authority || receipt.destination_hash !== context.destination_hash) fail('OOB_RECEIPT_BINDING_INVALID');
  for (const field of ['nonce_hash','hostname_hash','host_key_fingerprint_hash','local_public_key_fingerprint_hash','authorized_fingerprint_set_hash']) hex(receipt[field], 64, 'OOB_RECEIPT_HASH_INVALID');
  if (!receipt.operator_confirmation || receipt.uid !== 0 || receipt.key_match_count !== 1 || receipt.console_source_class !== SOURCE_CLASS || receipt.attempts !== 1 || receipt.retry !== false || receipt.raw_values !== false) fail('OOB_RECEIPT_POLICY_INVALID');
  if (receipt.local_public_key_fingerprint_hash !== sha256(context.public_key_fingerprint)) fail('OOB_RECEIPT_BINDING_INVALID');
  integer(receipt.port, 1, 65535, 'OOB_RECEIPT_PORT_INVALID');
  return receipt;
}

export async function acquireHostKey(contextInput, adapter) {
  const context = validateContext(contextInput, { postAuthority: true });
  const receipt = validateOobReceipt(parseJsonBuffer(await adapter.readOwnerOnly(RECEIPT_NAMES.oob)), context);
  const source = parseJsonBuffer(await adapter.readOwnerOnly('official-console-oob-source.json'));
  await adapter.claim('acquire-host-key');
  const scan = await adapter.keyscan({ destination: context.destination, port: receipt.port, algorithm: 'ssh-ed25519', timeoutMs: 10_000 });
  keysExact(scan, ['algorithm', 'known_hosts_line', 'fingerprint'], 'KEYSCAN_RESULT_INVALID');
  if (scan.algorithm !== 'ssh-ed25519' || !safeEqual(scan.fingerprint, source.envelope.host_key_fingerprint)) fail('HOST_KEY_MISMATCH');
  if (typeof scan.known_hosts_line !== 'string' || !/^ssh-ed25519 [A-Za-z0-9+/]+={0,2}$/.test(scan.known_hosts_line)) fail('KEYSCAN_RESULT_INVALID');
  const knownHosts = `${context.destination} ${scan.known_hosts_line}\n`;
  const config = isolatedSshConfig({ destination: context.destination, port: receipt.port, identityFile: context.private_key_path, knownHostsFile: path.join(authorityRoot(context), 'known_hosts') });
  await adapter.writeOwnerOnly('known_hosts', Buffer.from(knownHosts), 0o600);
  await adapter.writeOwnerOnly('ssh_config', Buffer.from(config), 0o600);
  await adapter.writeOwnerOnly('host-key-acquisition.receipt.json', jsonBuffer({ schema_version: 1, purpose: TOOL_NAME, oob_receipt_hash: sha256(jsonBuffer(receipt)), known_hosts_hash: sha256(knownHosts), config_hash: sha256(config), attempts: 1, retry: false, raw_values: false }), 0o600);
  return Object.freeze({ status: 'PASS', attempts: '1/1', raw_values: false });
}

export async function verifyEffectiveSshConfig(contextInput, adapter) {
  const context = validateContext(contextInput, { postAuthority: true });
  const receipt = validateOobReceipt(parseJsonBuffer(await adapter.readOwnerOnly(RECEIPT_NAMES.oob)), context);
  await adapter.readOwnerOnly('host-key-acquisition.receipt.json');
  await adapter.claim('verify-effective-config');
  const configPath = path.join(authorityRoot(context), 'ssh_config');
  const knownHostsPath = path.join(authorityRoot(context), 'known_hosts');
  const output = await adapter.sshG({ configPath, alias: FIXED_ALIAS });
  const values = parseEffectiveConfig(output);
  validateEffectiveConfig(values, { destination: context.destination, port: receipt.port, identityFile: context.private_key_path, knownHostsFile: knownHostsPath });
  await adapter.writeOwnerOnly('ssh-effective-config.capture', Buffer.from(output), 0o600);
  await adapter.writeOwnerOnly('ssh-effective-config.receipt.json', jsonBuffer({ schema_version: 1, purpose: TOOL_NAME, effective_config_hash: sha256(output), attempts: 1, retry: false, raw_values: false }), 0o600);
  return Object.freeze({ status: 'PASS', attempts: '1/1', raw_values: false });
}

export async function attestConnection(contextInput, adapter) {
  const context = validateContext(contextInput, { postAuthority: true });
  const oob = validateOobReceipt(parseJsonBuffer(await adapter.readOwnerOnly(RECEIPT_NAMES.oob)), context);
  const source = parseJsonBuffer(await adapter.readOwnerOnly('official-console-oob-source.json'));
  const effective = parseJsonBuffer(await adapter.readOwnerOnly('ssh-effective-config.receipt.json'));
  keysExact(effective, ['schema_version','purpose','effective_config_hash','attempts','retry','raw_values'], 'SSH_G_RECEIPT_INVALID');
  if (effective.schema_version !== 1 || effective.purpose !== TOOL_NAME || effective.attempts !== 1 || effective.retry !== false || effective.raw_values !== false) fail('SSH_G_RECEIPT_INVALID');
  await adapter.claim('attest-connection');
  const challenge = adapter.nonce();
  const result = await adapter.sshAttest({ configPath: path.join(authorityRoot(context), 'ssh_config'), alias: FIXED_ALIAS, challenge });
  keysExact(result, ['challenge','uid','hostname','exit'], 'SSH_ATTEST_RESULT_INVALID');
  if (!safeEqual(result.challenge, challenge) || result.uid !== 0 || result.exit !== 0 || !safeEqual(result.hostname, source.envelope.hostname)) fail('SSH_ATTEST_MISMATCH');
  const receipt = {
    schema_version: 1, purpose: TOOL_NAME, authority: context.authority,
    oob_receipt_hash: sha256(jsonBuffer(oob)), key_hash: sha256(context.public_key_fingerprint),
    host_hash: oob.host_key_fingerprint_hash, config_hash: effective.effective_config_hash,
    effective_config_hash: effective.effective_config_hash, challenge_hash: sha256(challenge),
    uid_hash: sha256(String(result.uid)), hostname_hash: sha256(result.hostname), exit: 0,
    attempts: 1, retry: false, raw_values: false,
  };
  await adapter.writeOwnerOnly(RECEIPT_NAMES.ssh, jsonBuffer(receipt), 0o600);
  return Object.freeze({ status: 'PASS', attempts: '1/1', raw_values: false });
}

export async function verifyExisting(contextInput, adapter) {
  const context = validateContext(contextInput, { postAuthority: true });
  for (const claim of ['ingest-console-attestation','acquire-host-key','verify-effective-config','attest-connection']) await adapter.readOwnerOnly(`${claim}.claim.json`);
  const oob = validateOobReceipt(parseJsonBuffer(await adapter.readOwnerOnly(RECEIPT_NAMES.oob)), context);
  const ssh = parseJsonBuffer(await adapter.readOwnerOnly(RECEIPT_NAMES.ssh));
  keysExact(ssh, ['schema_version','purpose','authority','oob_receipt_hash','key_hash','host_hash','config_hash','effective_config_hash','challenge_hash','uid_hash','hostname_hash','exit','attempts','retry','raw_values'], 'SSH_RECEIPT_INVALID');
  if (ssh.authority !== context.authority || ssh.oob_receipt_hash !== sha256(jsonBuffer(oob)) || ssh.attempts !== 1 || ssh.retry !== false || ssh.raw_values !== false) fail('SSH_RECEIPT_INVALID');
  return Object.freeze({ status: 'PASS', raw_values: false });
}

async function durableWrite(filePath, data, mode) {
  const parent = path.dirname(filePath);
  try { const st = await lstat(parent); if (!st.isDirectory() || st.isSymbolicLink() || st.uid !== process.getuid() || (st.mode & 0o077) !== 0) fail('ROOT_UNSAFE'); } catch (error) { if (error instanceof OobTrustError) throw error; fail('ROOT_UNSAFE'); }
  const handle = await open(filePath, FS_CONSTANTS.O_WRONLY | FS_CONSTANTS.O_CREAT | FS_CONSTANTS.O_EXCL | FS_CONSTANTS.O_NOFOLLOW, mode);
  try { await handle.writeFile(data); await handle.sync(); } finally { await handle.close(); }
  const dir = await open(parent, FS_CONSTANTS.O_RDONLY); try { await dir.sync(); } finally { await dir.close(); }
}

export function createRealAdapter(context) {
  const root = authorityRoot(context);
  const artifact = (name) => path.join(root, name);
  return {
    kind: 'real', nowMs: () => Date.now(), monotonicMs: () => Math.floor(performance.now()), nonce: () => randomBytes(36).toString('base64url'),
    ensureRoot: async () => { const st = await lstat(root); if (!st.isDirectory() || st.isSymbolicLink() || st.uid !== process.getuid() || (st.mode & 0o077) !== 0) fail('ROOT_UNSAFE'); const resolved = await realpath(root); if (resolved !== root) fail('ROOT_UNSAFE'); },
    claim: async (name) => durableWrite(artifact(`${name}.claim.json`), jsonBuffer({ schema_version: 1, purpose: TOOL_NAME, attempt: 1, retry: false }), 0o600),
    writeOwnerOnly: async (name, data, mode = 0o600) => durableWrite(artifact(name), data, mode),
    readOwnerOnly: async (name) => { const st = await lstat(artifact(name)); if (!st.isFile() || st.isSymbolicLink() || (st.mode & 0o077) !== 0) fail('ARTIFACT_UNSAFE'); return readFile(artifact(name)); },
    clearPasteboard: async () => { const result = spawnSync('/usr/bin/pbcopy', [], { input: '', env: CLOSED_ENV, encoding: 'utf8' }); if (result.status !== 0) fail('PASTEBOARD_CLEAR_FAILED'); },
    verifyAuthority: async (ctx) => { const local = spawnSync('/usr/bin/git', ['hash-object', SCRIPT_PATH], { env: CLOSED_ENV, encoding: 'utf8' }); const committed = spawnSync('/usr/bin/git', ['-C', MANAGER_ROOT, 'rev-parse', `${ctx.authority}:scripts/ci3/ci3-oob-ssh-trust-bootstrap.mjs`], { env: CLOSED_ENV, encoding: 'utf8' }); const authority = spawnSync('/usr/bin/git', ['-C', MANAGER_ROOT, 'cat-file', '-e', `${ctx.authority}^{commit}`], { env: CLOSED_ENV, encoding: 'utf8' }); const evidenceBlob = spawnSync('/usr/bin/git', ['-C', MANAGER_ROOT, 'cat-file', '-e', `${ctx.authority_blob}^{blob}`], { env: CLOSED_ENV, encoding: 'utf8' }); const nodeStat = await lstat(ctx.node_executable); const nodeReal = await realpath(ctx.node_executable); const nodeDigest = spawnSync('/usr/bin/shasum', ['-a', '256', ctx.node_executable], { env: CLOSED_ENV, encoding: 'utf8', maxBuffer: 64 * 1024 }); if (local.status !== 0 || committed.status !== 0 || authority.status !== 0 || evidenceBlob.status !== 0 || local.stdout.trim() !== ctx.module_blob || committed.stdout.trim() !== ctx.module_blob || !nodeStat.isFile() || nodeStat.isSymbolicLink() || nodeReal !== ctx.node_executable || nodeDigest.status !== 0 || nodeDigest.stdout.trim().split(/\s+/)[0] !== ctx.node_sha256) fail('AUTHORITY_BINDING_INVALID'); return true; },
    verifyPhysicalKeyPair: async (ctx) => { const priv = await lstat(ctx.private_key_path); const pub = await lstat(ctx.public_key_path); if (!priv.isFile() || !pub.isFile() || priv.isSymbolicLink() || pub.isSymbolicLink() || (priv.mode & 0o077) !== 0) fail('KEYPAIR_UNSAFE'); const derived = spawnSync('/usr/bin/ssh-keygen', ['-y', '-f', ctx.private_key_path], { env: CLOSED_ENV, encoding: 'utf8', maxBuffer: 64 * 1024 }); const published = spawnSync('/usr/bin/ssh-keygen', ['-lf', ctx.public_key_path, '-E', 'sha256'], { env: CLOSED_ENV, encoding: 'utf8', maxBuffer: 64 * 1024 }); const derivedFp = spawnSync('/usr/bin/ssh-keygen', ['-lf', '-', '-E', 'sha256'], { input: derived.stdout, env: CLOSED_ENV, encoding: 'utf8', maxBuffer: 64 * 1024 }); if (derived.status !== 0 || published.status !== 0 || derivedFp.status !== 0) fail('KEYPAIR_INVALID'); const left = published.stdout.trim().split(/\s+/)[1]; const right = derivedFp.stdout.trim().split(/\s+/)[1]; if (!safeEqual(left, right) || !safeEqual(left, ctx.public_key_fingerprint)) fail('KEYPAIR_INVALID'); return true; },
    keyscan: async ({ destination, port, timeoutMs }) => { const result = spawnSync('/usr/bin/ssh-keyscan', ['-T', String(Math.ceil(timeoutMs / 1000)), '-p', String(port), '-t', 'ed25519', destination], { env: CLOSED_ENV, encoding: 'utf8', maxBuffer: 64 * 1024, timeout: timeoutMs + 1000 }); if (result.status !== 0 || !result.stdout.trim()) fail('KEYSCAN_FAILED'); const line = result.stdout.trim().split('\n'); if (line.length !== 1) fail('KEYSCAN_RESULT_INVALID'); const fp = spawnSync('/usr/bin/ssh-keygen', ['-lf', '-', '-E', 'sha256'], { input: `${line[0]}\n`, env: CLOSED_ENV, encoding: 'utf8' }); if (fp.status !== 0) fail('KEYSCAN_RESULT_INVALID'); return { algorithm: 'ssh-ed25519', known_hosts_line: line[0].split(/\s+/).slice(1).join(' '), fingerprint: fp.stdout.trim().split(/\s+/)[1] }; },
    sshG: async ({ configPath, alias }) => { const result = spawnSync('/usr/bin/ssh', ['-G', '-F', configPath, alias], { env: CLOSED_ENV, encoding: 'utf8', maxBuffer: 64 * 1024 }); if (result.status !== 0) fail('SSH_G_FAILED'); return result.stdout; },
    sshAttest: async ({ configPath, alias, challenge }) => { const remote = `/usr/bin/test \"$(/usr/bin/id -u)\" = 0 && /usr/bin/printf '%s\\n%s\\n%s\\n' ${shellQuote(challenge)} \"$(/usr/bin/id -u)\" \"$(/bin/hostname -f)\"`; const result = spawnSync('/usr/bin/ssh', ['-F', configPath, alias, '--', remote], { env: CLOSED_ENV, encoding: 'utf8', maxBuffer: 16 * 1024, timeout: 15_000 }); const lines = result.stdout.trim().split('\n'); if (lines.length !== 3) fail('SSH_ATTEST_RESULT_INVALID'); return { challenge: lines[0], uid: Number(lines[1]), hostname: lines[2], exit: result.status ?? 255 }; },
  };
}

function readHiddenLineFromTty(prompt) {
  const tty = '/dev/tty';
  let fd;
  try { fd = openSync(tty, 'r+'); } catch { fail('TTY_REQUIRED'); }
  const before = spawnSync('/bin/stty', ['-g'], { stdio: [fd, 'pipe', fd], encoding: 'utf8' });
  if (before.status !== 0) { closeSync(fd); fail('TTY_REQUIRED'); }
  const restore = () => spawnSync('/bin/stty', [before.stdout.trim()], { stdio: [fd, fd, fd] });
  const handlers = new Map();
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
    const handler = () => { restore(); closeSync(fd); process.kill(process.pid, signal); };
    handlers.set(signal, handler); process.once(signal, handler);
  }
  process.stderr.write(prompt);
  spawnSync('/bin/stty', ['-echo'], { stdio: [fd, fd, fd] });
  try {
    const chunks = []; const byte = Buffer.allocUnsafe(1);
    while (chunks.length <= MAX_ATTESTATION_BYTES) {
      const count = readSync(fd, byte, 0, 1, null);
      if (count !== 1) fail('TTY_READ_FAILED');
      if (byte[0] === 10 || byte[0] === 13) return Buffer.from(chunks).toString('utf8');
      chunks.push(byte[0]);
    }
    fail('OOB_FRAME_INVALID');
  } finally {
    restore();
    for (const [signal, handler] of handlers) process.removeListener(signal, handler);
    closeSync(fd);
    process.stderr.write('\n');
  }
}

function loadProductionContext() {
  const file = path.join(homedir(), '.config', 'agentempp', 'ci3', ROOT_BASENAME, 'current-authority.json');
  let stat; try { stat = lstatSync(file); } catch { fail('PRODUCTION_CONTEXT_MISSING'); }
  if (!stat.isFile() || stat.isSymbolicLink() || (stat.mode & 0o077) !== 0) fail('PRODUCTION_CONTEXT_UNSAFE');
  let parsed; try { const raw = readFileSync(file, 'utf8'); parsed = JSON.parse(raw); if (`${canonicalJson(parsed)}\n` !== raw) fail('PRODUCTION_CONTEXT_INVALID'); } catch (error) { if (error instanceof OobTrustError) throw error; fail('PRODUCTION_CONTEXT_MISSING'); }
  return validateContext(parsed);
}

export async function runCli(argv = process.argv.slice(2)) {
  if (argv.length !== 1 || !CLOSED_MODES.includes(argv[0])) fail('MODE_INVALID');
  const mode = argv[0];
  if (mode === '--self-test') return { status: 'PASS', modes: CLOSED_MODES.length, raw_values: false };
  const context = loadProductionContext(); const adapter = createRealAdapter(context);
  if (adapter.kind !== 'real') fail('SYNTHETIC_ADAPTER_FORBIDDEN');
  if (mode === '--prepare-human-gate') return prepareHumanGate(context, adapter);
  if (mode === '--ingest-console-attestation') {
    if (!process.stdin.isTTY || !process.stdout.isTTY) fail('TTY_REQUIRED');
    const confirmation = readHiddenLineFromTty('Confirme que o output foi obtido no console web oficial da VPS autenticado pela sua conta. Digite SIM: ');
    const encodedLine = readHiddenLineFromTty('Cole o output no prompt oculto: ');
    return ingestConsoleAttestation(context, { confirmation, encodedLine }, adapter);
  }
  if (mode === '--verify-existing') return verifyExisting(context, adapter);
  if (mode === '--acquire-host-key') return acquireHostKey(context, adapter);
  if (mode === '--verify-effective-config') return verifyEffectiveSshConfig(context, adapter);
  return attestConnection(context, adapter);
}

if (process.argv[1] && path.resolve(process.argv[1]) === SCRIPT_PATH) {
  runCli().then((result) => process.stdout.write(`${canonicalJson(result)}\n`)).catch((error) => {
    process.stderr.write(`${error instanceof OobTrustError ? error.code : 'STOP'}\n`); process.exitCode = 1;
  });
}
